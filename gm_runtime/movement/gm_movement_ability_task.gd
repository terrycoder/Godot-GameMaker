class_name GMMovementAbilityTask
extends GMAbilityTask

var _movement_request_data: Dictionary = {}
var movement_request: GMMovementRequest:
	get:
		var parsed := GMMovementRequest.from_dict(_movement_request_data.duplicate(true))
		return parsed.request if parsed.ok else null
## The P15 task is shared by Planar 2D and Planar 3D services.
var executor: Object
var actor: Object
var command_id: String = ""

func _init(request: GMMovementRequest = null, service: Object = null, movement_actor: Object = null, p_task_id: String = "") -> void:
	_movement_request_data = request.to_dict().duplicate(true) if request != null else {}
	executor = service; actor = movement_actor
	super._init(p_task_id if not p_task_id.is_empty() else "gm.task.movement", {"movement_request": _movement_request_data.duplicate(true)})

func _start() -> Variant:
	if _movement_request_data.is_empty() or executor == null or actor == null: return fail("movement.task_context_missing", "移动AbilityTask缺少请求、执行器或角色。")
	var parsed := GMMovementRequest.from_dict(_movement_request_data.duplicate(true))
	if not parsed.ok: return fail(str(parsed.get("code", "movement.request_invalid")), str(parsed.get("reason_zh", "移动请求无效。")), parsed)
	var started: Variant = executor.call("start_request", parsed.request, actor)
	if not started.ok: return fail(str(started.get("code", "movement.start_failed")), str(started.get("reason_zh", "移动启动失败。")), started)
	command_id = str(started.get("command_id", ""))
	if started.get("completed", false): return complete(started)
	return _pending("movement.running", "移动AbilityTask正在执行。", started)

func _tick(delta: float) -> Variant:
	var result: Variant = executor.call("tick_command", command_id, delta)
	if not result.ok: return fail(str(result.get("code", "movement.failed")), str(result.get("reason_zh", "移动执行失败。")), result)
	if result.get("completed", false): return complete(result)
	return _pending("movement.running", "移动AbilityTask正在执行。", result)

func cancel(reason_zh: String = "移动任务已取消。", data: Dictionary = {}) -> GMAbilityTaskResult:
	if executor != null and not command_id.is_empty(): executor.cancel_move(command_id, reason_zh)
	return super.cancel(reason_zh, data)
