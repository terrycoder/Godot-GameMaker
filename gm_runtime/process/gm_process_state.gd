class_name GMProcessState
extends RefCounted

## Declarative lifecycle contract shared by every Process family.

const SCHEMA_VERSION := 1
const CREATED := "created"
const READY := "ready"
const RUNNING := "running"
const PAUSED := "paused"
const BLOCKED := "blocked"
const COMPLETED := "completed"
const CANCELLED := "cancelled"
const FAILED := "failed"

const TERMINAL := [COMPLETED, CANCELLED]
const TRANSITIONS := {
	CREATED: [READY, CANCELLED, FAILED],
	READY: [RUNNING, PAUSED, CANCELLED, FAILED],
	RUNNING: [PAUSED, BLOCKED, COMPLETED, CANCELLED, FAILED],
	PAUSED: [READY, RUNNING, CANCELLED, FAILED],
	BLOCKED: [READY, RUNNING, CANCELLED, FAILED],
	COMPLETED: [],
	CANCELLED: [],
	FAILED: [READY, CANCELLED],
}

static func is_known(value: Variant) -> bool:
	return value is String and TRANSITIONS.has(value)

static func can_transition(from_state: String, to_state: String) -> bool:
	return is_known(from_state) and is_known(to_state) and TRANSITIONS[from_state].has(to_state)

static func is_terminal(value: String) -> bool:
	return TERMINAL.has(value)

static func validate(value: Variant) -> Dictionary:
	if not is_known(value):
		return {"ok": false, "code": "process.state_invalid", "reason_zh": "Process 状态不在声明式生命周期内。", "state": value}
	return {"ok": true, "state": value}
