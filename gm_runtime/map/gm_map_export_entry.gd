extends Node

func _ready() -> void:
	var square := GMMapResource.new()
	square.map_id = &"gm.map_anchor.runtime_export_smoke"
	square.map_size = Vector2i(4, 4)
	for row in [[&"ground", "地表", 0], [&"road", "道路", 1], [&"water", "水域", 2], [&"logic", "逻辑层", 4]]:
		var layer := GMMapLayerDefinition.new()
		layer.layer_id = row[0]
		layer.display_name_zh = row[1]
		layer.kind = row[2]
		layer.draw_order = square.layers.size() * 10
		square.add_layer(layer)
	square.set_visual_cell(&"ground", Vector2i.ZERO, 1)
	square.set_logic_cell(Vector2i.ZERO, {"ground_type": "grass", "walkable": true, "cost": 1.0, "water": false, "height_level": 0})
	square.set_logic_cell(Vector2i(1, 0), {"ground_type": "wall", "walkable": false, "cost": 99.0, "water": false, "height_level": 0})
	var instantiated := GMMapLogicGenerator.instantiate_nodes(square)
	if bool(instantiated.get("ok", false)) and instantiated.get("root") != null:
		add_child(instantiated.root)
	var facts := {
		"event": "TASK08_STARTUP_SENTINEL",
		"ok": square != null and square.validate().ok and bool(instantiated.get("ok", false)) and int(instantiated.get("collision_shape_count", 0)) > 0 and int(instantiated.get("navigation_region_count", 0)) > 0 and str(instantiated.get("source", "")) == "logic_cells" and not bool(instantiated.get("visual_cells_read", true)),
		"map_id": str(square.map_id),
		"grid_type": square.grid_type,
		"layers": square.layers.size(),
		"logic_cells": square.logic_cells.size(),
		"collision_shape_count": instantiated.get("collision_shape_count", 0),
		"navigation_region_count": instantiated.get("navigation_region_count", 0),
		"source": instantiated.get("source", ""),
		"visual_cells_read": instantiated.get("visual_cells_read", true),
	}
	print(JSON.stringify(facts))
	_build_runtime_view(facts)
	var capture_output := OS.get_environment("GM_TASK08_EXPORT_CAPTURE_OUTPUT")
	if not capture_output.is_empty():
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		var image := get_viewport().get_texture().get_image()
		var absolute := ProjectSettings.globalize_path(capture_output)
		DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		var capture_error := image.save_png(absolute)
		print(JSON.stringify({"event":"TASK08_EXPORT_CAPTURE_SENTINEL","ok":capture_error == OK,"path":absolute,"width":image.get_width(),"height":image.get_height(),"startup":facts}))
	get_tree().quit(0 if facts.ok else 8)

func _build_runtime_view(facts: Dictionary) -> void:
	var background := ColorRect.new()
	background.color = Color("18222f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var panel := PanelContainer.new()
	panel.position = Vector2(110, 70)
	panel.size = Vector2(880, 560)
	background.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	panel.add_child(content)
	var title := Label.new()
	title.text = "GM 地图正式导出运行 · Godot %s" % Engine.get_version_info().get("string", "")
	title.add_theme_font_size_override("font_size", 26)
	content.add_child(title)
	var summary := Label.new()
	summary.text = "方格样板  |  三表现层 + 一逻辑层  |  来源：logic_cells"
	summary.add_theme_font_size_override("font_size", 20)
	content.add_child(summary)
	var grid := GridContainer.new()
	grid.columns = 4
	for y in 4:
		for x in 4:
			var cell := ColorRect.new()
			cell.custom_minimum_size = Vector2(72, 72)
			cell.color = Color("64b5f6") if Vector2i(x, y) == Vector2i.ZERO else (Color("ef5350") if Vector2i(x, y) == Vector2i(1, 0) else Color("455a64"))
			cell.tooltip_text = "可通行" if Vector2i(x, y) == Vector2i.ZERO else ("不可通行" if Vector2i(x, y) == Vector2i(1, 0) else "未配置")
			grid.add_child(cell)
	content.add_child(grid)
	var detail := Label.new()
	detail.text = "NavigationRegion2D=%s   CollisionShape2D=%s   visual_cells_read=%s\n启动哨兵：TASK08_STARTUP_SENTINEL ok=%s" % [facts.navigation_region_count, facts.collision_shape_count, facts.visual_cells_read, facts.ok]
	detail.add_theme_font_size_override("font_size", 18)
	content.add_child(detail)
