class_name GMRealtimeAbilityScheduler
extends GMAbilityScheduler

func _init() -> void:
	super("realtime", "realtime")

func supports_unit(unit: String) -> bool:
	return unit in ["auto", "seconds", "physics_frames"]

func advance(amount: float = 1.0, unit: String = "auto") -> Dictionary:
	var resolved := unit if unit != "auto" else "seconds"
	match resolved:
		"seconds": return advance_seconds(amount)
		"physics_frames": return advance_physics_frames(int(amount))
		_: return _unsupported(resolved, amount)

func advance_seconds(amount: float) -> Dictionary:
	if paused:
		last_advance = {"ok": true, "advanced": false, "paused": true, "unit": "seconds", "amount": amount, "scheduler_id": scheduler_id, "mode": mode}
		return last_advance.duplicate(true)
	var safe_amount := maxf(float(amount), 0.0)
	time_seconds += safe_amount
	tick_count += 1
	last_advance = {"ok": true, "advanced": safe_amount > 0.0, "paused": false, "unit": "seconds", "amount": safe_amount, "scheduler_id": scheduler_id, "mode": mode}
	var result := last_advance.duplicate(true)
	result["snapshot"] = snapshot()
	return result

func advance_physics_frames(amount: int = 1) -> Dictionary:
	if paused:
		last_advance = {"ok": true, "advanced": false, "paused": true, "unit": "physics_frames", "amount": amount, "scheduler_id": scheduler_id, "mode": mode}
		return last_advance.duplicate(true)
	var safe_amount := maxi(amount, 0)
	physics_frame += safe_amount
	time_seconds += float(safe_amount) / 60.0
	tick_count += 1
	last_advance = {"ok": true, "advanced": safe_amount > 0, "paused": false, "unit": "physics_frames", "amount": safe_amount, "scheduler_id": scheduler_id, "mode": mode}
	var result := last_advance.duplicate(true)
	result["snapshot"] = snapshot()
	return result

func set_paused(value: bool) -> Dictionary:
	paused = value
	return {"ok": true, "paused": paused, "scheduler_id": scheduler_id}
