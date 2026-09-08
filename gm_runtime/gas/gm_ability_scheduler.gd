class_name GMAbilityScheduler
extends RefCounted

## AbilityTask 只依赖这个接口，不依赖 SceneTreeTimer 或具体调度器。

var scheduler_id: String = "base"
var mode: String = "abstract"
var tick_count: int = 0
var time_seconds: float = 0.0
var physics_frame: int = 0
var turn: int = 0
var action_points: int = 0
var paused: bool = false
var last_advance: Dictionary = {}

func _init(p_scheduler_id: String = "base", p_mode: String = "abstract") -> void:
	scheduler_id = p_scheduler_id
	mode = p_mode

func advance(amount: float = 1.0, unit: String = "auto") -> Dictionary:
	var normalized_unit := unit if not unit.is_empty() else "auto"
	if normalized_unit == "auto": normalized_unit = "seconds"
	return _unsupported(normalized_unit, amount)

func advance_seconds(amount: float) -> Dictionary:
	return _unsupported("seconds", amount)

func advance_physics_frames(amount: int = 1) -> Dictionary:
	return _unsupported("physics_frames", amount)

func advance_action_points(amount: int = 1) -> Dictionary:
	return _unsupported("action_points", amount)

func advance_turns(amount: int = 1) -> Dictionary:
	return _unsupported("turns", amount)

func advance_time(amount: float = 1.0) -> Dictionary:
	return advance_seconds(amount)

func advance_frames(amount: int = 1) -> Dictionary:
	return advance_physics_frames(amount)

func advance_turn(amount: int = 1) -> Dictionary:
	return advance_turns(amount)

func wait_seconds(amount: float) -> Dictionary:
	return describe_wait("seconds", amount)

func wait_physics_frames(amount: int) -> Dictionary:
	return describe_wait("physics_frames", amount)

func wait_action_points(amount: int) -> Dictionary:
	return describe_wait("action_points", amount)

func wait_turns(amount: int) -> Dictionary:
	return describe_wait("turns", amount)

func supports_unit(unit: String) -> bool:
	return unit == "auto"

func metric(unit: String) -> float:
	match unit:
		"seconds": return time_seconds
		"physics_frames": return float(physics_frame)
		"action_points": return float(action_points)
		"turns": return float(turn)
		_: return 0.0

func snapshot() -> Dictionary:
	return {
		"scheduler_id": scheduler_id,
		"mode": mode,
		"tick_count": tick_count,
		"time_seconds": time_seconds,
		"physics_frame": physics_frame,
		"turn": turn,
		"action_points": action_points,
		"paused": paused,
		"last_advance": last_advance.duplicate(true),
	}

func restore_snapshot(value: Dictionary) -> Dictionary:
	if not value is Dictionary: return {"ok": false, "code": "scheduler.snapshot_invalid", "reason_zh": "调度器存档不是对象。"}
	var saved_mode := str(value.get("mode", mode))
	if saved_mode != mode and saved_mode != "abstract": return {"ok": false, "code": "scheduler.mode_mismatch", "reason_zh": "调度器模式与存档不一致：%s → %s。" % [saved_mode, mode]}
	scheduler_id = str(value.get("scheduler_id", scheduler_id))
	tick_count = maxi(int(value.get("tick_count", 0)), 0)
	time_seconds = maxf(float(value.get("time_seconds", 0.0)), 0.0)
	physics_frame = maxi(int(value.get("physics_frame", 0)), 0)
	turn = maxi(int(value.get("turn", 0)), 0)
	action_points = maxi(int(value.get("action_points", 0)), 0)
	paused = bool(value.get("paused", false))
	last_advance = value.get("last_advance", {}).duplicate(true) if value.get("last_advance", {}) is Dictionary else {}
	return {"ok": true, "restored": true, "scheduler_id": scheduler_id, "mode": mode}

func describe_wait(unit: String, amount: float) -> Dictionary:
	var resolved := unit
	if resolved == "auto": resolved = "turns" if mode == "turn" else "seconds"
	return {
		"ok": supports_unit(resolved),
		"unit": resolved,
		"amount": amount,
		"start": metric(resolved),
		"scheduler_id": scheduler_id,
		"mode": mode,
		"reason_zh": "" if supports_unit(resolved) else "当前调度器不支持该等待单位：%s。" % resolved,
	}

func progress_since(wait_description: Dictionary) -> float:
	var unit := str(wait_description.get("unit", "seconds"))
	return metric(unit) - float(wait_description.get("start", metric(unit)))

func _unsupported(unit: String, amount: Variant) -> Dictionary:
	last_advance = {"ok": false, "advanced": false, "unsupported": true, "unit": unit, "amount": amount, "scheduler_id": scheduler_id, "mode": mode}
	return last_advance.duplicate(true)
