class_name GMPlanarPosition
extends RefCounted

## Dimension-agnostic logical position used by both planar backends.
## The value deliberately contains no scene, node, navigation or backend object.

const SCHEMA_VERSION := 1
const REQUIRED_KEYS := ["schema_version", "map_id", "surface_id", "x", "y"]
const POSITION_SCRIPT := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const STABLE_DATA := preload("res://gm_runtime/simulation/gm_stable_data.gd")

var schema_version: int = SCHEMA_VERSION
var map_id: String = ""
var surface_id: String = ""
var x: float = 0.0
var y: float = 0.0

func _init(p_map_id: String = "", p_surface_id: String = "", p_x: float = 0.0, p_y: float = 0.0) -> void:
	map_id = p_map_id
	surface_id = p_surface_id
	x = p_x
	y = p_y

static func from_native(value: Variant) -> Dictionary:
	if value is RefCounted and value.get_script() == POSITION_SCRIPT:
		return from_native(value.to_native())
	var validation := _validate_native(value)
	if not validation.ok:
		return validation
	var normalized: Dictionary = validation.value
	var position = POSITION_SCRIPT.new(str(normalized.map_id), str(normalized.surface_id), float(normalized.x), float(normalized.y))
	return {"ok": true, "position": position, "value": position.to_native()}

static func from_dict(value: Variant) -> Dictionary:
	return from_native(value)

static func from_json(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return _failure("spatial.position_json_invalid", "逻辑位置JSON无效。")
	return from_native(parser.data)

static func validate_native(value: Variant) -> Dictionary:
	return _validate_native(value)

func duplicate_position():
	return POSITION_SCRIPT.new(map_id, surface_id, x, y)

func copy():
	return duplicate_position()

func to_native() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"map_id": map_id,
		"surface_id": surface_id,
		"x": x,
		"y": y,
	}

func to_dict() -> Dictionary:
	return to_native()

func to_json() -> String:
	return JSON.stringify(to_native())

func validate() -> Dictionary:
	return _validate_native(to_native())

func is_same_surface(other: Variant) -> bool:
	var parsed := from_native(other)
	return parsed.ok and map_id == parsed.position.map_id and surface_id == parsed.position.surface_id

static func is_valid_stable_id(value: Variant, allow_empty: bool = false) -> bool:
	if not value is String and not value is StringName:
		return false
	var text := str(value)
	if text.is_empty():
		return allow_empty
	if text != text.strip_edges() or text.contains(" ") or text.contains("\t") or text.contains("\r") or text.contains("\n"):
		return false
	if text.begins_with("/") or text.begins_with("\\"):
		return false
	if text.contains("/") or text.contains("\\") or text.contains(":"):
		return false
	var lowered := text.to_lower()
	if lowered.begins_with("res://") or lowered.begins_with("user://"):
		return false
	for forbidden in ["nodepath", "navigationagent", "navigationregion", "backend_instance", "scene_path"]:
		if lowered.contains(forbidden):
			return false
	# Treat RID as a reserved identity token, not as an arbitrary substring;
	# otherwise legitimate authored IDs such as `bridge` are rejected.
	var identity_tokens := lowered.replace(".", "_").replace("-", "_").split("_", false)
	if identity_tokens.has("rid"):
		return false
	return true

static func _validate_native(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("spatial.position_type_invalid", "逻辑位置必须是纯Dictionary值。")
	var source: Dictionary = value
	for raw_key in source.keys():
		if not raw_key is String and not raw_key is StringName:
			return _failure("spatial.position_key_invalid", "逻辑位置字段名必须是字符串。")
		if not REQUIRED_KEYS.has(str(raw_key)):
			return _failure("spatial.position_field_unknown", "逻辑位置包含未知字段：%s" % str(raw_key))
	for required in REQUIRED_KEYS:
		if not source.has(required):
			return _failure("spatial.position_field_missing", "逻辑位置缺少字段：%s" % required)
	var schema_check := STABLE_DATA.normalize_schema_version(source.get("schema_version"))
	if not schema_check.ok:
		return _failure("spatial.position_version_unsupported", "不支持的逻辑位置Schema版本。")
	var raw_map = source.get("map_id")
	var raw_surface = source.get("surface_id")
	if not is_valid_stable_id(raw_map) or str(raw_map).is_empty():
		return _failure("spatial.position_map_invalid", "逻辑位置的map_id必须是非空稳定ID。")
	if not is_valid_stable_id(raw_surface) or str(raw_surface).is_empty():
		return _failure("spatial.position_surface_invalid", "逻辑位置的surface_id必须是非空稳定ID。")
	if not _finite_number(source.get("x")) or not _finite_number(source.get("y")):
		return _failure("spatial.position_nonfinite", "逻辑位置x/y必须是有限数值。")
	return {
		"ok": true,
		"value": {
			"schema_version": SCHEMA_VERSION,
			"map_id": str(raw_map),
			"surface_id": str(raw_surface),
			"x": float(source.get("x")),
			"y": float(source.get("y")),
		},
	}

static func _finite_number(value: Variant) -> bool:
	if not value is int and not value is float:
		return false
	return is_finite(float(value))

static func _failure(code: String, error_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": error_zh}
