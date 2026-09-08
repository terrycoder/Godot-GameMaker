class_name GMSpatialTargetRef
extends RefCounted

const SCHEMA_VERSION := 1
const KINDS := ["entity", "anchor", "route", "facility_slot", "logical_position"]
const ALLOWED_KEYS := ["schema_version", "domain_id", "kind", "semantic_id", "map_id", "logical_position", "planar_position"]
const TARGET_SCRIPT := preload("res://gm_runtime/spatial_core/gm_spatial_target_ref.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const SPATIAL_DOMAIN := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")

var _data: Dictionary = {}

static func from_native(value: Variant) -> Dictionary:
	if value is RefCounted and value.get_script() == TARGET_SCRIPT:
		return from_native(value.to_native())
	var validation := _validate_native(value)
	if not validation.ok:
		return validation
	var target = TARGET_SCRIPT.new()
	target._data = validation.value.duplicate(true)
	return {"ok": true, "target": target, "value": target.to_native()}

static func from_json(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"ok": false, "code": "spatial.target_json_invalid", "error_zh": "空间目标JSON无效。"}
	return from_native(parser.data)

func to_native() -> Dictionary:
	return _data.duplicate(true)

func to_json() -> String:
	return JSON.stringify(to_native())

func domain_id() -> String:
	return str(_data.get("domain_id", ""))

func kind() -> String:
	return str(_data.get("kind", ""))

func semantic_id() -> String:
	return str(_data.get("semantic_id", ""))

func map_id() -> String:
	return str(_data.get("map_id", ""))

func logical_position_native() -> Dictionary:
	var value = _data.get("logical_position", {})
	return value.duplicate(true) if value is Dictionary else {}

func planar_position():
	var value = _data.get("planar_position", null)
	var parsed := PLANAR_POSITION.from_native(value)
	return parsed.position if parsed.ok else null

static func from_planar_position(position, domain_id: String = SPATIAL_DOMAIN.PLANAR_2D) -> Dictionary:
	if position == null:
		return _failure("spatial.target_position_missing", "空间目标缺少逻辑位置。")
	var parsed := PLANAR_POSITION.from_native(position)
	if not parsed.ok: return parsed
	var domain := SPATIAL_DOMAIN.validate_id(domain_id)
	if not domain.ok: return _failure("spatial.target_domain_invalid", "空间目标的空间域无效。")
	var target = TARGET_SCRIPT.new()
	target._data = {
		"schema_version": SCHEMA_VERSION,
		"domain_id": str(domain.domain_id),
		"kind": "logical_position",
		"semantic_id": "",
		"map_id": parsed.position.map_id,
		"planar_position": parsed.position.to_native(),
	}
	return {"ok": true, "target": target, "value": target.to_native()}

static func _validate_native(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("spatial.target_type_invalid", "空间目标必须是Dictionary值。")
	for raw_key in value.keys():
		if not raw_key is String and not raw_key is StringName:
			return _failure("spatial.target_key_invalid", "空间目标字段名必须是字符串。")
		if not ALLOWED_KEYS.has(str(raw_key)):
			return _failure("spatial.target_field_unknown", "空间目标包含未知字段：%s" % str(raw_key))
	if value.get("schema_version", null) != SCHEMA_VERSION:
		return _failure("spatial.target_version_unsupported", "不支持的空间目标版本。")
	var domain := SPATIAL_DOMAIN.validate_id(value.get("domain_id", null))
	if not domain.ok:
		return _failure("spatial.target_domain_invalid", "空间目标的空间域无效。")
	var target_kind = value.get("kind", null)
	if not target_kind is String and not target_kind is StringName:
		return _failure("spatial.target_kind_invalid", "空间目标类型必须是稳定字符串。")
	var kind_text := str(target_kind)
	if not KINDS.has(kind_text):
		return _failure("spatial.target_kind_unknown", "未知空间目标类型：%s" % kind_text)
	var semantic_id = value.get("semantic_id", "")
	var map_id = value.get("map_id", "")
	if not semantic_id is String and not semantic_id is StringName:
		return _failure("spatial.target_semantic_id_invalid", "语义目标ID必须是字符串。")
	if not map_id is String and not map_id is StringName:
		return _failure("spatial.target_map_id_invalid", "地图ID必须是字符串。")
	var semantic_text := str(semantic_id)
	var map_text := str(map_id)
	if kind_text != "logical_position" and not _stable_id(semantic_text):
		return _failure("spatial.target_semantic_id_invalid", "语义目标需要非空稳定ID。")
	if kind_text in ["anchor", "route", "facility_slot", "logical_position"] and not _stable_id(map_text):
		return _failure("spatial.target_map_id_invalid", "该空间目标需要非空稳定地图ID。")
	var logical = value.get("logical_position", null)
	var planar = value.get("planar_position", null)
	if kind_text == "logical_position":
		if planar != null:
			var parsed_planar := PLANAR_POSITION.from_native(planar)
			if not parsed_planar.ok:
				return _failure("spatial.target_planar_position_invalid", "自由位置的PlanarPosition无效。")
			if str(parsed_planar.position.map_id) != map_text:
				return _failure("spatial.target_planar_position_map_mismatch", "自由位置的map_id与目标map_id不一致。")
			if logical != null:
				if not logical is Dictionary or logical.size() != 2 or not logical.has("x") or not logical.has("y") or not _finite_number(logical.get("x")) or not _finite_number(logical.get("y")):
					return _failure("spatial.target_logical_position_invalid", "兼容逻辑位置必须只包含有限x/y。")
				if not is_equal_approx(float(logical.x), parsed_planar.position.x) or not is_equal_approx(float(logical.y), parsed_planar.position.y):
					return _failure("spatial.target_position_mismatch", "兼容逻辑位置与PlanarPosition不一致。")
		else:
			if not logical is Dictionary or logical.size() != 2 or not logical.has("x") or not logical.has("y"):
				return _failure("spatial.target_logical_position_invalid", "自由位置必须只包含有限逻辑平面x/y。")
			if not _finite_number(logical.x) or not _finite_number(logical.y):
				return _failure("spatial.target_logical_position_invalid", "自由位置x/y必须是有限数值。")
	elif logical != null or planar != null:
		return _failure("spatial.target_logical_position_unexpected", "稳定语义目标不得同时保存自由位置。")
	var normalized := {
		"schema_version": SCHEMA_VERSION,
		"domain_id": str(domain.domain_id),
		"kind": kind_text,
		"semantic_id": semantic_text,
		"map_id": map_text,
	}
	if kind_text == "logical_position":
		if planar != null:
			var normalized_planar := PLANAR_POSITION.from_native(planar)
			normalized["logical_position"] = {"x": normalized_planar.position.x, "y": normalized_planar.position.y}
			normalized["planar_position"] = normalized_planar.position.to_native()
		else:
			normalized["logical_position"] = {"x": float(logical.x), "y": float(logical.y)}
	return {"ok": true, "value": normalized}

static func _stable_id(value: String) -> bool:
	return PLANAR_POSITION.is_valid_stable_id(value)

static func _finite_number(value: Variant) -> bool:
	if not value is int and not value is float:
		return false
	return is_finite(float(value))

static func _failure(code: String, error_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": error_zh}
