class_name GMProcessSettlementGateway
extends RefCounted

## Narrow completion adapter: a Process may ask the sealed P19 coordinator to
## settle a production transaction, but it never owns transaction lifecycle or
## a second Fact source.

const COMPLETION_KEY_PREFIX := "gm.process.completion."

var coordinator: GMDomainTransactionCoordinator
var resolver: GMP19TransactionResolver
var fact_store: GMFactEventStore
var host: GMAbilitySystemHost

func _init(p_coordinator: GMDomainTransactionCoordinator = null, p_resolver: GMP19TransactionResolver = null, p_fact_store: GMFactEventStore = null, p_host: GMAbilitySystemHost = null) -> void:
	coordinator = p_coordinator
	resolver = p_resolver
	fact_store = p_fact_store
	host = p_host

func validate() -> Dictionary:
	if coordinator == null or resolver == null or fact_store == null or host == null:
		return {"ok": false, "code": "process.settlement_not_configured", "reason_zh": "P19 结算网关未配置。"}
	if fact_store.change_store == null: return {"ok": false, "code": "process.change_store_missing", "reason_zh": "P19 事实Store缺少既有ChangeStore。"}
	return {"ok": true, "resolver_id": resolver.resolver_id, "fact_store": "gm.fact_event_store"}

func settle_p19(instance: GMProcessInstance, definition: GMProcessDefinition) -> Dictionary:
	var configured := validate()
	if not configured.ok: return configured
	if instance == null or definition == null: return {"ok": false, "code": "process.settlement_input_missing", "reason_zh": "P19 完成适配器缺少Process输入。"}
	if definition.completion_kind != "p19_transaction": return {"ok": false, "code": "process.settlement_kind_invalid", "reason_zh": "P19 网关只接受p19_transaction完成类型。"}
	var data := definition.completion_payload.duplicate(true)
	var operation := str(data.get("p19_operation", data.get("inventory_operation", data.get("numeric_operation", ""))))
	if not GMProcessDefinition._stable_id(operation): return {"ok": false, "code": "process.settlement_operation_missing", "reason_zh": "P19 完成请求缺少稳定事务操作。"}
	var target_id := str(data.get("target_id", ""))
	if not GMProcessDefinition._stable_id(target_id): return {"ok": false, "code": "process.settlement_target_missing", "reason_zh": "P19 完成请求必须显式携带稳定目标。"}
	data["process_instance_id"] = instance.instance_id
	var key := COMPLETION_KEY_PREFIX + instance.instance_id
	if data.has("planned_fact_event_id") and not str(data.planned_fact_event_id).begins_with("gm.fact."):
		return {"ok": false, "code": "process.settlement_fact_id_invalid", "reason_zh": "P19 完成事实必须使用gm.fact.*身份。"}
	if not data.has("planned_fact_event_id"):
		data["planned_fact_event_id"] = "gm.fact.process.%s" % instance.instance_id.trim_prefix("gm.process.instance.")
	var request := GMAbilityActivationRequest.new(host, "gm.ability.process.complete", "", null, data, "gm.process.kernel", {}, key)
	request.request_id = "gmreq-process-%s" % key.sha256_text()
	request.created_at_usec = 0
	request.causal_chain = GMCausalChain.from_activation_request(request)
	var request_check := request.validate()
	if not request_check.ok: return request_check
	var ability_instance_id := request.derive_instance_id()
	request.event_data["ability_instance_id"] = ability_instance_id
	var bound := request.causal_chain.bind_ability_instance_identity(ability_instance_id)
	if not bound.ok: return bound
	var linked := request.causal_chain.add_ref(GMCausalRef.ability_instance(ability_instance_id, request.ability_id), [request.request_id])
	if not linked.ok: return linked
	var fact_type := str(data.get("fact_type", "gm.fact.process.completed"))
	if not fact_type.begins_with("gm.fact."): return {"ok": false, "code": "process.settlement_fact_type_invalid", "reason_zh": "P19 完成事实类型必须使用gm.fact.*身份。"}
	var result: Variant = coordinator.resolve(request, resolver, fact_store, fact_store.change_store, {
		"resolver_id": resolver.resolver_id,
		"fact_type": fact_type,
		"source_system": "gm.process.kernel",
		"ability_id": request.ability_id,
		"ability_instance_id": ability_instance_id,
	}, request.causal_chain)
	if result is GMCommittedFactResult:
		return {"ok": true, "kind": "committed_fact", "process_instance_id": instance.instance_id, "fact_event_id": result.fact_event.event_id, "idempotent": result.idempotent, "idempotency_key": key}
	if result is GMBlockedResult:
		return {"ok": false, "code": result.error_code, "reason_zh": result.reason_zh, "kind": "blocked", "details": result.details.duplicate(true), "idempotency_key": key}
	return {"ok": false, "code": "process.settlement_result_invalid", "reason_zh": "P19 结算返回未知结果类型。"}
