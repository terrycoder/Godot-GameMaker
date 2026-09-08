class_name GMP19RequestAdapter
extends RefCounted

## Shared request-only surface for P19 adapters. Adapters create one
## ActivationRequest and delegate execution to the existing Host entry point;
## they never write a Store or create a second lifecycle.

static func build(host: GMAbilitySystemHost, operation: String, event_data: Dictionary, source_id: String, idempotency_key: String) -> GMAbilityActivationRequest:
		var data := event_data.duplicate(true)
		data["p19_operation"] = operation
		data["p19_adapter_contract"] = "gm.p19.public_adapter.v1"
		if not data.has("source_id"): data["source_id"] = source_id
		return GMAbilityActivationRequest.new(host, "gm.ability.p19.%s" % operation, "", null, data, source_id, {}, idempotency_key)

static func validate_public_target(event_data: Dictionary) -> Dictionary:
		if str(event_data.get("p19_adapter_contract", "")) != "gm.p19.public_adapter.v1": return {"ok": true}
		var raw_target: Variant = event_data.get("target_id", null)
		if typeof(raw_target) != TYPE_STRING or not _stable_id(str(raw_target)):
			return {"ok": false, "code": "p19.adapter_target_invalid", "reason_zh": "P19 公共适配器必须显式提供非空稳定 target_id。", "field": "target_id"}
		return {"ok": true, "target_id": str(raw_target)}

static func _stable_id(value: String) -> bool:
		if value.is_empty() or value != value.strip_edges() or value.length() > 160: return false
		for index in value.length():
			var code := value.unicode_at(index)
			if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code in [46, 95, 45]): return false
		return true

static func execute(host: GMAbilitySystemHost, request: GMAbilityActivationRequest) -> RefCounted:
		if host == null or not is_instance_valid(host):
			return GMBlockedResult.from_failure({"ok": false, "code": "p19.adapter_host_missing", "reason_zh": "P19 适配器执行缺少能力宿主。"}, request, request.causal_chain if request != null else null)
		return host.activate_typed(request)
