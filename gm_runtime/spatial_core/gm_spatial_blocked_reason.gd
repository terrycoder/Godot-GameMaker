class_name GMSpatialBlockedReason
extends RefCounted

## Structured, serializable failure reason.  It is a result value, not a
## second error/fact store.

const SCHEMA_VERSION := 1
const REASON_SCRIPT := preload("res://gm_runtime/spatial_core/gm_spatial_blocked_reason.gd")
const BACKEND_MISSING := "spatial.backend.missing"
const BACKEND_DUPLICATE := "spatial.backend.duplicate"
const BACKEND_UNREGISTERED := "spatial.backend.unregistered"
const BACKEND_DOMAIN_UNAVAILABLE := "spatial.backend.domain_unavailable"
const CAPABILITY_UNSUPPORTED := "spatial.capability.unsupported"
const CAPABILITY_MISMATCH := "spatial.backend.capability_mismatch"
const MAP_MISSING := "spatial.map.missing"
const SURFACE_MISSING := "spatial.surface.missing"
const SURFACE_MISMATCH := "spatial.surface.mismatch"
const POSITION_INVALID := "spatial.position.invalid"
const POSITION_AMBIGUOUS := "spatial.position.ambiguous"
const NOT_WALKABLE := "spatial.position.not_walkable"
const UNREACHABLE := "spatial.position.unreachable"
const PATH_UNAVAILABLE := "spatial.path.unavailable"
const ADAPTER_DISABLED := "spatial.adapter.disabled"
const TARGET_INVALID := "spatial.target.invalid"
const SNAPSHOT_INVALID := "spatial.snapshot.invalid"

var schema_version: int = SCHEMA_VERSION
var code: String = ""
var reason_zh: String = ""
var details: Dictionary = {}

func _init(p_code: String = "", p_reason_zh: String = "", p_details: Dictionary = {}) -> void:
	code = p_code
	reason_zh = p_reason_zh
	details = p_details.duplicate(true)

static func create(p_code: String, p_reason_zh: String, p_details: Dictionary = {}):
	return REASON_SCRIPT.new(p_code, p_reason_zh, p_details)

static func from_native(value: Variant) -> Dictionary:
	if value is RefCounted and value.get_script() == REASON_SCRIPT:
		return {"ok": true, "reason": value.copy(), "value": value.to_native()}
	if not value is Dictionary:
		return _failure("spatial.blocked_reason_type_invalid", "空间阻断原因必须是Dictionary值。")
	var source: Dictionary = value
	for raw_key in source.keys():
		if not raw_key is String and not raw_key is StringName:
			return _failure("spatial.blocked_reason_key_invalid", "空间阻断原因字段名必须是字符串。")
		if str(raw_key) not in ["schema_version", "code", "reason_zh", "details"]:
			return _failure("spatial.blocked_reason_field_unknown", "空间阻断原因包含未知字段：%s" % str(raw_key))
	for required in ["schema_version", "code", "reason_zh", "details"]:
		if not source.has(required):
			return _failure("spatial.blocked_reason_field_missing", "空间阻断原因缺少字段：%s" % required)
	if not source.schema_version is int or int(source.schema_version) != SCHEMA_VERSION:
		return _failure("spatial.blocked_reason_version_invalid", "空间阻断原因Schema版本无效。")
	if not source.code is String or str(source.code).strip_edges().is_empty():
		return _failure("spatial.blocked_reason_code_invalid", "空间阻断原因code不能为空。")
	if not source.reason_zh is String or str(source.reason_zh).strip_edges().is_empty():
		return _failure("spatial.blocked_reason_message_invalid", "空间阻断原因必须包含中文说明。")
	if not source.details is Dictionary:
		return _failure("spatial.blocked_reason_details_invalid", "空间阻断原因details必须是Dictionary。")
	var stable := GMStableData.validate(source.details)
	if not stable.ok:
		return _failure("spatial.blocked_reason_details_unstable", "空间阻断原因details必须是纯数据。")
	var reason = REASON_SCRIPT.new(str(source.code), str(source.reason_zh), source.details)
	return {"ok": true, "reason": reason, "value": reason.to_native()}

func copy():
	return REASON_SCRIPT.new(code, reason_zh, details)

func to_native() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "code": code, "reason_zh": reason_zh, "details": details.duplicate(true)}

func validate() -> Dictionary:
	return from_native(to_native())

static func _failure(p_code: String, message: String) -> Dictionary:
	return {"ok": false, "code": p_code, "error_zh": message}
