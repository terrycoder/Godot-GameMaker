@tool
class_name GMMapSemanticResource
extends Resource

const SCHEMA := "gm.map.semantic.v1"
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

@export var map_id: StringName
@export var terrain_map: GMMapResource
@export var regions: Array[GMSemanticRegion] = []
@export var routes: Array[GMSemanticRoute] = []
@export var anchors: Array[GMSemanticAnchor] = []
@export var portals: Array[GMSemanticPortal] = []
@export var camera_zones: Array[GMCameraZoneConfig] = []
## Explicit, serializable Surface identities owned by this map.  A map may
## expose more than one surface; the adapter must resolve membership here
## rather than deriving a private name from map_id.
@export var surface_ids: PackedStringArray = []
@export var schema_version: String = SCHEMA

func register_surface(surface_id: Variant) -> Dictionary:
	var normalized := str(surface_id).strip_edges()
	if normalized.is_empty() or not PLANAR_POSITION.is_valid_stable_id(normalized):
		return {"ok": false, "code": "semantic.surface_invalid", "error_zh": "Surface必须是非空稳定ID。", "map_id": str(map_id), "surface_id": normalized}
	if surface_ids.has(normalized):
		return {"ok": false, "code": "semantic.surface_duplicate", "error_zh": "Surface稳定ID重复：%s" % normalized, "map_id": str(map_id), "surface_id": normalized}
	surface_ids.append(normalized)
	surface_ids.sort()
	return {"ok": true, "map_id": str(map_id), "surface_id": normalized}

func resolve_surface(surface_id: Variant) -> Dictionary:
	var normalized := str(surface_id)
	if not surface_ids.has(normalized):
		return {"ok": false, "code": "semantic.surface_missing", "error_zh": "地图%s未注册Surface：%s" % [map_id, normalized], "map_id": str(map_id), "surface_id": normalized}
	return {"ok": true, "map_id": str(map_id), "surface_id": normalized}

func has_surface(surface_id: Variant) -> bool:
	return surface_ids.has(str(surface_id))

func first_surface_id() -> String:
	return str(surface_ids[0]) if not surface_ids.is_empty() else ""

func validate_surface_registration() -> Dictionary:
	var errors: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_surface_id in surface_ids:
		var normalized := str(raw_surface_id).strip_edges()
		if normalized.is_empty() or not PLANAR_POSITION.is_valid_stable_id(normalized):
			errors.append({"code": "semantic.surface_invalid", "error_zh": "Surface必须是非空稳定ID：%s" % normalized, "map_id": str(map_id), "surface_id": normalized})
			continue
		if normalized != str(raw_surface_id):
			errors.append({"code": "semantic.surface_whitespace", "error_zh": "Surface稳定ID不得包含首尾空白：%s" % raw_surface_id, "map_id": str(map_id), "surface_id": str(raw_surface_id)})
		if seen.has(normalized):
			errors.append({"code": "semantic.surface_duplicate", "error_zh": "Surface稳定ID重复：%s" % normalized, "map_id": str(map_id), "surface_id": normalized})
		seen[normalized] = true
	return {"ok": errors.is_empty(), "errors": errors, "errors_zh": errors.map(func(row): return row.get("error_zh", "")), "map_id": str(map_id), "surface_ids": Array(surface_ids)}

## Compatibility registration for old serialized map resources that predate
## the explicit Surface relation.  This runs at map registration time and
## stores the result in surface_ids; the adapter never derives this formula.
func ensure_legacy_surface_registration() -> Dictionary:
	if not surface_ids.is_empty():
		return validate_surface_registration()
	var legacy_id := "gm.surface.planar_2d.%s" % str(map_id)
	return register_surface(legacy_id)

func resolve_anchor(anchor_id: StringName) -> Dictionary:
	for anchor in anchors:
		if anchor.anchor_id == anchor_id: return {"ok": true, "anchor": anchor, "anchor_id": str(anchor_id), "map_id": str(map_id)}
	return {"ok": false, "code": "semantic.anchor_missing", "error_zh": "地图%s缺少锚点：%s" % [map_id, anchor_id], "map_id": str(map_id), "object_id": str(anchor_id)}

func resolve_region(region_id: StringName) -> Dictionary:
	for region in regions:
		if region.region_id == region_id: return {"ok": true, "region": region, "region_id": str(region_id), "map_id": str(map_id)}
	return {"ok": false, "code": "semantic.region_missing", "error_zh": "地图%s缺少区域：%s" % [map_id, region_id], "map_id": str(map_id), "object_id": str(region_id)}

func resolve_route(route_id: StringName) -> Dictionary:
	for route in routes:
		if route.route_id == route_id: return {"ok": true, "route": route, "route_id": str(route_id), "map_id": str(map_id)}
	return {"ok": false, "code": "semantic.route_missing", "error_zh": "地图%s缺少路线：%s" % [map_id, route_id], "map_id": str(map_id), "object_id": str(route_id)}

func validate_definition(registry: GMMapSemanticRegistry = null) -> Dictionary:
	var errors: Array[Dictionary] = []
	if str(map_id).strip_edges().is_empty(): errors.append(_error("semantic.map_id_missing", "语义地图必须引用稳定地图ID", "map_id", ""))
	if terrain_map == null: errors.append(_error("semantic.terrain_map_missing", "语义地图缺少任务08地形资源", "terrain_map", str(map_id)))
	elif str(terrain_map.map_id) != str(map_id): errors.append(_error("semantic.terrain_map_mismatch", "语义地图ID与地形地图ID不一致", "terrain_map.map_id", str(map_id)))
	_validate_collection(regions, "region_id", "semantic.region_duplicate", errors)
	_validate_collection(routes, "route_id", "semantic.route_duplicate", errors)
	_validate_collection(anchors, "anchor_id", "semantic.anchor_duplicate", errors)
	_validate_collection(portals, "portal_id", "semantic.portal_duplicate", errors)
	_validate_collection(camera_zones, "camera_id", "semantic.camera_duplicate", errors)
	var surface_validation := validate_surface_registration()
	for surface_error in surface_validation.get("errors", []): errors.append(surface_error)
	for region in regions:
		_append_errors(region.validate_definition(), errors)
		if not str(region.camera_config_id).is_empty() and not _has_camera(region.camera_config_id): errors.append(_error("semantic.camera_reference_missing", "区域引用的相机配置不存在：%s" % region.camera_config_id, "camera_config_id", str(region.region_id)))
	for route in routes:
		_append_errors(route.validate_definition(), errors)
		for point in route.points:
			var point_map_id := str(point.get("map_id", map_id))
			if point_map_id != str(map_id) and not _has_portal_to(point_map_id):
				errors.append(_error("semantic.route_cross_map_without_portal", "路线跨地图但没有语义传送连接：%s" % point_map_id, "points.map_id", str(route.route_id)))
		for anchor_id in route.referenced_anchor_ids():
			if not resolve_anchor(anchor_id).ok: errors.append(_error("semantic.route_anchor_missing", "路线引用的锚点不存在：%s" % anchor_id, "points.anchor_id", str(route.route_id)))
		if terrain_map != null: _append_errors(route.validate_reachability(terrain_map), errors)
	for anchor in anchors: _append_errors(anchor.validate_definition(), errors)
	for portal in portals: _append_errors(portal.validate_definition(registry), errors)
	for camera in camera_zones: _append_errors(camera.validate_definition(), errors)
	_validate_region_conflicts(errors)
	_validate_camera_conflicts(errors)
	return {"ok": errors.is_empty(), "errors": errors, "errors_zh": errors.map(func(row): return row.get("error_zh", "")), "map_id": str(map_id), "schema_version": schema_version}

func regions_at(world_position: Vector2) -> Array[GMSemanticRegion]:
	var matches: Array[GMSemanticRegion] = []
	for region in regions:
		if region.contains_point(world_position): matches.append(region)
	matches.sort_custom(func(a, b): return a.priority > b.priority)
	if matches.size() > 1 and matches[0].overlap_rule == GMSemanticRegion.OverlapRule.HIGHEST_PRIORITY:
		return [matches[0]]
	return matches

func camera_at(world_position: Vector2, target_role_id: StringName) -> Dictionary:
	var matches: Array[GMCameraZoneConfig] = []
	for camera in camera_zones:
		if camera.contains_point(world_position) and camera.target_role_id == target_role_id: matches.append(camera)
	if matches.is_empty(): return {"ok": false, "code": "semantic.camera_zone_missing", "error_zh": "当前位置没有适用相机区", "map_id": str(map_id)}
	matches.sort_custom(func(a, b): return a.priority > b.priority)
	if matches.size() > 1 and matches[0].priority == matches[1].priority: return {"ok": false, "code": "semantic.camera_priority_conflict", "error_zh": "重叠相机区优先级冲突", "map_id": str(map_id), "objects": [str(matches[0].camera_id), str(matches[1].camera_id)]}
	return {"ok": true, "camera": matches[0], "camera_id": str(matches[0].camera_id), "map_id": str(map_id)}

func _validate_collection(values: Array, property_name: String, duplicate_code: String, errors: Array[Dictionary]) -> void:
	var seen := {}
	for value in values:
		if value == null:
			errors.append(_error("semantic.object_null", "语义对象不能为空", property_name, str(map_id)))
			continue
		var identity := str(value.get(property_name))
		if seen.has(identity): errors.append(_error(duplicate_code, "稳定ID重复：%s" % identity, property_name, identity))
		seen[identity] = true

func _validate_region_conflicts(errors: Array[Dictionary]) -> void:
	for index in regions.size():
		for other_index in range(index + 1, regions.size()):
			var a := regions[index]
			var b := regions[other_index]
			if not a.overlaps(b): continue
			if a.overlap_rule == GMSemanticRegion.OverlapRule.EXCLUSIVE or b.overlap_rule == GMSemanticRegion.OverlapRule.EXCLUSIVE:
				errors.append(_error("semantic.region_overlap_exclusive", "互斥区域发生重叠：%s / %s" % [a.region_id, b.region_id], "overlap_rule", str(a.region_id)))
			elif a.priority == b.priority and (a.overlap_rule == GMSemanticRegion.OverlapRule.HIGHEST_PRIORITY or b.overlap_rule == GMSemanticRegion.OverlapRule.HIGHEST_PRIORITY):
				errors.append(_error("semantic.region_priority_conflict", "重叠区域优先级冲突：%s / %s" % [a.region_id, b.region_id], "priority", str(a.region_id)))

func _validate_camera_conflicts(errors: Array[Dictionary]) -> void:
	for index in camera_zones.size():
		for other_index in range(index + 1, camera_zones.size()):
			var a := camera_zones[index]
			var b := camera_zones[other_index]
			if a.bounds.intersects(b.bounds) and a.priority == b.priority:
				errors.append(_error("semantic.camera_priority_conflict", "重叠相机区没有唯一优先级：%s / %s" % [a.camera_id, b.camera_id], "priority", str(a.camera_id)))

func _has_camera(camera_id: StringName) -> bool:
	for camera in camera_zones:
		if camera.camera_id == camera_id: return true
	return false

func _has_portal_to(target_map_id: String) -> bool:
	for portal in portals:
		if str(portal.target_map_id) == target_map_id: return true
	return false

func _append_errors(result: Dictionary, target: Array[Dictionary]) -> void:
	for row in result.get("errors", []): target.append(row)

func _error(code: String, message: String, field: String, object_id: String) -> Dictionary:
	return {"code": code, "error_zh": message, "field": field, "object_id": object_id, "map_id": str(map_id)}
