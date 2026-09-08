class_name GMFeedbackBackend
extends RefCounted

## Presentation-only backend interface.  It receives bounded semantic steps and
## cannot return a domain result or mutate the Fact/Task/Reservation stores.

var backend_id := "gm.feedback.backend.base"
var accepted_steps: Array[Dictionary] = []

func _init(p_backend_id: String = "gm.feedback.backend.base") -> void:
	backend_id = p_backend_id

func accept_step(_step: GMFeedbackStep, _request: GMFeedbackPresentationRequest, _logical_tick: int) -> Dictionary:
	return {"ok": false, "code": "feedback.backend_not_implemented", "reason_zh": "表现后端没有实现语义步骤接收。"}

func clear_feedback(feedback_id: String) -> Dictionary:
	var kept: Array[Dictionary] = []
	for row in accepted_steps:
		if str(row.get("feedback_id", "")) != feedback_id:
			kept.append(row)
	accepted_steps = kept
	return {"ok": true, "code": "feedback.backend_cleared", "backend_id": backend_id}

func snapshot() -> Dictionary:
	return {"backend_id": backend_id, "accepted_count": accepted_steps.size()}
