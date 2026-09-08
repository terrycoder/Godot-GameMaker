class_name GMProcessInstance
extends RefCounted

## Persisted runtime state for one ProcessDefinition revision.

const SCHEMA_VERSION := 1

var instance_id: String = ""
var definition_id: String = ""
var definition_revision: int = 1
var state: String = GMProcessState.CREATED
var progress := GMProcessProgress.new()
var participant_ids: Array[String] = []
var start_request_id: String = ""
var task_definition_id: String = ""
var duty_provider_id: String = ""
var result: Dictionary = {}
var failure: Dictionary = {}
var history: Array = []

func configure(p_instance_id: String, definition: GMProcessDefinition, request_id: String, clock_value: int) -> GMProcessInstance:
	instance_id = p_instance_id
	definition_id = definition.definition_id if definition != null else ""
	definition_revision = definition.revision if definition != null else 1
	state = GMProcessState.CREATED
	progress = GMProcessProgress.new(definition.duration_units if definition != null else 1, clock_value)
	participant_ids.clear()
	start_request_id = request_id
	task_definition_id = definition.task_definition_id if definition != null else ""
	duty_provider_id = definition.duty_provider_id if definition != null else ""
	result.clear()
	failure.clear()
	history.clear()
	_record(GMProcessState.CREATED, clock_value, "Process 已由 Ability 请求创建。", {})
	return self

func transition(next_state: String, clock_value: int, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	if typeof(clock_value) != TYPE_INT or clock_value < 0: return _failure("process.transition_clock_invalid", "状态转换必须使用非负逻辑时钟值。")
	if reason_zh.strip_edges().is_empty(): return _failure("process.transition_reason_missing", "状态转换必须记录原因。")
	if not GMProcessState.can_transition(state, next_state):
		return {"ok": false, "code": "process.transition_invalid", "reason_zh": "Process 状态转换不被声明式规则允许。", "from": state, "to": next_state}
	var stable := GMStableData.validate_persistence(details)
	if not stable.ok: return _failure("process.transition_details_invalid", "状态转换详情必须是持久化纯数据。")
	state = next_state
	_record(next_state, clock_value, reason_zh, details)
	return {"ok": true, "state": state}

func add_participant(participant_id: String) -> Dictionary:
	if not GMProcessDefinition._stable_id(participant_id): return _failure("process.participant_invalid", "参与者必须是稳定 ID。")
	if participant_ids.has(participant_id): return {"ok": true, "duplicate": true, "participant_ids": participant_ids.duplicate()}
	participant_ids.append(participant_id)
	participant_ids.sort()
	_record(state, progress.last_clock_value, "Ability 请求登记参与者。", {"participant_id": participant_id})
	return {"ok": true, "duplicate": false, "participant_ids": participant_ids.duplicate()}

func record_progress_checkpoint(clock_value: int, units: int) -> Dictionary:
	if typeof(clock_value) != TYPE_INT or clock_value < progress.last_clock_value:
		return _failure("process.progress_checkpoint_invalid", "进度检查点不得早于当前逻辑时钟。")
	if typeof(units) != TYPE_INT or units <= 0:
		return _failure("process.progress_checkpoint_units_invalid", "进度检查点必须记录正整数增量。")
	_record(state, clock_value, "逻辑时钟推进 Process 进度。", {"advanced_units": units, "elapsed_units": progress.elapsed_units})
	return {"ok": true, "history_sequence": history.size()}

func validate(json_boundary: bool = false) -> Dictionary:
	var errors: Array[String] = []
	if not GMProcessDefinition._stable_id(instance_id) or not instance_id.begins_with("gm.process.instance."):
		errors.append("ProcessInstance instance_id 必须是稳定 Process 身份。")
	if not GMProcessDefinition._stable_id(definition_id): errors.append("ProcessInstance definition_id 无效。")
	if definition_revision <= 0 or definition_revision > GMStableData.JSON_SAFE_INTEGER_MAX: errors.append("definition_revision 必须为正整数。")
	if not GMProcessState.is_known(state): errors.append("ProcessInstance 状态未知。")
	var progress_check := progress.validate() if progress != null else _failure("process.progress_missing", "ProcessInstance 缺少进度。")
	if not progress_check.ok: errors.append("ProcessProgress 无效。")
	if not GMProcessDefinition._stable_id(start_request_id): errors.append("ProcessInstance start_request_id 无效。")
	for optional_id in [task_definition_id, duty_provider_id]:
		if not optional_id.is_empty() and not GMProcessDefinition._stable_id(optional_id): errors.append("ProcessInstance 关联 ID 无效。")
	var seen: Dictionary = {}
	for participant_id in participant_ids:
		if not GMProcessDefinition._stable_id(participant_id) or seen.has(participant_id): errors.append("参与者必须是唯一稳定 ID：%s" % participant_id)
		seen[participant_id] = true
	if not result is Dictionary or not failure is Dictionary or not history is Array: errors.append("ProcessInstance 结果、失败和历史字段类型无效。")
	else:
		var stable := GMStableData.validate_persistence({"result": result, "failure": failure, "history": history})
		if not stable.ok: errors.append("ProcessInstance 含非持久化数据。")
	var history_check := _validate_history(json_boundary)
	if not history_check.ok: errors.append_array(history_check.errors)
	if state == GMProcessState.BLOCKED and failure.is_empty(): errors.append("blocked Process 必须保留类型化阻断原因。")
	if state == GMProcessState.FAILED and failure.is_empty(): errors.append("failed Process 必须保留类型化失败原因。")
	if state == GMProcessState.COMPLETED and result.is_empty(): errors.append("completed Process 必须保留类型化完成结果。")
	return {"ok": errors.is_empty(), "errors": errors}

func to_native() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"instance_id": instance_id,
		"definition_id": definition_id,
		"definition_revision": definition_revision,
		"state": state,
		"progress": progress.to_native() if progress != null else {},
		"participant_ids": participant_ids.duplicate(),
		"start_request_id": start_request_id,
		"task_definition_id": task_definition_id,
		"duty_provider_id": duty_provider_id,
		"result": result.duplicate(true),
		"failure": failure.duplicate(true),
		"history": history.duplicate(true),
	}

func to_json() -> String:
	return JSON.stringify(to_native())

static func from_native(value: Variant, json_boundary: bool = false) -> Dictionary:
	var fields := ["schema_version", "instance_id", "definition_id", "definition_revision", "state", "progress", "participant_ids", "start_request_id", "task_definition_id", "duty_provider_id", "result", "failure", "history"]
	if not value is Dictionary or value.size() != fields.size(): return _failure("process.instance_shape_invalid", "ProcessInstance 字段缺失或附加。")
	for field in fields:
		if not value.has(field): return _failure("process.instance_shape_invalid", "ProcessInstance 缺少字段：%s" % field)
	if not _integer(value.schema_version, json_boundary) or int(value.schema_version) != SCHEMA_VERSION: return _failure("process.instance_version_invalid", "ProcessInstance 版本不受支持。")
	if not _integer(value.definition_revision, json_boundary) or int(value.definition_revision) <= 0: return _failure("process.instance_revision_invalid", "definition_revision 必须是正整数。")
	for field in ["instance_id", "definition_id", "state", "start_request_id", "task_definition_id", "duty_provider_id"]:
		if typeof(value[field]) != TYPE_STRING: return _failure("process.instance_type_invalid", "%s 必须是字符串。" % field)
	if not value.participant_ids is Array or not value.result is Dictionary or not value.failure is Dictionary or not value.history is Array:
		return _failure("process.instance_type_invalid", "ProcessInstance 集合字段类型无效。")
	var progress_result := GMProcessProgress.from_native(value.progress, json_boundary)
	if not progress_result.ok: return progress_result
	var instance := GMProcessInstance.new()
	instance.instance_id = value.instance_id
	instance.definition_id = value.definition_id
	instance.definition_revision = int(value.definition_revision)
	instance.state = value.state
	instance.progress = progress_result.progress
	instance.participant_ids.clear()
	for participant_id in value.participant_ids:
		if typeof(participant_id) != TYPE_STRING: return _failure("process.instance_participant_type_invalid", "参与者ID必须是字符串。")
		instance.participant_ids.append(participant_id)
	instance.start_request_id = value.start_request_id
	instance.task_definition_id = value.task_definition_id
	instance.duty_provider_id = value.duty_provider_id
	instance.result = value.result.duplicate(true)
	instance.failure = value.failure.duplicate(true)
	var history_value: Variant = value.history.duplicate(true)
	if json_boundary:
		# JSON numbers may decode as floats; canonicalize only the persisted
		# history boundary so schema integer fields become native integers while
		# non-integral values remain available to strict history validation.
		history_value = _normalize_json_history_value(history_value)
	instance.history = history_value
	var validation := instance.validate(json_boundary)
	if not validation.ok: return {"ok": false, "code": "process.instance_invalid", "reason_zh": "ProcessInstance 验证失败。", "errors": validation.errors}
	return {"ok": true, "instance": instance, "value": instance.to_native()}

static func from_json(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK: return _failure("process.instance_json_invalid", "ProcessInstance JSON 无效。")
	return from_native(parser.data, true)

func _validate_history(json_boundary: bool = false) -> Dictionary:
	if history.is_empty(): return _failure("process.history_empty", "ProcessInstance 必须保留至少一条生命周期历史。")
	var previous_clock := -1
	var previous_state := ""
	for index in history.size():
		var entry: Variant = history[index]
		if not entry is Dictionary: return {"ok": false, "errors": ["Process 历史条目必须是对象。"]}
		var fields := ["sequence", "state", "clock_value", "reason_zh", "details"]
		if entry.size() != fields.size(): return {"ok": false, "errors": ["Process 历史条目字段缺失或附加。"]}
		for field in fields:
			if not entry.has(field): return {"ok": false, "errors": ["Process 历史条目缺少字段：%s" % field]}
		if not _integer(entry.sequence, json_boundary) or int(entry.sequence) != index + 1: return {"ok": false, "errors": ["Process 历史序号不连续。"]}
		if not GMProcessState.is_known(entry.state): return {"ok": false, "errors": ["Process 历史状态未知。"]}
		if index == 0 and str(entry.state) != GMProcessState.CREATED: return {"ok": false, "errors": ["Process 历史首态必须是created。"]}
		if index > 0 and str(entry.state) != previous_state and not GMProcessState.can_transition(previous_state, str(entry.state)):
			return {"ok": false, "errors": ["Process 历史包含未声明的状态跳转。"]}
		if not _integer(entry.clock_value, json_boundary) or int(entry.clock_value) < previous_clock: return {"ok": false, "errors": ["Process 历史逻辑时钟倒退。"]}
		if typeof(entry.reason_zh) != TYPE_STRING or str(entry.reason_zh).strip_edges().is_empty(): return {"ok": false, "errors": ["Process 历史原因不能为空。"]}
		if not entry.details is Dictionary: return {"ok": false, "errors": ["Process 历史详情必须是对象。"]}
		previous_clock = int(entry.clock_value)
		previous_state = str(entry.state)
	if str(history.back().state) != state: return {"ok": false, "errors": ["Process 历史末态与当前状态不一致。"]}
	if int(history.back().clock_value) < progress.last_clock_value: return {"ok": false, "errors": ["Process 历史末时钟早于进度时钟。"]}
	return {"ok": true}

func _record(next_state: String, clock_value: int, reason_zh: String, details: Dictionary) -> void:
	history.append({"sequence": history.size() + 1, "state": next_state, "clock_value": clock_value, "reason_zh": reason_zh, "details": details.duplicate(true)})

static func _integer(value: Variant, json_boundary: bool) -> bool:
	if typeof(value) == TYPE_INT: return value >= 0 and value <= GMStableData.JSON_SAFE_INTEGER_MAX
	return json_boundary and typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value) and value >= 0.0 and value <= float(GMStableData.JSON_SAFE_INTEGER_MAX)

static func _normalize_json_history_value(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized: Dictionary = {}
		for key in value.keys(): normalized[key] = _normalize_json_history_value(value[key])
		return normalized
	if value is Array:
		var normalized_array: Array = []
		for item in value: normalized_array.append(_normalize_json_history_value(item))
		return normalized_array
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value) and abs(value) <= float(GMStableData.JSON_SAFE_INTEGER_MAX):
		return int(value)
	return value

static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty(): result["details"] = details
	return result
