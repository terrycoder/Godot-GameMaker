@tool
class_name GMPlanar3DSpatialAdapter
extends RefCounted

## Planar 3D is a surface graph, not unrestricted 3D navigation.  All
## authored positions remain GMPlanarPosition values; Godot navigation nodes
## are optional runtime projections and never enter query/save values.

const SPATIAL_DOMAIN := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")
const CAPABILITIES := preload("res://gm_runtime/spatial_core/gm_spatial_backend_capabilities.gd")
const QUERY_RESULT := preload("res://gm_runtime/spatial_core/gm_spatial_query_result.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const TARGET_REF := preload("res://gm_runtime/spatial_core/gm_spatial_target_ref.gd")
const MAP_BACKEND_SCRIPT := preload("res://gm_runtime/map/3d/gm_map_backend_3d.gd")
const GRAPH_SCRIPT := preload("res://gm_runtime/map/3d/gm_surface_graph.gd")

const POSITION_CAPABILITIES := [
	CAPABILITIES.RESOLVE_TARGET,
	CAPABILITIES.LOGICAL_TO_WORLD,
	CAPABILITIES.WORLD_TO_LOGICAL,
	CAPABILITIES.PLANAR_DISTANCE,
	CAPABILITIES.PLANAR_DIRECTION,
	CAPABILITIES.TRAVEL_COST,
	CAPABILITIES.FIND_SURFACE,
	CAPABILITIES.GROUND_HEIGHT,
	CAPABILITIES.VALIDATE_WALKABLE_POSITION,
	CAPABILITIES.IS_REACHABLE,
	CAPABILITIES.REQUEST_PATH,
	CAPABILITIES.SCREEN_TO_WORLD,
	CAPABILITIES.WORLD_TO_SCREEN,
	CAPABILITIES.SNAP_TO_SURFACE,
	CAPABILITIES.FIND_NEAREST_SURFACE,
]

var _registry
var _enabled := true
var _map_backend: GMMapBackend3D
var _runtime_nodes: Array[Node] = []

func _init(registry = null, enabled: bool = true, map_backend = null) -> void:
	_registry = registry
	_enabled = enabled
	_map_backend = map_backend if map_backend is GMMapBackend3D else MAP_BACKEND_SCRIPT.new()

func capabilities():
	var supported := PackedStringArray(POSITION_CAPABILITIES) if _enabled and _map_backend != null else PackedStringArray()
	return CAPABILITIES.new(SPATIAL_DOMAIN.PLANAR_3D, supported)

func map_backend() -> GMMapBackend3D:
	return _map_backend

func configure_graph(graph: GMSurfaceGraph) -> Dictionary:
	if not _enabled: return _blocked(CAPABILITIES.FIND_SURFACE, "spatial.adapter.disabled", "Planar 3D空间扩展已关闭。")
	if _map_backend == null: return _blocked(CAPABILITIES.FIND_SURFACE, "spatial.backend.missing", "Planar 3D地图后端不可用。")
	return _map_backend.configure_graph(graph)

func register_graph(graph: GMSurfaceGraph) -> Dictionary:
	return configure_graph(graph)

func map_snapshot_state() -> Dictionary:
	return _map_backend.snapshot_state() if _map_backend != null else {}

func validate_map_snapshot_state(value: Variant) -> Dictionary:
	if _map_backend == null: return {"ok": false, "code": "map.backend.missing", "error_zh": "Planar 3D地图后端不可用。"}
	return _map_backend.validate_snapshot_state(value)

func restore_map_snapshot_state(value: Variant) -> Dictionary:
	if _map_backend == null: return {"ok": false, "code": "map.backend.missing", "error_zh": "Planar 3D地图后端不可用。"}
	return _map_backend.restore_snapshot_state(value)

func validate_registry_positions(registry_object: Object, map_state: Variant) -> Dictionary:
	# Validate staged entity positions against a detached Graph view.  This lets
	# GMAtomicWorldLoadCoordinator check a save before mutating the live backend.
	if registry_object == null or not is_instance_valid(registry_object): return {"ok": false, "code": "spatial.snapshot.registry_missing", "reason_zh": "空间快照贡献者缺少实体注册表。"}
	var staged_backend := MAP_BACKEND_SCRIPT.new()
	var restored := staged_backend.restore_snapshot_state(map_state)
	if not restored.ok: return restored
	var staged_adapter := GMPlanar3DSpatialAdapter.new(_registry, true, staged_backend)
	var positions: Dictionary = {}
	for entity_id in registry_object.all_entity_ids():
		var record = registry_object.get_record(entity_id)
		var data: Dictionary = record.get("data", {}) if record is Dictionary else {}
		var candidate = data.get("spatial_position", data.get("gm.spatial.planar_position", null))
		if candidate == null: continue
		var parsed := PLANAR_POSITION.from_native(candidate)
		if not parsed.ok: return {"ok": false, "code": "spatial.snapshot_position_invalid", "reason_zh": "快照实体空间位置无效：%s" % entity_id, "entity_id": entity_id}
		var surface_result := staged_adapter.find_surface(parsed.position)
		if not surface_result.ok: return {"ok": false, "code": "spatial.snapshot.position_unresolvable", "reason_zh": "实体空间位置无法由存档Surface Graph解析。", "entity_id": entity_id, "details": surface_result}
		positions[entity_id] = parsed.position.to_native()
	return {"ok": true, "schema_version": 1, "positions": positions, "entity_count": positions.size()}

func shutdown() -> void:
	for node in _runtime_nodes:
		if node != null and is_instance_valid(node): node.queue_free()
	_runtime_nodes.clear()

func query_target(target) -> Dictionary:
	var required := _require_capability(CAPABILITIES.RESOLVE_TARGET)
	if not required.ok: return required
	var normalized := _normalize_target(target)
	if not normalized.ok: return _blocked(CAPABILITIES.RESOLVE_TARGET, str(normalized.get("code", "spatial.target.invalid")), str(normalized.get("error_zh", "空间目标无效。")), {}, normalized)
	var target_ref = normalized.target
	var native: Dictionary = target_ref.to_native()
	if target_ref.domain_id() != SPATIAL_DOMAIN.PLANAR_3D:
		return _blocked(CAPABILITIES.RESOLVE_TARGET, "spatial.adapter.domain_unsupported", "3D适配器只支持PLANAR_3D。", native)
	match target_ref.kind():
		"anchor":
			if _registry == null: return _blocked(CAPABILITIES.RESOLVE_TARGET, "spatial.adapter.registry_missing", "3D锚点需要既有SemanticMap注册表。", native)
			var anchor_result = _registry.resolve_anchor(target_ref.map_id(), target_ref.semantic_id())
			if not anchor_result.ok: return _blocked(CAPABILITIES.RESOLVE_TARGET, str(anchor_result.get("code", "spatial.anchor_missing")), str(anchor_result.get("error_zh", "3D锚点不存在。")), native, anchor_result)
			var anchor = anchor_result.get("anchor", null)
			if anchor == null: return _blocked(CAPABILITIES.RESOLVE_TARGET, "spatial.anchor.invalid", "3D锚点解析结果无效。", native)
			var anchor_surface_id := str(anchor.surface_id) if "surface_id" in anchor else ""
			var position_result := _unique_surface_position(target_ref.map_id(), anchor.position, {"surface_id": anchor_surface_id})
			if not position_result.ok: return _blocked(CAPABILITIES.RESOLVE_TARGET, str(position_result.code), str(position_result.error_zh), native, position_result)
			var position: GMPlanarPosition = position_result.position
			return _success(CAPABILITIES.RESOLVE_TARGET, native, {"kind": "anchor", "semantic_id": target_ref.semantic_id(), "map_id": target_ref.map_id(), "logical_position": {"x": position.x, "y": position.y}, "planar_position": position.to_native(), "surface_id": position.surface_id})
		"route":
			if _registry == null: return _blocked(CAPABILITIES.RESOLVE_TARGET, "spatial.adapter.registry_missing", "3D路线需要既有SemanticMap注册表。", native)
			var map_result = _registry.resolve_map(target_ref.map_id())
			if not map_result.ok: return _blocked(CAPABILITIES.RESOLVE_TARGET, str(map_result.get("code", "spatial.map.missing")), str(map_result.get("error_zh", "3D语义地图不存在。")), native, map_result)
			var route_result: Dictionary = map_result.map.resolve_route(target_ref.semantic_id())
			if not route_result.ok: return _blocked(CAPABILITIES.RESOLVE_TARGET, str(route_result.get("code", "spatial.route.missing")), str(route_result.get("error_zh", "3D路线不存在。")), native, route_result)
			var route_points: Array = []
			for row in route_result.route.points:
				if not row is Dictionary or not row.get("position", null) is Vector2:
					return _blocked(CAPABILITIES.RESOLVE_TARGET, "spatial.route.point_invalid", "3D路线点必须包含Vector2逻辑位置。", native)
				var surface_id := str(row.get("surface_id", ""))
				var point_result := _unique_surface_position(target_ref.map_id(), row.position, {"surface_id": surface_id})
				if not point_result.ok: return _blocked(CAPABILITIES.RESOLVE_TARGET, str(point_result.code), str(point_result.error_zh), native, point_result)
				route_points.append(point_result.position.to_native())
			return _success(CAPABILITIES.RESOLVE_TARGET, native, {"kind": "route", "semantic_id": target_ref.semantic_id(), "map_id": target_ref.map_id(), "point_count": route_points.size(), "logical_points": route_points})
		"logical_position":
			var position_result := _position_from_target_native(native)
			if not position_result.ok: return _blocked(CAPABILITIES.RESOLVE_TARGET, str(position_result.get("code", "spatial.position.invalid")), str(position_result.get("error_zh", "自由逻辑位置无效。")), native, position_result)
			var position: GMPlanarPosition = position_result.position
			return _success(CAPABILITIES.RESOLVE_TARGET, native, {"kind": "logical_position", "map_id": target_ref.map_id(), "logical_position": {"x": position.x, "y": position.y}, "planar_position": position.to_native(), "surface_id": position.surface_id})
		_:
			return _blocked(CAPABILITIES.RESOLVE_TARGET, "spatial.adapter.target_kind_unsupported", "当前3D适配器不解析该目标类型：%s" % target_ref.kind(), native)

func resolve_target(target) -> Dictionary:
	return query_target(target)

func logical_to_world(position, context: Dictionary = {}) -> Dictionary:
	var required := _require_capability(CAPABILITIES.LOGICAL_TO_WORLD)
	if not required.ok: return required
	var parsed := _parse_position(position, context)
	if not parsed.ok: return _blocked(CAPABILITIES.LOGICAL_TO_WORLD, str(parsed.code), str(parsed.error_zh), {}, parsed)
	var planar: GMPlanarPosition = parsed.position
	var surface: GMSurfaceDefinition3D = parsed.surface
	if not surface.contains_logical(Vector2(planar.x, planar.y)): return _blocked(CAPABILITIES.LOGICAL_TO_WORLD, "spatial.position.out_of_bounds", "逻辑位置不在Surface边界内。", planar.to_native())
	var world := surface.logical_to_world(Vector2(planar.x, planar.y))
	return _success(CAPABILITIES.LOGICAL_TO_WORLD, planar.to_native(), {"world_position": _vector3_dict(world), "height": world.y, "map_id": planar.map_id, "surface_id": planar.surface_id})

func world_to_logical(world, context: Dictionary = {}) -> Dictionary:
	var required := _require_capability(CAPABILITIES.WORLD_TO_LOGICAL)
	if not required.ok: return required
	var world_result := _parse_vector3(world)
	if not world_result.ok: return _blocked(CAPABILITIES.WORLD_TO_LOGICAL, str(world_result.code), str(world_result.error_zh), {}, world_result)
	var nearest := _nearest_surface_internal(world_result.value, context)
	if not nearest.ok: return _blocked(CAPABILITIES.WORLD_TO_LOGICAL, str(nearest.code), str(nearest.error_zh), _vector3_dict(world_result.value), nearest)
	var planar: GMPlanarPosition = nearest.position
	return _success(CAPABILITIES.WORLD_TO_LOGICAL, _vector3_dict(world_result.value), {"logical_position": {"x": planar.x, "y": planar.y}, "planar_position": planar.to_native(), "surface_id": planar.surface_id, "ground_height": nearest.ground_height, "distance": nearest.distance})

func get_planar_distance(from_position, to_position, context: Dictionary = {}) -> Dictionary:
	var required := _require_capability(CAPABILITIES.PLANAR_DISTANCE)
	if not required.ok: return required
	var path_result := _find_path(from_position, to_position, context)
	if not path_result.ok: return _blocked(CAPABILITIES.PLANAR_DISTANCE, str(path_result.get("code", "spatial.path.unavailable")), str(path_result.get("error_zh", "无法计算Planar 3D距离。")), {}, path_result)
	return _success(CAPABILITIES.PLANAR_DISTANCE, {"from": path_result.from.to_native(), "to": path_result.to.to_native()}, {"distance": path_result.cost, "surface_transitions": path_result.surface_transitions})

func get_planar_direction(from_position, to_position, context: Dictionary = {}) -> Dictionary:
	var required := _require_capability(CAPABILITIES.PLANAR_DIRECTION)
	if not required.ok: return required
	var from_result := _parse_position(from_position, context)
	if not from_result.ok: return _blocked(CAPABILITIES.PLANAR_DIRECTION, str(from_result.code), str(from_result.error_zh), {}, from_result)
	var to_result := _parse_position(to_position, context)
	if not to_result.ok: return _blocked(CAPABILITIES.PLANAR_DIRECTION, str(to_result.code), str(to_result.error_zh), {}, to_result)
	var from: GMPlanarPosition = from_result.position
	var to: GMPlanarPosition = to_result.position
	var world_from: Vector3 = from_result.surface.logical_to_world(Vector2(from.x, from.y))
	var world_to: Vector3 = to_result.surface.logical_to_world(Vector2(to.x, to.y))
	var delta := Vector3(world_to.x - world_from.x, 0.0, world_to.z - world_from.z)
	var direction := Vector3.ZERO if is_zero_approx(delta.length()) else delta.normalized()
	return _success(CAPABILITIES.PLANAR_DIRECTION, {"from": from.to_native(), "to": to.to_native()}, {"direction": _vector3_dict(direction), "distance": delta.length(), "surface_transition": from.surface_id != to.surface_id})

func get_travel_cost(from_position, to_position, context: Dictionary = {}) -> Dictionary:
	var required := _require_capability(CAPABILITIES.TRAVEL_COST)
	if not required.ok: return required
	var path_result := _find_path(from_position, to_position, context)
	if not path_result.ok: return _blocked(CAPABILITIES.TRAVEL_COST, str(path_result.get("code", "spatial.path.unavailable")), str(path_result.get("error_zh", "无法计算Planar 3D通行成本。")), {}, path_result)
	return _success(CAPABILITIES.TRAVEL_COST, {"from": path_result.from.to_native(), "to": path_result.to.to_native()}, {"cost": path_result.cost, "path_length": path_result.logical_points.size(), "surface_transitions": path_result.surface_transitions})

func find_surface(position_or_context, context: Dictionary = {}) -> Dictionary:
	var required := _require_capability(CAPABILITIES.FIND_SURFACE)
	if not required.ok: return required
	if _is_world_value(position_or_context):
		var world_result := _parse_vector3(position_or_context)
		if not world_result.ok: return _blocked(CAPABILITIES.FIND_SURFACE, str(world_result.code), str(world_result.error_zh), {}, world_result)
		var nearest := _nearest_surface_internal(world_result.value, context)
		if not nearest.ok: return _blocked(CAPABILITIES.FIND_SURFACE, str(nearest.code), str(nearest.error_zh), _vector3_dict(world_result.value), nearest)
		return _success(CAPABILITIES.FIND_SURFACE, _vector3_dict(world_result.value), {"map_id": nearest.position.map_id, "surface_id": nearest.position.surface_id, "available": true, "planar_position": nearest.position.to_native(), "ground_height": nearest.ground_height, "distance": nearest.distance})
	var query_context := context.duplicate(true)
	var value = position_or_context
	if value is RefCounted and value.has_method("to_native"): value = value.to_native()
	if position_or_context is Dictionary and position_or_context.has("map_id"):
		query_context = position_or_context.duplicate(true)
		value = position_or_context.get("planar_position", position_or_context)
	var partial := _parse_logical_partial(value, query_context)
	if not partial.ok: return _blocked(CAPABILITIES.FIND_SURFACE, str(partial.code), str(partial.error_zh), {}, partial)
	var map_id := str(partial.map_id)
	var graph: GMSurfaceGraph = _map_backend.resolve_graph(map_id) if _map_backend != null else null
	if graph == null: return _blocked(CAPABILITIES.FIND_SURFACE, "spatial.map.missing", "Planar 3D地图Surface Graph不存在。", partial)
	var candidates: Array = _surface_candidates(graph, partial.point, str(partial.get("surface_id", "")))
	if candidates.is_empty(): return _blocked(CAPABILITIES.FIND_SURFACE, "spatial.surface.missing", "逻辑位置不属于任何Surface。", partial)
	if candidates.size() > 1: return _blocked(CAPABILITIES.FIND_SURFACE, "spatial.position.ambiguous", "逻辑位置同时落入多个Surface，缺少高度/Surface选择。", partial, {"candidates": _surface_ids(candidates)})
	var surface: GMSurfaceDefinition3D = candidates[0]
	var planar := PLANAR_POSITION.new(map_id, str(surface.surface_id), partial.point.x, partial.point.y)
	var reference := _validate_position_reference(planar)
	if not reference.ok: return _blocked(CAPABILITIES.FIND_SURFACE, str(reference.code), str(reference.error_zh), planar.to_native(), reference)
	return _success(CAPABILITIES.FIND_SURFACE, planar.to_native(), {"map_id": map_id, "surface_id": str(surface.surface_id), "available": true, "planar_position": planar.to_native()})

func find_nearest_surface(world_position, context: Dictionary = {}) -> Dictionary:
	var required := _require_capability(CAPABILITIES.FIND_NEAREST_SURFACE)
	if not required.ok: return required
	var world_result := _parse_vector3(world_position)
	if not world_result.ok: return _blocked(CAPABILITIES.FIND_NEAREST_SURFACE, str(world_result.code), str(world_result.error_zh), {}, world_result)
	var nearest := _nearest_surface_internal(world_result.value, context)
	if not nearest.ok: return _blocked(CAPABILITIES.FIND_NEAREST_SURFACE, str(nearest.code), str(nearest.error_zh), _vector3_dict(world_result.value), nearest)
	return _success(CAPABILITIES.FIND_NEAREST_SURFACE, _vector3_dict(world_result.value), {"map_id": nearest.position.map_id, "surface_id": nearest.position.surface_id, "planar_position": nearest.position.to_native(), "world_position": _vector3_dict(nearest.surface.logical_to_world(Vector2(nearest.position.x, nearest.position.y))), "ground_height": nearest.ground_height, "distance": nearest.distance})

func find_ground_height(position, context: Dictionary = {}) -> Dictionary:
	var required := _require_capability(CAPABILITIES.GROUND_HEIGHT)
	if not required.ok: return required
	var parsed := _parse_position_or_nearest(position, context)
	if not parsed.ok: return _blocked(CAPABILITIES.GROUND_HEIGHT, str(parsed.code), str(parsed.error_zh), {}, parsed)
	var planar: GMPlanarPosition = parsed.position
	var surface: GMSurfaceDefinition3D = parsed.surface
	var height := surface.world_height_at(Vector2(planar.x, planar.y))
	return _success(CAPABILITIES.GROUND_HEIGHT, planar.to_native(), {"height": height, "map_id": planar.map_id, "surface_id": planar.surface_id, "planar_position": planar.to_native()})

func ground_height(position, context: Dictionary = {}) -> Dictionary:
	return find_ground_height(position, context)

func snap_to_surface(position, context: Dictionary = {}) -> Dictionary:
	var required := _require_capability(CAPABILITIES.SNAP_TO_SURFACE)
	if not required.ok: return required
	var parsed := _parse_position_or_nearest(position, context)
	if not parsed.ok: return _blocked(CAPABILITIES.SNAP_TO_SURFACE, str(parsed.code), str(parsed.error_zh), {}, parsed)
	var planar: GMPlanarPosition = parsed.position
	var surface: GMSurfaceDefinition3D = parsed.surface
	var world := surface.logical_to_world(Vector2(planar.x, planar.y))
	return _success(CAPABILITIES.SNAP_TO_SURFACE, _value_target(position), {"planar_position": planar.to_native(), "world_position": _vector3_dict(world), "height": world.y, "map_id": planar.map_id, "surface_id": planar.surface_id})

func snap(position, context: Dictionary = {}) -> Dictionary:
	return snap_to_surface(position, context)

func validate_walkable_position(position, context: Dictionary = {}) -> Dictionary:
	var required := _require_capability(CAPABILITIES.VALIDATE_WALKABLE_POSITION)
	if not required.ok: return required
	var parsed := _parse_position_or_nearest(position, context)
	if not parsed.ok: return _blocked(CAPABILITIES.VALIDATE_WALKABLE_POSITION, str(parsed.code), str(parsed.error_zh), {}, parsed)
	var planar: GMPlanarPosition = parsed.position
	var surface: GMSurfaceDefinition3D = parsed.surface
	var profile := str(context.get("agent_profile", "default")).strip_edges()
	if not surface.contains_logical(Vector2(planar.x, planar.y)): return _blocked(CAPABILITIES.VALIDATE_WALKABLE_POSITION, "spatial.position.out_of_bounds", "逻辑位置不在Surface边界内。", planar.to_native())
	if not surface.walkable: return _blocked(CAPABILITIES.VALIDATE_WALKABLE_POSITION, "spatial.position.not_walkable", "Surface未标记为可行走。", planar.to_native())
	if not surface.supports_agent(profile): return _blocked(CAPABILITIES.VALIDATE_WALKABLE_POSITION, "spatial.position.agent_profile_blocked", "Surface不支持当前Agent Profile。", planar.to_native(), {"agent_profile": profile})
	if surface.slope_degrees() > surface.max_slope_degrees + 0.0001: return _blocked(CAPABILITIES.VALIDATE_WALKABLE_POSITION, "spatial.position.slope_blocked", "Surface坡度超过最大可行走坡度。", planar.to_native(), {"slope_degrees": surface.slope_degrees(), "max_slope_degrees": surface.max_slope_degrees})
	var radius := maxf(0.0, float(context.get("agent_radius", 0.0)))
	if _map_backend.is_blocked(planar, radius): return _blocked(CAPABILITIES.VALIDATE_WALKABLE_POSITION, "spatial.position.dynamic_obstacle", "当前位置被动态障碍阻挡。", planar.to_native(), {"dynamic_obstacle_version": _map_backend.dynamic_obstacle_version()})
	if parsed.has("source_world"):
		var source_world: Vector3 = parsed.source_world
		var ground := surface.world_height_at(Vector2(planar.x, planar.y))
		var tolerance := maxf(0.0, float(context.get("vertical_tolerance", 0.5)))
		if absf(source_world.y - ground) > tolerance: return _blocked(CAPABILITIES.VALIDATE_WALKABLE_POSITION, "spatial.position.vertical_mismatch", "world位置与Surface地面高度差超过容差。", planar.to_native(), {"world_height": source_world.y, "ground_height": ground, "tolerance": tolerance})
	return _success(CAPABILITIES.VALIDATE_WALKABLE_POSITION, planar.to_native(), {"walkable": true, "map_id": planar.map_id, "surface_id": planar.surface_id, "ground_height": surface.world_height_at(Vector2(planar.x, planar.y)), "agent_profile": profile})

func is_reachable(from_position, to_position, context: Dictionary = {}) -> Dictionary:
	var required := _require_capability(CAPABILITIES.IS_REACHABLE)
	if not required.ok: return required
	var path_result := _find_path(from_position, to_position, context)
	if not path_result.ok and str(path_result.get("code", "")) in ["spatial.path.unreachable", "spatial.position.not_walkable", "spatial.position.dynamic_obstacle"]:
		var pair := _parse_pair(from_position, to_position, context)
		if not pair.ok: return pair
		return _success(CAPABILITIES.IS_REACHABLE, {"from": pair.from.to_native(), "to": pair.to.to_native()}, {"reachable": false})
	if not path_result.ok: return _blocked(CAPABILITIES.IS_REACHABLE, str(path_result.get("code", "spatial.path.unavailable")), str(path_result.get("error_zh", "无法判断Planar 3D可达性。")), {}, path_result)
	return _success(CAPABILITIES.IS_REACHABLE, {"from": path_result.from.to_native(), "to": path_result.to.to_native()}, {"reachable": true, "cost": path_result.cost, "surface_transitions": path_result.surface_transitions})

func request_path(from_position, to_position, context: Dictionary = {}) -> Dictionary:
	var required := _require_capability(CAPABILITIES.REQUEST_PATH)
	if not required.ok: return required
	var path_result := _find_path(from_position, to_position, context)
	if not path_result.ok:
		var code := str(path_result.get("code", "spatial.path.unavailable"))
		if code == "spatial.position.not_walkable" or code == "spatial.position.dynamic_obstacle": code = "spatial.path.unreachable"
		return _blocked(CAPABILITIES.REQUEST_PATH, code, str(path_result.get("error_zh", "Planar 3D路径不可用。")), {}, path_result)
	return _success(CAPABILITIES.REQUEST_PATH, {"from": path_result.from.to_native(), "to": path_result.to.to_native()}, {"path": path_result.logical_points, "logical_points": path_result.logical_points, "surface_transitions": path_result.surface_transitions, "estimated_cost": path_result.cost, "backend_status": path_result.backend_status, "blocked_reason": {}})

func screen_to_world(screen_position, context: Dictionary = {}) -> Dictionary:
	var required := _require_capability(CAPABILITIES.SCREEN_TO_WORLD)
	if not required.ok: return required
	var screen := _parse_vector2(screen_position)
	if not screen.ok: return _blocked(CAPABILITIES.SCREEN_TO_WORLD, str(screen.code), str(screen.error_zh), {}, screen)
	var camera_result := _camera_screen_to_world(screen.value, context)
	if camera_result.ok: return _success(CAPABILITIES.SCREEN_TO_WORLD, _vector2_dict(screen.value), {"world_position": _vector3_dict(camera_result.world_position), "projection": "camera3d_plane"})
	var transform := _screen_transform_context(context)
	if not transform.ok: return _blocked(CAPABILITIES.SCREEN_TO_WORLD, str(transform.code), str(transform.error_zh), {}, transform)
	var world := Vector3(screen.value.x * transform.scale.x + transform.offset.x, float(context.get("world_y", 0.0)), screen.value.y * transform.scale.y + transform.offset.y)
	return _success(CAPABILITIES.SCREEN_TO_WORLD, _vector2_dict(screen.value), {"world_position": _vector3_dict(world), "projection": "pure_value_plane"})

func world_to_screen(world_position, context: Dictionary = {}) -> Dictionary:
	var required := _require_capability(CAPABILITIES.WORLD_TO_SCREEN)
	if not required.ok: return required
	var world := _parse_vector3(world_position)
	if not world.ok: return _blocked(CAPABILITIES.WORLD_TO_SCREEN, str(world.code), str(world.error_zh), {}, world)
	var camera = context.get("camera", null)
	if camera != null and is_instance_valid(camera) and camera is Camera3D:
		var screen: Vector2 = camera.unproject_position(world.value)
		if is_finite(screen.x) and is_finite(screen.y): return _success(CAPABILITIES.WORLD_TO_SCREEN, _vector3_dict(world.value), {"screen_position": _vector2_dict(screen), "projection": "camera3d"})
	var transform := _screen_transform_context(context)
	if not transform.ok: return _blocked(CAPABILITIES.WORLD_TO_SCREEN, str(transform.code), str(transform.error_zh), {}, transform)
	if is_zero_approx(transform.scale.x) or is_zero_approx(transform.scale.y): return _blocked(CAPABILITIES.WORLD_TO_SCREEN, "spatial.screen_transform_invalid", "屏幕坐标转换比例不能为零。")
	var screen := Vector2((world.value.x - transform.offset.x) / transform.scale.x, (world.value.z - transform.offset.y) / transform.scale.y)
	return _success(CAPABILITIES.WORLD_TO_SCREEN, _vector3_dict(world.value), {"screen_position": _vector2_dict(screen), "projection": "pure_value_plane"})

## Optional runtime projections.  They intentionally return objects only from
## these adapter helpers, never from GMSpatialQueryResult values or saves.
func create_navigation_region_3d(map_id: String, surface_id: String, parent: Node = null) -> Dictionary:
	var surface := _map_backend.resolve_surface(map_id, surface_id) if _map_backend != null else null
	if surface == null: return {"ok": false, "code": "spatial.surface.missing", "error_zh": "NavigationRegion3D投影的Surface不存在。"}
	var region := NavigationRegion3D.new()
	region.name = "RuntimeSurface_%s" % surface_id
	region.set_meta("gm_surface_id", surface_id)
	region.set_meta("gm_map_id", map_id)
	if parent != null: parent.add_child(region)
	_runtime_nodes.append(region)
	return {"ok": true, "node": region, "map_id": map_id, "surface_id": surface_id, "runtime_only": true}

func create_navigation_agent_3d(parent: Node = null) -> Dictionary:
	var agent := NavigationAgent3D.new()
	agent.name = "RuntimePlanar3DAgent"
	if parent != null: parent.add_child(agent)
	_runtime_nodes.append(agent)
	return {"ok": true, "node": agent, "runtime_only": true}

func _require_capability(capability_id: String) -> Dictionary:
	if not _enabled: return _blocked(capability_id, "spatial.adapter.disabled", "Planar 3D空间扩展已关闭。")
	if _map_backend == null: return _blocked(capability_id, "spatial.backend.missing", "Planar 3D地图后端不可用。")
	var result := capabilities().query(capability_id)
	return {"ok": true} if result.ok else _blocked(capability_id, str(result.code), str(result.get("error_zh", "空间能力不可用。")))

func _success(capability_id: String, target: Dictionary, value: Dictionary) -> Dictionary:
	return QUERY_RESULT.success(SPATIAL_DOMAIN.PLANAR_3D, capability_id, target, value)

func _blocked(capability_id: String, code: String, message: String, target: Dictionary = {}, details: Dictionary = {}) -> Dictionary:
	var merged := details.duplicate(true)
	if not target.is_empty() and not merged.has("target"): merged["target"] = target.duplicate(true)
	return QUERY_RESULT.blocked(code, message, SPATIAL_DOMAIN.PLANAR_3D, capability_id, merged)

func _normalize_target(target) -> Dictionary:
	if target == null: return {"ok": false, "code": "spatial.target_missing", "error_zh": "空间目标不能为空。"}
	if target is RefCounted and target.has_method("to_native"): return TARGET_REF.from_native(target.to_native())
	return TARGET_REF.from_native(target)

func _position_from_target_native(native: Dictionary) -> Dictionary:
	var candidate = native.get("planar_position", null)
	if candidate != null:
		var parsed := _parse_position(candidate)
		if not parsed.ok: return parsed
		if native.has("map_id") and str(native.get("map_id", "")) != str(parsed.position.map_id): return {"ok": false, "code": "spatial.position.map_mismatch", "error_zh": "目标map_id与PlanarPosition不一致。"}
		return parsed
	return _parse_position(native, {"map_id": str(native.get("map_id", ""))})

func _parse_position(value, context: Dictionary = {}) -> Dictionary:
	if value is Vector3 or _is_world_value(value):
		var world_result := _parse_vector3(value)
		if not world_result.ok: return world_result
		var nearest := _nearest_surface_internal(world_result.value, context)
		return nearest if not nearest.ok else {"ok": true, "position": nearest.position, "surface": nearest.surface, "source_world": world_result.value}
	var native: Variant = value
	if value is Vector2:
		var map_id := str(context.get("map_id", ""))
		if map_id.is_empty(): return {"ok": false, "code": "spatial.position.map_missing", "error_zh": "Vector2适配输入必须显式提供map_id。"}
		var surface_id := str(context.get("surface_id", ""))
		var candidate := _unique_surface_position(map_id, value, {"surface_id": surface_id})
		return candidate
	if value is Dictionary and value.has("world_position"):
		return _parse_position(value.get("world_position"), context)
	if value is Dictionary and value.has("planar_position"):
		return _parse_position(value.get("planar_position"), context)
	if value is Dictionary and value.has("logical_position"):
		var wrapper: Dictionary = value
		var logical: Dictionary = wrapper.get("logical_position", {})
		if not logical is Dictionary or not logical.has("x") or not logical.has("y"): return {"ok": false, "code": "spatial.position.invalid", "error_zh": "逻辑位置包装值无效。"}
		var map_id := str(wrapper.get("map_id", context.get("map_id", "")))
		var surface_id := str(wrapper.get("surface_id", context.get("surface_id", "")))
		var partial := _parse_logical_partial({"map_id": map_id, "surface_id": surface_id, "x": logical.get("x"), "y": logical.get("y")}, context)
		if not partial.ok: return partial
		if partial.candidates.size() != 1: return {"ok": false, "code": "spatial.position.ambiguous", "error_zh": "逻辑位置未能唯一选择Surface。", "candidates": _surface_ids(partial.candidates)}
		var surface: GMSurfaceDefinition3D = partial.candidates[0]
		var planar := PLANAR_POSITION.new(map_id, str(surface.surface_id), partial.point.x, partial.point.y)
		var reference := _validate_position_reference(planar)
		if not reference.ok: return reference
		return {"ok": true, "position": planar, "surface": surface}
	if value is Dictionary and value.has("map_id") and value.has("x") and value.has("y"):
		var partial := _parse_logical_partial(value, context)
		if not partial.ok: return partial
		if partial.candidates.size() != 1: return {"ok": false, "code": "spatial.position.ambiguous", "error_zh": "逻辑位置未能唯一选择Surface。", "candidates": _surface_ids(partial.candidates)}
		var surface: GMSurfaceDefinition3D = partial.candidates[0]
		var planar := PLANAR_POSITION.new(str(partial.map_id), str(surface.surface_id), partial.point.x, partial.point.y)
		var reference := _validate_position_reference(planar)
		if not reference.ok: return reference
		return {"ok": true, "position": planar, "surface": surface}
	var parsed := PLANAR_POSITION.from_native(native)
	if not parsed.ok: return {"ok": false, "code": "spatial.position.invalid", "error_zh": str(parsed.get("error_zh", "PlanarPosition无效。")), "details": parsed}
	var reference := _validate_position_reference(parsed.position)
	if not reference.ok: return reference
	return {"ok": true, "position": parsed.position, "surface": reference.surface}

func _parse_position_or_nearest(value, context: Dictionary) -> Dictionary:
	return _parse_position(value, context)

func _parse_pair(from_value, to_value, context: Dictionary) -> Dictionary:
	var from := _parse_position(from_value, context)
	if not from.ok: return _blocked(CAPABILITIES.REQUEST_PATH, str(from.code), str(from.error_zh), {}, from)
	var to := _parse_position(to_value, context)
	if not to.ok: return _blocked(CAPABILITIES.REQUEST_PATH, str(to.code), str(to.error_zh), {}, to)
	return {"ok": true, "from": from.position, "to": to.position, "from_surface": from.surface, "to_surface": to.surface}

func _validate_position_reference(position: GMPlanarPosition) -> Dictionary:
	if position == null: return {"ok": false, "code": "spatial.position.invalid", "error_zh": "空间位置不能为空。"}
	var graph: GMSurfaceGraph = _map_backend.resolve_graph(str(position.map_id)) if _map_backend != null else null
	if graph == null: return {"ok": false, "code": "spatial.map.missing", "error_zh": "Planar 3D地图Surface Graph不存在。", "map_id": position.map_id}
	var surface := graph.resolve_surface(str(position.surface_id), str(position.map_id))
	if surface == null: return {"ok": false, "code": "spatial.surface.missing", "error_zh": "空间位置引用了不存在或不属于该地图的Surface。", "map_id": position.map_id, "surface_id": position.surface_id}
	if _registry != null:
		var relation: Dictionary = _registry.resolve_surface(position.map_id, position.surface_id)
		if not relation.ok: return {"ok": false, "code": "spatial.surface.missing", "error_zh": "SemanticMap没有注册该Planar 3D Surface。", "map_id": position.map_id, "surface_id": position.surface_id}
	return {"ok": true, "surface": surface, "graph": graph}

func _resolve_graphs_valid() -> Dictionary:
	if _map_backend == null: return {"ok": false, "code": "spatial.backend.missing", "error_zh": "Planar 3D地图后端不可用。"}
	var availability := _map_backend.availability()
	return availability if availability.ok else {"ok": false, "code": "spatial.graph.invalid", "error_zh": "Surface Graph校验失败，空间查询已失败关闭。", "details": availability}

func _parse_logical_partial(value: Variant, context: Dictionary = {}) -> Dictionary:
	if value is RefCounted and value.has_method("to_native"): value = value.to_native()
	if not value is Dictionary: return {"ok": false, "code": "spatial.position.invalid", "error_zh": "逻辑位置必须是Dictionary。"}
	var source: Dictionary = value
	var map_id := str(source.get("map_id", context.get("map_id", "")))
	if map_id.is_empty(): return {"ok": false, "code": "spatial.position.map_missing", "error_zh": "逻辑位置必须显式提供map_id。"}
	if not source.has("x") or not source.has("y"): return {"ok": false, "code": "spatial.position.invalid", "error_zh": "逻辑位置必须包含有限x/y。"}
	var x := float(source.get("x"))
	var y := float(source.get("y"))
	if not is_finite(x) or not is_finite(y): return {"ok": false, "code": "spatial.position.nonfinite", "error_zh": "逻辑位置x/y不得是NaN或INF。"}
	var graph: GMSurfaceGraph = _map_backend.resolve_graph(map_id) if _map_backend != null else null
	if graph == null: return {"ok": false, "code": "spatial.map.missing", "error_zh": "Planar 3D地图Surface Graph不存在。", "map_id": map_id}
	var surface_id := str(source.get("surface_id", context.get("surface_id", "")))
	var candidates := _surface_candidates(graph, Vector2(x, y), surface_id)
	return {"ok": true, "map_id": map_id, "point": Vector2(x, y), "surface_id": surface_id, "candidates": candidates}

func _unique_surface_position(map_id: String, point: Vector2, context: Dictionary) -> Dictionary:
	var graph: GMSurfaceGraph = _map_backend.resolve_graph(map_id) if _map_backend != null else null
	if graph == null: return {"ok": false, "code": "spatial.map.missing", "error_zh": "Planar 3D地图Surface Graph不存在。"}
	var surface_id := str(context.get("surface_id", ""))
	var candidates := _surface_candidates(graph, point, surface_id)
	if candidates.is_empty(): return {"ok": false, "code": "spatial.surface.missing", "error_zh": "逻辑位置不属于任何Surface。"}
	if candidates.size() > 1: return {"ok": false, "code": "spatial.position.ambiguous", "error_zh": "逻辑位置同时落入多个Surface，缺少唯一Surface选择。", "candidates": _surface_ids(candidates)}
	var surface: GMSurfaceDefinition3D = candidates[0]
	var planar := PLANAR_POSITION.new(map_id, str(surface.surface_id), point.x, point.y)
	var reference := _validate_position_reference(planar)
	if not reference.ok: return reference
	return {"ok": true, "position": planar, "surface": surface}

func _surface_candidates(graph: GMSurfaceGraph, point: Vector2, surface_id: String = "") -> Array:
	var candidates: Array = []
	for surface in graph.surfaces:
		if surface == null or (not surface_id.is_empty() and str(surface.surface_id) != surface_id): continue
		if surface.contains_logical(point): candidates.append(surface)
	candidates.sort_custom(func(left, right): return str(left.surface_id) < str(right.surface_id))
	return candidates

func _nearest_surface_internal(world: Vector3, context: Dictionary) -> Dictionary:
	var graph_check := _resolve_graphs_valid()
	if not graph_check.ok: return graph_check
	var map_id := str(context.get("map_id", ""))
	if map_id.is_empty():
		var ids := _map_backend.map_ids()
		if ids.size() != 1: return {"ok": false, "code": "spatial.position.ambiguous", "error_zh": "world坐标缺少map_id，无法唯一选择地图。", "candidates": Array(ids)}
		map_id = str(ids[0])
	var graph: GMSurfaceGraph = _map_backend.resolve_graph(map_id)
	if graph == null: return {"ok": false, "code": "spatial.map.missing", "error_zh": "Planar 3D地图Surface Graph不存在。"}
	var requested_surface := str(context.get("surface_id", ""))
	var profile := str(context.get("agent_profile", "default"))
	var max_vertical := float(context.get("max_vertical_distance", 4.0))
	var tie_epsilon := maxf(0.0, float(context.get("tie_epsilon", 0.05)))
	var candidates: Array = []
	for surface in graph.surfaces:
		if surface == null or (not requested_surface.is_empty() and str(surface.surface_id) != requested_surface): continue
		if not surface.supports_agent(profile): continue
		var logical := surface.world_to_logical(world)
		if not surface.contains_logical(logical): continue
		var ground := surface.world_height_at(logical)
		var distance := absf(world.y - ground)
		if distance <= max_vertical: candidates.append({"surface": surface, "logical": logical, "ground_height": ground, "distance": distance})
	if candidates.is_empty(): return {"ok": false, "code": "spatial.surface.missing", "error_zh": "world位置附近没有满足高度容差的可采样Surface。", "map_id": map_id}
	candidates.sort_custom(func(left, right):
		if not is_equal_approx(float(left.distance), float(right.distance)): return float(left.distance) < float(right.distance)
		return str(left.surface.surface_id) < str(right.surface.surface_id)
	)
	if candidates.size() > 1 and absf(float(candidates[0].distance) - float(candidates[1].distance)) <= tie_epsilon:
		return {"ok": false, "code": "spatial.position.ambiguous", "error_zh": "world位置对多个Surface的采样距离相同，已失败关闭。", "map_id": map_id, "candidates": _surface_ids_from_rows(candidates)}
	var selected = candidates[0]
	var surface: GMSurfaceDefinition3D = selected.surface
	var planar := PLANAR_POSITION.new(map_id, str(surface.surface_id), selected.logical.x, selected.logical.y)
	var reference := _validate_position_reference(planar)
	if not reference.ok: return reference
	return {"ok": true, "position": planar, "surface": surface, "ground_height": float(selected.ground_height), "distance": float(selected.distance)}

func _find_path(from_value, to_value, context: Dictionary) -> Dictionary:
	var graph_check := _resolve_graphs_valid()
	if not graph_check.ok: return graph_check
	var pair := _parse_pair(from_value, to_value, context)
	if not pair.ok: return pair
	var from: GMPlanarPosition = pair.from
	var to: GMPlanarPosition = pair.to
	var from_surface: GMSurfaceDefinition3D = pair.from_surface
	var to_surface: GMSurfaceDefinition3D = pair.to_surface
	var profile := str(context.get("agent_profile", "default"))
	var from_walkable := _walkable_internal(from, from_surface, profile, context)
	if not from_walkable.ok: return from_walkable
	var to_walkable := _walkable_internal(to, to_surface, profile, context)
	if not to_walkable.ok: return to_walkable
	if from.map_id == to.map_id and from.surface_id == to.surface_id:
		return _direct_path(from, to, from_surface, profile, context)
	return _surface_graph_path(from, to, from_surface, to_surface, profile, context)

func _direct_path(from: GMPlanarPosition, to: GMPlanarPosition, surface: GMSurfaceDefinition3D, profile: String, context: Dictionary) -> Dictionary:
	var distance := Vector2(from.x, from.y).distance_to(Vector2(to.x, to.y))
	var segment := _segment_walkable(str(from.map_id), str(from.surface_id), Vector2(from.x, from.y), Vector2(to.x, to.y), surface, profile, context)
	if not segment.ok: return {"ok": false, "code": "spatial.path.unreachable", "error_zh": "直线路径段与不可通行区域相交。", "details": segment, "blocked_reason": segment}
	var steps := maxi(1, ceili(distance / maxf(0.25, float(context.get("path_sample_spacing", 1.0)))))
	var points: Array = []
	for step in range(steps + 1):
		var point := Vector2(from.x, from.y).lerp(Vector2(to.x, to.y), float(step) / float(steps))
		var sample := PLANAR_POSITION.new(from.map_id, from.surface_id, point.x, point.y)
		var valid := _walkable_internal(sample, surface, profile, context)
		if not valid.ok: return {"ok": false, "code": "spatial.path.unreachable", "error_zh": "直线路径经过不可通行位置。", "details": valid}
		points.append(sample.to_native())
	return {"ok": true, "from": from, "to": to, "logical_points": points, "surface_transitions": [], "cost": distance, "backend_status": "surface_direct", "blocked_reason": {}}

func _surface_graph_path(from: GMPlanarPosition, to: GMPlanarPosition, from_surface: GMSurfaceDefinition3D, to_surface: GMSurfaceDefinition3D, profile: String, context: Dictionary) -> Dictionary:
	var start_key := _surface_key(from.map_id, from.surface_id)
	var goal_key := _surface_key(to.map_id, to.surface_id)
	var best: Dictionary = {start_key: {"cost": 0.0, "at": Vector2(from.x, from.y), "previous": "", "edge": {}}}
	var visited: Dictionary = {}
	var selected_goal: Dictionary = {}
	var blocked_segments: Array = []
	while true:
		var current_key := ""
		var current_record: Dictionary = {}
		for key in best.keys():
			if visited.has(key): continue
			if current_key.is_empty() or float(best[key].cost) < float(current_record.get("cost", INF)):
				current_key = str(key)
				current_record = best[key]
		if current_key.is_empty(): break
		visited[current_key] = true
		var current_surface_result := _surface_by_key(current_key)
		if not current_surface_result.ok: return current_surface_result
		var current_surface: GMSurfaceDefinition3D = current_surface_result.surface
		var arrival: Vector2 = current_record.at
		if current_key == goal_key:
			var final_point := Vector2(to.x, to.y)
			var final_segment := _segment_walkable(str(to.map_id), str(to.surface_id), arrival, final_point, current_surface, profile, context)
			if final_segment.ok:
				var final_cost := float(current_record.cost) + arrival.distance_to(final_point)
				if selected_goal.is_empty() or final_cost < float(selected_goal.cost):
					selected_goal = {"cost": final_cost, "key": current_key}
			else:
				blocked_segments.append({"stage": "goal_segment", "map_id": str(to.map_id), "surface_id": str(to.surface_id), "details": final_segment})
		for edge in _outgoing_edges(current_key, profile):
			var edge_source: Vector2 = edge.source_point
			var segment := _segment_walkable(str(edge.from_map), str(edge.from_surface), arrival, edge_source, current_surface, profile, context)
			if not segment.ok:
				blocked_segments.append({"stage": "connection_segment", "connection_id": str(edge.connection.connection_id), "map_id": str(edge.from_map), "surface_id": str(edge.from_surface), "details": segment})
				continue
			var edge_target_surface_result := _surface_by_key(str(edge.to_key))
			if not edge_target_surface_result.ok: continue
			var target_surface: GMSurfaceDefinition3D = edge_target_surface_result.surface
			var target_planar := PLANAR_POSITION.new(str(edge.to_map), str(edge.to_surface), edge.target_point.x, edge.target_point.y)
			var target_valid := _walkable_internal(target_planar, target_surface, profile, context)
			if not target_valid.ok:
				blocked_segments.append({"stage": "connection_arrival", "connection_id": str(edge.connection.connection_id), "map_id": str(edge.to_map), "surface_id": str(edge.to_surface), "details": target_valid})
				continue
			var new_cost := float(current_record.cost) + arrival.distance_to(edge_source) + float(edge.connection.traversal_cost)
			var next_key := str(edge.to_key)
			if not best.has(next_key) or new_cost < float(best[next_key].cost):
				best[next_key] = {"cost": new_cost, "at": edge.target_point, "previous": current_key, "edge": edge}
		if not selected_goal.is_empty() and float(current_record.cost) > float(selected_goal.cost): break
	if selected_goal.is_empty():
		return {"ok": false, "code": "spatial.path.unreachable", "error_zh": "Surface Graph中没有满足方向、Profile与动态障碍条件的路径。", "blocked_reason": {"code": "spatial.path.segment_blocked" if not blocked_segments.is_empty() else "spatial.path.unreachable", "segments": blocked_segments}}
	var transitions: Array = []
	var cursor := str(selected_goal.key)
	while cursor != start_key:
		var record: Dictionary = best.get(cursor, {})
		if record.is_empty(): return {"ok": false, "code": "spatial.path.unreachable", "error_zh": "Surface Graph路径回溯失败。"}
		transitions.push_front(record.edge)
		cursor = str(record.previous)
	var logical_points: Array = [from.to_native()]
	var last_position := Vector2(from.x, from.y)
	for edge in transitions:
		if last_position.distance_to(edge.source_point) > 0.0001:
			logical_points.append(PLANAR_POSITION.new(str(edge.from_map), str(edge.from_surface), edge.source_point.x, edge.source_point.y).to_native())
		logical_points.append(PLANAR_POSITION.new(str(edge.to_map), str(edge.to_surface), edge.target_point.x, edge.target_point.y).to_native())
		last_position = edge.target_point
	logical_points.append(to.to_native())
	var transition_values: Array = []
	for edge in transitions: transition_values.append({"connection_id": str(edge.connection.connection_id), "connection_kind": edge.connection.connection_kind, "from_map_id": str(edge.from_map), "from_surface_id": str(edge.from_surface), "to_map_id": str(edge.to_map), "to_surface_id": str(edge.to_surface), "direction": edge.direction, "required_ability_id": str(edge.connection.required_ability_id)})
	return {"ok": true, "from": from, "to": to, "logical_points": logical_points, "surface_transitions": transition_values, "cost": float(selected_goal.cost), "backend_status": "surface_graph_dijkstra", "blocked_reason": {}}

func _outgoing_edges(surface_key: String, profile: String) -> Array:
	var edges: Array = []
	for map_id in _map_backend.map_ids():
		var graph: GMSurfaceGraph = _map_backend.resolve_graph(str(map_id))
		for connection in graph.connections:
			if connection == null or not connection.supports_agent(profile): continue
			var source_key := _surface_key(str(connection.source_map_id), str(connection.source_surface_id))
			var target_key := _surface_key(str(connection.target_map_id), str(connection.target_surface_id))
			if surface_key == source_key and (connection.direction == "source_to_target" or connection.bidirectional):
				edges.append({"from_map": str(connection.source_map_id), "from_surface": str(connection.source_surface_id), "to_map": str(connection.target_map_id), "to_surface": str(connection.target_surface_id), "to_key": target_key, "source_point": connection.source_exit, "target_point": connection.target_entry, "connection": connection, "direction": "source_to_target"})
			if surface_key == target_key and (connection.direction == "target_to_source" or connection.bidirectional):
				edges.append({"from_map": str(connection.target_map_id), "from_surface": str(connection.target_surface_id), "to_map": str(connection.source_map_id), "to_surface": str(connection.source_surface_id), "to_key": source_key, "source_point": connection.target_entry, "target_point": connection.source_exit, "connection": connection, "direction": "target_to_source"})
	edges.sort_custom(func(left, right):
		if str(left.connection.connection_id) != str(right.connection.connection_id): return str(left.connection.connection_id) < str(right.connection.connection_id)
		return str(left.direction) < str(right.direction)
	)
	return edges

func _surface_by_key(key: String) -> Dictionary:
	var pieces := key.split("::")
	if pieces.size() != 2: return {"ok": false, "code": "spatial.surface.invalid", "error_zh": "Surface路径节点键无效。"}
	var surface := _map_backend.resolve_surface(pieces[0], pieces[1])
	if surface == null: return {"ok": false, "code": "spatial.surface.missing", "error_zh": "Surface路径节点不存在。", "surface_key": key}
	return {"ok": true, "surface": surface}

func _walkable_internal(position: GMPlanarPosition, surface: GMSurfaceDefinition3D, profile: String, context: Dictionary) -> Dictionary:
	if surface == null: return {"ok": false, "code": "spatial.surface.missing", "error_zh": "Surface不存在。"}
	var point := Vector2(position.x, position.y)
	if not surface.contains_logical(point): return {"ok": false, "code": "spatial.position.out_of_bounds", "error_zh": "逻辑位置超出Surface边界。"}
	if not surface.walkable or not surface.supports_agent(profile): return {"ok": false, "code": "spatial.position.not_walkable", "error_zh": "Surface对当前位置或Agent Profile不可通行。"}
	if surface.slope_degrees() > surface.max_slope_degrees + 0.0001: return {"ok": false, "code": "spatial.position.not_walkable", "error_zh": "Surface坡度超过通行上限。"}
	if _map_backend.is_logical_blocked(str(position.map_id), str(position.surface_id), point, maxf(0.0, float(context.get("agent_radius", 0.0)))): return {"ok": false, "code": "spatial.position.dynamic_obstacle", "error_zh": "位置被动态障碍阻挡。"}
	return {"ok": true}

func _segment_walkable(map_id: String, surface_id: String, start: Vector2, finish: Vector2, surface: GMSurfaceDefinition3D, profile: String, context: Dictionary) -> Dictionary:
	if surface == null: return {"ok": false, "code": "spatial.surface.missing", "error_zh": "路径段所属Surface不存在。"}
	var radius := maxf(0.0, float(context.get("agent_radius", 0.0)))
	if not surface.contains_logical(start) or not surface.contains_logical(finish):
		return {"ok": false, "code": "spatial.position.out_of_bounds", "error_zh": "路径段超出Surface边界。"}
	if _map_backend.is_logical_segment_blocked(map_id, surface_id, start, finish, radius):
		return {"ok": false, "code": "spatial.position.dynamic_obstacle", "error_zh": "路径段与动态障碍相交。"}
	var distance := start.distance_to(finish)
	var spacing := maxf(0.25, float(context.get("path_sample_spacing", 1.0)))
	var steps := maxi(1, ceili(distance / spacing))
	for step in range(steps + 1):
		var point := start.lerp(finish, float(step) / float(steps))
		if not surface.contains_logical(point): return {"ok": false, "code": "spatial.position.out_of_bounds", "error_zh": "路径段经过Surface边界外。"}
		if _map_backend.is_logical_blocked(map_id, surface_id, point, radius): return {"ok": false, "code": "spatial.position.dynamic_obstacle", "error_zh": "路径段经过动态障碍。"}
	return {"ok": true}

func _surface_key(map_id: String, surface_id: String) -> String:
	return "%s::%s" % [map_id, surface_id]

func _is_world_value(value: Variant) -> bool:
	return value is Vector3 or (value is Dictionary and value.has("z") and value.has("x") and value.has("y") and not value.has("schema_version"))

func _value_target(value: Variant) -> Dictionary:
	if value is Dictionary: return value.duplicate(true)
	if value is Vector3: return _vector3_dict(value)
	if value is Vector2: return _vector2_dict(value)
	return {}

func _parse_vector2(value) -> Dictionary:
	var result := Vector2.ZERO
	if value is Vector2: result = value
	elif value is Dictionary and value.has("x") and value.has("y"): result = Vector2(float(value.get("x")), float(value.get("y")))
	else: return {"ok": false, "code": "spatial.vector2_invalid", "error_zh": "二维坐标必须是Vector2或x/y Dictionary。"}
	if not is_finite(result.x) or not is_finite(result.y): return {"ok": false, "code": "spatial.vector2_nonfinite", "error_zh": "二维坐标不得是NaN或INF。"}
	return {"ok": true, "value": result}

func _parse_vector3(value) -> Dictionary:
	var result := Vector3.ZERO
	if value is Vector3: result = value
	elif value is Dictionary and value.has("x") and value.has("y") and value.has("z"): result = Vector3(float(value.get("x")), float(value.get("y")), float(value.get("z")))
	else: return {"ok": false, "code": "spatial.vector3_invalid", "error_zh": "三维坐标必须是Vector3或x/y/z Dictionary。"}
	if not is_finite(result.x) or not is_finite(result.y) or not is_finite(result.z): return {"ok": false, "code": "spatial.vector3_nonfinite", "error_zh": "三维坐标不得是NaN或INF。"}
	return {"ok": true, "value": result}

func _vector2_dict(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}

func _vector3_dict(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}

func _screen_transform_context(context: Dictionary) -> Dictionary:
	var scale := _parse_vector2(context.get("screen_scale", context.get("scale", Vector2.ONE)))
	var offset := _parse_vector2(context.get("screen_offset", context.get("offset", Vector2.ZERO)))
	if not scale.ok or not offset.ok: return {"ok": false, "code": "spatial.screen_transform_invalid", "error_zh": "屏幕转换上下文必须包含有限scale/offset。"}
	return {"ok": true, "scale": scale.value, "offset": offset.value}

func _camera_screen_to_world(screen: Vector2, context: Dictionary) -> Dictionary:
	var camera = context.get("camera", null)
	if camera == null or not is_instance_valid(camera) or not camera is Camera3D: return {"ok": false}
	var origin: Vector3 = camera.project_ray_origin(screen)
	var normal: Vector3 = camera.project_ray_normal(screen)
	if is_zero_approx(normal.y): return {"ok": false}
	var plane_y := float(context.get("world_y", 0.0))
	var distance := (plane_y - origin.y) / normal.y
	if distance < 0.0: return {"ok": false}
	return {"ok": true, "world_position": origin + normal * distance}

func _surface_ids(candidates: Array) -> Array:
	var ids: Array = []
	for surface in candidates: ids.append(str(surface.surface_id))
	ids.sort()
	return ids

func _surface_ids_from_rows(rows: Array) -> Array:
	var ids: Array = []
	for row in rows: ids.append(str(row.surface.surface_id))
	ids.sort()
	return ids
