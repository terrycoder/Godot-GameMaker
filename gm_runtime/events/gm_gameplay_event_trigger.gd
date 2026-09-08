@tool
class_name GMGameplayEventTrigger
extends Resource

## Gameplay Event Trigger 资源。
##
## 一条规则固定为：事件 Schema/Tag → 条件组合 → 目标选择 → 能力/事件动作。
## 运行时只向 GMEventTriggerRuntime 注册，事实仍由既有能力和领域事务提交。

@export_group("触发器身份")
@export var trigger_id: String = ""
@export var display_name_zh: String = "Gameplay Event 触发器"
@export var enabled: bool = true
@export var event_tag: String = ""
@export var event_schema: Dictionary = {}

@export_group("条件")
@export_enum("全部满足", "任一满足") var condition_operator: String = "全部满足"
@export var conditions: Array = []
@export var max_condition_depth: int = 16

@export_group("目标")
@export var target_selector: GMTargetSelector

@export_group("处理器与动作")
@export var handler: GMEventHandler
@export var actions: Array = []

func matches(event: GMGameplayEvent) -> bool:
	return enabled and event != null and event.matches_tag(event_tag, true)

func validate_definition(host: Object = null, context: Dictionary = {}) -> Dictionary:
	var errors: Array[Dictionary] = []
	if trigger_id.strip_edges().is_empty(): errors.append(_error("event.trigger_id_missing", "Gameplay Event 触发器缺少稳定触发器 ID。", "trigger_id"))
	if event_tag.strip_edges().is_empty(): errors.append(_error("event.trigger_tag_missing", "Gameplay Event 触发器缺少事件标签。", "event_tag"))
	elif not (event_tag.begins_with("gm.event.") or event_tag.contains(".event.")): errors.append(_error("event.trigger_tag_invalid", "Gameplay Event 触发器标签必须使用事件命名空间：%s。" % event_tag, "event_tag"))
	if not event_schema.is_empty():
		var required_schema: Variant = event_schema.get("required", event_schema)
		var optional_schema: Variant = event_schema.get("optional", {})
		if not required_schema is Dictionary: errors.append(_error("event.schema_invalid", "触发器事件 Schema 的 required 必须是 Dictionary。", "event_schema.required"))
		if not optional_schema is Dictionary: errors.append(_error("event.schema_invalid", "触发器事件 Schema 的 optional 必须是 Dictionary。", "event_schema.optional"))
	if condition_operator not in ["全部满足", "任一满足"]: errors.append(_error("event.condition_operator_invalid", "触发器条件组合操作符无效：%s。" % condition_operator, "condition_operator"))
	if conditions.is_empty() and actions.is_empty(): errors.append(_error("event.trigger_empty", "Gameplay Event 触发器至少需要条件或动作。", "actions"))
	var condition_context := context.duplicate(true)
	condition_context["validate_expression_values"] = false
	for index in conditions.size():
		var condition: Variant = conditions[index]
		if condition == null or not condition is GMEventCondition:
			errors.append(_error("event.condition_invalid", "触发器第 %d 项不是 GMEventCondition。" % index, "conditions[%d]" % index))
			continue
		condition.max_depth = maxi(max_condition_depth, 1)
		var condition_check: Dictionary = condition.validate_definition(condition_context)
		if not condition_check.ok: errors.append_array(_prefix_errors(condition_check.get("errors", []), "conditions[%d]" % index))
	if target_selector != null:
		var selector_check: Dictionary = target_selector.validate_definition(context)
		if not selector_check.ok: errors.append_array(_prefix_errors(selector_check.get("errors", []), "target_selector"))
	for index in actions.size():
		var action: Variant = actions[index]
		if action == null or not action is GMEventAction:
			errors.append(_error("event.action_invalid", "触发器第 %d 项不是 GMEventAction。" % index, "actions[%d]" % index))
			continue
		var action_check: Dictionary = action.validate_definition(context)
		if not action_check.ok: errors.append_array(_prefix_errors(action_check.get("errors", []), "actions[%d]" % index))
		if host != null and action.action_kind == GMEventAction.ACTIVATE_ABILITY:
			var ability_id: String = action.ability_id
			if ability_id.is_empty() and not action.ability_tag.is_empty():
				var probe := GMAbilityActivationRequest.new(host, "", action.ability_tag, null, {}, "event_trigger_validation", {}, "")
				ability_id = host.resolve_ability_id(probe) if host.has_method("resolve_ability_id") else ""
			if ability_id.is_empty() or not host.has_ability(ability_id): errors.append(_error("event.ability_missing", "触发器动作引用的能力不存在或未授予：%s。" % (action.ability_id if not action.ability_id.is_empty() else action.ability_tag), "actions[%d].ability_id" % index))
	if handler != null:
		var handler_check: Dictionary = handler.validate_definition(context)
		if not handler_check.ok: errors.append_array(_prefix_errors(handler_check.get("errors", []), "handler"))
	return {"ok": errors.is_empty(), "code": "event.trigger_valid" if errors.is_empty() else "event.trigger_invalid", "errors": errors, "errors_zh": _messages(errors), "trigger_id": trigger_id, "event_tag": event_tag}

func process(event: GMGameplayEvent, host: Object, runtime_context: Dictionary = {}) -> Dictionary:
	if not matches(event): return {"ok": true, "matched": false, "trigger_id": trigger_id, "event_tag": event_tag}
	var payload_check: Dictionary = event.validate_payload(event_schema) if event != null else {"ok": false, "code": "event.missing", "reason_zh": "触发器没有收到 GameplayEvent。"}
	if not payload_check.ok: return {"ok": false, "matched": true, "code": "event.schema_blocked", "reason_zh": "GameplayEvent 载荷不符合触发器 Schema，已阻断事件链。", "schema": payload_check, "trigger_id": trigger_id}
	var stack: Array = runtime_context.get("trigger_stack", []) if runtime_context.get("trigger_stack", []) is Array else []
	if stack.has(trigger_id):
		var cycle := stack.duplicate(true)
		cycle.append(trigger_id)
		return {"ok": false, "matched": true, "code": "event.recursion_cycle", "reason_zh": "Gameplay Event 触发器检测到递归事件链：%s。" % " → ".join(cycle), "trigger_id": trigger_id, "chain": cycle}
	var context := runtime_context.duplicate(true)
	context["event"] = event
	context["host"] = host
	context["trigger_id"] = trigger_id
	context["attributes"] = _attributes_from_host(host)
	context["content_state"] = _content_state(event, runtime_context)
	var next_stack := stack.duplicate(true)
	next_stack.append(trigger_id)
	context["trigger_stack"] = next_stack
	var definition_check := validate_definition(host, context)
	if not definition_check.ok: return {"ok": false, "matched": true, "code": "event.trigger_invalid", "reason_zh": "Gameplay Event 触发器验证失败，已阻断执行。", "errors": definition_check.errors, "trigger_id": trigger_id}
	var condition_rows: Array[Dictionary] = []
	for condition in conditions:
		var condition_result: Dictionary = condition.evaluate(context)
		condition_rows.append(condition_result)
		if not condition_result.ok: return {"ok": false, "matched": true, "code": "event.condition_blocked", "reason_zh": "Gameplay Event 条件评估失败，已阻断动作。", "conditions": condition_rows, "errors": condition_result.get("errors", []), "trigger_id": trigger_id}
	var matched_conditions := condition_rows.map(func(row): return bool(row.get("matched", false)))
	var conditions_pass := matched_conditions.all(func(value): return bool(value)) if condition_operator == "全部满足" else matched_conditions.any(func(value): return bool(value))
	if conditions.is_empty(): conditions_pass = true
	if not conditions_pass: return {"ok": true, "matched": true, "conditions_passed": false, "conditions": condition_rows, "trigger_id": trigger_id, "actions": []}
	var handler_result: Dictionary = {"ok": true, "handled": false}
	if handler != null:
		handler_result = handler.handle_event(event, context)
		if not handler_result.ok: return {"ok": false, "matched": true, "code": "event.handler_blocked", "reason_zh": "Gameplay Event 处理器失败，已阻断动作。", "handler": handler_result, "conditions": condition_rows, "trigger_id": trigger_id}
	var target_result: Dictionary = {"ok": true, "targets": [null], "source": "none"}
	var needs_target := _actions_need_target()
	if target_selector != null:
		target_result = target_selector.select(event, context)
		if not target_result.ok: return {"ok": false, "matched": true, "code": str(target_result.get("code", "target.missing")), "reason_zh": str(target_result.get("reason_zh", "目标选择失败。")), "target": target_result, "conditions": condition_rows, "trigger_id": trigger_id}
	elif needs_target:
		return {"ok": false, "matched": true, "code": "target.selector_missing", "reason_zh": "触发器动作需要目标，但没有配置 GMTargetSelector。", "conditions": condition_rows, "trigger_id": trigger_id}
	var targets: Array = target_result.get("targets", [null]) if target_result.get("targets", [null]) is Array else [null]
	if targets.is_empty() and needs_target: return {"ok": false, "matched": true, "code": "target.missing", "reason_zh": "目标选择器返回空目标，已阻断能力或事件动作。", "conditions": condition_rows, "trigger_id": trigger_id}
	var action_rows: Array[Dictionary] = []
	for action in actions:
		for target in targets:
			var action_result: Dictionary = action.execute(host, event, trigger_id, target, context)
			action_rows.append(action_result)
			if not action_result.ok:
				return {"ok": false, "matched": true, "conditions_passed": true, "conditions": condition_rows, "handler": handler_result, "target": _target_snapshot(target), "actions": action_rows, "code": str(action_result.get("code", "event.action_blocked")), "reason_zh": str(action_result.get("reason_zh", "事件动作执行失败。")), "trigger_id": trigger_id}
	return {"ok": true, "matched": true, "conditions_passed": true, "conditions": condition_rows, "handler": handler_result, "target": _target_snapshot(targets[0]) if not targets.is_empty() else {}, "targets": targets.map(func(value): return _target_snapshot(value)), "actions": action_rows, "trigger_id": trigger_id, "event": event.to_dict(), "cause_chain": context.get("cause_chain", {})}

func summary() -> Dictionary:
	var condition_rows: Array = []
	for condition in conditions:
		if condition is GMEventCondition: condition_rows.append(condition.summary())
	var action_rows: Array = []
	for action in actions:
		if action is GMEventAction: action_rows.append(action.summary())
	return {"trigger_id": trigger_id, "display_name_zh": display_name_zh, "enabled": enabled, "event_tag": event_tag, "event_schema": event_schema.duplicate(true), "condition_operator": condition_operator, "conditions": condition_rows, "target_selector": target_selector.summary() if target_selector != null else {}, "handler": handler.summary() if handler != null else {}, "actions": action_rows}

func _actions_need_target() -> bool:
	for action in actions:
		if action is GMEventAction and action.target_required: return true
	return false

func _attributes_from_host(host: Object) -> Dictionary:
	if host == null or not is_instance_valid(host): return {}
	var attribute_set: Variant = host.get("attribute_set")
	return attribute_set.snapshot() if attribute_set != null and attribute_set.has_method("snapshot") else {}

func _content_state(event: GMGameplayEvent, context: Dictionary) -> Dictionary:
	var value: Variant = context.get("content_state", {})
	if value is Dictionary and not value.is_empty(): return value.duplicate(true)
	if event != null and event.context.get("content_state", {}) is Dictionary: return event.context.get("content_state", {}).duplicate(true)
	return {}

func _target_snapshot(target: Variant) -> Dictionary:
	if target is GMTargetData: return target.to_dict()
	return {}

func _error(code: String, reason_zh: String, field: String) -> Dictionary:
	return {"code": code, "reason_zh": reason_zh, "field": field, "trigger_id": trigger_id}

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
	for row in value: result.append(str(row.get("reason_zh", "Gameplay Event 触发器无效。")))
	return result
