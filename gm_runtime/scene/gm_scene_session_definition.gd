class_name GMSceneSessionDefinition
extends RefCounted

## 一次场景执行的不可变纯值定义。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const CONTEXT := preload("res://gm_runtime/scene/gm_task_execution_context.gd")
const SKELETON := preload("res://gm_runtime/scene/gm_scene_skeleton_definition.gd")
const RECIPE := preload("res://gm_runtime/scene/gm_scene_recipe.gd")
const RETURN_CONTEXT := preload("res://gm_runtime/scene/gm_scene_return_context.gd")

const SCHEMA_VERSION := "gm.scene.session_definition.v1"
const FIELDS: Array[String] = ["schema_version", "definition_id", "task_id", "assignment_id", "context", "skeleton", "recipe", "return_context"]

var definition_id: String
var task_id: String
var assignment_id: String
var context: Dictionary
var skeleton: Dictionary
var recipe: Dictionary
var return_context: Dictionary

func _init(
	p_definition_id: String = "",
	p_task_id: String = "",
	p_assignment_id: String = "",
	p_context: Dictionary = {},
	p_skeleton: Dictionary = {},
	p_recipe: Dictionary = {},
	p_return_context: Dictionary = {}
) -> void:
	definition_id = p_definition_id
	task_id = p_task_id
	assignment_id = p_assignment_id
	context = VALUE.duplicate_value(p_context)
	skeleton = VALUE.duplicate_value(p_skeleton)
	recipe = VALUE.duplicate_value(p_recipe)
	return_context = VALUE.duplicate_value(p_return_context)

static func from_dict(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var stable := VALUE.persistence(value)
	if not stable.ok:
		return stable
	if value.schema_version != SCHEMA_VERSION:
		return {"ok": false, "code": "scene.definition.schema", "error_zh": "SceneSessionDefinition Schema版本不匹配。"}
	if not VALUE.stable_id(value.definition_id) or not VALUE.stable_id(value.task_id) or not VALUE.stable_id(value.assignment_id, true):
		return {"ok": false, "code": "scene.definition.identity", "error_zh": "场景定义标识无效。"}
	var context_check := CONTEXT.from_dict(value.context)
	if not context_check.ok:
		return {"ok": false, "code": "scene.definition.context", "error_zh": "场景定义上下文无效。", "detail": context_check}
	var context_value: GMTaskExecutionContext = context_check.value
	if context_value.task_id != str(value.task_id) or context_value.assignment_id != str(value.assignment_id):
		return {"ok": false, "code": "scene.definition.context_identity", "error_zh": "定义身份与上下文身份不一致。"}
	var skeleton_check := SKELETON.from_dict(value.skeleton)
	if not skeleton_check.ok:
		return {"ok": false, "code": "scene.definition.skeleton", "error_zh": "场景定义骨架无效。", "detail": skeleton_check}
	var recipe_check := RECIPE.from_dict(value.recipe)
	if not recipe_check.ok:
		return {"ok": false, "code": "scene.definition.recipe", "error_zh": "场景定义配方无效。", "detail": recipe_check}
	var recipe_value: GMSceneRecipe = recipe_check.value
	var skeleton_value: GMSceneSkeletonDefinition = skeleton_check.value
	if recipe_value.skeleton_id != skeleton_value.skeleton_id:
		return {"ok": false, "code": "scene.definition.skeleton_mismatch", "error_zh": "配方与骨架标识不一致。"}
	var return_value: Dictionary = value.return_context
	if typeof(return_value) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.definition.return_type", "error_zh": "场景定义返回上下文必须是字典。"}
	if not return_value.is_empty():
		var return_check := RETURN_CONTEXT.from_dict(return_value)
		if not return_check.ok:
			return {"ok": false, "code": "scene.definition.return", "error_zh": "场景定义返回上下文无效。", "detail": return_check}
		return_value = return_check.value.to_dict()
		if not context_value.return_context.is_empty() and return_value != context_value.return_context:
			return {"ok": false, "code": "scene.definition.return_mismatch", "error_zh": "定义返回上下文与执行上下文不一致。"}
	var definition := GMSceneSessionDefinition.new(
		str(value.definition_id), str(value.task_id), str(value.assignment_id), context_value.to_dict(),
		skeleton_value.to_dict(), recipe_value.to_dict(), VALUE.duplicate_value(return_value)
	)
	return {"ok": true, "value": definition}

static func from_json(text: String) -> Dictionary:
	var parsed := VALUE.parse_json(text)
	if not parsed.ok:
		return parsed
	return from_dict(parsed.value)

func validate() -> Dictionary:
	return GMSceneSessionDefinition.from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"definition_id": definition_id,
		"task_id": task_id,
		"assignment_id": assignment_id,
		"context": VALUE.duplicate_value(context),
		"skeleton": VALUE.duplicate_value(skeleton),
		"recipe": VALUE.duplicate_value(recipe),
		"return_context": VALUE.duplicate_value(return_context)
	}

func to_json() -> String:
	return VALUE.json_string(to_dict())

func fingerprint() -> String:
	return VALUE.digest(to_dict())
