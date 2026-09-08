extends Node

func _ready() -> void:
	var registry := GMMapSemanticRegistry.new()
	var alpha := GMMapSemanticResource.new(); alpha.map_id = &"map.export.alpha"
	var start := GMSemanticAnchor.new(); start.anchor_id = &"anchor.start"; start.position = Vector2.ZERO
	var goal := GMSemanticAnchor.new(); goal.anchor_id = &"anchor.goal"; goal.position = Vector2(32.0, 0.0)
	var return_anchor := GMSemanticAnchor.new(); return_anchor.anchor_id = &"anchor.return"; return_anchor.position = Vector2(0.0, 16.0)
	alpha.anchors = [start, goal, return_anchor]
	var beta := GMMapSemanticResource.new(); beta.map_id = &"map.export.beta"
	var exit_anchor := GMSemanticAnchor.new(); exit_anchor.anchor_id = &"anchor.exit"; exit_anchor.position = Vector2(8.0, 8.0); beta.anchors = [exit_anchor]
	registry.register_map(alpha); registry.register_map(beta)
	var actor := GMCharacterRuntime2D.new(); actor.stable_instance_id = "actor.export"; actor.map_id = "map.export.alpha"; add_child(actor)
	var executor := GMMovementAbilityExecutor.new(registry); executor.register_actor(actor.stable_instance_id, actor, actor.map_id)
	var direct_data := {"schema": GMMovementRequest.SCHEMA, "kind": "anchor", "source": "script", "owner_id": "owner.export", "actor_id": actor.stable_instance_id, "map_id": actor.map_id, "anchor_id": "anchor.goal", "speed": 160.0, "acceleration": 1200.0, "stop_distance": 0.5, "follow_distance": 8.0}
	var parsed := GMMovementRequest.from_dict(direct_data)
	var started := executor.start_request(parsed.request, actor) if parsed.ok else parsed
	var result: Dictionary = started
	if started.ok:
		for index in 60:
			result = executor.tick_command(started.command_id, 0.025)
			if result.get("completed", false): break
	var travel_data := direct_data.duplicate(true); travel_data.kind = "travel"; travel_data.erase("anchor_id"); travel_data.entry_anchor_id = "anchor.start"; travel_data.exit_anchor_id = "anchor.exit"; travel_data.return_anchor_id = "anchor.return"; travel_data.target_map_id = "map.export.beta"
	var travel_parsed := GMMovementRequest.from_dict(travel_data)
	var travel := executor.start_request(travel_parsed.request, actor) if travel_parsed.ok else travel_parsed
	var ok := bool(result.get("ok", false)) and bool(result.get("completed", false)) and actor.position.distance_to(Vector2(32.0, 0.0)) <= 0.6 and bool(travel.get("ok", false)) and not bool(travel.get("scene_session_created", true)) and str(travel.get("deferred_to", "")) == "P23"
	print(JSON.stringify({"event": "P15_EXPORT_STARTUP_SENTINEL", "ok": ok, "ability_id": GMMovementAbilityDefinition.new().ability_id, "movement_schema": GMMovementRequest.SCHEMA, "position": {"x": actor.position.x, "y": actor.position.y}, "scene_session_created": travel.get("scene_session_created", null), "deferred_to": travel.get("deferred_to", "")}))
	get_tree().quit(0 if ok else 1)
