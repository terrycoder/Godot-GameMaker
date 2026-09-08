class_name GMAttributeSet
extends RefCounted

## 统一、类型化的属性运行时。
## 规则层只通过本类读写属性。definitions 保存静态类型/边界/派生依赖，
## current_values 保存未叠加修正器的当前值，modifier_records 保存来源追踪。
## 计算失败时返回结构化中文错误；不会把 NaN、循环或未知属性静默变成 0。

signal attribute_changed(attribute_id: String, old_value: Variant, new_value: Variant, reason_zh: String, sources: Array)

const SCHEMA_VERSION := "gm.attribute_set.v2"
const SUPPORTED_TYPES := ["float", "int", "bool", "string"]

## 与旧任务兼容：旧调用方读取 values；它始终指向 current_values。
var values: Dictionary = {}
var base_values: Dictionary = {}
var current_values: Dictionary = {}
var definitions: Dictionary = {}
var modifier_records: Dictionary = {}
## 旧调用方可能读取 modifiers；保留一个属性到句柄的索引。
var modifiers: Dictionary = {}
var change_log: Array[Dictionary] = []
var last_error: Dictionary = {}
var _next_modifier_id: int = 1

func _init() -> void:
	values = current_values

func define_attribute(attribute_id: String, value_type: String = "float", base_value: Variant = 0.0, min_value: Variant = -INF, max_value: Variant = INF, dependencies: Array = [], derived_rule: Dictionary = {}) -> Dictionary:
	var id := attribute_id.strip_edges()
	if id.is_empty(): return _error("attribute.id_missing", "属性 ID 不能为空。")
	var normalized_type := value_type.strip_edges().to_lower()
	if not SUPPORTED_TYPES.has(normalized_type): return _error("attribute.type_invalid", "属性类型不受支持：%s。" % value_type)
	if normalized_type in ["float", "int"]:
		if not _finite_number(base_value): return _error("attribute.nan_or_inf", "属性定义不能包含 NaN 或无穷值：%s。" % id)
		# The legacy-compatible -INF/INF defaults mean "unbounded".
		if min_value is float and is_inf(float(min_value)) and float(min_value) < 0.0: min_value = null
		if max_value is float and is_inf(float(max_value)) and float(max_value) > 0.0: max_value = null
		if min_value != null and not _finite_number(min_value): return _error("attribute.nan_or_inf", "属性下限不能是 NaN 或无穷值：%s。" % id)
		if max_value != null and not _finite_number(max_value): return _error("attribute.nan_or_inf", "属性上限不能是 NaN 或无穷值：%s。" % id)
		if min_value != null and max_value != null and float(min_value) > float(max_value): return _error("attribute.bounds_invalid", "属性最小值不能大于最大值：%s。" % id)
	var dependency_list: Array[String] = []
	for raw in dependencies:
		var dependency := str(raw).strip_edges()
		if dependency.is_empty() or dependency_list.has(dependency): continue
		dependency_list.append(dependency)
	var rule := derived_rule.duplicate(true) if derived_rule is Dictionary else {}
	if not rule.is_empty() and dependency_list.is_empty():
		var rule_attributes: Variant = rule.get("attributes", [])
		if rule_attributes is Array:
			for raw_attribute in rule_attributes:
				var rule_id := str(raw_attribute).strip_edges()
				if not rule_id.is_empty() and not dependency_list.has(rule_id): dependency_list.append(rule_id)
	var coerced_base := _coerce(base_value, normalized_type)
	if not coerced_base.ok: return coerced_base
	var coerced_min := _coerce(min_value, normalized_type) if normalized_type in ["float", "int"] and min_value != null else {"ok": true, "value": null}
	var coerced_max := _coerce(max_value, normalized_type) if normalized_type in ["float", "int"] and max_value != null else {"ok": true, "value": null}
	if not coerced_min.ok or not coerced_max.ok: return _error("attribute.bounds_type_invalid", "属性边界类型错误：%s。" % id)
	var definition := {
		"attribute_id": id,
		"value_type": normalized_type,
		"min_value": coerced_min.value,
		"max_value": coerced_max.value,
		"dependencies": dependency_list,
		"derived_rule": rule,
		"derived": not rule.is_empty(),
	}
	definitions[id] = definition
	base_values[id] = coerced_base.value
	current_values[id] = coerced_base.value
	values = current_values
	if not rule.is_empty():
		var check := evaluate(id)
		if not check.ok:
			definitions.erase(id)
			base_values.erase(id)
			current_values.erase(id)
			return check
	return {"ok": true, "attribute_id": id, "definition": definition.duplicate(true), "value": coerced_base.value}

func set_value(attribute_id: String, value: Variant) -> Dictionary:
	var id := attribute_id.strip_edges()
	if id.is_empty(): return _error("attribute.id_missing", "属性 ID 不能为空。")
	if not definitions.has(id):
		var created := define_attribute(id, "float", value, -INF, INF)
		if not created.ok: return created
		return {"ok": true, "attribute_id": id, "value": current_values[id], "created_definition": true}
	return set_current_value(id, value, "设置属性当前值。")

func set_base_value(attribute_id: String, value: Variant, reason_zh: String = "设置属性基值。") -> Dictionary:
	var id := attribute_id.strip_edges()
	var definition: Dictionary = definitions.get(id, {})
	if definition.is_empty(): return _error("attribute.missing", "属性不存在：%s。" % id)
	if bool(definition.get("derived", false)): return _error("attribute.derived_read_only", "派生属性不能直接设置基值：%s。" % id)
	var checked := _coerce(value, str(definition.get("value_type", "float")))
	if not checked.ok: return checked
	var old_value: Variant = get_value(id, null)
	base_values[id] = checked.value
	current_values[id] = _clamp_value(checked.value, definition)
	return _emit_if_changed(id, old_value, get_value(id, null), reason_zh)

func set_current_value(attribute_id: String, value: Variant, reason_zh: String = "设置属性当前值。") -> Dictionary:
	var id := attribute_id.strip_edges()
	var definition: Dictionary = definitions.get(id, {})
	if definition.is_empty(): return _error("attribute.missing", "属性不存在：%s。" % id)
	if bool(definition.get("derived", false)): return _error("attribute.derived_read_only", "派生属性不能直接设置当前值：%s。" % id)
	var checked := _coerce(value, str(definition.get("value_type", "float")))
	if not checked.ok: return checked
	var old_value: Variant = get_value(id, null)
	current_values[id] = _clamp_value(checked.value, definition)
	values = current_values
	return _emit_if_changed(id, old_value, get_value(id, null), reason_zh)

func apply_delta(attribute_id: String, delta: Variant, source_id: String = "", reason_zh: String = "属性发生数值变化。") -> Dictionary:
	var id := attribute_id.strip_edges()
	var definition: Dictionary = definitions.get(id, {})
	if definition.is_empty(): return _error("attribute.missing", "属性不存在：%s。" % id)
	if bool(definition.get("derived", false)): return _error("attribute.derived_read_only", "派生属性不能直接改变：%s。" % id)
	if not _finite_number(delta): return _error("attribute.nan_or_inf", "属性变化不能是 NaN 或无穷值：%s。" % id)
	if str(definition.get("value_type", "float")) not in ["float", "int"]: return _error("attribute.type_mismatch", "非数值属性不能执行数值变化：%s。" % id)
	var before: Variant = get_value(id, null)
	var next_value := float(current_values.get(id, base_values.get(id, 0.0))) + float(delta)
	if str(definition.get("value_type", "float")) == "int": next_value = int(round(next_value))
	var checked := _coerce(next_value, str(definition.get("value_type", "float")))
	if not checked.ok: return checked
	current_values[id] = _clamp_value(checked.value, definition)
	values = current_values
	var result := _emit_if_changed(id, before, get_value(id, null), reason_zh)
	if result.ok and not source_id.strip_edges().is_empty(): result["source_id"] = source_id
	return result

func modify(attribute_id: String, delta: Variant, source_id: String = "", reason_zh: String = "属性发生数值变化。") -> Dictionary:
	return apply_delta(attribute_id, delta, source_id, reason_zh)

func get_value(attribute_id: String, default_value: Variant = 0.0) -> Variant:
	var result := evaluate(attribute_id)
	if result.ok: return result.value
	return default_value

func evaluate(attribute_id: String) -> Dictionary:
	var id := attribute_id.strip_edges()
	if id.is_empty(): return _error("attribute.id_missing", "属性 ID 不能为空。")
	var result := _evaluate_internal(id, [], {})
	if not result.ok:
		last_error = result.duplicate(true)
		return result
	last_error = {}
	return result

func add_modifier(attribute_id: String, modifier_type: String, value: Variant, source_id: String = "unknown", stacks: int = 1, modifier_id: String = "") -> Dictionary:
	var id := attribute_id.strip_edges()
	var definition: Dictionary = definitions.get(id, {})
	if definition.is_empty(): return _error("attribute.missing", "属性不存在：%s。" % id)
	if str(definition.get("value_type", "float")) not in ["float", "int"]: return _error("attribute.type_mismatch", "只有数值属性可以添加修正器：%s。" % id)
	if not _finite_number(value): return _error("attribute.nan_or_inf", "属性修正器不能包含 NaN 或无穷值：%s。" % id)
	var normalized_type := modifier_type.strip_edges().to_lower()
	if normalized_type == "flat": normalized_type = "add"
	if normalized_type == "percent": normalized_type = "percent_add"
	if normalized_type == "final_multiplier": normalized_type = "multiply"
	if not ["add", "percent_add", "multiply", "override"].has(normalized_type): return _error("attribute.modifier_type_invalid", "未知属性修正器类型：%s。" % modifier_type)
	var safe_source := source_id.strip_edges()
	if safe_source.is_empty(): return _error("attribute.source_missing", "属性修正器来源不能为空。")
	var safe_stacks := maxi(stacks, 1)
	var old_value: Variant = get_value(id, null)
	var handle := modifier_id.strip_edges()
	if handle.is_empty():
		handle = "gm.modifier.%d" % _next_modifier_id
		_next_modifier_id += 1
	if modifier_records.has(handle): return _error("attribute.modifier_duplicate", "属性修正器句柄重复：%s。" % handle)
	modifier_records[handle] = {"modifier_id": handle, "attribute_id": id, "type": normalized_type, "value": float(value), "source_id": safe_source, "stacks": safe_stacks}
	if not modifiers.has(id): modifiers[id] = []
	modifiers[id].append(handle)
	var new_value: Variant = get_value(id, null)
	_emit_if_changed(id, old_value, new_value, "添加属性修正器。")
	return {"ok": true, "modifier_id": handle, "attribute_id": id, "source_id": safe_source, "value": new_value}

func remove_modifier(modifier_id: String) -> Dictionary:
	var handle := modifier_id.strip_edges()
	if not modifier_records.has(handle): return {"ok": false, "code": "attribute.modifier_missing", "reason_zh": "属性修正器不存在或已经移除：%s。" % handle, "already_removed": true}
	var record: Dictionary = modifier_records[handle]
	var id := str(record.get("attribute_id", ""))
	var old_value: Variant = get_value(id, null)
	modifier_records.erase(handle)
	if modifiers.has(id):
		modifiers[id].erase(handle)
		if modifiers[id].is_empty(): modifiers.erase(id)
	var new_value: Variant = get_value(id, null)
	_emit_if_changed(id, old_value, new_value, "移除属性修正器。")
	return {"ok": true, "modifier_id": handle, "attribute_id": id, "value": new_value}

func remove_source_modifiers(source_id: String) -> Dictionary:
	var removed: Array[Dictionary] = []
	for handle in modifier_records.keys().duplicate():
		if str(modifier_records[handle].get("source_id", "")) == source_id:
			removed.append(remove_modifier(str(handle)))
	return {"ok": true, "source_id": source_id, "removed": removed}

func source_summary(attribute_id: String = "") -> Dictionary:
	var result: Dictionary = {}
	var ids: Array = [attribute_id] if not attribute_id.strip_edges().is_empty() else definitions.keys()
	for raw_id in ids:
		var id := str(raw_id)
		if not definitions.has(id): continue
		var rows: Array = []
		for handle in modifiers.get(id, []):
			if modifier_records.has(handle): rows.append(modifier_records[handle].duplicate(true))
		result[id] = {"base": base_values.get(id), "current": current_values.get(id), "effective": get_value(id, null), "derived": definitions[id].get("derived", false), "dependencies": definitions[id].get("dependencies", []).duplicate(), "modifiers": rows}
	return result

func snapshot() -> Dictionary:
	var result: Dictionary = {}
	for id in definitions.keys(): result[id] = get_value(str(id), null)
	return result

func snapshot_state() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "definitions": definitions.duplicate(true), "base_values": base_values.duplicate(true), "current_values": current_values.duplicate(true), "modifier_records": modifier_records.duplicate(true), "next_modifier_id": _next_modifier_id, "changes": change_log.duplicate(true)}

func restore_state(value: Dictionary) -> Dictionary:
	# Restore is a two-phase operation.  A failed definition, value, modifier or
	# derived-graph check must never expose a partially replaced AttributeSet.
	var staged := GMAttributeSet.new()
	var staged_result := staged._restore_state_in_place(value)
	if not staged_result.ok:
		last_error = staged.last_error.duplicate(true)
		return staged_result
	definitions = staged.definitions
	base_values = staged.base_values
	current_values = staged.current_values
	modifier_records = staged.modifier_records
	modifiers = staged.modifiers
	_next_modifier_id = staged._next_modifier_id
	change_log = staged.change_log
	values = current_values
	last_error = {}
	return staged_result

func _restore_state_in_place(value: Dictionary) -> Dictionary:
	if str(value.get("schema_version", "")) not in [SCHEMA_VERSION, "gm.attribute_set.v1"]: return _error("attribute.snapshot_schema_invalid", "属性集存档版本不受支持。")
	if not value.get("definitions", null) is Dictionary: return _error("attribute.snapshot_definitions_invalid", "属性存档定义集合无效。")
	if not value.get("base_values", null) is Dictionary: return _error("attribute.snapshot_base_values_invalid", "属性存档基值集合无效。")
	if not value.get("current_values", null) is Dictionary: return _error("attribute.snapshot_current_values_invalid", "属性存档当前值集合无效。")
	if not value.get("modifier_records", null) is Dictionary: return _error("attribute.snapshot_modifiers_invalid", "属性存档修正器集合无效。")
	var next_definitions: Dictionary = value.definitions
	var next_base: Dictionary = value.base_values
	var next_current: Dictionary = value.current_values
	for raw_id in next_definitions:
		var id := str(raw_id)
		var definition: Dictionary = next_definitions[raw_id] if next_definitions[raw_id] is Dictionary else {}
		if definition.is_empty(): return _error("attribute.snapshot_definition_invalid", "属性存档定义无效：%s。" % id)
		var definition_id := str(definition.get("attribute_id", id)).strip_edges()
		var value_type := str(definition.get("value_type", "")).strip_edges().to_lower()
		if id.strip_edges().is_empty() or definition_id != id: return _error("attribute.snapshot_definition_id_invalid", "属性存档定义身份无效：%s。" % id)
		if not SUPPORTED_TYPES.has(value_type): return _error("attribute.type_invalid", "属性类型不受支持：%s。" % value_type)
		var min_value: Variant = definition.get("min_value", null)
		var max_value: Variant = definition.get("max_value", null)
		if value_type in ["float", "int"]:
			if min_value != null and not _finite_number(min_value): return _error("attribute.nan_or_inf", "属性下限不能是 NaN 或无穷值：%s。" % id)
			if max_value != null and not _finite_number(max_value): return _error("attribute.nan_or_inf", "属性上限不能是 NaN 或无穷值：%s。" % id)
			if min_value != null and max_value != null and float(min_value) > float(max_value): return _error("attribute.bounds_invalid", "属性最小值不能大于最大值：%s。" % id)
		var dependencies: Variant = definition.get("dependencies", [])
		if not dependencies is Array: return _error("attribute.snapshot_dependencies_invalid", "属性派生依赖格式无效：%s。" % id)
		var derived_rule: Variant = definition.get("derived_rule", {})
		if not derived_rule is Dictionary: return _error("attribute.snapshot_derived_rule_invalid", "属性派生规则格式无效：%s。" % id)
		var base_check := _coerce(next_base.get(id, null), value_type)
		if not base_check.ok: return base_check
		var current_check := _coerce(next_current.get(id, next_base.get(id, null)), value_type)
		if not current_check.ok: return current_check
		definitions[id] = definition.duplicate(true)
		definitions[id]["attribute_id"] = id
		definitions[id]["value_type"] = value_type
		base_values[id] = _clamp_value(base_check.value, definitions[id])
		current_values[id] = _clamp_value(current_check.value, definitions[id])
	var records: Dictionary = value.modifier_records
	for raw_handle in records:
		var record: Dictionary = records[raw_handle] if records[raw_handle] is Dictionary else {}
		var handle := str(raw_handle)
		if record.is_empty() or handle.strip_edges().is_empty(): return _error("attribute.snapshot_modifier_invalid", "属性修正器存档记录无效：%s。" % handle)
		if str(record.get("modifier_id", handle)) != handle: return _error("attribute.snapshot_modifier_id_invalid", "属性修正器存档身份无效：%s。" % handle)
		var attribute_id := str(record.get("attribute_id", ""))
		if not definitions.has(attribute_id): return _error("attribute.snapshot_modifier_attribute_missing", "属性修正器引用不存在属性：%s。" % attribute_id)
		var added := add_modifier(attribute_id, str(record.get("type", "")), record.get("value", null), str(record.get("source_id", "")), int(record.get("stacks", 0)), handle)
		if not added.ok: return added
	_next_modifier_id = maxi(int(value.get("next_modifier_id", 1)), 1)
	values = current_values
	var raw_changes: Variant = value.get("changes", [])
	if not raw_changes is Array: return _error("attribute.snapshot_changes_invalid", "属性变化记录格式无效。")
	change_log.clear()
	for raw_change in raw_changes:
		if not raw_change is Dictionary: return _error("attribute.snapshot_change_invalid", "属性变化记录包含非对象条目。")
		change_log.append(raw_change.duplicate(true))
	for id in definitions:
		var check := evaluate(str(id))
		if not check.ok: return check
	return {"ok": true, "restored": true, "attribute_count": definitions.size(), "modifier_count": modifier_records.size()}

func _evaluate_internal(id: String, stack: Array, cache: Dictionary) -> Dictionary:
	if cache.has(id): return cache[id].duplicate(true)
	if not definitions.has(id): return _error("attribute.missing", "属性不存在：%s。" % id)
	if stack.has(id): return _error("attribute.derived_cycle", "派生属性存在循环依赖：%s。" % " -> ".join(stack + [id]))
	var definition: Dictionary = definitions[id]
	var next_stack := stack.duplicate()
	next_stack.append(id)
	var value: Variant = current_values.get(id, base_values.get(id, null))
	if bool(definition.get("derived", false)):
		var inputs: Array[Variant] = []
		for dependency in definition.get("dependencies", []):
			var input := _evaluate_internal(str(dependency), next_stack, cache)
			if not input.ok: return input
			if typeof(input.value) not in [TYPE_INT, TYPE_FLOAT]: return _error("attribute.derived_type_invalid", "派生依赖不是数值属性：%s。" % dependency)
			inputs.append(float(input.value))
		var calculated := _calculate_derived(definition.get("derived_rule", {}), inputs)
		if not calculated.ok: return calculated
		value = calculated.value
	value = _apply_modifiers(id, value)
	var typed := _coerce(value, str(definition.get("value_type", "float")))
	if not typed.ok: return typed
	value = _clamp_value(typed.value, definition)
	if typeof(value) in [TYPE_FLOAT, TYPE_INT] and not _finite_number(value): return _error("attribute.nan_or_inf", "属性计算产生 NaN 或无穷值：%s。" % id)
	var result := {"ok": true, "attribute_id": id, "value": value, "type": definition.get("value_type", "float"), "sources": _sources_for(id), "dependencies": definition.get("dependencies", []).duplicate()}
	cache[id] = result.duplicate(true)
	return result

func _calculate_derived(rule: Variant, inputs: Array[Variant]) -> Dictionary:
	var config: Dictionary = rule if rule is Dictionary else {}
	var operation := str(config.get("op", config.get("operation", "sum"))).to_lower()
	var constant := float(config.get("constant", 0.0))
	match operation:
		"constant": return {"ok": true, "value": config.get("value", constant)}
		"copy": return {"ok": true, "value": inputs[0] if not inputs.is_empty() else constant}
		"sum", "add":
			var total := constant
			for value in inputs: total += float(value)
			return {"ok": true, "value": total}
		"multiply":
			var total := 1.0
			if inputs.is_empty(): total = constant if not is_equal_approx(constant, 0.0) else 0.0
			for value in inputs: total *= float(value)
			return {"ok": true, "value": total + constant}
		"ratio", "divide":
			if inputs.size() < 2 or is_zero_approx(float(inputs[1])): return _error("attribute.derived_divide_zero", "派生属性除数为零。")
			return {"ok": true, "value": float(inputs[0]) / float(inputs[1]) + constant}
		"min":
			if inputs.is_empty(): return {"ok": true, "value": constant}
			return {"ok": true, "value": minf_array(inputs) + constant}
		"max":
			if inputs.is_empty(): return {"ok": true, "value": constant}
			return {"ok": true, "value": maxf_array(inputs) + constant}
	return _error("attribute.derived_operation_invalid", "未知派生计算操作：%s。" % operation)

func _sources_for(attribute_id: String) -> Array:
	var result: Array = []
	for handle in modifiers.get(attribute_id, []):
		if modifier_records.has(handle): result.append(str(modifier_records[handle].get("source_id", "")))
	return result

func _apply_modifiers(attribute_id: String, raw_value: Variant) -> Variant:
	if typeof(raw_value) not in [TYPE_INT, TYPE_FLOAT]: return raw_value
	var value := float(raw_value)
	var additive := 0.0
	var multiplier := 1.0
	var override_value: Variant = null
	for handle in modifiers.get(attribute_id, []):
		if not modifier_records.has(handle): continue
		var modifier: Dictionary = modifier_records[handle]
		var stacks := maxi(int(modifier.get("stacks", 1)), 1)
		var modifier_value := float(modifier.get("value", 0.0))
		match str(modifier.get("type", "add")):
			"add": additive += modifier_value * stacks
			"percent_add": multiplier += modifier_value * stacks
			"multiply": multiplier *= pow(modifier_value, stacks)
			"override": override_value = modifier_value
	var result := float(override_value) if override_value != null else value
	return result * multiplier + additive

func _clamp_value(value: Variant, definition: Dictionary) -> Variant:
	if str(definition.get("value_type", "float")) not in ["float", "int"]: return value
	var result := float(value)
	if definition.get("min_value", null) != null: result = maxf(result, float(definition.get("min_value")))
	if definition.get("max_value", null) != null: result = minf(result, float(definition.get("max_value")))
	return int(round(result)) if str(definition.get("value_type", "float")) == "int" else result

func _coerce(value: Variant, value_type: String) -> Dictionary:
	match value_type:
		"float":
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not _finite_number(value): return _error("attribute.type_mismatch", "属性需要有限数值。")
			return {"ok": true, "value": float(value)}
		"int":
			if typeof(value) != TYPE_INT: return _error("attribute.type_mismatch", "属性需要整数值。")
			return {"ok": true, "value": int(value)}
		"bool":
			if typeof(value) != TYPE_BOOL: return _error("attribute.type_mismatch", "属性需要布尔值。")
			return {"ok": true, "value": bool(value)}
		"string":
			if typeof(value) != TYPE_STRING: return _error("attribute.type_mismatch", "属性需要字符串值。")
			return {"ok": true, "value": str(value)}
	return _error("attribute.type_invalid", "属性类型不受支持：%s。" % value_type)

func _emit_if_changed(id: String, old_value: Variant, new_value: Variant, reason_zh: String) -> Dictionary:
	if old_value == new_value: return {"ok": true, "changed": false, "attribute_id": id, "value": new_value}
	var entry := {"attribute_id": id, "old_value": old_value, "new_value": new_value, "reason_zh": reason_zh, "sources": _sources_for(id), "timestamp_usec": Time.get_ticks_usec()}
	change_log.append(entry)
	attribute_changed.emit(id, old_value, new_value, reason_zh, entry.sources)
	return {"ok": true, "changed": true, "attribute_id": id, "old_value": old_value, "value": new_value, "sources": entry.sources}

func _error(code: String, reason_zh: String) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	last_error = result.duplicate(true)
	return result

func _finite_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]: return false
	var number := float(value)
	return not is_nan(number) and not is_inf(number)

func minf_array(values_array: Array[Variant]) -> float:
	var result := INF
	for value in values_array: result = minf(result, float(value))
	return result

func maxf_array(values_array: Array[Variant]) -> float:
	var result := -INF
	for value in values_array: result = maxf(result, float(value))
	return result
