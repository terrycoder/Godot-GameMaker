class_name GMPlanar2DSpatialAdapter
extends RefCounted

const SPATIAL_DOMAIN := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")
const CAPABILITIES := preload("res://gm_runtime/spatial_core/gm_spatial_backend_capabilities.gd")
const QUERY_RESULT := preload("res://gm_runtime/spatial_core/gm_spatial_query_result.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const MAP_RESOURCE := preload("res://gm_runtime/map/gm_map_resource.gd")

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
]

var _registry
var _enabled := true

func _init(registry = null, enabled: bool = true) -> void:
	_registry = registry
	_enabled = enabled

func capabilities():
	var supported := PackedStringArray(POSITION_CAPABILITIES) if _enabled and _registry != null else PackedStringArray()
	return CAPABILITIES.new(SPATIAL_DOMAIN.PLANAR_2D, supported)

func query_target(target) -> Dictionary:
	if not _enabled:
		return _blocked(CAPABILITIES.RESOLVE_TARGET, "spatial.adapter.disabled", "空间扩展已关闭。")
	if _registry == null:
		return _blocked(CAPABILITIES.RESOLVE_TARGET, "spatial.adapter.registry_missing", "2D语义地图注册表不可用。")
	if target == null:
		return _blocked(CAPABILITIES.RESOLVE_TARGET, "spatial.target_missing", "空间目标不能为空。")
	var native = target.to_native()
	if target.domain_id() != SPATIAL_DOMAIN.PLANAR_2D:
		return _blocked(CAPABILITIES.RESOLVE_TARGET, "spatial.adapter.domain_unsupported", "2D适配器只支持PLANAR_2D。", native)
	match target.kind():
		"anchor":
			var anchor_result = _registry.resolve_anchor(target.map_id(), target.semantic_id())
			if not anchor_result.ok:
				return _blocked(CAPABILITIES.RESOLVE_TARGET, str(anchor_result.get("code", "spatial.anchor_missing")), str(anchor_result.get("error_zh", "2D锚点不存在。")), native)
			var anchor = anchor_result.get("anchor", null)
			if anchor == null:
				return _blocked(CAPABILITIES.RESOLVE_TARGET, "spatial.anchor_invalid", "2D锚点解析结果无效。", native)
			var position = _make_position(target.map_id(), anchor.position.x, anchor.position.y)
			if position == null:
				return _blocked(CAPABILITIES.RESOLVE_TARGET, "spatial.surface.missing", "语义地图没有可用的已注册Surface。", native)
			return _success(CAPABILITIES.RESOLVE_TARGET, native, {"kind": "anchor", "semantic_id": target.semantic_id(), "map_id": target.map_id(), "logical_position": {"x": position.x, "y": position.y}, "planar_position": position.to_native()})
		"route":
			var map_result = _registry.resolve_map(target.map_id())
			if not map_result.ok:
				return _blocked(CAPABILITIES.RESOLVE_TARGET, str(map_result.get("code", "spatial.map.missing")), str(map_result.get("error_zh", "2D语义地图不存在。")), native)
			var route_result: Dictionary = map_result.map.resolve_route(target.semantic_id())
			if not route_result.ok:
				return _blocked(CAPABILITIES.RESOLVE_TARGET, str(route_result.get("code", "spatial.route.missing")), str(route_result.get("error_zh", "2D路线不存在。")), native)
			return _success(CAPABILITIES.RESOLVE_TARGET, native, {"kind": "route", "semantic_id": target.semantic_id(), "map_id": target.map_id(), "point_count": route_result.route.points.size()})
		"logical_position":
			var logical: Dictionary = native.get("logical_position", {})
			var position_result := _position_from_target_native(native)
			if not position_result.ok:
				return _blocked(CAPABILITIES.RESOLVE_TARGET, str(position_result.get("code", "spatial.position.invalid")), str(position_result.get("error_zh", "自由逻辑位置无效。")), native)
			var position = position_result.position
			return _success(CAPABILITIES.RESOLVE_TARGET, native, {"kind": "logical_position", "map_id": target.map_id(), "logical_position": logical.duplicate(true), "planar_position": position.to_native()})
		_:
			return _blocked(CAPABILITIES.RESOLVE_TARGET, "spatial.adapter.target_kind_unsupported", "当前2D适配器不解析该目标类型：%s" % target.kind(), native)

func resolve_target(target) -> Dictionary:
	return query_target(target)

func logical_to_world(position, context: Dictionary = {}) -> Dictionary:
	var capability := _require_capability(CAPABILITIES.LOGICAL_TO_WORLD)
	if not capability.ok: return capability
	var parsed := _parse_position(position, context)
	if not parsed.ok: return _blocked(CAPABILITIES.LOGICAL_TO_WORLD, str(parsed.code), str(parsed.error_zh), {}, parsed)
	var value = parsed.position
	var transform := _transform_context(context)
	if not transform.ok: return _blocked(CAPABILITIES.LOGICAL_TO_WORLD, str(transform.code), str(transform.error_zh), value.to_native(), transform)
	var world := Vector2(value.x * transform.scale.x + transform.offset.x, value.y * transform.scale.y + transform.offset.y)
	return _success(CAPABILITIES.LOGICAL_TO_WORLD, value.to_native(), {"world_position": _vector2_dict(world), "height": 0.0, "map_id": value.map_id, "surface_id": value.surface_id})

func world_to_logical(world, context: Dictionary = {}) -> Dictionary:
	var capability := _require_capability(CAPABILITIES.WORLD_TO_LOGICAL)
	if not capability.ok: return capability
	var map_id := str(context.get("map_id", ""))
	if map_id.is_empty():
		return _blocked(CAPABILITIES.WORLD_TO_LOGICAL, "spatial.position.ambiguous", "world坐标缺少map_id，无法唯一还原逻辑位置。", {}, {"candidates": _registry.map_ids()})
	var world_value := _parse_vector2(world)
	if not world_value.ok: return _blocked(CAPABILITIES.WORLD_TO_LOGICAL, "spatial.world_position_invalid", "world坐标必须是有限x/y。", {}, world_value)
	var transform := _transform_context(context)
	if not transform.ok: return _blocked(CAPABILITIES.WORLD_TO_LOGICAL, str(transform.code), str(transform.error_zh), {}, transform)
	if is_zero_approx(transform.scale.x) or is_zero_approx(transform.scale.y):
		return _blocked(CAPABILITIES.WORLD_TO_LOGICAL, "spatial.world_transform_invalid", "world坐标转换比例不能为零。")
	var logical := Vector2((world_value.value.x - transform.offset.x) / transform.scale.x, (world_value.value.y - transform.offset.y) / transform.scale.y)
	var parsed_position := _parse_position({"map_id": map_id, "surface_id": str(context.get("surface_id", "")), "logical_position": {"x": logical.x, "y": logical.y}}, context)
	if not parsed_position.ok: return _blocked(CAPABILITIES.WORLD_TO_LOGICAL, str(parsed_position.get("code", "spatial.position.invalid")), str(parsed_position.get("error_zh", "逻辑位置无效。")), {}, parsed_position)
	var position = parsed_position.position
	return _success(CAPABILITIES.WORLD_TO_LOGICAL, _vector2_dict(world_value.value), {"logical_position": {"x": logical.x, "y": logical.y}, "planar_position": position.to_native()})

func get_planar_distance(from_position, to_position, context: Dictionary = {}) -> Dictionary:
	var capability := _require_capability(CAPABILITIES.PLANAR_DISTANCE)
	if not capability.ok: return capability
	var pair := _parse_pair(from_position, to_position, context, CAPABILITIES.PLANAR_DISTANCE)
	if not pair.ok: return pair
	var delta := Vector2(pair.to.x - pair.from.x, pair.to.y - pair.from.y)
	return _success(CAPABILITIES.PLANAR_DISTANCE, {"from": pair.from.to_native(), "to": pair.to.to_native()}, {"distance": delta.length()})

func get_planar_direction(from_position, to_position, context: Dictionary = {}) -> Dictionary:
	var capability := _require_capability(CAPABILITIES.PLANAR_DIRECTION)
	if not capability.ok: return capability
	var pair := _parse_pair(from_position, to_position, context, CAPABILITIES.PLANAR_DIRECTION)
	if not pair.ok: return pair
	var delta := Vector2(pair.to.x - pair.from.x, pair.to.y - pair.from.y)
	var direction := Vector2.ZERO if is_zero_approx(delta.length()) else delta.normalized()
	return _success(CAPABILITIES.PLANAR_DIRECTION, {"from": pair.from.to_native(), "to": pair.to.to_native()}, {"direction": _vector2_dict(direction), "distance": delta.length()})

func get_travel_cost(from_position, to_position, context: Dictionary = {}) -> Dictionary:
	var capability := _require_capability(CAPABILITIES.TRAVEL_COST)
	if not capability.ok: return capability
	var path_result := _find_grid_path(from_position, to_position, context)
	if not path_result.ok: return _blocked(CAPABILITIES.TRAVEL_COST, str(path_result.get("code", "spatial.path.unavailable")), str(path_result.get("error_zh", "无法计算2D通行成本。")), {}, path_result)
	return _success(CAPABILITIES.TRAVEL_COST, {"from": path_result.from.to_native(), "to": path_result.to.to_native()}, {"cost": path_result.cost, "path_length": path_result.path.size()})

func find_surface(position_or_context, context: Dictionary = {}) -> Dictionary:
	var capability := _require_capability(CAPABILITIES.FIND_SURFACE)
	if not capability.ok: return capability
	var query_context := context.duplicate(true)
	var position_value = position_or_context
	if position_or_context is Dictionary and position_or_context.has("map_id"):
		query_context = position_or_context.duplicate(true)
		position_value = position_or_context.get("planar_position", position_or_context)
	var parsed := _parse_position(position_value, query_context)
	if not parsed.ok: return _blocked(CAPABILITIES.FIND_SURFACE, str(parsed.code), str(parsed.error_zh), {}, parsed)
	var map_result := _resolve_map(parsed.position.map_id)
	if not map_result.ok: return _blocked(CAPABILITIES.FIND_SURFACE, str(map_result.code), str(map_result.error_zh), parsed.position.to_native(), map_result)
	return _success(CAPABILITIES.FIND_SURFACE, parsed.position.to_native(), {"map_id": parsed.position.map_id, "surface_id": parsed.position.surface_id, "available": true})

func find_ground_height(position, context: Dictionary = {}) -> Dictionary:
	var capability := _require_capability(CAPABILITIES.GROUND_HEIGHT)
	if not capability.ok: return capability
	var parsed := _parse_position(position, context)
	if not parsed.ok: return _blocked(CAPABILITIES.GROUND_HEIGHT, str(parsed.code), str(parsed.error_zh), {}, parsed)
	var map_result := _resolve_map(parsed.position.map_id)
	if not map_result.ok: return _blocked(CAPABILITIES.GROUND_HEIGHT, str(map_result.code), str(map_result.error_zh), parsed.position.to_native(), map_result)
	var cell_result := _cell_for_position(map_result.map, parsed.position)
	if not cell_result.ok: return _blocked(CAPABILITIES.GROUND_HEIGHT, str(cell_result.code), str(cell_result.error_zh), parsed.position.to_native(), cell_result)
	var logic: Dictionary = cell_result.logic
	return _success(CAPABILITIES.GROUND_HEIGHT, parsed.position.to_native(), {"height": float(logic.get("height_level", 0)), "cell": _cell_dict(cell_result.cell)})

func validate_walkable_position(position, context: Dictionary = {}) -> Dictionary:
	var capability := _require_capability(CAPABILITIES.VALIDATE_WALKABLE_POSITION)
	if not capability.ok: return capability
	var parsed := _parse_position(position, context)
	if not parsed.ok: return _blocked(CAPABILITIES.VALIDATE_WALKABLE_POSITION, str(parsed.code), str(parsed.error_zh), {}, parsed)
	var map_result := _resolve_map(parsed.position.map_id)
	if not map_result.ok: return _blocked(CAPABILITIES.VALIDATE_WALKABLE_POSITION, str(map_result.code), str(map_result.error_zh), parsed.position.to_native(), map_result)
	var cell_result := _cell_for_position(map_result.map, parsed.position)
	if not cell_result.ok: return _blocked(CAPABILITIES.VALIDATE_WALKABLE_POSITION, str(cell_result.code), str(cell_result.error_zh), parsed.position.to_native(), cell_result)
	if not bool(cell_result.logic.get("walkable", false)):
		return _blocked(CAPABILITIES.VALIDATE_WALKABLE_POSITION, "spatial.position.not_walkable", "逻辑位置所在单元不可通行。", parsed.position.to_native(), {"cell": _cell_dict(cell_result.cell)})
	return _success(CAPABILITIES.VALIDATE_WALKABLE_POSITION, parsed.position.to_native(), {"walkable": true, "cell": _cell_dict(cell_result.cell)})

func is_reachable(from_position, to_position, context: Dictionary = {}) -> Dictionary:
	var capability := _require_capability(CAPABILITIES.IS_REACHABLE)
	if not capability.ok: return capability
	var path_result := _find_grid_path(from_position, to_position, context)
	var path_code := str(path_result.get("code", ""))
	if not path_result.ok and (path_code == "spatial.path.unreachable" or path_code == "spatial.position.not_walkable"):
		var pair := _parse_pair(from_position, to_position, context, CAPABILITIES.IS_REACHABLE)
		if not pair.ok: return pair
		return _success(CAPABILITIES.IS_REACHABLE, {"from": pair.from.to_native(), "to": pair.to.to_native()}, {"reachable": false})
	if not path_result.ok: return _blocked(CAPABILITIES.IS_REACHABLE, str(path_result.get("code", "spatial.path.unavailable")), str(path_result.get("error_zh", "无法判断2D可达性。")), {}, path_result)
	return _success(CAPABILITIES.IS_REACHABLE, {"from": path_result.from.to_native(), "to": path_result.to.to_native()}, {"reachable": true, "cost": path_result.cost})

func request_path(from_position, to_position, context: Dictionary = {}) -> Dictionary:
	var capability := _require_capability(CAPABILITIES.REQUEST_PATH)
	if not capability.ok: return capability
	var path_result := _find_grid_path(from_position, to_position, context)
	if not path_result.ok:
		var path_code := str(path_result.get("code", "spatial.path.unavailable"))
		if path_code == "spatial.position.not_walkable": path_code = "spatial.path.unreachable"
		return _blocked(CAPABILITIES.REQUEST_PATH, path_code, str(path_result.get("error_zh", "2D路径不可用。")), {}, path_result)
	return _success(CAPABILITIES.REQUEST_PATH, {"from": path_result.from.to_native(), "to": path_result.to.to_native()}, {"path": path_result.path, "cost": path_result.cost})

func screen_to_world(screen_position, context: Dictionary = {}) -> Dictionary:
	var capability := _require_capability(CAPABILITIES.SCREEN_TO_WORLD)
	if not capability.ok: return capability
	var screen := _parse_vector2(screen_position)
	if not screen.ok: return _blocked(CAPABILITIES.SCREEN_TO_WORLD, "spatial.screen_position_invalid", "屏幕坐标必须是有限x/y。", {}, screen)
	var transform := _screen_transform_context(context)
	if not transform.ok: return _blocked(CAPABILITIES.SCREEN_TO_WORLD, str(transform.code), str(transform.error_zh), {}, transform)
	var world := Vector2(screen.value.x * transform.scale.x + transform.offset.x, screen.value.y * transform.scale.y + transform.offset.y)
	return _success(CAPABILITIES.SCREEN_TO_WORLD, _vector2_dict(screen.value), {"world_position": _vector2_dict(world)})

func world_to_screen(world_position, context: Dictionary = {}) -> Dictionary:
	var capability := _require_capability(CAPABILITIES.WORLD_TO_SCREEN)
	if not capability.ok: return capability
	var world := _parse_vector2(world_position)
	if not world.ok: return _blocked(CAPABILITIES.WORLD_TO_SCREEN, "spatial.world_position_invalid", "world坐标必须是有限x/y。", {}, world)
	var transform := _screen_transform_context(context)
	if not transform.ok: return _blocked(CAPABILITIES.WORLD_TO_SCREEN, str(transform.code), str(transform.error_zh), {}, transform)
	if is_zero_approx(transform.scale.x) or is_zero_approx(transform.scale.y): return _blocked(CAPABILITIES.WORLD_TO_SCREEN, "spatial.screen_transform_invalid", "屏幕坐标转换比例不能为零。")
	var screen := Vector2((world.value.x - transform.offset.x) / transform.scale.x, (world.value.y - transform.offset.y) / transform.scale.y)
	return _success(CAPABILITIES.WORLD_TO_SCREEN, _vector2_dict(world.value), {"screen_position": _vector2_dict(screen)})

func _require_capability(capability_id: String) -> Dictionary:
	if not _enabled: return _blocked(capability_id, "spatial.adapter.disabled", "空间扩展已关闭。")
	if _registry == null: return _blocked(capability_id, "spatial.adapter.registry_missing", "2D语义地图注册表不可用。")
	var result = capabilities().query(capability_id)
	return {"ok": true} if result.ok else _blocked(capability_id, str(result.code), str(result.get("error_zh", "空间能力不可用。")))

func _success(capability_id: String, target: Dictionary, value: Dictionary) -> Dictionary:
	return QUERY_RESULT.success(SPATIAL_DOMAIN.PLANAR_2D, capability_id, target, value)

func _blocked(capability_id: String, code: String, message: String, target: Dictionary = {}, details: Dictionary = {}) -> Dictionary:
	return QUERY_RESULT.blocked(code, message, SPATIAL_DOMAIN.PLANAR_2D, capability_id, details if details.has("target") else details.merged({"target": target}, true) if not target.is_empty() else details)

func _make_position(map_id: String, x: float, y: float, surface_id: String = ""):
	var resolved_surface := surface_id
	if resolved_surface.is_empty() and _registry != null:
		var first_surface: Dictionary = _registry.first_surface_id(map_id)
		if first_surface.ok: resolved_surface = str(first_surface.surface_id)
	if resolved_surface.is_empty(): return null
	return PLANAR_POSITION.new(map_id, resolved_surface, x, y)

func _position_from_target_native(native: Dictionary) -> Dictionary:
	var candidate = native.get("planar_position", null)
	if candidate != null:
		var parsed_planar := _parse_position(candidate)
		if not parsed_planar.ok: return parsed_planar
		if native.has("map_id") and str(native.get("map_id", "")) != str(parsed_planar.position.map_id):
			return {"ok": false, "code": "spatial.position.map_mismatch", "error_zh": "目标map_id与PlanarPosition不一致。"}
		return parsed_planar
	return _parse_position(native)

func _parse_position(value, context: Dictionary = {}) -> Dictionary:
	var native: Variant = value
	if value is Vector2:
		var map_id := str(context.get("map_id", ""))
		if map_id.is_empty(): return {"ok": false, "code": "spatial.position.map_missing", "error_zh": "Vector2适配输入必须显式提供map_id。"}
		native = {"schema_version": PLANAR_POSITION.SCHEMA_VERSION, "map_id": map_id, "surface_id": _surface_id_from_context(map_id, context), "x": value.x, "y": value.y}
	elif value is Dictionary and value.has("logical_position"):
		var wrapper: Dictionary = value
		var logical: Dictionary = wrapper.get("logical_position", {})
		if not logical is Dictionary or not logical.has("x") or not logical.has("y"): return {"ok": false, "code": "spatial.position.invalid", "error_zh": "逻辑位置包装值无效。"}
		var map_id := str(wrapper.get("map_id", context.get("map_id", "")))
		if map_id.is_empty(): return {"ok": false, "code": "spatial.position.map_missing", "error_zh": "逻辑位置必须显式提供map_id。"}
		var surface_id := str(wrapper.get("surface_id", context.get("surface_id", "")))
		native = {"schema_version": PLANAR_POSITION.SCHEMA_VERSION, "map_id": map_id, "surface_id": surface_id if not surface_id.is_empty() else _surface_id_from_context(map_id, context), "x": logical.get("x"), "y": logical.get("y")}
	var parsed := PLANAR_POSITION.from_native(native)
	if not parsed.ok: return {"ok": false, "code": "spatial.position.invalid", "error_zh": str(parsed.get("error_zh", "PlanarPosition无效。")), "details": parsed}
	var reference := _validate_position_reference(parsed.position)
	if not reference.ok: return reference
	return {"ok": true, "position": parsed.position, "map": reference.get("map", null), "semantic_map": reference.get("semantic_map", null)}

func _validate_position_reference(position) -> Dictionary:
	if position == null: return {"ok": false, "code": "spatial.position.invalid", "error_zh": "空间位置不能为空。"}
	var map_result := _resolve_map(str(position.map_id))
	if not map_result.ok: return map_result
	var surface_result: Dictionary = _registry.resolve_surface(str(position.map_id), str(position.surface_id))
	if not surface_result.ok:
		var semantic_map = map_result.get("semantic_map", null)
		var registered_surface_ids: Array = []
		if semantic_map != null: registered_surface_ids = Array(semantic_map.surface_ids)
		return {"ok": false, "code": "spatial.surface.missing", "error_zh": "空间位置引用了不存在或不属于该地图的Surface。", "map_id": str(position.map_id), "surface_id": str(position.surface_id), "registered_surface_ids": registered_surface_ids}
	return {"ok": true, "map": map_result.get("map", null), "semantic_map": map_result.get("semantic_map", null), "map_id": str(position.map_id), "surface_id": str(position.surface_id)}

func _surface_id_from_context(map_id: String, context: Dictionary) -> String:
	var explicit := str(context.get("surface_id", "")).strip_edges()
	if not explicit.is_empty(): return explicit
	if _registry != null:
		var first_surface: Dictionary = _registry.first_surface_id(map_id)
		if first_surface.ok: return str(first_surface.surface_id)
	return ""

func _parse_pair(from_value, to_value, context: Dictionary, capability_id: String) -> Dictionary:
	var from := _parse_position(from_value, context)
	if not from.ok: return _blocked(capability_id, str(from.code), str(from.error_zh), {}, from)
	var to := _parse_position(to_value, context)
	if not to.ok: return _blocked(capability_id, str(to.code), str(to.error_zh), {}, to)
	if from.position.map_id != to.position.map_id or from.position.surface_id != to.position.surface_id:
		return _blocked(capability_id, "spatial.surface.mismatch", "两个逻辑位置不在同一地图Surface上。", {"from": from.position.to_native(), "to": to.position.to_native()})
	return {"ok": true, "from": from.position, "to": to.position}

func _resolve_map(map_id: String) -> Dictionary:
	if _registry == null: return {"ok": false, "code": "spatial.map.missing", "error_zh": "2D语义地图注册表不可用。"}
	var result = _registry.resolve_map(map_id)
	if not result.ok: return {"ok": false, "code": str(result.get("code", "spatial.map.missing")), "error_zh": str(result.get("error_zh", "语义地图不存在。"))}
	var semantic_map = result.get("map", null)
	if semantic_map == null: return {"ok": false, "code": "spatial.map.invalid", "error_zh": "语义地图资源无效。"}
	if str(semantic_map.get("map_id")) != map_id: return {"ok": false, "code": "spatial.map.invalid", "error_zh": "语义地图稳定ID与注册键不一致。"}
	var terrain_map = semantic_map.get("terrain_map") if semantic_map is Resource else null
	if terrain_map == null or not terrain_map.has_method("in_bounds"): return {"ok": false, "code": "spatial.map.invalid", "error_zh": "语义地图缺少可查询的任务08逻辑地形。"}
	if str(terrain_map.get("map_id")) != map_id: return {"ok": false, "code": "spatial.map.invalid", "error_zh": "语义地图地形稳定ID与注册键不一致。"}
	var resolved: Dictionary = result.duplicate()
	resolved["semantic_map"] = semantic_map
	resolved["map"] = terrain_map
	return resolved

func _cell_for_position(map, position) -> Dictionary:
	if map == null: return {"ok": false, "code": "spatial.map.missing", "error_zh": "地形地图不存在。"}
	var tile_size: Vector2i = map.tile_size
	if tile_size.x <= 0 or tile_size.y <= 0: return {"ok": false, "code": "spatial.map.invalid", "error_zh": "地形地图tile_size无效。"}
	var cell := Vector2i(floori(position.x / float(tile_size.x)), floori(position.y / float(tile_size.y)))
	if not map.in_bounds(cell): return {"ok": false, "code": "spatial.position.out_of_bounds", "error_zh": "逻辑位置超出地图边界。", "cell": cell}
	var logic: Dictionary = map.logic_cells.get(MAP_RESOURCE.cell_key(cell), {})
	if logic.is_empty(): return {"ok": false, "code": "spatial.cell_missing", "error_zh": "地图逻辑单元未定义。", "cell": cell}
	return {"ok": true, "cell": cell, "logic": logic}

func _find_grid_path(from_value, to_value, context: Dictionary) -> Dictionary:
	var pair := _parse_pair(from_value, to_value, context, CAPABILITIES.REQUEST_PATH)
	if not pair.ok: return pair
	var map_result := _resolve_map(pair.from.map_id)
	if not map_result.ok: return map_result
	var map = map_result.map
	var start_result := _cell_for_position(map, pair.from)
	var end_result := _cell_for_position(map, pair.to)
	if not start_result.ok: return start_result
	if not end_result.ok: return end_result
	if not bool(start_result.logic.get("walkable", false)) or not bool(end_result.logic.get("walkable", false)):
		return {"ok": false, "code": "spatial.position.not_walkable", "error_zh": "路径起点或终点不可通行。"}
	var start: Vector2i = start_result.cell
	var goal: Vector2i = end_result.cell
	var queue: Array[Vector2i] = [start]
	var came_from: Dictionary = {MAP_RESOURCE.cell_key(start): ""}
	var cost_by_key: Dictionary = {MAP_RESOURCE.cell_key(start): 0.0}
	var found := start == goal
	var cursor := 0
	while cursor < queue.size() and not found:
		var current: Vector2i = queue[cursor]
		cursor += 1
		for neighbor in _neighbors(current):
			if not map.in_bounds(neighbor): continue
			var key := MAP_RESOURCE.cell_key(neighbor)
			if came_from.has(key): continue
			var logic: Dictionary = map.logic_cells.get(key, {})
			if logic.is_empty() or not bool(logic.get("walkable", false)): continue
			came_from[key] = MAP_RESOURCE.cell_key(current)
			cost_by_key[key] = float(cost_by_key.get(MAP_RESOURCE.cell_key(current), 0.0)) + maxf(0.0, float(logic.get("cost", 1.0)))
			queue.append(neighbor)
			if neighbor == goal:
				found = true
				break
	if not found: return {"ok": false, "code": "spatial.path.unreachable", "error_zh": "两个逻辑位置之间没有可达路径。"}
	var cells: Array[Vector2i] = []
	var current := goal
	while true:
		cells.push_front(current)
		if current == start: break
		var previous_key := str(came_from.get(MAP_RESOURCE.cell_key(current), ""))
		var pieces := previous_key.split(",")
		current = Vector2i(int(pieces[0]), int(pieces[1]))
	var path: Array = []
	for cell in cells:
		var center := Vector2((float(cell.x) + 0.5) * float(map.tile_size.x), (float(cell.y) + 0.5) * float(map.tile_size.y))
		path.append(_make_position(pair.from.map_id, center.x, center.y, pair.from.surface_id).to_native())
	return {"ok": true, "from": pair.from, "to": pair.to, "path": path, "cost": float(cost_by_key.get(MAP_RESOURCE.cell_key(goal), 0.0))}

func _neighbors(cell: Vector2i) -> Array[Vector2i]:
	return [cell + Vector2i.RIGHT, cell + Vector2i.DOWN, cell + Vector2i.LEFT, cell + Vector2i.UP]

func _transform_context(context: Dictionary) -> Dictionary:
	var scale := _parse_vector2(context.get("scale", Vector2.ONE))
	var offset := _parse_vector2(context.get("offset", Vector2.ZERO))
	if not scale.ok or not offset.ok: return {"ok": false, "code": "spatial.world_transform_invalid", "error_zh": "world转换上下文必须包含有限scale/offset。"}
	return {"ok": true, "scale": scale.value, "offset": offset.value}

func _screen_transform_context(context: Dictionary) -> Dictionary:
	var scale := _parse_vector2(context.get("screen_scale", context.get("scale", Vector2.ONE)))
	var offset := _parse_vector2(context.get("screen_offset", context.get("offset", Vector2.ZERO)))
	if not scale.ok or not offset.ok: return {"ok": false, "code": "spatial.screen_transform_invalid", "error_zh": "屏幕转换上下文必须包含有限scale/offset。"}
	return {"ok": true, "scale": scale.value, "offset": offset.value}

func _parse_vector2(value) -> Dictionary:
	var result := Vector2.ZERO
	if value is Vector2:
		result = value
	elif value is Dictionary and value.has("x") and value.has("y"):
		result = Vector2(float(value.get("x")), float(value.get("y")))
	else:
		return {"ok": false, "code": "spatial.vector2_invalid", "error_zh": "二维坐标必须是Vector2或x/y Dictionary。"}
	if not is_finite(result.x) or not is_finite(result.y): return {"ok": false, "code": "spatial.vector2_nonfinite", "error_zh": "二维坐标不得是NaN或INF。"}
	return {"ok": true, "value": result}

func _vector2_dict(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}

func _cell_dict(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}
