@tool
class_name GMSurfaceGraph
extends Resource

## The single authored logical graph for a planar 3D map.  It is a Resource
## so the formal editor can save/reopen it; `to_native()` is the save contract.

const SCHEMA := "gm.surface_graph.v1"
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const SURFACE_SCRIPT := preload("res://gm_runtime/map/3d/gm_surface_definition_3d.gd")
const CONNECTION_SCRIPT := preload("res://gm_runtime/map/3d/gm_surface_connection.gd")
const STABLE_DATA := preload("res://gm_runtime/simulation/gm_stable_data.gd")
const HEIGHT_AMBIGUITY_EPSILON := 0.05
const NATIVE_FIELDS := ["schema", "schema_version", "graph_id", "map_id", "display_name_zh", "surfaces", "connections"]

@export var graph_id: StringName = &""
@export var map_id: StringName = &""
@export var display_name_zh: String = ""
@export var surfaces: Array[GMSurfaceDefinition3D] = []
@export var connections: Array[GMSurfaceConnection] = []

func register_surface(surface: GMSurfaceDefinition3D) -> Dictionary:
	if surface == null: return _failure("surface.missing", "不能注册空Surface。")
	var candidate := surface.validate()
	if not candidate.ok: return {"ok": false, "code": "surface.invalid", "error_zh": "Surface定义无效，未写入图。", "errors": candidate.errors}
	if str(surface.map_id) != str(map_id): return _failure("surface.map_mismatch", "Surface所属地图与Graph不一致。")
	if resolve_surface(str(surface.surface_id)) != null: return _failure("surface.duplicate", "Surface稳定ID重复：%s" % surface.surface_id)
	surfaces.append(surface)
	canonicalize_order()
	return {"ok": true, "surface_id": str(surface.surface_id), "count": surfaces.size()}

func register_connection(connection: GMSurfaceConnection) -> Dictionary:
	if connection == null: return _failure("connection.missing", "不能注册空连接。")
	var candidate := connection.validate()
	if not candidate.ok: return {"ok": false, "code": "connection.invalid", "error_zh": "连接定义无效，未写入图。", "errors": candidate.errors}
	if resolve_connection(str(connection.connection_id)) != null: return _failure("connection.duplicate", "连接稳定ID重复：%s" % connection.connection_id)
	var endpoint := _validate_connection_endpoints(connection, {str(map_id): self})
	if not endpoint.ok: return endpoint
	connections.append(connection)
	canonicalize_order()
	return {"ok": true, "connection_id": str(connection.connection_id), "count": connections.size()}

func remove_surface(surface_id: String) -> Dictionary:
	var surface := resolve_surface(surface_id)
	if surface == null: return _failure("surface.missing", "找不到Surface：%s" % surface_id)
	for connection in connections:
		if str(connection.source_surface_id) == surface_id or str(connection.target_surface_id) == surface_id:
			return _failure("surface.referenced", "Surface仍被连接引用，拒绝删除：%s" % surface_id)
	surfaces.erase(surface)
	return {"ok": true, "surface_id": surface_id}

func remove_connection(connection_id: String) -> Dictionary:
	var connection := resolve_connection(connection_id)
	if connection == null: return _failure("connection.missing", "找不到连接：%s" % connection_id)
	connections.erase(connection)
	return {"ok": true, "connection_id": connection_id}

func resolve_surface(surface_id: String, requested_map_id: String = "") -> GMSurfaceDefinition3D:
	for surface in surfaces:
		if str(surface.surface_id) == surface_id and (requested_map_id.is_empty() or str(surface.map_id) == requested_map_id): return surface
	return null

func resolve_connection(connection_id: String) -> GMSurfaceConnection:
	for connection in connections:
		if str(connection.connection_id) == connection_id: return connection
	return null

func surface_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for surface in surfaces: result.append(str(surface.surface_id))
	result.sort()
	return result

func find_surface_candidates(logical: Vector2, agent_profile: String = "default") -> Array[GMSurfaceDefinition3D]:
	var result: Array[GMSurfaceDefinition3D] = []
	for surface in surfaces:
		if surface.contains_logical(logical) and surface.supports_agent(agent_profile): result.append(surface)
	result.sort_custom(func(left, right):
		if not is_equal_approx(left.world_height_at(logical), right.world_height_at(logical)):
			return left.world_height_at(logical) < right.world_height_at(logical)
		return str(left.surface_id) < str(right.surface_id)
	)
	return result

func validate(known_graphs: Array = []) -> Dictionary:
	var errors: Array[Dictionary] = []
	if str(graph_id).is_empty() or not PLANAR_POSITION.is_valid_stable_id(str(graph_id)): errors.append(_error("graph.id_invalid", "Surface Graph必须是非空稳定ID。", "graph_id"))
	if str(map_id).is_empty() or not PLANAR_POSITION.is_valid_stable_id(str(map_id)): errors.append(_error("graph.map_id_invalid", "Surface Graph必须引用非空稳定地图ID。", "map_id"))
	var graph_by_map: Dictionary = {str(map_id): self}
	for other in known_graphs:
		# Reconfiguring an existing map validates the candidate against itself;
		# the previous registered revision must not shadow it by map_id.
		if other is GMSurfaceGraph and other != self and str(other.map_id) != str(map_id):
			graph_by_map[str(other.map_id)] = other
	var surface_by_id: Dictionary = {}
	for surface in surfaces:
		if surface == null:
			errors.append(_error("surface.null", "Surface列表不能包含空项。", "surfaces")); continue
		var surface_id := str(surface.surface_id)
		if surface_by_id.has(surface_id): errors.append(_error("surface.duplicate", "Surface稳定ID重复：%s" % surface_id, "surfaces"))
		surface_by_id[surface_id] = surface
		var surface_result := surface.validate()
		for row in surface_result.get("errors", []): errors.append(row)
		if str(surface.map_id) != str(map_id): errors.append(_error("surface.map_mismatch", "Surface不能属于另一个地图：%s" % surface_id, "surfaces"))
	for left_index in surfaces.size():
		var left := surfaces[left_index]
		if left == null: continue
		for right_index in range(left_index + 1, surfaces.size()):
			var right := surfaces[right_index]
			if right == null or not _polygons_overlap(left.boundary, right.boundary): continue
			if _same_height_in_overlap(left, right):
				errors.append(_error("surface.overlap_ambiguous", "可行走Surface在同一高度发生重叠，采样会产生歧义：%s / %s" % [left.surface_id, right.surface_id], "surfaces"))
	var connection_ids: Dictionary = {}
	for connection in connections:
		if connection == null:
			errors.append(_error("connection.null", "连接列表不能包含空项。", "connections")); continue
		var connection_id := str(connection.connection_id)
		if connection_ids.has(connection_id): errors.append(_error("connection.duplicate", "连接稳定ID重复：%s" % connection_id, "connections"))
		connection_ids[connection_id] = true
		var connection_result := connection.validate()
		for row in connection_result.get("errors", []): errors.append(row)
		var endpoint := _validate_connection_endpoints(connection, graph_by_map)
		if not endpoint.ok: errors.append_array(endpoint.get("errors", [_error(str(endpoint.get("code", "connection.invalid")), str(endpoint.get("error_zh", "连接出口校验失败。")), "connections")]))
	return {"ok": errors.is_empty(), "code": "surface_graph.valid" if errors.is_empty() else "surface_graph.invalid", "errors": errors, "errors_zh": errors.map(func(row): return row.get("error_zh", "")), "graph_id": str(graph_id), "map_id": str(map_id), "surface_count": surfaces.size(), "connection_count": connections.size()}

func to_native() -> Dictionary:
	var surface_values: Array = []
	for surface in _ordered_surfaces(): surface_values.append(surface.to_native())
	var connection_values: Array = []
	for connection in _ordered_connections(): connection_values.append(connection.to_native())
	return {"schema": SCHEMA, "schema_version": 1, "graph_id": str(graph_id), "map_id": str(map_id), "display_name_zh": display_name_zh, "surfaces": surface_values, "connections": connection_values}

static func from_native(value: Variant) -> Dictionary:
	if not value is Dictionary: return _failure("graph.native_type_invalid", "Surface Graph纯值必须是Dictionary。")
	var source: Dictionary = value
	var shape := _validate_native_fields(source)
	if not shape.ok: return shape
	if str(source.get("schema", "")) != SCHEMA:
		return _failure("graph.schema_invalid", "Surface Graph Schema标识无效。")
	var schema_version := STABLE_DATA.normalize_schema_version(source.get("schema_version"))
	if not schema_version.ok:
		return _failure("graph.schema_version_invalid", "Surface Graph Schema版本必须是整数1。")
	var graph := GMSurfaceGraph.new()
	graph.graph_id = str(source.get("graph_id", ""))
	graph.map_id = str(source.get("map_id", ""))
	graph.display_name_zh = str(source.get("display_name_zh", ""))
	var raw_surfaces: Variant = source.get("surfaces", [])
	var raw_connections: Variant = source.get("connections", [])
	if not raw_surfaces is Array or not raw_connections is Array: return _failure("graph.collection_invalid", "Surface Graph的Surface/连接必须是数组。")
	for raw_surface in raw_surfaces:
		var parsed_surface := SURFACE_SCRIPT.from_native(raw_surface)
		if not parsed_surface.ok: return parsed_surface
		graph.surfaces.append(parsed_surface.surface)
	for raw_connection in raw_connections:
		var parsed_connection := CONNECTION_SCRIPT.from_native(raw_connection)
		if not parsed_connection.ok: return parsed_connection
		graph.connections.append(parsed_connection.connection)
	graph.canonicalize_order()
	var validation := graph.validate()
	if not validation.ok: return validation
	return {"ok": true, "graph": graph, "value": graph.to_native()}

func copy_graph() -> GMSurfaceGraph:
	# Godot 4.6 Resource.duplicate(true) does not reliably preserve every
	# element of typed Resource arrays after incremental authoring.  The native
	# contract is already the canonical deep-copy boundary for this resource.
	var parsed: Dictionary = from_native(to_native())
	return parsed.get("graph", null) as GMSurfaceGraph if parsed.ok else null

## Canonical order is part of the public graph value contract.  It is applied
## at mutable ingress and by serialization, so Resources, Native values and
## JSON reloads converge even when declarations arrive in reverse order.
func canonicalize_order() -> void:
	surfaces.sort_custom(func(left, right): return str(left.surface_id) < str(right.surface_id))
	connections.sort_custom(func(left, right): return str(left.connection_id) < str(right.connection_id))

func _ordered_surfaces() -> Array:
	var result: Array = []
	for surface in surfaces: result.append(surface)
	result.sort_custom(func(left, right): return str(left.surface_id) < str(right.surface_id))
	return result

func _ordered_connections() -> Array:
	var result: Array = []
	for connection in connections: result.append(connection)
	result.sort_custom(func(left, right): return str(left.connection_id) < str(right.connection_id))
	return result

func stable_digest() -> String:
	return GMStableData.digest(to_native())

func _validate_connection_endpoints(connection: GMSurfaceConnection, graph_by_map: Dictionary) -> Dictionary:
	var errors: Array[Dictionary] = []
	var source_graph: GMSurfaceGraph = graph_by_map.get(str(connection.source_map_id), null)
	var target_graph: GMSurfaceGraph = graph_by_map.get(str(connection.target_map_id), null)
	if source_graph == null: errors.append(_connection_error(connection, "connection.source_map_missing", "连接源地图不存在。"))
	if target_graph == null: errors.append(_connection_error(connection, "connection.target_map_missing", "连接目标地图不存在。"))
	if source_graph != null:
		var source_surface := source_graph.resolve_surface(str(connection.source_surface_id))
		if source_surface == null: errors.append(_connection_error(connection, "connection.source_surface_missing", "连接源Surface不存在。"))
		elif not source_surface.contains_logical(connection.source_exit): errors.append(_connection_error(connection, "connection.source_exit_invalid", "连接源出口必须位于源Surface边界内。"))
	if target_graph != null:
		var target_surface := target_graph.resolve_surface(str(connection.target_surface_id))
		if target_surface == null: errors.append(_connection_error(connection, "connection.target_surface_missing", "连接目标Surface不存在。"))
		elif not target_surface.contains_logical(connection.target_entry): errors.append(_connection_error(connection, "connection.target_entry_invalid", "连接目标入口必须位于目标Surface边界内。"))
	if source_graph != null and target_graph != null:
		var source_surface := source_graph.resolve_surface(str(connection.source_surface_id))
		var target_surface := target_graph.resolve_surface(str(connection.target_surface_id))
		if source_surface != null and target_surface != null:
			var shared := false
			for profile in connection.agent_profiles:
				if source_surface.supports_agent(str(profile)) and target_surface.supports_agent(str(profile)): shared = true; break
			if not shared: errors.append(_connection_error(connection, "connection.agent_profile_mismatch", "连接两端没有共同的可行Agent Profile。"))
	if not errors.is_empty(): return {"ok": false, "code": "connection.endpoint_invalid", "error_zh": "连接出口或目标入口校验失败。", "errors": errors}
	return {"ok": true}

static func _polygons_overlap(left: PackedVector2Array, right: PackedVector2Array) -> bool:
	if left.size() < 3 or right.size() < 3: return false
	for point in left:
		if Geometry2D.is_point_in_polygon(point, right): return true
	for point in right:
		if Geometry2D.is_point_in_polygon(point, left): return true
	for left_index in left.size():
		var a := left[left_index]
		var b := left[(left_index + 1) % left.size()]
		for right_index in right.size():
			var c := right[right_index]
			var d := right[(right_index + 1) % right.size()]
			if _segments_intersect(a, b, c, d): return true
	return false

static func _same_height_in_overlap(left: GMSurfaceDefinition3D, right: GMSurfaceDefinition3D) -> bool:
	var probes: Array[Vector2] = []
	for point in left.boundary:
		if right.contains_logical(point): probes.append(point)
	for point in right.boundary:
		if left.contains_logical(point): probes.append(point)
	if probes.is_empty():
		var center := (left.boundary[0] + right.boundary[0]) * 0.5
		if left.contains_logical(center) and right.contains_logical(center): probes.append(center)
	for point in probes:
		if absf(left.world_height_at(point) - right.world_height_at(point)) <= HEIGHT_AMBIGUITY_EPSILON: return true
	return false

static func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab := b - a
	var cd := d - c
	var denominator := ab.cross(cd)
	if is_zero_approx(denominator): return false
	var ac := c - a
	var t := ac.cross(cd) / denominator
	var u := ac.cross(ab) / denominator
	return t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0

static func _connection_error(connection: GMSurfaceConnection, code: String, message: String) -> Dictionary:
	return {"code": code, "error_zh": message, "field": "connections", "connection_id": str(connection.connection_id)}

static func _error(code: String, message: String, field: String) -> Dictionary:
	return {"code": code, "error_zh": message, "field": field}

static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": message}

static func _validate_native_fields(source: Dictionary) -> Dictionary:
	for field in NATIVE_FIELDS:
		if not source.has(field):
			return _failure("graph.schema_field_missing", "Surface Graph缺少必需字段：%s。" % field)
	for raw_key in source.keys():
		if not NATIVE_FIELDS.has(str(raw_key)):
			return _failure("graph.schema_field_unknown", "Surface Graph包含未知字段：%s。" % raw_key)
	return {"ok": true}
