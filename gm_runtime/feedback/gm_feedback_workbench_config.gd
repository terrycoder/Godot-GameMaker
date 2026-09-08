@tool
class_name GMFeedbackWorkbenchConfig
extends Resource

const SCHEMA_VERSION := "gm.feedback.workbench.v1"
const FIELDS := ["schema_version", "sequence_id", "semantic_action_id", "target_ref", "direction", "anchor_id", "required_content_id", "display_name_zh"]
const DIRECTIONS := ["down", "left", "right", "up", "down_left", "down_right", "up_left", "up_right"]

@export var sequence_id := "gm.feedback.sequence.neutral_demo"
@export var semantic_action_id := "idle"
@export var target_ref := "gm.actor.neutral_demo"
@export_enum("下:down", "左:left", "右:right", "上:up", "左下:down_left", "右下:down_right", "左上:up_left", "右上:up_right") var direction := "down"
@export var anchor_id := ""
@export var required_content_id := "gm.content.feedback.accepted"
@export var display_name_zh := "中性语义反馈样例"

func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "sequence_id": sequence_id, "semantic_action_id": semantic_action_id, "target_ref": target_ref, "direction": direction, "anchor_id": anchor_id, "required_content_id": required_content_id, "display_name_zh": display_name_zh}

func validate() -> Dictionary:
	var row := to_dict()
	if not GMFeedbackValidation.exact(row, FIELDS):
		return {"ok": false, "code": "feedback.workbench.shape_invalid", "reason_zh": "P18工作台配置字段集合无效。"}
	for key in ["sequence_id", "semantic_action_id", "target_ref", "required_content_id"]:
		if not GMFeedbackValidation.stable_id(row[key]):
			return {"ok": false, "code": "feedback.workbench.identity_invalid", "reason_zh": "工作台配置只能使用稳定英文ID。", "field": key}
	if anchor_id != "" and not GMFeedbackValidation.stable_id(anchor_id):
		return {"ok": false, "code": "feedback.workbench.anchor_invalid", "reason_zh": "锚点必须是稳定ID或空值。"}
	if direction not in DIRECTIONS or display_name_zh.strip_edges().is_empty():
		return {"ok": false, "code": "feedback.workbench.value_invalid", "reason_zh": "工作台方向或中文名称无效。"}
	return {"ok": true, "code": "feedback.workbench.valid"}

func preview_apply(value: Variant) -> Dictionary:
	if not value is Dictionary or not GMFeedbackValidation.exact(value, FIELDS):
		return {"ok": false, "code": "feedback.workbench.input_invalid", "reason_zh": "待应用配置字段必须精确匹配。"}
	var candidate := GMFeedbackWorkbenchConfig.new()
	var applied := candidate._apply_unchecked(value)
	if not applied.ok:
		return applied
	return {"ok": true, "code": "feedback.workbench.preflight_valid", "value": candidate.to_dict()}

func apply_dict(value: Variant) -> Dictionary:
	var before := to_dict()
	var checked := preview_apply(value)
	if not checked.ok:
		return checked
	var applied := _apply_unchecked(checked.value)
	if not applied.ok:
		_apply_unchecked(before)
		return applied
	return {"ok": true, "code": "feedback.workbench.applied"}

func _apply_unchecked(value: Dictionary) -> Dictionary:
	if str(value.get("schema_version", "")) != SCHEMA_VERSION:
		return {"ok": false, "code": "feedback.workbench.schema_invalid", "reason_zh": "工作台配置Schema不匹配。"}
	sequence_id = str(value.sequence_id)
	semantic_action_id = str(value.semantic_action_id)
	target_ref = str(value.target_ref)
	direction = str(value.direction)
	anchor_id = str(value.anchor_id)
	required_content_id = str(value.required_content_id)
	display_name_zh = str(value.display_name_zh)
	var checked := validate()
	if not checked.ok:
		return checked
	return {"ok": true, "code": "feedback.workbench.unchecked_applied"}

