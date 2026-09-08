class_name GMPlayerShellAbilityBackend
extends GMInteractionBackend

## P25-only bridge: P21 carries a pure request, then this adapter constructs
## the existing GMAbilityActivationRequest with the live resolved target.  It
## owns no ability state or domain result authority.

var host: GMAbilitySystemHost
var target_resolver: Callable

func _init(p_host: GMAbilitySystemHost = null, p_target_resolver: Callable = Callable()) -> void:
	super._init("gm.interaction.backend.p25.ability")
	host = p_host
	target_resolver = p_target_resolver

func can_handle(kind: String) -> bool:
	return kind == "ability"

func submit(request: GMInteractionRequest) -> Variant:
	if host == null or not is_instance_valid(host):
		return {"status": "rejected", "code": "interaction.host_missing", "reason_zh": "玩家外壳交互缺少统一AbilityHost。"}
	var ability_id := str(request.payload.get("ability_id", ""))
	var target_id := str(request.payload.get("target_id", GMP21BackendSupport.ref_id(request.target_ref)))
	if ability_id.is_empty() or target_id.is_empty():
		return {"status": "rejected", "code": "interaction.request_identity_missing", "reason_zh": "交互请求缺少稳定能力或目标身份。"}
	if not target_resolver.is_valid():
		return {"status": "rejected", "code": "interaction.target_resolver_missing", "reason_zh": "玩家外壳交互缺少目标解析器。"}
	var target_value: Variant = target_resolver.call(target_id)
	if target_value == null or not is_instance_valid(target_value):
		return {"status": "blocked", "code": "interaction.target_missing", "reason_zh": "交互目标已离场或不可用。", "payload": {"target_id": target_id}}
	var event_data: Dictionary = request.payload.get("event_data", {}) if request.payload.get("event_data", {}) is Dictionary else {}
	var payload := event_data.duplicate(true)
	payload["source_id"] = GMP21BackendSupport.ref_id(request.source_ref)
	payload["target_id"] = target_id
	var target_data := GMTargetData.from_entity(target_value, target_id)
	var activation := GMAbilityActivationRequest.new(host, ability_id, "", target_data, payload, GMP21BackendSupport.ref_id(request.source_ref), {}, request.idempotency_key)
	return host.activate_typed(activation)
