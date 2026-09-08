class_name GMAbilityTaskWait
extends GMAbilityTask

## 逻辑等待：实时使用秒，回合使用回合；能力定义无需复制一份。

var amount: float = 0.0
var wait_unit: String = "auto"
var wait_description: Dictionary = {}

func _init(p_amount: Variant = 0.0, p_task_id: Variant = "", p_unit: String = "auto") -> void:
	var actual_amount: Variant = p_amount
	var actual_id: Variant = p_task_id
	if p_amount is String:
		actual_id = p_amount
		actual_amount = p_task_id
	amount = maxf(float(actual_amount), 0.0)
	wait_unit = p_unit
	super._init(str(actual_id), {"amount": amount, "unit": wait_unit})

func _start() -> Variant:
	if scheduler == null:
		return fail("task.scheduler_missing", "等待任务缺少 GMAbilityScheduler。")
	wait_description = scheduler.describe_wait(wait_unit, amount)
	if not wait_description.ok:
		return fail("task.scheduler_unit_unsupported", str(wait_description.reason_zh), wait_description)
	if amount <= 0.0:
		return complete({"wait_unit": wait_description.unit, "amount": amount})
	return _pending("task.waiting", "正在等待%s。" % _unit_label(str(wait_description.unit)), wait_description)

func _tick(_delta: float) -> Variant:
	if scheduler == null:
		return fail("task.scheduler_missing", "等待任务缺少 GMAbilityScheduler。")
	var progress := scheduler.progress_since(wait_description)
	if progress >= amount:
		return complete({"wait_unit": wait_description.unit, "amount": amount, "progress": progress})
	return _pending("task.waiting", "正在等待%s。" % _unit_label(str(wait_description.unit)), {"progress": progress, "remaining": amount - progress, "wait_unit": wait_description.unit})

func _unit_label(unit: String) -> String:
	match unit:
		"seconds": return "游戏时间"
		"turns": return "回合"
		"action_points": return "行动点"
		"physics_frames": return "物理帧"
		_: return "调度器"
