class_name GMSpatialQueryResult
extends RefCounted

const SCHEMA_VERSION := 1
const BLOCKED_REASON := preload("res://gm_runtime/spatial_core/gm_spatial_blocked_reason.gd")
const STABLE_DATA := preload("res://gm_runtime/simulation/gm_stable_data.gd")
const SPATIAL_DOMAIN := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")
const SPATIAL_CAPABILITIES := preload("res://gm_runtime/spatial_core/gm_spatial_backend_capabilities.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

static func success(domain_id: String, capability_id: String, target: Dictionary, value: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"schema_version": SCHEMA_VERSION,
		"domain_id": domain_id,
		"capability_id": capability_id,
		"target": target.duplicate(true),
		"value": value.duplicate(true),
	}

static func blocked(code: String, error_zh: String, domain_id: String = "", capability_id: String = "", details: Dictionary = {}) -> Dictionary:
	var reason = BLOCKED_REASON.new(code, error_zh, details)
	return {
		"ok": false,
		"schema_version": SCHEMA_VERSION,
		"code": code,
		"error_zh": error_zh,
		"domain_id": domain_id,
		"capability_id": capability_id,
		"details": details.duplicate(true),
		"blocked_reason": reason.to_native(),
	}

static func is_success(value: Variant) -> bool:
	return value is Dictionary and bool(value.get("ok", false)) and validate_native(value).ok

static func is_blocked(value: Variant) -> bool:
	return value is Dictionary and not bool(value.get("ok", true)) and value.has("blocked_reason")

static func validate_native(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "code": "spatial.result_type_invalid", "error_zh": "空间查询结果必须是Dictionary。"}
	var source: Dictionary = value
	if not source.get("schema_version", null) is int or int(source.get("schema_version", -1)) != SCHEMA_VERSION:
		return {"ok": false, "code": "spatial.result_version_invalid", "error_zh": "空间查询结果Schema版本无效。"}
	if not source.get("ok", null) is bool:
		return {"ok": false, "code": "spatial.result_status_invalid", "error_zh": "空间查询结果ok字段类型无效。"}
	if bool(source.get("ok", false)):
		var success_shape := _exact_fields(source, ["ok", "schema_version", "domain_id", "capability_id", "target", "value"])
		if not success_shape.ok:
			return {"ok": false, "code": "spatial.result_field_unknown", "error_zh": "成功查询结果包含未知顶层字段。", "details": success_shape}
		for required in ["domain_id", "capability_id", "target", "value"]:
			if not source.has(required): return {"ok": false, "code": "spatial.result_field_missing", "error_zh": "成功查询结果缺少字段：%s" % required}
		var domain_value: Variant = source.get("domain_id")
		var domain := SPATIAL_DOMAIN.validate_id(domain_value)
		if not domain.ok:
			return {"ok": false, "code": "spatial.result_domain_invalid", "error_zh": "成功查询结果domain_id必须是已声明的稳定空间域ID。", "details": domain}
		var capability_value: Variant = source.get("capability_id")
		if not PLANAR_POSITION.is_valid_stable_id(capability_value) or not SPATIAL_CAPABILITIES.ALL_KNOWN.has(str(capability_value)):
			return {"ok": false, "code": "spatial.result_capability_invalid", "error_zh": "成功查询结果capability_id必须是已声明的稳定能力ID。"}
		if not source.target is Dictionary or not source.value is Dictionary:
			return {"ok": false, "code": "spatial.result_value_invalid", "error_zh": "成功查询结果target/value必须是Dictionary。"}
		var target_validation := STABLE_DATA.validate(source.target, "$.target")
		if not target_validation.ok:
			return {"ok": false, "code": "spatial.result_target_non_pure", "error_zh": "成功查询结果target必须是纯数据，不得包含运行时对象身份。", "details": {"errors": target_validation.errors.duplicate()}}
		var value_validation := STABLE_DATA.validate(source.value, "$.value")
		if not value_validation.ok:
			return {"ok": false, "code": "spatial.result_value_non_pure", "error_zh": "成功查询结果value必须是纯数据，不得包含运行时对象身份。", "details": {"errors": value_validation.errors.duplicate()}}
		return {"ok": true, "result": source.duplicate(true)}
	var blocked_shape := _exact_fields(source, ["ok", "schema_version", "code", "error_zh", "domain_id", "capability_id", "details", "blocked_reason"])
	if not blocked_shape.ok:
		return {"ok": false, "code": "spatial.result_field_unknown", "error_zh": "阻断查询结果包含未知顶层字段。", "details": blocked_shape}
	if not source.has("code") or not source.has("error_zh") or not source.has("blocked_reason"):
		return {"ok": false, "code": "spatial.result_blocked_shape_invalid", "error_zh": "阻断查询结果缺少结构化原因。"}
	var blocked_domain := _validate_optional_domain(source.get("domain_id", ""))
	if not blocked_domain.ok: return blocked_domain
	var blocked_capability := _validate_optional_capability(source.get("capability_id", ""))
	if not blocked_capability.ok: return blocked_capability
	var reason := BLOCKED_REASON.from_native(source.blocked_reason)
	if not reason.ok: return reason
	if str(source.get("code", "")) != str(reason.reason.code) or str(source.get("error_zh", "")) != str(reason.reason.reason_zh):
		return {"ok": false, "code": "spatial.result_reason_mismatch", "error_zh": "空间查询结果的阻断摘要与结构化原因不一致。"}
	return {"ok": true, "result": source.duplicate(true)}

static func _exact_fields(source: Dictionary, expected: Array) -> Dictionary:
	var actual: Array[String] = []
	for key in source.keys(): actual.append(str(key))
	actual.sort()
	var allowed: Array[String] = []
	for key in expected: allowed.append(str(key))
	allowed.sort()
	return {"ok": actual == allowed, "actual": actual, "expected": allowed}

static func _validate_optional_domain(value: Variant) -> Dictionary:
	if value == null or str(value).is_empty(): return {"ok": true}
	var result := SPATIAL_DOMAIN.validate_id(value)
	if result.ok: return {"ok": true}
	return {"ok": false, "code": "spatial.result_domain_invalid", "error_zh": "阻断查询结果domain_id必须是稳定空间域ID。", "details": result}

static func _validate_optional_capability(value: Variant) -> Dictionary:
	if value == null or str(value).is_empty(): return {"ok": true}
	if PLANAR_POSITION.is_valid_stable_id(value) and SPATIAL_CAPABILITIES.ALL_KNOWN.has(str(value)): return {"ok": true}
	return {"ok": false, "code": "spatial.result_capability_invalid", "error_zh": "阻断查询结果capability_id必须是稳定能力ID。"}

static func ensure_blocked(value: Dictionary, fallback_code: String, fallback_reason_zh: String) -> Dictionary:
	if is_blocked(value): return value.duplicate(true)
	return blocked(fallback_code, fallback_reason_zh, str(value.get("domain_id", "")), str(value.get("capability_id", "")), {"invalid_result": value.duplicate(true)})
