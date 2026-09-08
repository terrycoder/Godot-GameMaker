class_name GMPlayerShellWorld2D
extends Node2D

## 2D visual projection for P25.  It owns no gameplay state: the shell pushes
## only read-only projection values before redraw.

var map_size := Vector2(1088.0, 640.0)
var tile_size := Vector2(32.0, 32.0)
var target_position := Vector2(800.0, 320.0)
var player_position := Vector2(160.0, 320.0)
var target_available := true
var active_scene_label := "中性场景"
var last_query_label := "等待查询"

func set_projection(values: Dictionary) -> void:
	map_size = values.get("map_size", map_size)
	tile_size = values.get("tile_size", tile_size)
	target_position = values.get("target_position", target_position)
	player_position = values.get("player_position", player_position)
	target_available = bool(values.get("target_available", target_available))
	active_scene_label = str(values.get("scene_label", active_scene_label))
	last_query_label = str(values.get("query_label", last_query_label))
	queue_redraw()

func _draw() -> void:
	var background := Rect2(Vector2.ZERO, map_size)
	draw_rect(background, Color("#111a2a"), true)
	draw_rect(background, Color("#5b7394"), false, 2.0)
	var columns := int(ceil(map_size.x / tile_size.x))
	var rows := int(ceil(map_size.y / tile_size.y))
	for x in columns + 1:
		var x_value := minf(float(x) * tile_size.x, map_size.x)
		draw_line(Vector2(x_value, 0.0), Vector2(x_value, map_size.y), Color(0.15, 0.22, 0.34, 0.42), 1.0)
	for y in rows + 1:
		var y_value := minf(float(y) * tile_size.y, map_size.y)
		draw_line(Vector2(0.0, y_value), Vector2(map_size.x, y_value), Color(0.15, 0.22, 0.34, 0.42), 1.0)

	var zone := Rect2(Vector2(80.0, 210.0), Vector2(960.0, 220.0))
	draw_style_box(_box(Color(0.15, 0.35, 0.53, 0.16), Color(0.30, 0.61, 0.86, 0.32), 12.0), zone)
	draw_string(ThemeDB.fallback_font, Vector2(88.0, 236.0), active_scene_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#a7d4ff"))

	if target_available:
		draw_circle(target_position, 30.0, Color(0.96, 0.69, 0.24, 0.22))
		draw_arc(target_position, 24.0, 0.0, TAU, 32, Color("#f6c35b"), 3.0)
		draw_line(target_position - Vector2(12.0, 0.0), target_position + Vector2(12.0, 0.0), Color("#f6c35b"), 2.0)
		draw_line(target_position - Vector2(0.0, 12.0), target_position + Vector2(0.0, 12.0), Color("#f6c35b"), 2.0)
		draw_string(ThemeDB.fallback_font, target_position + Vector2(-52.0, 54.0), "中性信标", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#ffe3a2"))
	else:
		draw_string(ThemeDB.fallback_font, target_position + Vector2(-65.0, 8.0), "目标不可用", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#ff9e9e"))

	draw_line(player_position, target_position, Color(0.37, 0.72, 0.96, 0.28), 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(26.0, map_size.y - 24.0), "空间查询：%s" % last_query_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#9fb1c7"))

func _box(fill: Color, border: Color, radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(radius))
	return style
