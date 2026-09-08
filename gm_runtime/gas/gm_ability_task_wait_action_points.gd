class_name GMAbilityTaskWaitActionPoints
extends GMAbilityTaskWait

func _init(p_points: Variant = 1, p_task_id: Variant = "") -> void:
	super._init(float(p_points), p_task_id, "action_points")

