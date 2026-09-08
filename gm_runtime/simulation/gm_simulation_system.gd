class_name GMSimulationSystem
extends RefCounted

## 后台系统是纯数据执行器；它只读取 GMWorldSnapshot 并写 GMCommandBuffer。

var system_id: String = ""
var stage: int = 0
var frequency_ticks: int = 1
var priority: int = 0
var budget_units: int = 0
var enabled: bool = true

func _init(p_system_id: String = "", p_stage: int = 0, p_frequency_ticks: int = 1, p_priority: int = 0, p_budget_units: int = 0) -> void:
	system_id = p_system_id.strip_edges()
	stage = p_stage
	frequency_ticks = maxi(p_frequency_ticks, 1)
	priority = p_priority
	budget_units = maxi(p_budget_units, 0)

func is_due(tick: int) -> bool:
	return enabled and tick % frequency_ticks == 0

func step(_snapshot: GMWorldSnapshot, _commands: GMCommandBuffer) -> Dictionary:
	return {"ok": true, "command_count": 0}

func run(snapshot: GMWorldSnapshot, commands: GMCommandBuffer) -> Dictionary:
	if not enabled: return {"ok": true, "skipped": true, "reason": "disabled"}
	var result: Variant = step(snapshot, commands)
	if not result is Dictionary:
		return {"ok": false, "code": "system.invalid_result", "reason_zh": "系统没有返回结构化结果。"}
	var normalized: Dictionary = result.duplicate(true)
	if not normalized.has("ok"): normalized["ok"] = true
	return normalized

func descriptor() -> Dictionary:
	return {"system_id": system_id, "stage": stage, "frequency_ticks": frequency_ticks, "priority": priority, "budget_units": budget_units, "enabled": enabled}
