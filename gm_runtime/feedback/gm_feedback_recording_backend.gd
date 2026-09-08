class_name GMFeedbackRecordingBackend
extends GMFeedbackBackend

var fail_required_kinds: Dictionary = {}
var fail_optional_kinds: Dictionary = {}

func _init(p_backend_id: String = "gm.feedback.backend.recording") -> void:
	super._init(p_backend_id)

func configure_failure(required_kinds: Array = [], optional_kinds: Array = []) -> void:
	fail_required_kinds.clear()
	fail_optional_kinds.clear()
	for kind in required_kinds:
		fail_required_kinds[str(kind)] = true
	for kind in optional_kinds:
		fail_optional_kinds[str(kind)] = true

func accept_step(step: GMFeedbackStep, request: GMFeedbackPresentationRequest, logical_tick: int) -> Dictionary:
	if step == null or request == null:
		return {"ok": false, "code": "feedback.backend_input_invalid", "reason_zh": "表现后端收到空步骤或空请求。"}
	if fail_required_kinds.has(step.step_kind) or fail_optional_kinds.has(step.step_kind):
		return {"ok": false, "code": "feedback.backend_injected_failure", "reason_zh": "表现后端拒绝当前步骤。", "backend_id": backend_id, "step_kind": step.step_kind}
	accepted_steps.append({"feedback_id": request.feedback_id, "step_id": step.step_id, "step_kind": step.step_kind, "logical_tick": logical_tick, "content_id": step.content_id})
	return {"ok": true, "code": "feedback.backend_step_accepted", "backend_id": backend_id, "step_id": step.step_id}
