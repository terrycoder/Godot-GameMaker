class_name GMEventTriggerRuntime
extends RefCounted

## 接入 GMAbilitySystemHost.gameplay_event 的唯一事件触发运行时。
##
## 这不是第二条事件总线：它只监听 Host 已有的 GameplayEvent signal，并
## 把声明式触发器翻译成正式能力请求或再次调用 Host.emit_gameplay_event。

var host: Object
var triggers: Dictionary = {}
var dispatch_log: Array[Dictionary] = []
var blocked_log: Array[Dictionary] = []
var dispatch_results_by_id: Dictionary = {}
var _signal_connected: bool = false
var script_registry: GMEventScriptRegistry

func _init(p_host: Object = null) -> void:
	host = p_host
	script_registry = GMEventScriptRegistry.new()
	_attach_to_host()

func register_trigger(trigger: GMGameplayEventTrigger) -> Dictionary:
	if trigger == null: return {"ok": false, "code": "event.trigger_missing", "reason_zh": "不能注册空 Gameplay Event 触发器。"}
	var validation := trigger.validate_definition(host)
	if not validation.ok: return {"ok": false, "code": "event.trigger_invalid", "reason_zh": "Gameplay Event 触发器注册被阻断。", "errors": validation.errors, "errors_zh": validation.errors_zh, "trigger_id": trigger.trigger_id}
	if triggers.has(trigger.trigger_id) and triggers[trigger.trigger_id] != trigger:
		return {"ok": false, "code": "event.trigger_duplicate", "reason_zh": "Gameplay Event 触发器 ID 重复：%s。" % trigger.trigger_id, "trigger_id": trigger.trigger_id}
	triggers[trigger.trigger_id] = trigger
	return {"ok": true, "trigger_id": trigger.trigger_id, "registered": true, "trigger": trigger.summary()}

func unregister_trigger(trigger_id: String) -> Dictionary:
	if not triggers.has(trigger_id): return {"ok": false, "code": "event.trigger_missing", "reason_zh": "找不到 Gameplay Event 触发器：%s。" % trigger_id, "trigger_id": trigger_id}
	triggers.erase(trigger_id)
	return {"ok": true, "trigger_id": trigger_id, "unregistered": true}

func validate_all(context: Dictionary = {}) -> Dictionary:
	var rows: Array[Dictionary] = []
	var errors: Array[Dictionary] = []
	for trigger_id in _sorted_trigger_ids():
		var trigger: GMGameplayEventTrigger = triggers[trigger_id]
		var row := trigger.validate_definition(host, context)
		rows.append({"trigger_id": trigger_id, "validation": row})
		if not row.ok: errors.append_array(row.get("errors", []))
	return {"ok": errors.is_empty(), "code": "event.runtime_valid" if errors.is_empty() else "event.runtime_invalid", "triggers": rows, "errors": errors, "errors_zh": _messages(errors)}

func dispatch(event: GMGameplayEvent) -> Dictionary:
	if event == null: return {"ok": false, "code": "event.missing", "reason_zh": "不能分发空 GameplayEvent。"}
	var stack: Array = event.context.get("trigger_stack", []) if event.context.get("trigger_stack", []) is Array else []
	var context := {"host": host, "event": event, "trigger_stack": stack, "cause_chain": event.context.get("cause_chain", {})}
	var runtime_context: Variant = host.get("runtime_context") if host != null and host.has_method("get") else null
	if runtime_context != null and is_instance_valid(runtime_context) and runtime_context is Node and runtime_context.has_meta("gm_entity_registry"):
		var registry_value: Variant = runtime_context.get_meta("gm_entity_registry")
		if registry_value is Dictionary: context["entity_registry"] = registry_value
	var rows: Array[Dictionary] = []
	var ok := true
	for trigger_id in _sorted_trigger_ids():
		var trigger: GMGameplayEventTrigger = triggers[trigger_id]
		if not trigger.matches(event): continue
		var row: Dictionary = trigger.process(event, host, context)
		rows.append(row)
		var logged := {"event": event.to_dict(), "trigger_id": trigger_id, "result": row.duplicate(true), "trigger_chain": stack.duplicate(true)}
		dispatch_log.append(logged)
		if not row.ok:
			ok = false
			blocked_log.append(logged)
	var result := {"ok": ok, "event": event.to_dict(), "triggered": rows, "trigger_count": rows.size(), "dispatch_depth": event.dispatch_depth, "event_dispatch_id": event.dispatch_id}
	dispatch_results_by_id[event.dispatch_id] = result.duplicate(true)
	return result

func result_for_event(event: GMGameplayEvent) -> Dictionary:
	if event == null: return {}
	var result: Variant = dispatch_results_by_id.get(event.dispatch_id, {})
	return result.duplicate(true) if result is Dictionary else {}

func find_script_usage(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var normalized := path.strip_edges()
	for trigger_id in _sorted_trigger_ids():
		var trigger: GMGameplayEventTrigger = triggers[trigger_id]
		if trigger.target_selector != null and trigger.target_selector._resolved_script_path() == normalized:
			result.append({"trigger_id": trigger_id, "kind": "GMTargetSelector", "field": "target_selector", "path": normalized, "locatable": true})
		if trigger.handler != null and trigger.handler._resolved_script_path() == normalized:
			result.append({"trigger_id": trigger_id, "kind": "GMEventHandler", "field": "handler", "path": normalized, "locatable": true})
		for index in trigger.conditions.size():
			var condition: Variant = trigger.conditions[index]
			if condition is GMEventCondition and condition._resolved_script_path() == normalized:
				result.append({"trigger_id": trigger_id, "kind": "GMEventCondition", "field": "conditions[%d]" % index, "path": normalized, "locatable": true})
	return result

func reload_scripts(root: String, expected_kind: String = "") -> Dictionary:
	var result := script_registry.reload_and_discover(root, expected_kind)
	result["usage_locations"] = {}
	for path in script_registry.discovered.keys(): result["usage_locations"][path] = find_script_usage(str(path))
	return result

func snapshot() -> Dictionary:
	var trigger_rows: Array = []
	for trigger_id in _sorted_trigger_ids():
		var trigger: GMGameplayEventTrigger = triggers[trigger_id]
		trigger_rows.append(trigger.summary())
	return {"runtime_kind": "GMEventTriggerRuntime", "single_gameplay_event_source": true, "signal_source": "GMAbilitySystemHost.gameplay_event", "trigger_count": triggers.size(), "triggers": trigger_rows, "dispatch_count": dispatch_log.size(), "blocked_count": blocked_log.size(), "dispatch_log": dispatch_log.duplicate(true), "blocked_log": blocked_log.duplicate(true), "last_dispatch_count": dispatch_results_by_id.size(), "script_registry": script_registry.snapshot() if script_registry != null else {}}

func event_graph() -> Dictionary:
	return GMGameplayEventAuditGraph.build_from_triggers(triggers.values())

func detach() -> void:
	if _signal_connected and host != null and is_instance_valid(host) and host.has_signal("gameplay_event") and host.is_connected("gameplay_event", Callable(self, "_on_gameplay_event")):
		host.disconnect("gameplay_event", Callable(self, "_on_gameplay_event"))
	_signal_connected = false

func _attach_to_host() -> void:
	if host == null or not is_instance_valid(host) or not host.has_signal("gameplay_event"): return
	var callable := Callable(self, "_on_gameplay_event")
	if not host.is_connected("gameplay_event", callable): host.connect("gameplay_event", callable)
	_signal_connected = true

func _on_gameplay_event(event: GMGameplayEvent) -> void:
	dispatch(event)

func _sorted_trigger_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw in triggers.keys(): ids.append(str(raw))
	ids.sort()
	return ids

func _messages(errors: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for row in errors: result.append(str(row.get("reason_zh", "事件触发运行时无效。")))
	return result
