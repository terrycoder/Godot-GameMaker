class_name GMAbilityTaskWaitPhysicsFrames
extends GMAbilityTaskWait

func _init(p_frames: Variant = 1, p_task_id: Variant = "") -> void:
	super._init(float(p_frames), p_task_id, "physics_frames")

