@tool
class_name GMMapBackend3D
extends "res://gm_runtime/map/gm_map_backend.gd"

## Runtime-owned registry for authored planar 3D Surface Graphs.
##
## Graph resources are the authored/save contract.  Dynamic obstacles and any
## NavigationRegion3D/NavigationAgent3D projections stay in this backend and
## are deliberately excluded from snapshot_state().

const GRAPH_SCRIPT := preload("res://gm_runtime/map/3d/gm_surface_graph.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const STABLE_DATA := preload("res://gm_runtime/simulation/gm_stable_data.gd")

const SCHEMA := "gm.map_backend_3d.v1"
const SNAPSHOT_SCHEMA := "gm.map_backend_3d.snapshot.v1"
const SNAPSHOT_FIELDS := ["schema", "schema_version", "maps"]

var _graphs: Dictionary = {}
var _dynamic_obstacles: Array = []
var _dynamic_obstacle_version: int = 0

func backend_id() -> StringName:
	return &"gm.map_backend.planar_3d"

func availability() -> Dictionary:
	var validation := _validate_all_graphs()
	if not validation.ok:
		return {"ok": false, "read_only": true, "code": "map.backend_3d_invalid", "error_zh": "Planar 3D Surface Graph校验失败。", "details": validation}
	return {"ok": true, "read_only": true, "code": "map.backend_3d_ready", "backend_id": str(backend_id()), "map_count": _graphs.size(), "dynamic_obstacle_version": _dynamic_obstacle_version}

func configure_graph(graph: GMSurfaceGraph) -> Dictionary:
	if graph == null:
		return _failure("map.graph_missing", "不能配置空的Surface Graph。")
	var candidate := graph.copy_graph()
	var known: Array = []
	for map_key in _graphs.keys():
		known.append(_graphs[map_key])
	var validation := candidate.validate(known)
	if not validation.ok:
		return {"ok": false, "code": "map.graph_invalid", "error_zh": "Surface Graph无效，未写入地图后端。", "errors": validation.errors}
	var candidate_map := str(candidate.map_id)
	var candidate_graph_id := str(candidate.graph_id)
	for map_key in _graphs.keys():
		var existing: GMSurfaceGraph = _graphs[map_key]
		if str(existing.graph_id) == candidate_graph_id and str(existing.map_id) != candidate_map:
			return _failure("map.graph_id_duplicate", "Surface Graph稳定ID已被另一张地图使用。")
	var previous_graph = _graphs.get(candidate_map, null)
	_graphs[candidate_map] = candidate
	var all_validation := _validate_all_graphs()
	if not all_validation.ok:
		if previous_graph == null: _graphs.erase(candidate_map)
		else: _graphs[candidate_map] = previous_graph
		return {"ok": false, "code": "map.graph_invalid", "error_zh": "Surface Graph组合校验失败，未写入地图后端。", "errors": all_validation.errors}
	return {"ok": true, "code": "map.graph_configured", "map_id": candidate_map, "graph_id": candidate_graph_id, "value": candidate.to_native()}

func register_graph(graph: GMSurfaceGraph) -> Dictionary:
	return configure_graph(graph)

func remove_graph(map_id: String) -> Dictionary:
	if not _graphs.has(map_id): return _failure("map.graph_missing", "找不到地图Surface Graph：%s" % map_id)
	_graphs.erase(map_id)
	return {"ok": true, "map_id": map_id}

func resolve_graph(map_id: String) -> GMSurfaceGraph:
	return _graphs.get(map_id, null) as GMSurfaceGraph

func resolve_surface(map_id: String, surface_id: String) -> GMSurfaceDefinition3D:
	var graph := resolve_graph(map_id)
	if graph == null: return null
	return graph.resolve_surface(surface_id, map_id)

func graph_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for map_key in _graphs.keys(): result.append(str(_graphs[map_key].graph_id))
	result.sort()
	return result

func map_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for map_key in _graphs.keys(): result.append(str(map_key))
	result.sort()
	return result

func snapshot_state() -> Dictionary:
	var maps: Array = []
	var sorted_ids := map_ids()
	for map_id in sorted_ids:
		maps.append(_graphs[map_id].to_native())
	return {"schema": SNAPSHOT_SCHEMA, "schema_version": 1, "maps": maps}

func map_snapshot_state() -> Dictionary:
	return snapshot_state()

func validate_snapshot_state(value: Variant) -> Dictionary:
	if value == null or (value is Dictionary and value.is_empty()): return {"ok": true, "code": "map.snapshot_empty"}
	if not value is Dictionary: return _failure("map.snapshot_type_invalid", "Planar 3D地图快照必须是Dictionary。")
	var source: Dictionary = value
	var shape := _validate_snapshot_fields(source)
	if not shape.ok: return shape
	if str(source.get("schema", "")) != SNAPSHOT_SCHEMA:
		return _failure("map.snapshot_schema_invalid", "Planar 3D地图快照Schema标识无效。")
	var schema_version := STABLE_DATA.normalize_schema_version(source.get("schema_version"))
	if not schema_version.ok:
		return _failure("map.snapshot_schema_version_invalid", "Planar 3D地图快照Schema版本必须是整数1。")
	var stable := STABLE_DATA.validate(source, "$.spatial_map_state")
	if not stable.ok: return {"ok": false, "code": "map.snapshot_non_pure", "error_zh": "Planar 3D地图快照只能包含纯值。", "errors": stable.errors}
	var raw_maps: Variant = source.get("maps", [])
	if not raw_maps is Array: return _failure("map.snapshot_maps_invalid", "Planar 3D地图快照maps必须是数组。")
	var seen_maps: Dictionary = {}
	var parsed_graphs: Array = []
	for raw_graph in raw_maps:
		var parsed := GRAPH_SCRIPT.from_native(raw_graph)
		if not parsed.ok: return {"ok": false, "code": "map.snapshot_graph_invalid", "error_zh": "Planar 3D地图快照包含无效Surface Graph。", "details": parsed}
		var graph: GMSurfaceGraph = parsed.graph
		if seen_maps.has(str(graph.map_id)): return _failure("map.snapshot_map_duplicate", "Planar 3D地图快照包含重复map_id。")
		seen_maps[str(graph.map_id)] = true
		parsed_graphs.append(graph)
	for graph in parsed_graphs:
		var graph_validation: Dictionary = graph.validate(parsed_graphs)
		if not graph_validation.ok: return {"ok": false, "code": "map.snapshot_graph_invalid", "error_zh": "Planar 3D地图快照Graph组合校验失败。", "errors": graph_validation.errors}
	parsed_graphs.sort_custom(func(left, right): return str(left.map_id) < str(right.map_id))
	var canonical_maps: Array = []
	for graph in parsed_graphs: canonical_maps.append(graph.to_native())
	return {"ok": true, "code": "map.snapshot_valid", "maps": parsed_graphs.size(), "value": {"schema": SNAPSHOT_SCHEMA, "schema_version": 1, "maps": canonical_maps}}

func restore_snapshot_state(value: Variant) -> Dictionary:
	var validation: Dictionary = validate_snapshot_state(value)
	if not validation.ok: return validation
	if value == null or (value is Dictionary and value.is_empty()): return {"ok": true, "code": "map.snapshot_empty"}
	var source: Dictionary = value
	var parsed_graphs: Dictionary = {}
	for raw_graph in source.get("maps", []):
		var parsed := GRAPH_SCRIPT.from_native(raw_graph)
		if not parsed.ok: return parsed
		var graph: GMSurfaceGraph = parsed.graph
		parsed_graphs[str(graph.map_id)] = graph
	_graphs = parsed_graphs
	_dynamic_obstacles.clear()
	_dynamic_obstacle_version += 1
	return {"ok": true, "code": "map.snapshot_restored", "map_count": _graphs.size()}

func update_dynamic_obstacles(obstacles: Array) -> Dictionary:
	var candidate: Array = []
	var ids: Dictionary = {}
	for raw_obstacle in obstacles:
		if not raw_obstacle is Dictionary: return _failure("map.obstacle_type_invalid", "动态障碍必须是Dictionary纯值。")
		var obstacle: Dictionary = raw_obstacle
		var obstacle_id := str(obstacle.get("obstacle_id", ""))
		var map_id := str(obstacle.get("map_id", ""))
		var surface_id := str(obstacle.get("surface_id", ""))
		if obstacle_id.is_empty() or not PLANAR_POSITION.is_valid_stable_id(obstacle_id): return _failure("map.obstacle_id_invalid", "动态障碍obstacle_id必须是稳定ID。")
		if ids.has(obstacle_id): return _failure("map.obstacle_duplicate", "动态障碍obstacle_id不能重复。")
		if resolve_surface(map_id, surface_id) == null: return _failure("map.obstacle_surface_missing", "动态障碍引用的Surface不存在。")
		var min_value: Variant = _rect_point(obstacle.get("min", null))
		var max_value: Variant = _rect_point(obstacle.get("max", null))
		if min_value == null or max_value == null: return _failure("map.obstacle_bounds_invalid", "动态障碍必须包含有限min/max矩形。")
		if min_value.x >= max_value.x or min_value.y >= max_value.y: return _failure("map.obstacle_bounds_invalid", "动态障碍min必须严格小于max。")
		ids[obstacle_id] = true
		candidate.append({"obstacle_id": obstacle_id, "map_id": map_id, "surface_id": surface_id, "min": {"x": min_value.x, "y": min_value.y}, "max": {"x": max_value.x, "y": max_value.y}, "enabled": bool(obstacle.get("enabled", true))})
	candidate.sort_custom(func(left, right): return str(left.obstacle_id) < str(right.obstacle_id))
	_dynamic_obstacles = candidate
	_dynamic_obstacle_version += 1
	return {"ok": true, "code": "map.dynamic_obstacles_updated", "version": _dynamic_obstacle_version, "count": _dynamic_obstacles.size()}

func clear_dynamic_obstacles() -> Dictionary:
	_dynamic_obstacles.clear()
	_dynamic_obstacle_version += 1
	return {"ok": true, "code": "map.dynamic_obstacles_cleared", "version": _dynamic_obstacle_version}

func dynamic_obstacle_version() -> int:
	return _dynamic_obstacle_version

func is_blocked(position: Variant, radius: float = 0.0) -> bool:
	var parsed := PLANAR_POSITION.from_native(position)
	if not parsed.ok: return true
	var planar: GMPlanarPosition = parsed.position
	return is_logical_blocked(planar.map_id, planar.surface_id, Vector2(planar.x, planar.y), radius)

func is_logical_blocked(map_id: String, surface_id: String, point: Vector2, radius: float = 0.0) -> bool:
	var safe_radius := maxf(radius, 0.0)
	for obstacle in _dynamic_obstacles:
		if not bool(obstacle.get("enabled", true)): continue
		if str(obstacle.get("map_id", "")) != map_id or str(obstacle.get("surface_id", "")) != surface_id: continue
		var min_value: Dictionary = obstacle.get("min", {})
		var max_value: Dictionary = obstacle.get("max", {})
		if point.x >= float(min_value.get("x", 0.0)) - safe_radius and point.x <= float(max_value.get("x", 0.0)) + safe_radius and point.y >= float(min_value.get("y", 0.0)) - safe_radius and point.y <= float(max_value.get("y", 0.0)) + safe_radius:
			return true
	return false

func is_logical_segment_blocked(map_id: String, surface_id: String, start: Vector2, finish: Vector2, radius: float = 0.0) -> bool:
	var safe_radius := maxf(radius, 0.0)
	for obstacle in _dynamic_obstacles:
		if not bool(obstacle.get("enabled", true)): continue
		if str(obstacle.get("map_id", "")) != map_id or str(obstacle.get("surface_id", "")) != surface_id: continue
		var min_value: Dictionary = obstacle.get("min", {})
		var max_value: Dictionary = obstacle.get("max", {})
		var min_x := float(min_value.get("x", 0.0)) - safe_radius
		var max_x := float(max_value.get("x", 0.0)) + safe_radius
		var min_y := float(min_value.get("y", 0.0)) - safe_radius
		var max_y := float(max_value.get("y", 0.0)) + safe_radius
		if _segment_intersects_aabb(start, finish, min_x, max_x, min_y, max_y): return true
	return false

func _validate_all_graphs() -> Dictionary:
	var graphs: Array = []
	var graph_ids_seen: Dictionary = {}
	for map_key in _graphs.keys():
		var graph: GMSurfaceGraph = _graphs[map_key]
		if graph == null: return _failure("map.graph_null", "地图后端不能包含空Graph。")
		if str(graph.map_id) != str(map_key): return _failure("map.graph_key_mismatch", "地图后端Graph索引与map_id不一致。")
		if graph_ids_seen.has(str(graph.graph_id)): return _failure("map.graph_id_duplicate", "地图后端Graph稳定ID不能重复。")
		graph_ids_seen[str(graph.graph_id)] = true
		graphs.append(graph)
	for graph in graphs:
		var validation: Dictionary = graph.validate(graphs)
		if not validation.ok: return {"ok": false, "code": "map.graph_invalid", "errors": validation.errors}
	return {"ok": true}

static func _rect_point(value: Variant):
	if not value is Dictionary: return null
	var point: Dictionary = value
	if not point.has("x") or not point.has("y"): return null
	var x := float(point.get("x"))
	var y := float(point.get("y"))
	if not is_finite(x) or not is_finite(y): return null
	return Vector2(x, y)

static func _segment_intersects_aabb(start: Vector2, finish: Vector2, min_x: float, max_x: float, min_y: float, max_y: float) -> bool:
	var delta := finish - start
	var t_enter := 0.0
	var t_exit := 1.0
	for axis in 2:
		var origin := start.x if axis == 0 else start.y
		var direction := delta.x if axis == 0 else delta.y
		var lower := min_x if axis == 0 else min_y
		var upper := max_x if axis == 0 else max_y
		if is_zero_approx(direction):
			if origin < lower or origin > upper: return false
			continue
		var first := (lower - origin) / direction
		var second := (upper - origin) / direction
		if first > second:
			var swap_value := first
			first = second
			second = swap_value
		t_enter = maxf(t_enter, first)
		t_exit = minf(t_exit, second)
		if t_enter > t_exit: return false
	return t_enter <= t_exit

static func _failure(code: String, error_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": error_zh}

static func _validate_snapshot_fields(source: Dictionary) -> Dictionary:
	for field in SNAPSHOT_FIELDS:
		if not source.has(field):
			return _failure("map.snapshot_schema_field_missing", "Planar 3D地图快照缺少必需字段：%s。" % field)
	for raw_key in source.keys():
		if not SNAPSHOT_FIELDS.has(str(raw_key)):
			return _failure("map.snapshot_schema_field_unknown", "Planar 3D地图快照包含未知字段：%s。" % raw_key)
	return {"ok": true}
