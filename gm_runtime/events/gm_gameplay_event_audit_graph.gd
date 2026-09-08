class_name GMGameplayEventAuditGraph
extends RefCounted

## GameplayEvent 图：只描述事件→条件→目标→能力/事件，不混入 Godot 信号。

static func build_from_triggers(values: Array, context: Dictionary = {}) -> Dictionary:
	var nodes: Array[Dictionary] = []
	var edges: Array[Dictionary] = []
	for raw in values:
		if not raw is GMGameplayEventTrigger: continue
		var trigger: GMGameplayEventTrigger = raw
		var event_node := "event:%s" % trigger.event_tag
		var trigger_node := "trigger:%s" % trigger.trigger_id
		var location := _location(context, trigger.trigger_id)
		_add_node(nodes, event_node, "event", trigger.event_tag, "GameplayEvent 事件标签", bool(location.get("ok", false)), str(location.get("reason_zh", "")))
		_add_node(nodes, trigger_node, "trigger", trigger.trigger_id, trigger.display_name_zh, bool(location.get("ok", false)), str(location.get("reason_zh", "")))
		_add_edge(edges, event_node, trigger_node, "event_to_trigger", "事件匹配", trigger.event_tag, "GameplayEvent", location)
		for index in trigger.conditions.size():
			var condition: Variant = trigger.conditions[index]
			if not condition is GMEventCondition: continue
			var condition_node := "%s:condition:%d" % [trigger_node, index]
			_add_node(nodes, condition_node, "condition", condition.condition_id, condition.condition_kind, bool(location.get("ok", false)), str(location.get("reason_zh", "")))
			_add_edge(edges, trigger_node, condition_node, "condition", "条件", condition.condition_kind, "GameplayEvent", location)
		if trigger.target_selector != null:
			var target_node := "%s:target" % trigger_node
			_add_node(nodes, target_node, "target", trigger.target_selector.selector_id, trigger.target_selector.display_name_zh, bool(location.get("ok", false)), str(location.get("reason_zh", "")))
			_add_edge(edges, trigger_node, target_node, "target_select", "目标选择", trigger.target_selector.selector_kind, "GameplayEvent", location)
		for index in trigger.actions.size():
			var action: Variant = trigger.actions[index]
			if not action is GMEventAction: continue
			var action_node := "%s:action:%d" % [trigger_node, index]
			var label: String = action.ability_id if not action.ability_id.is_empty() else action.event_tag
			_add_node(nodes, action_node, "ability" if action.action_kind == GMEventAction.ACTIVATE_ABILITY else "event_action", label, action.action_kind, bool(location.get("ok", false)), str(location.get("reason_zh", "")))
			_add_edge(edges, trigger_node, action_node, "action", action.action_kind, label, "GameplayEvent", location)
	return {"schema_version": "gm.task07.gameplay_event_graph.v1", "graph_kind": "GameplayEvent", "title_zh": "GameplayEvent→条件→目标→能力/事件图", "description_zh": "独立于 Godot 局部信号图；展示谁会被 GameplayEvent 触发。locatable 只有在编辑器真实资源定位 API 成功后才为 true。", "nodes": nodes, "edges": edges, "node_count": nodes.size(), "edge_count": edges.size(), "evidence": {"source": "GMEventTriggerRuntime.triggers", "gameplay_event_is_not_fact": true, "click_targets": edges.map(func(edge): return {"source_id": edge.source_id, "target_id": edge.target_id, "stable_resource_id": edge.stable_resource_id, "resolved_locator": edge.resolved_locator, "locatable": edge.locatable, "reason_zh": edge.reason_zh})}}

static func _location(context: Dictionary, stable_id: String) -> Dictionary:
	var locations: Variant = context.get("location_results", {})
	if locations is Dictionary and locations.has(stable_id):
		var result: Variant = locations[stable_id]
		if result is Dictionary: return result
	return {"ok": false, "resolved_locator": "", "reason_zh": "尚未通过编辑器真实 API 定位稳定资源 ID：%s。" % stable_id}

static func _add_node(nodes: Array[Dictionary], id: String, kind: String, business_id: String, label: String, locatable: bool, reason_zh: String) -> void:
	if nodes.any(func(row): return str(row.get("id", "")) == id): return
	nodes.append({"id": id, "kind": kind, "business_id": business_id, "label_zh": label, "locatable": locatable, "reason_zh": "" if locatable else reason_zh})

static func _add_edge(edges: Array[Dictionary], source_id: String, target_id: String, kind: String, label: String, reason: String, graph: String, location: Dictionary) -> void:
	var locatable := bool(location.get("ok", false))
	edges.append({"source_id": source_id, "target_id": target_id, "kind": kind, "label_zh": label, "reason_zh": reason if locatable else str(location.get("reason_zh", reason)), "graph": graph, "locatable": locatable, "stable_resource_id": str(location.get("stable_id", "")), "resolved_locator": str(location.get("resolved_locator", ""))})
