class_name GMAbilityTaskWaitTurn
extends GMAbilityTaskWait

func _init(p_turns: Variant = 1, p_task_id: Variant = "") -> void:
	super._init(float(p_turns), p_task_id, "turns")

