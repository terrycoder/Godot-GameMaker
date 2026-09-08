class_name GMP21BackendSupport
extends RefCounted

## Runtime-only bridge helpers. They construct existing GAS requests and bind
## the existing causal-chain prefix; they do not persist any P21 state.

static func build_ability_request(interaction: GMInteractionRequest, ability_id: String, payload: Dictionary, host: GMAbilitySystemHost) -> Dictionary:
	if interaction == null or host == null or not is_instance_valid(host):
		return GMP21Contract.failure("interaction.host_missing", "交互Backend缺少有效AbilityHost。")
	if not GMP21Contract.stable_id(ability_id):
		return GMP21Contract.failure("interaction.ability_id_invalid", "交互Ability ID无效。")
	var source_id := ref_id(interaction.source_ref)
	if not GMP21Contract.stable_id(source_id):
		return GMP21Contract.failure("interaction.source_ref_invalid", "交互源必须能解析为稳定ID。")
	var data := payload.duplicate(true)
	if not data.has("source_id"): data["source_id"] = source_id
	if not data.has("target_id"): data["target_id"] = ref_id(interaction.target_ref)
	var pure_check := GMP21Contract.pure(data, "$.event_data")
	if not pure_check.ok: return pure_check
	var request := GMAbilityActivationRequest.new(host, ability_id, "", null, data, source_id, {}, interaction.idempotency_key)
	var instance_id := request.derive_instance_id()
	request.event_data["ability_instance_id"] = instance_id
	var bound := request.causal_chain.bind_ability_instance_identity(instance_id)
	if not bound.ok: return bound
	var linked := request.causal_chain.add_ref(GMCausalRef.ability_instance(instance_id, ability_id), [request.request_id])
	if not linked.ok: return linked
	return {"ok": true, "request": request, "ability_instance_id": instance_id}

static func ref_id(value: Variant) -> String:
	if value is String: return str(value)
	if value is Dictionary:
		if value.has("id"): return str(value.get("id", ""))
		if value.has("semantic_id"): return str(value.get("semantic_id", ""))
	return ""

static func source_type(payload: Dictionary) -> String:
	var value := str(payload.get("source_type", "player"))
	return value if value in ["player", "ai", "organization", "world_event", "script", "duty_provider"] else ""

