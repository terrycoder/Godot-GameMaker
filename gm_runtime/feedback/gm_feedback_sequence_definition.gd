class_name GMFeedbackSequenceDefinition
extends RefCounted

const SCHEMA_VERSION := "gm.feedback_sequence.v1"
const FIELDS := ["schema_version", "sequence_id", "display_name_zh", "max_steps", "max_duration_ticks", "steps"]
const MAX_STEPS := 32
const MAX_DURATION_TICKS := 600

var schema_version := SCHEMA_VERSION
var sequence_id := ""
var display_name_zh := ""
var max_steps := MAX_STEPS
var max_duration_ticks := MAX_DURATION_TICKS
var steps: Array[GMFeedbackStep] = []

func _init(p_sequence_id: String = "", p_display_name_zh: String = "") -> void:
	sequence_id = p_sequence_id
	display_name_zh = p_display_name_zh

func ordered_steps() -> Array[GMFeedbackStep]:
	var result: Array[GMFeedbackStep] = []
	for step in steps:
		if step != null:
			result.append(step)
	result.sort_custom(_step_before)
	return result

func to_dict() -> Dictionary:
	var rows: Array = []
	for step in ordered_steps():
		rows.append(step.to_dict())
	return {"schema_version": schema_version, "sequence_id": sequence_id, "display_name_zh": display_name_zh, "max_steps": max_steps, "max_duration_ticks": max_duration_ticks, "steps": rows}

func digest() -> String:
	return GMStableData.digest(to_dict())

func validate() -> Dictionary:
	var row := to_dict()
	if not GMFeedbackValidation.exact(row, FIELDS):
		return GMFeedbackValidation.failure("feedback.sequence_shape_invalid", "FeedbackSequenceDefinition字段集合必须精确匹配。")
	if typeof(schema_version) != TYPE_STRING or typeof(sequence_id) != TYPE_STRING or typeof(display_name_zh) != TYPE_STRING or typeof(max_steps) != TYPE_INT or typeof(max_duration_ticks) != TYPE_INT or typeof(steps) != TYPE_ARRAY:
		return GMFeedbackValidation.failure("feedback.sequence_variant_invalid", "反馈序列原始Variant类型无效。")
	if schema_version != SCHEMA_VERSION or not GMFeedbackValidation.stable_id(sequence_id) or display_name_zh.strip_edges().is_empty() or not GMFeedbackValidation.bounded_integer(max_steps, 1, MAX_STEPS) or not GMFeedbackValidation.bounded_integer(max_duration_ticks, 0, MAX_DURATION_TICKS):
		return GMFeedbackValidation.failure("feedback.sequence_header_invalid", "反馈序列的身份、中文名称或有界预算无效。")
	if steps.is_empty() or steps.size() > max_steps:
		return GMFeedbackValidation.failure("feedback.sequence_step_count_invalid", "反馈序列必须包含1至 max_steps 个步骤。")
	var ids := {}
	var duration_sum := 0
	for step in steps:
		if step == null:
			return GMFeedbackValidation.failure("feedback.sequence_step_missing", "反馈序列包含空步骤。")
		var checked := step.validate()
		if not checked.ok:
			return checked
		if ids.has(step.step_id):
			return GMFeedbackValidation.failure("feedback.sequence_step_duplicate", "反馈序列步骤ID重复。", {"step_id": step.step_id})
		ids[step.step_id] = true
		duration_sum += step.duration_ticks
		if duration_sum > max_duration_ticks:
			return GMFeedbackValidation.failure("feedback.sequence_duration_invalid", "反馈序列的串行保守时长超过上限。")
	for step in steps:
		for dependency in step.after_step_ids:
			if not ids.has(dependency):
				return GMFeedbackValidation.failure("feedback.sequence_dependency_missing", "反馈序列引用了不存在的前置步骤。", {"step_id": step.step_id, "dependency": dependency})
	if not _acyclic(ids):
		return GMFeedbackValidation.failure("feedback.sequence_cycle", "反馈序列依赖图不能包含循环。")
	return {"ok": true, "code": "feedback.sequence_valid", "value": row.duplicate(true), "digest": digest()}

func _acyclic(ids: Dictionary) -> bool:
	var visiting := {}
	var visited := {}
	for step in steps:
		if not _visit(step.step_id, visiting, visited):
			return false
	return true

func _visit(step_id: String, visiting: Dictionary, visited: Dictionary) -> bool:
	if visited.has(step_id):
		return true
	if visiting.has(step_id):
		return false
	visiting[step_id] = true
	var current: GMFeedbackStep = null
	for step in steps:
		if step.step_id == step_id:
			current = step
			break
	if current == null:
		return false
	for dependency in current.after_step_ids:
		if not _visit(dependency, visiting, visited):
			return false
	visiting.erase(step_id)
	visited[step_id] = true
	return true

static func from_dict(value: Variant, json_boundary: bool = false) -> GMFeedbackSequenceDefinition:
	if not value is Dictionary:
		return null
	var row: Dictionary = value
	if not GMFeedbackValidation.exact(row, FIELDS):
		return null
	if not GMFeedbackValidation.exact_field_types(row, ["schema_version", "sequence_id", "display_name_zh"], ["max_steps", "max_duration_ticks"], [], ["steps"], [], json_boundary):
		return null
	if row.schema_version != SCHEMA_VERSION or not GMFeedbackValidation.bounded_integer(row.max_steps, 1, MAX_STEPS, json_boundary) or not GMFeedbackValidation.bounded_integer(row.max_duration_ticks, 0, MAX_DURATION_TICKS, json_boundary):
		return null
	var result := GMFeedbackSequenceDefinition.new(row.sequence_id, row.display_name_zh)
	result.schema_version = row.schema_version
	result.max_steps = int(row.max_steps) if json_boundary else row.max_steps
	result.max_duration_ticks = int(row.max_duration_ticks) if json_boundary else row.max_duration_ticks
	for raw_step in row.steps:
		var step := GMFeedbackStep.from_dict(raw_step, json_boundary)
		if step == null:
			return null
		result.steps.append(step)
	return result if result.validate().ok else null

static func _step_before(a: GMFeedbackStep, b: GMFeedbackStep) -> bool:
	if a.logical_order != b.logical_order:
		return a.logical_order < b.logical_order
	if a.parallel_group != b.parallel_group:
		return a.parallel_group < b.parallel_group
	return a.step_id < b.step_id
