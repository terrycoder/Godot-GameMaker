class_name GMProcessInteractionBackend
extends GMInteractionBackend

var process_service: GMProcessService
var host: GMAbilitySystemHost

func _init(p_process_service: GMProcessService, p_host: GMAbilitySystemHost = null) -> void:
	super._init("gm.interaction.backend.process")
	process_service = p_process_service
	host = p_host if p_host != null else GMAbilitySystemHost.new()

func can_handle(kind: String) -> bool:
	return kind == "process"

func submit(request: GMInteractionRequest) -> Variant:
	if process_service == null: return {"status": "rejected", "code": "interaction.process_service_missing", "reason_zh": "Process Backend未安装P20 ProcessService。", "payload": {}}
	var payload := request.payload.duplicate(true)
	if not payload.has("process_action"):
		payload["process_action"] = str(payload.get("action", ""))
	var ability_id := str(payload.get("ability_id", "gm.ability.process.p21"))
	var built := GMP21BackendSupport.build_ability_request(request, ability_id, payload, host)
	if not built.ok: return {"status": "rejected", "code": built.get("code", "interaction.process_request_invalid"), "reason_zh": built.get("reason_zh", "Process请求无效。"), "payload": built}
	return process_service.request(built.request)

