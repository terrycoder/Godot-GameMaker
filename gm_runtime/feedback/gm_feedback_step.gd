class_name GMFeedbackStep
extends RefCounted

const SCHEMA_VERSION := "gm.feedback_step.v1"
const FIELDS := ["schema_version", "step_id", "step_kind", "semantic_action_id", "cue_id", "target_ref", "duration_ticks", "logical_order", "parallel_group", "after_step_ids", "optional", "content_id", "text_zh", "metadata"]
const KINDS := ["semantic_action", "cue", "text", "icon", "audio", "vfx", "attention", "noop"]

var schema_version := SCHEMA_VERSION
var step_id := ""
var step_kind := "noop"
var semantic_action_id := ""
var cue_id := ""
var target_ref := ""
var duration_ticks := 0
var logical_order := 0
var parallel_group := ""
var after_step_ids: Array[String] = []
var optional := false
var content_id := ""
var text_zh := ""
var metadata: Dictionary = {}

func _init(p_step_id: String = "", p_step_kind: String = "noop") -> void:
	step_id = p_step_id
	step_kind = p_step_kind

func to_dict() -> Dictionary:
	var dependencies := after_step_ids.duplicate()
	dependencies.sort()
	return {"schema_version": schema_version, "step_id": step_id, "step_kind": step_kind, "semantic_action_id": semantic_action_id, "cue_id": cue_id, "target_ref": target_ref, "duration_ticks": duration_ticks, "logical_order": logical_order, "parallel_group": parallel_group, "after_step_ids": dependencies, "optional": optional, "content_id": content_id, "text_zh": text_zh, "metadata": metadata.duplicate(true)}

func validate() -> Dictionary:
	var row := to_dict()
	if not GMFeedbackValidation.exact(row, FIELDS):
		return GMFeedbackValidation.failure("feedback.step_shape_invalid", "FeedbackStep字段集合必须精确匹配。")
	if typeof(schema_version) != TYPE_STRING or typeof(step_id) != TYPE_STRING or typeof(step_kind) != TYPE_STRING or typeof(semantic_action_id) != TYPE_STRING or typeof(cue_id) != TYPE_STRING or typeof(target_ref) != TYPE_STRING or typeof(duration_ticks) != TYPE_INT or typeof(logical_order) != TYPE_INT or typeof(parallel_group) != TYPE_STRING or typeof(after_step_ids) != TYPE_ARRAY or typeof(optional) != TYPE_BOOL or typeof(content_id) != TYPE_STRING or typeof(text_zh) != TYPE_STRING or typeof(metadata) != TYPE_DICTIONARY:
		return GMFeedbackValidation.failure("feedback.step_variant_invalid", "FeedbackStep原始Variant类型无效。")
	if schema_version != SCHEMA_VERSION or not GMFeedbackValidation.stable_id(step_id) or step_kind not in KINDS:
		return GMFeedbackValidation.failure("feedback.step_identity_invalid", "FeedbackStep的Schema、ID或步骤类型无效。")
	if not GMFeedbackValidation.stable_id(semantic_action_id, true) or not GMFeedbackValidation.stable_id(cue_id, true) or not GMFeedbackValidation.stable_id(target_ref, true) or not GMFeedbackValidation.stable_id(parallel_group, true) or not GMFeedbackValidation.stable_id(content_id, true):
		return GMFeedbackValidation.failure("feedback.step_reference_invalid", "FeedbackStep只能引用稳定的语义、Cue、目标和内容ID。")
	if step_kind == "semantic_action" and semantic_action_id.is_empty():
		return GMFeedbackValidation.failure("feedback.step_action_missing", "语义动作步骤缺少 semantic_action_id。")
	if step_kind == "cue" and cue_id.is_empty():
		return GMFeedbackValidation.failure("feedback.step_cue_missing", "Cue步骤缺少 cue_id。")
	if typeof(text_zh) != TYPE_STRING or typeof(optional) != TYPE_BOOL or not GMFeedbackValidation.bounded_integer(duration_ticks, 0, 600) or not GMFeedbackValidation.bounded_integer(logical_order, 0, 100000):
		return GMFeedbackValidation.failure("feedback.step_value_invalid", "FeedbackStep的时长、顺序或布尔字段超出边界。")
	var seen := {}
	for dependency in after_step_ids:
		if not GMFeedbackValidation.stable_id(dependency) or dependency == step_id or seen.has(dependency):
			return GMFeedbackValidation.failure("feedback.step_dependency_invalid", "FeedbackStep依赖必须是唯一且不同于自身的稳定ID。")
		seen[dependency] = true
	var stable := GMFeedbackValidation.stable_value(metadata, "$.metadata")
	if not stable.ok:
		return stable
	return {"ok": true, "code": "feedback.step_valid", "value": row.duplicate(true)}

static func from_dict(value: Variant, json_boundary: bool = false) -> GMFeedbackStep:
	if not value is Dictionary:
		return null
	var row: Dictionary = value
	if not GMFeedbackValidation.exact(row, FIELDS):
		return null
	var raw_check := _validate_raw_row(row, json_boundary)
	if not raw_check.ok:
		return null
	var result := GMFeedbackStep.new(row.step_id, row.step_kind)
	result.schema_version = row.schema_version
	result.semantic_action_id = row.semantic_action_id
	result.cue_id = row.cue_id
	result.target_ref = row.target_ref
	result.duration_ticks = int(row.duration_ticks) if json_boundary else row.duration_ticks
	result.logical_order = int(row.logical_order) if json_boundary else row.logical_order
	result.parallel_group = row.parallel_group
	result.optional = row.optional
	result.content_id = row.content_id
	result.text_zh = row.text_zh
	result.metadata = row.metadata.duplicate(true)
	result.after_step_ids.clear()
	for dependency in row.after_step_ids:
		result.after_step_ids.append(dependency)
	return result if result.validate().ok else null

static func _validate_raw_row(row: Dictionary, json_boundary: bool) -> Dictionary:
	var string_fields := ["schema_version", "step_id", "step_kind", "semantic_action_id", "cue_id", "target_ref", "parallel_group", "content_id", "text_zh"]
	if not GMFeedbackValidation.exact_field_types(row, string_fields, ["duration_ticks", "logical_order"], ["optional"], ["after_step_ids"], ["metadata"], json_boundary):
		return GMFeedbackValidation.failure("feedback.step_variant_invalid", "FeedbackStep原始Variant类型不符合精确契约。")
	if not GMFeedbackValidation.array_members_are(row.after_step_ids, TYPE_STRING):
		return GMFeedbackValidation.failure("feedback.step_dependency_variant_invalid", "FeedbackStep依赖必须是原生字符串数组。")
	if row.schema_version != SCHEMA_VERSION or not GMFeedbackValidation.bounded_integer(row.duration_ticks, 0, 600, json_boundary) or not GMFeedbackValidation.bounded_integer(row.logical_order, 0, 100000, json_boundary):
		return GMFeedbackValidation.failure("feedback.step_value_invalid", "FeedbackStep原始Variant的Schema或有界整数无效。")
	return {"ok": true}

func clone() -> GMFeedbackStep:
	return GMFeedbackStep.from_dict(to_dict())
