@tool
class_name GMSignalConnection
extends Resource

## Godot 局部连接声明。persistent 与 runtime_dynamic 明确分开；业务身份
## 使用 gm_id/内容 ID，node_path 只作为当前编辑器定位证据，不参与身份。

@export var connection_id: String = ""
@export var source_business_id: String = ""
@export var target_business_id: String = ""
@export var source_scene_id: String = ""
@export var target_scene_id: String = ""
@export var signal_name: String = ""
@export var method_name: String = ""
@export var persistence_kind: String = "persistent"
@export var source_locator: String = ""
@export var target_locator: String = ""
@export var metadata: Dictionary = {}

var _source_ref: WeakRef
var _target_ref: WeakRef
var connected: bool = false

func configure(p_source_id: String, p_signal: String, p_target_id: String, p_method: String, p_persistent: bool = true) -> GMSignalConnection:
	source_business_id = p_source_id
	signal_name = p_signal
	target_business_id = p_target_id
	method_name = p_method
	persistence_kind = "persistent" if p_persistent else "runtime_dynamic"
	if connection_id.is_empty(): connection_id = "gm.signal.%s.%s.%s" % [_slug(source_business_id), _slug(signal_name), _slug(method_name)]
	return self

func validate(source: Object, target: Object) -> Dictionary:
	var errors: Array[Dictionary] = []
	if source == null or not is_instance_valid(source): errors.append(_error("signal.source_released", "信号源对象已释放。", "source"))
	if target == null or not is_instance_valid(target): errors.append(_error("signal.target_released", "信号目标对象已释放。", "target"))
	if signal_name.strip_edges().is_empty(): errors.append(_error("signal.name_missing", "信号连接缺少信号名。", "signal_name"))
	if method_name.strip_edges().is_empty(): errors.append(_error("signal.method_missing", "信号连接缺少 Callable 方法名。", "method_name"))
	if not errors.is_empty(): return _validation_result(errors)
	var signal_info := GMSignalSignature.find_signal(source, signal_name)
	if signal_info.is_empty(): errors.append(_error("signal.missing", "信号源没有名为 %s 的 Godot 信号。" % signal_name, "signal_name"))
	var method_result := GMSignalSignature.enumerate_methods(target, method_name)
	if not method_result.ok: errors.append(_error("signal.method_missing", "目标对象没有方法 %s，无法构造 Callable。" % method_name, "method_name"))
	if errors.is_empty():
		var method_info: Dictionary = method_result.methods[0]
		var signature := GMSignalSignature.compare(signal_info, method_info)
		if not signature.ok:
			errors.append({"code": "signal.signature_mismatch", "reason_zh": signature.reason_zh, "field": "method_name", "signature": signature})
	return _validation_result(errors)

func connect_to(source: Object, target: Object) -> Dictionary:
	var check := validate(source, target)
	if not check.ok: return check
	var callable := Callable(target, method_name)
	if source.is_connected(signal_name, callable):
		connected = true
		_source_ref = weakref(source)
		_target_ref = weakref(target)
		return {"ok": false, "code": "signal.duplicate_connection", "reason_zh": "信号已存在相同连接，拒绝重复连接。", "duplicate": true, "connection": to_dict()}
	var error := source.connect(signal_name, callable)
	if error != OK:
		return {"ok": false, "code": "signal.connect_failed", "reason_zh": "Godot 信号连接失败：%s。" % error, "error": error, "connection": to_dict()}
	_source_ref = weakref(source)
	_target_ref = weakref(target)
	connected = true
	return {"ok": true, "connected": true, "duplicate": false, "persistence_kind": persistence_kind, "connection": to_dict(), "signature": _signature_snapshot(source, target)}

func disconnect_from(source: Object = null, target: Object = null) -> Dictionary:
	var actual_source: Object = source if source != null else (_source_ref.get_ref() if _source_ref != null else null)
	var actual_target: Object = target if target != null else (_target_ref.get_ref() if _target_ref != null else null)
	if actual_source == null or not is_instance_valid(actual_source):
		connected = false
		return {"ok": false, "code": "signal.source_released", "reason_zh": "断开信号时信号源已释放。", "disconnected": false}
	if actual_target == null or not is_instance_valid(actual_target):
		connected = false
		return {"ok": false, "code": "signal.target_released", "reason_zh": "断开信号时信号目标已释放。", "disconnected": false}
	if GMSignalSignature.find_signal(actual_source, signal_name).is_empty():
		connected = false
		return {"ok": false, "code": "signal.missing", "reason_zh": "信号源没有名为 %s 的 Godot 信号，无法断开。" % signal_name, "disconnected": false}
	var callable := Callable(actual_target, method_name)
	if not actual_source.is_connected(signal_name, callable):
		connected = false
		return {"ok": false, "code": "signal.not_connected", "reason_zh": "找不到需要断开的信号连接。", "disconnected": false}
	actual_source.disconnect(signal_name, callable)
	connected = false
	return {"ok": true, "disconnected": true, "connection_id": connection_id}

func is_live_connected() -> bool:
	var source: Object = _source_ref.get_ref() if _source_ref != null else null
	var target: Object = _target_ref.get_ref() if _target_ref != null else null
	if source == null or not is_instance_valid(source) or target == null or not is_instance_valid(target): return false
	if GMSignalSignature.find_signal(source, signal_name).is_empty(): return false
	return source.is_connected(signal_name, Callable(target, method_name))

func signature_snapshot(source: Object, target: Object) -> Dictionary:
	return _signature_snapshot(source, target)

func to_dict() -> Dictionary:
	return {"connection_id": connection_id, "source_business_id": source_business_id, "target_business_id": target_business_id, "source_scene_id": source_scene_id, "target_scene_id": target_scene_id, "signal_name": signal_name, "method_name": method_name, "persistence_kind": persistence_kind, "source_locator": source_locator, "target_locator": target_locator, "metadata": metadata.duplicate(true), "connected": connected, "live_connected": is_live_connected()}

static func from_dict(value: Dictionary) -> GMSignalConnection:
	var result := GMSignalConnection.new()
	result.connection_id = str(value.get("connection_id", ""))
	result.source_business_id = str(value.get("source_business_id", ""))
	result.target_business_id = str(value.get("target_business_id", ""))
	result.source_scene_id = str(value.get("source_scene_id", ""))
	result.target_scene_id = str(value.get("target_scene_id", ""))
	result.signal_name = str(value.get("signal_name", ""))
	result.method_name = str(value.get("method_name", ""))
	result.persistence_kind = str(value.get("persistence_kind", "persistent"))
	result.source_locator = str(value.get("source_locator", ""))
	result.target_locator = str(value.get("target_locator", ""))
	result.metadata = value.get("metadata", {}).duplicate(true) if value.get("metadata", {}) is Dictionary else {}
	return result

func _signature_snapshot(source: Object, target: Object) -> Dictionary:
	var signal_info := GMSignalSignature.find_signal(source, signal_name)
	var method_result := GMSignalSignature.enumerate_methods(target, method_name)
	var method_info: Dictionary = method_result.methods[0] if method_result.ok else {}
	var compare := GMSignalSignature.compare(signal_info, method_info) if not signal_info.is_empty() and not method_info.is_empty() else {"ok": false, "reason_zh": "信号或 Callable 方法签名不存在。"}
	return {"signal": signal_info, "method": method_info, "compatibility": compare, "callable": {"target_business_id": target_business_id, "method": method_name}}

func _validation_result(errors: Array[Dictionary]) -> Dictionary:
	var messages: Array[String] = []
	for row in errors: messages.append(str(row.get("reason_zh", "信号连接无效。")))
	return {"ok": errors.is_empty(), "code": "signal.valid" if errors.is_empty() else "signal.invalid", "errors": errors, "errors_zh": messages, "connection": to_dict()}

func _error(code: String, reason_zh: String, field: String) -> Dictionary:
	return {"code": code, "reason_zh": reason_zh, "field": field}

func _slug(value: String) -> String:
	var result := ""
	for index in value.to_lower().length():
		var code := value.to_lower().unicode_at(index)
		result += value.to_lower().substr(index, 1) if ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45) else "_"
	return result.trim_prefix("_").trim_suffix("_") if not result.is_empty() else "connection"
