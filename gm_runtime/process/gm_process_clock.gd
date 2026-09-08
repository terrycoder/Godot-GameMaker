class_name GMProcessClock
extends RefCounted

## An injected logical clock. The kernel never reads system time.

const SCHEMA_VERSION := 1
const MODES := ["real", "turn", "test"]

var mode: String = "test"
var _value: int = 0

func _init(p_mode: String = "test", p_initial_value: int = 0) -> void:
	mode = p_mode
	_value = p_initial_value

func now() -> int:
	return _value

func validate() -> Dictionary:
	if not MODES.has(mode):
		return {"ok": false, "code": "process.clock_mode_invalid", "reason_zh": "未知逻辑时钟适配器。", "mode": mode}
	if _value < 0 or _value > GMStableData.JSON_SAFE_INTEGER_MAX:
		return {"ok": false, "code": "process.clock_value_invalid", "reason_zh": "逻辑时钟值必须是JSON安全范围内的非负整数。", "value": _value}
	return {"ok": true, "mode": mode, "value": _value}

func advance(units: int) -> Dictionary:
	var valid := validate()
	if not valid.ok: return valid
	if typeof(units) != TYPE_INT or units <= 0:
		return {"ok": false, "code": "process.clock_units_invalid", "reason_zh": "逻辑时钟增量必须为正整数。"}
	if _value > GMStableData.JSON_SAFE_INTEGER_MAX - units:
		return {"ok": false, "code": "process.clock_overflow", "reason_zh": "逻辑时钟增量超出JSON安全整数范围。"}
	_value += units
	return {"ok": true, "mode": mode, "value": _value, "advanced": units}

func to_native() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "mode": mode, "value": _value}

func restore_native(value: Variant, json_boundary: bool = false) -> Dictionary:
	var parsed := GMProcessClock.from_native(value, json_boundary)
	if not parsed.ok: return parsed
	mode = parsed.clock.mode
	_value = parsed.clock.now()
	return {"ok": true, "clock": self, "value": to_native()}

static func from_native(value: Variant, json_boundary: bool = false) -> Dictionary:
	var fields := ["schema_version", "mode", "value"]
	if not value is Dictionary or value.size() != fields.size():
		return _failure("process.clock_shape_invalid", "ProcessClock 字段缺失或附加。")
	for field in fields:
		if not value.has(field): return _failure("process.clock_shape_invalid", "ProcessClock 缺少字段：%s" % field)
	if not _integer(value.schema_version, json_boundary) or int(value.schema_version) != SCHEMA_VERSION:
		return _failure("process.clock_version_invalid", "ProcessClock 版本不受支持。")
	if typeof(value.mode) != TYPE_STRING: return _failure("process.clock_mode_invalid", "ProcessClock mode 必须是字符串。")
	if not _integer(value.value, json_boundary): return _failure("process.clock_value_invalid", "ProcessClock value 必须是精确非负整数。")
	var clock := GMProcessClock.new(value.mode, int(value.value))
	var validation := clock.validate()
	if not validation.ok: return validation
	return {"ok": true, "clock": clock, "value": clock.to_native()}

static func from_json(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK: return _failure("process.clock_json_invalid", "ProcessClock JSON 无效。")
	return from_native(parser.data, true)

static func _integer(value: Variant, json_boundary: bool) -> bool:
	if typeof(value) == TYPE_INT: return value >= 0 and value <= GMStableData.JSON_SAFE_INTEGER_MAX
	return json_boundary and typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value) and value >= 0.0 and value <= float(GMStableData.JSON_SAFE_INTEGER_MAX)

static func _failure(code: String, reason_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh}
