extends Node2D

func _draw() -> void:
	draw_rect(Rect2(-64, -40, 128, 80), Color("6d3b1e"), true)
	draw_rect(Rect2(-72, -48, 144, 18), Color("c58b3e"), true)
	draw_circle(Vector2(0, 4), 10, Color("f2d15b"))
	draw_line(Vector2(0, 14), Vector2(0, 28), Color("20150e"), 5.0)
