class_name GMSemanticRuntime
extends RefCounted

var registry: GMMapSemanticRegistry
var _active_regions_by_actor: Dictionary = {}

func _init(value_registry: GMMapSemanticRegistry = null) -> void:
	registry = value_registry if value_registry != null else GMMapSemanticRegistry.new()

func update_actor_regions(map_id: StringName, actor_id: String, world_position: Vector2, actor: Object = null) -> Dictionary:
	var map_result := registry.resolve_map(map_id)
	if not map_result.ok: return map_result
	var current: Array[GMSemanticRegion] = map_result.map.regions_at(world_position)
	var current_ids := PackedStringArray()
	for region in current: current_ids.append(str(region.region_id))
	var key := "%s::%s" % [map_id, actor_id]
	var previous: PackedStringArray = _active_regions_by_actor.get(key, PackedStringArray())
	var events: Array[GMGameplayEvent] = []
	for region in current:
		if not previous.has(str(region.region_id)):
			events.append(GMGameplayEvent.new(str(region.enter_event_tag), actor, null, {"map_id": str(map_id), "region_id": str(region.region_id), "actor_id": actor_id, "position": world_position}, "gm.map.semantic"))
	for old_id in previous:
		if not current_ids.has(old_id):
			var old: Dictionary = map_result.map.resolve_region(old_id)
			if old.ok: events.append(GMGameplayEvent.new(str(old.region.exit_event_tag), actor, null, {"map_id": str(map_id), "region_id": old_id, "actor_id": actor_id, "position": world_position}, "gm.map.semantic"))
	_active_regions_by_actor[key] = current_ids
	return {"ok": true, "entered": _difference(current_ids, previous), "exited": _difference(previous, current_ids), "events": events, "active_region_ids": current_ids}

func make_test_launch(map_id: StringName, anchor_id: StringName = &"", cursor_position: Variant = null) -> Dictionary:
	var position := Vector2.ZERO
	var source := "cursor"
	if not str(anchor_id).is_empty():
		var resolved := registry.resolve_anchor(map_id, anchor_id)
		if not resolved.ok: return resolved
		position = resolved.anchor.position
		source = "anchor"
	elif cursor_position is Vector2: position = cursor_position
	else: return {"ok": false, "code": "semantic.test_position_missing", "error_zh": "从当前位置测试缺少光标或锚点"}
	return {"ok": true, "ephemeral": true, "persist_to_save": false, "map_id": str(map_id), "anchor_id": str(anchor_id), "position": position, "source": source}

static func sanitize_save_payload(payload: Dictionary) -> Dictionary:
	var result := payload.duplicate(true)
	result.erase("semantic_test_launch")
	result.erase("test_cursor_position")
	result.erase("test_anchor_id")
	return result

func _difference(left: PackedStringArray, right: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for item in left:
		if not right.has(item): result.append(item)
	return result
