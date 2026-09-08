@tool
class_name GMP26SampleRules
extends Resource

const SCHEMA := "gm.p26.sample_rules.v1"

@export var rule_id: String = "gm.rule.p26.warehouse_capacity"
@export var display_name_zh: String = "中性仓库容量恢复规则"
@export_range(1, 64, 1) var initial_warehouse_slot_limit: int = 1
@export_range(1, 64, 1) var recovery_warehouse_slot_limit: int = 2

func validate() -> Dictionary:
	var errors_zh: Array[String] = []
	if rule_id.strip_edges().is_empty(): errors_zh.append("规则稳定ID不能为空。")
	if display_name_zh.strip_edges().is_empty(): errors_zh.append("中文显示名不能为空。")
	if initial_warehouse_slot_limit < 1: errors_zh.append("初始容量至少为1。")
	if recovery_warehouse_slot_limit <= initial_warehouse_slot_limit: errors_zh.append("恢复容量必须大于初始容量。")
	return {"ok": errors_zh.is_empty(), "errors_zh": errors_zh, "schema": SCHEMA}

func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA,
		"rule_id": rule_id,
		"display_name_zh": display_name_zh,
		"initial_warehouse_slot_limit": initial_warehouse_slot_limit,
		"recovery_warehouse_slot_limit": recovery_warehouse_slot_limit,
	}
