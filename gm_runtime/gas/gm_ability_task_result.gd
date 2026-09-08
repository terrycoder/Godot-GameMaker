class_name GMAbilityTaskResult
extends RefCounted

var ok: bool = false
var code: String = ""
var reason_zh: String = ""
var data: Dictionary = {}
var task_id: String = ""
var state: String = ""
var terminal: bool = false
var callback_accepted: bool = true

func _init(p_ok: bool = false, p_code: String = "", p_reason_zh: String = "", p_data: Dictionary = {}, p_task_id: String = "", p_state: String = "", p_terminal: bool = false) -> void:
	ok = p_ok
	code = p_code
	reason_zh = p_reason_zh
	data = p_data.duplicate(true)
	task_id = p_task_id
	state = p_state
	terminal = p_terminal

func to_dict() -> Dictionary:
	return {
		"ok": ok,
		"code": code,
		"reason_zh": reason_zh,
		"data": data.duplicate(true),
		"task_id": task_id,
		"state": state,
		"terminal": terminal,
		"callback_accepted": callback_accepted,
	}

func with_task(p_task_id: String, p_state: String, p_terminal: bool = false) -> GMAbilityTaskResult:
	task_id = p_task_id
	state = p_state
	terminal = p_terminal
	return self
