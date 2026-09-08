class_name GMTaskInteractionBackend
extends GMInteractionBackend

var task_service: GMTaskService
var host: GMAbilitySystemHost

func _init(p_task_service: GMTaskService, p_host: GMAbilitySystemHost = null) -> void:
	super._init("gm.interaction.backend.task")
	task_service = p_task_service
	host = p_host if p_host != null else GMAbilitySystemHost.new()

func can_handle(kind: String) -> bool:
	return kind == "task"

func submit(request: GMInteractionRequest) -> Variant:
	if task_service == null: return {"status": "rejected", "code": "interaction.task_service_missing", "reason_zh": "Task Backend未安装P16 TaskService。", "payload": {}}
	var operation := str(request.payload.get("operation", request.payload.get("task_operation", "")))
	if operation.is_empty(): return {"status": "rejected", "code": "interaction.task_operation_missing", "reason_zh": "Task交互缺少稳定operation。", "payload": {}}
	var source_id := GMP21BackendSupport.ref_id(request.source_ref)
	var source_type := GMP21BackendSupport.source_type(request.payload)
	if not GMP21Contract.stable_id(source_id) or source_type.is_empty(): return {"status": "rejected", "code": "interaction.task_source_invalid", "reason_zh": "Task交互源类型或稳定ID无效。", "payload": {}}
	var payload := request.payload.duplicate(true)
	payload.erase("operation")
	payload.erase("task_operation")
	payload["target_id"] = GMP21BackendSupport.ref_id(request.target_ref)
	var raw: Variant = task_service.submit_operation(host, operation, payload, source_type, source_id, request.idempotency_key)
	return raw
