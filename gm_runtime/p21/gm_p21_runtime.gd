class_name GMP21Runtime
extends RefCounted

## P21 assembly point. It owns only neutral orchestration objects and delegates
## all authoritative writes to the already sealed P16/P19/P20/GAS services.

var router: GMInteractionRouter
var shop: GMShopService
var task_projection: GMTaskProjectionService
var task_service: GMTaskService
var dialogue_definitions: Dictionary = {}

func _init() -> void:
	router = GMInteractionRouter.new()
	shop = GMShopService.new(router)
	task_projection = GMTaskProjectionService.new()

func install_task_service(service: GMTaskService) -> Dictionary:
	if service == null:
		return GMP21Contract.failure("p21.task_service_missing", "不能安装空P16 TaskService。")
	task_service = service
	task_projection.task_service = service
	return router.register_backend("task", GMTaskInteractionBackend.new(service))

func install_ability_backend(host: GMAbilitySystemHost) -> Dictionary:
	if host == null:
		return GMP21Contract.failure("p21.ability_host_missing", "不能安装空AbilityHost。")
	return router.register_backend("ability", GMAbilityInteractionBackend.new(host))

func install_transaction_backend(resolver: GMDomainResolver, fact_store: GMFactEventStore, change_store: GMChangeRecordStore, coordinator: GMDomainTransactionCoordinator = null, host: GMAbilitySystemHost = null) -> Dictionary:
	if resolver == null or fact_store == null:
		return GMP21Contract.failure("p21.transaction_backend_missing", "P19事务Backend缺少既有Resolver或FactStore。")
	var actual_coordinator := coordinator if coordinator != null else GMDomainTransactionCoordinator.new()
	var actual_host := host if host != null else GMAbilitySystemHost.new()
	return router.register_backend("transaction", GMTransactionInteractionBackend.new(resolver, fact_store, change_store, actual_coordinator, actual_host))

func install_process_backend(service: GMProcessService, host: GMAbilitySystemHost = null) -> Dictionary:
	if service == null:
		return GMP21Contract.failure("p21.process_service_missing", "不能安装空P20 ProcessService。")
	var actual_host := host if host != null else GMAbilitySystemHost.new()
	return router.register_backend("process", GMProcessInteractionBackend.new(service, actual_host))

func register_dialogue(definition: GMDialogueDefinition) -> Dictionary:
	if definition == null:
		return GMP21Contract.failure("p21.dialogue_definition_missing", "不能注册空DialogueDefinition。")
	var checked := definition.validate()
	if not checked.ok:
		return checked
	if dialogue_definitions.has(definition.dialogue_id):
		var existing: GMDialogueDefinition = dialogue_definitions[definition.dialogue_id]
		if existing.to_dict() == definition.to_dict():
			return {"ok": true, "code": "p21.dialogue_definition_unchanged", "duplicate": true}
		if definition.revision <= existing.revision:
			return GMP21Contract.failure("p21.dialogue_definition_conflict", "DialogueDefinition修订号未递增。")
	dialogue_definitions[definition.dialogue_id] = definition
	return {"ok": true, "code": "p21.dialogue_definition_registered", "dialogue_id": definition.dialogue_id, "revision": definition.revision}

func new_dialogue_session(dialogue_id: String, session_id: String, source_ref: Variant, target_ref: Variant) -> Dictionary:
	var definition: GMDialogueDefinition = dialogue_definitions.get(dialogue_id, null)
	if definition == null:
		return GMP21Contract.failure("p21.dialogue_definition_missing", "DialogueDefinition不存在。", {"dialogue_id": dialogue_id})
	var session := GMDialogueSession.new()
	var started := session.configure(definition, session_id, source_ref, target_ref)
	if not started.ok:
		return started
	return {"ok": true, "code": "p21.dialogue_session_created", "session": session, "snapshot": session.snapshot()}

func submit(request_value: Variant) -> GMInteractionResult:
	return router.submit(request_value)

func build_task_projection(task_id: String) -> Dictionary:
	return task_projection.build(task_id)

func snapshot() -> Dictionary:
	var dialogue_rows: Array = []
	for dialogue_id in dialogue_definitions:
		var definition: GMDialogueDefinition = dialogue_definitions[dialogue_id]
		dialogue_rows.append(definition.to_dict())
	dialogue_rows.sort_custom(func(left: Dictionary, right: Dictionary): return str(left.get("dialogue_id", "")) < str(right.get("dialogue_id", "")))
	var backend_kinds: Array[String] = []
	for kind in router.backends.keys(): backend_kinds.append(str(kind))
	backend_kinds.sort()
	return {"schema_version": "gm.p21.runtime.v1", "dialogues": dialogue_rows, "shops": shop.snapshot(), "backend_kinds": backend_kinds}
