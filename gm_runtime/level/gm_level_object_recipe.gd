extends RefCounted

## P24 关卡对象配方。
##
## 它是 P23 SceneRecipe 的窄扩展：每个对象都必须绑定到既有语义槽，定义
## 只引用稳定 ID，生成器输入也只保留纯值。它不复制 SceneRecipe、SceneSession
## 或任何领域 Store。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const SCENE_RECIPE := preload("res://gm_runtime/scene/gm_scene_recipe.gd")
const DEFINITION := preload("res://gm_runtime/level/gm_level_object_definition.gd")

const SCHEMA_VERSION := "gm.level.object_recipe.v1"
const FIELDS: Array[String] = ["schema_version", "recipe_id", "scene_recipe_id", "definitions", "objects", "generators", "variation_tokens"]
const OBJECT_FIELDS: Array[String] = ["object_id", "definition_id", "slot_id", "initial_state", "tags"]
const GENERATOR_FIELDS: Array[String] = ["generator_id", "definition_id", "slot_id", "count", "actor_recipe", "task_budget", "seed", "generated_kind", "generated_definition_id", "tags"]
const ALLOWED_OBJECT_SLOT_KINDS: Array[String] = ["object", "facility", "extraction", "entry", "exit", "resource", "objective"]

var recipe_id: String
var scene_recipe_id: String
var definitions: Array
var objects: Array
var generators: Array
var variation_tokens: Array

func _init(
	p_recipe_id: String = "",
	p_scene_recipe_id: String = "",
	p_definitions: Array = [],
	p_objects: Array = [],
	p_generators: Array = [],
	p_variation_tokens: Array = []
) -> void:
	recipe_id = p_recipe_id
	scene_recipe_id = p_scene_recipe_id
	definitions = VALUE.duplicate_value(p_definitions)
	objects = VALUE.duplicate_value(p_objects)
	generators = VALUE.duplicate_value(p_generators)
	variation_tokens = VALUE.duplicate_value(p_variation_tokens)

static func from_dict(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var stable := VALUE.persistence(value)
	if not stable.ok:
		return {"ok": false, "code": "level_object.recipe.persistence", "error_zh": "P24对象配方必须是可持久化纯值。", "detail": stable}
	if str(value.get("schema_version", "")) != SCHEMA_VERSION:
		return {"ok": false, "code": "level_object.recipe.schema", "error_zh": "P24对象配方Schema版本不匹配。"}
	for identity in ["recipe_id", "scene_recipe_id"]:
		if not VALUE.stable_id(value.get(identity, ""), false):
			return {"ok": false, "code": "level_object.recipe.identity", "error_zh": "P24对象配方包含非法稳定标识。", "field": identity}
	var definitions_check := _validate_definitions(value.definitions)
	if not definitions_check.ok:
		return definitions_check
	var objects_check := _validate_objects(value.objects, definitions_check.value)
	if not objects_check.ok:
		return objects_check
	var generators_check := _validate_generators(value.generators, definitions_check.value, objects_check.value)
	if not generators_check.ok:
		return generators_check
	var variation_check := VALUE.string_array(value.variation_tokens, true)
	if not variation_check.ok:
		return {"ok": false, "code": "level_object.recipe.variation", "error_zh": "P24对象配方变化选项必须是稳定字符串数组。"}
	var recipe = load("res://gm_runtime/level/gm_level_object_recipe.gd").new(
		str(value.recipe_id), str(value.scene_recipe_id), definitions_check.value,
		objects_check.value, generators_check.value, variation_check.value
	)
	return {"ok": true, "value": recipe}

static func from_json(text: String) -> Dictionary:
	var parsed := VALUE.parse_json(text)
	if not parsed.ok:
		return parsed
	return from_dict(parsed.value)

static func from_scene_recipe(
	p_scene_recipe: Variant,
	p_recipe_id: String,
	p_definitions: Array,
	p_objects: Array,
	p_generators: Array = [],
	p_variation_tokens: Array = []
) -> Dictionary:
	var scene_check := _as_scene_recipe(p_scene_recipe)
	if not scene_check.ok:
		return scene_check
	var scene: GMSceneRecipe = scene_check.value
	var candidate = load("res://gm_runtime/level/gm_level_object_recipe.gd").new(p_recipe_id, scene.recipe_id, p_definitions, p_objects, p_generators, p_variation_tokens)
	var local_check: Dictionary = candidate.validate()
	if not local_check.ok:
		return local_check
	var bound: Dictionary = candidate.validate_against_scene(scene)
	if not bound.ok:
		return bound
	return {"ok": true, "value": candidate}

func validate_against_scene(scene_value: Variant) -> Dictionary:
	var scene_check := _as_scene_recipe(scene_value)
	if not scene_check.ok:
		return scene_check
	var scene: GMSceneRecipe = scene_check.value
	if scene.recipe_id != scene_recipe_id:
		return {"ok": false, "code": "level_object.recipe.scene_mismatch", "error_zh": "P24对象配方没有绑定当前P23 SceneRecipe。"}
	var semantic_objects := {}
	for raw_object in scene.semantic_objects:
		if typeof(raw_object) == TYPE_DICTIONARY:
			semantic_objects[str(raw_object.get("object_id", ""))] = raw_object
	var slots := {}
	var slot_use_counts := {}
	for raw_slot in scene.slots:
		if typeof(raw_slot) != TYPE_DICTIONARY:
			continue
		slots[str(raw_slot.get("slot_id", ""))] = raw_slot
	for raw_object in objects:
		var object_id := str(raw_object.get("object_id", ""))
		var slot_id := str(raw_object.get("slot_id", ""))
		if not semantic_objects.has(object_id):
			return {"ok": false, "code": "level_object.recipe.object_not_in_scene", "error_zh": "P24对象必须先出现在P23 SceneRecipe semantic_objects中。", "object_id": object_id}
		if not slots.has(slot_id):
			return {"ok": false, "code": "level_object.recipe.slot_missing", "error_zh": "P24对象绑定了不存在的P23语义槽。", "slot_id": slot_id}
		var slot: Dictionary = slots[slot_id]
		var slot_kind := str(slot.get("slot_kind", ""))
		if not ALLOWED_OBJECT_SLOT_KINDS.has(slot_kind):
			return {"ok": false, "code": "level_object.recipe.slot_kind", "error_zh": "P24对象只能装配到对象/设施/入口/撤离等语义槽。", "slot_id": slot_id}
		if typeof(slot.get("target_ref", null)) != TYPE_DICTIONARY or slot.target_ref.is_empty():
			return {"ok": false, "code": "level_object.recipe.slot_unbound", "error_zh": "P24对象语义槽必须有稳定目标绑定。", "slot_id": slot_id}
		slot_use_counts[slot_id] = int(slot_use_counts.get(slot_id, 0)) + 1
		var capacity := int(slot.get("capacity", 1))
		if int(slot_use_counts[slot_id]) > capacity:
			return {"ok": false, "code": "level_object.recipe.slot_capacity", "error_zh": "P24对象数量超过语义槽容量。", "slot_id": slot_id}
		var semantic_kind := str(semantic_objects[object_id].get("object_kind", ""))
		var definition_kind := _definition_kind(str(raw_object.get("definition_id", "")))
		if not definition_kind.ok:
			return definition_kind
		if semantic_kind != definition_kind.object_kind:
			return {"ok": false, "code": "level_object.recipe.kind_mismatch", "error_zh": "P24对象类别必须与P23 semantic_object类别一致。", "object_id": object_id}
	for raw_generator in generators:
		var generator_id := str(raw_generator.get("generator_id", ""))
		var definition_check := _definition_by_id(str(raw_generator.get("definition_id", "")))
		if not definition_check.ok:
			return definition_check
		if definition_check.value.object_kind != "generator":
			return {"ok": false, "code": "level_object.recipe.generator_kind", "error_zh": "生成配方必须引用generator定义。", "generator_id": generator_id}
		var binding_found := false
		for raw_object in objects:
			if str(raw_object.get("object_id", "")) == generator_id and str(raw_object.get("definition_id", "")) == str(raw_generator.get("definition_id", "")) and str(raw_object.get("slot_id", "")) == str(raw_generator.get("slot_id", "")):
				binding_found = true
				break
		if not binding_found:
			return {"ok": false, "code": "level_object.recipe.generator_unbound", "error_zh": "生成配方必须绑定到同一SceneRecipe语义槽中的generator对象。", "generator_id": generator_id}
		if not slots.has(str(raw_generator.get("slot_id", ""))):
			return {"ok": false, "code": "level_object.recipe.generator_slot_missing", "error_zh": "生成配方语义槽不存在。", "generator_id": generator_id}
	return {"ok": true, "scene_recipe_id": scene.recipe_id}

static func _validate_definitions(values: Variant) -> Dictionary:
	if typeof(values) != TYPE_ARRAY or values.is_empty():
		return {"ok": false, "code": "level_object.recipe.definitions", "error_zh": "P24对象配方至少需要一个Definition。"}
	var normalized: Array = []
	var ids := {}
	for raw_definition in values:
		var check := DEFINITION.from_dict(raw_definition)
		if not check.ok:
			return {"ok": false, "code": "level_object.recipe.definition_invalid", "error_zh": "P24对象配方包含非法Definition。", "detail": check}
		var definition = check.value
		if ids.has(definition.definition_id):
			return {"ok": false, "code": "level_object.recipe.definition_duplicate", "error_zh": "P24对象Definition ID重复。"}
		ids[definition.definition_id] = true
		normalized.append(definition.to_dict())
	return {"ok": true, "value": normalized}

static func _validate_objects(values: Variant, definitions: Array) -> Dictionary:
	if typeof(values) != TYPE_ARRAY:
		return {"ok": false, "code": "level_object.recipe.objects_type", "error_zh": "P24对象绑定必须是数组。"}
	var normalized: Array = []
	var ids := {}
	for raw_object in values:
		var fields := VALUE.exact_fields(raw_object, OBJECT_FIELDS)
		if not fields.ok:
			return fields
		for identity in ["object_id", "definition_id", "slot_id"]:
			if not VALUE.stable_id(raw_object.get(identity, ""), false):
				return {"ok": false, "code": "level_object.recipe.object_identity", "error_zh": "P24对象绑定标识无效。", "field": identity}
		var object_id := str(raw_object.object_id)
		if ids.has(object_id):
			return {"ok": false, "code": "level_object.recipe.object_duplicate", "error_zh": "P24对象ID重复。", "object_id": object_id}
		if not _contains_definition(definitions, str(raw_object.definition_id)):
			return {"ok": false, "code": "level_object.recipe.definition_missing", "error_zh": "P24对象绑定引用了不存在的Definition。", "definition_id": str(raw_object.definition_id)}
		if typeof(raw_object.initial_state) != TYPE_DICTIONARY or not VALUE.persistence(raw_object.initial_state).ok:
			return {"ok": false, "code": "level_object.recipe.initial_state", "error_zh": "P24对象初始状态必须是可持久化纯字典。"}
		var tags := VALUE.string_array(raw_object.tags, true)
		if not tags.ok:
			return {"ok": false, "code": "level_object.recipe.object_tags", "error_zh": "P24对象标签无效。"}
		ids[object_id] = true
		normalized.append({"object_id": object_id, "definition_id": str(raw_object.definition_id), "slot_id": str(raw_object.slot_id), "initial_state": VALUE.duplicate_value(raw_object.initial_state), "tags": tags.value})
	return {"ok": true, "value": normalized}

static func _validate_generators(values: Variant, definitions: Array, objects: Array) -> Dictionary:
	if typeof(values) != TYPE_ARRAY:
		return {"ok": false, "code": "level_object.recipe.generators_type", "error_zh": "P24生成配方必须是数组。"}
	var normalized: Array = []
	var ids := {}
	for raw_generator in values:
		var fields := VALUE.exact_fields(raw_generator, GENERATOR_FIELDS)
		if not fields.ok:
			return fields
		var generator_id := str(raw_generator.generator_id)
		for identity in ["generator_id", "definition_id", "slot_id", "generated_kind", "generated_definition_id"]:
			if not VALUE.stable_id(raw_generator.get(identity, ""), false):
				return {"ok": false, "code": "level_object.recipe.generator_identity", "error_zh": "P24生成配方标识无效。", "field": identity}
		if ids.has(generator_id):
			return {"ok": false, "code": "level_object.recipe.generator_duplicate", "error_zh": "P24生成器ID重复。"}
		var definition_check := _definition_from_array(definitions, str(raw_generator.definition_id))
		if not definition_check.ok:
			return definition_check
		if definition_check.value.object_kind != "generator":
			return {"ok": false, "code": "level_object.recipe.generator_definition", "error_zh": "P24生成配方必须使用generator Definition。"}
		var count_check := VALUE.integer_field(raw_generator.count, false)
		if not count_check.ok or int(count_check.value) < 1:
			return {"ok": false, "code": "level_object.recipe.generator_count", "error_zh": "P24生成数量必须是正整数。"}
		var seed_check := VALUE.safe_int(raw_generator.seed, true)
		if not seed_check.ok:
			return {"ok": false, "code": "level_object.recipe.generator_seed", "error_zh": "P24生成器seed必须是JSON安全整数。"}
		if typeof(raw_generator.actor_recipe) != TYPE_DICTIONARY or not VALUE.persistence(raw_generator.actor_recipe).ok:
			return {"ok": false, "code": "level_object.recipe.actor_recipe", "error_zh": "ActorRecipe输入必须是可持久化纯字典。"}
		var budget_check := _validate_budget(raw_generator.task_budget)
		if not budget_check.ok:
			return budget_check
		var tags := VALUE.string_array(raw_generator.tags, true)
		if not tags.ok:
			return {"ok": false, "code": "level_object.recipe.generator_tags", "error_zh": "P24生成器标签无效。"}
		ids[generator_id] = true
		normalized.append({
			"generator_id": generator_id, "definition_id": str(raw_generator.definition_id), "slot_id": str(raw_generator.slot_id),
			"count": int(count_check.value), "actor_recipe": VALUE.duplicate_value(raw_generator.actor_recipe),
			"task_budget": budget_check.value, "seed": int(seed_check.value), "generated_kind": str(raw_generator.generated_kind),
			"generated_definition_id": str(raw_generator.generated_definition_id), "tags": tags.value
		})
	return {"ok": true, "value": normalized}

static func _validate_budget(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "code": "level_object.recipe.budget_type", "error_zh": "task_budget必须是字典。"}
	var fields := VALUE.exact_fields(value, ["budget_id", "remaining", "unit"])
	if not fields.ok:
		return {"ok": false, "code": "level_object.recipe.budget_shape", "error_zh": "task_budget字段集合无效。", "detail": fields}
	if not VALUE.stable_id(value.budget_id, false) or not VALUE.stable_id(value.unit, false):
		return {"ok": false, "code": "level_object.recipe.budget_identity", "error_zh": "task_budget必须包含稳定budget_id与unit。"}
	var remaining := VALUE.integer_field(value.remaining, false)
	if not remaining.ok:
		return {"ok": false, "code": "level_object.recipe.budget_remaining", "error_zh": "task_budget.remaining必须是非负整数。"}
	return {"ok": true, "value": {"budget_id": str(value.budget_id), "remaining": int(remaining.value), "unit": str(value.unit)}}

static func _as_scene_recipe(value: Variant) -> Dictionary:
	if value is GMSceneRecipe:
		return {"ok": true, "value": value}
	return SCENE_RECIPE.from_dict(value)

static func _contains_definition(values: Array, definition_id: String) -> bool:
	return _definition_from_array(values, definition_id).ok

static func _definition_from_array(values: Array, definition_id: String) -> Dictionary:
	for raw_definition in values:
		if typeof(raw_definition) == TYPE_DICTIONARY and str(raw_definition.get("definition_id", "")) == definition_id:
			var check := DEFINITION.from_dict(raw_definition)
			return check
	return {"ok": false, "code": "level_object.recipe.definition_missing", "error_zh": "P24对象配方引用了不存在的Definition。", "definition_id": definition_id}

func _definition_by_id(definition_id: String) -> Dictionary:
	return _definition_from_array(definitions, definition_id)

func _definition_kind(definition_id: String) -> Dictionary:
	var check := _definition_by_id(definition_id)
	if not check.ok:
		return check
	return {"ok": true, "object_kind": check.value.object_kind}

func validate() -> Dictionary:
	return load("res://gm_runtime/level/gm_level_object_recipe.gd").from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"recipe_id": recipe_id,
		"scene_recipe_id": scene_recipe_id,
		"definitions": VALUE.duplicate_value(definitions),
		"objects": VALUE.duplicate_value(objects),
		"generators": VALUE.duplicate_value(generators),
		"variation_tokens": VALUE.duplicate_value(variation_tokens)
	}

func to_json() -> String:
	return VALUE.json_string(to_dict())

func fingerprint() -> String:
	return VALUE.digest(VALUE.persistence_canonical(to_dict()))
