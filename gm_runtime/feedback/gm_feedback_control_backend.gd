class_name GMFeedbackControlBackend
extends GMFeedbackBackend

var root_control: Control
var output_label: Label

func _init(p_root_control: Control = null, p_backend_id: String = "gm.feedback.backend.controls") -> void:
	super._init(p_backend_id)
	root_control = p_root_control
	if root_control != null:
		output_label = root_control.get_node_or_null("反馈内容") as Label

func attach(p_root_control: Control) -> void:
	root_control = p_root_control
	output_label = root_control.get_node_or_null("反馈内容") as Label if root_control != null else null

func accept_step(step: GMFeedbackStep, request: GMFeedbackPresentationRequest, logical_tick: int) -> Dictionary:
	if step == null or request == null or root_control == null:
		return {"ok": false, "code": "feedback.controls_unavailable", "reason_zh": "中文反馈控件尚未准备好。"}
	if output_label == null:
		output_label = root_control.find_child("反馈内容", true, false) as Label
	if step.step_kind in ["text", "attention"] and output_label != null:
		output_label.text = step.text_zh if not step.text_zh.is_empty() else ("已接收语义步骤：%s" % step.step_kind)
	if step.step_kind == "icon" and output_label != null:
		output_label.text = "图标占位：%s" % step.content_id
	if step.step_kind in ["audio", "vfx"] and output_label != null:
		output_label.text = "表现占位：%s" % step.step_kind
	accepted_steps.append({"feedback_id": request.feedback_id, "step_id": step.step_id, "step_kind": step.step_kind, "logical_tick": logical_tick, "content_id": step.content_id})
	return {"ok": true, "code": "feedback.controls_step_accepted", "backend_id": backend_id, "step_id": step.step_id}
