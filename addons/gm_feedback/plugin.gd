@tool
extends EditorPlugin

var dock: Control
var dock_button: Button

func _enter_tree() -> void:
	dock = preload("res://addons/gm_feedback/gm_feedback_dock.gd").new()
	dock.configure(get_editor_interface(), get_undo_redo())
	dock_button = add_control_to_bottom_panel(dock, "P18语义反馈工作台")
	dock.set_meta("bottom_panel_button", dock_button)
	if OS.get_environment("GM_P18_EDITOR_CAPTURE_OUTPUT").is_empty():
		dock.hide()
	else:
		make_bottom_panel_item_visible(dock)

func _exit_tree() -> void:
	if is_instance_valid(dock):
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
	dock = null

