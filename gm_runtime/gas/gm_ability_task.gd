class_name GMAbilityTask
extends RefCounted

## 所有异步能力步骤的统一宿主。子类只实现 _start/_tick，不自行维护能力生命周期。

signal started(result: GMAbilityTaskResult)
signal progressed(result: GMAbilityTaskResult)
signal completed(result: GMAbilityTaskResult)
signal failed(result: GMAbilityTaskResult)
signal cancelled(result: GMAbilityTaskResult)
signal finished(result: GMAbilityTaskResult)

enum State { IDLE, WAITING, RUNNING, COMPLETED, FAILED, CANCELLED, RELEASED }

var task_id: String = ""
var state: State = State.IDLE
var task_payload: Dictionary = {}
var scheduler: GMAbilityScheduler
var owner_instance: Object
var task_context: Dictionary = {}
var elapsed: float = 0.0
var timeout_amount: float = 0.0
var timeout_unit: String = "seconds"
var result: GMAbilityTaskResult
var released: bool = false
var callback_epoch: int = 0
var _finish_emitted: bool = false
var _timeout_metric_unit: String = ""
var _timeout_start_metric: float = 0.0

func _init(p_task_id: String = "", p_payload: Dictionary = {}) -> void:
	task_id = p_task_id if not p_task_id.strip_edges().is_empty() else "gm.runtime.task.%d" % Time.get_ticks_usec()
	task_payload = p_payload.duplicate(true)

func start(context: Dictionary = {}) -> GMAbilityTaskResult:
	if released:
		return _rejected("task.released", "能力任务已释放，不能再次启动。")
	if state != State.IDLE:
		return _rejected("task.already_started", "能力任务只能启动一次。")
	task_context = context.duplicate(true)
	owner_instance = context.get("instance", null)
	scheduler = context.get("scheduler", null)
	_capture_timeout_baseline()
	state = State.WAITING
	var started_result := _pending("task.started", "能力任务已开始等待。", {"task_id": task_id})
	started.emit(started_result)
	var hook_result: Variant = _start()
	if hook_result is GMAbilityTaskResult:
		if hook_result.terminal:
			return hook_result
		return hook_result.with_task(task_id, state_name(), false)
	if hook_result is Dictionary:
		return _apply_hook_dictionary(hook_result)
	return started_result

func tick(delta: float = 0.0) -> GMAbilityTaskResult:
	if released or is_terminal():
		return result if result != null else _rejected("task.callback_rejected", "任务已结束，回调被拒绝。")
	if state != State.WAITING and state != State.RUNNING:
		return _rejected("task.invalid_state", "只有等待中的任务可以推进。")
	if scheduler != null and scheduler.paused:
		return _pending("task.paused", "调度器暂停，任务未推进。", {"elapsed": elapsed})
	state = State.RUNNING
	elapsed += maxf(float(delta), 0.0)
	if timeout_amount > 0.0 and _timeout_reached():
		return fail("task.timeout", "能力任务超时。", {"timeout": timeout_amount, "unit": timeout_unit})
	var hook_result: Variant = _tick(delta)
	if hook_result is GMAbilityTaskResult:
		return hook_result.with_task(task_id, state_name(), hook_result.terminal)
	if hook_result is Dictionary:
		return _apply_hook_dictionary(hook_result)
	return _pending("task.waiting", "能力任务仍在等待。", {"elapsed": elapsed})

func advance(delta: float = 0.0) -> GMAbilityTaskResult:
	return tick(delta)

func handle_event(event: GMGameplayEvent) -> GMAbilityTaskResult:
	if released or is_terminal():
		return _rejected("task.callback_rejected", "任务结束后不得接收 Gameplay Event。")
	return _pending("task.event_ignored", "该任务忽略了当前 Gameplay Event。", {"event_tag": event.event_tag if event != null else ""})

func handle_signal(args: Array = []) -> GMAbilityTaskResult:
	if released or is_terminal():
		return _rejected("task.callback_rejected", "任务结束后不得接收信号回调。")
	return _pending("task.signal_ignored", "该任务忽略了当前信号。", {"args": args.duplicate(true)})

func complete(data: Dictionary = {}) -> GMAbilityTaskResult:
	if not _can_finish():
		return _rejected("task.already_finished", "能力任务已经结束，重复完成被拒绝。")
	state = State.COMPLETED
	var final_data := data.duplicate(true)
	final_data["task_id"] = task_id
	return _finish(true, "task.completed", "能力任务完成。", final_data)

func fail(code: String = "task.failed", reason_zh: String = "能力任务失败。", data: Dictionary = {}) -> GMAbilityTaskResult:
	if not _can_finish():
		return _rejected("task.already_finished", "能力任务已经结束，重复失败被拒绝。")
	state = State.FAILED
	var final_data := data.duplicate(true)
	final_data["task_id"] = task_id
	return _finish(false, code, reason_zh, final_data)

func cancel(reason_zh: String = "能力任务已取消。", data: Dictionary = {}) -> GMAbilityTaskResult:
	if not _can_finish():
		return _rejected("task.already_finished", "能力任务已经结束，重复取消被拒绝。")
	state = State.CANCELLED
	var final_data := data.duplicate(true)
	final_data["task_id"] = task_id
	return _finish(false, "task.cancelled", reason_zh, final_data)

func release(reason_zh: String = "能力任务宿主已释放。") -> GMAbilityTaskResult:
	if released:
		return _rejected("task.released", "能力任务已经释放。")
	var release_result := cancel(reason_zh) if not is_terminal() else (result if result != null else _rejected("task.released", reason_zh))
	released = true
	callback_epoch += 1
	owner_instance = null
	task_context.clear()
	return release_result

func is_terminal() -> bool:
	return state == State.COMPLETED or state == State.FAILED or state == State.CANCELLED or state == State.RELEASED

func accepts_callback(epoch: int = callback_epoch) -> bool:
	return not released and epoch == callback_epoch and not is_terminal()

func state_name() -> String:
	return State.keys()[state]

func to_dict() -> Dictionary:
	return {
		"task_id": task_id,
		"state": state_name(),
		"payload": task_payload.duplicate(true),
		"elapsed": elapsed,
		"released": released,
		"result": result.to_dict() if result != null else {},
	}

func _start() -> Variant:
	return complete({"payload": task_payload})

func _tick(_delta: float) -> Variant:
	return _pending("task.waiting", "能力任务仍在等待。", {"elapsed": elapsed})

func _after_finish(_result: GMAbilityTaskResult) -> void:
	pass

func _can_finish() -> bool:
	return not released and not is_terminal() and not _finish_emitted

func _finish(p_ok: bool, p_code: String, p_reason_zh: String, p_data: Dictionary) -> GMAbilityTaskResult:
	_finish_emitted = true
	result = GMAbilityTaskResult.new(p_ok, p_code, p_reason_zh, p_data, task_id, state_name(), true)
	_after_finish(result)
	if p_ok: completed.emit(result)
	else:
		if state == State.CANCELLED: cancelled.emit(result)
		else: failed.emit(result)
	finished.emit(result)
	return result

func _pending(p_code: String, p_reason_zh: String, p_data: Dictionary = {}) -> GMAbilityTaskResult:
	var pending := GMAbilityTaskResult.new(true, p_code, p_reason_zh, p_data, task_id, state_name(), false)
	progressed.emit(pending)
	return pending

func _rejected(p_code: String, p_reason_zh: String) -> GMAbilityTaskResult:
	var rejected := GMAbilityTaskResult.new(false, p_code, p_reason_zh, {"task_id": task_id}, task_id, state_name(), false)
	rejected.callback_accepted = false
	return rejected

func _apply_hook_dictionary(value: Dictionary) -> GMAbilityTaskResult:
	if value.get("terminal", false):
		if value.get("ok", false): return complete(value.get("data", value))
		return fail(str(value.get("code", "task.failed")), str(value.get("reason_zh", "能力任务失败。")), value.get("data", value))
	return _pending(str(value.get("code", "task.waiting")), str(value.get("reason_zh", "能力任务仍在等待。")), value.get("data", value))

func _timeout_reached() -> bool:
	if scheduler == null: return elapsed >= timeout_amount
	if timeout_unit == "local": return elapsed >= timeout_amount
	return scheduler.metric(_timeout_metric_unit) - _timeout_start_metric >= timeout_amount

func _capture_timeout_baseline() -> void:
	_timeout_metric_unit = timeout_unit
	_timeout_start_metric = 0.0
	if scheduler == null or timeout_unit == "local": return
	if timeout_unit == "auto":
		_timeout_metric_unit = "turns" if scheduler.mode == "turn" else "seconds"
	_timeout_start_metric = scheduler.metric(_timeout_metric_unit)
