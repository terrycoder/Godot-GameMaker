class_name GMAbilityTaskWaitEvent
extends GMAbilityTask

var event_tag: String = ""
var include_children: bool = true

func _init(p_event_tag: String = "", p_task_id: String = "", p_include_children: bool = true) -> void:
	event_tag = GMGameplayTag.normalize(p_event_tag)
	include_children = p_include_children
	super._init(p_task_id, {"event_tag": event_tag})

func _start() -> Variant:
	if event_tag.is_empty():
		return fail("task.event_tag_missing", "等待事件任务缺少稳定事件 ID。")
	return _pending("task.waiting_event", "正在等待 Gameplay Event：%s" % event_tag, {"event_tag": event_tag})

func handle_event(event: GMGameplayEvent) -> GMAbilityTaskResult:
	if released or is_terminal():
		return _rejected("task.callback_rejected", "任务结束后不得接收 Gameplay Event。")
	if event == null:
		return _pending("task.event_ignored", "忽略空 Gameplay Event。")
	var incoming := GMGameplayTag.normalize(event.event_tag)
	var matched := incoming == event_tag or (include_children and incoming.begins_with(event_tag + "."))
	if not matched:
		return _pending("task.event_ignored", "事件标签不匹配。", {"expected": event_tag, "actual": incoming})
	return complete({"event": event.to_dict(), "event_tag": incoming})

