extends RefCounted

## P24 -> P23 装配入口。
##
## 先调用既有 GMSceneRecipeBuilder 验证/解析 SceneRecipe，再把 P24 对象
## Definition 绑定到同一批语义槽。输出仍是纯值投影；后端不会成为场景事实。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const SCENE_RECIPE := preload("res://gm_runtime/scene/gm_scene_recipe.gd")
const LEVEL_RECIPE := preload("res://gm_runtime/level/gm_level_object_recipe.gd")
const DEFINITION := preload("res://gm_runtime/level/gm_level_object_definition.gd")
const P23_BUILDER := preload("res://gm_runtime/scene/gm_scene_recipe_builder.gd")
const ADAPTER := preload("res://gm_runtime/level/gm_level_object_backend_adapter.gd")
const GENERATOR := preload("res://gm_runtime/level/gm_level_object_generator.gd")

const SCHEMA_VERSION := "gm.level.object_assembly.v1"
const FIELDS: Array[String] = ["schema_version", "level_recipe_id", "scene_recipe_id", "backend_domain", "scene_build", "objects", "generators", "assembly_fingerprint"]

func assemble(
	scene_recipe_value: Variant,
	level_recipe_value: Variant,
	skeleton_value: Variant,
	context_value: Variant,
	backend: Object,
	presentation_by_definition: Dictionary = {}
) -> Dictionary:
	var scene_check := _as_scene_recipe(scene_recipe_value)
	if not scene_check.ok:
		return scene_check
	var level_check := _as_level_recipe(level_recipe_value)
	if not level_check.ok:
		return level_check
	var scene: GMSceneRecipe = scene_check.value
	var level = level_check.value
	var bound: Dictionary = level.validate_against_scene(scene)
	if not bound.ok:
		return bound
	var p23_builder := P23_BUILDER.new()
	var scene_build := p23_builder.build(scene, skeleton_value, context_value, backend)
	if not scene_build.ok:
		return {"ok": false, "code": "level_object.assembly.scene_build", "error_zh": "P24对象装配未通过既有P23 SceneRecipeBuilder。", "detail": scene_build}
	var adapter := ADAPTER.new(backend)
	var slot_map := {}
	for raw_slot in scene.slots:
		if typeof(raw_slot) == TYPE_DICTIONARY:
			slot_map[str(raw_slot.get("slot_id", ""))] = raw_slot
	var definitions := {}
	for raw_definition in level.definitions:
		var definition_check := DEFINITION.from_dict(raw_definition)
		if not definition_check.ok:
			return definition_check
		definitions[definition_check.value.definition_id] = definition_check.value
	var projections: Array = []
	for raw_object in level.objects:
		var definition = definitions.get(str(raw_object.definition_id), null)
		if definition == null:
			return _blocked("level_object.assembly.definition_missing", "P24对象装配引用了不存在的Definition。")
		var slot: Dictionary = slot_map.get(str(raw_object.slot_id), {})
		if slot.is_empty():
			return _blocked("level_object.assembly.slot_missing", "P24对象装配引用了不存在的语义槽。")
		var presentation: Dictionary = presentation_by_definition.get(definition.definition_id, {})
		var projection := adapter.materialize(definition, raw_object, slot, presentation)
		if not projection.ok:
			return {"ok": false, "code": "level_object.assembly.object_projection", "error_zh": "P24对象无法由当前后端适配。", "object_id": str(raw_object.object_id), "detail": projection}
		projections.append(projection.value)
	projections.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left.object_id) < str(right.object_id))
	var generator_rows: Array = []
	for raw_generator in level.generators:
		generator_rows.append(VALUE.duplicate_value(raw_generator))
	generator_rows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left.generator_id) < str(right.generator_id))
	var body: Dictionary = VALUE.persistence_canonical({
		"schema_version": SCHEMA_VERSION,
		"level_recipe_id": level.recipe_id,
		"scene_recipe_id": scene.recipe_id,
		"backend_domain": str(scene_build.value.backend_domain),
		"scene_build": VALUE.duplicate_value(scene_build.value),
		"objects": projections,
		"generators": generator_rows
	})
	var persistence := VALUE.persistence(body)
	if not persistence.ok:
		return _blocked("level_object.assembly.persistence", "P24对象装配输出不是可持久化纯值。", persistence)
	body["assembly_fingerprint"] = VALUE.digest(body)
	var parsed := parse_assembly(body)
	if not parsed.ok:
		return parsed
	return {"ok": true, "value": parsed.value}

func generate(level_recipe_value: Variant, generator_id: String) -> Dictionary:
	var level_check := _as_level_recipe(level_recipe_value)
	if not level_check.ok:
		return level_check
	var level = level_check.value
	if not VALUE.stable_id(generator_id, false):
		return _blocked("level_object.assembly.generator_id", "P24生成器ID无效。")
	for raw_generator in level.generators:
		if str(raw_generator.get("generator_id", "")) != generator_id:
			continue
		var definition_check: Dictionary = level._definition_by_id(str(raw_generator.get("definition_id", "")))
		if not definition_check.ok:
			return definition_check
		return GENERATOR.new().generate(raw_generator, definition_check.value)
	return _blocked("level_object.assembly.generator_missing", "P24对象配方没有该generator。", {"generator_id": generator_id})

func materialize_generated(
	generation_value: Variant,
	definition_value: Variant,
	slot_value: Variant,
	backend: Object,
	presentation: Dictionary = {}
) -> Dictionary:
	var generation_check := GENERATOR.parse_generation(generation_value)
	if not generation_check.ok:
		return generation_check
	var definition_check := _as_definition(definition_value)
	if not definition_check.ok:
		return definition_check
	var adapter := ADAPTER.new(backend)
	for raw_generated in generation_check.value.generated_objects:
		if str(raw_generated.get("definition_id", "")) != str(definition_check.value.definition_id):
			return _blocked(
				"level_object.assembly.generated_definition_mismatch",
				"生成对象Definition标识与物化Definition不一致，拒绝物化。",
				{"generated_definition_id": str(raw_generated.get("definition_id", "")), "materialize_definition_id": str(definition_check.value.definition_id), "object_id": str(raw_generated.get("object_id", ""))}
			)
	var projections: Array = []
	for raw_generated in generation_check.value.generated_objects:
		var binding := {
			"object_id": str(raw_generated.object_id),
			"definition_id": str(raw_generated.definition_id),
			"slot_id": str(raw_generated.slot_id),
			"initial_state": {},
			"tags": []
		}
		var projection := adapter.materialize(definition_check.value, binding, slot_value, presentation)
		if not projection.ok:
			return {"ok": false, "code": "level_object.assembly.generated_projection", "error_zh": "生成对象无法由当前后端适配。", "detail": projection}
		projections.append(projection.value)
	projections.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left.object_id) < str(right.object_id))
	return {"ok": true, "schema_version": "gm.level.generated_projection.v1", "generator_id": str(generation_check.value.generator_id), "backend_domain": str(projections[0].backend_domain) if not projections.is_empty() else "", "objects": projections, "projection_only": true}

static func parse_assembly(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var persistence := VALUE.persistence(value)
	if not persistence.ok:
		return _blocked("level_object.assembly.persistence", "P24对象装配必须是可持久化纯值。")
	if str(value.schema_version) != SCHEMA_VERSION:
		return _blocked("level_object.assembly.schema", "P24对象装配Schema版本不匹配。")
	for identity in ["level_recipe_id", "scene_recipe_id", "backend_domain"]:
		if not VALUE.stable_id(value.get(identity, ""), false):
			return _blocked("level_object.assembly.identity", "P24对象装配包含非法稳定标识。", {"field": identity})
	if typeof(value.scene_build) != TYPE_DICTIONARY or not P23_BUILDER.parse_build(value.scene_build).ok:
		return _blocked("level_object.assembly.scene_build", "P24对象装配中的P23 SceneRecipeBuild无效。")
	if str(value.scene_build.backend_domain) != str(value.backend_domain):
		return _blocked("level_object.assembly.domain", "P24对象装配后端域与P23 SceneRecipeBuild不一致。")
	if typeof(value.objects) != TYPE_ARRAY or typeof(value.generators) != TYPE_ARRAY:
		return _blocked("level_object.assembly.collections", "P24对象装配对象与生成器必须是数组。")
	var object_ids := {}
	for projection in value.objects:
		var projection_check := preload("res://gm_runtime/level/gm_level_object_backend_adapter.gd").parse_projection(projection)
		if not projection_check.ok:
			return _blocked("level_object.assembly.projection", "P24对象装配包含非法后端投影。", projection_check)
		var object_id := str(projection_check.value.object_id)
		if object_ids.has(object_id):
			return _blocked("level_object.assembly.object_duplicate", "P24对象装配对象ID重复。")
		object_ids[object_id] = true
	var generator_ids := {}
	for generator in value.generators:
		var generator_fields := VALUE.exact_fields(generator, LEVEL_RECIPE.GENERATOR_FIELDS)
		if not generator_fields.ok:
			return _blocked("level_object.assembly.generator", "P24对象装配包含非法生成配方。")
		if generator_ids.has(str(generator.generator_id)):
			return _blocked("level_object.assembly.generator_duplicate", "P24对象装配生成器ID重复。")
		generator_ids[str(generator.generator_id)] = true
	if str(value.assembly_fingerprint).is_empty() or not VALUE.stable_id(value.assembly_fingerprint, false):
		return _blocked("level_object.assembly.fingerprint", "P24对象装配fingerprint无效。")
	var body: Dictionary = VALUE.persistence_canonical({
		"schema_version": SCHEMA_VERSION,
		"level_recipe_id": str(value.level_recipe_id),
		"scene_recipe_id": str(value.scene_recipe_id),
		"backend_domain": str(value.backend_domain),
		"scene_build": VALUE.duplicate_value(value.scene_build),
		"objects": VALUE.duplicate_value(value.objects),
		"generators": VALUE.duplicate_value(value.generators)
	})
	if VALUE.digest(body) != str(value.assembly_fingerprint):
		return _blocked("level_object.assembly.fingerprint_mismatch", "P24对象装配fingerprint与内容不一致。")
	return {"ok": true, "value": body.merged({"assembly_fingerprint": str(value.assembly_fingerprint)}, true)}

static func _as_scene_recipe(value: Variant) -> Dictionary:
	if value is GMSceneRecipe:
		return {"ok": true, "value": value}
	return SCENE_RECIPE.from_dict(value)

static func _as_level_recipe(value: Variant) -> Dictionary:
	if value is RefCounted and value.get_script() == LEVEL_RECIPE:
		return {"ok": true, "value": value}
	return LEVEL_RECIPE.from_dict(value)

static func _as_definition(value: Variant) -> Dictionary:
	if value is RefCounted and value.get_script() == DEFINITION:
		return {"ok": true, "value": value}
	return DEFINITION.from_dict(value)

static func _blocked(code: String, error_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error_zh": error_zh}
	if not details.is_empty():
		result["details"] = VALUE.duplicate_value(details)
	return result
