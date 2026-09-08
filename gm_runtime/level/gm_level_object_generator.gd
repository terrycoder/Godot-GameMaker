extends RefCounted

## P24 纯值生成器。
##
## 生成顺序固定为：校验输入 -> 计算稳定业务ID -> 产出领域对象描述；后端
## 适配/物化由 GMLevelObjectBackendAdapter 单独完成。这里不创建 Actor、Node、
## SpawnRegistry 或 SceneSession，也不修改调用方的 task_budget。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const DEFINITION := preload("res://gm_runtime/level/gm_level_object_definition.gd")
const RECIPE := preload("res://gm_runtime/level/gm_level_object_recipe.gd")

const SCHEMA_VERSION := "gm.level.object_generation.v1"
const GENERATED_OBJECT_SCHEMA := "gm.level.generated_object.v1"
const FIELDS: Array[String] = [
	"schema_version", "generator_id", "definition_id", "seed", "count", "actor_recipe_id",
	"actor_recipe", "budget_before", "budget_consumed", "budget_after", "generated_objects", "generation_fingerprint"
]
const GENERATED_FIELDS: Array[String] = [
	"schema_version", "object_id", "object_kind", "definition_id", "source_generator_id",
	"slot_id", "index", "seed", "actor_recipe_id", "actor_recipe"
]

func generate(generator_value: Variant, definition_value: Variant) -> Dictionary:
	var generator_check := _validate_generator_input(generator_value)
	if not generator_check.ok:
		return generator_check
	var definition_check := _as_definition(definition_value)
	if not definition_check.ok:
		return definition_check
	var definition = definition_check.value
	var generator: Dictionary = generator_check.value
	if definition.object_kind != "generator":
		return _blocked("level_object.generator.definition_kind", "生成器必须使用generator Definition。")
	if str(generator.definition_id) != definition.definition_id:
		return _blocked("level_object.generator.definition_mismatch", "生成配方与generator Definition标识不一致。")
	var actor_recipe: Dictionary = generator.actor_recipe
	var actor_recipe_id := ""
	if not actor_recipe.is_empty():
		actor_recipe_id = str(actor_recipe.get("actor_recipe_id", actor_recipe.get("recipe_id", "")))
		if not VALUE.stable_id(actor_recipe_id, false):
			return _blocked("level_object.generator.actor_recipe_identity", "ActorRecipe必须提供稳定recipe_id或actor_recipe_id。")
	var budget_check := _validate_budget(generator.task_budget)
	if not budget_check.ok:
		return budget_check
	var budget_before: Dictionary = budget_check.value
	var count := int(generator.count)
	if count > int(budget_before.remaining):
		return _blocked("level_object.generator.budget_exceeded", "生成数量超过调用方提供的task budget；失败不产生部分对象。", {"requested": count, "remaining": int(budget_before.remaining)})
	var generated: Array = []
	for index in range(count):
		var identity_seed := {
			"generator_id": str(generator.generator_id),
			"definition_id": definition.definition_id,
			"seed": int(generator.seed),
			"index": index,
			"generated_kind": str(generator.generated_kind),
			"generated_definition_id": str(generator.generated_definition_id),
			"actor_recipe_id": actor_recipe_id
		}
		var object_id := "gm.generated.%s.%d" % [VALUE.digest(identity_seed).substr(0, 24), index]
		generated.append({
			"schema_version": GENERATED_OBJECT_SCHEMA,
			"object_id": object_id,
			"object_kind": str(generator.generated_kind),
			"definition_id": str(generator.generated_definition_id),
			"source_generator_id": str(generator.generator_id),
			"slot_id": str(generator.slot_id),
			"index": index,
			"seed": int(generator.seed),
			"actor_recipe_id": actor_recipe_id,
			"actor_recipe": VALUE.duplicate_value(actor_recipe)
		})
	var budget_after := budget_before.duplicate(true)
	budget_after.remaining = int(budget_before.remaining) - count
	var body: Dictionary = VALUE.persistence_canonical({
		"schema_version": SCHEMA_VERSION,
		"generator_id": str(generator.generator_id),
		"definition_id": definition.definition_id,
		"seed": int(generator.seed),
		"count": count,
		"actor_recipe_id": actor_recipe_id,
		"actor_recipe": VALUE.duplicate_value(actor_recipe),
		"budget_before": budget_before,
		"budget_consumed": count,
		"budget_after": budget_after,
		"generated_objects": generated
	})
	var persistence := VALUE.persistence(body)
	if not persistence.ok:
		return _blocked("level_object.generator.output_persistence", "生成器输出不是可持久化纯值。", persistence)
	body["generation_fingerprint"] = VALUE.digest(body)
	var parsed := parse_generation(body)
	if not parsed.ok:
		return parsed
	return {"ok": true, "value": parsed.value}

static func parse_generation(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var stable := VALUE.persistence(value)
	if not stable.ok:
		return {"ok": false, "code": "level_object.generation.persistence", "error_zh": "生成结果必须是可持久化纯值。", "detail": stable}
	if str(value.get("schema_version", "")) != SCHEMA_VERSION:
		return _blocked("level_object.generation.schema", "生成结果Schema版本不匹配。")
	for identity in ["generator_id", "definition_id"]:
		if not VALUE.stable_id(value.get(identity, ""), false):
			return _blocked("level_object.generation.identity", "生成结果包含非法稳定标识。", {"field": identity})
	if not VALUE.stable_id(value.actor_recipe_id, true):
		return _blocked("level_object.generation.actor_recipe", "生成结果ActorRecipe标识无效。")
	var seed_check := VALUE.safe_int(value.seed, true)
	var count_check := VALUE.integer_field(value.count, false)
	var consumed_check := VALUE.integer_field(value.budget_consumed, false)
	if not seed_check.ok or not count_check.ok or not consumed_check.ok or int(count_check.value) < 1 or int(consumed_check.value) != int(count_check.value):
		return _blocked("level_object.generation.count", "生成结果seed/count/budget_consumed不一致。")
	if typeof(value.actor_recipe) != TYPE_DICTIONARY or not VALUE.persistence(value.actor_recipe).ok:
		return _blocked("level_object.generation.actor_recipe", "生成结果ActorRecipe不是纯字典。")
	var before_check := _validate_budget(value.budget_before)
	var after_check := _validate_budget(value.budget_after)
	if not before_check.ok or not after_check.ok:
		return _blocked("level_object.generation.budget", "生成结果task budget无效。")
	if str(before_check.value.budget_id) != str(after_check.value.budget_id) or str(before_check.value.unit) != str(after_check.value.unit):
		return _blocked("level_object.generation.budget_identity", "生成结果前后budget身份不一致。")
	if int(after_check.value.remaining) != int(before_check.value.remaining) - int(consumed_check.value):
		return _blocked("level_object.generation.budget_mismatch", "生成结果budget剩余量与消耗量不一致。")
	if typeof(value.generated_objects) != TYPE_ARRAY or value.generated_objects.size() != int(count_check.value):
		return _blocked("level_object.generation.objects", "生成结果对象数量与count不一致。")
	var object_ids := {}
	for raw_object in value.generated_objects:
		var object_check := _parse_generated_object(raw_object)
		if not object_check.ok:
			return object_check
		var object_id := str(object_check.value.object_id)
		if object_ids.has(object_id):
			return _blocked("level_object.generation.object_duplicate", "生成结果对象stable ID重复。")
		object_ids[object_id] = true
		if str(object_check.value.source_generator_id) != str(value.generator_id):
			return _blocked("level_object.generation.object_origin", "生成对象没有绑定同一generator来源。")
	var body: Dictionary = VALUE.persistence_canonical({
		"schema_version": SCHEMA_VERSION,
		"generator_id": str(value.generator_id),
		"definition_id": str(value.definition_id),
		"seed": int(seed_check.value),
		"count": int(count_check.value),
		"actor_recipe_id": str(value.actor_recipe_id),
		"actor_recipe": VALUE.duplicate_value(value.actor_recipe),
		"budget_before": before_check.value,
		"budget_consumed": int(consumed_check.value),
		"budget_after": after_check.value,
		"generated_objects": VALUE.duplicate_value(value.generated_objects)
	})
	if str(value.generation_fingerprint) != VALUE.digest(body):
		return _blocked("level_object.generation.fingerprint", "生成结果fingerprint与内容不一致。")
	return {"ok": true, "value": body.merged({"generation_fingerprint": str(value.generation_fingerprint)}, true)}

static func _parse_generated_object(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, GENERATED_FIELDS)
	if not fields.ok:
		return fields
	if str(value.schema_version) != GENERATED_OBJECT_SCHEMA:
		return _blocked("level_object.generated_object.schema", "生成对象Schema版本不匹配。")
	for identity in ["object_id", "object_kind", "definition_id", "source_generator_id", "slot_id"]:
		if not VALUE.stable_id(value.get(identity, ""), false):
			return _blocked("level_object.generated_object.identity", "生成对象包含非法稳定标识。", {"field": identity})
	var index_check := VALUE.integer_field(value.index, false)
	var seed_check := VALUE.safe_int(value.seed, true)
	if not index_check.ok or not seed_check.ok or typeof(value.actor_recipe) != TYPE_DICTIONARY or not VALUE.persistence(value.actor_recipe).ok:
		return _blocked("level_object.generated_object.value", "生成对象包含非法索引、seed或ActorRecipe。")
	if not VALUE.stable_id(value.actor_recipe_id, true):
		return _blocked("level_object.generated_object.actor_recipe", "生成对象ActorRecipe标识无效。")
	return {"ok": true, "value": VALUE.persistence_canonical(value)}

static func _validate_generator_input(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, RECIPE.GENERATOR_FIELDS)
	if not fields.ok:
		return fields
	var stable := VALUE.persistence(value)
	if not stable.ok:
		return {"ok": false, "code": "level_object.generator.input_persistence", "error_zh": "生成配方输入必须是可持久化纯值。", "detail": stable}
	for identity in ["generator_id", "definition_id", "slot_id", "generated_kind", "generated_definition_id"]:
		if not VALUE.stable_id(value.get(identity, ""), false):
			return _blocked("level_object.generator.input_identity", "生成配方包含非法稳定标识。", {"field": identity})
	var count_check := VALUE.integer_field(value.count, false)
	if not count_check.ok or int(count_check.value) < 1:
		return _blocked("level_object.generator.input_count", "生成数量必须是正整数。")
	var seed_check := VALUE.safe_int(value.seed, true)
	if not seed_check.ok:
		return _blocked("level_object.generator.input_seed", "生成seed必须是JSON安全整数。")
	if typeof(value.actor_recipe) != TYPE_DICTIONARY or not VALUE.persistence(value.actor_recipe).ok:
		return _blocked("level_object.generator.input_actor_recipe", "ActorRecipe必须是可持久化纯字典。")
	var budget_check := _validate_budget(value.task_budget)
	if not budget_check.ok:
		return budget_check
	return {"ok": true, "value": {
		"generator_id": str(value.generator_id), "definition_id": str(value.definition_id), "slot_id": str(value.slot_id),
		"count": int(count_check.value), "actor_recipe": VALUE.duplicate_value(value.actor_recipe), "task_budget": budget_check.value,
		"seed": int(seed_check.value), "generated_kind": str(value.generated_kind),
		"generated_definition_id": str(value.generated_definition_id), "tags": VALUE.duplicate_value(value.tags)
	}}

static func _validate_budget(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _blocked("level_object.generator.budget_type", "task budget必须是字典。")
	var fields := VALUE.exact_fields(value, ["budget_id", "remaining", "unit"])
	if not fields.ok:
		return _blocked("level_object.generator.budget_shape", "task budget字段集合无效。")
	if not VALUE.stable_id(value.budget_id, false) or not VALUE.stable_id(value.unit, false):
		return _blocked("level_object.generator.budget_identity", "task budget身份无效。")
	var remaining := VALUE.integer_field(value.remaining, false)
	if not remaining.ok:
		return _blocked("level_object.generator.budget_remaining", "task budget剩余量必须是非负整数。")
	return {"ok": true, "value": {"budget_id": str(value.budget_id), "remaining": int(remaining.value), "unit": str(value.unit)}}

static func _as_definition(value: Variant) -> Dictionary:
	if value is RefCounted and value.get_script() == DEFINITION:
		return {"ok": true, "value": value}
	return DEFINITION.from_dict(value)

static func _blocked(code: String, error_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error_zh": error_zh}
	if not details.is_empty():
		result["details"] = VALUE.duplicate_value(details)
	return result
