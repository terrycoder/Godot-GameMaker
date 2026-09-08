class_name GMProcessProgress
extends RefCounted

const SCHEMA_VERSION := 1

var elapsed_units: int = 0
var required_units: int = 1
var last_clock_value: int = 0

func _init(p_required_units: int = 1, p_last_clock_value: int = 0) -> void:
	required_units = p_required_units
	last_clock_value = p_last_clock_value

func validate() -> Dictionary:
	if required_units <= 0:
		return {"ok": false, "code": "process.progress_required_invalid", "reason_zh": "Process 所需持续单位必须为正整数。"}
	if elapsed_units < 0 or elapsed_units > required_units:
		return {"ok": false, "code": "process.progress_elapsed_invalid", "reason_zh": "Process 已用持续单位超出定义范围。"}
	if last_clock_value < 0 or last_clock_value > GMStableData.JSON_SAFE_INTEGER_MAX:
		return {"ok": false, "code": "process.progress_clock_invalid", "reason_zh": "Process 进度逻辑时钟值无效。"}
	return {"ok": true, "progress": to_native()}

func advance(units: int, clock_value: int) -> Dictionary:
	if typeof(units) != TYPE_INT or units <= 0 or typeof(clock_value) != TYPE_INT or clock_value < last_clock_value:
		return {"ok": false, "code": "process.progress_advance_invalid", "reason_zh": "进度增量必须为正，逻辑时钟不得倒退。"}
	if clock_value > GMStableData.JSON_SAFE_INTEGER_MAX:
		return {"ok": false, "code": "process.progress_clock_invalid", "reason_zh": "Process 进度逻辑时钟超出JSON安全范围。"}
	elapsed_units = mini(required_units, elapsed_units + units)
	last_clock_value = clock_value
	return {"ok": true, "completed": elapsed_units >= required_units, "progress": to_native()}

func to_native() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "elapsed_units": elapsed_units, "required_units": required_units, "last_clock_value": last_clock_value}

static func from_native(value: Variant, json_boundary: bool = false) -> Dictionary:
	var fields := ["schema_version", "elapsed_units", "required_units", "last_clock_value"]
	if not value is Dictionary or value.size() != fields.size():
		return _failure("process.progress_shape_invalid", "ProcessProgress 字段缺失或附加。")
	for field in fields:
		if not value.has(field): return _failure("process.progress_shape_invalid", "ProcessProgress 缺少字段：%s" % field)
	if not _integer(value.schema_version, json_boundary) or int(value.schema_version) != SCHEMA_VERSION:
		return _failure("process.progress_version_invalid", "ProcessProgress 版本不受支持。")
	for field in ["elapsed_units", "required_units", "last_clock_value"]:
		if not _integer(value[field], json_boundary): return _failure("process.progress_integer_required", "%s 必须是精确非负整数。" % field)
	var progress := GMProcessProgress.new(int(value.required_units), int(value.last_clock_value))
	progress.elapsed_units = int(value.elapsed_units)
	var validation := progress.validate()
	if not validation.ok: return validation
	return {"ok": true, "progress": progress, "value": progress.to_native()}

static func from_json(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK: return _failure("process.progress_json_invalid", "ProcessProgress JSON 无效。")
	return from_native(parser.data, true)

static func _integer(value: Variant, json_boundary: bool) -> bool:
	if typeof(value) == TYPE_INT: return value >= 0 and value <= GMStableData.JSON_SAFE_INTEGER_MAX
	return json_boundary and typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value) and value >= 0.0 and value <= float(GMStableData.JSON_SAFE_INTEGER_MAX)

static func _failure(code: String, reason_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh}
