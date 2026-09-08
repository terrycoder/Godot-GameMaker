class_name GMInteractionResult
extends RefCounted

## Stable cross-backend result envelope. backend_id is diagnostic only and is
## deliberately excluded from the persisted/public contract.

const SCHEMA_VERSION := GMP21Contract.INTERACTION_RESULT_SCHEMA_VERSION
const FIELDS := ["schema_version", "request_id", "interaction_id", "kind", "status", "code", "reason_zh", "identity", "payload"]

var schema_version := SCHEMA_VERSION
var request_id := ""
var interaction_id := ""
var kind := ""
var status := "rejected"
var code := ""
var reason_zh := ""
var identity: Dictionary = {}
var payload: Dictionary = {}
var backend_id := ""

static func accepted(request: GMInteractionRequest, value: Dictionary = {}, result_code: String = "interaction.accepted", reason: String = "交互请求已受理。") -> GMInteractionResult:
	return _make(request, "accepted", result_code, reason, value)

static func committed(request: GMInteractionRequest, value: Dictionary = {}, result_code: String = "interaction.committed", reason: String = "交互请求已由领域权威提交。") -> GMInteractionResult:
	return _make(request, "committed", result_code, reason, value)

static func blocked(request: GMInteractionRequest, result_code: String, reason: String, value: Dictionary = {}) -> GMInteractionResult:
	return _make(request, "blocked", result_code, reason, value)

static func rejected(request: GMInteractionRequest, result_code: String, reason: String, value: Dictionary = {}) -> GMInteractionResult:
	if request == null:
		return rejected_public(value, result_code, reason, value)
	return _make(request, "rejected", result_code, reason, value)

static func rejected_public(public_value: Variant, result_code: String, reason: String, value: Dictionary = {}, fallback_kind: String = "process", fallback_interaction_id: String = "gm.interaction.rejected") -> GMInteractionResult:
	var kind := fallback_kind if fallback_kind in GMP21Contract.INTERACTION_KINDS else "process"
	var interaction_id := fallback_interaction_id if GMP21Contract.stable_id(fallback_interaction_id) else "gm.interaction.rejected"
	if public_value is Dictionary:
		var candidate_kind: Variant = public_value.get("kind", "")
		if candidate_kind is String and candidate_kind in GMP21Contract.INTERACTION_KINDS:
			kind = str(candidate_kind)
		var candidate_interaction_id: Variant = public_value.get("interaction_id", "")
		if candidate_interaction_id is String and GMP21Contract.stable_id(candidate_interaction_id):
			interaction_id = str(candidate_interaction_id)
	var code := result_code if GMP21Contract.stable_id(result_code) else "interaction.rejected"
	var message := reason.strip_edges() if not reason.strip_edges().is_empty() else "交互请求被拒绝。"
	var public_input: Variant = GMP21Contract.public_identity(public_value)
	var identity_seed := {"schema_version": SCHEMA_VERSION, "kind": kind, "interaction_id": interaction_id, "code": code, "public_input": public_input}
	var request_id := "gm.interaction.rejected.%s" % GMP21Contract.digest(identity_seed)
	var idempotency_key := "gm.interaction.rejected.%s" % GMP21Contract.digest({"request_id": request_id, "identity_seed": identity_seed})
	var payload_check := GMP21Contract.pure(value)
	var payload: Dictionary = value.duplicate(true) if payload_check.ok else {"details": public_input}
	var result := _make(null, "rejected", code, message, payload)
	result.request_id = request_id
	result.interaction_id = interaction_id
	result.kind = kind
	result.identity = {"request_id": request_id, "interaction_id": interaction_id, "idempotency_key": idempotency_key}
	return result

static func _make(request: GMInteractionRequest, p_status: String, p_code: String, p_reason: String, value: Dictionary) -> GMInteractionResult:
	var result := GMInteractionResult.new()
	if request != null:
		result.request_id = request.request_id
		result.interaction_id = request.interaction_id
		result.kind = request.kind
		result.identity = {"request_id": request.request_id, "interaction_id": request.interaction_id, "idempotency_key": request.idempotency_key}
	result.status = p_status
	result.code = p_code
	result.reason_zh = p_reason
	result.payload = value.duplicate(true)
	return result

func is_success() -> bool:
	return status in ["accepted", "committed"]

func is_committed() -> bool:
	return status == "committed"

func validate() -> Dictionary:
	var value := to_dict()
	if not GMP21Contract.exact(value, FIELDS):
		return GMP21Contract.failure("interaction.result_shape_invalid", "InteractionResult字段集合必须精确匹配。")
	if schema_version != SCHEMA_VERSION or not GMP21Contract.stable_id(request_id) or not GMP21Contract.stable_id(interaction_id) or kind not in GMP21Contract.INTERACTION_KINDS or status not in GMP21Contract.INTERACTION_STATUSES or not GMP21Contract.stable_id(code) or reason_zh.strip_edges().is_empty():
		return GMP21Contract.failure("interaction.result_identity_invalid", "InteractionResult的版本、身份、状态、代码或原因无效。")
	if not identity.has("request_id") or str(identity.get("request_id", "")) != request_id or not identity.has("interaction_id") or str(identity.get("interaction_id", "")) != interaction_id or not GMP21Contract.stable_id(str(identity.get("idempotency_key", ""))):
		return GMP21Contract.failure("interaction.result_identity_invalid", "InteractionResult身份必须回显同一请求合同。")
	var pure_check := GMP21Contract.pure({"identity": identity, "payload": payload})
	if not pure_check.ok:
		return pure_check
	return {"ok": true, "code": "interaction.result_valid", "value": value}

func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"request_id": request_id,
		"interaction_id": interaction_id,
		"kind": kind,
		"status": status,
		"code": code,
		"reason_zh": reason_zh,
		"identity": identity.duplicate(true),
		"payload": payload.duplicate(true),
	}

func to_json() -> String:
	return JSON.stringify(GMStableData.persistence_canonical(to_dict()), "", false, true)

static func from_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		value = GMStableData.persistence_canonical(value)
	if not value is Dictionary or not GMP21Contract.exact(value, FIELDS):
		return GMP21Contract.failure("interaction.result_shape_invalid", "InteractionResult字段缺失或包含未知字段。")
	for field in ["schema_version", "request_id", "interaction_id", "kind", "status", "code", "reason_zh"]:
		if typeof(value.get(field)) != TYPE_STRING:
			return GMP21Contract.failure("interaction.result_type_invalid", "InteractionResult字符串字段类型无效。", {"field": field})
	if not value.get("identity") is Dictionary or not value.get("payload") is Dictionary:
		return GMP21Contract.failure("interaction.result_type_invalid", "InteractionResult identity/payload必须是纯对象。")
	var result := GMInteractionResult.new()
	result.schema_version = str(value.get("schema_version", ""))
	result.request_id = str(value.get("request_id", ""))
	result.interaction_id = str(value.get("interaction_id", ""))
	result.kind = str(value.get("kind", ""))
	result.status = str(value.get("status", ""))
	result.code = str(value.get("code", ""))
	result.reason_zh = str(value.get("reason_zh", ""))
	result.identity = value.get("identity", {}).duplicate(true) if value.get("identity", {}) is Dictionary else {}
	result.payload = value.get("payload", {}).duplicate(true) if value.get("payload", {}) is Dictionary else {}
	var checked := result.validate()
	return {"ok": true, "code": "interaction.result_decoded", "result": result} if checked.ok else checked

static func from_json(text: String) -> Dictionary:
	var parsed := GMP21Contract.normalize_json(text, "interaction.result_json_invalid")
	if not parsed.ok:
		return parsed
	return from_dict(parsed.value)

static func from_backend(request: GMInteractionRequest, raw: Variant, p_backend_id: String = "") -> GMInteractionResult:
	if raw is GMInteractionResult:
		var existing: GMInteractionResult = raw
		existing.backend_id = p_backend_id
		return existing if existing.validate().ok else rejected(request, "interaction.backend_result_invalid", "Backend返回的InteractionResult无效。")
	if raw is GMCommittedFactResult:
		var committed_result := committed(request, {"domain_result": raw.to_dict()})
		committed_result.backend_id = p_backend_id
		return committed_result
	if raw is GMBlockedResult:
		var blocked_result := blocked(request, raw.error_code, raw.reason_zh, {"domain_result": raw.to_dict()})
		blocked_result.backend_id = p_backend_id
		return blocked_result
	if raw is Dictionary:
		var data: Dictionary = raw
		if GMP21Contract.exact(data, FIELDS):
			var decoded := from_dict(data)
			if decoded.ok:
				var result: GMInteractionResult = decoded.result
				if result.request_id != request.request_id or result.interaction_id != request.interaction_id or result.kind != request.kind:
					return rejected(request, "interaction.backend_identity_mismatch", "Backend返回结果身份与请求不一致。")
				result.backend_id = p_backend_id
				return result
		var status := str(data.get("status", "accepted"))
		var code := str(data.get("code", data.get("error_code", "interaction.accepted")))
		var reason := str(data.get("reason_zh", data.get("error_zh", "交互请求已受理。")))
		var payload: Dictionary = data.get("payload", data.get("details", data)).duplicate(true) if data.get("payload", data.get("details", data)) is Dictionary else {}
		var result := _make(request, status if status in GMP21Contract.INTERACTION_STATUSES else "rejected", code, reason, payload)
		result.backend_id = p_backend_id
		return result
	return rejected(request, "interaction.backend_result_type_invalid", "Backend返回了不受支持的结果类型。")
