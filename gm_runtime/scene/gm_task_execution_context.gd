class_name GMTaskExecutionContext
extends RefCounted

## TaskExecutionSession 唯一接收的任务上下文。
## 它只携带稳定语义引用、参与者、资源、约束、种子与返回位置。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const RETURN_CONTEXT := preload("res://gm_runtime/scene/gm_scene_return_context.gd")

const SCHEMA_VERSION := "gm.task.execution_context.v1"
const FIELDS: Array[String] = [
	"schema_version", "task_id", "assignment_id", "mode", "target",
	"participants", "resources", "constraints", "seed", "return_context"
]
const MODES: Array[String] = ["local", "summary", "scene"]

var task_id: String
var assignment_id: String
var mode: String
var target: Dictionary
var participants: Array
var resources: Array
var constraints: Dictionary
var seed: int
var return_context: Dictionary

func _init(
	p_task_id: String = "",
	p_assignment_id: String = "",
	p_mode: String = "scene",
	p_target: Dictionary = {},
	p_participants: Array = [],
	p_resources: Array = [],
	p_constraints: Dictionary = {},
	p_seed: int = 0,
	p_return_context: Dictionary = {}
) -> void:
	task_id = p_task_id
	assignment_id = p_assignment_id
	mode = p_mode
	target = VALUE.duplicate_value(p_target)
	participants = VALUE.duplicate_value(p_participants)
	resources = VALUE.duplicate_value(p_resources)
	constraints = VALUE.duplicate_value(p_constraints)
	seed = p_seed
	return_context = VALUE.duplicate_value(p_return_context)

static func from_dict(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var stable := VALUE.persistence(value)
	if not stable.ok:
		return stable
	if value.schema_version != SCHEMA_VERSION:
		return {"ok": false, "code": "scene.context.schema", "error_zh": "TaskExecutionContext Schema版本不匹配。"}
	if not VALUE.stable_id(value.task_id) or not VALUE.stable_id(value.assignment_id, true):
		return {"ok": false, "code": "scene.context.identity", "error_zh": "任务与分配标识必须是稳定值。"}
	if not MODES.has(str(value.mode)):
		return {"ok": false, "code": "scene.context.mode", "error_zh": "TaskExecutionContext模式无效。"}
	var target_check := VALUE.semantic_ref(value.target, false)
	if not target_check.ok:
		return {"ok": false, "code": "scene.context.target", "error_zh": "任务目标语义引用无效。", "detail": target_check}
	if typeof(value.participants) != TYPE_ARRAY or typeof(value.resources) != TYPE_ARRAY:
		return {"ok": false, "code": "scene.context.collections", "error_zh": "参与者与资源必须是数组。"}
	var normalized_participants: Array = []
	for participant in value.participants:
		var participant_check := VALUE.semantic_ref(participant, false)
		if not participant_check.ok:
			return {"ok": false, "code": "scene.context.participant", "error_zh": "参与者必须是稳定语义引用。", "detail": participant_check}
		normalized_participants.append(participant_check.get("value", VALUE.duplicate_value(participant)))
	var normalized_resources: Array = []
	for resource in value.resources:
		var resource_check := VALUE.semantic_ref(resource, false)
		if not resource_check.ok:
			return {"ok": false, "code": "scene.context.resource", "error_zh": "资源必须是稳定语义引用。", "detail": resource_check}
		normalized_resources.append(resource_check.get("value", VALUE.duplicate_value(resource)))
	if typeof(value.constraints) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.context.constraints", "error_zh": "约束必须是纯字典值。"}
	var seed_check := VALUE.safe_int(value.seed, true)
	if not seed_check.ok:
		return {"ok": false, "code": "scene.context.seed", "error_zh": "场景种子无效。", "detail": seed_check}
	if typeof(value.return_context) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.context.return_type", "error_zh": "返回上下文必须是字典。"}
	var normalized_return_context: Dictionary = {}
	if not value.return_context.is_empty():
		var return_check := RETURN_CONTEXT.from_dict(value.return_context)
		if not return_check.ok:
			return {"ok": false, "code": "scene.context.return_context", "error_zh": "返回上下文无效。", "detail": return_check}
		normalized_return_context = return_check.value.to_dict()
	var context := GMTaskExecutionContext.new(
		str(value.task_id), str(value.assignment_id), str(value.mode), target_check.get("value", VALUE.duplicate_value(value.target)),
		normalized_participants, normalized_resources, value.constraints, seed_check.value, normalized_return_context
	)
	return {"ok": true, "value": context}

## P16 的 execution request 仍由 P16 产生；此方法只读取其中的稳定上下文，
## 不创建任务实例、不修改任务状态。
static func from_task_context(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, ["schema", "task_id", "assignment_id", "mode", "stable_context"])
	if not fields.ok:
		return fields
	if value.schema != "gm.task.execution_request.v1":
		return {"ok": false, "code": "scene.context.request_schema", "error_zh": "P16任务执行上下文Schema不匹配。"}
	if typeof(value.stable_context) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.context.request_context", "error_zh": "P16 stable_context必须是纯字典。"}
	var stable_context: Dictionary = value.stable_context.duplicate(true)
	var direct := {
		"schema_version": SCHEMA_VERSION,
		"task_id": str(value.task_id),
		"assignment_id": str(value.assignment_id),
		"mode": str(value.mode),
		"target": stable_context.get("target", {}),
		"participants": stable_context.get("participants", []),
		"resources": stable_context.get("resources", []),
		"constraints": stable_context.get("constraints", {}),
		"seed": stable_context.get("seed", 0),
		"return_context": stable_context.get("return_context", {})
	}
	return from_dict(direct)

static func from_json(text: String) -> Dictionary:
	var parsed := VALUE.parse_json(text)
	if not parsed.ok:
		return parsed
	return from_dict(parsed.value)

func validate() -> Dictionary:
	return GMTaskExecutionContext.from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"task_id": task_id,
		"assignment_id": assignment_id,
		"mode": mode,
		"target": VALUE.duplicate_value(target),
		"participants": VALUE.duplicate_value(participants),
		"resources": VALUE.duplicate_value(resources),
		"constraints": VALUE.duplicate_value(constraints),
		"seed": seed,
		"return_context": VALUE.duplicate_value(return_context)
	}

func to_json() -> String:
	return VALUE.json_string(to_dict())

func fingerprint() -> String:
	return VALUE.digest(to_dict())
