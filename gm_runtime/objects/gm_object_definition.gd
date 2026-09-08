@tool
class_name GMObjectDefinition
extends GMContent

## 地图对象的声明式事实源。对象差异通过 prototype + overrides 组合，禁止深层场景继承。

const SCHEMA := "gm.object.definition.v1"
const OBJECT_KINDS := ["door", "chest", "mechanism", "building", "resource_node", "pickup", "destructible"]
const OVERRIDABLE_FIELDS := [
	"display_name_zh", "object_kind", "appearance_scene", "ability_definitions",
	"interaction_recipe", "collision_shape", "persistent", "semantic_type_id",
	"anchor_names", "state_defaults"
]

@export_group("对象原型")
@export var prototype: GMObjectDefinition
@export var overrides: Dictionary = {}
@export_enum("door", "chest", "mechanism", "building", "resource_node", "pickup", "destructible") var object_kind: String = "chest"

@export_group("装配组合")
@export var appearance_scene: PackedScene
@export var ability_definitions: Array[GMAbilityDefinition] = []
@export var interaction_recipe: GMInteractionRecipe
@export var collision_shape: Shape2D
@export var persistent: bool = true
@export var semantic_type_id: StringName = &"object.interactive"
@export var anchor_names: PackedStringArray = PackedStringArray(["interaction", "presentation"])
@export var state_defaults: Dictionary = {}
@export var schema_version: String = SCHEMA

func resolve_effective() -> Dictionary:
	var chain: Array[GMObjectDefinition] = []
	var seen := {}
	var cursor: GMObjectDefinition = self
	while cursor != null:
		var key := cursor.get_instance_id()
		if seen.has(key):
			return _failure("object.prototype_cycle", "对象原型形成循环，已拒绝解析。", {"content_id": content_id})
		seen[key] = true
		chain.push_front(cursor)
		cursor = cursor.prototype
	var effective := _base_snapshot(chain[0])
	for definition in chain:
		var checked := definition._validate_overrides()
		if not checked.ok: return checked
		for field in definition.overrides:
			effective[field] = _deep_copy(definition.overrides[field])
	effective["content_id"] = content_id
	effective["prototype_depth"] = chain.size() - 1
	effective["schema_version"] = schema_version
	var validation := _validate_effective(effective)
	if not validation.ok: return validation
	return {"ok": true, "effective": effective, "prototype_depth": chain.size() - 1}

func validate_definition() -> Dictionary:
	return resolve_effective()

func _base_snapshot(value: GMObjectDefinition, inherited: Dictionary = {}) -> Dictionary:
	var result := inherited.duplicate(true)
	result["display_name_zh"] = value.display_name_zh
	result["object_kind"] = value.object_kind
	result["appearance_scene"] = value.appearance_scene
	result["ability_definitions"] = value.ability_definitions.duplicate()
	result["interaction_recipe"] = value.interaction_recipe
	result["collision_shape"] = value.collision_shape
	result["persistent"] = value.persistent
	result["semantic_type_id"] = value.semantic_type_id
	result["anchor_names"] = value.anchor_names.duplicate()
	result["state_defaults"] = value.state_defaults.duplicate(true)
	return result

func _validate_overrides() -> Dictionary:
	for field in overrides:
		if not OVERRIDABLE_FIELDS.has(str(field)):
			return _failure("object.override_field_unknown", "对象覆盖字段不受支持：%s" % field, {"field": str(field)})
		var expected := _expected_type(str(field))
		if expected != TYPE_NIL and typeof(overrides[field]) != expected:
			return _failure("object.override_type_mismatch", "对象覆盖字段类型错误：%s" % field, {"field": str(field), "expected_type": expected, "actual_type": typeof(overrides[field])})
	return {"ok": true}

func _validate_effective(value: Dictionary) -> Dictionary:
	if content_id.strip_edges().is_empty(): return _failure("object.content_id_missing", "对象定义缺少任务03稳定内容ID。")
	if str(value.get("object_kind", "")) not in OBJECT_KINDS: return _failure("object.kind_invalid", "对象策划类型不受支持。")
	if value.get("interaction_recipe", null) == null: return _failure("object.recipe_missing", "对象定义缺少交互配方。")
	if value.get("collision_shape", null) == null: return _failure("object.collision_shape_missing", "对象定义缺少碰撞形状。")
	var ability_ids := {}
	for ability in value.get("ability_definitions", []):
		if ability == null or not ability is GMAbilityDefinition or ability.ability_id.strip_edges().is_empty():
			return _failure("object.ability_definition_invalid", "对象能力组合包含空项或缺少稳定能力ID。")
		if ability_ids.has(ability.ability_id): return _failure("object.ability_duplicate", "对象能力组合存在重复能力ID：%s" % ability.ability_id)
		ability_ids[ability.ability_id] = true
	var recipe: GMInteractionRecipe = value.get("interaction_recipe", null)
	var recipe_check := recipe.validate_recipe()
	if not recipe_check.ok: return recipe_check
	if not ability_ids.has(recipe.ability_id):
		return _failure("object.recipe_ability_missing", "交互配方引用的能力没有包含在对象能力组合中：%s" % recipe.ability_id)
	return {"ok": true}

func _expected_type(field: String) -> int:
	match field:
		"display_name_zh", "object_kind": return TYPE_STRING
		"appearance_scene", "interaction_recipe", "collision_shape": return TYPE_OBJECT
		"ability_definitions", "anchor_names": return TYPE_ARRAY
		"persistent": return TYPE_BOOL
		"semantic_type_id": return TYPE_STRING_NAME
		"state_defaults": return TYPE_DICTIONARY
	return TYPE_NIL

func _deep_copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": message, "details": details}
