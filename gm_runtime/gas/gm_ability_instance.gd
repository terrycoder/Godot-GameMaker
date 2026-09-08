class_name GMAbilityInstance
extends RefCounted

## 一次能力激活的唯一生命周期实现。能力定义只提供钩子，不能自行复制状态机。

enum State { IDLE, REQUESTED, CHECKING, COMMITTING, ACTIVATING, ACTIVE, ENDING, COMPLETED, FAILED, CANCELLED }
const ACTIVATION_REQUESTED := State.REQUESTED

var instance_id: String = ""
var host: GMAbilitySystemHost
var definition: GMAbilityDefinition
var spec: GMAbilitySpec
var request: GMAbilityActivationRequest
var causal_chain: GMCausalChain
var state: State = State.IDLE
var phase_trace: Array[String] = []
var timeline: GMAbilityTimeline
var result: Dictionary = {}
var tasks: Array[GMAbilityTask] = []
var task_results: Array[Dictionary] = []
var current_task_index: int = 0
var started_task_ids: Dictionary = {}
var handled_task_ids: Dictionary = {}
var domain_started: bool = false
var terminal_callback_sent: bool = false
var _host_event_connected: bool = false
var commit_record: Dictionary = {}
var commit_preflight_complete: bool = false

func _init(p_host: GMAbilitySystemHost, p_definition: GMAbilityDefinition, p_spec: GMAbilitySpec, p_request: GMAbilityActivationRequest, p_instance_id: String = "") -> void:
	host = p_host
	definition = p_definition
	spec = p_spec
	request = p_request
	instance_id = p_instance_id
	if instance_id.is_empty():
		instance_id = p_request.derive_instance_id(1, 0) if p_request != null else "gm.ability.instance.v2.req.%s" % str(Time.get_ticks_usec()).sha256_text()
	timeline = GMAbilityTimeline.new()
	causal_chain = p_request.causal_chain if p_request != null and p_request.causal_chain != null else GMCausalChain.from_activation_request(p_request)

func run() -> Dictionary:
	if state == State.IDLE: return start()
	if not is_terminal(): return status_snapshot(true)
	return result.duplicate(true)

func start() -> Dictionary:
	if state == State.IDLE:
		var preflight := preflight_check()
		if not preflight.ok: return preflight
	elif state != State.CHECKING and state != State.COMMITTING:
		return _rejected("ability.already_started", "能力实例只能启动一次。")
	return _start_after_preflight()

func preflight_check() -> Dictionary:
	if state != State.IDLE:
		return _rejected("ability.preflight_already_started", "能力候选预检只能执行一次。")
	if definition == null or host == null or request == null:
		return _fail({"ok": false, "code": "ability.context_missing", "reason_zh": "能力实例缺少定义、宿主或请求。"})
	if not _transition(State.REQUESTED, "收到能力激活请求。").ok: return _illegal_state(State.REQUESTED)
	if not _transition(State.CHECKING, "开始检查能力条件。").ok: return _illegal_state(State.CHECKING)
	var check := _normalize_hook(definition.can_activate(host, request, spec), "能力条件检查失败。")
	if not check.ok: return _fail(check)
	return status_snapshot(true)

func _start_after_preflight() -> Dictionary:
	if state == State.CHECKING:
		var commit_preflight := preflight_commit()
		if not commit_preflight.ok: return commit_preflight
	elif state != State.COMMITTING or not commit_preflight_complete:
		return _rejected("ability.commit_preflight_missing", "能力实例缺少提交预检查。")
	var commit := _normalize_hook(definition.commit_costs_and_cooldowns(host, request, spec), "能力提交失败。")
	if not commit.ok: return _fail(commit)
	if host.has_method("commit_ability_commit") and not bool(commit_record.get("committed", false)):
		var committed := _normalize_hook(host.commit_ability_commit(definition, request, spec, self), "能力成本提交失败。")
		if not committed.ok: return _fail(committed)
		commit_record = committed.duplicate(true)
	if not _transition(State.ACTIVATING, "提交完成，开始激活能力。").ok: return _illegal_state(State.ACTIVATING)
	var activated := _normalize_hook(definition.on_activate(host, request, spec), "能力激活失败。")
	if not activated.ok: return _fail(activated)
	if not _transition(State.ACTIVE, "能力进入 ACTIVE，开始执行任务。").ok: return _illegal_state(State.ACTIVE)
	_connect_host_events()
	var task_list: Variant = definition.create_tasks(host, request, spec)
	if task_list == null: task_list = []
	if not task_list is Array:
		return _fail({"ok": false, "code": "ability.tasks_invalid", "reason_zh": "能力任务工厂必须返回 Array。"})
	for candidate in task_list:
		if candidate == null or not candidate is GMAbilityTask:
			return _fail({"ok": false, "code": "ability.task_invalid", "reason_zh": "能力任务列表包含无效任务。"})
		if started_task_ids.has(candidate.task_id) or tasks.any(func(existing): return existing.task_id == candidate.task_id):
			return _fail({"ok": false, "code": "ability.task_duplicate", "reason_zh": "能力任务 ID 重复：%s" % candidate.task_id})
		tasks.append(candidate)
	if tasks.is_empty():
		return _finish_domain()
	if _is_parallel_tasks():
		for task in tasks: _start_task(task)
		if _all_tasks_terminal(): return _finish_domain()
	else:
		_start_next_serial_task()
	if is_terminal(): return result.duplicate(true)
	return status_snapshot(true)

func preflight_commit() -> Dictionary:
	if state != State.CHECKING:
		return _rejected("ability.commit_preflight_invalid_state", "提交预检查只能从 CHECKING 开始。")
	if not _transition(State.COMMITTING, "条件检查通过，开始提交成本与冷却。").ok: return _illegal_state(State.COMMITTING)
	if host.has_method("prepare_ability_commit"):
		var prepared := _normalize_hook(host.prepare_ability_commit(definition, request, spec), "能力成本预检失败。")
		if not prepared.ok: return _fail(prepared)
		commit_record = prepared.duplicate(true)
	var pre_commit := _normalize_hook(definition.pre_commit(host, request, spec), "能力提交前检查失败。")
	if not pre_commit.ok: return _fail(pre_commit)
	commit_preflight_complete = true
	return status_snapshot(true)

func tick(delta: float = 0.0) -> Dictionary:
	if is_terminal(): return result.duplicate(true)
	if state != State.ACTIVE: return status_snapshot(true)
	if _is_parallel_tasks():
		for task in tasks:
			if task != null and started_task_ids.has(task.task_id) and not task.is_terminal(): task.tick(delta)
	else:
		var current := _current_serial_task()
		if current != null and started_task_ids.has(current.task_id) and not current.is_terminal(): current.tick(delta)
	if not is_terminal() and _all_tasks_terminal(): return _finish_domain()
	return status_snapshot(true)

func cancel(reason_zh: String = "能力激活已取消。") -> Dictionary:
	if is_terminal(): return _rejected("ability.already_finished", "能力实例已经结束，重复取消被拒绝。")
	if not _transition(State.CANCELLED, reason_zh).ok: return _illegal_state(State.CANCELLED)
	_cancel_tasks("能力取消传播：%s" % reason_zh)
	_disconnect_host_events()
	if not terminal_callback_sent:
		terminal_callback_sent = true
		if definition != null: definition.on_cancel(host, request, spec, reason_zh)
		if host != null and host.has_method("_record_instance_commit_result"): host._record_instance_commit_result(self, "cancelled")
	result = _base_result(false, "CANCELLED", "ability.cancelled", reason_zh)
	result["task_results"] = task_results.duplicate(true)
	_notify_host_terminal()
	return result.duplicate(true)

func fail_external(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	return _fail({"ok": false, "code": code, "reason_zh": reason_zh, "details": details})

func emit_cue(parameters: GMCueParameters) -> Dictionary:
	if is_terminal():
		return {"ok": false, "code": "cue.after_ability_finished", "reason_zh": "能力结束后禁止发出该能力的 Cue。", "instance_id": instance_id}
	return host.emit_cue(parameters, self) if host != null else {"ok": false, "code": "cue.host_missing", "reason_zh": "能力 Cue 缺少宿主。"}

func is_terminal() -> bool:
	return state == State.COMPLETED or state == State.FAILED or state == State.CANCELLED

func is_active() -> bool:
	return state == State.ACTIVE

func state_name() -> String:
	return State.keys()[state]

func status_snapshot(pending: bool = false) -> Dictionary:
	return {
		"ok": state != State.FAILED and state != State.CANCELLED,
		"state": state_name(),
		"pending": pending and not is_terminal(),
		"instance_id": instance_id,
		"ability_id": definition.ability_id if definition != null else "",
		"phase_trace": phase_trace.duplicate(),
		"timeline": timeline.to_array() if timeline != null else [],
		"tasks": tasks.map(func(task): return task.to_dict()),
		"causal_chain": causal_chain.to_dict() if causal_chain != null else {},
	}

func to_timeline() -> Dictionary:
	return {
		"instance_id": instance_id,
		"ability_id": definition.ability_id if definition != null else "",
		"state": state_name(),
		"phase_trace": phase_trace.duplicate(),
		"entries": timeline.to_array() if timeline != null else [],
	}

func release_tasks() -> void:
	for task in tasks:
		if task != null and not task.released: task.release("能力实例已从宿主释放。")

func _start_next_serial_task() -> void:
	while not is_terminal() and current_task_index < tasks.size():
		var task := tasks[current_task_index]
		current_task_index += 1
		_start_task(task)
		if not task.is_terminal(): return
	if not is_terminal(): _finish_domain()

func _start_task(task: GMAbilityTask) -> void:
	if task == null or started_task_ids.has(task.task_id) or is_terminal(): return
	started_task_ids[task.task_id] = true
	task.finished.connect(_on_task_finished.bind(task))
	var task_start := task.start({"instance": self, "host": host, "scheduler": host.scheduler, "request": request})
	if task_start.terminal and task.is_terminal() and not handled_task_ids.has(task.task_id):
		_on_task_finished(task_start, task)

func _on_task_finished(task_result: GMAbilityTaskResult, task: GMAbilityTask) -> void:
	if is_terminal() or task == null or task_result == null or handled_task_ids.has(task.task_id): return
	handled_task_ids[task.task_id] = true
	var snapshot := task_result.to_dict()
	task_results.append(snapshot)
	timeline.append_event("TASK_%s" % task_result.state, task_result.reason_zh, host.scheduler, {"task_id": task.task_id, "task_result": snapshot})
	if not task_result.ok:
		if task_result.code == "task.cancelled":
			cancel("任务取消传播：%s" % task_result.reason_zh)
		else:
			_fail({"ok": false, "code": task_result.code, "reason_zh": task_result.reason_zh, "task_id": task.task_id, "task": snapshot})
		return
	var hook := _normalize_hook(definition.on_task_event(host, request, spec, snapshot), "能力任务回调失败。")
	if not hook.ok:
		_fail(hook)
		return
	if _is_parallel_tasks():
		if _all_tasks_terminal(): _finish_domain()
	else:
		_start_next_serial_task()

func _finish_domain() -> Dictionary:
	if is_terminal(): return result.duplicate(true)
	if domain_started: return status_snapshot(true)
	domain_started = true
	var domain_result := _normalize_hook(definition.execute(host, request, spec), "能力执行失败。")
	if not domain_result.ok: return _fail(domain_result)
	if not _transition(State.ENDING, "任务与领域命令完成，开始结束能力。").ok: return _illegal_state(State.ENDING)
	if not _transition(State.COMPLETED, "能力成功完成。").ok: return _illegal_state(State.COMPLETED)
	_disconnect_host_events()
	result = _base_result(true, "COMPLETED", "ability.completed", "能力已完成。")
	result["domain_result"] = domain_result
	result["task_results"] = task_results.duplicate(true)
	if not terminal_callback_sent:
		terminal_callback_sent = true
		if definition != null: definition.on_end(host, request, spec, result)
	if host != null and host.has_method("_record_instance_commit_result"): host._record_instance_commit_result(self, "completed")
	_notify_host_terminal()
	return result.duplicate(true)

func _fail(failure: Dictionary) -> Dictionary:
	if is_terminal(): return _rejected("ability.already_finished", "能力实例已经结束，重复结束被拒绝。")
	var code := str(failure.get("code", "ability.failed"))
	var reason := str(failure.get("reason_zh", "能力激活失败。"))
	if not _transition(State.FAILED, reason).ok: return _illegal_state(State.FAILED)
	_cancel_tasks("能力失败传播：%s" % reason)
	_disconnect_host_events()
	result = _base_result(false, "FAILED", code, reason)
	result["details"] = failure.duplicate(true)
	result["task_results"] = task_results.duplicate(true)
	if not terminal_callback_sent:
		terminal_callback_sent = true
		if definition != null: definition.on_fail(host, request, spec, result)
	if host != null and host.has_method("_record_instance_commit_result"): host._record_instance_commit_result(self, "failed")
	_notify_host_terminal()
	return result.duplicate(true)

func _base_result(p_ok: bool, p_state: String, code: String, reason: String) -> Dictionary:
	return {
		"ok": p_ok,
		"state": p_state,
		"failure_code": "" if p_ok else code,
		"failure_reason_zh": "" if p_ok else reason,
		"reason_zh": reason,
		"ability_id": definition.ability_id if definition != null else "",
		"instance_id": instance_id,
		"phase_trace": phase_trace.duplicate(),
		"timeline": timeline.to_array() if timeline != null else [],
		"request": request.to_dict() if request != null else {},
		"causal_chain": causal_chain.to_dict() if causal_chain != null else {},
		}

func _cancel_tasks(reason_zh: String) -> void:
	for task in tasks:
		if task == null or task.is_terminal(): continue
		var task_result := task.cancel(reason_zh)
		if task_result != null and task_result.terminal and not handled_task_ids.has(task.task_id):
			handled_task_ids[task.task_id] = true
			var snapshot := task_result.to_dict()
			task_results.append(snapshot)
			timeline.append_event("TASK_%s" % task_result.state, task_result.reason_zh, host.scheduler if host != null else null, {"task_id": task.task_id, "task_result": snapshot})

func _transition(next_state: State, reason_zh: String) -> Dictionary:
	if not _is_allowed_transition(state, next_state):
		if timeline != null: timeline.record(State.keys()[next_state], reason_zh, host.scheduler if host != null else null, false, {"from_state": state_name(), "error_code": "ability.illegal_state_transition"})
		return {"ok": false, "code": "ability.illegal_state_transition", "reason_zh": "非法能力状态跳转：%s -> %s" % [state_name(), State.keys()[next_state]]}
	state = next_state
	var name := state_name()
	phase_trace.append(name)
	if timeline != null: timeline.record(name, reason_zh, host.scheduler if host != null else null)
	return {"ok": true, "state": name}

func _set_state(next_state: State) -> Dictionary:
	return _transition(next_state, "内部状态转换。")

func _is_allowed_transition(from_state: State, to_state: State) -> bool:
	match from_state:
		State.IDLE: return to_state == State.REQUESTED or to_state == State.CANCELLED or to_state == State.FAILED
		State.REQUESTED: return to_state in [State.CHECKING, State.CANCELLED, State.FAILED]
		State.CHECKING: return to_state in [State.COMMITTING, State.CANCELLED, State.FAILED]
		State.COMMITTING: return to_state in [State.ACTIVATING, State.CANCELLED, State.FAILED]
		State.ACTIVATING: return to_state in [State.ACTIVE, State.CANCELLED, State.FAILED]
		State.ACTIVE: return to_state in [State.ENDING, State.CANCELLED, State.FAILED]
		State.ENDING: return to_state in [State.COMPLETED, State.CANCELLED, State.FAILED]
		_: return false

func _is_parallel_tasks() -> bool:
	return definition != null and (definition.task_execution_mode == "并行" or definition.task_execution_mode == "parallel")

func _all_tasks_terminal() -> bool:
	if tasks.is_empty(): return true
	for task in tasks:
		if task == null or not started_task_ids.has(task.task_id) or not task.is_terminal(): return false
	return true

func _current_serial_task() -> GMAbilityTask:
	var index := current_task_index - 1
	return tasks[index] if index >= 0 and index < tasks.size() else null

func _connect_host_events() -> void:
	if host != null and not _host_event_connected:
		host.gameplay_event.connect(_on_gameplay_event)
		_host_event_connected = true

func _disconnect_host_events() -> void:
	if _host_event_connected and host != null and host.is_connected("gameplay_event", Callable(self, "_on_gameplay_event")):
		host.disconnect("gameplay_event", Callable(self, "_on_gameplay_event"))
	_host_event_connected = false

func _on_gameplay_event(event: GMGameplayEvent) -> void:
	if is_terminal(): return
	for task in tasks:
		if task != null and started_task_ids.has(task.task_id) and not task.is_terminal(): task.handle_event(event)

func _normalize_hook(value: Variant, default_reason: String) -> Dictionary:
	if value is Dictionary:
		var result_value: Dictionary = value.duplicate(true)
		if not result_value.has("ok"): result_value["ok"] = true
		if not result_value.has("reason_zh"): result_value["reason_zh"] = default_reason if not result_value.get("ok", true) else "钩子已完成。"
		return result_value
	if value == null: return {"ok": true}
	if value is bool: return {"ok": value, "reason_zh": default_reason}
	return {"ok": true, "result": value}

func _rejected(code: String, reason_zh: String) -> Dictionary:
	return {"ok": false, "state": state_name(), "failure_code": code, "failure_reason_zh": reason_zh, "reason_zh": reason_zh, "instance_id": instance_id, "phase_trace": phase_trace.duplicate()}

func _notify_host_terminal() -> void:
	if host != null and host.has_method("_on_instance_terminal"):
		host._on_instance_terminal(self)

func _illegal_state(next_state: State) -> Dictionary:
	return _rejected("ability.illegal_state_transition", "非法能力状态跳转：%s -> %s" % [state_name(), State.keys()[next_state]])
