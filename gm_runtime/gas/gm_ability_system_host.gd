class_name GMAbilitySystemHost
extends RefCounted

## 统一能力宿主：授予、检查、生命周期、任务、事件、并发和调度都从这里进入。

signal gameplay_event(event: GMGameplayEvent)
signal activation_finished(result: Dictionary)
signal activation_queued(result: Dictionary)

const ACTIVATION_PATH := "GMAbilityActivationRequest -> GMAbilitySystemHost -> GMAbilityInstance -> GMAbilityDefinition -> DomainExecutor"
const DUPLICATE_SPEC_STRATEGY := GMAbilitySpec.DUPLICATE_STRATEGY
const DEFAULT_EVENT_DEPTH_LIMIT := 16
const DEFAULT_QUEUE_LIMIT := 32
const DEFAULT_IDEMPOTENCY_LEDGER_LIMIT := 256
const EVENT_TRIGGER_RUNTIME_SCRIPT := preload("res://gm_runtime/events/gm_event_trigger_runtime.gd")

static var mounted_entities: Dictionary = {}

var entity: Object
var runtime_context: Object
var tags: GMGameplayTagContainer
var tag_container: GMGameplayTagContainer
var attribute_set: GMAttributeSet
var registry: GMGameplayTagRegistry
var scheduler: GMAbilityScheduler
var definitions: Dictionary = {}
var specs: Dictionary = {}
var domain_services: Dictionary = {}
var active_instances: Array[GMAbilityInstance] = []
var instances_by_id: Dictionary = {}
var queued_requests: Array[Dictionary] = []
var queue_sequence: int = 0
var active_effects: Array[GMActiveEffect] = []
var effect_definitions: Dictionary = {}
var effect_runtime: GMEffectRuntime
var cue_router: GMCueRouter
var gameplay_events: Array[Dictionary] = []
var event_activation_log: Array[Dictionary] = []
var cue_events: Array[Dictionary] = []
var activation_log: Array[Dictionary] = []
var last_failure: Dictionary = {}
var mounted: bool = false
var event_dispatch_depth: int = 0
var max_event_dispatch_depth: int = DEFAULT_EVENT_DEPTH_LIMIT
var max_queue_size: int = DEFAULT_QUEUE_LIMIT
## Bounded, Host-lifetime ledger for exact explicit idempotency keys. Entries are
## never evicted implicitly: capacity exhaustion fails closed until the caller
## performs an explicit quiescent clear or ends the Host lifecycle.
var idempotency_ledger: Dictionary = {}
## Typed terminal values are kept beside the serialized v2 identity ledger so
## exact committed replays preserve the 05A public result contract.
var typed_terminal_results_by_key: Dictionary = {}
var idempotency_epoch: int = 1
var identity_allocation_sequence: int = 0
var assigned_instance_ids_by_request: Dictionary = {}
var max_idempotency_entries: int = DEFAULT_IDEMPOTENCY_LEDGER_LIMIT
var fact_event_store: GMFactEventStore
var change_record_store: GMChangeRecordStore
var transaction_coordinator: GMDomainTransactionCoordinator
var causal_chains: Dictionary = {}
var resolution_results: Array[Dictionary] = []
var inventory_resolver: Object
var inventory_commit_records: Dictionary = {}
var ability_commit_plans: Dictionary = {}
var same_frame_claims: Dictionary = {}
var event_trigger_runtime: GMEventTriggerRuntime

func _init() -> void:
	registry = GMGameplayTagRegistry.create_default()
	tags = GMGameplayTagContainer.new(registry)
	tag_container = tags
	attribute_set = GMAttributeSet.new()
	scheduler = GMRealtimeAbilityScheduler.new()
	cue_router = GMCueRouter.new()
	effect_runtime = GMEffectRuntime.new(self)
	change_record_store = GMChangeRecordStore.new()
	fact_event_store = GMFactEventStore.new(change_record_store)
	transaction_coordinator = GMDomainTransactionCoordinator.new()
	event_trigger_runtime = EVENT_TRIGGER_RUNTIME_SCRIPT.new(self)
	tags.gameplay_event.connect(_on_tag_event)

static func attach_to(p_entity: Object, p_runtime_context: Object) -> Dictionary:
	var host := GMAbilitySystemHost.new()
	var result := host.mount(p_entity, p_runtime_context)
	result["host"] = host if result.ok else null
	return result

func mount(p_entity: Object, p_runtime_context: Object) -> Dictionary:
	if p_entity == null or not is_instance_valid(p_entity): return _mount_failure("host.entity_missing", "能力宿主缺少实体上下文：必须提供 Node、Resource 代理或其他 Object。")
	if p_runtime_context == null or not is_instance_valid(p_runtime_context): return _mount_failure("host.context_missing", "能力宿主缺少 GMRuntimeContext：请先提供场景运行时上下文。")
	if mounted: return _mount_failure("host.duplicate_mount", "重复挂载能力宿主：当前宿主已经组合到实体。")
	_cleanup_invalid_mounts()
	var entity_key := _entity_key(p_entity)
	if mounted_entities.has(entity_key): return _mount_failure("host.duplicate_mount", "重复挂载能力宿主：该实体已有 GMAbilitySystemHost。")
	entity = p_entity
	runtime_context = p_runtime_context
	mounted = true
	mounted_entities[entity_key] = self
	return {"ok": true, "entity_id": entity_key, "entity_kind": _entity_kind(p_entity), "host": self}

func unmount() -> Dictionary:
	if not mounted: return {"ok": true, "already_unmounted": true}
	for instance in active_instances.duplicate():
		if instance != null and not instance.is_terminal(): instance.cancel("能力宿主已卸载。")
		if instance != null: _finalize_instance(instance)
	queued_requests.clear()
	idempotency_ledger.clear()
	typed_terminal_results_by_key.clear()
	assigned_instance_ids_by_request.clear()
	idempotency_epoch += 1
	if event_trigger_runtime != null: event_trigger_runtime.detach()
	var entity_key := _entity_key(entity)
	if mounted_entities.get(entity_key, null) == self: mounted_entities.erase(entity_key)
	mounted = false
	entity = null
	runtime_context = null
	return {"ok": true, "unmounted": true}

## Releases the complete Host lifetime graph after unmount. Normal remounting
## continues to use unmount(); terminal owners call dispose() so RefCounted
## service/signals cannot retain an exported process at shutdown.
func dispose() -> Dictionary:
	var result := unmount()
	if tags != null and tags.gameplay_event.is_connected(_on_tag_event):
		tags.gameplay_event.disconnect(_on_tag_event)
	definitions.clear()
	specs.clear()
	domain_services.clear()
	active_instances.clear()
	instances_by_id.clear()
	queued_requests.clear()
	active_effects.clear()
	effect_definitions.clear()
	gameplay_events.clear()
	event_activation_log.clear()
	cue_events.clear()
	activation_log.clear()
	last_failure.clear()
	idempotency_ledger.clear()
	typed_terminal_results_by_key.clear()
	assigned_instance_ids_by_request.clear()
	causal_chains.clear()
	resolution_results.clear()
	inventory_commit_records.clear()
	ability_commit_plans.clear()
	same_frame_claims.clear()
	event_trigger_runtime = null
	effect_runtime = null
	cue_router = null
	fact_event_store = null
	change_record_store = null
	transaction_coordinator = null
	inventory_resolver = null
	tags = null
	tag_container = null
	attribute_set = null
	registry = null
	scheduler = null
	result["disposed"] = true
	return result

func set_scheduler(p_scheduler: GMAbilityScheduler) -> Dictionary:
	if p_scheduler == null or not is_instance_valid(p_scheduler): return {"ok": false, "code": "scheduler.invalid", "reason_zh": "不能安装空能力调度器。"}
	scheduler = p_scheduler
	return {"ok": true, "scheduler_id": scheduler.scheduler_id, "mode": scheduler.mode}

func configure_fact_pipeline(p_fact_store: GMFactEventStore = null, p_change_store: GMChangeRecordStore = null, p_coordinator: GMDomainTransactionCoordinator = null) -> Dictionary:
	change_record_store = p_change_store if p_change_store != null else GMChangeRecordStore.new()
	fact_event_store = p_fact_store if p_fact_store != null else GMFactEventStore.new(change_record_store)
	if fact_event_store.change_store == null: fact_event_store.change_store = change_record_store
	transaction_coordinator = p_coordinator if p_coordinator != null else GMDomainTransactionCoordinator.new()
	return {"ok": true, "fact_store": fact_event_store.get_record_count(), "change_store": change_record_store.get_record_count()}

func configure_inventory_pipeline(p_resolver: Object) -> Dictionary:
	if p_resolver == null or not is_instance_valid(p_resolver):
		return {"ok": false, "code": "inventory.resolver_invalid", "reason_zh": "任务06库存成本必须安装05C唯一 InventoryResolver。"}
	if not p_resolver.has_method("preflight_transaction") or not p_resolver.has_method("commit_transaction"):
		return {"ok": false, "code": "inventory.resolver_interface_missing", "reason_zh": "库存成本 Resolver 缺少05C事务接口。"}
	inventory_resolver = p_resolver
	return {"ok": true, "resolver_id": str(p_resolver.get("resolver_id")) if "resolver_id" in p_resolver else "gm.resolver.inventory"}

func configure_p19_pipeline(p_resolver: Object) -> Dictionary:
	if p_resolver == null or not is_instance_valid(p_resolver):
		return {"ok": false, "code": "p19.resolver_invalid", "reason_zh": "P19 事务管线不能安装空 Resolver。"}
	for method_name in ["preflight_transaction", "reserve_transaction", "commit_transaction", "rollback_transaction", "capture_transaction_state", "restore_transaction_state", "release_transaction_reservations", "isolate_transaction_state"]:
		if not p_resolver.has_method(method_name):
			return {"ok": false, "code": "p19.resolver_interface_missing", "reason_zh": "P19 Resolver 缺少统一事务恢复接口：%s" % method_name}
	var service_id := str(p_resolver.get("resolver_id")) if "resolver_id" in p_resolver else "gm.resolver.p19"
	if service_id.strip_edges().is_empty(): service_id = "gm.resolver.p19"
	var registered := set_domain_service(service_id, p_resolver)
	if not registered.ok: return registered
	return {"ok": true, "resolver_id": service_id, "fact_store": fact_event_store.get_record_count() if fact_event_store != null else 0, "change_store": change_record_store.get_record_count() if change_record_store != null else 0}

func register_effect_definition(definition: GMEffectDefinition) -> Dictionary:
	return effect_runtime.register_definition(definition) if effect_runtime != null else {"ok": false, "code": "effect.runtime_missing", "reason_zh": "GameplayEffect 运行时未初始化。"}

func apply_effect(definition: GMEffectDefinition, spec: GMEffectSpec = null, owner_instance: Object = null) -> Dictionary:
	return effect_runtime.apply_effect(definition, spec, owner_instance) if effect_runtime != null else {"ok": false, "code": "effect.runtime_missing", "reason_zh": "GameplayEffect 运行时未初始化。"}

func remove_effect(active_effect_id: String, reason_zh: String = "GameplayEffect 被移除。", owner_instance: Object = null) -> Dictionary:
	return effect_runtime.remove_effect(active_effect_id, reason_zh, owner_instance) if effect_runtime != null else {"ok": false, "code": "effect.runtime_missing", "reason_zh": "GameplayEffect 运行时未初始化。"}

func register_cue_definition(definition: GMCueDefinition) -> Dictionary:
	return cue_router.register_definition(definition) if cue_router != null else {"ok": false, "code": "cue.router_missing", "reason_zh": "Cue 路由器未初始化。"}

func validate_required_cues() -> Dictionary:
	return cue_router.validate_required_content() if cue_router != null else {"ok": false, "code": "cue.router_missing", "reason_zh": "Cue 路由器未初始化。"}

func add_host_tag(tag_value: String, source: String = "host") -> Dictionary:
	return tags.add_tag(tag_value, source)

func remove_host_tag(tag_value: String, source: String = "host", amount: int = 1) -> Dictionary:
	return tags.remove_tag(tag_value, source, amount)

func register_tag(tag_value: String, platform_owned: bool = false) -> Dictionary:
	return registry.register(tag_value, [], platform_owned)

func set_domain_service(service_id: String, service: Object) -> Dictionary:
	if service_id.strip_edges().is_empty() or service == null: return {"ok": false, "code": "host.domain_service_invalid", "reason_zh": "领域服务注册失败：服务 ID 或实现为空。"}
	domain_services[service_id] = service
	return {"ok": true, "service_id": service_id}

func register_definition(definition: GMAbilityDefinition) -> Dictionary:
	if definition == null or definition.ability_id.strip_edges().is_empty(): return {"ok": false, "code": "ability.definition_invalid", "reason_zh": "能力定义缺少稳定能力 ID。"}
	if definitions.has(definition.ability_id) and definitions[definition.ability_id] != definition: return {"ok": false, "code": "ability.definition_duplicate", "reason_zh": "能力定义重复注册：%s" % definition.ability_id}
	definitions[definition.ability_id] = definition
	return {"ok": true, "ability_id": definition.ability_id}

func _validate_ability_grant_host() -> Dictionary:
	if not mounted:
		return {"ok": false, "code": "ability.host_unmounted", "reason_zh": "能力授予宿主尚未挂载到实体。"}
	if entity == null or not is_instance_valid(entity):
		return {"ok": false, "code": "ability.host_entity_invalid", "reason_zh": "能力授予宿主的实体上下文无效。"}
	if runtime_context == null or not is_instance_valid(runtime_context):
		return {"ok": false, "code": "ability.host_context_invalid", "reason_zh": "能力授予宿主的运行时上下文无效。"}
	return {"ok": true}

func preflight_ability_grant(definition: GMAbilityDefinition, source: String, level: int = 1, overrides: Dictionary = {}) -> Dictionary:
	var host_check := _validate_ability_grant_host()
	if not host_check.ok: return host_check
	if definition == null or definition.ability_id.strip_edges().is_empty():
		return {"ok": false, "code": "ability.definition_invalid", "reason_zh": "能力定义缺少稳定能力 ID。"}
	if source.strip_edges().is_empty():
		return {"ok": false, "code": "ability.source_missing", "reason_zh": "授予能力缺少来源：%s" % definition.ability_id}
	var ability_id := definition.ability_id
	if definitions.has(ability_id) and definitions[ability_id] != definition:
		return {"ok": false, "code": "ability.definition_duplicate", "reason_zh": "能力定义重复注册：%s" % ability_id}
	var existing_spec: GMAbilitySpec = specs.get(ability_id, null)
	if existing_spec != null and existing_spec.definition != null and existing_spec.definition != definition:
		return {"ok": false, "code": "ability.spec_definition_mismatch", "reason_zh": "能力 Spec 与定义对象不一致：%s" % ability_id}
	var spec_check := existing_spec.validate_grant_request(source, level, overrides) if existing_spec != null else GMAbilitySpec.new(definition).validate_grant_request(source, level, overrides)
	if not spec_check.ok:
		return {"ok": false, "code": "ability.%s" % str(spec_check.get("code", "grant_invalid")), "reason_zh": str(spec_check.get("reason_zh", "能力授予请求无效。"))}
	return {"ok": true, "ability_id": ability_id, "definition": definition, "source": source, "level": maxi(level, 1), "overrides": overrides.duplicate(true), "spec_exists": existing_spec != null}

func grant_ability(definition: GMAbilityDefinition, source: String, level: int = 1, overrides: Dictionary = {}) -> Dictionary:
	var preflight := preflight_ability_grant(definition, source, level, overrides)
	if not preflight.ok: return preflight
	var ability_id := str(preflight.ability_id)
	var spec: GMAbilitySpec = specs.get(ability_id, null)
	var created := false
	var grant_result: Dictionary
	if spec == null:
		# Stage the first source on a detached candidate before publishing either
		# the definition or the spec into the host.
		var candidate := GMAbilitySpec.new(definition)
		var candidate_result := candidate.grant_source(source, level, overrides)
		if not candidate_result.ok: return candidate_result
		spec = candidate
		grant_result = candidate_result
		created = true
	else:
		var grant_result_existing := spec.grant_source(source, level, overrides)
		if not grant_result_existing.ok: return grant_result_existing
		grant_result = grant_result_existing
	if not definitions.has(ability_id): definitions[ability_id] = definition
	if created: specs[ability_id] = spec
	grant_result["ability_id"] = ability_id
	grant_result["spec_created"] = created
	grant_result["spec"] = spec.to_summary()
	return grant_result

func _snapshot_ability_grant_state() -> Dictionary:
	var spec_states: Dictionary = {}
	for ability_id in specs.keys():
		var spec: GMAbilitySpec = specs[ability_id]
		if spec == null: continue
		spec_states[ability_id] = {
			"spec": spec,
			"definition": spec.definition,
			"ability_id": spec.ability_id,
			"source_records": spec.source_records.duplicate(true),
			"dynamic_tag_source_counts": spec.dynamic_tags.source_counts.duplicate(true) if spec.dynamic_tags != null else {},
			"dynamic_tag_events": spec.dynamic_tags.event_log.duplicate(true) if spec.dynamic_tags != null else [],
		}
	return {"definitions": definitions.duplicate(), "specs": specs.duplicate(), "spec_states": spec_states}

func _restore_ability_grant_state(snapshot: Dictionary) -> Dictionary:
	var saved_definitions: Dictionary = snapshot.get("definitions", {})
	var saved_specs: Dictionary = snapshot.get("specs", {})
	definitions.clear()
	definitions.merge(saved_definitions, true)
	specs.clear()
	specs.merge(saved_specs, true)
	var spec_states: Dictionary = snapshot.get("spec_states", {})
	for ability_id in spec_states.keys():
		var state: Dictionary = spec_states[ability_id]
		var spec = state.get("spec", null)
		if spec == null: continue
		spec.definition = state.get("definition", null)
		spec.ability_id = str(state.get("ability_id", ""))
		spec.source_records = state.get("source_records", {}).duplicate(true)
		if spec.dynamic_tags != null:
			spec.dynamic_tags.source_counts = state.get("dynamic_tag_source_counts", {}).duplicate(true)
			spec.dynamic_tags.event_log = state.get("dynamic_tag_events", []).duplicate(true)
	return {"ok": true, "restored": true}

func grant_bundle(bundle: GMAbilityBundle, source: String) -> Dictionary:
	if bundle == null: return {"ok": false, "code": "bundle.missing", "reason_zh": "不能授予空能力包。"}
	return bundle.grant_to(self, source, definitions)

func revoke_ability(ability_id: String, source: String) -> Dictionary:
	if ability_id.strip_edges().is_empty() or source.strip_edges().is_empty(): return {"ok": false, "code": "ability.revoke_invalid", "reason_zh": "撤销能力需要能力 ID 和来源。"}
	var spec: GMAbilitySpec = specs.get(ability_id, null)
	if spec == null: return {"ok": false, "code": "ability.spec_missing", "reason_zh": "宿主没有该能力 Spec：%s" % ability_id}
	var revoke_result := spec.revoke_source(source)
	if not revoke_result.ok: return revoke_result
	revoke_result["ability_id"] = ability_id
	if not spec.has_sources():
		specs.erase(ability_id)
		revoke_result["spec_removed"] = true
	else:
		revoke_result["spec_removed"] = false
		revoke_result["spec"] = spec.to_summary()
	return revoke_result

func revoke_bundle(bundle: GMAbilityBundle, source: String) -> Dictionary:
	if bundle == null: return {"ok": false, "code": "bundle.missing", "reason_zh": "不能撤销空能力包。"}
	return bundle.revoke_from(self, source)

func has_ability(ability_id: String) -> bool:
	return specs.has(ability_id)

func has_active_ability(ability_id: String) -> bool:
	for instance in active_instances:
		if instance != null and instance.is_active() and instance.definition != null and instance.definition.ability_id == ability_id: return true
	return false

func resolve_ability_id(request: GMAbilityActivationRequest) -> String:
	if request == null: return ""
	if not request.ability_id.strip_edges().is_empty(): return request.ability_id
	if request.ability_tag.strip_edges().is_empty(): return ""
	var query := GMGameplayTag.normalize(request.ability_tag)
	for id in specs:
		var definition: GMAbilityDefinition = definitions.get(id, null)
		if definition == null: continue
		for ability_tag in definition.ability_tags:
			var candidate := GMGameplayTag.normalize(str(ability_tag))
			if query == candidate or query.begins_with(candidate + ".") or candidate.begins_with(query + "."): return str(id)
	return ""

func activate(request: GMAbilityActivationRequest) -> Dictionary:
	var request_check := request.validate() if request != null else {"ok": false, "code": "request.missing", "reason_zh": "不能激活空请求。"}
	if not request_check.ok: return _failure(request_check, request)
	if request.host != self: return _failure({"ok": false, "code": "request.host_mismatch", "reason_zh": "激活请求宿主与能力宿主不一致。"}, request)
	var root_check := request.causal_chain.validate_activation_root(request.request_id) if request.causal_chain != null else {"ok": false, "code": "causal.chain_missing", "reason_zh": "激活请求缺少因果链。"}
	if not root_check.ok: return _failure(root_check, request)
	return _activate_request(request)

func request_activation(request: GMAbilityActivationRequest) -> Dictionary:
	return activate(request)

func _activate_request(request: GMAbilityActivationRequest, from_queue: bool = false) -> Dictionary:
	var ability_id := resolve_ability_id(request)
	if ability_id.is_empty(): return _failure({"ok": false, "code": "ability.not_granted", "reason_zh": "宿主未授予请求的能力：%s" % (request.ability_id if not request.ability_id.is_empty() else request.ability_tag)}, request)
	var spec: GMAbilitySpec = specs.get(ability_id, null)
	var definition: GMAbilityDefinition = definitions.get(ability_id, null)
	if spec == null or definition == null: return _failure({"ok": false, "code": "ability.not_granted", "reason_zh": "宿主未授予能力：%s" % ability_id}, request)
	var identity_check := _prepare_activation_identity(request, ability_id, from_queue)
	if identity_check.get("replay", false): return _replay_idempotent(identity_check, request)
	if not identity_check.ok: return _identity_rejection(identity_check, request)
	# Replacement and Cancel declarations must remain a pure plan until the
	# incoming candidate passes all required/blocked/target/commit checks.
	var instance_id := str(identity_check.get("instance_id", ""))
	request.event_data["ability_instance_id"] = instance_id
	var chain := causal_chain_for_request(request)
	var bind_result := chain.bind_ability_instance_identity(instance_id)
	if not bind_result.ok: return _failure(bind_result, request)
	var instance := GMAbilityInstance.new(self, definition, spec, request, instance_id)
	if instances_by_id.has(instance.instance_id):
		return _failure({"ok": false, "code": "ability.instance_id_collision", "reason_zh": "能力实例 ID 与活动实例冲突，已安全拒绝且未覆盖索引。", "instance_id": instance.instance_id}, request)
	var candidate_check: Dictionary = instance.preflight_check()
	if not candidate_check.ok: return _failure(candidate_check, request)
	var concurrency := _check_concurrency(definition, request)
	if not concurrency.ok:
		var concurrency_failure := instance.fail_external(str(concurrency.get("code", "ability.concurrent_rejected")), str(concurrency.get("reason_zh", "能力并发检查失败。")), concurrency)
		return _failure(concurrency_failure, request)
	if concurrency.get("queued", false) and not from_queue: return _enqueue(request, definition, ability_id, instance_id)
	if not concurrency.get("cancel_instances", []).is_empty():
		var commit_preflight := instance.preflight_commit()
		if not commit_preflight.ok: return _failure(commit_preflight, request)
	var instance_link := chain.add_ref(GMCausalRef.ability_instance(instance.instance_id, definition.ability_id), [request.request_id])
	if not instance_link.ok: return _failure({"ok": false, "code": "causal.ability_instance_link_failed", "reason_zh": "无法把 Host 分配的 AbilityInstance 接入当前请求因果链。", "details": instance_link}, request)
	var prefix_check := chain.validate_activation_prefix(request.request_id, instance.instance_id)
	if not prefix_check.ok: return _failure(prefix_check, request)
	_commit_concurrency_plan(concurrency)
	active_instances.append(instance)
	instances_by_id[instance.instance_id] = instance
	_mark_idempotency_state(request, "active")
	instance.causal_chain = chain
	_add_owned_tags(definition, instance.instance_id)
	var started := instance.start()
	if instance.is_terminal():
		_finalize_instance(instance)
		started = _decorate_result(started, definition, request, instance)
	else:
		started = _decorate_pending(started, definition, request, instance)
	return started

func causal_chain_for_request(request: GMAbilityActivationRequest) -> GMCausalChain:
	if request == null: return GMCausalChain.new()
	var chain: GMCausalChain = causal_chains.get(request.request_id, null)
	if chain == null:
		chain = request.causal_chain if request.causal_chain != null else GMCausalChain.from_activation_request(request)
		causal_chains[request.request_id] = chain
	return chain

func instance_for_request(request_id: String) -> GMAbilityInstance:
	for instance in active_instances:
		if instance != null and instance.request != null and instance.request.request_id == request_id: return instance
	return null

func build_candidate(request: GMAbilityActivationRequest, score: float = 0.0, reasons: Array = []) -> GMCandidateResult:
	return transaction_coordinator.candidate(request, null, causal_chain_for_request(request), score, reasons)

func activate_typed(request: GMAbilityActivationRequest) -> RefCounted:
	var activation := activate(request)
	if bool(activation.get("idempotent_replay", false)) and request != null and not request.idempotency_key.is_empty():
		var original: Variant = typed_terminal_results_by_key.get(request.idempotency_key, null)
		if original is GMCommittedFactResult:
			var committed_original: GMCommittedFactResult = original
			var replayed := GMCommittedFactResult.new(committed_original.fact_event, committed_original.change_records, committed_original.chain, committed_original.transaction_id, true)
			replayed.cues = committed_original.cues.duplicate(true)
			return replayed
	for entry in resolution_results:
		if str(entry.get("request_id", "")) != request.request_id: continue
		var result_value: Variant = entry.get("typed_result", null)
		if result_value is RefCounted: return result_value
	if bool(activation.get("pending", false)):
		return build_candidate(request, 0.0, ["能力已经进入生命周期，领域提交尚未完成。"])
	return GMBlockedResult.from_failure(activation, request, causal_chain_for_request(request))

func execute_domain_transaction(definition: GMAbilityDefinition, request: GMAbilityActivationRequest, spec: GMAbilitySpec) -> RefCounted:
	if fact_event_store == null or change_record_store == null or transaction_coordinator == null:
		return GMBlockedResult.from_failure({"code": "transaction.pipeline_missing", "reason_zh": "GM事实/事务管线尚未安装。", "fix": {"action": "配置 FactEventStore、ChangeRecordStore 和 Coordinator。"}}, request, causal_chain_for_request(request))
	var service_id := definition.resolver_id if not definition.resolver_id.is_empty() else definition.executor_service_id
	var service: Object = domain_services.get(service_id, null)
	var chain := causal_chain_for_request(request)
	if service == null:
		var missing := GMBlockedResult.new("transaction.resolver_missing", "能力缺少可用 DomainResolver，未产生事实。", str(request.event_data.get("source_id", request.source)), request.target_data.target_business_id if request.target_data != null else str(request.event_data.get("target_id", "")), chain, {"action": "注册 resolver_id=%s 的领域 Resolver。" % service_id})
		missing.details = {"resolver_id": service_id, "ability_id": definition.ability_id}
		resolution_results.append({"request_id": request.request_id, "typed_result": missing, "result": missing.to_dict()})
		return missing
	var metadata := {
		"resolver_id": service_id,
		"fact_type": definition.fact_type,
		"source_system": definition.fact_source_system,
		"ability_id": definition.ability_id,
		"ability_instance_id": instance_for_request(request.request_id).instance_id if instance_for_request(request.request_id) != null else str(request.event_data.get("ability_instance_id", "")),
		"fact_tags": Array(definition.fact_tags),
		"fact_visibility": definition.fact_visibility.duplicate(true)
	}
	var typed_result: Variant = transaction_coordinator.resolve(request, service, fact_event_store, change_record_store, metadata, chain)
	if typed_result is GMCommittedFactResult:
		var committed: GMCommittedFactResult = typed_result
		for cue_value in committed.cues:
			var cue_id := str(cue_value.get("cue_id", ""))
			var cue_parameters: Dictionary = cue_value.get("parameters", {}) if cue_value.get("parameters", {}) is Dictionary else {}
			var cue_result := emit_cue(GMCueParameters.new(cue_id, entity, cue_parameters), instance_for_request(request.request_id))
			if cue_result.ok:
				cue_value["emitted"] = true
				cue_value["cue"] = cue_result.get("cue", {})
		resolution_results.append({"request_id": request.request_id, "typed_result": committed, "result": committed.to_dict()})
		if not request.idempotency_key.is_empty(): typed_terminal_results_by_key[request.idempotency_key] = committed
		return committed
	if typed_result is GMBlockedResult:
		var blocked: GMBlockedResult = typed_result
		resolution_results.append({"request_id": request.request_id, "typed_result": blocked, "result": blocked.to_dict()})
		if not request.idempotency_key.is_empty(): typed_terminal_results_by_key[request.idempotency_key] = blocked
		return blocked
	var invalid := GMBlockedResult.new("transaction.result_invalid", "领域 Resolver 返回了未知事务结果，未产生事实。", request.source, request.target_data.target_business_id if request.target_data != null else "", chain, {"action": "仅返回 GMCandidateResult、GMBlockedResult 或 GMCommittedFactResult。"})
	resolution_results.append({"request_id": request.request_id, "typed_result": invalid, "result": invalid.to_dict()})
	return invalid

func advance_scheduler(amount: float = 1.0, unit: String = "auto") -> Dictionary:
	if scheduler == null: return {"ok": false, "code": "scheduler.missing", "reason_zh": "能力宿主缺少调度器。"}
	var advance_result := scheduler.advance(amount, unit)
	var effect_update := effect_runtime.advance(amount, unit, advance_result) if effect_runtime != null else {"ok": true, "updates": []}
	var updates: Array[Dictionary] = []
	if bool(advance_result.get("advanced", false)):
		for instance in active_instances.duplicate():
			if instance == null: continue
			var update: Dictionary = instance.tick(_delta_for_unit(amount, unit))
			updates.append(update)
			if instance.is_terminal(): _finalize_instance(instance)
	_drain_queue()
	if bool(advance_result.get("advanced", false)): _clear_expired_same_frame_claims()
	return {"ok": advance_result.get("ok", false), "scheduler": advance_result, "effects": effect_update, "updates": updates, "active_count": active_instances.size(), "queue_count": queued_requests.size()}

func tick(amount: float = 1.0, unit: String = "auto") -> Dictionary:
	return advance_scheduler(amount, unit)

func cancel_instance(instance_id: String, reason_zh: String = "能力实例被主动取消。") -> Dictionary:
	var instance: GMAbilityInstance = instances_by_id.get(instance_id, null)
	if instance == null: return {"ok": false, "code": "ability.instance_missing", "reason_zh": "找不到能力实例：%s" % instance_id}
	var result := instance.cancel(reason_zh)
	_finalize_instance(instance)
	return result

func _on_instance_terminal(instance: GMAbilityInstance) -> void:
	if instance != null and (active_instances.has(instance) or instances_by_id.has(instance.instance_id)):
		_finalize_instance(instance)

func cancel_ability(ability_id: String, reason_zh: String = "能力被主动取消。") -> Dictionary:
	var results: Array[Dictionary] = []
	for instance in active_instances.duplicate():
		if instance != null and instance.definition != null and instance.definition.ability_id == ability_id:
			results.append(cancel_instance(instance.instance_id, reason_zh))
	for entry in queued_requests.duplicate():
		var queued_request: GMAbilityActivationRequest = entry.request
		if queued_request != null and queued_request.ability_id == ability_id:
			results.append(_cancel_queued(entry.request.request_id, reason_zh))
	return {"ok": results.all(func(item): return not item.get("ok", true)) if not results.is_empty() else false, "results": results}

func cancel_request(request_id: String, reason_zh: String = "能力请求被主动取消。") -> Dictionary:
	for entry in queued_requests:
		var queued_request: GMAbilityActivationRequest = entry.request
		if queued_request != null and queued_request.request_id == request_id: return _cancel_queued(request_id, reason_zh)
	var instance: GMAbilityInstance = instances_by_id.get(request_id, null)
	if instance != null: return cancel_instance(instance.instance_id, reason_zh)
	for candidate in active_instances:
		if candidate != null and candidate.request != null and candidate.request.request_id == request_id: return cancel_instance(candidate.instance_id, reason_zh)
	return {"ok": false, "code": "ability.request_missing", "reason_zh": "找不到能力请求：%s" % request_id}

## ---------- Task06: 原子成本、冷却与同帧提交 ----------

func check_ability_commit(definition: GMAbilityDefinition, request: GMAbilityActivationRequest, _spec: GMAbilitySpec = null) -> Dictionary:
	if definition == null: return {"ok": false, "code": "ability.definition_missing", "reason_zh": "成本检查缺少能力定义。"}
	var has_commit_work := not definition.costs.is_empty() or not definition.cost_effect_ids.is_empty() or not definition.inventory_costs.is_empty() or not definition.cooldown_effect_id.is_empty() or not definition.cooldown_tag.is_empty() or definition.cooldown_duration_seconds > 0.0
	if not has_commit_work and definition.required_cue_ids.is_empty(): return {"ok": true, "no_op": true}
	for cue_id in definition.required_cue_ids:
		if cue_router == null or not cue_router.definitions.has(str(cue_id)):
			return {"ok": false, "code": "cue.required_missing", "reason_zh": "能力要求的必需 Cue 未注册：%s。" % cue_id, "cue_id": str(cue_id), "logic_unchanged": true}
	var numeric_costs: Array[Dictionary] = []
	for raw in definition.costs:
		var row: Dictionary = raw.duplicate(true)
		var attribute_id := str(row.get("attribute_id", row.get("attribute", ""))).strip_edges()
		var amount := float(row.get("amount", row.get("value", row.get("cost", 0.0))))
		if attribute_id.is_empty() or not attribute_set.definitions.has(attribute_id): return {"ok": false, "code": "cost.attribute_missing", "reason_zh": "能力成本引用了缺失属性：%s。" % attribute_id, "attribute_id": attribute_id}
		if amount <= 0.0 or is_nan(amount) or is_inf(amount): return {"ok": false, "code": "cost.amount_invalid", "reason_zh": "能力成本必须是有限正数：%s。" % attribute_id}
		var definition_row: Dictionary = attribute_set.definitions.get(attribute_id, {})
		if str(definition_row.get("value_type", "float")) not in ["float", "int"]: return {"ok": false, "code": "cost.attribute_not_numeric", "reason_zh": "能力成本属性不是数值类型：%s。" % attribute_id}
		var available := float(attribute_set.get_value(attribute_id, 0.0))
		if available < amount: return {"ok": false, "code": "cost.insufficient", "reason_zh": "能力成本不足：%s 可用 %.3f，需要 %.3f。" % [attribute_id, available, amount], "attribute_id": attribute_id, "available": available, "required": amount}
		numeric_costs.append({"attribute_id": attribute_id, "amount": amount, "available": available})
	for effect_id in definition.cost_effect_ids:
		var effect: GMEffectDefinition = effect_definitions.get(str(effect_id), null)
		if effect == null: return {"ok": false, "code": "cost.effect_definition_missing", "reason_zh": "能力成本效果定义缺失：%s。" % effect_id, "effect_id": str(effect_id)}
		if not effect.is_instant(): return {"ok": false, "code": "cost.effect_not_instant", "reason_zh": "能力成本效果必须是瞬时 GameplayEffect：%s。" % effect_id}
	var cooldown: GMEffectDefinition = _resolve_cooldown_definition(definition)
	if not definition.cooldown_effect_id.is_empty() and cooldown == null:
		return {"ok": false, "code": "cooldown.effect_definition_missing", "reason_zh": "能力冷却效果定义缺失：%s。" % definition.cooldown_effect_id, "effect_id": definition.cooldown_effect_id}
	if cooldown != null:
		var cooldown_source := _cooldown_source(definition.ability_id)
		for active in active_effects:
			if active != null and active.is_active() and active.effect_definition_id == cooldown.effect_id and active.source_id == cooldown_source:
				return {"ok": false, "code": "cooldown.active", "reason_zh": "能力仍在冷却中：%s。" % definition.ability_id, "active_effect_id": active.active_effect_id, "remaining_units": active.remaining_units}
	if not definition.cooldown_tag.is_empty() and tags.matches(definition.cooldown_tag, "hierarchy"):
		return {"ok": false, "code": "cooldown.tag_active", "reason_zh": "能力冷却标签仍然存在：%s。" % definition.cooldown_tag, "cooldown_tag": definition.cooldown_tag}
	var same_frame_key := _same_frame_key(definition, request)
	if not same_frame_key.is_empty() and same_frame_claims.has(same_frame_key):
		return {"ok": false, "code": "ability.same_frame_duplicate", "reason_zh": "同一物理帧/行动点/回合已提交过该能力成本。", "same_frame_key": same_frame_key}
	if not definition.inventory_costs.is_empty() and inventory_resolver == null:
		return {"ok": false, "code": "inventory.resolver_missing", "reason_zh": "消耗类能力必须通过05C唯一库存事务底座。"}
	var inventory_rows: Array[Dictionary] = []
	for raw_inventory in definition.inventory_costs:
		var inventory_row: Dictionary = raw_inventory.duplicate(true)
		var kind := str(inventory_row.get("item_kind", "lot"))
		var item_id := str(inventory_row.get("item_id", inventory_row.get("lot_id", inventory_row.get("instance_id", ""))))
		var quantity := int(inventory_row.get("quantity", inventory_row.get("amount", 1)))
		if not ["lot", "instance"].has(kind) or item_id.is_empty() or quantity <= 0: return {"ok": false, "code": "inventory.cost_invalid", "reason_zh": "能力库存成本必须声明有效的物品类型、身份和数量。", "row": inventory_row}
		inventory_rows.append({"item_kind": kind, "item_id": item_id, "quantity": quantity, "source_container_id": str(inventory_row.get("source_container_id", "")), "target_id": str(inventory_row.get("target_id", ""))})
	return {"ok": true, "no_op": false, "numeric_costs": numeric_costs, "inventory_costs": inventory_rows, "cooldown_effect_id": cooldown.effect_id if cooldown != null else "", "same_frame_key": same_frame_key, "refund_policy": _normalize_refund_policy(definition.cancel_refund_policy)}

func prepare_ability_commit(definition: GMAbilityDefinition, request: GMAbilityActivationRequest, spec: GMAbilitySpec = null, _owner_instance: Object = null) -> Dictionary:
	if request == null: return {"ok": false, "code": "request.missing", "reason_zh": "能力成本预检缺少请求。"}
	var key := request.request_id
	if ability_commit_plans.has(key): return ability_commit_plans[key].duplicate(true)
	var checked := check_ability_commit(definition, request, spec)
	if not checked.ok: return checked
	var plan := checked.duplicate(true)
	plan["request_id"] = key
	plan["ability_id"] = definition.ability_id
	plan["prepared"] = true
	plan["committed"] = false
	plan["finalized"] = false
	plan["attribute_snapshot"] = attribute_set.snapshot_state()
	plan["tag_snapshot"] = tags.snapshot()
	plan["effect_snapshot"] = effect_runtime.snapshot(true) if effect_runtime != null else {}
	plan["inventory_snapshot"] = _inventory_snapshot()
	plan["applied_cooldown_ids"] = []
	plan["inventory_facts"] = []
	ability_commit_plans[key] = plan
	return plan.duplicate(true)

func commit_ability_commit(definition: GMAbilityDefinition, request: GMAbilityActivationRequest, _spec: GMAbilitySpec = null, owner_instance: Object = null) -> Dictionary:
	if request == null: return {"ok": false, "code": "request.missing", "reason_zh": "能力成本提交缺少请求。"}
	var key := request.request_id
	var plan: Dictionary = ability_commit_plans.get(key, {})
	if plan.is_empty():
		var prepared := prepare_ability_commit(definition, request, _spec, owner_instance)
		if not prepared.ok: return prepared
		plan = ability_commit_plans.get(key, {})
	if bool(plan.get("committed", false)): return plan.duplicate(true)
	var same_frame_key := str(plan.get("same_frame_key", ""))
	if not same_frame_key.is_empty() and same_frame_claims.has(same_frame_key):
		return {"ok": false, "code": "ability.same_frame_duplicate", "reason_zh": "同一物理帧/行动点/回合已提交过该能力成本。", "same_frame_key": same_frame_key}
	plan["attribute_snapshot"] = attribute_set.snapshot_state()
	plan["tag_snapshot"] = tags.snapshot()
	plan["effect_snapshot"] = effect_runtime.snapshot(true) if effect_runtime != null else {}
	plan["inventory_snapshot"] = _inventory_snapshot()
	var applied_costs: Array[Dictionary] = []
	for row in plan.get("numeric_costs", []):
		var paid := attribute_set.apply_delta(str(row.get("attribute_id", "")), -float(row.get("amount", 0.0)), "gm.cost.%s" % definition.ability_id, "提交能力成本。")
		if not paid.ok: return _rollback_commit_plan(plan, "能力数值成本部分扣除失败。", paid)
		applied_costs.append(paid)
	plan["applied_numeric_costs"] = applied_costs
	for effect_id in definition.cost_effect_ids:
		var cost_effect: GMEffectDefinition = effect_definitions.get(str(effect_id), null)
		if cost_effect == null: return _rollback_commit_plan(plan, "能力成本效果定义在提交阶段缺失。", {"ok": false, "code": "cost.effect_definition_missing", "reason_zh": "成本效果定义缺失：%s。" % effect_id})
		var cost_spec := GMEffectSpec.new(cost_effect, "gm.cost.%s" % definition.ability_id)
		cost_spec.configure_identity("gm.cost.%s" % definition.ability_id, _host_entity_id(), {"ability_id": definition.ability_id, "request_id": request.request_id})
		var applied_effect := apply_effect(cost_effect, cost_spec, owner_instance)
		if not applied_effect.ok: return _rollback_commit_plan(plan, "能力成本效果提交失败。", applied_effect)
		plan["applied_cost_effects"] = Array(plan.get("applied_cost_effects", []))
		plan["applied_cost_effects"].append(applied_effect)
	var cooldown := _resolve_cooldown_definition(definition)
	if cooldown != null:
		var cooldown_spec := GMEffectSpec.new(cooldown, _cooldown_source(definition.ability_id))
		cooldown_spec.configure_identity(_cooldown_source(definition.ability_id), _host_entity_id(), {"ability_id": definition.ability_id, "request_id": request.request_id, "kind": "cooldown"})
		var cooldown_result := apply_effect(cooldown, cooldown_spec, owner_instance)
		if not cooldown_result.ok: return _rollback_commit_plan(plan, "能力冷却提交失败。", cooldown_result)
		plan.applied_cooldown_ids.append(str(cooldown_result.get("active_effect_id", "")))
	var inventory_result := _commit_inventory_costs(definition, request, plan)
	if not inventory_result.ok: return _rollback_commit_plan(plan, "库存成本提交失败，属性、效果和冷却必须原子回滚。", inventory_result)
	plan["inventory_facts"] = inventory_result.get("facts", [])
	plan["committed"] = true
	plan["commit_timestamp_usec"] = Time.get_ticks_usec()
	plan["same_frame_key"] = same_frame_key
	if not same_frame_key.is_empty(): same_frame_claims[same_frame_key] = {"request_id": key, "metric": _same_frame_metric()}
	abiliy_commit_plans_store(key, plan)
	inventory_commit_records[key] = plan.duplicate(true)
	return plan.duplicate(true)

func rollback_ability_commit(instance_or_request: Object, reason_zh: String = "能力取消，执行成本退款策略。") -> Dictionary:
	var key := _commit_key(instance_or_request)
	var plan: Dictionary = ability_commit_plans.get(key, inventory_commit_records.get(key, {}))
	if plan.is_empty(): return {"ok": true, "rolled_back": false, "reason_zh": "没有已经提交的能力成本。"}
	if not bool(plan.get("committed", false)):
		ability_commit_plans.erase(key)
		inventory_commit_records.erase(key)
		return {"ok": true, "rolled_back": false, "discarded_preflight": true, "reason_zh": "未提交的能力成本预检查计划已丢弃。"}
	var policy := _normalize_refund_policy(str(plan.get("refund_policy", "none")))
	var result := {"ok": true, "rolled_back": false, "refund_policy": policy, "reason_zh": reason_zh, "inventory_refunded": false}
	if policy == "none":
		result["reason_zh"] = "按不退款策略保留已提交成本与冷却。"
	else:
		var restored := _restore_non_inventory_commit(plan)
		if not restored.ok: return restored
		result["rolled_back"] = true
		if policy == "all":
			if plan.get("inventory_facts", []).is_empty():
				var inventory_restored := _restore_inventory_snapshot(plan)
				result["inventory_refunded"] = inventory_restored.ok
			else:
				result["inventory_refund_blocked"] = true
				result["reason_zh"] = "全量退款要求库存逆操作；05C消耗事实已提交，未猜测或伪造逆事实。"
	if not str(plan.get("same_frame_key", "")).is_empty(): same_frame_claims.erase(str(plan.get("same_frame_key", "")))
	plan["refund_result"] = result.duplicate(true)
	plan["rolled_back"] = result.rolled_back
	ability_commit_plans[key] = plan
	return result

func finalize_ability_commit(instance_or_request: Object) -> Dictionary:
	var key := _commit_key(instance_or_request)
	var plan: Dictionary = ability_commit_plans.get(key, {})
	if plan.is_empty(): return {"ok": true, "finalized": false, "reason_zh": "没有能力成本计划。"}
	plan["finalized"] = true
	abiliy_commit_plans_store(key, plan)
	return {"ok": true, "finalized": true, "request_id": key, "fact_count": plan.get("inventory_facts", []).size()}

func _record_instance_commit_result(instance: GMAbilityInstance, outcome: String) -> void:
	if instance == null: return
	if outcome == "completed":
		finalize_ability_commit(instance)
	else:
		rollback_ability_commit(instance, "能力实例%s，应用提交后的退款策略。" % outcome)

func prepare_for_save() -> Dictionary:
	var cancelled: Array[Dictionary] = []
	for instance in active_instances.duplicate():
		if instance == null or instance.is_terminal(): continue
		var result: Dictionary = instance.cancel("保存前安全结束不可持久化能力任务；不序列化协程或SceneTreeTimer。")
		cancelled.append(result)
	var queued_count := queued_requests.size()
	queued_requests.clear()
	var removed_effects: Array[Dictionary] = []
	for active in active_effects.duplicate():
		if active != null and not active.persisted and effect_runtime != null:
			removed_effects.append(effect_runtime.remove_effect(active.active_effect_id, "保存前该效果不可持久化，已安全移除。"))
	return {"ok": true, "cancelled_instances": cancelled, "queued_cleared": queued_count, "non_persisted_effects_removed": removed_effects, "no_coroutines_serialized": true}

func _rollback_commit_plan(plan: Dictionary, reason_zh: String, failure: Dictionary) -> Dictionary:
	_restore_non_inventory_commit(plan)
	_restore_inventory_snapshot(plan)
	var result := {"ok": false, "code": str(failure.get("code", "ability.commit_failed")), "reason_zh": reason_zh, "details": failure.duplicate(true), "rolled_back": true, "rollback": {"attributes": true, "effects": true, "tags": true, "inventory": true}}
	ability_commit_plans.erase(str(plan.get("request_id", "")))
	return result

func _restore_non_inventory_commit(plan: Dictionary) -> Dictionary:
	var attr_result := attribute_set.restore_state(plan.get("attribute_snapshot", {}))
	if not attr_result.ok: return attr_result
	var tag_result := tags.restore_snapshot(plan.get("tag_snapshot", {}))
	if not tag_result.ok: return tag_result
	if effect_runtime != null:
		var effect_result := effect_runtime.restore_snapshot(plan.get("effect_snapshot", {}))
		if not effect_result.ok: return effect_result
	return {"ok": true, "restored": true}

func _restore_inventory_snapshot(plan: Dictionary) -> Dictionary:
	var store: Object = _inventory_store()
	if store == null or not store.has_method("restore_snapshot"): return {"ok": true, "restored": false, "skipped": true}
	var snapshot: Dictionary = plan.get("inventory_snapshot", {})
	if snapshot.is_empty(): return {"ok": true, "restored": false, "skipped": true}
	return store.restore_snapshot(snapshot)

func _commit_inventory_costs(definition: GMAbilityDefinition, request: GMAbilityActivationRequest, plan: Dictionary) -> Dictionary:
	if definition.inventory_costs.is_empty(): return {"ok": true, "facts": []}
	if inventory_resolver == null: return {"ok": false, "code": "inventory.resolver_missing", "reason_zh": "库存成本没有安装05C InventoryResolver。"}
	var facts: Array[Dictionary] = []
	for index in definition.inventory_costs.size():
		var row: Dictionary = definition.inventory_costs[index].duplicate(true)
		var event_data := row.duplicate(true)
		event_data["inventory_operation"] = "consume"
		event_data["operation"] = "consume"
		event_data["source_id"] = str(event_data.get("source_id", request.source))
		event_data["target_id"] = str(event_data.get("target_id", _host_entity_id()))
		event_data["planned_fact_event_id"] = "gm.fact.inventory.consume.%s.%d" % [_slug(request.idempotency_key if not request.idempotency_key.is_empty() else request.request_id), index + 1]
		event_data["ability_id"] = definition.ability_id
		var inventory_request := GMAbilityActivationRequest.new(self, definition.ability_id, "", request.target_data, event_data, request.source, request.schedule_context, "%s.inventory.consume.%d" % [request.idempotency_key if not request.idempotency_key.is_empty() else request.request_id, index + 1])
		# The inventory transaction is a child operation of this activation, not a
		# second activation root.  Preserve the authoritative 05A request identity
		# so the existing causal prefix can be validated and committed unchanged.
		inventory_request.request_id = request.request_id
		inventory_request.causal_chain = request.causal_chain
		var metadata := {"resolver_id": str(inventory_resolver.get("resolver_id")), "fact_type": "gm.fact.inventory.consume", "source_system": "gm.ability.cost", "ability_id": definition.ability_id, "ability_instance_id": str(request.event_data.get("ability_instance_id", "")), "fact_tags": ["gm.inventory", "gm.inventory.consume", "gm.ability.cost"], "fact_visibility": {"public": false, "witnesses": []}}
		var typed_result: Variant = transaction_coordinator.resolve(inventory_request, inventory_resolver, fact_event_store, change_record_store, metadata, request.causal_chain)
		if not typed_result is GMCommittedFactResult:
			var failure: Dictionary = typed_result.to_dict() if typed_result is RefCounted and typed_result.has_method("to_dict") else {"result": typed_result}
			return {"ok": false, "code": "inventory.cost_not_committed", "reason_zh": "库存成本未产生正式 Committed Fact，已阻断能力提交。", "result": failure}
		var committed: GMCommittedFactResult = typed_result
		facts.append({"fact_event_id": committed.fact_event.event_id if committed.fact_event != null else "", "transaction_id": committed.transaction_id, "idempotent": committed.idempotent, "change_count": committed.change_records.size()})
	return {"ok": true, "facts": facts}

func _resolve_cooldown_definition(definition: GMAbilityDefinition) -> GMEffectDefinition:
	if definition == null: return null
	if not definition.cooldown_effect_id.is_empty(): return effect_definitions.get(definition.cooldown_effect_id, null)
	if definition.cooldown_tag.is_empty() or definition.cooldown_duration_seconds <= 0.0: return null
	var dynamic_id := "gm.effect.cooldown.%s" % _slug(definition.ability_id)
	var existing: GMEffectDefinition = effect_definitions.get(dynamic_id, null)
	if existing != null: return existing
	var generated := GMEffectDefinition.new()
	generated.effect_id = dynamic_id
	generated.display_name_zh = "能力冷却：%s" % definition.display_name_zh
	generated.effect_kind = "duration"
	generated.granted_tags = PackedStringArray([definition.cooldown_tag])
	generated.duration_seconds = definition.cooldown_duration_seconds
	generated.duration_unit = definition.cooldown_unit
	generated.max_stacks = 1
	generated.stack_policy = "ignore"
	# Cooldown state is gameplay state, not a transient task.  It must survive
	# an independent save/reopen so the reopened host cannot activate the same
	# ability while its cooldown tag/effect is still active.
	generated.persist = true
	generated.content_version = definition.content_version
	if effect_runtime != null and effect_runtime.register_definition(generated).ok: return generated
	return null

func _same_frame_key(definition: GMAbilityDefinition, request: GMAbilityActivationRequest) -> String:
	if definition == null or request == null: return ""
	var has_cost := not definition.costs.is_empty() or not definition.cost_effect_ids.is_empty() or not definition.inventory_costs.is_empty() or not definition.cooldown_tag.is_empty() or not definition.cooldown_effect_id.is_empty() or definition.cooldown_duration_seconds > 0.0
	if not has_cost: return ""
	var explicit := str(request.event_data.get("same_frame_key", request.event_data.get("frame_id", "")))
	var frame := explicit if not explicit.is_empty() else str(_same_frame_metric())
	return "%s|%s|%s|%s" % [definition.ability_id, request.source, _target_id_for_request(request), frame]

func _same_frame_metric() -> int:
	if scheduler == null: return 0
	return scheduler.physics_frame if scheduler.mode == "realtime" else scheduler.turn if scheduler.mode == "turn" else scheduler.tick_count

func _clear_expired_same_frame_claims() -> void:
	same_frame_claims.clear()

func _cooldown_source(ability_id: String) -> String:
	return "gm.cooldown.%s" % _slug(ability_id)

func _target_id_for_request(request: GMAbilityActivationRequest) -> String:
	if request == null: return _host_entity_id()
	if request.target_data != null and not request.target_data.target_business_id.is_empty(): return request.target_data.target_business_id
	return str(request.event_data.get("target_id", _host_entity_id()))

func _host_entity_id() -> String:
	return GMEffectSpec.stable_identity(entity) if entity != null else "gm.host"

func entity_id_for_gas() -> String:
	return _host_entity_id()

func _inventory_store() -> Object:
	if inventory_resolver == null: return null
	var value: Variant = inventory_resolver.get("inventory_store")
	return value if value is Object else null

func _inventory_snapshot() -> Dictionary:
	var store := _inventory_store()
	return store.snapshot() if store != null and store.has_method("snapshot") else {}

func _commit_key(value: Object) -> String:
	if value is GMAbilityInstance: return value.request.request_id if value.request != null else value.instance_id
	if value is GMAbilityActivationRequest: return value.request_id
	return str(value)

func _normalize_refund_policy(value: String) -> String:
	match value:
		"退属性与冷却", "attributes_and_cooldown", "attribute_and_cooldown": return "attributes_and_cooldown"
		"全量退款（需领域逆操作）", "all": return "all"
		_: return "none"

func abiliy_commit_plans_store(key: String, plan: Dictionary) -> void:
	ability_commit_plans[key] = plan.duplicate(true)

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in raw.length():
		var code := raw.unicode_at(index)
		result += raw.substr(index, 1) if ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45) else "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_") if not result.is_empty() else "request"

func emit_gameplay_event(event: GMGameplayEvent) -> Dictionary:
	if event == null: return {"ok": false, "code": "event.missing", "reason_zh": "不能发出空 Gameplay Event。"}
	var validation := event.validate()
	if not validation.ok: return validation
	if event_dispatch_depth >= max_event_dispatch_depth:
		return {"ok": false, "code": "event.recursion_limit", "reason_zh": "Gameplay Event 递归深度过大，已阻断继续分发。", "depth": event_dispatch_depth, "limit": max_event_dispatch_depth}
	event_dispatch_depth += 1
	event.set_dispatch_depth(event_dispatch_depth)
	gameplay_events.append(event.to_dict())
	gameplay_event.emit(event)
	var triggered: Array[Dictionary] = []
	for id in specs:
		var definition: GMAbilityDefinition = definitions.get(id, null)
		if definition == null or definition.event_trigger_tags.is_empty(): continue
		var matches := false
		for event_tag in definition.event_trigger_tags:
			if event.matches_tag(str(event_tag), true):
				matches = true
				break
		if not matches: continue
		var target_data := GMTargetData.from_entity(event.target) if event.target != null and is_instance_valid(event.target) else null
		var request := GMAbilityActivationRequest.new(self, str(id), "", target_data, {"gameplay_event": event.to_dict()}, "gameplay_event", {"mode": scheduler.mode, "event_depth": event_dispatch_depth})
		var activation := activate(request)
		triggered.append(activation)
		event_activation_log.append({"event": event.to_dict(), "ability_id": id, "activation": activation})
	event_dispatch_depth -= 1
	var trigger_runtime_result: Dictionary = event_trigger_runtime.result_for_event(event) if event_trigger_runtime != null else {"ok": true, "triggered": []}
	var trigger_rows: Array = trigger_runtime_result.get("triggered", []) if trigger_runtime_result.get("triggered", []) is Array else []
	triggered.append_array(trigger_rows)
	return {"ok": bool(trigger_runtime_result.get("ok", true)), "event": event.to_dict(), "triggered": triggered, "depth": event_dispatch_depth, "trigger_runtime": trigger_runtime_result}

func register_event_trigger(trigger: GMGameplayEventTrigger) -> Dictionary:
	if event_trigger_runtime == null: return {"ok": false, "code": "event.runtime_missing", "reason_zh": "Gameplay Event 触发运行时尚未初始化。"}
	return event_trigger_runtime.register_trigger(trigger)

func unregister_event_trigger(trigger_id: String) -> Dictionary:
	if event_trigger_runtime == null: return {"ok": false, "code": "event.runtime_missing", "reason_zh": "Gameplay Event 触发运行时尚未初始化。"}
	return event_trigger_runtime.unregister_trigger(trigger_id)

func validate_event_triggers(context: Dictionary = {}) -> Dictionary:
	if event_trigger_runtime == null: return {"ok": false, "code": "event.runtime_missing", "reason_zh": "Gameplay Event 触发运行时尚未初始化。"}
	return event_trigger_runtime.validate_all(context)

func event_trigger_snapshot() -> Dictionary:
	return event_trigger_runtime.snapshot() if event_trigger_runtime != null else {"trigger_count": 0, "runtime_missing": true}

func gameplay_event_audit_graph() -> Dictionary:
	return event_trigger_runtime.event_graph() if event_trigger_runtime != null else {"graph_kind": "GameplayEvent", "nodes": [], "edges": []}

func emit_cue(parameters: GMCueParameters, owner_instance: GMAbilityInstance = null) -> Dictionary:
	if parameters == null: return {"ok": false, "code": "cue.missing", "reason_zh": "不能发出空 Gameplay Cue。"}
	if owner_instance != null and (owner_instance.is_terminal() or not instances_by_id.has(owner_instance.instance_id)):
		return {"ok": false, "code": "cue.after_ability_finished", "reason_zh": "能力结束后禁止发出该能力的 Cue。", "instance_id": owner_instance.instance_id}
	var required_override := bool(parameters.context.get("required", false)) if parameters != null else false
	var routed := cue_router.route(parameters, required_override) if cue_router != null else {"ok": true, "cue": parameters.to_dict()}
	if not routed.ok:
		if str(routed.get("code", "")) == "cue.optional_missing":
			var optional_snapshot: Dictionary = parameters.to_dict()
			cue_events.append({"cue": optional_snapshot, "optional_missing": true, "logic_unchanged": true})
			return {"ok": true, "optional_missing": true, "logic_unchanged": true, "code": routed.code, "cue": optional_snapshot}
		return routed
	var snapshot: Dictionary = routed.get("cue", parameters.to_dict()).duplicate(true)
	if owner_instance != null: snapshot["instance_id"] = owner_instance.instance_id
	cue_events.append(snapshot)
	return {"ok": true, "cue": snapshot}

func execute_domain_command(service_id: String, definition: GMAbilityDefinition, request: GMAbilityActivationRequest, spec: GMAbilitySpec) -> Dictionary:
	var service: Object = domain_services.get(service_id, null)
	if service == null: return {"ok": false, "code": "ability.domain_service_missing", "reason_zh": "能力“%s”缺少领域执行器：%s" % [definition.display_name_zh, service_id], "executor": service_id}
	var value: Variant
	if service.has_method("execute_ability"): value = service.execute_ability(definition, request, spec)
	elif service.has_method("execute"): value = service.execute(definition, request, spec)
	else: return {"ok": false, "code": "ability.domain_service_invalid", "reason_zh": "领域执行器未提供统一 execute_ability 接口：%s" % service_id, "executor": service_id}
	if value is Dictionary:
		var normalized: Dictionary = value.duplicate(true)
		if not normalized.has("ok"): normalized["ok"] = true
		normalized["executor"] = service_id
		return normalized
	return {"ok": true, "result": value, "executor": service_id}

func ability_status(ability_id: String) -> Dictionary:
	var spec: GMAbilitySpec = specs.get(ability_id, null)
	var definition: GMAbilityDefinition = definitions.get(ability_id, null)
	if spec == null or definition == null: return {"ok": false, "code": "ability.not_granted", "reason_zh": "能力未授予：%s" % ability_id, "ability_id": ability_id, "available": false}
	var request := GMAbilityActivationRequest.new(self, ability_id, "", null, {}, "browser")
	var check := definition.can_activate(self, request, spec)
	return {"ok": true, "ability_id": ability_id, "available": check.ok, "reason_zh": "" if check.ok else str(check.reason_zh), "level": spec.effective_level(), "sources": Array(spec.sources()), "tags": Array(definition.ability_tags), "definition": definition.to_summary(), "spec": spec.to_summary()}

func ability_browser_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var ids: Array[String] = []
	for id in specs: ids.append(str(id))
	ids.sort()
	for id in ids: rows.append(ability_status(id))
	return rows

func host_summary() -> Dictionary:
	return {
		"mounted": mounted,
		"entity_id": _entity_key(entity) if entity != null else "",
		"entity_kind": _entity_kind(entity),
		"is_character_body_dependency": false,
		"tag_snapshot": tags.snapshot(),
		"ability_count": specs.size(),
		"ability_ids": specs.keys(),
		"active_instance_count": active_instances.size(),
		"active_effect_count": active_effects.size(),
		"active_effects": effect_runtime.snapshot(true) if effect_runtime != null else {},
		"cue_router": cue_router.snapshot() if cue_router != null else {},
		"inventory_commit_count": inventory_commit_records.size(),
		"queued_request_count": queued_requests.size(),
		"idempotency": idempotency_ledger_snapshot(false),
		"scheduler": scheduler.snapshot() if scheduler != null else {},
		"duplicate_spec_strategy": DUPLICATE_SPEC_STRATEGY,
		"fact_pipeline": {
			"fact_count": fact_event_store.get_record_count() if fact_event_store != null else 0,
			"change_count": change_record_store.get_record_count() if change_record_store != null else 0,
			"causal_chain_count": causal_chains.size(),
		},
	}

func _check_concurrency(definition: GMAbilityDefinition, _request: GMAbilityActivationRequest) -> Dictionary:
	var cancel_instances: Array[GMAbilityInstance] = []
	for existing in active_instances:
		if existing == null or existing.is_terminal() or existing.definition == null: continue
		if _active_definition_blocks_incoming(existing.definition, definition):
			return {"ok": false, "code": "ability.blocked_by_ability", "reason_zh": "活动能力“%s”阻断来袭能力“%s”。" % [existing.definition.ability_id, definition.ability_id], "blocking_instance_id": existing.instance_id, "blocking_ability_id": existing.definition.ability_id}
		if _definition_cancels_existing(definition, existing.definition):
			cancel_instances.append(existing)
	if definition.concurrency_group.is_empty(): return {"ok": true, "cancel_instances": cancel_instances}
	var same_group: Array[GMAbilityInstance] = []
	for existing in active_instances:
		if existing != null and not existing.is_terminal() and existing.definition != null and existing.definition.concurrency_group == definition.concurrency_group: same_group.append(existing)
	if same_group.is_empty(): return {"ok": true, "cancel_instances": cancel_instances}
	var policy := _normalize_policy(definition.concurrency_policy)
	match policy:
		"reject": return {"ok": false, "code": "ability.concurrent_rejected", "reason_zh": "能力并发组“%s”已有能力正在执行。" % definition.concurrency_group}
		"replace", "cancel_old":
			for old in same_group:
				if not cancel_instances.has(old): cancel_instances.append(old)
			return {"ok": true, "replaced": same_group.size(), "cancel_instances": cancel_instances}
		"queue", "wait": return {"ok": true, "queued": true, "reason_zh": "能力正在等待并发组空闲。", "cancel_instances": cancel_instances}
		"parallel": return {"ok": true, "parallel": true, "cancel_instances": cancel_instances}
		_: return {"ok": false, "code": "ability.concurrency_policy_invalid", "reason_zh": "未知并发策略：%s" % definition.concurrency_policy}

func _commit_concurrency_plan(plan: Dictionary) -> void:
	for existing in plan.get("cancel_instances", []):
		if existing == null or existing.is_terminal(): continue
		existing.cancel("被新能力的集中并发/Cancel规则取消。")
		_finalize_instance(existing)

func _prepare_activation_identity(request: GMAbilityActivationRequest, ability_id: String, from_queue: bool = false) -> Dictionary:
	if request == null: return {"ok": false, "code": "ability.identity_request_missing", "reason_zh": "稳定身份派生缺少请求。", "identity_preserve": true}
	var explicit := not request.idempotency_key.is_empty()
	if not explicit:
		var assigned := str(assigned_instance_ids_by_request.get(request.request_id, ""))
		if assigned.is_empty():
			identity_allocation_sequence += 1
			assigned = request.derive_instance_id(idempotency_epoch, identity_allocation_sequence)
			if _instance_id_owned_by_other(assigned, "", request.request_id):
				return {"ok": false, "code": "ability.instance_identity_derivation_collision", "reason_zh": "非幂等请求派生身份发生碰撞，已关闭式拒绝。", "instance_id": assigned, "identity_preserve": true}
			assigned_instance_ids_by_request[request.request_id] = assigned
		return {"ok": true, "instance_id": assigned, "explicit": false}
	var contract_hash := request.idempotency_contract_hash(ability_id)
	if idempotency_ledger.has(request.idempotency_key):
		var existing: Dictionary = idempotency_ledger[request.idempotency_key]
		if str(existing.get("contract_hash", "")) != contract_hash:
			return {"ok": false, "code": "ability.idempotency_key_conflict", "reason_zh": "同一精确幂等键对应不同激活合同，已关闭式拒绝。", "instance_id": str(existing.get("instance_id", "")), "identity_preserve": true}
		var status := str(existing.get("status", "reserved"))
		if from_queue and status == "queued" and str(existing.get("request_id", "")) == request.request_id:
			return {"ok": true, "instance_id": str(existing.get("instance_id", "")), "explicit": true, "from_queue": true}
		if status == "terminal":
			return {"ok": true, "replay": true, "entry": existing.duplicate(true), "instance_id": str(existing.get("instance_id", "")), "identity_preserve": true}
		return {"ok": false, "code": "ability.idempotency_key_queued" if status == "queued" else "ability.idempotency_key_active", "reason_zh": "显式幂等键已有未终结请求，重复请求已确定性拒绝。", "instance_id": str(existing.get("instance_id", "")), "existing_request_id": str(existing.get("request_id", "")), "identity_preserve": true}
	if idempotency_ledger.size() >= maxi(max_idempotency_entries, 1):
		return {"ok": false, "code": "ability.idempotency_ledger_full", "reason_zh": "Host 幂等账本已达有界容量；请在静默点显式清理或结束 Host 生命周期。", "ledger_limit": maxi(max_idempotency_entries, 1), "identity_preserve": true}
	var instance_id := request.derive_instance_id(idempotency_epoch, 0)
	if _instance_id_owned_by_other(instance_id, request.idempotency_key, request.request_id):
		return {"ok": false, "code": "ability.instance_identity_derivation_collision", "reason_zh": "不同原始幂等键派生为同一身份，已关闭式拒绝。", "instance_id": instance_id, "identity_preserve": true}
	idempotency_ledger[request.idempotency_key] = {
		"version": GMAbilityActivationRequest.IDENTITY_VERSION,
		"epoch": idempotency_epoch,
		"key_hash": request.idempotency_key_hash(),
		"contract_hash": contract_hash,
		"request_id": request.request_id,
		"ability_id": ability_id,
		"instance_id": instance_id,
		"status": "reserved",
		"result": {},
		"replay_count": 0,
	}
	return {"ok": true, "instance_id": instance_id, "explicit": true}

func _instance_id_owned_by_other(instance_id: String, exact_key: String, request_id: String) -> bool:
	if instances_by_id.has(instance_id): return true
	for key in idempotency_ledger:
		var entry: Dictionary = idempotency_ledger[key]
		if str(entry.get("instance_id", "")) == instance_id and str(key) != exact_key: return true
	for assigned_request_id in assigned_instance_ids_by_request:
		if str(assigned_instance_ids_by_request[assigned_request_id]) == instance_id and str(assigned_request_id) != request_id: return true
	return false

func _mark_idempotency_state(request: GMAbilityActivationRequest, status: String, terminal_result: Dictionary = {}) -> void:
	if request == null: return
	if request.idempotency_key.is_empty():
		if status == "terminal": assigned_instance_ids_by_request.erase(request.request_id)
		return
	if not idempotency_ledger.has(request.idempotency_key): return
	var entry: Dictionary = idempotency_ledger[request.idempotency_key]
	if str(entry.get("request_id", "")) != request.request_id: return
	entry["status"] = status
	if status == "terminal": entry["result"] = terminal_result.duplicate(true)
	idempotency_ledger[request.idempotency_key] = entry

func _replay_idempotent(identity: Dictionary, retry_request: GMAbilityActivationRequest) -> Dictionary:
	var entry: Dictionary = identity.get("entry", {})
	var replay: Dictionary = entry.get("result", {}).duplicate(true)
	if replay.is_empty(): return _failure({"ok": false, "code": "ability.idempotency_replay_missing", "reason_zh": "幂等终态缺少可回放结果，已关闭式拒绝。", "identity_preserve": true}, retry_request)
	entry["replay_count"] = int(entry.get("replay_count", 0)) + 1
	idempotency_ledger[retry_request.idempotency_key] = entry
	replay["idempotent_replay"] = true
	replay["replay_count"] = entry.replay_count
	replay["original_request_id"] = str(entry.get("request_id", ""))
	replay["retry_request_id"] = retry_request.request_id
	replay["instance_id"] = str(entry.get("instance_id", replay.get("instance_id", "")))
	return replay

func _identity_rejection(failure: Dictionary, request: GMAbilityActivationRequest) -> Dictionary:
	var code := str(failure.get("code", "ability.identity_rejected"))
	var reason := str(failure.get("reason_zh", "稳定身份检查拒绝了请求。"))
	var result := {"ok": false, "state": "REJECTED", "failure_code": code, "failure_reason_zh": reason, "reason_zh": reason, "request": request.to_dict() if request != null else {}, "identity_rejection": true}
	for key in ["instance_id", "existing_request_id", "ledger_limit"]:
		if failure.has(key): result[key] = failure[key]
	last_failure = result.duplicate(true)
	return result

func idempotency_ledger_snapshot(include_raw_keys: bool = false) -> Dictionary:
	var rows: Array[Dictionary] = []
	for exact_key in idempotency_ledger:
		var entry: Dictionary = idempotency_ledger[exact_key]
		var row := {
			"version": str(entry.get("version", "")), "epoch": int(entry.get("epoch", 0)),
			"key_hash": str(entry.get("key_hash", "")), "contract_hash": str(entry.get("contract_hash", "")),
			"request_id": str(entry.get("request_id", "")), "ability_id": str(entry.get("ability_id", "")),
			"instance_id": str(entry.get("instance_id", "")), "status": str(entry.get("status", "")),
			"replay_count": int(entry.get("replay_count", 0)),
		}
		if include_raw_keys: row["idempotency_key"] = str(exact_key)
		rows.append(row)
	rows.sort_custom(func(a, b): return str(a.instance_id) < str(b.instance_id))
	return {"version": GMAbilityActivationRequest.IDENTITY_VERSION, "epoch": idempotency_epoch, "entry_count": rows.size(), "limit": maxi(max_idempotency_entries, 1), "fail_closed": true, "entries": rows}

func clear_terminal_idempotency_history() -> Dictionary:
	if not active_instances.is_empty() or not queued_requests.is_empty():
		return {"ok": false, "code": "ability.idempotency_clear_not_quiescent", "reason_zh": "仅可在无活动实例且无排队请求时清理幂等历史。", "active_count": active_instances.size(), "queue_count": queued_requests.size()}
	var cleared := idempotency_ledger.size()
	idempotency_ledger.clear()
	typed_terminal_results_by_key.clear()
	assigned_instance_ids_by_request.clear()
	idempotency_epoch += 1
	return {"ok": true, "cleared": cleared, "new_epoch": idempotency_epoch}

func _active_definition_blocks_incoming(active_definition: GMAbilityDefinition, incoming_definition: GMAbilityDefinition) -> bool:
	if active_definition == null or incoming_definition == null: return false
	for blocked_id in active_definition.block_ability_ids:
		if str(blocked_id) == incoming_definition.ability_id: return true
	for block_tag in active_definition.block_tags:
		if _definition_has_ability_tag(incoming_definition, str(block_tag)): return true
	return false

func _enqueue(request: GMAbilityActivationRequest, definition: GMAbilityDefinition, ability_id: String, instance_id: String) -> Dictionary:
	if queued_requests.size() >= max_queue_size: return _failure({"ok": false, "code": "ability.queue_full", "reason_zh": "能力并发队列已满，拒绝继续排队。"}, request)
	queue_sequence += 1
	var snapshot := scheduler.snapshot()
	var entry := {"sequence": queue_sequence, "request": request, "ability_id": ability_id, "definition": definition, "instance_id": instance_id, "enqueued": snapshot, "enqueued_usec": Time.get_ticks_usec()}
	queued_requests.append(entry)
	_mark_idempotency_state(request, "queued")
	var result := {"ok": true, "state": "QUEUED", "pending": true, "queued": true, "queue_position": queued_requests.size(), "queue_sequence": queue_sequence, "ability_id": ability_id, "instance_id": instance_id, "request": request.to_dict(), "reason_zh": "能力已进入并发队列。"}
	activation_queued.emit(result)
	return result

func _drain_queue() -> void:
	if queued_requests.is_empty(): return
	queued_requests.sort_custom(func(a, b): return int(a.sequence) < int(b.sequence))
	for entry in queued_requests.duplicate():
		var request: GMAbilityActivationRequest = entry.request
		var definition: GMAbilityDefinition = entry.definition
		if request == null or definition == null:
			queued_requests.erase(entry)
			continue
		if _queue_expired(entry, definition):
			queued_requests.erase(entry)
			var timeout_result := _failure({"ok": false, "code": "ability.queue_timeout", "reason_zh": "能力排队超时，已安全出队。"}, request)
			timeout_result["state"] = "FAILED"
			continue
		var concurrency := _check_concurrency(definition, request)
		if concurrency.get("queued", false): continue
		if not concurrency.ok:
			queued_requests.erase(entry)
			_failure(concurrency, request)
			continue
		queued_requests.erase(entry)
		_activate_request(request, true)

func _queue_expired(entry: Dictionary, definition: GMAbilityDefinition) -> bool:
	var started: Dictionary = entry.get("enqueued", {})
	if scheduler.mode == "turn": return int(scheduler.turn) - int(started.get("turn", scheduler.turn)) >= maxi(definition.queue_timeout_turns, 1)
	return float(scheduler.time_seconds) - float(started.get("time_seconds", scheduler.time_seconds)) >= maxf(definition.queue_timeout_seconds, 0.1)

func _cancel_queued(request_id: String, reason_zh: String) -> Dictionary:
	for entry in queued_requests.duplicate():
		var request: GMAbilityActivationRequest = entry.request
		if request != null and request.request_id == request_id:
			queued_requests.erase(entry)
			var result := {"ok": false, "state": "CANCELLED", "failure_code": "ability.cancelled", "failure_reason_zh": reason_zh, "reason_zh": reason_zh, "instance_id": str(entry.get("instance_id", request.event_data.get("ability_instance_id", ""))), "request": request.to_dict()}
			_mark_idempotency_state(request, "terminal", result)
			assigned_instance_ids_by_request.erase(request.request_id)
			activation_log.append(result.duplicate(true))
			activation_finished.emit(result)
			return result
	return {"ok": false, "code": "ability.queue_request_missing", "reason_zh": "排队请求不存在：%s" % request_id}

func _finalize_instance(instance: GMAbilityInstance) -> void:
	if instance == null: return
	if not active_instances.has(instance) and not instances_by_id.has(instance.instance_id): return
	instance.release_tasks()
	_add_or_remove_owned_tags(instance.definition, instance.instance_id, false)
	active_instances.erase(instance)
	instances_by_id.erase(instance.instance_id)
	var final_result := instance.result.duplicate(true) if not instance.result.is_empty() else instance.status_snapshot(false)
	final_result["activation_path"] = ACTIVATION_PATH.replace("DomainExecutor", instance.definition.executor_service_id if instance.definition != null and not instance.definition.executor_service_id.is_empty() else "no-domain")
	final_result["source"] = instance.request.source if instance.request != null else ""
	final_result["request"] = instance.request.to_dict() if instance.request != null else {}
	final_result["causal_chain"] = instance.causal_chain.to_dict() if instance.causal_chain != null else {}
	final_result["fact_count"] = fact_event_store.get_record_count() if fact_event_store != null else 0
	final_result["change_record_count"] = change_record_store.get_record_count() if change_record_store != null else 0
	_mark_idempotency_state(instance.request, "terminal", final_result)
	if instance.request != null: assigned_instance_ids_by_request.erase(instance.request.request_id)
	activation_log.append(final_result.duplicate(true))
	activation_finished.emit(final_result)
	if final_result.get("ok", false):
		emit_gameplay_event(GMGameplayEvent.new("gm.event.ability.activated", entity, instance.request.target_data.target if instance.request != null and instance.request.target_data != null else null, {"ability_id": instance.definition.ability_id, "source": instance.request.source if instance.request != null else ""}, "ability"))

func _decorate_pending(value: Dictionary, definition: GMAbilityDefinition, request: GMAbilityActivationRequest, instance: GMAbilityInstance) -> Dictionary:
	var result := _decorate_result(value, definition, request, instance)
	result["ok"] = true
	result["state"] = instance.state_name()
	result["pending"] = not instance.is_terminal()
	return result

func _decorate_result(value: Dictionary, definition: GMAbilityDefinition, request: GMAbilityActivationRequest, instance: GMAbilityInstance) -> Dictionary:
	var result := value.duplicate(true)
	result["ability_id"] = definition.ability_id
	result["instance_id"] = instance.instance_id
	result["activation_path"] = ACTIVATION_PATH.replace("DomainExecutor", definition.executor_service_id if not definition.executor_service_id.is_empty() else "no-domain")
	result["source"] = request.source
	result["request"] = request.to_dict()
	return result

func _failure(failure: Dictionary, request: GMAbilityActivationRequest) -> Dictionary:
	var code := str(failure.get("code", failure.get("failure_code", "ability.failed")))
	var reason := str(failure.get("reason_zh", failure.get("failure_reason_zh", "能力激活失败。")))
	var result := {"ok": false, "state": "FAILED", "failure_code": code, "failure_reason_zh": reason, "reason_zh": reason, "request": request.to_dict() if request != null else {}, "host": host_summary(), "path": ACTIVATION_PATH}
	for key in ["instance_id", "ability_id", "phase_trace", "timeline", "task_results", "details", "ledger_limit", "existing_request_id"]:
		if failure.has(key): result[key] = failure[key]
	if request != null and not str(request.event_data.get("ability_instance_id", "")).is_empty() and not result.has("instance_id"):
		result["instance_id"] = str(request.event_data.get("ability_instance_id", ""))
	if request != null and request.causal_chain != null: result["causal_chain"] = request.causal_chain.to_dict()
	if request != null and not bool(failure.get("identity_preserve", false)):
		_mark_idempotency_state(request, "terminal", result)
		assigned_instance_ids_by_request.erase(request.request_id)
	last_failure = result.duplicate(true)
	activation_log.append(result.duplicate(true))
	activation_finished.emit(result)
	return result

func _definition_cancels_existing(incoming: GMAbilityDefinition, existing: GMAbilityDefinition) -> bool:
	for id in incoming.cancel_ability_ids:
		if id == existing.ability_id: return true
	for tag in incoming.cancel_tags:
		if _definition_has_tag(existing, str(tag)): return true
	return false

func _definition_has_tag(definition: GMAbilityDefinition, query: String) -> bool:
	var normalized := GMGameplayTag.normalize(query)
	for tag in definition.ability_tags + definition.grant_tags + definition.owned_tags:
		var candidate := GMGameplayTag.normalize(str(tag))
		if candidate == normalized or candidate.begins_with(normalized + ".") or normalized.begins_with(candidate + "."): return true
	return false

func _definition_has_ability_tag(definition: GMAbilityDefinition, query: String) -> bool:
	var normalized := GMGameplayTag.normalize(query)
	for tag in definition.ability_tags:
		var candidate := GMGameplayTag.normalize(str(tag))
		if candidate == normalized or candidate.begins_with(normalized + ".") or normalized.begins_with(candidate + "."): return true
	return false

func _add_owned_tags(definition: GMAbilityDefinition, source: String) -> void:
	_add_or_remove_owned_tags(definition, source, true)

func _add_or_remove_owned_tags(definition: GMAbilityDefinition, source: String, add: bool) -> void:
	if definition == null: return
	for tag in definition.grant_tags + definition.owned_tags:
		if add: tags.add_tag(str(tag), source)
		else: tags.remove_tag(str(tag), source)

func _normalize_policy(value: String) -> String:
	match value:
		"允许并行", "parallel", "allow_parallel": return "parallel"
		"同组拒绝", "reject": return "reject"
		"同组替换", "replace": return "replace"
		"同组排队", "queue": return "queue"
		"取消旧能力再启动", "cancel_old": return "cancel_old"
		"等待指定能力结束", "wait": return "wait"
		_: return value

func _delta_for_unit(amount: float, unit: String) -> float:
	if unit == "physics_frames": return float(amount) / 60.0
	if unit == "turns" or unit == "action_points": return 0.0
	return maxf(float(amount), 0.0)

func _on_tag_event(event: GMGameplayEvent) -> void:
	gameplay_event.emit(event)

func _mount_failure(code: String, reason_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "failure_code": code, "failure_reason_zh": reason_zh}

func _entity_key(value: Object) -> String:
	return str(value.get_instance_id()) if value != null and is_instance_valid(value) else ""

func _entity_kind(value: Object) -> String:
	if value == null or not is_instance_valid(value): return "无"
	var runtime_class := value.get_class()
	if value is Node2D or value is Node: return runtime_class
	if value is Resource: return "Resource代理"
	return runtime_class

static func _cleanup_invalid_mounts() -> void:
	for key in mounted_entities.keys().duplicate():
		var value = mounted_entities[key]
		if value == null or not is_instance_valid(value) or not value.mounted: mounted_entities.erase(key)
