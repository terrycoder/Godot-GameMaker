class_name GMAbilityTimeline
extends RefCounted

## 可观察能力时间线。它只保存可序列化的阶段证据，不保存协程或 NodePath。

var entries: Array[Dictionary] = []
var _sequence: int = 0

func record(state_name: String, reason_zh: String, scheduler: Object = null, accepted: bool = true, extra: Dictionary = {}) -> Dictionary:
	_sequence += 1
	var clock: Dictionary = scheduler.snapshot() if scheduler != null and scheduler.has_method("snapshot") else {}
	var entry := {
		"sequence": _sequence,
		"state": state_name,
		"reason_zh": reason_zh,
		"accepted": accepted,
		"time_usec": Time.get_ticks_usec(),
		"time_seconds": float(clock.get("time_seconds", 0.0)),
		"physics_frame": int(clock.get("physics_frame", 0)),
		"turn": int(clock.get("turn", 0)),
		"action_points": int(clock.get("action_points", 0)),
		"scheduler_id": str(clock.get("scheduler_id", "")),
		"scheduler_mode": str(clock.get("mode", "")),
	}
	for key in extra:
		entry[key] = extra[key]
	entries.append(entry)
	return entry

func append_event(event_name: String, reason_zh: String, scheduler: Object = null, extra: Dictionary = {}) -> Dictionary:
	return record(event_name, reason_zh, scheduler, true, extra)

func to_array() -> Array[Dictionary]:
	return entries.duplicate(true)

func to_dict() -> Dictionary:
	return {"entry_count": entries.size(), "entries": to_array()}

