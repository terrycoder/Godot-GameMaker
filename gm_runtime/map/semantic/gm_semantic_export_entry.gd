extends Node

func _ready() -> void:
	var semantic: GMMapSemanticResource = load("res://gm_runtime/map/semantic/gm_semantic_export_sample.tres")
	var terrain: GMMapResource = semantic.terrain_map
	var portal: GMSemanticPortal = semantic.portals[0]
	var camera_config: GMCameraZoneConfig = semantic.camera_zones[0]
	var registry := GMMapSemanticRegistry.new()
	registry.register_map(semantic)
	var runtime := GMSemanticRuntime.new(registry)
	var enter := runtime.update_actor_regions(terrain.map_id, "player", Vector2(32, 32), self)
	var portal_result := portal.request_transfer(registry)
	var camera := Camera2D.new()
	add_child(camera)
	var camera_result := camera_config.apply_to(camera)
	camera.enabled = false
	var validator := GMMapSemanticValidator.new()
	var validation := validator.begin(registry).step(4)
	var test_launch := runtime.make_test_launch(terrain.map_id, &"gm.map_anchor.export_spawn")
	var save_payload := GMSemanticRuntime.sanitize_save_payload({"slot":"formal", "semantic_test_launch":test_launch})
	var facts := {"event":"TASK09_STARTUP_SENTINEL", "ok":semantic.validate_definition(registry).ok and portal_result.ok and camera_result.ok and validation.complete and enter.events.size() == 1 and test_launch.ephemeral and not save_payload.has("semantic_test_launch"), "map_id":str(terrain.map_id), "regions":semantic.regions.size(), "routes":semantic.routes.size(), "anchors":semantic.anchors.size(), "portals":semantic.portals.size(), "camera_zones":semantic.camera_zones.size(), "gameplay_event_tag":enter.events[0].event_tag if not enter.events.is_empty() else "", "portal_identity":portal_result.persist_identity, "test_persisted":save_payload.has("semantic_test_launch"), "validation_count":validation.results.size(), "editor_dependency":false}
	print(JSON.stringify(facts))
	_build_runtime_view(facts, semantic)
	var capture_output := OS.get_environment("GM_TASK09_EXPORT_CAPTURE_OUTPUT")
	if not capture_output.is_empty():
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		var image := get_viewport().get_texture().get_image()
		var absolute := ProjectSettings.globalize_path(capture_output)
		DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		var capture_error := image.save_png(absolute)
		print(JSON.stringify({"event":"TASK09_EXPORT_CAPTURE_SENTINEL", "ok":capture_error == OK, "path":absolute, "width":image.get_width(), "height":image.get_height(), "startup":facts}))
	get_tree().quit(0 if facts.ok else 9)

func _build_runtime_view(facts: Dictionary, semantic: GMMapSemanticResource) -> void:
	var background := ColorRect.new()
	background.color = Color("111a27")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var panel := PanelContainer.new()
	panel.position = Vector2(100, 55)
	panel.size = Vector2(900, 590)
	background.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)
	var title := Label.new()
	title.text = "GM 语义地图正式运行 · Godot %s" % Engine.get_version_info().string
	title.add_theme_font_size_override("font_size", 27)
	content.add_child(title)
	var summary := Label.new()
	summary.text = "区域 %s  |  路线 %s  |  锚点 %s  |  Portal %s  |  Camera2D区 %s" % [facts.regions, facts.routes, facts.anchors, facts.portals, facts.camera_zones]
	summary.add_theme_font_size_override("font_size", 19)
	content.add_child(summary)
	var canvas := Control.new()
	canvas.custom_minimum_size = Vector2(820, 330)
	content.add_child(canvas)
	var grid_step := Vector2(82, 68)
	var grid_origin := Vector2(28, 24)
	for y in semantic.terrain_map.map_size.y:
		for x in semantic.terrain_map.map_size.x:
			var cell := ColorRect.new()
			cell.position = grid_origin + Vector2(x, y) * grid_step
			cell.size = Vector2(78, 64)
			cell.color = Color("244b54")
			canvas.add_child(cell)
	var route := Line2D.new()
	route.width = 6
	route.default_color = Color("ffd166")
	var route_points := PackedVector2Array()
	for row in semantic.routes[0].points:
		route_points.append(grid_origin + Vector2(row.position) / Vector2(semantic.terrain_map.tile_size) * grid_step + grid_step * 0.5)
	if semantic.routes[0].closed: route_points.append(route_points[0])
	route.points = route_points
	canvas.add_child(route)
	for point in route_points.slice(0, semantic.routes[0].points.size()):
		var marker := Polygon2D.new()
		marker.polygon = PackedVector2Array([Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10)])
		marker.color = Color("59a8ff")
		marker.position = point
		canvas.add_child(marker)
	var detail := Label.new()
	detail.text = "GameplayEvent: %s\nPortal身份: %s + %s\n从当前位置测试写入正式存档: %s\nTASK09_STARTUP_SENTINEL ok=%s" % [facts.gameplay_event_tag, facts.portal_identity.map_id, facts.portal_identity.anchor_id, facts.test_persisted, facts.ok]
	detail.add_theme_font_size_override("font_size", 17)
	content.add_child(detail)
