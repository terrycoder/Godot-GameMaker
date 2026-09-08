class_name GMAbilityTaskPlaySemanticAnimation
extends GMAbilityTask

var semantic_id: String = ""
var animation_executor: Object
var command_key: String = ""

func _init(p_semantic_id: String = "", p_executor: Object = null, p_task_id: String = "") -> void:
	semantic_id = p_semantic_id
	animation_executor = p_executor
	super._init(p_task_id, {"semantic_animation": semantic_id})

func _start() -> Variant:
	if semantic_id.is_empty(): return fail("task.animation_id_missing", "语义动画任务缺少稳定动画 ID。")
	if animation_executor == null or not is_instance_valid(animation_executor): return fail("task.animation_executor_missing", "语义动画任务缺少表现执行器。")
	if not animation_executor.has_method("play_semantic_animation"):
		return fail("task.animation_executor_invalid", "表现执行器未提供 play_semantic_animation 接口。")
	var played = animation_executor.play_semantic_animation(semantic_id, task_context)
	if played is Dictionary:
		if not played.get("ok", true): return fail(str(played.get("code", "task.animation_failed")), str(played.get("reason_zh", "语义动画播放失败。")), played)
		command_key = str(played.get("command_id", played.get("id", "")))
		if played.get("completed", false): return complete(played)
	return _pending("task.playing_animation", "正在播放语义动画：%s" % semantic_id, {"command_id": command_key})
	return complete({"animation": semantic_id, "result": played})

func _tick(_delta: float) -> Variant:
	if animation_executor == null or not is_instance_valid(animation_executor): return fail("task.animation_executor_released", "语义动画执行器已释放。")
	if animation_executor.has_method("is_animation_complete") and animation_executor.is_animation_complete(command_key, semantic_id): return complete({"animation": semantic_id, "command_id": command_key})
	if animation_executor.has_method("poll_semantic_animation"):
		var polled = animation_executor.poll_semantic_animation(command_key, semantic_id, task_context)
		if polled is Dictionary:
			if polled.get("failed", false): return fail(str(polled.get("code", "task.animation_failed")), str(polled.get("reason_zh", "语义动画失败。")), polled)
			if polled.get("completed", false): return complete(polled)
	return _pending("task.playing_animation", "正在播放语义动画：%s" % semantic_id, {"command_id": command_key})

func cancel(reason_zh: String = "语义动画任务已取消。", data: Dictionary = {}) -> GMAbilityTaskResult:
	if animation_executor != null and is_instance_valid(animation_executor) and animation_executor.has_method("cancel_semantic_animation"):
		animation_executor.cancel_semantic_animation(command_key, semantic_id, reason_zh)
	return super.cancel(reason_zh, data)

