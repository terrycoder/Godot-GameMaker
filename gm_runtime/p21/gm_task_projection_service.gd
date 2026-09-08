class_name GMTaskProjectionService
extends RefCounted

## The service exposes only reads from the P16 service. There is deliberately
## no submit/transition/complete/write method on the projection surface.

var task_service: GMTaskService

func _init(p_task_service: GMTaskService = null) -> void:
	task_service = p_task_service

func build(task_id: String) -> Dictionary:
	if task_service == null:
		return GMP21Contract.failure("task.projection_service_missing", "TaskProjectionService未安装P16 TaskService。")
	if not GMP21Contract.stable_id(task_id):
		return GMP21Contract.failure("task.projection_task_id_invalid", "TaskProjection需要稳定Task ID。")
	var task := task_service.read_task(task_id)
	if task.is_empty():
		return GMP21Contract.failure("task.missing", "P16 Task不存在。", {"task_id": task_id})
	var domain := task_service.domain_snapshot()
	var definitions: Variant = domain.get("definitions", {})
	if not definitions is Dictionary: return GMP21Contract.failure("task.projection_source_invalid", "P16 Definition集合无效。")
	var definition: Dictionary = definitions.get(str(task.get("definition_id", "")), {})
	var revision := task_service.version_for("domain")
	return GMTaskProjection.from_authority(task, definition, revision)

func list() -> Array[GMTaskProjection]:
	var result: Array[GMTaskProjection] = []
	if task_service == null: return result
	var domain := task_service.domain_snapshot()
	var tasks: Variant = domain.get("tasks", {})
	if not tasks is Dictionary: return result
	var ids: Array[String] = []
	for task_id in tasks.keys(): ids.append(str(task_id))
	ids.sort()
	for task_id in ids:
		var built := build(task_id)
		if built.ok and built.projection != null: result.append(built.projection)
	return result

