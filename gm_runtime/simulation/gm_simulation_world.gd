class_name GMSimulationWorld
extends RefCounted

## 纯数据后台模拟外骨架：snapshot -> command buffer -> deterministic merge -> 05A transaction -> committed fact。

const SCHEMA_VERSION := GMReceiptEnvelopeAdapter.WORLD_SCHEMA
const COMMIT_RECEIPT_SCHEMA := GMReceiptEnvelopeAdapter.LEDGER_SCHEMA
const COMMIT_RECEIPT_ENVELOPE_SCHEMA := GMReceiptEnvelopeAdapter.ENVELOPE_SCHEMA
const SPATIAL_CONTRIBUTOR := preload("res://gm_runtime/spatial_core/gm_spatial_snapshot_contributor.gd")
const SPATIAL_CAPABILITIES := preload("res://gm_runtime/spatial_core/gm_spatial_backend_capabilities.gd")

var world_id: String = "gm.simulation.world.default"
var seed: int = 1
var tick: int = 0
var phase: String = "idle"
var world_budget_units: int = 0
var registry: GMEntityRegistry
var systems: Dictionary = {}
var stores: Dictionary = {}
var change_store: GMChangeRecordStore
var event_store: GMEventStore
var transaction_coordinator: GMDomainTransactionCoordinator
var domain_resolver: Object = null
var domain_metadata: Dictionary = {}
var domain_host: GMAbilitySystemHost
var scene_bridge: GMSceneBridge
var spatial_runtime_context: Object = null
var abstract_commits: Array = []
var tick_history: Array = []
var last_snapshot: GMWorldSnapshot
var last_merge: Dictionary = {}
var max_commit_receipts: int = 256
var commit_receipt_epoch: int = 1
var scheduler_debt: Dictionary = {}
var _commit_receipts: Dictionary = {}
var _command_contracts_by_key: Dictionary = {}
var _next_receipt_sequence: int = 1
var _post_receipt_mutations: Array = []
var _next_mutation_sequence: int = 1
var _journal_projection_cursor: Dictionary = {}
var _suppress_mutation_journal: bool = false
var _domain_owner: RefCounted
var _domain_context: RefCounted
var _domain_definition: GMAbilityDefinition
var _store_replacement_listeners: Array[Callable] = []
var _atomic_restore_participants: Array[Dictionary] = []

func _init(p_seed: int = 1, p_world_id: String = "gm.simulation.world.default") -> void:
	seed = p_seed
	world_id = p_world_id.strip_edges()
	registry = GMEntityRegistry.new()
	_bind_mutation_observers()
	change_store = GMChangeRecordStore.new()
	event_store = GMEventStore.new(change_store)
	event_store.configure_archive_identity(world_id, 1)
	transaction_coordinator = GMDomainTransactionCoordinator.new()
	domain_host = GMAbilitySystemHost.new()
	_domain_owner = RefCounted.new()
	_domain_context = RefCounted.new()
	_domain_owner.set_meta("gm_id", world_id)
	_domain_context.set_meta("gm_runtime_context", "simulation")
	domain_host.mount(_domain_owner, _domain_context)
	domain_host.configure_fact_pipeline(event_store, change_store, transaction_coordinator)
	scene_bridge = GMSceneBridge.new()

func configure_domain(resolver: Object, metadata: Dictionary = {}) -> Dictionary:
	if resolver == null or not is_instance_valid(resolver):
		return {"ok": false, "code": "world.resolver_missing", "reason_zh": "后台领域提交缺少有效 Resolver。"}
	for method_name in ["preflight_transaction", "reserve_transaction", "commit_transaction", "rollback_transaction"]:
		if not resolver.has_method(method_name): return {"ok": false, "code": "world.resolver_interface_missing", "reason_zh": "Resolver 缺少05A事务接口：%s" % method_name}
	domain_resolver = resolver
	domain_metadata = GMStableData.clone(metadata)
	if not domain_metadata.has("resolver_id") and resolver.get("resolver_id") != null: domain_metadata["resolver_id"] = str(resolver.get("resolver_id"))
	var resolver_id := str(domain_metadata.get("resolver_id", ""))
	var ability_id := str(domain_metadata.get("ability_id", "gm.ability.simulation.command"))
	var fact_type := str(domain_metadata.get("fact_type", "gm.fact.simulation.command.committed"))
	if resolver_id.is_empty() or ability_id.is_empty() or fact_type.is_empty():
		return {"ok": false, "code": "world.domain_metadata_invalid", "reason_zh": "后台领域Host配置缺少resolver_id、ability_id或fact_type。"}
	var service_result := domain_host.set_domain_service(resolver_id, resolver)
	if not service_result.ok: return service_result
	_domain_definition = GMAbilityDefinition.new()
	_domain_definition.ability_id = ability_id
	_domain_definition.display_name_zh = "后台模拟领域命令"
	_domain_definition.executor_service_id = resolver_id
	_domain_definition.resolver_id = resolver_id
	_domain_definition.fact_type = fact_type
	_domain_definition.fact_source_system = str(domain_metadata.get("source_system", "gm.simulation"))
	_domain_definition.fact_tags = PackedStringArray(domain_metadata.get("fact_tags", []))
	_domain_definition.fact_visibility = GMStableData.clone(domain_metadata.get("fact_visibility", {"public": false, "witnesses": []}))
	var grant := domain_host.grant_ability(_domain_definition, "gm.simulation.domain")
	if not grant.ok: return {"ok": false, "code": str(grant.get("code", "world.domain_grant_failed")), "reason_zh": str(grant.get("reason_zh", "后台领域能力授予失败。")), "details": grant}
	return {"ok": true, "resolver_id": resolver_id, "ability_id": ability_id, "metadata": domain_metadata.duplicate(true), "host_identity_version": GMAbilityActivationRequest.IDENTITY_VERSION}

func register_entity(entity_id: String, kind: String = "generic", data: Dictionary = {}, resolution: String = GMResolutionState.ACTIVE, flags: Dictionary = {}) -> Dictionary:
	var normalized := SPATIAL_CONTRIBUTOR.normalize_entity_data(data)
	if not normalized.ok: return normalized
	if bool(normalized.get("has_position", false)):
		if not has_active_spatial_backend(): return {"ok": false, "code": "spatial.backend.missing", "reason_zh": "实体包含空间位置，但当前世界没有激活空间执行后端。"}
		var surface_result = spatial_runtime_context.query_spatial(SPATIAL_CAPABILITIES.FIND_SURFACE, "find_surface", [normalized.position])
		if not surface_result.ok: return surface_result
	return registry.register_entity(entity_id, kind, normalized.data, resolution, flags)

func configure_spatial_runtime_context(context: Object) -> Dictionary:
	if context == null or not is_instance_valid(context) or not context.has_method("has_active_spatial_backend"):
		return {"ok": false, "code": "spatial.context_invalid", "reason_zh": "世界空间上下文必须是现有GMRuntimeContext。"}
	spatial_runtime_context = context
	return {"ok": true, "active": has_active_spatial_backend()}

func has_active_spatial_backend() -> bool:
	return spatial_runtime_context != null and is_instance_valid(spatial_runtime_context) and bool(spatial_runtime_context.call("has_active_spatial_backend"))

func set_entity_spatial_position(entity_id: String, position, expected_version: int = -1) -> Dictionary:
	if not has_active_spatial_backend(): return {"ok": false, "code": "spatial.backend.missing", "reason_zh": "设置实体空间位置需要已激活的空间执行后端。"}
	var parsed := SPATIAL_CONTRIBUTOR.PLANAR_POSITION.from_native(position)
	if not parsed.ok: return parsed
	var surface_result = spatial_runtime_context.query_spatial(SPATIAL_CAPABILITIES.FIND_SURFACE, "find_surface", [parsed.position])
	if not surface_result.ok: return surface_result
	return registry.apply_patch(entity_id, {SPATIAL_CONTRIBUTOR.POSITION_KEY: parsed.position.to_native()}, expected_version, "gm.spatial.position")

func get_entity_spatial_position(entity_id: String):
	return SPATIAL_CONTRIBUTOR.position_for_record(registry.get_record(entity_id))

func register_system(system: GMSimulationSystem) -> Dictionary:
	if system == null or not is_instance_valid(system): return {"ok": false, "code": "world.system_missing", "reason_zh": "不能注册空后台系统。"}
	if system.system_id.is_empty(): return {"ok": false, "code": "world.system_id_missing", "reason_zh": "后台系统缺少稳定 system_id。"}
	if systems.has(system.system_id): return {"ok": false, "code": "world.system_duplicate", "reason_zh": "后台系统 ID 重复：%s" % system.system_id}
	systems[system.system_id] = system
	return {"ok": true, "system": system.descriptor()}

func add_store(store: GMStore) -> Dictionary:
	if store == null or not is_instance_valid(store): return {"ok": false, "code": "world.store_missing", "reason_zh": "不能注册空 Store。"}
	if store.store_id.is_empty() or stores.has(store.store_id): return {"ok": false, "code": "world.store_duplicate", "reason_zh": "Store ID 缺失或重复：%s" % store.store_id}
	if not _commit_receipts.is_empty(): return {"ok": false, "code": "world.store_configuration_locked", "reason_zh": "已有提交收据后不能改变Store集合。"}
	stores[store.store_id] = store
	_bind_store_observer(store)
	return {"ok": true, "store_id": store.store_id}

func register_store_replacement_listener(callback: Callable) -> Dictionary:
	if not callback.is_valid(): return {"ok": false, "code": "world.store_listener_invalid", "reason_zh": "Store替换监听器无效。"}
	if not _store_replacement_listeners.has(callback): _store_replacement_listeners.append(callback)
	return {"ok": true, "listener_count": _store_replacement_listeners.size()}

func unregister_store_replacement_listener(callback: Callable) -> void:
	_store_replacement_listeners.erase(callback)

func register_atomic_restore_participant(prepare_callback: Callable, commit_callback: Callable) -> Dictionary:
	if not prepare_callback.is_valid(): return {"ok": false, "code": "world.restore_prepare_invalid", "reason_zh": "原子恢复贡献者缺少有效prepare回调。"}
	if not commit_callback.is_valid(): return {"ok": false, "code": "world.restore_commit_invalid", "reason_zh": "原子恢复贡献者缺少有效commit回调。"}
	_atomic_restore_participants.append({"prepare": prepare_callback, "commit": commit_callback})
	return {"ok": true, "participant_count": _atomic_restore_participants.size()}

func unregister_atomic_restore_participant(prepare_callback: Callable, commit_callback: Callable) -> void:
	for index in range(_atomic_restore_participants.size() - 1, -1, -1):
		var participant: Dictionary = _atomic_restore_participants[index]
		if participant.get("prepare", Callable()) == prepare_callback and participant.get("commit", Callable()) == commit_callback:
			_atomic_restore_participants.remove_at(index)

func _prepare_atomic_restore_participants(snapshot: Dictionary, staged_stores: Dictionary) -> Dictionary:
	var prepared: Array[Dictionary] = []
	for participant in _atomic_restore_participants.duplicate():
		var prepare_callback: Callable = participant.get("prepare", Callable())
		var raw_result: Variant = prepare_callback.call(snapshot, staged_stores)
		if not raw_result is Dictionary:
			return {"ok": false, "code": "world.restore_contributor_invalid", "reason_zh": "原子恢复贡献者prepare没有返回有效结果。"}
		var result: Dictionary = raw_result
		if not bool(result.get("ok", false)):
			return {"ok": false, "code": "world.restore_contributor_invalid", "reason_zh": "贡献者候选在世界提交前验证失败，世界保持不变。", "details": result}
		if not result.has("prepared"):
			return {"ok": false, "code": "world.restore_contributor_unstaged", "reason_zh": "原子恢复贡献者prepare没有返回暂存状态。"}
		prepared.append({"commit": participant.get("commit", Callable()), "prepared": result.get("prepared")})
	return {"ok": true, "prepared": prepared, "participant_count": prepared.size()}

func _commit_atomic_restore_participants(prepared_result: Dictionary) -> void:
	# Every callback receives a state that passed detached semantic validation.
	# Commits are direct swaps/assignments and intentionally have no recovery path.
	for participant in prepared_result.get("prepared", []):
		var commit_callback: Callable = participant.get("commit", Callable())
		commit_callback.call(participant.get("prepared"), self)

func _notify_store_replaced() -> void:
	for callback in _store_replacement_listeners.duplicate():
		if callback.is_valid(): callback.call(self)
		else: _store_replacement_listeners.erase(callback)

func set_world_budget(units: int) -> void:
	world_budget_units = maxi(units, 0)

func capture_snapshot(p_phase: String = "read") -> GMWorldSnapshot:
	phase = p_phase
	var world_state := {"world_id": world_id, "phase": p_phase}
	if has_active_spatial_backend(): world_state["spatial"] = SPATIAL_CONTRIBUTOR.context_state(spatial_runtime_context)
	last_snapshot = GMWorldSnapshot.from_registry(registry, tick, seed, p_phase, world_state)
	return last_snapshot

func run_tick() -> Dictionary:
	var snapshot := capture_snapshot("tick.%06d" % tick)
	var buffers: Array = []
	var system_results: Array = []
	for system in _ordered_systems():
		var current: GMSimulationSystem = system
		if not current.is_due(snapshot.tick):
			system_results.append({"system_id": current.system_id, "skipped": true, "reason": "frequency"})
			continue
		var buffer := GMCommandBuffer.new(current.system_id, snapshot, current.stage, current.priority, current.budget_units)
		var run_result: Dictionary
		var isolated := false
		var raw_result: Variant = current.run(snapshot, buffer)
		if raw_result is Dictionary:
			run_result = raw_result.duplicate(true)
		else:
			run_result = {"ok": false, "code": "system.exception", "reason_zh": "系统返回值无效，已隔离该系统。"}
			isolated = true
		if not bool(run_result.get("ok", true)):
			isolated = true
			# 系统失败只隔离自身的缓冲，不影响其他系统。
			buffer = GMCommandBuffer.new(current.system_id, snapshot, current.stage, current.priority, current.budget_units)
		var closed := buffer.close()
		if not isolated: buffers.append(buffer)
		system_results.append({"system_id": current.system_id, "ok": not isolated, "isolated": isolated, "result": run_result, "buffer": closed})
	var merge := merge_command_buffers(snapshot, buffers)
	var commit := commit_merge(snapshot, merge)
	var record := {"tick": snapshot.tick, "snapshot_id": snapshot.snapshot_id, "systems": system_results, "merge": merge, "commit": commit}
	tick_history.append(GMStableData.clone(record))
	tick += 1
	return {"ok": bool(commit.get("ok", false)) and bool(merge.get("ok", false)), "tick": snapshot.tick, "snapshot": snapshot.to_dict(), "systems": system_results, "merge": merge, "commit": commit}

func merge_command_buffers(snapshot: GMWorldSnapshot, buffers: Array) -> Dictionary:
	if snapshot == null: return {"ok": false, "code": "merge.snapshot_missing", "reason_zh": "合并缺少快照。", "accepted": [], "rejected": [], "conflicts": []}
	var integrity := snapshot.verify_integrity()
	if not integrity.ok: return {"ok": false, "code": "merge.snapshot_integrity_failed", "reason_zh": "快照完整性失败，命令合并已关闭式拒绝。", "details": integrity, "accepted": [], "rejected": [], "conflicts": []}
	if last_snapshot != null and snapshot.snapshot_id != last_snapshot.snapshot_id:
		return {"ok": false, "code": "merge.stale_snapshot", "reason_zh": "命令使用了过期快照，不能合并。", "expected_snapshot_id": last_snapshot.snapshot_id, "actual_snapshot_id": snapshot.snapshot_id, "accepted": [], "rejected": [], "conflicts": []}
	var commands: Array = []
	for buffer_value in buffers:
		if buffer_value is GMCommandBuffer:
			if buffer_value.snapshot_id != snapshot.snapshot_id:
				for stale in buffer_value.get_commands(): commands.append({"stale": true, "command": stale})
			else:
				for command in buffer_value.get_commands(): commands.append(command)
		elif buffer_value is Array:
			for command in buffer_value: commands.append(command)
	commands.sort_custom(func(left, right): return _command_less(left, right))
	var accepted: Array = []
	var rejected: Array = []
	var conflicts: Array = []
	var seen_idempotency: Dictionary = {}
	var claimed_keys: Dictionary = {}
	var candidates: Array = []
	for command_value in commands:
		if not command_value is Dictionary: rejected.append({"code": "merge.command_invalid", "reason_zh": "命令不是对象。"}); continue
		var command: Dictionary = command_value
		if bool(command.get("stale", false)):
			rejected.append({"command": command.get("command", {}), "code": "merge.stale_snapshot", "reason_zh": "命令缓冲绑定了过期快照。"})
			continue
		var validation := _validate_command(command, snapshot)
		if not validation.ok:
			rejected.append({"command": GMStableData.clone(command), "code": validation.code, "reason_zh": validation.reason_zh, "errors": validation.get("errors", [])})
			continue
		var idempotency_key := str(command.get("idempotency_key", ""))
		if seen_idempotency.has(idempotency_key):
			var previous: Dictionary = seen_idempotency[idempotency_key]
			if GMStableData.canonical_json(previous) == GMStableData.canonical_json(command):
				rejected.append({"command": GMStableData.clone(command), "code": "merge.duplicate_command", "reason_zh": "重复命令被幂等跳过。", "duplicate_of": previous.get("command_id", "")})
			else:
				var duplicate_conflict := {"code": "merge.duplicate_conflict", "reason_zh": "同一幂等键对应不同命令。", "idempotency_key": idempotency_key, "first": previous.get("command_id", ""), "second": command.get("command_id", "")}
				conflicts.append(duplicate_conflict)
				rejected.append({"command": GMStableData.clone(command), "code": duplicate_conflict.code, "reason_zh": duplicate_conflict.reason_zh})
			continue
		seen_idempotency[idempotency_key] = command
		candidates.append(command)
	for command in candidates:
		var loser := false
		for write_key_value in command.get("write_keys", []):
			var write_key := str(write_key_value)
			if claimed_keys.has(write_key):
				loser = true
				var winner: Dictionary = claimed_keys[write_key]
				var conflict := {"write_key": write_key, "winner": winner.get("command_id", ""), "loser": command.get("command_id", ""), "winner_system": winner.get("system_id", ""), "loser_system": command.get("system_id", ""), "code": "merge.write_conflict", "reason_zh": "多个系统对同一写入键产生冲突，按确定性顺序保留先者。"}
				conflicts.append(conflict)
		for write_key_value in command.get("write_keys", []):
			var write_key := str(write_key_value)
			if not claimed_keys.has(write_key): claimed_keys[write_key] = command
		if loser:
			rejected.append({"command": GMStableData.clone(command), "code": "merge.write_conflict", "reason_zh": "命令写入键与先前系统冲突。"})
		else: accepted.append(command)
	var budget_used := 0
	var budget_rejected: Array = []
	var budget_limit := world_budget_units
	if budget_limit > 0:
		var budget_accepted: Array = []
		for command in accepted:
			var cost := maxi(int(command.get("cost", 1)), 1)
			if budget_used + cost > budget_limit:
				var row := {"command": GMStableData.clone(command), "code": "merge.budget_exceeded", "reason_zh": "世界提交预算已用尽，命令被隔离。", "budget": budget_limit, "used": budget_used, "cost": cost}
				budget_rejected.append(row)
			else:
				budget_used += cost
				budget_accepted.append(command)
		accepted = budget_accepted
	rejected.append_array(budget_rejected)
	last_merge = {"ok": true, "snapshot_id": snapshot.snapshot_id, "input_command_count": commands.size(), "accepted": GMStableData.clone(accepted), "rejected": GMStableData.clone(rejected), "conflicts": GMStableData.clone(conflicts), "budget_limit": budget_limit, "budget_used": budget_used}
	return last_merge

func commit_merge(snapshot: GMWorldSnapshot, merge: Dictionary) -> Dictionary:
	if snapshot == null or not bool(merge.get("ok", false)): return {"ok": false, "code": "commit.merge_invalid", "reason_zh": "提交缺少有效的确定性合并结果。", "results": []}
	var integrity := snapshot.verify_integrity()
	if not integrity.ok: return {"ok": false, "code": "commit.snapshot_integrity_failed", "reason_zh": "快照完整性失败，提交已关闭式拒绝。", "details": integrity, "results": []}
	if str(merge.get("snapshot_id", "")) != snapshot.snapshot_id: return {"ok": false, "code": "commit.stale_merge", "reason_zh": "合并结果与快照不匹配。", "results": []}
	var receipt_contract := _commit_receipt_contract(snapshot, merge)
	var receipt_id := GMReceiptEnvelopeAdapter.receipt_id_for_contract(receipt_contract)
	if _commit_receipts.has(receipt_id):
		var replay: Dictionary = GMStableData.clone(_commit_receipts[receipt_id].get("result", {}))
		replay["idempotent_replay"] = true
		replay["receipt_id"] = receipt_id
		return replay
	var accepted: Array = merge.get("accepted", [])
	var pending_contracts: Dictionary = {}
	for command_value in accepted:
		if not command_value is Dictionary: return {"ok": false, "code": "commit.command_invalid", "reason_zh": "提交合同包含无效命令。", "results": []}
		var command: Dictionary = command_value
		var exact_key := str(command.get("idempotency_key", ""))
		var contract_digest := _command_contract_digest(command)
		if _command_contracts_by_key.has(exact_key) and str(_command_contracts_by_key[exact_key]) != contract_digest:
			return {"ok": false, "code": "commit.idempotency_conflict", "reason_zh": "同一精确幂等键对应不同提交合同，已关闭式拒绝。", "idempotency_key": exact_key, "results": []}
		if pending_contracts.has(exact_key) and str(pending_contracts[exact_key]) != contract_digest:
			return {"ok": false, "code": "commit.idempotency_conflict", "reason_zh": "同一merge内精确幂等键合同冲突。", "idempotency_key": exact_key, "results": []}
		pending_contracts[exact_key] = contract_digest
	if _commit_receipts.size() >= maxi(max_commit_receipts, 1):
		return {"ok": false, "code": "commit.receipt_ledger_full", "reason_zh": "提交收据账本达到有界容量；必须显式存档并清理。", "receipt_limit": maxi(max_commit_receipts, 1), "results": []}
	var results: Array = []
	var all_ok := true
	var before_state := _receipt_state_projection()
	_suppress_mutation_journal = true
	for index in accepted.size():
		var command: Dictionary = accepted[index]
		var result := _commit_command(command, snapshot, index)
		results.append(result)
		if not bool(result.get("ok", false)): all_ok = false
	_suppress_mutation_journal = false
	var identity_projection := _result_identity_projection(results)
	var final_result := {"ok": all_ok, "accepted_count": accepted.size(), "results": results, "event_count": event_store.get_record_count(), "change_count": change_store.get_record_count(), "cue_count": int(identity_projection.get("cue_count", 0)), "abstract_count": abstract_commits.size(), "receipt_id": receipt_id, "idempotent_replay": false}
	for exact_key in pending_contracts: _command_contracts_by_key[exact_key] = pending_contracts[exact_key]
	var after_state := _receipt_state_projection(identity_projection)
	var envelope := GMReceiptEnvelopeAdapter.create_envelope(receipt_id, _next_receipt_sequence, world_id, commit_receipt_epoch, receipt_contract, final_result, before_state, after_state, identity_projection)
	_commit_receipts[receipt_id] = envelope
	_next_receipt_sequence += 1
	_journal_projection_cursor = GMStableData.clone(after_state)
	return final_result

func commit_receipt_ledger_snapshot() -> Dictionary:
	var rows: Array = []
	for receipt in _commit_receipts.values(): rows.append(GMStableData.clone(receipt))
	rows.sort_custom(func(left, right): return int(left.get("receipt_sequence", 0)) < int(right.get("receipt_sequence", 0)))
	return {"schema": COMMIT_RECEIPT_SCHEMA, "epoch": commit_receipt_epoch, "entry_count": rows.size(), "limit": maxi(max_commit_receipts, 1), "receipts": rows, "command_contracts": GMStableData.clone(_command_contracts_by_key)}

func archive_and_clear_commit_receipts(archive_digest: String) -> Dictionary:
	var ledger := commit_receipt_ledger_snapshot()
	var expected := _persistence_digest(ledger)
	if archive_digest != expected:
		return {"ok": false, "code": "commit.receipt_archive_digest_mismatch", "reason_zh": "只有已确认持久化的完整收据账本才能清理。", "expected_digest": expected}
	var cleared := _commit_receipts.size()
	_commit_receipts.clear()
	_command_contracts_by_key.clear()
	_post_receipt_mutations.clear()
	commit_receipt_epoch += 1
	_next_receipt_sequence = 1
	_next_mutation_sequence = 1
	_journal_projection_cursor = {}
	return {"ok": true, "cleared": cleared, "new_epoch": commit_receipt_epoch, "archive_digest": expected}

func set_entity_resolution(entity_id: String, resolution: String, expected_version: int = -1) -> Dictionary:
	return registry.set_resolution(entity_id, resolution, expected_version)

func save_snapshot() -> Dictionary:
	var spatial_validation := SPATIAL_CONTRIBUTOR.validate_registry(registry, spatial_runtime_context)
	if not spatial_validation.ok: return {"ok": false, "code": "spatial.snapshot.invalid", "reason_zh": str(spatial_validation.get("reason_zh", "实体空间位置校验失败。")), "details": spatial_validation}
	if not spatial_validation.positions.is_empty() and not has_active_spatial_backend():
		return {"ok": false, "code": "spatial.backend.missing", "reason_zh": "空间实体存在但没有激活后端，拒绝生成不完整存档。"}
	var store_snapshots := {}
	for store_id in stores.keys():
		var store: GMStore = stores[store_id]
		store_snapshots[store_id] = store.snapshot()
	var result := {
		"schema_version": SCHEMA_VERSION,
		"world_id": world_id,
		"seed": seed,
		"tick": tick,
		"phase": phase,
		"world_budget_units": world_budget_units,
		"registry": registry.snapshot(),
		"event_store": event_store.snapshot(),
		"stores": store_snapshots,
		"abstract_commits": GMStableData.clone(abstract_commits),
		"commit_receipts": commit_receipt_ledger_snapshot(),
		"post_receipt_journal": GMWorldProjectionStrategy.build_journal(world_id, commit_receipt_epoch, _post_receipt_mutations),
		"pending_merge": GMStableData.clone(last_merge),
		"scheduler_debt": GMStableData.clone(scheduler_debt),
		"tick_history": GMStableData.clone(tick_history)
	}
	if has_active_spatial_backend(): result["spatial_state"] = spatial_runtime_context.call("spatial_snapshot_state")
	return result

func save_to_file(path: String) -> Dictionary:
	var snapshot := save_snapshot()
	if snapshot.has("ok") and not bool(snapshot.get("ok", false)): return snapshot
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return {"ok": false, "code": "world.save_open_failed", "reason_zh": "无法打开世界存档写入路径。", "path": path}
	file.store_string(JSON.stringify(GMStableData.canonical(snapshot), "\t") + "\n")
	file.close()
	return {"ok": true, "path": path, "digest": GMStableData.digest(snapshot), "tick": tick, "event_count": event_store.get_record_count()}

func load_snapshot(value: Dictionary) -> Dictionary:
	return GMAtomicWorldLoadCoordinator.new().load(self, value)
func load_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok": false, "code": "world.save_missing", "reason_zh": "世界存档文件不存在。", "path": path}
	var text := FileAccess.get_file_as_string(path)
	var value: Variant = JSON.parse_string(text)
	if not value is Dictionary: return {"ok": false, "code": "world.save_json_invalid", "reason_zh": "世界存档不是有效 JSON。"}
	return load_snapshot(value)

func deterministic_digest() -> String:
	return GMStableData.digest({"world": save_snapshot(), "history": tick_history})

func summary() -> Dictionary:
	return {"world_id": world_id, "seed": seed, "tick": tick, "phase": phase, "entity_count": registry.all_entity_ids().size(), "system_count": systems.size(), "event_count": event_store.get_record_count(), "change_count": change_store.get_record_count(), "abstract_count": abstract_commits.size(), "deterministic_digest": deterministic_digest()}

func _commit_command(command: Dictionary, snapshot: GMWorldSnapshot, index: int) -> Dictionary:
	var operation := str(command.get("operation", ""))
	var entity_id := str(command.get("entity_id", ""))
	var expected_version := int(command.get("expected_version", -1))
	match operation:
		"state_patch":
			var payload: Dictionary = command.get("payload", {}) if command.get("payload", {}) is Dictionary else {}
			var patch: Dictionary = payload.get("patch", {}) if payload.get("patch", {}) is Dictionary else payload
			return registry.apply_patch(entity_id, patch, expected_version, str(command.get("system_id", "")))
		"set_resolution":
			var resolution_payload: Dictionary = command.get("payload", {}) if command.get("payload", {}) is Dictionary else {}
			return registry.set_resolution(entity_id, str(resolution_payload.get("resolution", "")), expected_version)
		"abstract":
			var abstract_payload: Dictionary = command.get("payload", {}) if command.get("payload", {}) is Dictionary else {}
			var allowed := GMResolutionState.command_allowed(str(command.get("resolution", "")), operation, abstract_payload)
			if not allowed.ok: return allowed
			var abstract_id := "gm.abstract.%06d.%04d" % [snapshot.tick, index + 1]
			var abstract_record := {"abstract_id": abstract_id, "tick": snapshot.tick, "entity_id": entity_id, "resolution": command.get("resolution", ""), "system_id": command.get("system_id", ""), "kind": abstract_payload.get("abstract_kind", ""), "payload": GMStableData.clone(abstract_payload)}
			abstract_commits.append(abstract_record)
			registry.increment_abstract_count(entity_id)
			return {"ok": true, "operation": operation, "abstract_id": abstract_id, "entity_id": entity_id}
		"domain":
			return _commit_domain_command(command, snapshot)
		_:
			return {"ok": false, "code": "commit.operation_invalid", "reason_zh": "后台命令操作类型未注册。", "operation": operation}

func _commit_domain_command(command: Dictionary, snapshot: GMWorldSnapshot) -> Dictionary:
	if domain_resolver == null or not is_instance_valid(domain_resolver): return {"ok": false, "code": "commit.resolver_missing", "reason_zh": "后台领域命令缺少 Resolver，未产生事实。"}
	var payload: Dictionary = command.get("payload", {}) if command.get("payload", {}) is Dictionary else {}
	var event_data: Dictionary = payload.get("event_data", {}) if payload.get("event_data", {}) is Dictionary else {}
	event_data = event_data.duplicate(true)
	event_data["source_id"] = str(event_data.get("source_id", command.get("entity_id", "")))
	if not event_data.has("target_id") and payload.has("target_id"): event_data["target_id"] = str(payload.get("target_id", ""))
	if not event_data.has("expected_versions"): event_data["expected_versions"] = payload.get("expected_versions", {}) if payload.get("expected_versions", {}) is Dictionary else {}
	if not event_data.has("time"): event_data["time"] = "tick:%06d" % snapshot.tick
	if not event_data.has("timestamp_usec"): event_data["timestamp_usec"] = snapshot.tick * 1000000
	var idempotency_key := str(command.get("idempotency_key", ""))
	var ability_id := str(payload.get("ability_id", domain_metadata.get("ability_id", "gm.ability.simulation.command")))
	if _domain_definition == null or _domain_definition.ability_id != ability_id:
		return {"ok": false, "code": "commit.ability_not_configured", "reason_zh": "领域命令必须使用已配置的Host能力公开入口。", "ability_id": ability_id}
	var request := GMAbilityActivationRequest.new(domain_host, ability_id, "", GMTargetData.from_location(Vector2.ZERO), event_data, "gm.simulation.system.%s" % str(command.get("system_id", "")), {"mode": "simulation", "tick": snapshot.tick}, idempotency_key)
	var request_material := {"world_id": world_id, "snapshot_id": snapshot.snapshot_id, "command": _command_contract(command), "ability_id": ability_id}
	request.request_id = "gmreq-simulation-v2-%s" % GMStableData.digest(request_material)
	request.created_at_usec = snapshot.tick * 1000000
	request.causal_chain = GMCausalChain.from_activation_request(request)
	var result: Variant = domain_host.activate_typed(request)
	if result is GMCommittedFactResult:
		var committed: GMCommittedFactResult = result
		var fact := committed.fact_event
		if fact == null or not event_store.contains_id(fact.event_id): return {"ok": false, "code": "commit.event_store_missing", "reason_zh": "05A 返回Committed Fact但EventStore未观察到事实。"}
		return {"ok": true, "operation": "domain", "result_kind": GMCommittedFactResult.RESULT_KIND, "idempotent": committed.idempotent, "fact_event_id": fact.event_id, "fact": fact.to_dict(), "committed": committed.to_dict(), "ability_instance_id": fact.ability_instance_id, "transaction_id": fact.transaction_id, "causal_chain": committed.chain.to_dict() if committed.chain != null else {}, "cues": committed.cues.duplicate(true)}
	if result is GMBlockedResult:
		var blocked: GMBlockedResult = result
		return {"ok": false, "operation": "domain", "result_kind": GMBlockedResult.RESULT_KIND, "code": blocked.error_code, "reason_zh": blocked.reason_zh, "blocked": blocked.to_dict()}
	return {"ok": false, "code": "commit.result_invalid", "reason_zh": "05A Resolver 返回了未知结果类型。"}

func _validate_command(command: Dictionary, snapshot: GMWorldSnapshot) -> Dictionary:
	if str(command.get("schema_version", "")) != "gm.command.v1": return {"ok": false, "code": "merge.command_schema_invalid", "reason_zh": "命令 Schema 无效。"}
	if str(command.get("snapshot_id", "")) != snapshot.snapshot_id: return {"ok": false, "code": "merge.stale_snapshot", "reason_zh": "命令来自过期快照。"}
	var entity_id := str(command.get("entity_id", ""))
	if not snapshot.has_entity(entity_id): return {"ok": false, "code": "merge.entity_invalid", "reason_zh": "命令目标实体不存在。", "entity_id": entity_id}
	if str(command.get("resolution", "")) != snapshot.resolution_for(entity_id): return {"ok": false, "code": "merge.resolution_stale", "reason_zh": "命令声明的分辨率与快照不一致。", "entity_id": entity_id}
	var stable := GMStableData.validate(command)
	if not stable.ok: return {"ok": false, "code": "merge.command_data_invalid", "reason_zh": "命令包含不可序列化数据。", "errors": stable.errors}
	var resolution_check := GMResolutionState.command_allowed(str(command.get("resolution", "")), str(command.get("operation", "")), command.get("payload", {}) if command.get("payload", {}) is Dictionary else {})
	if not resolution_check.ok: return resolution_check
	return {"ok": true}

func _commit_receipt_contract(snapshot: GMWorldSnapshot, merge: Dictionary) -> Dictionary:
	return {
		"schema": COMMIT_RECEIPT_SCHEMA,
		"epoch": commit_receipt_epoch,
		"world_id": world_id,
		"snapshot": snapshot.to_dict(),
		"merge": GMStableData.clone(merge),
		"commands": _command_contracts(merge.get("accepted", []) if merge.get("accepted", []) is Array else []),
	}

func _command_contracts(commands: Array) -> Array:
	var result: Array = []
	for command in commands:
		if command is Dictionary: result.append(_command_contract(command))
	return result

func _command_contract(command: Dictionary) -> Dictionary:
	var result: Dictionary = GMStableData.clone(command)
	# Transport/order fields do not define business intent. Exact idempotency key,
	# payload, write set, resolution, version and originating system do.
	for field_name in ["command_id", "sequence"]: result.erase(field_name)
	return result

func _command_contract_digest(command: Dictionary) -> String:
	return GMReceiptEnvelopeAdapter.command_contract_digest(command)

func _receipt_envelope_digest(envelope: Dictionary) -> String:
	return GMReceiptEnvelopeAdapter.envelope_digest(envelope)

func _receipt_state_projection(extra_identity: Dictionary = {}) -> Dictionary:
	var cue_state := GMWorldProjectionStrategy.cue_projection(_receipt_rows(), extra_identity)
	return GMWorldProjectionStrategy.project(registry, event_store, stores, abstract_commits, cue_state)


func _result_identity_projection(results: Array) -> Dictionary:
	return GMReceiptEnvelopeAdapter.result_identity_projection(results)


func _receipt_rows() -> Array:
	var rows: Array = []
	for receipt in _commit_receipts.values(): rows.append(GMStableData.clone(receipt))
	rows.sort_custom(func(left, right): return int(left.get("receipt_sequence", 0)) < int(right.get("receipt_sequence", 0)))
	return rows


func _bind_mutation_observers() -> void:
	var registry_callback := Callable(self, "_on_component_mutation")
	if registry != null and not registry.mutation_committed.is_connected(registry_callback):
		registry.mutation_committed.connect(registry_callback)
	for store_value in stores.values():
		if store_value is GMStore: _bind_store_observer(store_value)


func _bind_store_observer(store: GMStore) -> void:
	var callback := Callable(self, "_on_component_mutation")
	if not store.mutation_committed.is_connected(callback): store.mutation_committed.connect(callback)


func _on_component_mutation(change: Dictionary) -> void:
	if _suppress_mutation_journal: return
	var current_projection := _receipt_state_projection()
	if _commit_receipts.is_empty():
		_journal_projection_cursor = current_projection
		return
	var rows := _receipt_rows()
	var base_row: Dictionary = rows.back()
	if _journal_projection_cursor.is_empty(): _journal_projection_cursor = GMStableData.clone(base_row.after_state)
	var previous_digest := GMWorldProjectionStrategy.journal_genesis(world_id, commit_receipt_epoch) if _post_receipt_mutations.is_empty() else str(_post_receipt_mutations.back().get("record_digest", ""))
	var entry := GMWorldProjectionStrategy.make_journal_entry(
		world_id,
		commit_receipt_epoch,
		_next_mutation_sequence,
		int(base_row.receipt_sequence),
		str(base_row.receipt_id),
		previous_digest,
		str(change.get("component_kind", "")),
		str(change.get("component_id", "")),
		str(change.get("operation", "")),
		change.get("before_component", {}) if change.get("before_component", {}) is Dictionary else {},
		change.get("after_component", {}) if change.get("after_component", {}) is Dictionary else {},
		_journal_projection_cursor,
		current_projection
	)
	_post_receipt_mutations.append(entry)
	_next_mutation_sequence += 1
	_journal_projection_cursor = current_projection

func _require_exact_fields(value: Dictionary, expected_fields: Array) -> Dictionary:
	var actual: Array[String] = []
	for key in value.keys(): actual.append(str(key))
	actual.sort()
	var expected: Array[String] = []
	for key in expected_fields: expected.append(str(key))
	expected.sort()
	return {"ok": actual == expected, "actual": actual, "expected": expected}

func _object_has_property(value: Object, property_name: String) -> bool:
	for property in value.get_property_list():
		if str(property.get("name", "")) == property_name: return true
	return false

func _persistence_digest(value: Variant) -> String:
	return GMReceiptEnvelopeAdapter.persistence_digest(value)

func _ordered_systems() -> Array:
	var result: Array = []
	for system_id in systems.keys(): result.append(systems[system_id])
	result.sort_custom(func(left, right):
		if left.stage != right.stage: return left.stage < right.stage
		if left.priority != right.priority: return left.priority > right.priority
		return left.system_id < right.system_id
	)
	return result

func _command_less(left: Dictionary, right: Dictionary) -> bool:
	if int(left.get("stage", 0)) != int(right.get("stage", 0)): return int(left.get("stage", 0)) < int(right.get("stage", 0))
	if int(left.get("priority", 0)) != int(right.get("priority", 0)): return int(left.get("priority", 0)) > int(right.get("priority", 0))
	if str(left.get("system_id", "")) != str(right.get("system_id", "")): return str(left.get("system_id", "")) < str(right.get("system_id", ""))
	return int(left.get("sequence", 0)) < int(right.get("sequence", 0))
