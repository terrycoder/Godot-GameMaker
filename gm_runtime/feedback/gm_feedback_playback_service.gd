class_name GMFeedbackPlaybackService
extends RefCounted

## P18 playback coordinator. Live execution is intentionally ephemeral and is
## fed only by a pure presentation plan built from the current upstream
## authority. Presentation playback is
## never a save authority: the retired v1/v2 snapshot, descriptor, catalog and
## journal-restore ancestry is fail-closed below.

const SNAPSHOT_SCHEMA := "gm.feedback.playback.snapshot.v2"
const LEGACY_SNAPSHOT_SCHEMA := "gm.feedback.playback.snapshot.v1"
## Historical fields retained only so legacy helper code remains parseable; no
## public method accepts or writes this shape after EXIT.
const SNAPSHOT_FIELDS := ["schema", "logical_tick", "active", "completed", "receipt_ids", "backend_independent"]
const ROW_FIELDS := ["binding_id", "descriptor_digest", "state", "current_step_id", "current_step_index", "started_logical_tick", "completed_logical_tick", "due_ticks", "transition_journal", "step_receipts", "optional_missing", "blocked_reason", "cancel_reason", "backend_kinds"]
const EPHEMERAL_STATUS_SCHEMA := "gm.feedback.playback.ephemeral_status.v1"
const RETIRED_RESTORE_CODE := "feedback.restore_api_retired"
const MIGRATION_REQUIRED_CODE := "feedback.snapshot_migration_required"
const PRESENTATION_PLAN_REQUIRED_CODE := "feedback.presentation_plan_required"
const MIGRATION_RECEIPT_RETIRED_CODE := "feedback.migration_receipt_retired"
const MAX_ACTIVE := 64

var cue_router: GMCueRouter

## Kept as an inert compatibility property so historical callers fail closed
## without being able to replace or reactivate a catalog-backed restore path.
var restore_catalog:
	get:
		return null
	set(_value):
		pass
var sequences: Dictionary = {}
var backends: Dictionary = {}
var presenters: Dictionary = {}
var active_sessions: Dictionary = {}
var completed_records: Dictionary = {}
var receipts_by_feedback: Dictionary = {}
var request_fingerprints: Dictionary = {}
var logical_tick := 0

func _init(p_cue_router: GMCueRouter = null, _p_authority_reader: GMFeedbackAuthorityReader = null) -> void:
	cue_router = p_cue_router
	# The second argument remains source-compatible for old callers, but P18
	# never retains or consults a reader/store capability.

func register_sequence(definition: GMFeedbackSequenceDefinition) -> Dictionary:
	if definition == null:
		return _failure("feedback.sequence_missing", "不能注册空反馈序列。")
	var checked := definition.validate()
	if not checked.ok:
		return checked
	if sequences.has(definition.sequence_id):
		var existing: GMFeedbackSequenceDefinition = sequences[definition.sequence_id]
		if existing.digest() != definition.digest():
			return _failure("feedback.sequence_conflict", "同一sequence_id不允许注册不同定义。")
		return {"ok": true, "code": "feedback.sequence_idempotent", "sequence_id": definition.sequence_id}
	sequences[definition.sequence_id] = GMFeedbackSequenceDefinition.from_dict(definition.to_dict())
	return {"ok": true, "code": "feedback.sequence_registered", "sequence_id": definition.sequence_id, "digest": definition.digest()}

func register_backend(backend: GMFeedbackBackend) -> Dictionary:
	if backend == null or not GMFeedbackValidation.stable_id(backend.backend_id):
		return _failure("feedback.backend_invalid", "表现后端必须提供稳定backend_id。")
	backends[backend.backend_id] = backend
	return {"ok": true, "code": "feedback.backend_registered", "backend_id": backend.backend_id}

func register_presenter(target_ref: String, presenter: Object) -> Dictionary:
	if not GMFeedbackValidation.stable_id(target_ref) or presenter == null or not is_instance_valid(presenter) or not presenter.has_method("play_semantic_action"):
		return _failure("feedback.presenter_invalid", "Presenter必须是稳定目标对应的现有语义动作入口。")
	if presenters.has(target_ref) and presenters[target_ref] != presenter:
		cancel_target(target_ref, "presentation.player_takeover", "新的Presenter已接管目标，旧反馈已取消。")
	presenters[target_ref] = presenter
	return {"ok": true, "code": "feedback.presenter_registered", "target_ref": target_ref}

func unregister_presenter(target_ref: String, reason_code: String = "presentation.target_unloaded", reason_zh: String = "目标Presenter已卸载，反馈已取消。") -> Dictionary:
	if not GMFeedbackValidation.stable_id(target_ref):
		return _failure("feedback.presenter_target_invalid", "Presenter目标必须是稳定ID。")
	var cancelled := cancel_target(target_ref, reason_code, reason_zh)
	presenters.erase(target_ref)
	return {"ok": true, "code": "feedback.presenter_unregistered", "target_ref": target_ref, "cancelled": cancelled.cancelled if cancelled is Dictionary else 0, "logic_unchanged": true, "domain_facts_written": false}

func handoff_target(target_ref: String, replacement: Object = null) -> Dictionary:
	var removed := unregister_presenter(target_ref, "presentation.player_takeover", "Presenter接管期间清理旧反馈。")
	if replacement == null:
		return {"ok": true, "code": "feedback.presenter_handoff_cleared", "cancelled": removed.cancelled, "logic_unchanged": true, "domain_facts_written": false}
	var registered := register_presenter(target_ref, replacement)
	registered["cancelled"] = removed.cancelled
	registered["logic_unchanged"] = true
	registered["domain_facts_written"] = false
	return registered

## Retired after P18 EXIT.  Descriptor registration was part of the snapshot
## restore ancestry and cannot be used for live playback or persistence.
func register_restore_descriptor(mapped: Dictionary, attention_runtime: GMAgentPlannerRuntime = null) -> Dictionary:
	return _retired_restore_api("register_restore_descriptor")

## Reader-bound mapper artifacts are retired.  They must be converted by the
## upstream mapper into a pure-value PresentationPlan before entering P18.
func play_mapped(_mapped: Variant, _attention_runtime: GMAgentPlannerRuntime = null) -> Dictionary:
	return _retired_presentation_api("play_mapped")

## Accepted P18 playback entrypoint.  Only copied presentation values cross
## this boundary; no FactEventStore, reader, authority package, descriptor,
## catalog, journal, or backend capability is retained.
func play_plan(plan: Variant) -> Dictionary:
	var built := GMFeedbackLivePlaybackContext.from_plan(plan)
	if not built.ok:
		return built
	var context: GMFeedbackLivePlaybackContext = built.context
	var registered := context.validate_registered_definition(sequences)
	if not registered.ok:
		return registered
	return _play_context(context)

func play_request(_request: Variant, _definition: GMFeedbackSequenceDefinition = null) -> Dictionary:
	return _retired_presentation_api("play_request")

func _play_context(context: GMFeedbackLivePlaybackContext) -> Dictionary:
	var request: GMFeedbackPresentationRequest = context.request
	var definition: GMFeedbackSequenceDefinition = context.definition
	if not request is GMFeedbackPresentationRequest or definition == null:
		return _failure("feedback.live_context_invalid", "live表现上下文不完整。")
	if cue_router == null:
		return _blocked_result(request, "feedback.cue_router_missing", "P18未连接现有GMCueRouter，反馈不会静默绕过Cue总线。", {"action": "连接P06 GMCueRouter后重试。"})
	return _play_context_internal(context)

func _play_context_internal(context: GMFeedbackLivePlaybackContext) -> Dictionary:
	var request: GMFeedbackPresentationRequest = context.request
	var fingerprint := request.fingerprint()
	if completed_records.has(request.idempotency_key):
		var completed: Dictionary = completed_records[request.idempotency_key]
		if str(completed.get("fingerprint", "")) != fingerprint:
			return _blocked_result(request, "feedback.idempotency_conflict", "幂等键已对应不同语义反馈，拒绝覆盖既有回执。", {"action": "使用新的幂等键或读取既有PresentationReceipt。"})
		var duplicate := GMPresentationReceipt.from_dict(completed.get("receipt", {}))
		if duplicate == null:
			return _failure("feedback.completed_receipt_invalid", "已完成反馈回执无法再次验证。")
		duplicate.idempotent = true
		if duplicate.status == "blocked":
			var blocked_code := str(duplicate.blocked_reason.get("code", "feedback.step_blocked"))
			return {"ok": false, "code": blocked_code, "reason_zh": str(duplicate.blocked_reason.get("reason_zh", "反馈表现被阻断。")), "receipt": duplicate, "logic_unchanged": true, "domain_facts_written": false}
		return _success_result(duplicate, "feedback.idempotent_replay")
	if active_sessions.has(request.feedback_id):
		var active: Dictionary = active_sessions[request.feedback_id]
		if str(active.get("fingerprint", "")) != fingerprint:
			return _blocked_result(request, "feedback.feedback_id_conflict", "feedback_id已对应不同请求，拒绝覆盖活动反馈。", {"action": "使用新的稳定反馈身份。"})
		var active_receipt := _receipt_from_session(active)
		active_receipt.idempotent = true
		return _success_result(active_receipt, "feedback.active_replay")
	if receipts_by_feedback.has(request.feedback_id):
		return _blocked_result(request, "feedback.feedback_id_conflict", "feedback_id已对应既有表现回执，拒绝使用新的幂等身份覆盖。", {"action": "读取既有PresentationReceipt或使用新的稳定反馈身份。"})
	if active_sessions.size() >= MAX_ACTIVE:
		return _blocked_result(request, "feedback.active_limit", "活动反馈数量达到有界上限。", {"action": "先取消或完成旧反馈后重试。"})
	var session := _new_session(context, fingerprint)
	active_sessions[request.feedback_id] = session
	request_fingerprints[request.idempotency_key] = fingerprint
	_advance_session(session, logical_tick)
	return _result_for_session(session)

func advance_to(target_tick: int) -> Dictionary:
	if typeof(target_tick) != TYPE_INT or target_tick < logical_tick or target_tick > 600:
		return _failure("feedback.logical_tick_invalid", "反馈播放逻辑时钟必须单调递增且不超过600。")
	logical_tick = target_tick
	var processed: Array = []
	for feedback_id in active_sessions.keys().duplicate():
		var session: Dictionary = active_sessions.get(feedback_id, {})
		if session.is_empty():
			continue
		_advance_session(session, logical_tick)
		processed.append(_receipt_from_session(session).to_dict())
	return {"ok": true, "code": "feedback.advanced", "logical_tick": logical_tick, "active": processed, "logic_unchanged": true, "domain_facts_written": false}

func drain(max_ticks: int = 600) -> Dictionary:
	if typeof(max_ticks) != TYPE_INT or max_ticks < 0 or max_ticks > 600:
		return _failure("feedback.drain_limit_invalid", "反馈排空步数必须是0至600的原生整数。")
	var advanced := 0
	while not active_sessions.is_empty() and advanced < max_ticks:
		var result := advance_to(mini(600, logical_tick + 1))
		if not result.ok:
			return result
		advanced += 1
	if not active_sessions.is_empty():
		return _failure("feedback.drain_bound_exhausted", "反馈在有界逻辑时钟内未完成，已保持活动状态。")
	return {"ok": true, "code": "feedback.drained", "advanced_ticks": advanced, "logical_tick": logical_tick, "logic_unchanged": true, "domain_facts_written": false}

func cancel_feedback(feedback_id: String, reason_code: String = "presentation.cancelled", reason_zh: String = "反馈被取消。") -> Dictionary:
	if not active_sessions.has(feedback_id):
		return _failure("feedback.active_missing", "指定反馈不在活动集合中。")
	var session: Dictionary = active_sessions[feedback_id]
	for backend in backends.values():
		if backend is GMFeedbackBackend:
			backend.clear_feedback(feedback_id)
	var context: GMFeedbackLivePlaybackContext = session.context
	var step: GMFeedbackStep = GMFeedbackLifecycleReducer.current_step(session.state, context.definition)
	if step == null:
		for candidate in context.definition.ordered_steps():
			if not session.state.completed_steps.has(candidate.step_id):
				step = candidate
				break
	if step == null:
		return _failure("feedback.active_step_missing", "活动反馈缺少可取消的当前步骤。")
	var cancelled := _apply_event(session, GMFeedbackLifecycleReducer.event("step_cancelled", step.step_id, logical_tick, GMFeedbackLifecycleReducer.CANONICAL_CODES.step_cancelled, GMFeedbackLifecycleReducer.CANONICAL_REASONS.step_cancelled, {"requested_reason_code": reason_code, "requested_reason_zh": reason_zh}, ""))
	if not cancelled.ok:
		return cancelled
	var terminal := _apply_event(session, GMFeedbackLifecycleReducer.event("session_cancelled", "", logical_tick, GMFeedbackLifecycleReducer.CANONICAL_CODES.session_cancelled, GMFeedbackLifecycleReducer.CANONICAL_REASONS.session_cancelled, {"requested_reason_code": reason_code, "requested_reason_zh": reason_zh}, ""))
	if not terminal.ok:
		return terminal
	_finish_session(session)
	return _success_result(_receipt_from_session(session), "feedback.cancelled")

func cancel_target(target_ref: String, reason_code: String = "presentation.target_unloaded", reason_zh: String = "目标反馈已清理。") -> Dictionary:
	var ids: Array = []
	for feedback_id in active_sessions.keys():
		var session: Dictionary = active_sessions[feedback_id]
		var context: GMFeedbackLivePlaybackContext = session.context
		if context.request.target_ref == target_ref:
			ids.append(str(feedback_id))
	for feedback_id in ids:
		cancel_feedback(feedback_id, reason_code, reason_zh)
	return {"ok": true, "cancelled": ids.size(), "code": reason_code, "logic_unchanged": true, "domain_facts_written": false}

func cancel_all(reason_code: String = "presentation.unload", reason_zh: String = "反馈服务卸载，活动表现已清理。") -> Dictionary:
	var ids := active_sessions.keys().duplicate()
	for feedback_id in ids:
		cancel_feedback(str(feedback_id), reason_code, reason_zh)
	return {"ok": true, "cancelled": ids.size(), "code": reason_code, "logic_unchanged": true, "domain_facts_written": false}

func snapshot() -> Dictionary:
	return {"schema": EPHEMERAL_STATUS_SCHEMA, "logical_tick": logical_tick, "active_count": active_sessions.size(), "completed_count": completed_records.size(), "receipt_count": receipts_by_feedback.size(), "persistence": "none", "authoritative": false, "logic_unchanged": true, "domain_facts_written": false}

func snapshot_json() -> String:
	return JSON.stringify(GMStableData.persistence_canonical(snapshot()), "", true, true)

## All persisted P18 presentation state is retired.  The catalog argument is
## accepted only as a compatibility shape and is never inspected.
func restore(value: Variant, catalog_value: Variant = null, attention_runtime: GMAgentPlannerRuntime = null) -> Dictionary:
	return _migration_required(value)

func restore_json(text: String, catalog_value: Variant = null, attention_runtime: GMAgentPlannerRuntime = null) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return _failure("feedback.snapshot_json_invalid", "反馈快照不是合法JSON对象。")
	return _migration_required(parsed)

## Runtime migration attestation is retired.  Presentation-only state is
## discarded unconditionally; any durable migration audit belongs upstream.
func record_retired_state_discard(_value: Variant, _current_fact_ids: Variant = []) -> Dictionary:
	return _retired_migration_receipt_api()

func clear() -> Dictionary:
	cancel_all("presentation.clear", "反馈服务清理。")
	active_sessions.clear()
	completed_records.clear()
	receipts_by_feedback.clear()
	request_fingerprints.clear()
	return {"ok": true, "code": "feedback.cleared", "logic_unchanged": true, "domain_facts_written": false}

func _new_session(context: GMFeedbackLivePlaybackContext, fingerprint: String) -> Dictionary:
	var state := GMFeedbackLifecycleReducer.initial_state(context.definition, logical_tick)
	var session := {"context": context, "fingerprint": fingerprint, "state": state}
	_sync_session_aliases(session)
	return session

func _advance_session(session: Dictionary, tick: int) -> void:
	var context: GMFeedbackLivePlaybackContext = session.context
	var definition: GMFeedbackSequenceDefinition = context.definition
	var guard := 0
	while guard < definition.steps.size() * 8 + 16:
		guard += 1
		var state: Dictionary = session.state
		if str(state.state) in GMFeedbackLifecycleReducer.TERMINAL_STATES:
			return
		var action := GMFeedbackLifecycleReducer.next_action(state, definition, tick)
		if action.is_empty():
			if GMFeedbackLifecycleReducer.all_steps_completed(state, definition):
				var completed := _apply_event(session, GMFeedbackLifecycleReducer.event("session_completed", "", tick, GMFeedbackLifecycleReducer.CANONICAL_CODES.session_completed, "", {}, ""))
				if completed.ok:
					_finish_session(session)
				return
			if not state.accepted_steps.is_empty() or _has_future_step(state, definition, tick):
				_sync_session_aliases(session)
				return
			var blocked := _apply_event(session, GMFeedbackLifecycleReducer.event("step_blocked", _first_pending_step_id(state, definition), tick, GMFeedbackLifecycleReducer.CANONICAL_CODES.step_blocked, GMFeedbackLifecycleReducer.CANONICAL_REASONS.step_blocked, {"cause_code": "feedback.step_deadlock", "cause_reason_zh": "反馈步骤依赖在有界序列内无法满足。"}, ""))
			if blocked.ok:
				var blocked_terminal := _apply_event(session, GMFeedbackLifecycleReducer.event("session_blocked", "", tick, GMFeedbackLifecycleReducer.CANONICAL_CODES.session_blocked, GMFeedbackLifecycleReducer.CANONICAL_REASONS.session_blocked, {"cause_code": "feedback.step_deadlock"}, ""))
				if blocked_terminal.ok:
					_finish_session(session)
			return
		var step: GMFeedbackStep = action.step
		if action.kind == "complete":
			var complete_result := _apply_event(session, GMFeedbackLifecycleReducer.event("step_completed", step.step_id, tick, GMFeedbackLifecycleReducer.CANONICAL_CODES.step_completed, "", {}, ""))
			if not complete_result.ok:
				return
			continue
		var executed := _execute_step(session, step, tick)
		if executed.ok:
			var accepted_result := _apply_event(session, GMFeedbackLifecycleReducer.event("step_accepted", step.step_id, tick, GMFeedbackLifecycleReducer.CANONICAL_CODES.step_accepted, "", {}, str(executed.get("backend_id", ""))))
			if not accepted_result.ok:
				return
			if step.duration_ticks == 0:
				var immediate := _apply_event(session, GMFeedbackLifecycleReducer.event("step_completed", step.step_id, tick, GMFeedbackLifecycleReducer.CANONICAL_CODES.step_completed, "", {}, ""))
				if not immediate.ok:
					return
			continue
		if bool(executed.get("optional_missing", false)):
			var optional_result := _apply_event(session, GMFeedbackLifecycleReducer.event("step_optional_missing", step.step_id, tick, GMFeedbackLifecycleReducer.CANONICAL_CODES.step_optional_missing, GMFeedbackLifecycleReducer.CANONICAL_REASONS.step_optional_missing, {"cause_code": str(executed.get("code", "feedback.optional_missing")), "cause_reason_zh": str(executed.get("reason_zh", "可选表现内容缺失。"))}, ""))
			if not optional_result.ok:
				return
			continue
		var blocked_result := _apply_event(session, GMFeedbackLifecycleReducer.event("step_blocked", step.step_id, tick, GMFeedbackLifecycleReducer.CANONICAL_CODES.step_blocked, GMFeedbackLifecycleReducer.CANONICAL_REASONS.step_blocked, {"cause_code": str(executed.get("code", "feedback.step_rejected")), "cause_reason_zh": str(executed.get("reason_zh", "表现步骤未能完成。"))}, ""))
		if not blocked_result.ok:
			return
		var terminal_result := _apply_event(session, GMFeedbackLifecycleReducer.event("session_blocked", "", tick, GMFeedbackLifecycleReducer.CANONICAL_CODES.session_blocked, GMFeedbackLifecycleReducer.CANONICAL_REASONS.session_blocked, {"cause_code": str(executed.get("code", "feedback.step_rejected"))}, ""))
		if terminal_result.ok:
			_finish_session(session)
		return
	_sync_session_aliases(session)

func _execute_step(session: Dictionary, step: GMFeedbackStep, tick: int) -> Dictionary:
	var context: GMFeedbackLivePlaybackContext = session.context
	var request: GMFeedbackPresentationRequest = context.request
	if step.step_kind == "semantic_action":
		var presenter: Object = presenters.get(request.target_ref, null)
		if presenter == null or not is_instance_valid(presenter) or not presenter.has_method("play_semantic_action"):
			return _missing_or_required(step, "feedback.presenter_missing", "目标没有可用的P14 Presenter。")
		var result: Variant = presenter.call("play_semantic_action", StringName(step.semantic_action_id), StringName(request.direction))
		if not result is Dictionary or not bool(result.get("ok", false)):
			return {"ok": false, "code": "feedback.presenter_rejected", "reason_zh": "Presenter拒绝了语义动作。", "details": result if result is Dictionary else {}}
		return {"ok": true, "code": "feedback.presenter_accepted"}
	if step.step_kind == "cue":
		if cue_router == null:
			return _missing_or_required(step, "feedback.cue_router_missing", "现有Cue路由器不可用。")
		var parameters := GMCueParameters.new(step.cue_id, null, {"stage": "execute", "source_id": request.source_fact_id, "target_id": request.target_ref, "feedback_id": request.feedback_id, "anchor_id": request.anchor_id, "tags": ["gm.feedback"]})
		var routed := cue_router.route(parameters, not step.optional)
		if not routed.ok:
			return _missing_or_required(step, str(routed.get("code", "feedback.cue_rejected")), str(routed.get("reason_zh", "Cue未能路由。")))
		return {"ok": true, "code": "feedback.cue_routed"}
	if step.step_kind == "noop":
		return {"ok": true, "code": "feedback.noop"}
	var backend: GMFeedbackBackend = backends.get(step.step_kind, null)
	if backend == null:
		backend = backends.get("gm.feedback.backend.%s" % step.step_kind, null)
	if backend == null:
		return _missing_or_required(step, "feedback.backend_missing", "步骤所需表现后端未注册。")
	var backend_result := backend.accept_step(step, request, tick)
	if not backend_result.ok:
		return _missing_or_required(step, str(backend_result.get("code", "feedback.backend_rejected")), str(backend_result.get("reason_zh", "表现后端拒绝了步骤。")))
	return backend_result

func _missing_or_required(step: GMFeedbackStep, code: String, reason_zh: String) -> Dictionary:
	return {"ok": false, "code": code if GMFeedbackValidation.stable_id(code) else "feedback.step_rejected", "reason_zh": reason_zh, "optional_missing": step.optional}

func _apply_event(session: Dictionary, item: Dictionary) -> Dictionary:
	var context: GMFeedbackLivePlaybackContext = session.context
	var applied := GMFeedbackLifecycleReducer.apply_event(session.state, context.definition, item, context.request.source_fact_id)
	if not applied.ok:
		return applied
	session.state = applied.state
	_sync_session_aliases(session)
	return applied

func _finish_session(session: Dictionary) -> void:
	var context: GMFeedbackLivePlaybackContext = session.context
	var request: GMFeedbackPresentationRequest = context.request
	var receipt := _receipt_from_session(session)
	var record := {"fingerprint": session.fingerprint, "receipt": receipt.to_dict()}
	completed_records[request.idempotency_key] = record
	receipts_by_feedback[request.feedback_id] = receipt.to_dict()
	active_sessions.erase(request.feedback_id)

func _result_for_session(session: Dictionary) -> Dictionary:
	var receipt := _receipt_from_session(session)
	if receipt.status == "blocked":
		var blocked_code := str(receipt.blocked_reason.get("code", GMFeedbackLifecycleReducer.CANONICAL_CODES.step_blocked))
		return {"ok": false, "code": blocked_code, "reason_zh": str(receipt.blocked_reason.get("reason_zh", "反馈表现被阻断。")), "receipt": receipt, "logic_unchanged": true, "domain_facts_written": false}
	return _success_result(receipt, "feedback.accepted")

func _success_result(receipt: GMPresentationReceipt, code: String) -> Dictionary:
	return {"ok": true, "code": code, "receipt": receipt, "logic_unchanged": true, "domain_facts_written": false}

func _receipt_from_session(session: Dictionary) -> GMPresentationReceipt:
	var context: GMFeedbackLivePlaybackContext = session.context
	var request: GMFeedbackPresentationRequest = context.request
	var state: Dictionary = session.state
	var receipt := GMPresentationReceipt.new()
	receipt.presentation_receipt_id = "gm.presentation.receipt.%s" % request.feedback_id
	receipt.feedback_id = request.feedback_id
	receipt.idempotency_key = request.idempotency_key
	receipt.source_fact_id = request.source_fact_id
	receipt.commit_package_id = ""
	receipt.sequence_id = request.sequence_id
	receipt.status = str(state.state)
	receipt.current_step_id = str(state.current_step_id) if str(state.state) in GMFeedbackLifecycleReducer.ACTIVE_STATES else ""
	receipt.step_receipts.clear()
	for step_row in state.step_receipts:
		receipt.step_receipts.append(step_row.duplicate(true))
	receipt.blocked_reason = state.blocked_reason.duplicate(true)
	receipt.cancel_reason = str(state.cancel_reason)
	receipt.backend_kinds.clear()
	for backend_id in state.backend_kinds:
		receipt.backend_kinds.append(str(backend_id))
	receipt.started_logical_tick = int(state.started_tick)
	receipt.completed_logical_tick = int(state.completed_tick)
	receipt.optional_missing.clear()
	for missing in state.optional_missing:
		receipt.optional_missing.append(missing.duplicate(true))
	receipt.logic_unchanged = true
	receipt.domain_facts_written = false
	return receipt

func _sync_session_aliases(session: Dictionary) -> void:
	var state: Dictionary = session.state
	session["status"] = state.state
	session["current_step_id"] = state.current_step_id
	session["current_step_index"] = state.current_step_index
	session["started_tick"] = state.started_tick
	session["completed_tick"] = state.completed_tick
	session["completed_steps"] = state.completed_steps
	session["due_ticks"] = state.due_ticks
	session["step_receipts"] = state.step_receipts

func _restore_internal(value: Variant, catalog: GMFeedbackRestoreCatalog, attention_runtime: GMAgentPlannerRuntime, json_boundary: bool) -> Dictionary:
	return _migration_required(value)
	# Historical v2 implementation intentionally unreachable after P18 EXIT.
	var shape := _validate_snapshot_shape(value, json_boundary)
	if not shape.ok:
		return shape
	var snapshot: Dictionary = value
	var staged_active: Dictionary = {}
	var staged_completed: Dictionary = {}
	var staged_bindings: Dictionary = {}
	var staged_fingerprints: Dictionary = {}
	var staged_receipts: Dictionary = {}
	for raw_row in snapshot.active:
		var staged := _stage_row(raw_row, catalog, true, attention_runtime, int(snapshot.logical_tick), json_boundary)
		if not staged.ok:
			return staged
		var session: Dictionary = staged.session
		var descriptor: GMFeedbackRestoreDescriptor = session.descriptor
		var request: GMSemanticFeedbackRequest = descriptor.request
		if staged_active.has(request.feedback_id) or staged_bindings.has(descriptor.binding_id) or staged_fingerprints.has(request.idempotency_key) or staged_completed.has(request.idempotency_key) or staged_receipts.has(request.feedback_id):
			return _failure("feedback.snapshot_duplicate_identity", "反馈快照包含重复的binding、反馈或幂等身份。", {"atomic": true})
		staged_active[request.feedback_id] = session
		staged_bindings[descriptor.binding_id] = true
		staged_fingerprints[request.idempotency_key] = request.fingerprint()
	for raw_row in snapshot.completed:
		var staged := _stage_row(raw_row, catalog, false, attention_runtime, int(snapshot.logical_tick), json_boundary)
		if not staged.ok:
			return staged
		var session: Dictionary = staged.session
		var descriptor: GMFeedbackRestoreDescriptor = session.descriptor
		var request: GMSemanticFeedbackRequest = descriptor.request
		if staged_completed.has(request.idempotency_key) or staged_fingerprints.has(request.idempotency_key) or staged_active.has(request.feedback_id) or staged_bindings.has(descriptor.binding_id) or staged_receipts.has(request.feedback_id):
			return _failure("feedback.snapshot_duplicate_identity", "反馈快照包含重复的binding、反馈或幂等身份。", {"atomic": true})
		var receipt := _receipt_from_session(session)
		staged_completed[request.idempotency_key] = {"fingerprint": request.fingerprint(), "receipt": receipt.to_dict(), "row": raw_row.duplicate(true), "binding_id": descriptor.binding_id}
		staged_bindings[descriptor.binding_id] = true
		staged_fingerprints[request.idempotency_key] = request.fingerprint()
		staged_receipts[request.feedback_id] = receipt.to_dict()
	var expected_receipt_ids: Array[String] = []
	for feedback_id in staged_receipts.keys():
		expected_receipt_ids.append(str(feedback_id))
	expected_receipt_ids.sort()
	var supplied_receipt_ids: Array[String] = []
	for feedback_id in snapshot.receipt_ids:
		supplied_receipt_ids.append(str(feedback_id))
	supplied_receipt_ids.sort()
	if supplied_receipt_ids != expected_receipt_ids:
		return _failure("feedback.snapshot_receipt_index_mismatch", "快照回执索引必须精确覆盖由completed reducer记录产生的反馈身份。", {"atomic": true})
	logical_tick = int(snapshot.logical_tick)
	active_sessions = staged_active
	completed_records = staged_completed
	receipts_by_feedback = staged_receipts
	request_fingerprints = staged_fingerprints
	return {"ok": true, "code": "feedback.snapshot_restored", "active_count": active_sessions.size(), "completed_count": completed_records.size(), "logic_unchanged": true, "domain_facts_written": false}

func _stage_row(raw_row: Variant, catalog: GMFeedbackRestoreCatalog, active: bool, attention_runtime: GMAgentPlannerRuntime, snapshot_tick: int, json_boundary: bool) -> Dictionary:
	return _migration_required(raw_row)
	# Historical journal staging is intentionally unreachable after EXIT.
	if not raw_row is Dictionary:
		return _failure("feedback.snapshot_row_invalid", "反馈快照行必须是Dictionary。")
	var row: Dictionary = raw_row
	var row_check := _validate_row_shape(row, active, json_boundary)
	if not row_check.ok:
		return row_check
	var resolved := catalog.resolve(row.binding_id, str(row.descriptor_digest))
	if not resolved.ok:
		return resolved
	var descriptor: GMFeedbackRestoreDescriptor = resolved.descriptor
	if not descriptor.request.attention_projection.is_empty() and attention_runtime == null:
		return _failure("feedback.restore_descriptor_attention_runtime_missing", "跨实例恢复含Attention的反馈必须提供当前P17 runtime。", {"atomic": true})
	var runtime_check := descriptor.validate_runtime(cue_router, backends, presenters, attention_runtime)
	if not runtime_check.ok:
		return runtime_check
	var replayed := GMFeedbackLifecycleReducer.replay(descriptor.definition, row.transition_journal, snapshot_tick, active, descriptor.request.source_fact_id)
	if not replayed.ok:
		return _failure("feedback.snapshot_lifecycle_unreachable", "快照journal无法由当前trusted definition与shared reducer重放。", replayed)
	var state: Dictionary = replayed.state
	var projection := GMFeedbackLifecycleReducer.projection(state)
	for field in ["state", "current_step_id", "current_step_index", "started_logical_tick", "completed_logical_tick", "due_ticks", "transition_journal", "step_receipts", "optional_missing", "blocked_reason", "cancel_reason", "backend_kinds"]:
		if row.get(field, null) != projection.get(field, null):
			return _failure("feedback.snapshot_reducer_projection_mismatch", "快照序列化字段必须逐值等于shared reducer产物。", {"field": field, "atomic": true})
	var session := {"descriptor": descriptor, "fingerprint": descriptor.request.fingerprint(), "state": state}
	_sync_session_aliases(session)
	return {"ok": true, "code": "feedback.snapshot_row_staged", "session": session}

func _require_catalog(catalog: GMFeedbackRestoreCatalog) -> Dictionary:
	return _retired_restore_api("_require_catalog")

func _migration_required(value: Variant) -> Dictionary:
	var from_schema := str(value.get("schema", "unknown")) if value is Dictionary else "unknown"
	return _failure(MIGRATION_REQUIRED_CODE, "P18表现持久化已退役；旧v1/v2状态必须无条件丢弃，并由上游当前权威重新生成纯值PresentationPlan。", {"from_schema": from_schema, "retired_schemas": [LEGACY_SNAPSHOT_SCHEMA, SNAPSHOT_SCHEMA], "to_schema": EPHEMERAL_STATUS_SCHEMA, "required_api": "upstream_current_authority -> GMSemanticFeedbackMapper.build_presentation_plan_from_fact/build_presentation_plan_from_result -> GMFeedbackPlaybackService.play_plan", "migration": "discard_presentation_only_state_unconditionally", "replayed": false, "atomic": true, "authoritative": false, "persistence": "none", "domain_facts_written": false})

func _validate_snapshot_shape(value: Variant, json_boundary: bool) -> Dictionary:
	if not value is Dictionary or not GMFeedbackValidation.exact(value, SNAPSHOT_FIELDS):
		return _failure("feedback.snapshot_shape_invalid", "反馈快照顶层字段集合必须精确匹配。")
	var snapshot: Dictionary = value
	if str(snapshot.schema) == LEGACY_SNAPSHOT_SCHEMA:
		return _migration_required(snapshot)
	if str(snapshot.schema) != SNAPSHOT_SCHEMA or not GMFeedbackValidation.bounded_integer(snapshot.logical_tick, 0, 600, json_boundary) or not snapshot.active is Array or not snapshot.completed is Array or not snapshot.receipt_ids is Array or snapshot.active.size() > MAX_ACTIVE or snapshot.completed.size() > MAX_ACTIVE or snapshot.backend_independent != true:
		return _failure("feedback.snapshot_header_invalid", "反馈快照Schema、逻辑时钟、数量或后端独立标志无效。")
	var seen_receipts := {}
	for feedback_id in snapshot.receipt_ids:
		if not GMFeedbackValidation.stable_id(feedback_id) or seen_receipts.has(str(feedback_id)):
			return _failure("feedback.snapshot_receipt_ids_invalid", "反馈快照回执索引必须是唯一稳定ID。")
		seen_receipts[str(feedback_id)] = true
	for row in snapshot.active:
		var active_check := _validate_row_shape(row, true, json_boundary)
		if not active_check.ok:
			return active_check
	for row in snapshot.completed:
		var completed_check := _validate_row_shape(row, false, json_boundary)
		if not completed_check.ok:
			return completed_check
	var maximum_tick := int(snapshot.logical_tick)
	for collection in [snapshot.active, snapshot.completed]:
		for row in collection:
			maximum_tick = maxi(maximum_tick, int(row.started_logical_tick))
			maximum_tick = maxi(maximum_tick, int(row.completed_logical_tick))
			for event_item in row.transition_journal:
				maximum_tick = maxi(maximum_tick, int(event_item.logical_tick))
	if maximum_tick > int(snapshot.logical_tick):
		return _failure("feedback.snapshot_tick_regression", "快照逻辑时钟不能早于其中的reducer事件时钟。")
	return {"ok": true, "code": "feedback.snapshot_shape_valid"}

func _validate_row_shape(value: Variant, active: bool, json_boundary: bool) -> Dictionary:
	if not value is Dictionary or not GMFeedbackValidation.exact(value, ROW_FIELDS):
		return _failure("feedback.snapshot_row_shape_invalid", "v2反馈快照行只能包含trusted binding引用与reducer投影。")
	var row: Dictionary = value
	if not GMFeedbackValidation.stable_id(row.binding_id) or not GMFeedbackValidation.is_digest(row.descriptor_digest):
		return _failure("feedback.snapshot_row_binding_invalid", "反馈快照行的binding或descriptor摘要无效。")
	var states := GMFeedbackLifecycleReducer.ACTIVE_STATES + GMFeedbackLifecycleReducer.TERMINAL_STATES
	if row.state not in states or (active and row.state not in GMFeedbackLifecycleReducer.ACTIVE_STATES) or (not active and row.state not in GMFeedbackLifecycleReducer.TERMINAL_STATES):
		return _failure("feedback.snapshot_row_state_invalid", "反馈快照行状态与active/completed集合不一致。")
	if not GMFeedbackValidation.stable_id(row.current_step_id, true) or not GMFeedbackValidation.bounded_integer(row.current_step_index, 0, 32, json_boundary) or not GMFeedbackValidation.bounded_integer(row.started_logical_tick, 0, 600, json_boundary) or not GMFeedbackValidation.bounded_integer(row.completed_logical_tick, 0, 600, json_boundary):
		return _failure("feedback.snapshot_row_projection_invalid", "反馈快照行current或生命周期时钟字段无效。")
	if not row.due_ticks is Dictionary or not row.transition_journal is Array or not row.step_receipts is Array or not row.optional_missing is Array or not row.blocked_reason is Dictionary or not GMFeedbackValidation.stable_id(row.cancel_reason, true) or not row.backend_kinds is Array:
		return _failure("feedback.snapshot_row_projection_invalid", "反馈快照行缺少严格reducer投影字段。")
	for step_id in row.due_ticks.keys():
		if not GMFeedbackValidation.stable_id(step_id) or not GMFeedbackValidation.bounded_integer(row.due_ticks[step_id], 0, 600, json_boundary):
			return _failure("feedback.snapshot_due_invalid", "due_ticks必须是稳定步骤ID到有界整数的映射。")
	var seen_backends := {}
	for backend_id in row.backend_kinds:
		if not GMFeedbackValidation.stable_id(backend_id) or seen_backends.has(str(backend_id)):
			return _failure("feedback.snapshot_backend_invalid", "reducer后端集合必须包含稳定且唯一的ID。")
		seen_backends[str(backend_id)] = true
	var seen_steps := {}
	for step_row in row.step_receipts:
		if not step_row is Dictionary or not GMFeedbackValidation.exact(step_row, ["step_id", "step_kind", "status", "logical_tick", "code", "optional"]):
			return _failure("feedback.snapshot_step_invalid", "reducer步骤回执字段集合无效。")
		if not GMFeedbackValidation.stable_id(step_row.step_id) or step_row.step_kind not in GMFeedbackStep.KINDS or step_row.status not in GMPresentationReceipt.STEP_STATUSES or not GMFeedbackValidation.bounded_integer(step_row.logical_tick, 0, 600, json_boundary) or not GMFeedbackValidation.stable_id(step_row.code) or typeof(step_row.optional) != TYPE_BOOL or seen_steps.has(str(step_row.step_id)):
			return _failure("feedback.snapshot_step_invalid", "reducer步骤回执身份、状态、时钟或唯一性无效。")
		seen_steps[str(step_row.step_id)] = true
	for missing in row.optional_missing:
		if not missing is Dictionary or not GMFeedbackValidation.exact(missing, ["step_id", "code", "reason_zh"]) or not GMFeedbackValidation.stable_id(missing.step_id) or not GMFeedbackValidation.stable_id(missing.code) or str(missing.reason_zh).strip_edges().is_empty():
			return _failure("feedback.snapshot_optional_missing_invalid", "optional_missing索引字段无效。")
	if row.state == "blocked" and GMFeedbackBlockedReason.from_dict(row.blocked_reason) == null:
		return _failure("feedback.snapshot_blocked_reason_invalid", "blocked终态缺少有效结构化原因。")
	if row.state != "blocked" and not row.blocked_reason.is_empty():
		return _failure("feedback.snapshot_blocked_reason_unexpected", "非blocked终态不能携带blocked reason。")
	if row.state == "cancelled" and str(row.cancel_reason).is_empty():
		return _failure("feedback.snapshot_cancel_reason_missing", "cancelled终态必须带canonical取消原因。")
	if row.state != "cancelled" and not str(row.cancel_reason).is_empty():
		return _failure("feedback.snapshot_cancel_reason_unexpected", "非cancelled终态不能携带取消原因。")
	if active and int(row.completed_logical_tick) != 0:
		return _failure("feedback.snapshot_active_completion_invalid", "活动reducer状态不得带terminal tick。")
	if not active and int(row.completed_logical_tick) < int(row.started_logical_tick):
		return _failure("feedback.snapshot_completion_order_invalid", "终态完成时钟不得早于启动时钟。")
	for raw_event in row.transition_journal:
		var event_check := GMFeedbackLifecycleReducer.validate_event(raw_event, json_boundary)
		if not event_check.ok:
			return event_check
	return {"ok": true, "code": "feedback.snapshot_row_shape_valid"}

func _normalize_json(value: Dictionary) -> Dictionary:
	var copy: Dictionary = value.duplicate(true)
	var top := _normalize_integer(copy, "logical_tick")
	if not top.ok:
		return top
	for collection_name in ["active", "completed"]:
		for index in copy[collection_name].size():
			var row: Dictionary = copy[collection_name][index]
			for key in ["current_step_index", "started_logical_tick", "completed_logical_tick"]:
				var checked := _normalize_integer(row, key)
				if not checked.ok:
					return checked
			for step_id in row.due_ticks.keys():
				var due_check := _normalize_integer(row.due_ticks, step_id)
				if not due_check.ok:
					return due_check
			for event_index in row.transition_journal.size():
				var event_check := _normalize_integer(row.transition_journal[event_index], "logical_tick")
				if not event_check.ok:
					return event_check
			for step_index in row.step_receipts.size():
				var step_check := _normalize_integer(row.step_receipts[step_index], "logical_tick")
				if not step_check.ok:
					return step_check
			copy[collection_name][index] = row
	return {"ok": true, "value": copy}

func _normalize_integer(owner: Dictionary, key: Variant) -> Dictionary:
	if not owner.has(key) or typeof(owner[key]) != TYPE_FLOAT or not is_finite(float(owner[key])) or owner[key] != floor(owner[key]) or abs(float(owner[key])) > GMFeedbackValidation.MAX_SAFE_INT:
		return _failure("feedback.snapshot_json_integer_invalid", "JSON边界整数必须是有限安全整数。", {"field": str(key)})
	owner[key] = int(owner[key])
	return {"ok": true, "code": "feedback.snapshot_json_integer_valid"}

func _has_future_step(state: Dictionary, definition: GMFeedbackSequenceDefinition, tick: int) -> bool:
	for step in definition.ordered_steps():
		if not state.completed_steps.has(step.step_id) and not state.accepted_steps.has(step.step_id) and step.logical_order > tick:
			return true
	return false

func _first_pending_step_id(state: Dictionary, definition: GMFeedbackSequenceDefinition) -> String:
	for step in definition.ordered_steps():
		if not state.completed_steps.has(step.step_id) and not state.accepted_steps.has(step.step_id):
			return step.step_id
	return ""

func _blocked_result(request: GMFeedbackPresentationRequest, code: String, reason_zh: String, details: Dictionary) -> Dictionary:
	var reason := GMFeedbackBlockedReason.new(code, reason_zh, str(details.get("action", "检查反馈配置后重试。")), "presentation", false, request.source_fact_id, details)
	var receipt := GMPresentationReceipt.new()
	receipt.presentation_receipt_id = "gm.presentation.blocked.%s" % request.feedback_id
	receipt.feedback_id = request.feedback_id
	receipt.idempotency_key = request.idempotency_key
	receipt.source_fact_id = request.source_fact_id
	receipt.commit_package_id = ""
	receipt.sequence_id = request.sequence_id
	receipt.status = "blocked"
	receipt.blocked_reason = reason.to_dict()
	receipt.logic_unchanged = true
	receipt.domain_facts_written = false
	return {"ok": false, "code": code, "reason_zh": reason_zh, "receipt": receipt, "logic_unchanged": true, "domain_facts_written": false}

static func _row_before(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("binding_id", "")) != str(b.get("binding_id", "")):
		return str(a.get("binding_id", "")) < str(b.get("binding_id", ""))
	return str(a.get("descriptor_digest", "")) < str(b.get("descriptor_digest", ""))

func snapshot_tick_for_restore(row: Dictionary) -> int:
	var maximum := int(row.get("started_logical_tick", 0))
	for event_item in row.get("transition_journal", []):
		maximum = maxi(maximum, int(event_item.get("logical_tick", 0)))
	return maximum

func _retired_presentation_api(api_name: String) -> Dictionary:
	return _failure(PRESENTATION_PLAN_REQUIRED_CODE, "P18只接受纯值PresentationPlan；reader-bound mapper、直接request与authority capability入口已退役。", {"api": api_name, "required_api": "upstream_current_authority -> GMSemanticFeedbackMapper.build_presentation_plan_from_fact/build_presentation_plan_from_result -> GMFeedbackPlaybackService.play_plan", "authoritative": false, "persistence": "none", "domain_facts_written": false})

func _retired_migration_receipt_api() -> Dictionary:
	return _failure(MIGRATION_RECEIPT_RETIRED_CODE, "P18运行时migration receipt已退役；Presentation-only丢弃不在P18生成逐实例attestation。", {"retired_schema": "gm.feedback.presentation_migration_receipt.v1", "required_owner": "upstream_save_or_migration_owner", "replayed": false, "authoritative": false, "persistence": "none", "domain_facts_written": false})

func _retired_restore_api(api_name: String) -> Dictionary:
	return _failure(RETIRED_RESTORE_CODE, "P18 descriptor/catalog/journal restore API已退役，不能用于live播放或状态持久化；请由上游当前权威重建纯值PresentationPlan。", {"api": api_name, "required_api": "upstream_current_authority -> GMSemanticFeedbackMapper.build_presentation_plan_from_fact/build_presentation_plan_from_result -> GMFeedbackPlaybackService.play_plan", "migration": "discard_presentation_only_state_unconditionally", "replayed": false, "authoritative": false, "persistence": "none", "logic_unchanged": true, "domain_facts_written": false})

func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
