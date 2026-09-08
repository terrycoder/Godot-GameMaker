extends RefCounted

## P24 的维度无关关卡对象规则定义。
##
## 这是纯值合同：它描述对象类别、能力和稳定语义引用，但不持有节点、
## SceneTree、后端实例或领域 Store。P24 的 Resolver 对所有对象类别复用同
## 一套规则入口；2D/Planar3D 差异只在后续适配器中出现。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const RETURN_CONTEXT := preload("res://gm_runtime/scene/gm_scene_return_context.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

const SCHEMA_VERSION := "gm.level.object_definition.v1"
const RESOLVER_ID := "gm.level.object.resolver.v1"
const OBJECT_KINDS: Array[String] = [
	"door", "chest", "mechanism", "teleport", "checkpoint", "revive", "extraction", "generator"
]
const FIELDS: Array[String] = [
	"schema_version", "definition_id", "object_kind", "ability_id", "resolver_id",
	"state_defaults", "target_ref", "destination", "return_context", "logical_position",
	"surface_id", "tags", "generation"
]

var definition_id: String
var object_kind: String
var ability_id: String
var resolver_id: String
var state_defaults: Dictionary
var target_ref: Dictionary
var destination: Dictionary
var return_context: Dictionary
var logical_position: Dictionary
var surface_id: String
var tags: Array
var generation: Dictionary

func _init(
	p_definition_id: String = "",
	p_object_kind: String = "",
	p_ability_id: String = "",
	p_state_defaults: Dictionary = {},
	p_target_ref: Dictionary = {},
	p_destination: Dictionary = {},
	p_return_context: Dictionary = {},
	p_logical_position: Dictionary = {},
	p_surface_id: String = "",
	p_tags: Array = [],
	p_generation: Dictionary = {},
	p_resolver_id: String = RESOLVER_ID
) -> void:
	definition_id = p_definition_id
	object_kind = p_object_kind
	ability_id = p_ability_id
	resolver_id = p_resolver_id
	state_defaults = VALUE.duplicate_value(p_state_defaults)
	target_ref = VALUE.duplicate_value(p_target_ref)
	destination = VALUE.duplicate_value(p_destination)
	return_context = VALUE.duplicate_value(p_return_context)
	logical_position = VALUE.duplicate_value(p_logical_position)
	surface_id = p_surface_id
	tags = VALUE.duplicate_value(p_tags)
	generation = VALUE.duplicate_value(p_generation)

static func from_dict(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var stable := VALUE.persistence(value)
	if not stable.ok:
		return {"ok": false, "code": "level_object.definition.persistence", "error_zh": "关卡对象定义必须是可持久化纯值。", "detail": stable}
	if _contains_direct_write_marker(value):
		return {"ok": false, "code": "level_object.definition.direct_write", "error_zh": "关卡对象定义不得声明直接写入领域状态。"}
	if str(value.get("schema_version", "")) != SCHEMA_VERSION:
		return {"ok": false, "code": "level_object.definition.schema", "error_zh": "关卡对象定义Schema版本不匹配。"}
	for identity in ["definition_id", "object_kind", "ability_id", "resolver_id"]:
		if not VALUE.stable_id(value.get(identity, ""), false):
			return {"ok": false, "code": "level_object.definition.identity", "error_zh": "关卡对象定义包含非法稳定标识。", "field": identity}
	if not OBJECT_KINDS.has(str(value.object_kind)):
		return {"ok": false, "code": "level_object.definition.kind", "error_zh": "关卡对象类别不在P24通用范围内。", "object_kind": str(value.object_kind)}
	if str(value.resolver_id) != RESOLVER_ID:
		return {"ok": false, "code": "level_object.definition.resolver", "error_zh": "关卡对象必须使用P24唯一Resolver。"}
	if typeof(value.state_defaults) != TYPE_DICTIONARY or not VALUE.persistence(value.state_defaults).ok:
		return {"ok": false, "code": "level_object.definition.state", "error_zh": "关卡对象默认状态必须是可持久化纯字典。"}
	var target_check := VALUE.semantic_ref(value.target_ref, true)
	if not target_check.ok:
		return {"ok": false, "code": "level_object.definition.target", "error_zh": "关卡对象目标引用无效。", "detail": target_check}
	var destination_check := _validate_destination(value.destination)
	if not destination_check.ok:
		return destination_check
	var return_check := _validate_return_context(value.return_context)
	if not return_check.ok:
		return return_check
	var position_check := _validate_position(value.logical_position, str(value.surface_id))
	if not position_check.ok:
		return position_check
	if not VALUE.stable_id(value.surface_id, true):
		return {"ok": false, "code": "level_object.definition.surface", "error_zh": "关卡对象Surface标识无效。"}
	var tags_check := VALUE.string_array(value.tags, true)
	if not tags_check.ok:
		return {"ok": false, "code": "level_object.definition.tags", "error_zh": "关卡对象标签必须是稳定字符串数组。"}
	if typeof(value.generation) != TYPE_DICTIONARY or not VALUE.persistence(value.generation).ok:
		return {"ok": false, "code": "level_object.definition.generation", "error_zh": "关卡对象生成配置必须是可持久化纯字典。"}
	if str(value.object_kind) == "teleport" and destination_check.value.is_empty():
		return {"ok": false, "code": "level_object.definition.destination_missing", "error_zh": "teleport定义必须声明稳定目标地图与锚点。"}
	if str(value.object_kind) == "checkpoint" and position_check.value.is_empty():
		return {"ok": false, "code": "level_object.definition.position_missing", "error_zh": "checkpoint定义必须声明稳定Logical Position。"}
	if str(value.object_kind) == "checkpoint" and str(value.surface_id).is_empty():
		return {"ok": false, "code": "level_object.definition.surface_missing", "error_zh": "checkpoint定义必须声明稳定Surface。"}
	var definition = load("res://gm_runtime/level/gm_level_object_definition.gd").new(
		str(value.definition_id), str(value.object_kind), str(value.ability_id), value.state_defaults,
		target_check.get("value", VALUE.duplicate_value(value.target_ref)), destination_check.value,
		return_check.value, position_check.value, str(value.surface_id), tags_check.value,
		value.generation, str(value.resolver_id)
	)
	return {"ok": true, "value": definition}

static func from_json(text: String) -> Dictionary:
	var parsed := VALUE.parse_json(text)
	if not parsed.ok:
		return parsed
	return from_dict(parsed.value)

static func _validate_destination(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "code": "level_object.definition.destination_type", "error_zh": "传送目标必须是字典。"}
	if value.is_empty():
		return {"ok": true, "value": {}}
	var fields := VALUE.exact_fields(value, ["map_id", "anchor_id", "scene_id", "transition"])
	if not fields.ok:
		return {"ok": false, "code": "level_object.definition.destination_shape", "error_zh": "传送目标字段集合无效。", "detail": fields}
	if not VALUE.persistence(value).ok:
		return {"ok": false, "code": "level_object.definition.destination_persistence", "error_zh": "传送目标必须是可持久化纯值。"}
	for identity in ["map_id", "anchor_id"]:
		if not VALUE.stable_id(value.get(identity, ""), false):
			return {"ok": false, "code": "level_object.definition.destination_identity", "error_zh": "传送目标必须提供稳定地图与锚点标识。", "field": identity}
	if not VALUE.stable_id(value.get("scene_id", ""), true) or not VALUE.stable_id(value.get("transition", ""), true):
		return {"ok": false, "code": "level_object.definition.destination_optional", "error_zh": "传送目标可选标识无效。"}
	return {"ok": true, "value": {"map_id": str(value.map_id), "anchor_id": str(value.anchor_id), "scene_id": str(value.scene_id), "transition": str(value.transition)}}

static func _validate_return_context(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "code": "level_object.definition.return_type", "error_zh": "返回上下文必须是字典。"}
	if value.is_empty():
		return {"ok": true, "value": {}}
	var checked := RETURN_CONTEXT.from_dict(value)
	if not checked.ok:
		return {"ok": false, "code": "level_object.definition.return_invalid", "error_zh": "关卡对象返回上下文未通过既有P23合同。", "detail": checked}
	return {"ok": true, "value": checked.value.to_dict()}

static func _validate_position(value: Variant, expected_surface_id: String) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "code": "level_object.definition.position_type", "error_zh": "Logical Position必须是字典。"}
	if value.is_empty():
		return {"ok": true, "value": {}}
	var checked := PLANAR_POSITION.from_native(value)
	if not checked.ok:
		return {"ok": false, "code": "level_object.definition.position_invalid", "error_zh": "Logical Position未通过既有空间纯值合同。", "detail": checked}
	var position: Dictionary = checked.position.to_native()
	if not expected_surface_id.is_empty() and str(position.get("surface_id", "")) != expected_surface_id:
		return {"ok": false, "code": "level_object.definition.position_surface_mismatch", "error_zh": "Logical Position与Surface标识不一致。"}
	return {"ok": true, "value": position}

static func _contains_direct_write_marker(value: Variant) -> bool:
	if value is Array:
		for item in value:
			if _contains_direct_write_marker(item):
				return true
		return false
	if value is Dictionary:
		for key in value.keys():
			var name := str(key).to_lower()
			if name in ["direct_world_write", "direct_task_write", "direct_store_write", "direct_transaction_write", "scene_tree_mutation"] and bool(value[key]):
				return true
			if _contains_direct_write_marker(value[key]):
				return true
	return false

func validate() -> Dictionary:
	return load("res://gm_runtime/level/gm_level_object_definition.gd").from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"definition_id": definition_id,
		"object_kind": object_kind,
		"ability_id": ability_id,
		"resolver_id": resolver_id,
		"state_defaults": VALUE.duplicate_value(state_defaults),
		"target_ref": VALUE.duplicate_value(target_ref),
		"destination": VALUE.duplicate_value(destination),
		"return_context": VALUE.duplicate_value(return_context),
		"logical_position": VALUE.duplicate_value(logical_position),
		"surface_id": surface_id,
		"tags": VALUE.duplicate_value(tags),
		"generation": VALUE.duplicate_value(generation)
	}

func to_json() -> String:
	return VALUE.json_string(to_dict())

func fingerprint() -> String:
	return VALUE.digest(to_dict())
