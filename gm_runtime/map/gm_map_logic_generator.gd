class_name GMMapLogicGenerator
extends RefCounted

static func generate(map: GMMapResource) -> Dictionary:
	var collision_cells: Array[String] = []
	var navigation_cells: Array[String] = []
	var failures: Array[Dictionary] = []
	for key in map.logic_cells:
		var value: Variant = map.logic_cells[key]
		if not value is Dictionary:
			failures.append({"cell": key, "code": "map.logic_cell_invalid", "error_zh": "逻辑单元格式错误：%s" % key})
			continue
		if not value.has("walkable") or not value.has("cost"):
			failures.append({"cell": key, "code": "map.logic_cell_incomplete", "error_zh": "逻辑单元缺少通行或代价：%s" % key})
			continue
		if bool(value.walkable): navigation_cells.append(key)
		else: collision_cells.append(key)
	return {"ok": failures.is_empty(), "collision_cells": collision_cells, "navigation_cells": navigation_cells, "failures": failures, "source": "logic_cells", "visual_cells_read": false}

static func instantiate_nodes(map: GMMapResource) -> Dictionary:
	var report := generate(map)
	if not report.ok: return report
	var root := Node2D.new()
	root.name = "GMGeneratedMapLogic"
	var collision_body := StaticBody2D.new()
	collision_body.name = "CollisionFromLogic"
	root.add_child(collision_body)
	var navigation_root := Node2D.new()
	navigation_root.name = "NavigationFromLogic"
	root.add_child(navigation_root)
	for key in report.collision_cells:
		var cell := _parse_cell(key)
		var shape_node := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(map.tile_size)
		shape_node.shape = shape
		shape_node.position = (Vector2(cell) + Vector2(0.5, 0.5)) * Vector2(map.tile_size)
		shape_node.set_meta("gm_cell", key)
		collision_body.add_child(shape_node)
	for key in report.navigation_cells:
		var cell := _parse_cell(key)
		var origin := Vector2(cell) * Vector2(map.tile_size)
		var size := Vector2(map.tile_size)
		var polygon := NavigationPolygon.new()
		polygon.vertices = PackedVector2Array([origin, origin + Vector2(size.x, 0), origin + size, origin + Vector2(0, size.y)])
		polygon.add_polygon(PackedInt32Array([0, 1, 2, 3]))
		var region := NavigationRegion2D.new()
		region.navigation_polygon = polygon
		region.set_meta("gm_cell", key)
		navigation_root.add_child(region)
	return {"ok": true, "root": root, "collision_shape_count": collision_body.get_child_count(), "navigation_region_count": navigation_root.get_child_count(), "source": "logic_cells", "visual_cells_read": false, "failures": []}

static func _parse_cell(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
