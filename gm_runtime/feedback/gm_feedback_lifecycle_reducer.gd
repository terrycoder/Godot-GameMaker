class_name GMFeedbackLifecycleReducer
extends RefCounted

## Pure lifecycle state machine shared by live playback and snapshot replay.
## The journal is the only input needed to reconstruct state; all receipt and
## timing projections are derived here rather than trusted from a snapshot.

const JOURNAL_SCHEMA := "gm.feedback.lifecycle_journal.v2"
const EVENT_FIELDS := ["event", "step_id", "logical_tick", "code", "reason_zh", "details", "backend_id"]
const EVENTS := ["session_started", "step_accepted", "step_completed", "step_optional_missing", "step_blocked", "step_cancelled", "session_completed", "session_blocked", "session_cancelled"]
const ACTIVE_STATES := ["accepted", "playing"]
const TERMINAL_STATES := ["completed", "blocked", "cancelled"]
const CANONICAL_CODES := {
	"session_started": "feedback.session_started",
	"step_accepted": "feedback.step_accepted",
	"step_completed": "feedback.step_completed",
	"step_optional_missing": "feedback.step_optional_missing",
	"step_blocked": "feedback.step_blocked",
	"step_cancelled": "feedback.step_cancelled",
	"session_completed": "feedback.session_completed",
	"session_blocked": "feedback.session_blocked",
	"session_cancelled": "feedback.session_cancelled"
}
const CANONICAL_REASONS := {
	"step_optional_missing": "可选表现内容缺失。",
	"step_blocked": "表现步骤未能完成。",
	"step_cancelled": "反馈步骤已取消。",
	"session_blocked": "反馈表现被阻断。",
	"session_cancelled": "反馈表现已取消。"
}

static func initial_state(definition: GMFeedbackSequenceDefinition, started_tick: int) -> Dictionary:
	var state := _blank_state(definition, started_tick)
	state.journal.append(event("session_started", "", started_tick, CANONICAL_CODES.session_started, "", {}, ""))
	_refresh_current(state, definition)
	return state

static func _blank_state(_definition: GMFeedbackSequenceDefinition, started_tick: int) -> Dictionary:
	return {"schema": JOURNAL_SCHEMA, "state": "accepted", "started_tick": started_tick, "completed_tick": 0, "current_step_id": "", "current_step_index": 0, "completed_steps": {}, "completed_ticks": {}, "accepted_steps": {}, "due_ticks": {}, "step_receipts": [], "optional_missing": [], "blocked_reason": {}, "cancel_reason": "", "backend_kinds": [], "journal": []}

static func event(event_name: String, step_id: String, logical_tick: int, code: String, reason_zh: String, details: Dictionary = {}, backend_id: String = "") -> Dictionary:
	return {"event": event_name, "step_id": step_id, "logical_tick": logical_tick, "code": code, "reason_zh": reason_zh, "details": details.duplicate(true), "backend_id": backend_id}

static func validate_event(value: Variant, json_boundary: bool = false) -> Dictionary:
	return _validate_event(value, json_boundary)

static func next_action(state: Dictionary, definition: GMFeedbackSequenceDefinition, tick: int) -> Dictionary:
	if str(state.get("state", "")) in TERMINAL_STATES:
		return {}
	var ordered := definition.ordered_steps()
	for step in ordered:
		if state.get("accepted_steps", {}).has(step.step_id):
			if int(state.get("due_ticks", {}).get(step.step_id, 601)) <= tick:
				return {"kind": "complete", "step": step}
			continue
		if state.get("completed_steps", {}).has(step.step_id):
			continue
		if step.logical_order > tick or not _dependencies_complete(state, step):
			continue
		return {"kind": "execute", "step": step}
	return {}

static func apply_event(state: Dictionary, definition: GMFeedbackSequenceDefinition, raw_event: Variant, source_fact_id: String = "") -> Dictionary:
	var check := _validate_event(raw_event)
	if not check.ok:
		return check
	var item: Dictionary = raw_event
	var event_name := str(item.event)
	if event_name not in EVENTS:
		return _failure("feedback.lifecycle_event_unknown", "生命周期journal包含未知事件。")
	var tick := int(item.logical_tick)
	if state.journal.is_empty() and event_name != "session_started":
		return _failure("feedback.lifecycle_start_missing", "生命周期journal必须从session_started开始。")
	if not state.journal.is_empty() and tick < int(state.journal[-1].logical_tick):
		return _failure("feedback.lifecycle_event_order_invalid", "生命周期journal事件时钟必须单调递增。")
	if event_name == "session_started":
		if not state.journal.is_empty() or str(item.step_id) != "" or item.code != CANONICAL_CODES.session_started or not str(item.reason_zh).is_empty() or not item.details.is_empty() or not str(item.backend_id).is_empty():
			return _failure("feedback.lifecycle_start_invalid", "session_started必须是唯一且无附加语义的首事件。")
		state.started_tick = tick
		state.state = "accepted"
		state.journal.append(item.duplicate(true))
		_refresh_current(state, definition)
		return {"ok": true, "code": "feedback.lifecycle_event_applied", "state": state}
	if tick < int(state.started_tick):
		return _failure("feedback.lifecycle_event_before_start", "生命周期事件不能早于session启动时钟。")
	var step := _step_for(definition, str(item.step_id))
	if event_name.begins_with("step_") and step == null:
		return _failure("feedback.lifecycle_step_unknown", "生命周期事件引用了当前definition之外的步骤。")
	if item.code != str(CANONICAL_CODES.get(event_name, "")):
		return _failure("feedback.lifecycle_code_noncanonical", "生命周期事件code不是当前status的canonical code。", {"event": event_name})
	if event_name in CANONICAL_REASONS and str(item.reason_zh) != str(CANONICAL_REASONS[event_name]):
		return _failure("feedback.lifecycle_reason_noncanonical", "生命周期事件reason不是当前status的canonical reason。", {"event": event_name})
	var details_check := GMFeedbackValidation.stable_value(item.details, "$.details")
	if not details_check.ok:
		return details_check
	match event_name:
		"step_accepted":
			var accepted := _apply_step_accepted(state, definition, step, item)
			if not accepted.ok:
				return accepted
		"step_completed":
			var completed := _apply_step_completed(state, definition, step, item)
			if not completed.ok:
				return completed
		"step_optional_missing":
			var missing := _apply_step_optional_missing(state, definition, step, item)
			if not missing.ok:
				return missing
		"step_blocked":
			var blocked := _apply_step_blocked(state, definition, step, item, source_fact_id)
			if not blocked.ok:
				return blocked
		"step_cancelled":
			var cancelled := _apply_step_cancelled(state, definition, step, item)
			if not cancelled.ok:
				return cancelled
		"session_completed":
			var terminal_completed := _apply_session_completed(state, definition, item)
			if not terminal_completed.ok:
				return terminal_completed
		"session_blocked":
			var terminal_blocked := _apply_session_blocked(state, item)
			if not terminal_blocked.ok:
				return terminal_blocked
		"session_cancelled":
			var terminal_cancelled := _apply_session_cancelled(state, item)
			if not terminal_cancelled.ok:
				return terminal_cancelled
	state.journal.append(item.duplicate(true))
	_refresh_current(state, definition)
	return {"ok": true, "code": "feedback.lifecycle_event_applied", "state": state}

static func replay(definition: GMFeedbackSequenceDefinition, journal: Variant, snapshot_tick: int, active: bool, source_fact_id: String = "") -> Dictionary:
	if definition == null or not definition.validate().ok:
		return _failure("feedback.lifecycle_definition_invalid", "生命周期重放需要当前已校验definition。")
	if not journal is Array or journal.is_empty():
		return _failure("feedback.lifecycle_journal_missing", "快照必须保存非空的最小生命周期journal。")
	var state := _blank_state(definition, 0)
	for raw_event in journal:
		var event_check := _validate_event(raw_event)
		if not event_check.ok:
			return event_check
		if int(raw_event.logical_tick) > snapshot_tick:
			return _failure("feedback.lifecycle_event_future", "生命周期journal不能包含晚于快照时钟的事件。")
		var applied := apply_event(state, definition, raw_event, source_fact_id)
		if not applied.ok:
			return applied
	state.journal = journal.duplicate(true)
	if active:
		if str(state.state) not in ACTIVE_STATES or _all_completed(state, definition) or state.completed_tick != 0:
			return _failure("feedback.lifecycle_active_unreachable", "活动生命周期不是reducer可达的accepted/playing状态。")
		var next := next_action(state, definition, snapshot_tick)
		if not next.is_empty():
			return _failure("feedback.lifecycle_active_pending_transition", "活动快照遗漏了当前时钟已经可执行的canonical transition。")
	else:
		if str(state.state) not in TERMINAL_STATES or state.completed_tick < state.started_tick:
			return _failure("feedback.lifecycle_terminal_unreachable", "终态生命周期缺少可达的terminal transition。")
	if not _journal_terminal_shape(state):
		return _failure("feedback.lifecycle_terminal_journal_invalid", "生命周期journal的终态事件或顺序不符合规范。")
	_refresh_current(state, definition)
	return {"ok": true, "code": "feedback.lifecycle_replayed", "state": state}

static func projection(state: Dictionary) -> Dictionary:
	var due := {}
	for key in state.due_ticks.keys():
		due[str(key)] = int(state.due_ticks[key])
	var backends: Array = []
	for backend_id in state.backend_kinds:
		backends.append(str(backend_id))
	backends.sort()
	return {"state": str(state.state), "current_step_id": str(state.current_step_id), "current_step_index": int(state.current_step_index), "started_logical_tick": int(state.started_tick), "completed_logical_tick": int(state.completed_tick), "due_ticks": due, "step_receipts": state.step_receipts.duplicate(true), "optional_missing": state.optional_missing.duplicate(true), "blocked_reason": state.blocked_reason.duplicate(true), "cancel_reason": str(state.cancel_reason), "backend_kinds": backends, "transition_journal": state.journal.duplicate(true)}

static func all_steps_completed(state: Dictionary, definition: GMFeedbackSequenceDefinition) -> bool:
	return _all_completed(state, definition)

static func current_step(state: Dictionary, definition: GMFeedbackSequenceDefinition) -> GMFeedbackStep:
	var current_id := str(state.get("current_step_id", ""))
	return _step_for(definition, current_id)

static func _apply_step_accepted(state: Dictionary, definition: GMFeedbackSequenceDefinition, step: GMFeedbackStep, item: Dictionary) -> Dictionary:
	if str(state.state) not in ACTIVE_STATES or step == null or state.accepted_steps.has(step.step_id) or state.completed_steps.has(step.step_id):
		return _failure("feedback.lifecycle_accept_unreachable", "step_accepted不是当前生命周期的可达转移。")
	if int(item.logical_tick) < _earliest_start(state, step):
		return _failure("feedback.lifecycle_accept_before_ready", "步骤accepted时钟早于logical_order或依赖实际完成时钟。", {"step_id": step.step_id})
	var backend_id := str(item.backend_id)
	if not backend_id.is_empty():
		if not GMFeedbackValidation.stable_id(backend_id):
			return _failure("feedback.lifecycle_backend_invalid", "步骤backend_id必须是稳定ID。")
		if not state.backend_kinds.has(backend_id):
			state.backend_kinds.append(backend_id)
	state.accepted_steps[step.step_id] = {"accepted_tick": int(item.logical_tick), "backend_id": backend_id}
	state.due_ticks[step.step_id] = mini(600, int(item.logical_tick) + step.duration_ticks)
	state.step_receipts.append({"step_id": step.step_id, "step_kind": step.step_kind, "status": "accepted", "logical_tick": int(item.logical_tick), "code": CANONICAL_CODES.step_accepted, "optional": step.optional})
	state.state = "playing"
	return {"ok": true, "code": "feedback.lifecycle_accept_applied"}

static func _apply_step_completed(state: Dictionary, definition: GMFeedbackSequenceDefinition, step: GMFeedbackStep, item: Dictionary) -> Dictionary:
	if step == null or not state.accepted_steps.has(step.step_id) or state.completed_steps.has(step.step_id):
		return _failure("feedback.lifecycle_complete_unreachable", "step_completed必须对应当前accepted步骤。")
	var accepted_tick := int(state.accepted_steps[step.step_id].accepted_tick)
	var due_tick := int(state.due_ticks.get(step.step_id, 601))
	if int(item.logical_tick) < due_tick or int(item.logical_tick) < _earliest_start(state, step) + step.duration_ticks:
		return _failure("feedback.lifecycle_duration_unreachable", "步骤completed时钟早于依赖实际完成、logical_order、started_tick与duration共同确定的最早时刻。", {"step_id": step.step_id, "accepted_tick": accepted_tick, "due_tick": due_tick})
	if not _dependencies_complete(state, step):
		return _failure("feedback.lifecycle_dependency_unreachable", "步骤completed时其依赖必须已经实际完成。")
	state.accepted_steps.erase(step.step_id)
	state.due_ticks.erase(step.step_id)
	state.completed_steps[step.step_id] = true
	state.completed_ticks[step.step_id] = int(item.logical_tick)
	for receipt in state.step_receipts:
		if str(receipt.step_id) == step.step_id:
			receipt.status = "completed"
			receipt.logical_tick = int(item.logical_tick)
			receipt.code = CANONICAL_CODES.step_completed
			return {"ok": true, "code": "feedback.lifecycle_complete_applied"}
	return _failure("feedback.lifecycle_receipt_missing", "completed转移缺少对应的accepted receipt。")

static func _apply_step_optional_missing(state: Dictionary, definition: GMFeedbackSequenceDefinition, step: GMFeedbackStep, item: Dictionary) -> Dictionary:
	if step == null or not step.optional or state.accepted_steps.has(step.step_id) or state.completed_steps.has(step.step_id) or not _step_ready(state, step, int(item.logical_tick)):
		return _failure("feedback.lifecycle_optional_unreachable", "optional_missing不是当前可选步骤的可达转移。")
	state.completed_steps[step.step_id] = true
	state.completed_ticks[step.step_id] = int(item.logical_tick)
	state.optional_missing.append({"step_id": step.step_id, "code": CANONICAL_CODES.step_optional_missing, "reason_zh": CANONICAL_REASONS.step_optional_missing})
	state.step_receipts.append({"step_id": step.step_id, "step_kind": step.step_kind, "status": "optional_missing", "logical_tick": int(item.logical_tick), "code": CANONICAL_CODES.step_optional_missing, "optional": true})
	state.state = "playing"
	return {"ok": true, "code": "feedback.lifecycle_optional_applied"}

static func _apply_step_blocked(state: Dictionary, definition: GMFeedbackSequenceDefinition, step: GMFeedbackStep, item: Dictionary, source_fact_id: String) -> Dictionary:
	if step == null or step.optional or not _step_ready(state, step, int(item.logical_tick)) or _all_completed(state, definition):
		return _failure("feedback.lifecycle_block_unreachable", "required blocked步骤必须在当前可达且未完成的生命周期中出现。")
	var details: Dictionary = item.details.duplicate(true)
	details["step_id"] = step.step_id
	var reason := GMFeedbackBlockedReason.new(CANONICAL_CODES.step_blocked, CANONICAL_REASONS.step_blocked, "检查当前Presenter、Cue和表现内容后重试。", "presentation", false, source_fact_id, details)
	state.blocked_reason = reason.to_dict()
	state.step_receipts.append({"step_id": step.step_id, "step_kind": step.step_kind, "status": "blocked", "logical_tick": int(item.logical_tick), "code": CANONICAL_CODES.step_blocked, "optional": false})
	state.state = "playing"
	return {"ok": true, "code": "feedback.lifecycle_block_applied"}

static func _apply_step_cancelled(state: Dictionary, definition: GMFeedbackSequenceDefinition, step: GMFeedbackStep, item: Dictionary) -> Dictionary:
	if step == null or str(state.state) not in ACTIVE_STATES or state.completed_steps.has(step.step_id):
		return _failure("feedback.lifecycle_cancel_unreachable", "cancelled步骤必须来自当前未完成的活动生命周期。")
	if state.accepted_steps.has(step.step_id) and int(item.logical_tick) < int(state.accepted_steps[step.step_id].accepted_tick):
		return _failure("feedback.lifecycle_cancel_before_accept", "取消事件不能早于步骤accepted时钟。")
	state.accepted_steps.erase(step.step_id)
	state.due_ticks.erase(step.step_id)
	var updated := false
	for receipt in state.step_receipts:
		if str(receipt.step_id) == step.step_id:
			receipt.status = "cancelled"
			receipt.logical_tick = int(item.logical_tick)
			receipt.code = CANONICAL_CODES.step_cancelled
			updated = true
			break
	if not updated:
		state.step_receipts.append({"step_id": step.step_id, "step_kind": step.step_kind, "status": "cancelled", "logical_tick": int(item.logical_tick), "code": CANONICAL_CODES.step_cancelled, "optional": step.optional})
	state.state = "playing"
	return {"ok": true, "code": "feedback.lifecycle_cancel_applied"}

static func _apply_session_completed(state: Dictionary, definition: GMFeedbackSequenceDefinition, item: Dictionary) -> Dictionary:
	if str(state.state) not in ACTIVE_STATES or not _all_completed(state, definition) or not state.accepted_steps.is_empty() or not state.blocked_reason.is_empty():
		return _failure("feedback.lifecycle_complete_terminal_unreachable", "session_completed必须在所有步骤由reducer完成后出现。")
	if int(item.logical_tick) != _latest_completion_tick(state):
		return _failure("feedback.lifecycle_terminal_tick_unreachable", "session completed tick必须等于最后一个实际步骤完成tick。")
	state.state = "completed"
	state.completed_tick = int(item.logical_tick)
	return {"ok": true, "code": "feedback.lifecycle_terminal_completed"}

static func _apply_session_blocked(state: Dictionary, item: Dictionary) -> Dictionary:
	if str(state.state) not in ACTIVE_STATES or state.blocked_reason.is_empty() or _has_status(state, "cancelled"):
		return _failure("feedback.lifecycle_block_terminal_unreachable", "session_blocked必须紧跟canonical blocked步骤。")
	if int(item.logical_tick) != _latest_receipt_tick(state, "blocked"):
		return _failure("feedback.lifecycle_terminal_tick_unreachable", "session blocked tick必须等于blocked步骤的实际transition tick。")
	state.state = "blocked"
	state.completed_tick = int(item.logical_tick)
	return {"ok": true, "code": "feedback.lifecycle_terminal_blocked"}

static func _apply_session_cancelled(state: Dictionary, item: Dictionary) -> Dictionary:
	if str(state.state) not in ACTIVE_STATES or not _has_status(state, "cancelled") or not state.blocked_reason.is_empty():
		return _failure("feedback.lifecycle_cancel_terminal_unreachable", "session_cancelled必须紧跟canonical cancelled步骤。")
	if int(item.logical_tick) != _latest_receipt_tick(state, "cancelled"):
		return _failure("feedback.lifecycle_terminal_tick_unreachable", "session cancelled tick必须等于cancelled步骤的实际transition tick。")
	state.state = "cancelled"
	state.cancel_reason = CANONICAL_CODES.step_cancelled
	state.completed_tick = int(item.logical_tick)
	return {"ok": true, "code": "feedback.lifecycle_terminal_cancelled"}

static func _validate_event(value: Variant, json_boundary: bool = false) -> Dictionary:
	if not value is Dictionary or not GMFeedbackValidation.exact(value, EVENT_FIELDS):
		return _failure("feedback.lifecycle_event_shape_invalid", "生命周期journal事件字段集合必须精确匹配。")
	var item: Dictionary = value
	if typeof(item.event) != TYPE_STRING or typeof(item.step_id) != TYPE_STRING or typeof(item.code) != TYPE_STRING or typeof(item.reason_zh) != TYPE_STRING or typeof(item.details) != TYPE_DICTIONARY or typeof(item.backend_id) != TYPE_STRING:
		return _failure("feedback.lifecycle_event_variant_invalid", "生命周期journal事件原始Variant类型无效。")
	if item.event not in EVENTS or not GMFeedbackValidation.stable_id(item.step_id, true) or not GMFeedbackValidation.bounded_integer(item.logical_tick, 0, 600, json_boundary) or not GMFeedbackValidation.stable_id(item.code) or not GMFeedbackValidation.stable_id(item.backend_id, true):
		return _failure("feedback.lifecycle_event_value_invalid", "生命周期journal事件身份或时钟无效。")
	return {"ok": true, "code": "feedback.lifecycle_event_valid"}

static func _step_for(definition: GMFeedbackSequenceDefinition, step_id: String) -> GMFeedbackStep:
	for step in definition.ordered_steps():
		if step.step_id == step_id:
			return step
	return null

static func _dependencies_complete(state: Dictionary, step: GMFeedbackStep) -> bool:
	for dependency in step.after_step_ids:
		if not state.completed_steps.has(str(dependency)):
			return false
	return true

static func _step_ready(state: Dictionary, step: GMFeedbackStep, tick: int) -> bool:
	return step != null and step.logical_order <= tick and _dependencies_complete(state, step) and not state.accepted_steps.has(step.step_id) and not state.completed_steps.has(step.step_id)

static func _earliest_start(state: Dictionary, step: GMFeedbackStep) -> int:
	var result := maxi(int(state.started_tick), step.logical_order)
	for dependency in step.after_step_ids:
		result = maxi(result, int(state.completed_ticks.get(str(dependency), 601)))
	return result

static func _all_completed(state: Dictionary, definition: GMFeedbackSequenceDefinition) -> bool:
	return state.completed_steps.size() == definition.ordered_steps().size()

static func _has_status(state: Dictionary, status: String) -> bool:
	for row in state.step_receipts:
		if str(row.status) == status:
			return true
	return false

static func _latest_completion_tick(state: Dictionary) -> int:
	var latest := int(state.started_tick)
	for tick in state.completed_ticks.values():
		latest = maxi(latest, int(tick))
	return latest

static func _latest_receipt_tick(state: Dictionary, status: String) -> int:
	var latest := -1
	for row in state.step_receipts:
		if str(row.status) == status:
			latest = maxi(latest, int(row.logical_tick))
	return latest

static func _journal_terminal_shape(state: Dictionary) -> bool:
	if state.journal.is_empty():
		return false
	var terminal_name := str(state.journal[-1].event)
	if state.state == "completed":
		return terminal_name == "session_completed"
	if state.state == "blocked":
		return terminal_name == "session_blocked"
	if state.state == "cancelled":
		return terminal_name == "session_cancelled"
	return true

static func _refresh_current(state: Dictionary, definition: GMFeedbackSequenceDefinition) -> void:
	var ordered := definition.ordered_steps()
	var current_id := ""
	var current_index := 0
	if state.state == "blocked":
		for index in ordered.size():
			if str(state.step_receipts[-1].step_id) == ordered[index].step_id and str(state.step_receipts[-1].status) == "blocked":
				current_id = ordered[index].step_id
				current_index = index
				break
	elif state.state == "cancelled":
		for index in ordered.size():
			if str(state.step_receipts[-1].step_id) == ordered[index].step_id and str(state.step_receipts[-1].status) == "cancelled":
				current_id = ordered[index].step_id
				current_index = index
				break
	elif state.state in ACTIVE_STATES:
		for index in ordered.size():
			if state.accepted_steps.has(ordered[index].step_id):
				current_id = ordered[index].step_id
				current_index = index
		if current_id.is_empty():
			for index in ordered.size():
				var pending: GMFeedbackStep = ordered[index]
				if not state.completed_steps.has(pending.step_id):
					current_id = pending.step_id
					current_index = index
					break
	if state.state in ["completed"]:
		current_id = ""
		current_index = 0
	state.current_step_id = current_id
	state.current_step_index = current_index

static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
