@tool
class_name GMSignalAudit
extends RefCounted

## Godot 局部信号图。该图严格不含 GameplayEvent、FactEvent 或能力边。

static func build(connections: Array = [], context: Dictionary = {}) -> Dictionary:
	var nodes: Array[Dictionary] = []
	var edges: Array[Dictionary] = []
	for raw in connections:
		if not raw is GMSignalConnection: continue
		var connection: GMSignalConnection = raw
		var source_id := connection.source_business_id if not connection.source_business_id.is_empty() else "source:%s" % connection.source_locator
		var target_id := connection.target_business_id if not connection.target_business_id.is_empty() else "target:%s" % connection.target_locator
		var source_location := _location(context, connection.source_business_id, connection.source_locator)
		var target_location := _location(context, connection.target_business_id, connection.target_locator)
		var source_locator := str(source_location.get("resolved_locator", connection.source_locator))
		var target_locator := str(target_location.get("resolved_locator", connection.target_locator))
		var endpoints_locatable: bool = bool(source_location.get("ok", false)) and bool(target_location.get("ok", false))
		var endpoint_reason := "" if endpoints_locatable else _location_reason(source_location, target_location)
		_add_node(nodes, source_id, "signal_source", connection.source_business_id, source_locator, bool(source_location.get("ok", false)), str(source_location.get("reason_zh", "")))
		_add_node(nodes, target_id, "callable_target", connection.target_business_id, target_locator, bool(target_location.get("ok", false)), str(target_location.get("reason_zh", "")))
		edges.append({"connection_id": connection.connection_id, "source_id": source_id, "target_id": target_id, "signal_name": connection.signal_name, "method_name": connection.method_name, "kind": "GodotSignal→Callable", "persistence_kind": connection.persistence_kind, "persistent": connection.persistence_kind == "persistent", "runtime_dynamic": connection.persistence_kind == "runtime_dynamic", "source_locator": source_locator, "target_locator": target_locator, "locatable": endpoints_locatable, "reason_zh": endpoint_reason, "evidence": "谁监听/谁触发的局部通信；定位结果来自 EditorSelection/Inspector"})
	return {"schema_version": "gm.task07.godot_signal_graph.v1", "graph_kind": "GodotLocalSignal", "title_zh": "Godot局部信号图", "description_zh": "只描述场景实例内的 Godot signal→Callable 局部通信，不是 GameplayEvent 或 Committed Fact 图。locatable 只有在真实 EditorSelection/Inspector 定位成功后才为 true。", "nodes": nodes, "edges": edges, "node_count": nodes.size(), "edge_count": edges.size(), "evidence": {"signal_graph_is_not_gameplay_event": true, "connection_count": edges.size(), "click_targets": edges.map(func(edge): return {"connection_id": edge.connection_id, "stable_source_id": edge.source_id, "stable_target_id": edge.target_id, "source_locator": edge.source_locator, "target_locator": edge.target_locator, "locatable": edge.locatable, "reason_zh": edge.reason_zh})}}

static func validate_separation(local_graph: Dictionary, event_graph: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if str(local_graph.get("graph_kind", "")) != "GodotLocalSignal": errors.append("局部信号图 graph_kind 错误。")
	if str(event_graph.get("graph_kind", "")) != "GameplayEvent": errors.append("GameplayEvent 图 graph_kind 错误。")
	if str(local_graph.get("title_zh", "")) == str(event_graph.get("title_zh", "")): errors.append("两类审计图标题不可相同。")
	for edge in local_graph.get("edges", []):
		if edge is Dictionary and str(edge.get("kind", "")).contains("GameplayEvent"): errors.append("Godot 局部信号图混入 GameplayEvent 边。")
	for edge in event_graph.get("edges", []):
		if edge is Dictionary and str(edge.get("kind", "")).contains("GodotSignal"): errors.append("GameplayEvent 图混入 Godot signal 边。")
	return {"ok": errors.is_empty(), "errors": errors, "errors_zh": errors, "local_graph_kind": local_graph.get("graph_kind", ""), "event_graph_kind": event_graph.get("graph_kind", "")}

static func _location(context: Dictionary, stable_id: String, fallback_locator: String = "") -> Dictionary:
	var locations: Variant = context.get("location_results", {})
	if locations is Dictionary and locations.has(stable_id):
		var result: Variant = locations[stable_id]
		if result is Dictionary: return result
	if stable_id.is_empty():
		return {"ok": false, "resolved_locator": fallback_locator, "reason_zh": "图节点缺少稳定业务 ID，不能执行真实定位。"}
	return {"ok": false, "resolved_locator": fallback_locator, "reason_zh": "尚未通过 EditorSelection/Inspector 实际定位稳定 ID：%s。" % stable_id}

static func _location_reason(source: Dictionary, target: Dictionary) -> String:
	var source_reason := str(source.get("reason_zh", ""))
	if not source_reason.is_empty(): return source_reason
	return str(target.get("reason_zh", "信号连接端点尚未完成真实定位。"))

static func _add_node(nodes: Array[Dictionary], id: String, kind: String, business_id: String, locator: String, locatable: bool, reason_zh: String) -> void:
	if nodes.any(func(row): return str(row.get("id", "")) == id): return
	nodes.append({"id": id, "kind": kind, "business_id": business_id, "locator": locator, "locatable": locatable, "reason_zh": "" if locatable else reason_zh})
