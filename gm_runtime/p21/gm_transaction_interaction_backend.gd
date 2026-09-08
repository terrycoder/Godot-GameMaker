class_name GMTransactionInteractionBackend
extends GMInteractionBackend

var resolver: Object
var fact_store: GMFactEventStore
var change_store: GMChangeRecordStore
var coordinator: GMDomainTransactionCoordinator
var host: GMAbilitySystemHost

func _init(p_resolver: Object, p_fact_store: GMFactEventStore = null, p_change_store: GMChangeRecordStore = null, p_coordinator: GMDomainTransactionCoordinator = null, p_host: GMAbilitySystemHost = null) -> void:
	super._init("gm.interaction.backend.transaction")
	resolver = p_resolver
	change_store = p_change_store if p_change_store != null else GMChangeRecordStore.new()
	fact_store = p_fact_store if p_fact_store != null else GMFactEventStore.new(change_store)
	if fact_store.change_store == null: fact_store.change_store = change_store
	coordinator = p_coordinator if p_coordinator != null else GMDomainTransactionCoordinator.new()
	host = p_host if p_host != null else GMAbilitySystemHost.new()

func can_handle(kind: String) -> bool:
	return kind == "transaction"

func submit(request: GMInteractionRequest) -> Variant:
	if resolver == null or not is_instance_valid(resolver): return {"status": "rejected", "code": "interaction.transaction_resolver_missing", "reason_zh": "Transaction Backend未安装P19 Resolver。", "payload": {}}
	var ability_id := str(request.payload.get("ability_id", "gm.ability.p21.transaction"))
	var built := GMP21BackendSupport.build_ability_request(request, ability_id, request.payload, host)
	if not built.ok: return {"status": "rejected", "code": built.get("code", "interaction.transaction_request_invalid"), "reason_zh": built.get("reason_zh", "Transaction请求无效。"), "payload": built}
	var fact_type := str(request.payload.get("fact_type", "gm.fact.p21.interaction"))
	if not fact_type.begins_with("gm.fact."): return {"status": "rejected", "code": "interaction.fact_type_invalid", "reason_zh": "Transaction请求的Fact类型必须使用gm.fact.*。", "payload": {}}
	var resolver_id := str(resolver.get("resolver_id")) if "resolver_id" in resolver else "gm.resolver.p19"
	if resolver_id.is_empty(): resolver_id = "gm.resolver.p19"
	var raw: Variant = coordinator.resolve(built.request, resolver, fact_store, change_store, {"resolver_id": resolver_id, "fact_type": fact_type, "source_system": "gm.p21.interaction", "ability_instance_id": built.ability_instance_id}, built.request.causal_chain)
	return raw
