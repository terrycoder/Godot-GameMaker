@tool
class_name GMEventCondition
extends Resource

## Gameplay Event 条件基类与内置条件。
##
## 条件只读事件上下文、宿主标签/属性和声明式内容状态。它不拥有领域
## 写入口；任何状态变化必须由触发器动作转入统一 Ability/Transaction。

const KIND_TAG := "标签"
const KIND_ATTRIBUTE := "属性"
const KIND_CONTENT_STATE := "内容状态"
const KIND_EXPRESSION := "Expression"
const KIND_GDSCRIPT := "GDScript"
const KIND_GROUP := "组合"

@export_group("条件身份")
@export var condition_id: String = ""
@export var display_name_zh: String = "事件条件"
@export_enum("标签", "属性", "内容状态", "Expression", "GDScript", "组合") var condition_kind: String = KIND_TAG
@export var invert: bool = false

@export_group("标签条件")
@export var tag_query: String = ""
@export_enum("事件", "宿主", "目标") var tag_scope: String = "事件"
@export var include_child_tags: bool = true

@export_group("属性条件")
@export var attribute_id: String = ""
@export_enum("等于", "不等于", "大于", "大于等于", "小于", "小于等于") var attribute_comparison: String = "等于"
@export var attribute_expected_value: Variant = 0.0

@export_group("内容状态条件")
@export var content_state_key: String = ""
@export_enum("等于", "不等于", "存在", "不存在") var content_comparison: String = "等于"
@export var content_expected_value: Variant = true

@export_group("Expression 条件")
@export var expression: GMExpressionField

@export_group("GDScript 条件")
## 若脚本通过资源脚本附加，script_path 可留空；留空时验证器会从对象脚本定位。
@export_file("*.gd") var script_path: String = ""

@export_group("组合条件")
@export_enum("全部满足", "任一满足", "全部不满足") var group_operator: String = "全部满足"
@export var children: Array = []
@export var max_depth: int = 16

func validate_definition(context: Dictionary = {}) -> Dictionary:
	return _validate_node(context, 0, {}, [])

func evaluate(context: Dictionary = {}) -> Dictionary:
	var definition_check := validate_definition(context)
	if not definition_check.ok: return _evaluation_failure(definition_check)
	# _evaluate_node is the single semantic boundary for every condition node.
	# It evaluates the raw node value and applies this node's invert exactly once,
	# including when the node is reached through a nested group.
	return _evaluate_node(context, 0, {}, [])

## GDScript 扩展覆盖点。正式脚本必须显式声明：
## func _evaluate_custom(context: Dictionary) -> Dictionary
func _evaluate_custom(_context: Dictionary) -> Dictionary:
	return {"ok": false, "code": "event.condition_script_not_implemented", "reason_zh": "事件条件 GDScript 没有实现 _evaluate_custom。"}

func summary() -> Dictionary:
	var child_rows: Array = []
	for child in children:
		if child is GMEventCondition: child_rows.append(child.summary())
	return {
		"condition_id": condition_id,
		"display_name_zh": display_name_zh,
		"condition_kind": condition_kind,
		"invert": invert,
		"tag_query": tag_query,
		"tag_scope": tag_scope,
		"attribute_id": attribute_id,
		"attribute_comparison": attribute_comparison,
		"content_state_key": content_state_key,
		"content_comparison": content_comparison,
		"expression": expression.expression if expression != null else "",
		"script_path": _resolved_script_path(),
		"group_operator": group_operator,
		"children": child_rows,
		"max_depth": max_depth
	}

func _validate_node(context: Dictionary, depth: int, visited: Dictionary, stack: Array) -> Dictionary:
	if depth > maxi(max_depth, 1):
		return _error("event.condition_depth", "事件条件递归深度超过限制：%d。" % maxi(max_depth, 1), "condition")
	var instance_key := str(get_instance_id())
	if stack.has(instance_key):
		var cycle := stack.duplicate()
		cycle.append(instance_key)
		return _error("event.condition_cycle", "事件条件检测到循环引用：%s。" % " → ".join(cycle), "condition")
	if visited.has(instance_key):
		return _error("event.condition_duplicate_cycle", "事件条件重复进入同一节点，已阻断潜在循环：%s。" % condition_id, "condition")
	var next_stack := stack.duplicate()
	next_stack.append(instance_key)
	var next_visited := visited.duplicate()
	next_visited[instance_key] = true
	var errors: Array[Dictionary] = []
	if condition_id.strip_edges().is_empty(): errors.append(_error_item("event.condition_id_missing", "事件条件缺少稳定条件 ID。", "condition_id"))
	match condition_kind:
		KIND_TAG:
			if tag_query.strip_edges().is_empty(): errors.append(_error_item("event.condition_tag_missing", "标签条件缺少标签查询。", "tag_query"))
		KIND_ATTRIBUTE:
			if attribute_id.strip_edges().is_empty(): errors.append(_error_item("event.condition_attribute_missing", "属性条件缺少属性 ID。", "attribute_id"))
		KIND_CONTENT_STATE:
			if content_state_key.strip_edges().is_empty(): errors.append(_error_item("event.condition_content_key_missing", "内容状态条件缺少状态键。", "content_state_key"))
		KIND_EXPRESSION:
			if expression == null: errors.append(_error_item("event.condition_expression_missing", "Expression 条件缺少 GMExpressionField。", "expression"))
			else:
				var expression_inputs: Dictionary = _expression_inputs(context)
				if not bool(context.get("validate_expression_values", true)):
					for input_name in expression.input_names:
						if not expression_inputs.has(input_name): expression_inputs[input_name] = _expression_default(str(input_name))
				var expression_check: Dictionary = expression.validate(expression_inputs)
				if not expression_check.ok: errors.append_array(_prefix_errors(expression_check.get("errors", []), "expression"))
		KIND_GDSCRIPT:
			var script_check := _validate_script()
			if not script_check.ok: errors.append_array(_prefix_errors(script_check.get("errors", []), "script"))
		KIND_GROUP:
			if children.is_empty(): errors.append(_error_item("event.condition_children_missing", "组合条件至少需要一个子条件。", "children"))
			if group_operator not in ["全部满足", "任一满足", "全部不满足"]: errors.append(_error_item("event.condition_operator_invalid", "组合条件操作符无效：%s。" % group_operator, "group_operator"))
			for index in children.size():
				var child: Variant = children[index]
				if child == null or not child is GMEventCondition:
					errors.append(_error_item("event.condition_child_invalid", "组合条件第 %d 项不是 GMEventCondition。" % index, "children[%d]" % index))
					continue
				var child_check: Dictionary = child._validate_node(context, depth + 1, next_visited, next_stack)
				if not child_check.ok: errors.append_array(_prefix_errors(child_check.get("errors", []), "children[%d]" % index))
		_:
			errors.append(_error_item("event.condition_kind_invalid", "未知事件条件类型：%s。" % condition_kind, "condition_kind"))
	return {"ok": errors.is_empty(), "code": "event.condition_valid" if errors.is_empty() else "event.condition_invalid", "errors": errors, "errors_zh": _messages(errors), "condition_id": condition_id}

func _evaluate_node(context: Dictionary, depth: int, visited: Dictionary, stack: Array) -> Dictionary:
	if depth > maxi(max_depth, 1): return _error("event.condition_depth", "事件条件递归深度超过限制：%d。" % maxi(max_depth, 1), "condition")
	var instance_key := str(get_instance_id())
	if stack.has(instance_key):
		var cycle := stack.duplicate()
		cycle.append(instance_key)
		return _error("event.condition_cycle", "事件条件检测到循环引用：%s。" % " → ".join(cycle), "condition")
	if visited.has(instance_key): return _error("event.condition_duplicate_cycle", "事件条件执行检测到重复循环节点：%s。" % condition_id, "condition")
	var next_stack := stack.duplicate()
	next_stack.append(instance_key)
	var next_visited := visited.duplicate()
	next_visited[instance_key] = true
	var matched := false
	var details: Dictionary = {}
	match condition_kind:
		KIND_TAG: matched = _evaluate_tag(context, details)
		KIND_ATTRIBUTE: matched = _evaluate_attribute(context, details)
		KIND_CONTENT_STATE: matched = _evaluate_content(context, details)
		KIND_EXPRESSION:
			var expression_result := expression.evaluate(_expression_inputs(context)) if expression != null else {"ok": false, "code": "event.condition_expression_missing", "reason_zh": "Expression 条件缺少表达式对象。"}
			if not expression_result.ok: return _evaluation_failure(expression_result)
			matched = bool(expression_result.get("value", false))
			details = expression_result.duplicate(true)
		KIND_GDSCRIPT:
			var script_result: Variant = _evaluate_custom(context)
			if not script_result is Dictionary: return _error("event.condition_script_return_type", "事件条件 GDScript 必须返回 Dictionary。", "script")
			var script_dict: Dictionary = script_result
			if not script_dict.has("ok") or not bool(script_dict.get("ok", false)):
				return _normalize_script_failure(script_dict)
			matched = bool(script_dict.get("matched", script_dict.get("value", false)))
			details = script_dict.duplicate(true)
		KIND_GROUP:
			var child_results: Array[Dictionary] = []
			for child in children:
				if child == null or not child is GMEventCondition: return _error("event.condition_child_invalid", "组合条件包含无效子条件。", "children")
				var child_result: Dictionary = child._evaluate_node(context, depth + 1, next_visited, next_stack)
				if not child_result.ok: return child_result
				child_results.append(child_result)
			var matches: Array = child_results.map(func(item): return bool(item.get("matched", false)))
			match group_operator:
				"全部满足": matched = matches.all(func(value): return bool(value))
				"任一满足": matched = matches.any(func(value): return bool(value))
				"全部不满足": matched = matches.all(func(value): return not bool(value))
			details = {"children": child_results, "operator": group_operator}
		_:
			return _error("event.condition_kind_invalid", "未知事件条件类型：%s。" % condition_kind, "condition_kind")
	if invert: matched = not matched
	return {"ok": true, "matched": matched, "condition_id": condition_id, "condition_kind": condition_kind, "details": details, "inverted": invert}

func _evaluate_tag(context: Dictionary, details: Dictionary) -> bool:
	var event: Variant = context.get("event", null)
	var host: Variant = context.get("host", null)
	var matched := false
	if tag_scope == "事件" and event != null and event is GMGameplayEvent: matched = event.matches_tag(tag_query, include_child_tags)
	elif tag_scope == "宿主" and host != null and host.has_method("tags"):
		matched = host.tags.matches(tag_query, "hierarchy" if include_child_tags else "exact")
	elif tag_scope == "宿主" and host != null and host.get("tags") != null:
		matched = host.get("tags").matches(tag_query, "hierarchy" if include_child_tags else "exact")
	elif tag_scope == "目标":
		var target_data: Variant = context.get("target_data", null)
		var target: Variant = target_data.target if target_data is GMTargetData else null
		if target != null and is_instance_valid(target) and target.has_meta("gm_tags"):
			var tags_value: Variant = target.get_meta("gm_tags")
			if tags_value is Array or tags_value is PackedStringArray:
				for value in tags_value:
					var tag := GMGameplayTag.normalize(str(value))
					var query := GMGameplayTag.normalize(tag_query)
					if tag == query or (include_child_tags and tag.begins_with(query + ".")): matched = true
	details["tag_query"] = tag_query
	details["scope"] = tag_scope
	return matched

func _evaluate_attribute(context: Dictionary, details: Dictionary) -> bool:
	var value: Variant = null
	var found := false
	var host: Variant = context.get("host", null)
	if host != null and host.get("attribute_set") != null:
		var attribute_set: Variant = host.get("attribute_set")
		if attribute_set.definitions.has(attribute_id):
			value = attribute_set.get_value(attribute_id, null)
			found = true
	var attributes: Variant = context.get("attributes", {})
	if not found and attributes is Dictionary and attributes.has(attribute_id):
		value = attributes[attribute_id]
		found = true
	if not found: return false
	details["attribute_id"] = attribute_id
	details["actual"] = value
	details["expected"] = attribute_expected_value
	details["comparison"] = attribute_comparison
	return _compare(value, attribute_expected_value, attribute_comparison)

func _evaluate_content(context: Dictionary, details: Dictionary) -> bool:
	var state: Variant = context.get("content_state", {})
	if state.is_empty() and context.get("event", null) is GMGameplayEvent:
		state = context.event.context.get("content_state", {})
	if not state is Dictionary: return false
	var exists: bool = state.has(content_state_key)
	var actual: Variant = state.get(content_state_key, null)
	details["key"] = content_state_key
	details["exists"] = exists
	details["actual"] = actual
	details["expected"] = content_expected_value
	match content_comparison:
		"存在": return exists
		"不存在": return not exists
		"不等于": return exists and actual != content_expected_value
		_: return exists and actual == content_expected_value

func _compare(actual: Variant, expected: Variant, comparison: String) -> bool:
	if comparison == "等于": return actual == expected or (actual is float and expected is int and is_equal_approx(actual, float(expected))) or (actual is int and expected is float and is_equal_approx(float(actual), expected))
	if comparison == "不等于": return not _compare(actual, expected, "等于")
	if typeof(actual) not in [TYPE_INT, TYPE_FLOAT] or typeof(expected) not in [TYPE_INT, TYPE_FLOAT]: return false
	match comparison:
		"大于": return float(actual) > float(expected)
		"大于等于": return float(actual) >= float(expected)
		"小于": return float(actual) < float(expected)
		"小于等于": return float(actual) <= float(expected)
	return false

func _expression_inputs(context: Dictionary) -> Dictionary:
	var inputs: Dictionary = {}
	var supplied: Variant = context.get("expression_inputs", {})
	if supplied is Dictionary: inputs.merge(supplied, true)
	var event: Variant = context.get("event", null)
	if event is GMGameplayEvent:
		inputs.merge(event.payload, true)
		inputs["event_tag"] = event.event_tag
		inputs["source_id"] = _stable_id(event.instigator)
		inputs["target_id"] = _stable_id(event.target)
	var attributes: Variant = context.get("attributes", {})
	if attributes is Dictionary:
		for key in attributes: inputs[str(key)] = attributes[key]
	var state: Variant = context.get("content_state", {})
	if state is Dictionary:
		for key in state: inputs[str(key)] = state[key]
	return inputs

func _expression_default(input_name: String) -> Variant:
	var normalized := input_name.to_lower()
	if normalized.contains("id") or normalized.contains("tag") or normalized.contains("name"): return ""
	return 0.0

func _validate_script() -> Dictionary:
	var path := _resolved_script_path()
	if path.is_empty(): return {"ok": false, "errors": [{"code": "script.path_missing", "reason_zh": "GDScript 条件没有附加脚本或脚本路径。", "line": 0}]}
	return GMEventScriptValidator.validate_condition_script(path)

func _resolved_script_path() -> String:
	if not script_path.strip_edges().is_empty(): return script_path.strip_edges()
	var script_value: Variant = get_script()
	if script_value is Script and str(script_value.resource_path) != "res://gm_runtime/events/gm_event_condition.gd": return str(script_value.resource_path)
	return ""

func _normalize_script_failure(value: Dictionary) -> Dictionary:
	if value.has("reason_zh") and not bool(value.get("ok", false)): return value
	return {"ok": false, "code": "event.condition_script_failed", "reason_zh": "事件条件 GDScript 返回了未通过结果。", "details": value.duplicate(true)}

func _evaluation_failure(value: Dictionary) -> Dictionary:
	return {"ok": false, "code": str(value.get("code", "event.condition_failed")), "reason_zh": str(value.get("reason_zh", "事件条件评估失败。")), "errors": value.get("errors", []), "details": value.duplicate(true), "condition_id": condition_id}

func _error(code: String, reason_zh: String, field: String) -> Dictionary:
	var row := _error_item(code, reason_zh, field)
	return {"ok": false, "code": code, "reason_zh": reason_zh, "errors": [row], "errors_zh": [reason_zh], "condition_id": condition_id}

func _error_item(code: String, reason_zh: String, field: String) -> Dictionary:
	return {"code": code, "reason_zh": reason_zh, "field": field, "condition_id": condition_id}

func _prefix_errors(value: Variant, prefix: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array: return result
	for raw in value:
		if raw is Dictionary:
			var row: Dictionary = raw.duplicate(true)
			row["field"] = "%s.%s" % [prefix, str(row.get("field", ""))]
			result.append(row)
	return result

func _messages(value: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for row in value: result.append(str(row.get("reason_zh", "事件条件无效。")))
	return result

func _stable_id(value: Object) -> String:
	if value == null or not is_instance_valid(value): return ""
	if value.has_method("get_business_id"): return str(value.get_business_id())
	if value.has_method("get_gm_id"): return str(value.get_gm_id())
	if value is Node and value.has_meta("gm_id"): return str(value.get_meta("gm_id"))
	return ""
