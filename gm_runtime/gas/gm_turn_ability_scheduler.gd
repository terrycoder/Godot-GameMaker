class_name GMTurnAbilityScheduler
extends GMAbilityScheduler

func _init() -> void:
	super("turn", "turn")

func supports_unit(unit: String) -> bool:
	return unit in ["auto", "turns", "action_points"]

func advance(amount: float = 1.0, unit: String = "auto") -> Dictionary:
	var resolved := unit if unit != "auto" else "turns"
	match resolved:
		"turns": return advance_turns(int(amount))
		"action_points": return advance_action_points(int(amount))
		_: return _unsupported(resolved, amount)

func advance_turns(amount: int = 1) -> Dictionary:
	if paused:
		last_advance = {"ok": true, "advanced": false, "paused": true, "unit": "turns", "amount": amount, "scheduler_id": scheduler_id, "mode": mode}
		return last_advance.duplicate(true)
	var safe_amount := maxi(amount, 0)
	turn += safe_amount
	tick_count += 1
	last_advance = {"ok": true, "advanced": safe_amount > 0, "paused": false, "unit": "turns", "amount": safe_amount, "scheduler_id": scheduler_id, "mode": mode}
	var result := last_advance.duplicate(true)
	result["snapshot"] = snapshot()
	return result

func advance_action_points(amount: int = 1) -> Dictionary:
	if paused:
		last_advance = {"ok": true, "advanced": false, "paused": true, "unit": "action_points", "amount": amount, "scheduler_id": scheduler_id, "mode": mode}
		return last_advance.duplicate(true)
	var safe_amount := maxi(amount, 0)
	action_points += safe_amount
	tick_count += 1
	last_advance = {"ok": true, "advanced": safe_amount > 0, "paused": false, "unit": "action_points", "amount": safe_amount, "scheduler_id": scheduler_id, "mode": mode}
	var result := last_advance.duplicate(true)
	result["snapshot"] = snapshot()
	return result

func set_paused(value: bool) -> Dictionary:
	paused = value
	return {"ok": true, "paused": paused, "scheduler_id": scheduler_id}
