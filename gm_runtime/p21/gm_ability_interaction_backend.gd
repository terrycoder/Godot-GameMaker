class_name GMAbilityInteractionBackend
extends GMInteractionBackend

var host: GMAbilitySystemHost

func _init(p_host: GMAbilitySystemHost = null) -> void:
	super._init("gm.interaction.backend.ability")
	host = p_host if p_host != null else GMAbilitySystemHost.new()

func can_handle(kind: String) -> bool:
	return kind == "ability"

func submit(request: GMInteractionRequest) -> Variant:
	var ability_id := str(request.payload.get("ability_id", ""))
	var event_data: Dictionary = request.payload.get("event_data", {}) if request.payload.get("event_data", {}) is Dictionary else {}
	var payload := event_data.duplicate(true)
	for key in request.payload:
		if key not in ["ability_id", "event_data"] and not payload.has(key): payload[key] = request.payload[key]
	var built := GMP21BackendSupport.build_ability_request(request, ability_id, payload, host)
	if not built.ok: return {"status": "rejected", "code": built.get("code", "interaction.ability_request_invalid"), "reason_zh": built.get("reason_zh", "Ability请求无效。"), "payload": built}
	return host.activate_typed(built.request)

