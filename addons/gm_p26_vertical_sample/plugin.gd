@tool
extends EditorPlugin

var dock: Control

func _enter_tree() -> void:
	dock = preload("res://addons/gm_p26_vertical_sample/gm_p26_vertical_sample_dock.gd").new()
	dock.configure(get_editor_interface(), get_undo_redo())
	add_control_to_bottom_panel(dock, "P26中性跨模块样板")
	dock.hide()
	call_deferred("_run_probe_if_requested")

func _exit_tree() -> void:
	if is_instance_valid(dock):
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
	dock = null

func _run_probe_if_requested() -> void:
	var output_path := OS.get_environment("GM_P26_EDITOR_CAPTURE_JSON")
	if output_path.is_empty(): return
	await get_tree().create_timer(2.0).timeout
	for _frame in 6: await get_tree().process_frame
	var facts: Dictionary
	if not is_instance_valid(dock) or not dock.has_method("run_p26_editor_probe"):
		facts = {"event":"P26_EDITOR_SENTINEL", "ok":false, "code":"p26.editor.dock_missing"}
	else:
		make_bottom_panel_item_visible(dock)
		dock.show()
		facts = dock.run_p26_editor_probe()
	facts["godot"] = Engine.get_version_info().string
	facts["dock_registered"] = is_instance_valid(dock)
	var absolute := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(facts, "  ") + "\n")
	print("P26_EDITOR_RESULT " + JSON.stringify(facts))
	get_tree().quit(0 if bool(facts.get("ok", false)) else 271)
