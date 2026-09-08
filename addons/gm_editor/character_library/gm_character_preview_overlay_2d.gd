@tool
class_name GMCharacterPreviewOverlay2D
extends Node2D

var presenter: GMCharacterPresenter2D
var show_collision := true
var show_anchors := true
var show_events := true

func configure(value: GMCharacterPresenter2D) -> void:
	presenter = value
	queue_redraw()

func _draw() -> void:
	if presenter == null or presenter.visual_set == null: return
	if show_collision:
		draw_rect(Rect2(-22, -14, 44, 42), Color(0.2, 0.8, 1.0, 0.18), true)
		draw_rect(Rect2(-22, -14, 44, 42), Color("5bd8ff"), false, 2.0)
	if show_anchors:
		for anchor in presenter.visual_set.anchors:
			if anchor == null: continue
			var sampled := presenter.anchor_position(anchor.anchor_name)
			if sampled.ok:
				var p: Vector2 = sampled.position
				draw_circle(p, 5.0, Color("ffd15b"))
				draw_line(p - Vector2(8, 0), p + Vector2(8, 0), Color.WHITE, 1.0)
				draw_line(p - Vector2(0, 8), p + Vector2(0, 8), Color.WHITE, 1.0)
				draw_string(ThemeDB.fallback_font, p + Vector2(8, -8), str(anchor.anchor_name), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	if show_events:
		var action := presenter.visual_set.action_for(presenter.semantic)
		if action != null:
			for event in action.events:
				if event != null: draw_string(ThemeDB.fallback_font, Vector2(-130, 100 + event.frame_index * 16), "F%d  %s:%s" % [event.frame_index, event.event_kind, event.event_name], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ffbd7a"))
