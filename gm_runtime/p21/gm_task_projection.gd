class_name GMTaskProjection
extends RefCounted

## Read-only value projection over the P16 Task authority. The copied values
## are display data; this class intentionally has no mutation API.

const SCHEMA_VERSION := GMP21Contract.TASK_PROJECTION_SCHEMA_VERSION
const FIELDS := ["schema_version", "projection_id", "task_id", "definition_id", "display_name_zh", "description_zh", "state", "assignment_id", "source", "objectives", "readonly", "source_revision"]
const OBJECTIVE_FIELDS := ["objective_id", "display_name_zh", "current", "target", "complete", "signal_kind", "signal_type"]

var schema_version := SCHEMA_VERSION
var projection_id := ""
var task_id := ""
var definition_id := ""
var display_name_zh := ""
var description_zh := ""
var state := ""
var assignment_id := ""
var source: Dictionary = {}
var objectives: Array[Dictionary] = []
var readonly := true
var source_revision := 0

func validate() -> Dictionary:
	var value := to_dict()
	if not GMP21Contract.exact(value, FIELDS): return GMP21Contract.failure("task.projection_shape_invalid", "TaskProjection字段集合必须精确匹配。")
	if schema_version != SCHEMA_VERSION or not GMP21Contract.stable_id(projection_id) or not GMP21Contract.stable_id(task_id) or not GMP21Contract.stable_id(definition_id) or display_name_zh.strip_edges().is_empty() or typeof(description_zh) != TYPE_STRING or state not in ["draft", "available", "assigned", "in_progress", "blocked", "completed", "failed", "cancelled"] or typeof(assignment_id) != TYPE_STRING or not GMP21Contract.stable_id(assignment_id, true) or not readonly or not GMP21Contract.nonnegative_integer(source_revision):
		return GMP21Contract.failure("task.projection_identity_invalid", "TaskProjection身份、状态、只读标记或来源版本无效。")
	if not GMP21Contract.typed_ref(source): return GMP21Contract.failure("task.projection_source_invalid", "TaskProjection source必须是稳定类型+ID引用。")
	var seen: Dictionary = {}
	for objective in objectives:
		if not GMP21Contract.exact(objective, OBJECTIVE_FIELDS) or typeof(objective.objective_id) != TYPE_STRING or not GMP21Contract.stable_id(objective.objective_id) or typeof(objective.display_name_zh) != TYPE_STRING or objective.display_name_zh.strip_edges().is_empty() or not GMP21Contract.nonnegative_integer(objective.current) or not GMP21Contract.positive_integer(objective.target) or typeof(objective.complete) != TYPE_BOOL or objective.complete != (int(objective.current) >= int(objective.target)) or typeof(objective.signal_kind) != TYPE_STRING or objective.signal_kind not in ["fact", "change", "cue"] or typeof(objective.signal_type) != TYPE_STRING or not GMP21Contract.stable_id(objective.signal_type):
			return GMP21Contract.failure("task.projection_objective_invalid", "TaskProjection Objective投影无效。")
		if seen.has(objective.objective_id): return GMP21Contract.failure("task.projection_objective_duplicate", "TaskProjection Objective ID重复。")
		seen[objective.objective_id] = true
	return {"ok": true, "code": "task.projection_valid", "value": value}

func to_dict() -> Dictionary:
	var rows: Array = []
	for objective in objectives:
		rows.append(objective.duplicate(true))
	return {"schema_version": schema_version, "projection_id": projection_id, "task_id": task_id, "definition_id": definition_id, "display_name_zh": display_name_zh, "description_zh": description_zh, "state": state, "assignment_id": assignment_id, "source": source.duplicate(true), "objectives": rows, "readonly": readonly, "source_revision": source_revision}

func to_json() -> String:
	return JSON.stringify(GMStableData.persistence_canonical(to_dict()), "", false, true)

func digest() -> String:
	return GMP21Contract.digest(to_dict())

static func from_authority(task: Dictionary, definition: Dictionary, p_source_revision: int) -> Dictionary:
	if task.is_empty() or definition.is_empty(): return GMP21Contract.failure("task.projection_source_missing", "TaskProjection缺少P16 Task或Definition来源。")
	var raw_objectives: Variant = definition.get("objectives", null)
	var task_objectives: Variant = task.get("objectives", null)
	if not raw_objectives is Array or not task_objectives is Dictionary: return GMP21Contract.failure("task.projection_source_invalid", "P16 Task/Definition Objective结构无效。")
	var result := GMTaskProjection.new()
	result.task_id = str(task.get("task_id", ""))
	result.definition_id = str(task.get("definition_id", ""))
	result.display_name_zh = str(definition.get("display_name_zh", ""))
	result.description_zh = str(definition.get("description_zh", ""))
	result.state = str(task.get("state", ""))
	result.assignment_id = str(task.get("assignment_id", ""))
	var authority_source: Dictionary = task.get("source", {}) if task.get("source", {}) is Dictionary else {}
	result.source = {
		"type": str(authority_source.get("type", "p16")),
		"id": str(authority_source.get("id", result.task_id)),
	}
	result.source_revision = p_source_revision
	for raw_definition_objective in raw_objectives:
		if not raw_definition_objective is Dictionary: return GMP21Contract.failure("task.projection_objective_invalid", "P16 Definition Objective不是Dictionary。")
		var objective_id := str(raw_definition_objective.get("objective_id", ""))
		var progress: Dictionary = task_objectives.get(objective_id, {}) if task_objectives.get(objective_id, {}) is Dictionary else {}
		result.objectives.append({"objective_id": objective_id, "display_name_zh": str(raw_definition_objective.get("display_name_zh", "")), "current": int(progress.get("current", 0)), "target": int(progress.get("target", raw_definition_objective.get("target_value", 0))), "complete": bool(progress.get("complete", false)), "signal_kind": str(raw_definition_objective.get("signal_kind", "")), "signal_type": str(raw_definition_objective.get("signal_type", ""))})
	result.objectives.sort_custom(func(left: Dictionary, right: Dictionary): return str(left.get("objective_id", "")) < str(right.get("objective_id", "")))
	result.projection_id = "gm.task.projection.%s" % GMP21Contract.digest({"task": result.task_id, "source_revision": result.source_revision, "task_value": task, "definition_value": definition})
	var checked := result.validate()
	return {"ok": true, "code": "task.projection_built", "projection": result} if checked.ok else checked

static func from_dict(value: Variant, json_boundary: bool = false) -> GMTaskProjection:
	if not value is Dictionary or not GMP21Contract.exact(value, FIELDS): return null
	var source: Dictionary = value.duplicate(true)
	for field in ["schema_version", "projection_id", "task_id", "definition_id", "display_name_zh", "description_zh", "state", "assignment_id"]:
		if typeof(source.get(field)) != TYPE_STRING: return null
	if not source.get("source") is Dictionary or typeof(source.get("readonly")) != TYPE_BOOL or not source.get("objectives") is Array: return null
	if json_boundary and typeof(source.get("source_revision")) == TYPE_FLOAT and is_finite(float(source.source_revision)) and float(source.source_revision) == floor(float(source.source_revision)):
		source.source_revision = int(source.source_revision)
	if typeof(source.get("source_revision")) != TYPE_INT: return null
	for raw_objective in source.objectives:
		if not raw_objective is Dictionary: return null
		if json_boundary:
			for field in ["current", "target"]:
				if typeof(raw_objective.get(field)) == TYPE_FLOAT and is_finite(float(raw_objective[field])) and float(raw_objective[field]) == floor(float(raw_objective[field])):
					raw_objective[field] = int(raw_objective[field])
	var result := GMTaskProjection.new()
	for field in ["schema_version", "projection_id", "task_id", "definition_id", "display_name_zh", "description_zh", "state", "assignment_id"]: result[field] = str(source[field])
	result.source = source.source.duplicate(true)
	result.readonly = source.readonly
	result.source_revision = int(source.source_revision)
	for raw_objective in source.objectives:
		if not raw_objective is Dictionary: return null
		result.objectives.append(raw_objective.duplicate(true))
	return result if result.validate().ok else null

static func from_json(text: String) -> Dictionary:
	var parsed := GMP21Contract.normalize_json(text, "task.projection_json_invalid")
	if not parsed.ok: return parsed
	var projection := from_dict(parsed.value, true)
	return {"ok": true, "code": "task.projection_decoded", "projection": projection} if projection != null else GMP21Contract.failure("task.projection_json_invalid", "TaskProjection JSON未通过严格合同校验。")
