@tool
extends EditorPlugin

var dock: Control
var content_dock: Control
var gas_dock: Control
var event_trigger_dock: Control
var map_workbench_dock: Control
var map_3d_dock: Control
var map_3d_dock_button: Button
var scene_3d_dock: Control
var scene_3d_dock_button: Button
var map_semantic_dock: Control
var object_assembler_dock: Control
var character_library_dock: Control
var character_3d_dock: Control
var character_3d_dock_button: Button
var character_assembly_3d_dock: Control
var character_assembly_3d_dock_button: Button
var combat_3d_dock: Control
var combat_3d_dock_button: Button
var render_style_3d_dock: Control
var render_style_3d_dock_button: Button
var neutral_vertical_sample_dock: Control
var neutral_vertical_sample_dock_button: Button
var npc_assembly_dock: Control
var movement_dock: Control
var movement_dock_button: Button
var task_dock: Control
var task_dock_button: Button
var export_plugin: EditorExportPlugin
var inspector_plugin: EditorInspectorPlugin
var map_workbench_controller: GMMapWorkbenchController
var surface_gizmo_plugin
var planar_3d_tools: Control

func _enter_tree() -> void:
	_dispose_map_workbench_controller()
	map_workbench_controller = preload("res://addons/gm_editor/map/gm_map_workbench_controller.gd").new()
	var map_attach := map_workbench_controller.attach_editor_plugin(self)
	set_meta("gm_map_workbench_controller", map_workbench_controller)
	set_meta("gm_map_workbench_undo_gateway", map_attach.get("undo_gateway", ""))
	_dispose_map_workbench_dock()
	map_workbench_dock = preload("res://addons/gm_editor/map/gm_map_workbench_dock.gd").new()
	map_workbench_dock.configure(self, map_workbench_controller)
	_add_bottom_panel(map_workbench_dock, "GM地图工作台")
	if _is_command_line_export():
		_dispose_map_workbench_dock()
		_dispose_map_workbench_controller()
		export_plugin = preload("res://addons/gm_editor/gm_export_plugin.gd").new()
		add_export_plugin(export_plugin)
		print(JSON.stringify({"gm_plugin":"export_only_enter", "godot":Engine.get_version_info().string}))
		return
	_dispose_map_3d_dock()
	map_3d_dock = preload("res://addons/gm_editor/map3d/gm_map_3d_editor_dock.gd").new()
	map_3d_dock.configure(get_editor_interface(), get_undo_redo())
	map_3d_dock_button = add_control_to_bottom_panel(map_3d_dock, "GM平面3D地图")
	map_3d_dock.set_meta("bottom_panel_button", map_3d_dock_button)
	map_3d_dock.set_meta("surface_gizmo_plugin_registered", true)
	map_3d_dock.hide()
	_dispose_surface_gizmo_plugin()
	surface_gizmo_plugin = preload("res://addons/gm_editor/map3d/gm_surface_gizmo_plugin.gd").new()
	add_node_3d_gizmo_plugin(surface_gizmo_plugin)
	map_workbench_dock.hide()

	_dispose_scene_3d_dock()
	scene_3d_dock = preload("res://addons/gm_editor/map3d/gm_scene_3d_placement_dock.gd").new()
	scene_3d_dock.configure(get_editor_interface(), get_undo_redo(), map_3d_dock)
	scene_3d_dock_button = add_control_to_bottom_panel(scene_3d_dock, "GM 三维场景配方策划")
	scene_3d_dock.set_meta("bottom_panel_button", scene_3d_dock_button)
	scene_3d_dock.hide()
	_dispose_map_semantic_dock()
	map_semantic_dock = preload("res://addons/gm_editor/map_semantic/gm_map_semantic_dock.gd").new()
	map_semantic_dock.configure(self)
	_add_bottom_panel(map_semantic_dock, "GM语义地图")
	map_semantic_dock.hide()
	_dispose_object_assembler_dock()
	object_assembler_dock = preload("res://addons/gm_editor/object_assembler/gm_object_assembler_dock.gd").new()
	object_assembler_dock.configure(self)
	_add_bottom_panel(object_assembler_dock, "GM对象装配")
	object_assembler_dock.hide()
	_dispose_character_library_dock()
	character_library_dock = preload("res://addons/gm_editor/character_library/gm_character_library_dock.gd").new()
	character_library_dock.configure(get_editor_interface(), get_undo_redo())
	_add_bottom_panel(character_library_dock, "GM角色资产库")
	character_library_dock.hide()
	_dispose_character_3d_dock()
	character_3d_dock = preload("res://addons/gm_editor/character_library/gm_character_visual_3d_dock.gd").new()
	character_3d_dock.configure(get_editor_interface(), get_undo_redo())
	character_3d_dock_button = add_control_to_bottom_panel(character_3d_dock, "GM角色3D视觉")
	character_3d_dock.set_meta("bottom_panel_button", character_3d_dock_button)
	character_3d_dock.hide()
	_dispose_character_assembly_3d_dock()
	character_assembly_3d_dock = preload("res://addons/gm_editor/character_library/gm_character_assembly_3d_dock.gd").new()
	character_assembly_3d_dock.configure(get_editor_interface(), get_undo_redo())
	character_assembly_3d_dock_button = add_control_to_bottom_panel(character_assembly_3d_dock, "GM角色3D装配")
	character_assembly_3d_dock.set_meta("bottom_panel_button", character_assembly_3d_dock_button)
	character_assembly_3d_dock.hide()
	_dispose_combat_3d_dock()
	combat_3d_dock = preload("res://addons/gm_editor/combat3d/gm_planar_combat_3d_dock.gd").new()
	combat_3d_dock.configure(get_editor_interface(), get_undo_redo())
	combat_3d_dock_button = add_control_to_bottom_panel(combat_3d_dock, "GM平面战斗与Cue3D")
	combat_3d_dock.set_meta("bottom_panel_button", combat_3d_dock_button)
	combat_3d_dock.hide()
	_dispose_render_style_3d_dock()
	render_style_3d_dock = preload("res://addons/gm_editor/render_style/gm_render_style_3d_dock.gd").new()
	render_style_3d_dock.configure(get_editor_interface(), get_undo_redo())
	render_style_3d_dock_button = add_control_to_bottom_panel(render_style_3d_dock, "GM渲染风格与材质")
	render_style_3d_dock.set_meta("bottom_panel_button", render_style_3d_dock_button)
	render_style_3d_dock.hide()
	_dispose_neutral_vertical_sample_dock()
	neutral_vertical_sample_dock = preload("res://addons/gm_editor/map3d/gm_neutral_vertical_sample_dock.gd").new()
	var neutral_profile_path := OS.get_environment("GM_EXT_3D_10_EDITOR_PROFILE_PATH").strip_edges()
	neutral_vertical_sample_dock.configure(get_editor_interface(), get_undo_redo(), neutral_profile_path)
	neutral_vertical_sample_dock_button = add_control_to_bottom_panel(neutral_vertical_sample_dock, "Planar 3D中性纵向样板")
	neutral_vertical_sample_dock.set_meta("bottom_panel_button", neutral_vertical_sample_dock_button)
	neutral_vertical_sample_dock.hide()
	_dispose_npc_assembly_dock()
	npc_assembly_dock = preload("res://addons/gm_editor/npc/gm_npc_assembly_dock.gd").new()
	npc_assembly_dock.configure(self)
	_add_bottom_panel(npc_assembly_dock, "GM角色NPC装配")
	npc_assembly_dock.hide()
	_dispose_movement_dock()
	movement_dock = preload("res://addons/gm_editor/movement/gm_movement_dock.gd").new()
	movement_dock.configure(self)
	movement_dock_button = add_control_to_bottom_panel(movement_dock, "GM移动能力")
	movement_dock.set_meta("bottom_panel_button", movement_dock_button)
	movement_dock.hide()
	_dispose_task_dock()
	task_dock = preload("res://addons/gm_editor/task/gm_task_dock.gd").new()
	task_dock.configure(self)
	task_dock_button = add_control_to_bottom_panel(task_dock, "GM任务工作台")
	task_dock.set_meta("bottom_panel_button", task_dock_button)
	task_dock.hide()
	_dispose_dock()
	dock = preload("res://addons/gm_editor/workbench/workbench_dock.gd").new()
	dock.configure(get_editor_interface(), get_undo_redo())
	dock.set_meta("editor_interface", get_editor_interface())
	dock.set_meta("editor_undo_redo", get_undo_redo())
	_add_bottom_panel(dock, "GM策划工作台")
	make_bottom_panel_item_visible(dock)
	dock.show()
	_dispose_content_dock()
	content_dock = preload("res://addons/gm_editor/content/content_browser_dock.gd").new()
	content_dock.configure(get_editor_interface(), get_undo_redo())
	content_dock.set_meta("editor_interface", get_editor_interface())
	content_dock.set_meta("editor_undo_redo", get_undo_redo())
	_add_bottom_panel(content_dock, "GM内容资源库")
	# 内容库是实际 EditorPlugin 入口，但不抢占任务02工作台的默认焦点。
	content_dock.hide()
	_dispose_gas_dock()
	gas_dock = preload("res://addons/gm_editor/gas/gm_task04_ability_browser.gd").new()
	gas_dock.configure(OS.get_environment("GM_TASK04_EDITOR_CAPTURE_STATE"))
	_add_bottom_panel(gas_dock, "GM能力浏览器")
	gas_dock.hide()
	_dispose_event_trigger_dock()
	event_trigger_dock = preload("res://addons/gm_editor/triggers/gm_event_trigger_dock.gd").new()
	event_trigger_dock.configure(get_editor_interface(), get_undo_redo())
	event_trigger_dock.set_meta("editor_interface", get_editor_interface())
	event_trigger_dock.set_meta("editor_undo_redo", get_undo_redo())
	_add_bottom_panel(event_trigger_dock, "GM事件触发器")
	event_trigger_dock.hide()
	_dispose_inspector_plugin()
	inspector_plugin = preload("res://addons/gm_editor/content/gm_content_inspector_plugin.gd").new()
	add_inspector_plugin(inspector_plugin)
	if is_instance_valid(export_plugin): remove_export_plugin(export_plugin)
	export_plugin = preload("res://addons/gm_editor/gm_export_plugin.gd").new()
	add_export_plugin(export_plugin)
	print(JSON.stringify({"gm_plugin":"workbench_enter","panel":"GM策划工作台","panel_count":1,"event_trigger_panel":is_instance_valid(event_trigger_dock),"inspector_registered":is_instance_valid(inspector_plugin),"map_workbench_controller":is_instance_valid(map_workbench_controller),"map_workbench_undo_gateway":map_attach.get("undo_gateway", ""),"godot":Engine.get_version_info().string}))
	_ensure_workbench_visible()
	planar_3d_tools = preload("res://addons/gm_editor/map3d/gm_planar_3d_tools_dock.gd").new()
	planar_3d_tools.configure(get_editor_interface(), get_undo_redo(), dock.error_center)
	_add_bottom_panel(planar_3d_tools, "GM三维预算与验证")
	planar_3d_tools.hide()

func get_map_workbench_controller() -> GMMapWorkbenchController:
	return map_workbench_controller

func get_map_workbench_dock() -> Control:
	return map_workbench_dock

func open_map_in_workbench(target_map: GMMapResource) -> Dictionary:
	if not is_instance_valid(map_workbench_controller):
		return {"ok": false, "code": "map.workbench_controller_missing", "error_zh": "地图工作台控制器尚未进入编辑器生命周期"}
	return map_workbench_controller.configure(target_map, self)

func show_map_workbench() -> void:
	if is_instance_valid(map_workbench_dock):
		make_bottom_panel_item_visible(map_workbench_dock)
		map_workbench_dock.show()

func show_map_semantic_workbench() -> void:
	if is_instance_valid(map_semantic_dock):
		make_bottom_panel_item_visible(map_semantic_dock)
		map_semantic_dock.show()

func show_object_assembler_workbench() -> void:
	if is_instance_valid(object_assembler_dock):
		make_bottom_panel_item_visible(object_assembler_dock)
		object_assembler_dock.show()

func show_character_library() -> void:
	if is_instance_valid(character_library_dock):
		make_bottom_panel_item_visible(character_library_dock)
		character_library_dock.show()

func _ensure_workbench_visible() -> void:
	if not OS.get_environment("GM_TASK10_EDITOR_CAPTURE_OUTPUT").is_empty(): return
	if not OS.get_environment("GM_TASK11_EDITOR_CAPTURE_DIR").is_empty(): return
	if not OS.get_environment("GM_TASK12_EDITOR_CAPTURE_OUTPUT").is_empty(): return
	if not OS.get_environment("GM_P15_EDITOR_CAPTURE_OUTPUT").is_empty(): return
	if not OS.get_environment("GM_P16_EDITOR_CAPTURE_OUTPUT").is_empty(): return
	if not OS.get_environment("GM_EXT_3D_02_EDITOR_CAPTURE_JSON").is_empty(): return
	if not OS.get_environment("GM_EXT_3D_04_EDITOR_CAPTURE_JSON").is_empty(): return
	if not OS.get_environment("GM_EXT_3D_04_GENERALITY_CAPTURE_JSON").is_empty(): return
	if not OS.get_environment("GM_EXT_3D_05_EDITOR_CAPTURE_JSON").is_empty(): return
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(dock):
		make_bottom_panel_item_visible(dock)
		dock.show()

func _add_bottom_panel(control: Control, title: String) -> void:
	add_control_to_bottom_panel(control, title)

func _sha256_file(path: String) -> String:
	if not FileAccess.file_exists(path): return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		var remaining := file.get_length() - file.get_position()
		context.update(file.get_buffer(mini(remaining, 1048576)))
	return context.finish().hex_encode()

func _is_command_line_export() -> bool:
	var args := OS.get_cmdline_args()
	return args.has("--export-debug") or args.has("--export-release") or args.has("--export-pack") or args.has("--export-patch")

func _exit_tree() -> void:
	if is_instance_valid(planar_3d_tools):
		remove_control_from_bottom_panel(planar_3d_tools)
		planar_3d_tools.queue_free()
	planar_3d_tools = null
	_dispose_dock()
	_dispose_content_dock()
	_dispose_gas_dock()
	_dispose_event_trigger_dock()
	_dispose_map_workbench_dock()
	_dispose_map_3d_dock()
	_dispose_scene_3d_dock()
	_dispose_surface_gizmo_plugin()
	_dispose_map_semantic_dock()
	_dispose_object_assembler_dock()
	_dispose_character_library_dock()
	_dispose_character_3d_dock()
	_dispose_character_assembly_3d_dock()
	_dispose_combat_3d_dock()
	_dispose_render_style_3d_dock()
	_dispose_neutral_vertical_sample_dock()
	_dispose_npc_assembly_dock()
	_dispose_movement_dock()
	_dispose_task_dock()
	_dispose_inspector_plugin()
	_dispose_map_workbench_controller()
	if is_instance_valid(export_plugin):
		remove_export_plugin(export_plugin)
		export_plugin = null

func _dispose_dock() -> void:
	if is_instance_valid(dock):
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
	dock = null

func _dispose_content_dock() -> void:
	if is_instance_valid(content_dock):
		remove_control_from_bottom_panel(content_dock)
		content_dock.queue_free()
	content_dock = null

func _dispose_gas_dock() -> void:
	if is_instance_valid(gas_dock):
		remove_control_from_bottom_panel(gas_dock)
		gas_dock.queue_free()
	gas_dock = null

func _dispose_event_trigger_dock() -> void:
	if is_instance_valid(event_trigger_dock):
		remove_control_from_bottom_panel(event_trigger_dock)
		event_trigger_dock.queue_free()
	event_trigger_dock = null

func _dispose_map_workbench_dock() -> void:
	if is_instance_valid(map_workbench_dock):
		remove_control_from_bottom_panel(map_workbench_dock)
		map_workbench_dock.queue_free()
	map_workbench_dock = null

func _dispose_map_3d_dock() -> void:
	if is_instance_valid(map_3d_dock):
		remove_control_from_bottom_panel(map_3d_dock)
		map_3d_dock.queue_free()
	map_3d_dock = null
	map_3d_dock_button = null

func _dispose_scene_3d_dock() -> void:
	if is_instance_valid(scene_3d_dock):
		remove_control_from_bottom_panel(scene_3d_dock)
		scene_3d_dock.queue_free()
	scene_3d_dock = null
	scene_3d_dock_button = null

func _dispose_surface_gizmo_plugin() -> void:
	if is_instance_valid(surface_gizmo_plugin):
		remove_node_3d_gizmo_plugin(surface_gizmo_plugin)
	surface_gizmo_plugin = null

func _dispose_map_semantic_dock() -> void:
	if is_instance_valid(map_semantic_dock):
		remove_control_from_bottom_panel(map_semantic_dock)
		map_semantic_dock.queue_free()
	map_semantic_dock = null

func _dispose_object_assembler_dock() -> void:
	if is_instance_valid(object_assembler_dock):
		remove_control_from_bottom_panel(object_assembler_dock)
		object_assembler_dock.queue_free()
	object_assembler_dock = null

func _dispose_character_library_dock() -> void:
	if is_instance_valid(character_library_dock):
		remove_control_from_bottom_panel(character_library_dock)
		character_library_dock.free()
	character_library_dock = null

func _dispose_character_3d_dock() -> void:
	if is_instance_valid(character_3d_dock):
		remove_control_from_bottom_panel(character_3d_dock)
		character_3d_dock.queue_free()
	character_3d_dock = null
	character_3d_dock_button = null

func _dispose_character_assembly_3d_dock() -> void:
	if is_instance_valid(character_assembly_3d_dock):
		remove_control_from_bottom_panel(character_assembly_3d_dock)
		character_assembly_3d_dock.queue_free()
	character_assembly_3d_dock = null
	character_assembly_3d_dock_button = null

func _dispose_combat_3d_dock() -> void:
	if is_instance_valid(combat_3d_dock):
		remove_control_from_bottom_panel(combat_3d_dock)
		combat_3d_dock.queue_free()
	combat_3d_dock = null
	combat_3d_dock_button = null

func _dispose_render_style_3d_dock() -> void:
	if is_instance_valid(render_style_3d_dock):
		remove_control_from_bottom_panel(render_style_3d_dock)
		render_style_3d_dock.queue_free()
	render_style_3d_dock = null
	render_style_3d_dock_button = null

func _dispose_neutral_vertical_sample_dock() -> void:
	if is_instance_valid(neutral_vertical_sample_dock):
		remove_control_from_bottom_panel(neutral_vertical_sample_dock)
		neutral_vertical_sample_dock.queue_free()
	neutral_vertical_sample_dock = null
	neutral_vertical_sample_dock_button = null

func _dispose_npc_assembly_dock() -> void:
	if is_instance_valid(npc_assembly_dock):
		remove_control_from_bottom_panel(npc_assembly_dock)
		npc_assembly_dock.free()
	npc_assembly_dock = null

func _dispose_movement_dock() -> void:
	if is_instance_valid(movement_dock):
		remove_control_from_bottom_panel(movement_dock)
		movement_dock.queue_free()
	movement_dock = null
	movement_dock_button = null

func _dispose_task_dock() -> void:
	if is_instance_valid(task_dock):
		remove_control_from_bottom_panel(task_dock)
		task_dock.queue_free()
	task_dock = null
	task_dock_button = null

func _dispose_inspector_plugin() -> void:
	if is_instance_valid(inspector_plugin):
		remove_inspector_plugin(inspector_plugin)
	inspector_plugin = null

func _dispose_map_workbench_controller() -> void:
	if is_instance_valid(map_workbench_controller):
		map_workbench_controller.editor_undo_redo = null
		map_workbench_controller.session = null
	map_workbench_controller = null
	remove_meta("gm_map_workbench_controller")
	remove_meta("gm_map_workbench_undo_gateway")
