class_name GMSceneReturnContext
extends RefCounted

## 场景结束后交回 P15 的纯值边界。它只表达来源地图/锚点/逻辑位置，
## 不携带 Node、SceneTree 或移动执行器。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

const SCHEMA_VERSION := "gm.scene.return_context.v1"
const FIELDS: Array[String] = ["schema_version", "map_id", "anchor_id", "position"]

var map_id: String
var anchor_id: String
var position: Dictionary

func _init(p_map_id: String = "", p_anchor_id: String = "", p_position: Dictionary = {}) -> void:
	map_id = p_map_id
	anchor_id = p_anchor_id
	position = VALUE.duplicate_value(p_position)

static func from_dict(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var stable := VALUE.persistence(value)
	if not stable.ok:
		return stable
	if value.schema_version != SCHEMA_VERSION:
		return {"ok": false, "code": "scene.return.schema", "error_zh": "SceneReturnContext Schema版本不匹配。"}
	if not VALUE.stable_id(value.map_id) or not VALUE.stable_id(value.anchor_id):
		return {"ok": false, "code": "scene.return.reference", "error_zh": "返回地图与锚点必须是稳定标识。"}
	if str(value.map_id).is_empty() and not str(value.anchor_id).is_empty():
		return {"ok": false, "code": "scene.return.map_missing", "error_zh": "返回锚点存在时必须提供地图标识。"}
	if typeof(value.position) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.return.position_type", "error_zh": "返回位置必须是字典。"}
	var normalized_position: Dictionary = {}
	if not value.position.is_empty():
		var planar := PLANAR_POSITION.from_native(value.position)
		if not planar.ok:
			return {"ok": false, "code": "scene.return.position_invalid", "error_zh": "返回位置不是合法的GMPlanarPosition。", "detail": planar}
		normalized_position = planar.position.to_native()
	if str(value.map_id).is_empty() and value.position.is_empty():
		return {"ok": false, "code": "scene.return.empty", "error_zh": "返回上下文至少需要地图锚点或逻辑位置。"}
	var result := GMSceneReturnContext.new(str(value.map_id), str(value.anchor_id), normalized_position)
	return {"ok": true, "value": result}

static func from_json(text: String) -> Dictionary:
	var parsed := VALUE.parse_json(text)
	if not parsed.ok:
		return parsed
	return from_dict(parsed.value)

static func from_anchor(p_map_id: String, p_anchor_id: String, p_position: Dictionary = {}) -> GMSceneReturnContext:
	return GMSceneReturnContext.new(p_map_id, p_anchor_id, p_position)

func validate() -> Dictionary:
	return GMSceneReturnContext.from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"map_id": map_id,
		"anchor_id": anchor_id,
		"position": VALUE.duplicate_value(position)
	}

func to_json() -> String:
	return VALUE.json_string(to_dict())

func fingerprint() -> String:
	return VALUE.digest(to_dict())
