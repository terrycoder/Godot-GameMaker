class_name GMMapSemanticValidator
extends RefCounted

class ValidationSession:
	extends RefCounted
	var registry: GMMapSemanticRegistry
	var queue: Array[GMMapSemanticResource] = []
	var rules: Array = []
	var results: Array[Dictionary] = []
	var processed := 0
	var cancelled := false
	var complete := false

	func step(max_maps: int = 1) -> Dictionary:
		if cancelled: return {"ok": false, "code": "semantic.validation_cancelled", "cancelled": true, "complete": true, "processed": processed, "results": results}
		for count in mini(maxi(max_maps, 1), queue.size()):
			var map: GMMapSemanticResource = queue.pop_front()
			results.append_array(GMMapSemanticValidator._validate_map(map, registry))
			for rule in rules:
				if rule != null and rule.has_method("validate_map"):
					var custom: Variant = rule.call("validate_map", map, registry)
					if custom is Array: results.append_array(custom)
			processed += 1
		complete = queue.is_empty()
		return {"ok": complete and results.is_empty(), "cancelled": false, "complete": complete, "processed": processed, "remaining": queue.size(), "results": results.duplicate(true)}

	func cancel() -> Dictionary:
		cancelled = true
		queue.clear()
		return {"ok": true, "cancelled": true, "processed": processed, "results": results.duplicate(true)}

func begin(registry: GMMapSemanticRegistry, extension_rules: Array = []) -> ValidationSession:
	var session := ValidationSession.new()
	session.registry = registry
	for map_id in registry.map_ids():
		var resolved := registry.resolve_map(map_id)
		if resolved.ok: session.queue.append(resolved.map)
	session.rules = extension_rules.duplicate()
	return session

static func _validate_map(map: GMMapSemanticResource, registry: GMMapSemanticRegistry) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var definition := map.validate_definition(registry)
	for row in definition.errors: results.append(_located(row, map.map_id))
	for anchor in map.anchors:
		if str(anchor.anchor_type_id).contains("spawn"):
			var containing := map.regions_at(anchor.position)
			if containing.size() > 1: results.append(_issue("semantic.spawn_overlap", "出生锚点位于多个区域重叠处", map.map_id, anchor.anchor_id, "anchors"))
	for region in map.regions:
		var connected := false
		for anchor in map.anchors:
			if region.contains_point(anchor.position): connected = true; break
		if not connected:
			for route in map.routes:
				for point in route.points:
					if region.contains_point(point.get("position", Vector2.INF)): connected = true; break
				if connected: break
		if not connected: results.append(_issue("semantic.region_isolated", "区域没有锚点或路线连接", map.map_id, region.region_id, "regions"))
	return results

static func _located(row: Dictionary, map_id: StringName) -> Dictionary:
	var result := row.duplicate(true)
	result["map_id"] = str(result.get("map_id", map_id))
	result["object_id"] = str(result.get("object_id", ""))
	result["rule_id"] = str(result.get("code", "semantic.validation.unknown"))
	result["mutated"] = false
	return result

static func _issue(code: String, message: String, map_id: StringName, object_id: StringName, collection: String) -> Dictionary:
	return {"code": code, "rule_id": code, "error_zh": message, "map_id": str(map_id), "object_id": str(object_id), "collection": collection, "mutated": false}
