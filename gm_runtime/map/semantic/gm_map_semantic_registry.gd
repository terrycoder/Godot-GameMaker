class_name GMMapSemanticRegistry
extends RefCounted

var _maps: Dictionary = {}

func register_map(resource: GMMapSemanticResource) -> Dictionary:
	if resource == null or str(resource.map_id).strip_edges().is_empty(): return {"ok": false, "code": "semantic.map_invalid", "error_zh": "不能注册空语义地图或空地图ID"}
	var key := str(resource.map_id)
	if _maps.has(key): return {"ok": false, "code": "semantic.map_duplicate", "error_zh": "语义地图ID重复：%s" % key, "map_id": key}
	var surface_validation := resource.validate_surface_registration()
	if not surface_validation.ok:
		return {"ok": false, "code": "semantic.surface_invalid", "error_zh": "语义地图Surface注册关系无效。", "map_id": key, "errors": surface_validation.errors, "errors_zh": surface_validation.errors_zh}
	if resource.surface_ids.is_empty():
		var legacy_surface := resource.ensure_legacy_surface_registration()
		if not legacy_surface.ok: return legacy_surface
	_maps[key] = resource
	return {"ok": true, "map_id": key}

func replace_map(resource: GMMapSemanticResource) -> Dictionary:
	if resource == null or str(resource.map_id).strip_edges().is_empty(): return {"ok": false, "code": "semantic.map_invalid", "error_zh": "不能替换为空语义地图"}
	var key := str(resource.map_id)
	var surface_validation := resource.validate_surface_registration()
	if not surface_validation.ok:
		return {"ok": false, "code": "semantic.surface_invalid", "error_zh": "语义地图Surface注册关系无效。", "map_id": key, "errors": surface_validation.errors, "errors_zh": surface_validation.errors_zh}
	if resource.surface_ids.is_empty():
		var legacy_surface := resource.ensure_legacy_surface_registration()
		if not legacy_surface.ok: return legacy_surface
	_maps[key] = resource
	return {"ok": true, "map_id": key}

func resolve_map(map_id: StringName) -> Dictionary:
	var key := str(map_id)
	if not _maps.has(key): return {"ok": false, "code": "semantic.map_missing", "error_zh": "语义地图不存在：%s" % key, "map_id": key}
	return {"ok": true, "map": _maps[key], "map_id": key}

func resolve_anchor(map_id: StringName, anchor_id: StringName) -> Dictionary:
	var map_result := resolve_map(map_id)
	if not map_result.ok: return map_result
	return map_result.map.resolve_anchor(anchor_id)

func register_surface(map_id: StringName, surface_id: Variant) -> Dictionary:
	var map_result := resolve_map(map_id)
	if not map_result.ok: return map_result
	return map_result.map.register_surface(surface_id)

func resolve_surface(map_id: StringName, surface_id: Variant) -> Dictionary:
	var map_result := resolve_map(map_id)
	if not map_result.ok: return map_result
	return map_result.map.resolve_surface(surface_id)

func first_surface_id(map_id: StringName) -> Dictionary:
	var map_result := resolve_map(map_id)
	if not map_result.ok: return map_result
	var surface_id: String = map_result.map.first_surface_id()
	if surface_id.is_empty(): return {"ok": false, "code": "semantic.surface_missing", "error_zh": "语义地图没有注册Surface。", "map_id": str(map_id)}
	return {"ok": true, "map_id": str(map_id), "surface_id": surface_id}

func validate_all() -> Dictionary:
	var errors: Array[Dictionary] = []
	for key in _maps:
		var result: Dictionary = _maps[key].validate_definition(self)
		for row in result.errors: errors.append(row)
	return {"ok": errors.is_empty(), "errors": errors, "map_count": _maps.size()}

func map_ids() -> PackedStringArray:
	var result := PackedStringArray(_maps.keys())
	result.sort()
	return result
