class_name GMAbilityTaskSelectTarget
extends GMAbilityTask

var selector: Object
var selected_target: GMTargetData

func _init(p_selector: Object = null, p_task_id: String = "") -> void:
	selector = p_selector
	super._init(p_task_id, {})

func _start() -> Variant:
	if selector == null or not is_instance_valid(selector): return fail("task.target_selector_missing", "选择目标任务缺少目标选择器。")
	if not selector.has_method("select_target"): return fail("task.target_selector_invalid", "目标选择器未提供 select_target 接口。")
	var selected = selector.select_target(task_context)
	return _consume_selection(selected)

func _tick(_delta: float) -> Variant:
	if selected_target != null: return complete({"target_data": selected_target.to_dict()})
	if selector == null or not is_instance_valid(selector): return fail("task.target_selector_released", "选择目标期间目标选择器已释放。")
	if selector.has_method("poll_selected_target"):
		return _consume_selection(selector.poll_selected_target(task_context))
	return _pending("task.waiting_target", "正在等待目标选择。")

func _consume_selection(selected: Variant) -> Variant:
	if selected is GMTargetData:
		selected_target = selected
		return complete({"target_data": selected.to_dict()})
	if selected is Dictionary:
		if not selected.get("ok", true): return fail(str(selected.get("code", "task.target_selection_failed")), str(selected.get("reason_zh", "目标选择失败。")), selected)
		if selected.has("target_data") and selected.target_data is GMTargetData:
			selected_target = selected.target_data
			return complete({"target_data": selected_target.to_dict()})
		if selected.get("completed", false): return complete(selected)
	return _pending("task.waiting_target", "正在等待目标选择。", {"selection": selected})

