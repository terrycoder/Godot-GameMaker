class_name GMSceneValueContract
extends RefCounted

## P23 纯值边界工具。
##
## 这里不持有任务、世界、商店或事务状态，只负责把 SceneRecipe / Session
## 的输入约束到可复制、可保存的 JSON 等价值。后端对象永远不会进入这些值。

const STABLE_DATA := preload("res://gm_runtime/simulation/gm_stable_data.gd")
const SPATIAL_TARGET := preload("res://gm_runtime/spatial_core/gm_spatial_target_ref.gd")

const FORBIDDEN_TOKENS := [
	"NodePath",
	"SceneTree",
	"TileMap",
	"Node2D",
	"Node3D",
	"Resource",
	"RID",
	"res://",
	"user://"
]

static func exact_fields(value: Variant, fields: Array[String]) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.value.not_dictionary", "error_zh": "P23值必须是字典。"}
	var expected := {}
	for field in fields:
		expected[field] = true
	for key in value.keys():
		if typeof(key) != TYPE_STRING or not expected.has(str(key)):
			return {"ok": false, "code": "scene.value.unknown_field", "error_zh": "P23值包含未声明字段：%s。" % str(key)}
	for field in fields:
		if not value.has(field):
			return {"ok": false, "code": "scene.value.missing_field", "error_zh": "P23值缺少字段：%s。" % field}
	return {"ok": true}

static func persistence(value: Variant) -> Dictionary:
	var stable := STABLE_DATA.validate_persistence(value)
	if not stable.ok:
		return stable
	if _contains_forbidden_token(value):
		return {"ok": false, "code": "scene.value.runtime_reference", "error_zh": "P23纯值不得包含运行时节点、资源或路径引用。"}
	return {"ok": true, "code": "scene.value.persistence_valid"}

static func stable_id(value: Variant, allow_empty: bool = false) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text := str(value)
	if text.is_empty():
		return allow_empty
	if text.length() > 160:
		return false
	for character in ["/", "\\", "\n", "\r", "\t", " ", ":"]:
		if text.contains(character):
			return false
	return true

static func non_empty_string(value: Variant) -> bool:
	return stable_id(value, false)

static func safe_int(value: Variant, allow_negative: bool = true) -> Dictionary:
	var numeric := 0.0
	match typeof(value):
		TYPE_INT:
			numeric = float(value)
		TYPE_FLOAT:
			numeric = float(value)
		_:
			return {"ok": false, "code": "scene.value.integer_type", "error_zh": "P23整数值必须是整数或JSON可还原的有限整数。"}
	if not is_finite(numeric) or numeric != floor(numeric):
		return {"ok": false, "code": "scene.value.integer_invalid", "error_zh": "P23整数值必须是有限整数。"}
	if abs(numeric) > STABLE_DATA.JSON_SAFE_INTEGER_MAX:
		return {"ok": false, "code": "scene.value.integer_range", "error_zh": "P23整数值超出JSON安全范围。"}
	if not allow_negative and numeric < 0.0:
		return {"ok": false, "code": "scene.value.integer_negative", "error_zh": "P23整数值不得为负数。"}
	return {"ok": true, "value": int(numeric)}

static func integer_field(value: Variant, allow_negative: bool = true) -> Dictionary:
	return safe_int(value, allow_negative)

static func string_array(value: Variant, allow_empty: bool = false) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {"ok": false, "code": "scene.value.array_type", "error_zh": "P23列表字段必须是数组。"}
	var result: Array[String] = []
	for item in value:
		if not stable_id(item, allow_empty):
			return {"ok": false, "code": "scene.value.string_array_item", "error_zh": "P23列表包含非法稳定标识。"}
		result.append(str(item))
	return {"ok": true, "value": result}

static func typed_ref(value: Variant, allow_empty: bool = false) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.ref.not_dictionary", "error_zh": "语义引用必须是字典。"}
	var fields := exact_fields(value, ["type", "id"])
	if not fields.ok:
		return fields
	if not stable_id(value.type, allow_empty) or not stable_id(value.id, allow_empty):
		return {"ok": false, "code": "scene.ref.invalid", "error_zh": "语义引用的type/id必须是稳定标识。"}
	if not allow_empty and (str(value.type).is_empty() or str(value.id).is_empty()):
		return {"ok": false, "code": "scene.ref.empty", "error_zh": "语义引用不得为空。"}
	return {"ok": true}

static func optional_typed_ref(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY and value.is_empty():
		return {"ok": true}
	return typed_ref(value, false)

static func semantic_ref(value: Variant, allow_empty: bool = false) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.semantic_ref.type", "error_zh": "语义目标必须是稳定字典值。"}
	if allow_empty and value.is_empty():
		return {"ok": true}
	if value.has("schema_version") and value.has("domain_id") and value.has("kind"):
		var spatial := SPATIAL_TARGET.from_native(value)
		if not spatial.ok:
			return {"ok": false, "code": "scene.semantic_ref.spatial_invalid", "error_zh": "空间语义目标无效。", "detail": spatial}
		return {"ok": true, "value": duplicate_value(spatial.value)}
	var typed := typed_ref(value, allow_empty)
	if not typed.ok:
		return typed
	return {"ok": true, "value": duplicate_value(value)}

static func duplicate_value(value: Variant) -> Variant:
	return STABLE_DATA.clone(value)

static func persistence_canonical(value: Variant) -> Variant:
	return STABLE_DATA.persistence_canonical(value)

static func digest(value: Variant) -> String:
	return STABLE_DATA.digest(value)

static func json_string(value: Variant) -> String:
	return STABLE_DATA.persistence_canonical_json(value)

static func parse_json(text: String) -> Dictionary:
	if typeof(text) != TYPE_STRING or text.is_empty():
		return {"ok": false, "code": "scene.json.empty", "error_zh": "P23 JSON文本不得为空。"}
	var parsed = JSON.parse_string(text)
	if parsed == null:
		return {"ok": false, "code": "scene.json.invalid", "error_zh": "P23 JSON文本无效。"}
	return {"ok": true, "value": parsed}

static func _contains_forbidden_token(value: Variant) -> bool:
	if typeof(value) == TYPE_STRING:
		var text := str(value)
		for token in FORBIDDEN_TOKENS:
			if text.contains(token):
				return true
		return false
	if value is Array:
		for item in value:
			if _contains_forbidden_token(item):
				return true
		return false
	if value is Dictionary:
		for key in value.keys():
			if _contains_forbidden_token(str(key)) or _contains_forbidden_token(value[key]):
				return true
	return false
