@tool
class_name GMSemanticRegion
extends Resource

enum OverlapRule { STACK, HIGHEST_PRIORITY, EXCLUSIVE }

@export var region_id: StringName
@export var polygon: PackedVector2Array = PackedVector2Array()
@export var tags: PackedStringArray = PackedStringArray()
@export var priority: int = 0
@export var overlap_rule: OverlapRule = OverlapRule.STACK
@export var enter_event_tag: StringName = &"gm.event.map.region.entered"
@export var exit_event_tag: StringName = &"gm.event.map.region.exited"
@export var camera_config_id: StringName

func validate_definition() -> Dictionary:
	var errors: Array[Dictionary] = []
	if str(region_id).strip_edges().is_empty(): errors.append(_error("semantic.region_id_missing", "区域稳定ID不能为空", "region_id"))
	if polygon.size() < 3: errors.append(_error("semantic.region_shape_invalid", "区域形状至少需要3个点", "polygon"))
	elif _has_self_intersection(): errors.append(_error("semantic.region_self_intersection", "区域多边形发生非法自交", "polygon"))
	return {"ok": errors.is_empty(), "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh), "region_id": str(region_id)}

func contains_point(world_position: Vector2) -> bool:
	return polygon.size() >= 3 and Geometry2D.is_point_in_polygon(world_position, polygon)

func overlaps(other: GMSemanticRegion) -> bool:
	if other == null or polygon.size() < 3 or other.polygon.size() < 3: return false
	for point in polygon:
		if other.contains_point(point): return true
	for point in other.polygon:
		if contains_point(point): return true
	for index in polygon.size():
		var a1 := polygon[index]
		var a2 := polygon[(index + 1) % polygon.size()]
		for other_index in other.polygon.size():
			if _segments_intersect(a1, a2, other.polygon[other_index], other.polygon[(other_index + 1) % other.polygon.size()]): return true
	return false

func copy_with_id(new_id: StringName) -> Dictionary:
	if str(new_id).strip_edges().is_empty() or new_id == region_id:
		return {"ok": false, "code": "semantic.region_copy_id_invalid", "error_zh": "复制区域必须提供新的稳定ID", "object_id": str(region_id)}
	var result: GMSemanticRegion = duplicate(true)
	result.region_id = new_id
	return {"ok": true, "region": result, "region_id": str(new_id)}

func _has_self_intersection() -> bool:
	for index in polygon.size():
		var next := (index + 1) % polygon.size()
		for other in range(index + 1, polygon.size()):
			var other_next := (other + 1) % polygon.size()
			if index == other or next == other or index == other_next: continue
			if _segments_intersect(polygon[index], polygon[next], polygon[other], polygon[other_next]): return true
	return false

static func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab := b - a
	var cd := d - c
	var denominator := ab.cross(cd)
	if is_zero_approx(denominator): return false
	var ac := c - a
	var t := ac.cross(cd) / denominator
	var u := ac.cross(ab) / denominator
	return t > 0.00001 and t < 0.99999 and u > 0.00001 and u < 0.99999

func _error(code: String, message: String, field: String) -> Dictionary:
	return {"code": code, "error_zh": message, "field": field, "object_id": str(region_id)}
