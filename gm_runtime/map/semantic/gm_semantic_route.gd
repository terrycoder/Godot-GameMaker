@tool
class_name GMSemanticRoute
extends Resource

@export var route_id: StringName
@export var map_id: StringName
@export var points: Array[Dictionary] = []
@export var closed: bool = false
@export var allowed_movement_types: PackedStringArray = PackedStringArray(["walk"])

func validate_definition() -> Dictionary:
	var errors: Array[Dictionary] = []
	if str(route_id).strip_edges().is_empty(): errors.append(_error("semantic.route_id_missing", "路线稳定ID不能为空", "route_id"))
	if str(map_id).strip_edges().is_empty(): errors.append(_error("semantic.route_map_missing", "路线必须引用地图ID", "map_id"))
	if points.size() < 2: errors.append(_error("semantic.route_disconnected", "路线至少需要2个有序点", "points"))
	if allowed_movement_types.is_empty(): errors.append(_error("semantic.route_movement_missing", "路线必须声明允许移动类型", "allowed_movement_types"))
	for index in points.size():
		var row: Dictionary = points[index]
		if not row.has("position") or not row.position is Vector2: errors.append(_error("semantic.route_point_invalid", "路线点%d缺少位置" % index, "points[%d]" % index))
		if float(row.get("speed", 1.0)) <= 0.0: errors.append(_error("semantic.route_speed_invalid", "路线点%d速度必须大于0" % index, "points[%d].speed" % index))
		if float(row.get("wait", 0.0)) < 0.0: errors.append(_error("semantic.route_wait_invalid", "路线点%d停留不能为负数" % index, "points[%d].wait" % index))
	return {"ok": errors.is_empty(), "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh), "route_id": str(route_id)}

func reverse_points() -> void:
	points.reverse()

func referenced_anchor_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for row in points:
		var anchor_id := str(row.get("anchor_id", "")).strip_edges()
		if not anchor_id.is_empty() and not result.has(anchor_id): result.append(anchor_id)
	return result

func validate_reachability(map: GMMapResource) -> Dictionary:
	var errors: Array[Dictionary] = []
	if map == null or str(map.map_id) != str(map_id):
		errors.append(_error("semantic.route_map_mismatch", "路线地图不存在或地图ID不匹配：%s" % map_id, "map_id"))
		return {"ok": false, "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh)}
	for index in points.size():
		var position: Vector2 = points[index].get("position", Vector2.INF)
		var cell := Vector2i(floori(position.x / map.tile_size.x), floori(position.y / map.tile_size.y))
		var logic: Dictionary = map.logic_cells.get(GMMapResource.cell_key(cell), {})
		if not map.in_bounds(cell) or logic.is_empty() or not bool(logic.get("walkable", false)):
			errors.append(_error("semantic.route_unwalkable", "路线点%d位于不可通行单元：%s" % [index, cell], "points[%d]" % index))
	for index in maxi(points.size() - 1, 0):
		_validate_segment(map, index, index + 1, errors)
	if closed and points.size() > 2: _validate_segment(map, points.size() - 1, 0, errors)
	return {"ok": errors.is_empty(), "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh), "route_id": str(route_id)}

func _validate_segment(map: GMMapResource, from_index: int, to_index: int, errors: Array[Dictionary]) -> void:
	var from: Vector2 = points[from_index].get("position", Vector2.ZERO)
	var to: Vector2 = points[to_index].get("position", Vector2.ZERO)
	var steps := maxi(1, ceili(from.distance_to(to) / maxf(1.0, minf(map.tile_size.x, map.tile_size.y) * 0.5)))
	for step in range(steps + 1):
		var sample := from.lerp(to, float(step) / float(steps))
		var cell := Vector2i(floori(sample.x / map.tile_size.x), floori(sample.y / map.tile_size.y))
		var logic: Dictionary = map.logic_cells.get(GMMapResource.cell_key(cell), {})
		if not map.in_bounds(cell) or logic.is_empty() or not bool(logic.get("walkable", false)):
			errors.append(_error("semantic.route_segment_blocked", "路线段%d→%d经过不可通行单元：%s" % [from_index, to_index, cell], "points"))
			return

func _error(code: String, message: String, field: String) -> Dictionary:
	return {"code": code, "error_zh": message, "field": field, "object_id": str(route_id), "map_id": str(map_id)}
