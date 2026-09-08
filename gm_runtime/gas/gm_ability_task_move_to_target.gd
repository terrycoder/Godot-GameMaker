class_name GMAbilityTaskMoveToTarget
extends GMAbilityTask

var target_data: GMTargetData
var movement_executor: Object
var command_key: String = ""

func _init(p_target_data: GMTargetData = null, p_executor: Object = null, p_task_id: String = "") -> void:
	target_data = p_target_data
	movement_executor = p_executor
	super._init(p_task_id, {"target_data": target_data.to_dict() if target_data != null else {}})

func _start() -> Variant:
	var target_check := target_data.validate() if target_data != null else {"ok": false, "code": "target.missing", "reason_zh": "移动任务缺少目标。"}
	if not target_check.ok:
		return fail(str(target_check.code), str(target_check.reason_zh), target_check)
	if movement_executor == null or not is_instance_valid(movement_executor):
		return fail("task.movement_executor_missing", "移动任务缺少领域移动执行器。")
	if movement_executor.has_method("start_move_to_target"):
		var started = movement_executor.start_move_to_target(target_data, task_context)
		if started is Dictionary:
			if not started.get("ok", true): return fail(str(started.get("code", "task.move_start_failed")), str(started.get("reason_zh", "移动启动失败。")), started)
			command_key = str(started.get("command_id", started.get("id", "")))
			if started.get("completed", false): return complete(started)
		return _pending("task.moving", "正在移动到目标。", {"command_id": command_key, "target": target_data.to_dict()})
	if movement_executor.has_method("move_to_target"):
		var direct = movement_executor.move_to_target(target_data, task_context)
		if direct is Dictionary and not direct.get("ok", true): return fail(str(direct.get("code", "task.move_failed")), str(direct.get("reason_zh", "移动失败。")), direct)
		return complete({"target": target_data.to_dict(), "command": direct})
	return fail("task.movement_executor_invalid", "移动执行器未提供 start_move_to_target 或 move_to_target。")

func _tick(_delta: float) -> Variant:
	var target_check := target_data.validate() if target_data != null else {"ok": false, "code": "target.missing", "reason_zh": "移动任务目标为空。"}
	if not target_check.ok: return fail("target.released", "移动目标已释放，能力无法继续。", target_check)
	if movement_executor == null or not is_instance_valid(movement_executor): return fail("task.movement_executor_released", "移动执行器已释放。")
	if movement_executor.has_method("is_move_complete") and movement_executor.is_move_complete(command_key, target_data):
		return complete({"command_id": command_key, "target": target_data.to_dict()})
	if movement_executor.has_method("poll_move"):
		var polled = movement_executor.poll_move(command_key, target_data, task_context)
		if polled is Dictionary:
			if polled.get("failed", false): return fail(str(polled.get("code", "task.move_failed")), str(polled.get("reason_zh", "移动失败。")), polled)
			if polled.get("completed", false): return complete(polled)
	return _pending("task.moving", "正在移动到目标。", {"command_id": command_key})

func cancel(reason_zh: String = "移动任务已取消。", data: Dictionary = {}) -> GMAbilityTaskResult:
	if movement_executor != null and is_instance_valid(movement_executor) and movement_executor.has_method("cancel_move"):
		movement_executor.cancel_move(command_key, reason_zh)
	return super.cancel(reason_zh, data)

