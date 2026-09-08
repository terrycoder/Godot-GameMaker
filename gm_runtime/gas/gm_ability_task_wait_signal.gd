class_name GMAbilityTaskWaitSignal
extends GMAbilityTask

var signal_source: Object
var signal_name: String = ""
var _connected: bool = false

func _init(p_source: Object = null, p_signal_name: String = "", p_task_id: String = "") -> void:
	signal_source = p_source
	signal_name = p_signal_name
	super._init(p_task_id, {"signal": signal_name})

func _start() -> Variant:
	if signal_source == null or not is_instance_valid(signal_source):
		return fail("task.signal_source_missing", "等待信号任务的信号源已释放或为空。")
	if signal_name.is_empty() or not signal_source.has_signal(signal_name):
		return fail("task.signal_missing", "等待信号任务找不到信号：%s" % signal_name)
	var connect_result := signal_source.connect(signal_name, Callable(self, "_on_signal"))
	if connect_result != OK and connect_result != ERR_ALREADY_IN_USE:
		return fail("task.signal_connect_failed", "等待信号任务连接失败：%s" % signal_name)
	_connected = true
	return _pending("task.waiting_signal", "正在等待信号：%s" % signal_name, {"signal": signal_name})

func _tick(_delta: float) -> Variant:
	if signal_source == null or not is_instance_valid(signal_source):
		return fail("task.signal_source_released", "等待信号期间信号源已释放。")
	return _pending("task.waiting_signal", "正在等待信号：%s" % signal_name, {"signal": signal_name})

func _on_signal(...args: Array) -> void:
	if released or is_terminal(): return
	complete({"signal": signal_name, "args": args.duplicate(true)})

func _after_finish(_result: GMAbilityTaskResult) -> void:
	_disconnect()
	signal_source = null

func _disconnect() -> void:
	if _connected and signal_source != null and is_instance_valid(signal_source) and signal_source.is_connected(signal_name, Callable(self, "_on_signal")):
		signal_source.disconnect(signal_name, Callable(self, "_on_signal"))
	_connected = false
