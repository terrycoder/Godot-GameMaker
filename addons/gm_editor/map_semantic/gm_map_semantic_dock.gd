@tool
class_name GMMapSemanticDock
extends PanelContainer

class SemanticCanvas:
	extends Control
	const SCALE := Vector2(1.25, 1.25)
	const OFFSET := Vector2(24, 26)
	var semantic_map: GMMapSemanticResource
	var dock: GMMapSemanticDock
	var selected_kind := "all"
	var edit_mode := "select"
	var drag_hit: Dictionary = {}

	func configure(value: GMMapSemanticDock) -> void:
		dock = value
		mouse_filter = Control.MOUSE_FILTER_STOP
		gui_input.connect(_on_gui_input)

	func set_resource(value: GMMapSemanticResource) -> void:
		semantic_map = value
		queue_redraw()

	func world_to_canvas(value: Vector2) -> Vector2: return OFFSET + value * SCALE
	func canvas_to_world(value: Vector2) -> Vector2: return (value - OFFSET) / SCALE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("101722"), true)
		if semantic_map == null:
			draw_string(get_theme_default_font(), Vector2(28, 52), "请新建或打开 GMMapSemanticResource", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("b7c4d6"))
			return
		if semantic_map.terrain_map != null:
			for key in semantic_map.terrain_map.logic_cells:
				var parts := str(key).split(",")
				if parts.size() != 2: continue
				var cell := Vector2i(int(parts[0]), int(parts[1]))
				var row: Dictionary = semantic_map.terrain_map.logic_cells[key]
				var rect := Rect2(world_to_canvas(Vector2(cell * semantic_map.terrain_map.tile_size)), Vector2(semantic_map.terrain_map.tile_size) * SCALE - Vector2(2, 2))
				draw_rect(rect, Color("203449") if bool(row.get("walkable", false)) else Color("773b45"), true)
		if selected_kind in ["all", "region"]:
			for region in semantic_map.regions:
				var points := PackedVector2Array()
				for point in region.polygon: points.append(world_to_canvas(point))
				if points.size() >= 3 and region.validate_definition().ok: draw_colored_polygon(points, Color(0.15, 0.62, 0.48, 0.28))
				if points.size() > 1:
					var outline := points.duplicate(); outline.append(points[0]); draw_polyline(outline, Color("5ce0ad"), 3.0)
				for point in points: draw_circle(point, 5.0, Color("9af5d0"))
		if selected_kind in ["all", "route"]:
			for route in semantic_map.routes:
				var points := PackedVector2Array()
				for row in route.points: points.append(world_to_canvas(Vector2(row.get("position", Vector2.ZERO))))
				var line := points.duplicate()
				if route.closed and not line.is_empty(): line.append(line[0])
				if line.size() > 1: draw_polyline(line, Color("ffd166"), 4.0)
				for point in points: draw_circle(point, 6.0, Color("ffe7a3"))
		if selected_kind in ["all", "anchor"]:
			for anchor in semantic_map.anchors:
				var center := world_to_canvas(anchor.position)
				draw_circle(center, 9.0, Color("59a8ff"))
				draw_line(center, center + Vector2.RIGHT.rotated(deg_to_rad(anchor.facing_degrees)) * 18.0, Color.WHITE, 2.0)
		if selected_kind in ["all", "camera"]:
			for camera in semantic_map.camera_zones:
				draw_rect(Rect2(world_to_canvas(camera.bounds.position), camera.bounds.size * SCALE), Color("c77dff"), false, 3.0)

	func _on_gui_input(event: InputEvent) -> void:
		if dock == null or semantic_map == null: return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			var world := canvas_to_world(event.position)
			if event.pressed:
				if edit_mode == "add": dock.canvas_add_at(world)
				elif edit_mode == "select": dock.canvas_select_at(world)
				elif edit_mode == "move": drag_hit = dock.canvas_find_handle(world)
			elif edit_mode == "move" and not drag_hit.is_empty():
				dock.canvas_move_handle(drag_hit, world)
				drag_hit = {}

const KIND_NAMES := {"region":"区域", "route":"路线", "anchor":"锚点", "portal":"Portal", "camera":"Camera2D区"}
const COLLECTIONS := {"region":"regions", "route":"routes", "anchor":"anchors", "portal":"portals", "camera":"camera_zones"}
const ID_FIELDS := {"region":"region_id", "route":"route_id", "anchor":"anchor_id", "portal":"portal_id", "camera":"camera_id"}

var editor_plugin: EditorPlugin
var undo_redo: EditorUndoRedoManager
var semantic_map: GMMapSemanticResource
var registry := GMMapSemanticRegistry.new()
var current_resource_path := ""
var canvas: SemanticCanvas
var object_list: ItemList
var validation_list: ItemList
var status_title: Label
var status_body: RichTextLabel
var path_edit: LineEdit
var map_id_edit: LineEdit
var kind_picker: OptionButton
var canvas_mode_picker: OptionButton
var file_dialog: FileDialog
var inspector_box: VBoxContainer
var fields: Dictionary = {}
var field_rows: Dictionary = {}
var action_buttons: Dictionary = {}
var object_entries: Array[Dictionary] = []
var selected_kind := "region"
var selected_object_index := -1
var last_trace: Dictionary = {}

func _init() -> void:
	name = "GMMapSemanticDock"
	custom_minimum_size = Vector2(1220, 610)
	_build_ui()

func configure(value_plugin: EditorPlugin) -> Dictionary:
	editor_plugin = value_plugin
	undo_redo = value_plugin.get_undo_redo() if value_plugin != null else null
	var requested := OS.get_environment("GM_TASK09_SEMANTIC_RESOURCE")
	if requested.is_empty(): _new_resource_from_control()
	else:
		path_edit.text = requested
		_open_path_from_control()
	return {"ok":semantic_map != null and undo_redo != null, "resource_path":current_resource_path, "undo_gateway":"EditorUndoRedoManager"}

func get_capture_snapshot() -> Dictionary:
	return {
		"formal_ui":get_script().resource_path.begins_with("res://addons/gm_editor/map_semantic/"),
		"resource_path":current_resource_path,
		"map_id":str(semantic_map.map_id) if semantic_map != null else "",
		"regions":semantic_map.regions.size() if semantic_map != null else 0,
		"routes":semantic_map.routes.size() if semantic_map != null else 0,
		"anchors":semantic_map.anchors.size() if semantic_map != null else 0,
		"portals":semantic_map.portals.size() if semantic_map != null else 0,
		"camera_zones":semantic_map.camera_zones.size() if semantic_map != null else 0,
		"validation_rows":validation_list.item_count,
		"editable_controls":get_editable_control_names(),
		"can_create_or_edit":undo_redo != null and fields.size() > 0,
		"capabilities":{"new":true,"open":true,"save":true,"save_as":true,"close":true,"create":true,"edit":true,"delete":true,"duplicate":true,"undo":true,"redo":true,"canvas_input":true},
		"last_trace":last_trace.duplicate(true)
	}

func get_editable_control_names() -> PackedStringArray:
	var result := PackedStringArray()
	for key in fields: result.append(str(key))
	result.sort()
	return result

func _build_ui() -> void:
	var root := VBoxContainer.new(); root.add_theme_constant_override("separation", 6); add_child(root)
	var files := HBoxContainer.new(); root.add_child(files)
	var title := Label.new(); title.text = "GM 语义地图工作台"; title.add_theme_font_size_override("font_size", 22); title.custom_minimum_size.x = 230; files.add_child(title)
	_add_action(files, "新建", "new", _new_resource_from_control)
	path_edit = LineEdit.new(); path_edit.name = "SemanticResourcePath"; path_edit.placeholder_text = "res://.../*.tres"; path_edit.custom_minimum_size.x = 330; files.add_child(path_edit)
	_add_action(files, "打开路径", "open", _open_path_from_control)
	_add_action(files, "浏览…", "browse", _browse_open)
	_add_action(files, "保存", "save", _save_from_control)
	_add_action(files, "另存为…", "save_as", _browse_save)
	_add_action(files, "关闭", "close", _close_resource)
	_add_action(files, "撤销", "undo", _undo_from_control)
	_add_action(files, "重做", "redo", _redo_from_control)
	var tools := HBoxContainer.new(); root.add_child(tools)
	map_id_edit = LineEdit.new(); map_id_edit.name = "MapStableId"; map_id_edit.placeholder_text = "gm.map_anchor.map_id"; map_id_edit.custom_minimum_size.x = 240; tools.add_child(map_id_edit)
	_add_action(tools, "应用地图ID", "map_id", _apply_map_id_from_control)
	kind_picker = OptionButton.new(); kind_picker.name = "ObjectKind"
	for kind in ["region", "route", "anchor", "portal", "camera"]:
		kind_picker.add_item(KIND_NAMES[kind]); kind_picker.set_item_metadata(kind_picker.item_count - 1, kind)
	kind_picker.item_selected.connect(_on_kind_selected); tools.add_child(kind_picker)
	_add_action(tools, "新增", "create", _create_from_control)
	_add_action(tools, "应用编辑", "apply", _apply_from_control)
	_add_action(tools, "复制", "duplicate", _duplicate_from_control)
	_add_action(tools, "删除", "delete", _delete_from_control)
	_add_action(tools, "路线反转", "reverse", _reverse_route_from_control)
	_add_action(tools, "闭环切换", "closed", _toggle_route_closed_from_control)
	_add_action(tools, "一键验证", "validate", _run_validation)
	_add_action(tools, "从所选锚点测试", "test", _test_selected_anchor)
	var filters := HBoxContainer.new(); root.add_child(filters)
	for pair in [["全部覆盖","all"],["区域","region"],["路线","route"],["锚点","anchor"],["Portal","portal"],["相机区","camera"]]:
		var button := Button.new(); button.text = pair[0]; button.pressed.connect(func(): canvas.selected_kind = pair[1]; canvas.queue_redraw()); filters.add_child(button)
	var mode_label := Label.new(); mode_label.text = "  画布操作："; filters.add_child(mode_label)
	canvas_mode_picker = OptionButton.new(); canvas_mode_picker.name = "CanvasEditMode"
	for pair in [["选择","select"],["移动点/锚点","move"],["添加点/锚点","add"]]:
		canvas_mode_picker.add_item(pair[0]); canvas_mode_picker.set_item_metadata(canvas_mode_picker.item_count - 1, pair[1])
	canvas_mode_picker.item_selected.connect(func(index): canvas.edit_mode = str(canvas_mode_picker.get_item_metadata(index))); filters.add_child(canvas_mode_picker)
	var body := HSplitContainer.new(); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(body)
	var left := VBoxContainer.new(); left.custom_minimum_size.x = 310; body.add_child(left)
	object_list = ItemList.new(); object_list.name = "SemanticObjectList"; object_list.custom_minimum_size = Vector2(305, 360); object_list.size_flags_vertical = Control.SIZE_EXPAND_FILL; object_list.item_selected.connect(_on_object_selected); left.add_child(object_list)
	validation_list = ItemList.new(); validation_list.name = "ValidationResults"; validation_list.custom_minimum_size = Vector2(305, 150); left.add_child(validation_list)
	var center := VBoxContainer.new(); body.add_child(center)
	canvas = SemanticCanvas.new(); canvas.name = "SemanticCanvas"; canvas.custom_minimum_size = Vector2(600, 400); canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL; canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL; canvas.configure(self); center.add_child(canvas)
	status_title = Label.new(); status_title.add_theme_font_size_override("font_size", 17); center.add_child(status_title)
	status_body = RichTextLabel.new(); status_body.fit_content = true; status_body.custom_minimum_size.y = 58; center.add_child(status_body)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size.x = 390; body.add_child(scroll)
	inspector_box = VBoxContainer.new(); inspector_box.custom_minimum_size.x = 370; scroll.add_child(inspector_box)
	_build_fields()
	file_dialog = FileDialog.new(); file_dialog.name = "SemanticResourceFileDialog"; file_dialog.access = FileDialog.ACCESS_RESOURCES; file_dialog.add_filter("*.tres", "Godot Resource"); file_dialog.file_selected.connect(_on_file_selected); add_child(file_dialog)

func _build_fields() -> void:
	_add_field("id", "稳定ID", "region,route,anchor,portal,camera")
	_add_field("region_polygon", "区域点 x,y;…", "region", "text")
	_add_field("region_tags", "区域标签(逗号)", "region")
	_add_field("region_priority", "区域优先级", "region", "number")
	_add_field("region_overlap", "重叠规则", "region", "option", [["STACK",0],["HIGHEST_PRIORITY",1],["EXCLUSIVE",2]])
	_add_field("region_enter", "进入事件标签", "region")
	_add_field("region_exit", "离开事件标签", "region")
	_add_field("region_camera", "相机配置ID", "region")
	_add_field("route_points", "路线点 x,y|速度|停留|锚点|地图;…", "route", "text")
	_add_field("route_closed", "闭环", "route", "bool")
	_add_field("route_movement", "允许移动类型(逗号)", "route")
	_add_field("anchor_type", "锚点类型ID", "anchor")
	_add_field("anchor_position", "位置 x,y", "anchor")
	_add_field("anchor_facing", "朝向角度", "anchor", "number")
	_add_field("anchor_capacity", "容量", "anchor", "number")
	_add_field("anchor_tags", "锚点标签(逗号)", "anchor")
	_add_field("anchor_label", "编辑器节点/显示名", "anchor")
	_add_field("portal_source_map", "源地图ID", "portal")
	_add_field("portal_source_anchor", "源锚点ID", "portal")
	_add_field("portal_target_map", "目标地图ID", "portal")
	_add_field("portal_target_anchor", "目标锚点ID", "portal")
	_add_field("portal_return_anchor", "返回锚点ID", "portal")
	_add_field("portal_direction", "方向", "portal", "option", [["单向",0],["双向",1]])
	_add_field("portal_ability", "条件能力ID", "portal")
	_add_field("portal_loading", "加载参数(JSON)", "portal", "text")
	_add_field("camera_bounds", "边界 x,y,w,h", "camera")
	_add_field("camera_zoom", "缩放 x,y", "camera")
	_add_field("camera_follow", "跟随方案", "camera", "option", [["lock_on","lock_on"],["smooth_follow","smooth_follow"],["room_center","room_center"]])
	_add_field("camera_target", "目标角色ID", "camera")
	_add_field("camera_priority", "相机优先级", "camera", "number")
	_add_field("camera_pixel", "像素对齐占位", "camera", "bool")
	_set_form_visibility("region")

func _add_action(parent: Container, text: String, key: String, callback: Callable) -> void:
	var button := Button.new(); button.name = "Action_%s" % key; button.text = text; button.pressed.connect(callback); parent.add_child(button); action_buttons[key] = button

func _add_field(key: String, label_text: String, kinds: String, type: String = "line", options: Array = []) -> void:
	var row := HBoxContainer.new(); row.name = "FieldRow_%s" % key; row.set_meta("kinds", kinds)
	var label := Label.new(); label.text = label_text; label.custom_minimum_size.x = 145; row.add_child(label)
	var control: Control
	if type == "text": control = TextEdit.new(); control.custom_minimum_size.y = 72
	elif type == "number": control = SpinBox.new(); control.min_value = -100000; control.max_value = 100000; control.allow_greater = true; control.allow_lesser = true
	elif type == "bool": control = CheckBox.new()
	elif type == "option":
		control = OptionButton.new()
		for option in options: control.add_item(str(option[0])); control.set_item_metadata(control.item_count - 1, option[1])
	else: control = LineEdit.new()
	control.name = "Field_%s" % key; control.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(control); inspector_box.add_child(row); fields[key] = control; field_rows[key] = row

func _new_resource_from_control() -> void:
	semantic_map = GMMapSemanticResource.new()
	var value_id := map_id_edit.text.strip_edges()
	if value_id.is_empty(): value_id = "gm.map_anchor.untitled"
	semantic_map.map_id = value_id
	semantic_map.terrain_map = _make_terrain(value_id)
	current_resource_path = ""; path_edit.text = ""; map_id_edit.text = value_id; selected_object_index = -1
	_rebuild_registry(); _refresh_objects(); canvas.set_resource(semantic_map)
	last_trace = {"action":"new_resource","map_id":value_id,"through_control":true}
	_show_status("新建语义资源", "已创建未保存的 GMMapSemanticResource；请设置稳定地图ID并保存。")

func _make_terrain(value_id: String) -> GMMapResource:
	var terrain := GMMapResource.new(); terrain.map_id = value_id; terrain.map_size = Vector2i(12, 8); terrain.tile_size = Vector2i(32, 32)
	for y in terrain.map_size.y:
		for x in terrain.map_size.x: terrain.set_logic_cell(Vector2i(x, y), {"walkable":true,"cost":1.0})
	return terrain

func _browse_open() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; file_dialog.popup_centered_ratio(0.72)

func _browse_save() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_file = current_resource_path.get_file() if not current_resource_path.is_empty() else "semantic_map.tres"
	file_dialog.popup_centered_ratio(0.72)

func _on_file_selected(path: String) -> void:
	path_edit.text = path
	if file_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE: _open_path_from_control()
	else: _save_to_path(path)

func _open_path_from_control() -> void:
	var path := path_edit.text.strip_edges()
	var loaded := ResourceLoader.load(path, "GMMapSemanticResource", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded is GMMapSemanticResource:
		last_trace = {"action":"open","ok":false,"path":path}; _show_status("打开失败", "路径不是 GMMapSemanticResource：%s" % path); return
	semantic_map = loaded; current_resource_path = path; map_id_edit.text = str(semantic_map.map_id); selected_object_index = -1
	_rebuild_registry(); canvas.set_resource(semantic_map); _refresh_objects(); _run_validation()
	last_trace = {"action":"open","ok":true,"path":path,"through_control":true}; _show_status("资源已打开", path)

func _save_from_control() -> void:
	var path := current_resource_path if not current_resource_path.is_empty() else path_edit.text.strip_edges()
	if path.is_empty(): _browse_save()
	else: _save_to_path(path)

func _save_to_path(path: String) -> void:
	if semantic_map == null: _show_status("保存失败", "没有已打开的语义资源。"); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var error := ResourceSaver.save(semantic_map, path)
	if error == OK:
		current_resource_path = path; path_edit.text = path; last_trace = {"action":"save","ok":true,"path":path,"through_control":true}; _show_status("保存完成", "%s（ResourceSaver）" % path)
	else:
		last_trace = {"action":"save","ok":false,"path":path,"error":error}; _show_status("保存失败", "%s · error=%d" % [path,error])

func _close_resource() -> void:
	var before := current_resource_path
	semantic_map = null; current_resource_path = ""; selected_object_index = -1; object_entries.clear(); object_list.clear(); validation_list.clear(); canvas.set_resource(null)
	last_trace = {"action":"close","path":before,"through_control":true}; _show_status("资源已关闭", "可通过打开路径或浏览重新载入。")

func _apply_map_id_from_control() -> void:
	if semantic_map == null: return
	var before := str(semantic_map.map_id); var after := map_id_edit.text.strip_edges()
	if after.is_empty() or after == before: return
	if undo_redo == null: _show_status("编辑失败", "EditorUndoRedoManager 不可用，拒绝直接修改资源。"); return
	undo_redo.create_action("修改语义地图稳定ID", UndoRedo.MERGE_DISABLE, semantic_map)
	undo_redo.add_do_method(self,"_set_map_id",after)
	undo_redo.add_undo_method(self,"_set_map_id",before)
	undo_redo.commit_action()
	last_trace = {"action":"edit_map_id","before":before,"after":after,"through_control":true}

func _set_map_id(value: String) -> void:
	if semantic_map == null: return
	semantic_map.map_id = value
	if semantic_map.terrain_map != null: semantic_map.terrain_map.map_id = value
	map_id_edit.text = value; _rebuild_registry(); canvas.queue_redraw()

func _on_kind_selected(index: int) -> void:
	selected_kind = str(kind_picker.get_item_metadata(index)); selected_object_index = -1; _set_form_visibility(selected_kind); _clear_form(selected_kind)

func _set_form_visibility(kind: String) -> void:
	for key in field_rows: field_rows[key].visible = str(field_rows[key].get_meta("kinds","")).split(",").has(kind)

func _refresh_objects() -> void:
	object_entries.clear(); object_list.clear()
	if semantic_map == null: return
	for kind in ["region","route","anchor","portal","camera"]:
		var values: Array = semantic_map.get(COLLECTIONS[kind])
		for index in values.size(): object_entries.append({"kind":kind,"index":index}); object_list.add_item(_summary(kind, values[index]))
	canvas.queue_redraw()

func _summary(kind: String, item: Resource) -> String:
	if kind == "region": return "区域  %s  P%d" % [item.region_id,item.priority]
	if kind == "route": return "路线  %s  %d点%s" % [item.route_id,item.points.size()," 闭环" if item.closed else ""]
	if kind == "anchor": return "锚点  %s  容量%d" % [item.anchor_id,item.capacity]
	if kind == "portal": return "Portal  %s  → %s/%s" % [item.portal_id,item.target_map_id,item.target_anchor_id]
	return "Camera2D区  %s  优先级%d" % [item.camera_id,item.priority]

func _on_object_selected(list_index: int) -> void:
	if list_index < 0 or list_index >= object_entries.size(): return
	var entry := object_entries[list_index]; selected_kind = entry.kind; selected_object_index = entry.index
	for index in kind_picker.item_count:
		if str(kind_picker.get_item_metadata(index)) == selected_kind: kind_picker.select(index)
	_set_form_visibility(selected_kind); _load_form(); canvas.selected_kind = selected_kind; canvas.queue_redraw()

func _selected_object() -> Resource:
	if semantic_map == null or selected_object_index < 0: return null
	var values: Array = semantic_map.get(COLLECTIONS[selected_kind])
	return values[selected_object_index] if selected_object_index < values.size() else null

func _create_from_control() -> void:
	if semantic_map == null: return
	var before := _snapshot(selected_kind); var after := _clone(before); var object := _default_object(selected_kind, _next_id(selected_kind)); after.append(object); selected_object_index = after.size() - 1
	_commit_collection("新增%s" % KIND_NAMES[selected_kind], selected_kind, before, after); _select_entry(selected_kind, selected_object_index)
	last_trace = {"action":"create","kind":selected_kind,"object_id":_object_id(selected_kind,object),"through_control":true}

func _apply_from_control() -> void:
	var original := _selected_object()
	if original == null: _show_status("编辑失败", "请先选择对象。"); return
	var parsed := _object_from_form(selected_kind, original)
	if not parsed.ok: _show_status("字段错误", parsed.error_zh); return
	var before := _snapshot(selected_kind); var after := _clone(before); after[selected_object_index] = parsed.object
	_commit_collection("编辑%s" % KIND_NAMES[selected_kind], selected_kind, before, after); _select_entry(selected_kind, selected_object_index)
	last_trace = {"action":"edit","kind":selected_kind,"object_id":_object_id(selected_kind,parsed.object),"through_control":true}

func _duplicate_from_control() -> void:
	var original := _selected_object()
	if original == null: return
	var before := _snapshot(selected_kind); var after := _clone(before); var copy: Resource = original.duplicate(true)
	_set_object_id(selected_kind, copy, _next_id(selected_kind, "%s_copy" % _object_id(selected_kind,original))); after.append(copy); selected_object_index = after.size() - 1
	_commit_collection("复制%s" % KIND_NAMES[selected_kind], selected_kind, before, after); _select_entry(selected_kind,selected_object_index)
	last_trace = {"action":"duplicate","kind":selected_kind,"object_id":_object_id(selected_kind,copy),"through_control":true}

func _delete_from_control() -> void:
	var original := _selected_object()
	if original == null: return
	var removed := _object_id(selected_kind,original); var before := _snapshot(selected_kind); var after := _clone(before); after.remove_at(selected_object_index); selected_object_index = mini(selected_object_index,after.size()-1)
	_commit_collection("删除%s" % KIND_NAMES[selected_kind], selected_kind, before, after)
	last_trace = {"action":"delete","kind":selected_kind,"object_id":removed,"through_control":true}

func _reverse_route_from_control() -> void:
	if selected_kind != "route" or _selected_object() == null: return
	var before := _snapshot("route"); var after := _clone(before); after[selected_object_index].points.reverse(); _commit_collection("反转路线点","route",before,after); _select_entry("route",selected_object_index)
	last_trace = {"action":"route_reverse","route_id":_object_id("route",after[selected_object_index]),"points":_serialize_route(after[selected_object_index].points),"through_control":true}

func _toggle_route_closed_from_control() -> void:
	if selected_kind != "route" or _selected_object() == null: return
	var before := _snapshot("route"); var after := _clone(before); after[selected_object_index].closed = not after[selected_object_index].closed; _commit_collection("切换路线闭环","route",before,after); _select_entry("route",selected_object_index)
	last_trace = {"action":"route_closed","closed":after[selected_object_index].closed,"through_control":true}

func _commit_collection(label: String, kind: String, before: Array, after: Array) -> void:
	if undo_redo == null: _show_status("编辑失败", "EditorUndoRedoManager 不可用，拒绝直接修改资源。"); return
	undo_redo.create_action(label, UndoRedo.MERGE_DISABLE, semantic_map); undo_redo.add_do_method(self,"_replace_collection",kind,after); undo_redo.add_undo_method(self,"_replace_collection",kind,before); undo_redo.commit_action()

func _replace_collection(kind: String, values: Array) -> void:
	if semantic_map == null: return
	if kind == "region":
		var typed: Array[GMSemanticRegion] = []; for value in values: typed.append(value.duplicate(true)); semantic_map.regions = typed
	elif kind == "route":
		var typed: Array[GMSemanticRoute] = []; for value in values: typed.append(value.duplicate(true)); semantic_map.routes = typed
	elif kind == "anchor":
		var typed: Array[GMSemanticAnchor] = []; for value in values: typed.append(value.duplicate(true)); semantic_map.anchors = typed
	elif kind == "portal":
		var typed: Array[GMSemanticPortal] = []; for value in values: typed.append(value.duplicate(true)); semantic_map.portals = typed
	else:
		var typed: Array[GMCameraZoneConfig] = []; for value in values: typed.append(value.duplicate(true)); semantic_map.camera_zones = typed
	semantic_map.emit_changed(); _rebuild_registry(); _refresh_objects()
	if selected_object_index >= 0: _select_entry(kind,selected_object_index)

func _undo_from_control() -> void:
	if undo_redo == null: return
	var history_id := undo_redo.get_object_history_id(semantic_map); var history := undo_redo.get_history_undo_redo(history_id)
	if history != null: history.undo()
	_refresh_objects(); _load_form(); last_trace = {"action":"undo","history_id":history_id,"through_control":true}; _show_status("撤销", "已通过 EditorUndoRedoManager 对应历史恢复 Resource 值。")

func _redo_from_control() -> void:
	if undo_redo == null: return
	var history_id := undo_redo.get_object_history_id(semantic_map); var history := undo_redo.get_history_undo_redo(history_id)
	if history != null: history.redo()
	_refresh_objects(); _load_form(); last_trace = {"action":"redo","history_id":history_id,"through_control":true}; _show_status("重做", "已通过 EditorUndoRedoManager 对应历史重新应用 Resource 值。")

func _snapshot(kind: String) -> Array: return _clone(semantic_map.get(COLLECTIONS[kind])) if semantic_map != null else []
func _clone(values: Array) -> Array:
	var result: Array = []
	for value in values: result.append(value.duplicate(true))
	return result

func _default_object(kind: String, id: String) -> Resource:
	if kind == "region":
		var value := GMSemanticRegion.new(); value.region_id = id; value.polygon = PackedVector2Array([Vector2(48,48),Vector2(144,48),Vector2(144,112),Vector2(48,112)]); return value
	if kind == "route":
		var value := GMSemanticRoute.new(); value.route_id = id; value.map_id = semantic_map.map_id; value.points = [{"position":Vector2(48,48),"speed":1.0,"wait":0.0},{"position":Vector2(144,80),"speed":1.0,"wait":0.0}]; return value
	if kind == "anchor":
		var value := GMSemanticAnchor.new(); value.anchor_id = id; value.position = Vector2(64,64); return value
	if kind == "portal":
		var value := GMSemanticPortal.new(); value.portal_id = id; value.source_map_id = semantic_map.map_id; value.target_map_id = semantic_map.map_id; return value
	var value := GMCameraZoneConfig.new(); value.camera_id = id; value.bounds = Rect2(0,0,320,224); return value

func _next_id(kind: String, preferred: String = "") -> String:
	var candidate := preferred if not preferred.is_empty() else "gm.map_anchor.%s.%d" % [kind,_snapshot(kind).size()+1]; var base := candidate; var suffix := 2
	var ids := PackedStringArray(); for item in _snapshot(kind): ids.append(_object_id(kind,item))
	while ids.has(candidate): candidate = "%s_%d" % [base,suffix]; suffix += 1
	return candidate

func _object_id(kind: String, object: Resource) -> String: return str(object.get(ID_FIELDS[kind]))
func _set_object_id(kind: String, object: Resource, value: String) -> void: object.set(ID_FIELDS[kind],value)

func _clear_form(kind: String) -> void:
	for key in fields:
		if not str(field_rows[key].get_meta("kinds","")).split(",").has(kind): continue
		var control: Control = fields[key]
		if control is LineEdit: control.text = ""
		elif control is TextEdit: control.text = ""
		elif control is SpinBox: control.value = 0
		elif control is CheckBox: control.button_pressed = false
		elif control is OptionButton: control.select(0)

func _load_form() -> void:
	var object := _selected_object()
	if object == null: return
	fields.id.text = _object_id(selected_kind,object)
	if selected_kind == "region":
		fields.region_polygon.text = _serialize_points(object.polygon); fields.region_tags.text = ",".join(object.tags); fields.region_priority.value = object.priority; _select_metadata(fields.region_overlap,object.overlap_rule); fields.region_enter.text = str(object.enter_event_tag); fields.region_exit.text = str(object.exit_event_tag); fields.region_camera.text = str(object.camera_config_id)
	elif selected_kind == "route":
		fields.route_points.text = _serialize_route(object.points); fields.route_closed.button_pressed = object.closed; fields.route_movement.text = ",".join(object.allowed_movement_types)
	elif selected_kind == "anchor":
		fields.anchor_type.text = str(object.anchor_type_id); fields.anchor_position.text = _serialize_vector(object.position); fields.anchor_facing.value = object.facing_degrees; fields.anchor_capacity.value = object.capacity; fields.anchor_tags.text = ",".join(object.tags); fields.anchor_label.text = object.editor_label
	elif selected_kind == "portal":
		fields.portal_source_map.text = str(object.source_map_id); fields.portal_source_anchor.text = str(object.source_anchor_id); fields.portal_target_map.text = str(object.target_map_id); fields.portal_target_anchor.text = str(object.target_anchor_id); fields.portal_return_anchor.text = str(object.return_anchor_id); _select_metadata(fields.portal_direction,object.direction); fields.portal_ability.text = str(object.required_ability_id); fields.portal_loading.text = JSON.stringify(object.loading_parameters)
	else:
		fields.camera_bounds.text = "%s,%s,%s,%s" % [object.bounds.position.x,object.bounds.position.y,object.bounds.size.x,object.bounds.size.y]; fields.camera_zoom.text = _serialize_vector(object.zoom); _select_metadata(fields.camera_follow,object.follow_mode); fields.camera_target.text = str(object.target_role_id); fields.camera_priority.value = object.priority; fields.camera_pixel.button_pressed = object.pixel_align_placeholder

func _object_from_form(kind: String, original: Resource) -> Dictionary:
	var object: Resource = original.duplicate(true); var id: String = fields.id.text.strip_edges()
	if id.is_empty(): return {"ok":false,"error_zh":"稳定ID不能为空"}
	_set_object_id(kind,object,id)
	if kind == "region":
		var points := _parse_points(fields.region_polygon.text); if not points.ok: return points
		object.polygon = points.value; object.tags = _parse_strings(fields.region_tags.text); object.priority = int(fields.region_priority.value); object.overlap_rule = int(fields.region_overlap.get_selected_metadata()); object.enter_event_tag = fields.region_enter.text.strip_edges(); object.exit_event_tag = fields.region_exit.text.strip_edges(); object.camera_config_id = fields.region_camera.text.strip_edges()
	elif kind == "route":
		var points := _parse_route(fields.route_points.text); if not points.ok: return points
		object.map_id = semantic_map.map_id; object.points = points.value; object.closed = fields.route_closed.button_pressed; object.allowed_movement_types = _parse_strings(fields.route_movement.text)
	elif kind == "anchor":
		var point := _parse_vector(fields.anchor_position.text); if not point.ok: return point
		object.anchor_type_id = fields.anchor_type.text.strip_edges(); object.position = point.value; object.facing_degrees = fields.anchor_facing.value; object.capacity = maxi(1,int(fields.anchor_capacity.value)); object.tags = _parse_strings(fields.anchor_tags.text); object.editor_label = fields.anchor_label.text
	elif kind == "portal":
		object.source_map_id = fields.portal_source_map.text.strip_edges(); object.source_anchor_id = fields.portal_source_anchor.text.strip_edges(); object.target_map_id = fields.portal_target_map.text.strip_edges(); object.target_anchor_id = fields.portal_target_anchor.text.strip_edges(); object.return_anchor_id = fields.portal_return_anchor.text.strip_edges(); object.direction = int(fields.portal_direction.get_selected_metadata()); object.required_ability_id = fields.portal_ability.text.strip_edges()
		var parsed = JSON.parse_string(fields.portal_loading.text)
		if parsed == null and not fields.portal_loading.text.strip_edges().is_empty(): return {"ok":false,"error_zh":"加载参数必须是JSON对象"}
		if parsed != null and not parsed is Dictionary: return {"ok":false,"error_zh":"加载参数必须是JSON对象"}
		object.loading_parameters = parsed if parsed is Dictionary else {}
	else:
		var bounds := _parse_numbers(fields.camera_bounds.text,4); if not bounds.ok: return bounds
		var zoom := _parse_vector(fields.camera_zoom.text); if not zoom.ok: return zoom
		object.bounds = Rect2(bounds.value[0],bounds.value[1],bounds.value[2],bounds.value[3]); object.zoom = zoom.value; object.follow_mode = str(fields.camera_follow.get_selected_metadata()); object.target_role_id = fields.camera_target.text.strip_edges(); object.priority = int(fields.camera_priority.value); object.pixel_align_placeholder = fields.camera_pixel.button_pressed
	return {"ok":true,"object":object}

func _serialize_vector(value: Vector2) -> String: return "%s,%s" % [value.x,value.y]
func _serialize_points(values: PackedVector2Array) -> String:
	var rows := PackedStringArray()
	for value in values: rows.append(_serialize_vector(value))
	return ";".join(rows)
func _serialize_route(values: Array[Dictionary]) -> String:
	var rows := PackedStringArray()
	for row in values:
		var point: Vector2 = row.get("position",Vector2.ZERO); rows.append("%s,%s|%s|%s|%s|%s" % [point.x,point.y,row.get("speed",1.0),row.get("wait",0.0),row.get("anchor_id",""),row.get("map_id","")])
	return ";".join(rows)

func _parse_vector(text: String) -> Dictionary:
	var result := _parse_numbers(text,2); return {"ok":true,"value":Vector2(result.value[0],result.value[1])} if result.ok else result
func _parse_numbers(text: String, count: int) -> Dictionary:
	var pieces := text.strip_edges().split(",")
	if pieces.size() != count: return {"ok":false,"error_zh":"需要%d个逗号分隔数值" % count}
	var values: Array[float] = []
	for piece in pieces:
		if not piece.strip_edges().is_valid_float(): return {"ok":false,"error_zh":"数值格式无效：%s" % piece}
		values.append(float(piece))
	return {"ok":true,"value":values}
func _parse_points(text: String) -> Dictionary:
	var result := PackedVector2Array()
	for piece in text.strip_edges().split(";",false):
		var parsed := _parse_vector(piece); if not parsed.ok: return parsed
		result.append(parsed.value)
	return {"ok":true,"value":result}
func _parse_route(text: String) -> Dictionary:
	var result: Array[Dictionary] = []
	for piece in text.strip_edges().split(";",false):
		var columns := piece.split("|",true); var parsed := _parse_vector(columns[0]); if not parsed.ok: return parsed
		var row := {"position":parsed.value,"speed":float(columns[1]) if columns.size()>1 and columns[1].is_valid_float() else 1.0,"wait":float(columns[2]) if columns.size()>2 and columns[2].is_valid_float() else 0.0}
		if columns.size()>3 and not columns[3].is_empty(): row.anchor_id = columns[3]
		if columns.size()>4 and not columns[4].is_empty(): row.map_id = columns[4]
		result.append(row)
	return {"ok":true,"value":result}
func _parse_strings(text: String) -> PackedStringArray:
	var result := PackedStringArray()
	for value in text.split(",",false):
		var cleaned := value.strip_edges(); if not cleaned.is_empty(): result.append(cleaned)
	return result
func _select_metadata(control: OptionButton, value: Variant) -> void:
	for index in control.item_count:
		if control.get_item_metadata(index) == value: control.select(index); return
func _select_entry(kind: String, index: int) -> void:
	for list_index in object_entries.size():
		if object_entries[list_index].kind == kind and object_entries[list_index].index == index: object_list.select(list_index); _on_object_selected(list_index); return

func canvas_find_handle(world: Vector2) -> Dictionary:
	if semantic_map == null: return {}
	var best := {"distance":20.0}
	var editable_kinds := [selected_kind] if selected_kind in ["region","route","anchor"] else ["region","route","anchor"]
	for kind in editable_kinds:
		var values: Array = semantic_map.get(COLLECTIONS[kind])
		for object_index in values.size():
			var points: Array[Vector2] = []
			if kind == "region":
				for point in values[object_index].polygon: points.append(point)
			elif kind == "route":
				for row in values[object_index].points: points.append(row.position)
			else: points.append(values[object_index].position)
			for point_index in points.size():
				var distance := points[point_index].distance_to(world)
				if distance < float(best.distance): best = {"kind":kind,"object_index":object_index,"point_index":point_index,"distance":distance}
	return {} if not best.has("kind") else best
func canvas_select_at(world: Vector2) -> void:
	var hit := canvas_find_handle(world); if not hit.is_empty(): _select_entry(hit.kind,hit.object_index)
func canvas_move_handle(hit: Dictionary, world: Vector2) -> void:
	var kind := str(hit.kind); var before := _snapshot(kind); var after := _clone(before)
	if kind == "region":
		var points: PackedVector2Array = after[hit.object_index].polygon; points[hit.point_index] = world; after[hit.object_index].polygon = points
	elif kind == "route":
		var row: Dictionary = after[hit.object_index].points[hit.point_index].duplicate(true); row.position = world; after[hit.object_index].points[hit.point_index] = row
	else: after[hit.object_index].position = world
	selected_kind = kind; selected_object_index = hit.object_index; _commit_collection("画布移动%s点" % KIND_NAMES[kind],kind,before,after); _select_entry(kind,selected_object_index)
	last_trace = {"action":"canvas_move","kind":kind,"point_index":hit.point_index,"position":world,"through_gui_input":true}
func canvas_add_at(world: Vector2) -> void:
	if selected_kind == "anchor":
		_create_from_control(); fields.anchor_position.text = _serialize_vector(world); _apply_from_control(); last_trace = {"action":"canvas_add_anchor","position":world,"through_gui_input":true}; return
	if selected_kind not in ["region","route"] or _selected_object() == null: return
	var before := _snapshot(selected_kind); var after := _clone(before)
	if selected_kind == "region":
		var points: PackedVector2Array = after[selected_object_index].polygon; points.append(world); after[selected_object_index].polygon = points
	else: after[selected_object_index].points.append({"position":world,"speed":1.0,"wait":0.0})
	_commit_collection("画布添加%s点" % KIND_NAMES[selected_kind],selected_kind,before,after); _select_entry(selected_kind,selected_object_index)
	last_trace = {"action":"canvas_add_point","kind":selected_kind,"position":world,"through_gui_input":true}

func _run_validation() -> void:
	validation_list.clear()
	if semantic_map == null: return
	_rebuild_registry(); var session := GMMapSemanticValidator.new().begin(registry); var result := session.step(256)
	if result.results.is_empty(): validation_list.add_item("通过 · 当前资源无阻断错误")
	for row in result.results: validation_list.add_item("%s · %s · %s · %s" % [row.get("map_id",""),row.get("object_id",""),row.get("code",""),row.get("error_zh","")])
	last_trace = {"action":"validate","complete":result.complete,"cancelled":result.cancelled,"mutated":false,"result_count":result.results.size(),"through_control":true}; _show_status("一键验证完成", "结果含地图、对象和规则码；验证器只报告，不移动正式对象。")
func _test_selected_anchor() -> void:
	if selected_kind != "anchor" or not _selected_object() is GMSemanticAnchor: _show_status("从当前位置测试","请先选择锚点。"); return
	_rebuild_registry(); var anchor: GMSemanticAnchor = _selected_object(); var result := GMSemanticRuntime.new(registry).make_test_launch(semantic_map.map_id,anchor.anchor_id)
	last_trace = {"action":"test_from_anchor","result":result,"save_payload":GMSemanticRuntime.sanitize_save_payload({"slot":"formal","semantic_test_launch":result}),"through_control":true}; _show_status("从所选锚点测试","ephemeral=%s；persist_to_save=%s；正式存档已剔除测试参数。" % [result.get("ephemeral",false),result.get("persist_to_save",true)])
func _rebuild_registry() -> void:
	registry = GMMapSemanticRegistry.new(); if semantic_map != null: registry.register_map(semantic_map)
func _show_status(title: String, body: String) -> void:
	status_title.text = title; status_title.modulate = Color("8be9bd"); status_body.text = body

# 自动化仅操作本 Dock 已存在的正式控件并向正式 canvas.gui_input 信号送入鼠标事件。
# 它不直接写 GMMapSemanticResource、不创建替代 UI，也不伪造验证结果。
func drive_capture_through_formal_controls(state: String, save_path: String) -> Dictionary:
	map_id_edit.text = "gm.map_anchor.b09_capture"; action_buttons.new.pressed.emit()
	_ui_create("camera", {"id":"gm.camera.b09_room","camera_bounds":"0,0,320,224","camera_zoom":"1,1","camera_target":"player","camera_priority":5})
	_ui_create("region", {"id":"gm.map_anchor.region.b09_room","region_polygon":"32,32;256,32;256,192;32,192","region_tags":"room,shop","region_priority":10,"region_camera":"gm.camera.b09_room"})
	_ui_create("anchor", {"id":"gm.map_anchor.player_spawn","anchor_type":"gm.anchor_type.spawn","anchor_position":"48,48","anchor_facing":0,"anchor_capacity":1,"anchor_tags":"spawn","anchor_label":"PlayerSpawnNode"})
	_ui_create("anchor", {"id":"gm.map_anchor.shop_counter","anchor_type":"gm.anchor_type.interaction","anchor_position":"112,112","anchor_facing":90,"anchor_capacity":2,"anchor_tags":"shop,work","anchor_label":"ShopCounterNode"})
	_ui_create("route", {"id":"gm.map_anchor.route.b09_patrol","route_points":"48,48|1.0|0.0|gm.map_anchor.player_spawn|;112,112|0.8|1.5|gm.map_anchor.shop_counter|;224,160|1.2|0.0||","route_closed":true,"route_movement":"walk"})
	_ui_create("portal", {"id":"gm.map_anchor.portal.b09_door","portal_source_map":"gm.map_anchor.b09_capture","portal_source_anchor":"gm.map_anchor.shop_counter","portal_target_map":"gm.map_anchor.b09_capture","portal_target_anchor":"gm.map_anchor.player_spawn","portal_return_anchor":"gm.map_anchor.shop_counter","portal_direction":1,"portal_ability":"gm.ability.open_door","portal_loading":"{\"transition\":\"fade\",\"spawn_facing\":180}"})
	path_edit.text = save_path; action_buttons.save.pressed.emit()
	var trace := {"action":"formal_control_setup","state":state,"saved":current_resource_path==save_path,"through_controls":true}
	if state == "anchor_refactor":
		_select_object_by_id("anchor","gm.map_anchor.shop_counter"); fields.anchor_label.text = "柜台节点_已重命名"; action_buttons.apply.pressed.emit()
		canvas_mode_picker.select(1); canvas.edit_mode = "move"
		var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = canvas.world_to_canvas(Vector2(112,112)); canvas.gui_input.emit(press)
		var release := InputEventMouseButton.new(); release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false; release.position = canvas.world_to_canvas(Vector2(144,112)); canvas.gui_input.emit(release)
		var resolved := semantic_map.resolve_anchor(&"gm.map_anchor.shop_counter")
		trace = {"action":"anchor_move_and_node_rename","before_position":Vector2(112,112),"after_position":resolved.anchor.position,"stable_id_before":"gm.map_anchor.shop_counter","stable_id_after":str(resolved.anchor.anchor_id),"editor_label_after":resolved.anchor.editor_label,"reference_ok":resolved.ok,"through_gui_input":true}
	elif state == "errors":
		_ui_create("region", {"id":"gm.map_anchor.region.invalid_cross","region_polygon":"32,32;192,192;32,192;192,32","region_priority":11}); action_buttons.validate.pressed.emit(); trace = last_trace.duplicate(true); trace.through_controls = true
	elif state == "portal":
		_select_object_by_id("portal","gm.map_anchor.portal.b09_door"); var portal: GMSemanticPortal = _selected_object(); var result := portal.request_transfer(registry,PackedStringArray(["gm.ability.open_door"]))
		trace = {"action":"portal_runtime","result":result,"identity_uses_node_path":false,"direction":"bidirectional","return_anchor":str(portal.return_anchor_id),"through_selected_form":true,"through_controls":true}; _show_status("Portal 运行与编辑","正式表单显示源/目标、方向、返回点、能力与加载参数；目标按稳定ID解析。")
	elif state == "test":
		_select_object_by_id("anchor","gm.map_anchor.player_spawn"); action_buttons.test.pressed.emit(); trace = last_trace.duplicate(true); trace.through_controls = true
	else:
		_select_object_by_id("route","gm.map_anchor.route.b09_patrol"); var before: String = fields.route_points.text; action_buttons.reverse.pressed.emit(); var after: String = fields.route_points.text; action_buttons.undo.pressed.emit(); var undone: String = fields.route_points.text; action_buttons.redo.pressed.emit(); var redone: String = fields.route_points.text
		trace = {"action":"draw_edit_undo_redo","before":before,"after":after,"undo":undone,"redo":redone,"undo_restored":before==undone,"redo_restored":after==redone,"gateway":"EditorUndoRedoManager","through_controls":true}
	last_trace = trace; action_buttons.save.pressed.emit(); return trace

func run_b09_01_user_path_probe(save_path: String) -> Dictionary:
	var facts := {"setup":drive_capture_through_formal_controls("main",save_path)}
	# 五类对象的复制与删除均由同一组正式按钮触发。
	var crud_by_kind := {}; var all_copy_ok := true; var all_delete_ok := true
	for kind in ["region","route","anchor","portal","camera"]:
		var values: Array = semantic_map.get(COLLECTIONS[kind]); _select_entry(kind,0); var before_count := values.size(); action_buttons.duplicate.pressed.emit(); var copied_count: int = semantic_map.get(COLLECTIONS[kind]).size(); action_buttons.delete.pressed.emit(); var deleted_count: int = semantic_map.get(COLLECTIONS[kind]).size(); var copy_ok := copied_count==before_count+1; var delete_ok := deleted_count==before_count; all_copy_ok = all_copy_ok and copy_ok; all_delete_ok = all_delete_ok and delete_ok; crud_by_kind[kind] = {"before":before_count,"after_copy":copied_count,"after_delete":deleted_count,"copy_ok":copy_ok,"delete_ok":delete_ok}
	facts.crud = {"by_kind":crud_by_kind,"copy_ok":all_copy_ok,"delete_ok":all_delete_ok}
	# 真实画布输入：添加区域点、添加路线点、添加锚点，并移动锚点。
	_select_object_by_id("region","gm.map_anchor.region.b09_room"); canvas.edit_mode = "add"; _emit_canvas_click(Vector2(176,208)); var region_points := semantic_map.regions[0].polygon.size()
	_select_object_by_id("route","gm.map_anchor.route.b09_patrol"); canvas.edit_mode = "add"; _emit_canvas_click(Vector2(256,96)); var route_points := semantic_map.routes[0].points.size()
	selected_kind = "anchor"; canvas.edit_mode = "add"; _emit_canvas_click(Vector2(288,64)); var anchors_after_add := semantic_map.anchors.size()
	_select_object_by_id("anchor","gm.map_anchor.shop_counter"); fields.anchor_label.text = "柜台节点_已重命名"; action_buttons.apply.pressed.emit(); canvas.edit_mode = "move"; _emit_canvas_drag(Vector2(112,112),Vector2(144,112)); var moved_anchor := semantic_map.resolve_anchor(&"gm.map_anchor.shop_counter")
	facts.canvas = {"region_points":region_points,"route_points":route_points,"anchors":anchors_after_add,"anchor_position":moved_anchor.anchor.position,"anchor_editor_label":moved_anchor.anchor.editor_label,"stable_reference_ok":moved_anchor.ok,"through_gui_input":true}
	# 逐值 Undo/Redo：路线反转后撤销并重做。
	_select_object_by_id("route","gm.map_anchor.route.b09_patrol"); var before_order: String = fields.route_points.text; action_buttons.reverse.pressed.emit(); var after_order: String = fields.route_points.text; action_buttons.undo.pressed.emit(); var undo_order: String = fields.route_points.text; action_buttons.redo.pressed.emit(); var redo_order: String = fields.route_points.text
	facts.undo_redo = {"gateway":"EditorUndoRedoManager","before":before_order,"after":after_order,"undo":undo_order,"redo":redo_order,"undo_restored":before_order==undo_order,"redo_restored":after_order==redo_order}
	# 关闭并用正式打开路径控件在同一编辑器进程重开；独立进程由外部 reader 再验证。
	path_edit.text = save_path; action_buttons.save.pressed.emit(); var saved_counts := _counts(); action_buttons.close.pressed.emit(); path_edit.text = save_path; action_buttons.open.pressed.emit(); var reopened_counts := _counts()
	facts.save_close_open = {"path":save_path,"saved_counts":saved_counts,"reopened_counts":reopened_counts,"same_values":saved_counts==reopened_counts,"resource_loader":true,"resource_saver":true}
	facts.capabilities = get_capture_snapshot(); last_trace = {"action":"b09_01_user_path_probe","facts":facts,"through_controls":true}; return facts

func _ui_create(kind: String, values: Dictionary) -> void:
	for index in kind_picker.item_count:
		if str(kind_picker.get_item_metadata(index)) == kind: kind_picker.select(index); kind_picker.item_selected.emit(index); break
	action_buttons.create.pressed.emit()
	for key in values:
		var control: Control = fields.get(key)
		if control is LineEdit: control.text = str(values[key])
		elif control is TextEdit: control.text = str(values[key])
		elif control is SpinBox: control.value = float(values[key])
		elif control is CheckBox: control.button_pressed = bool(values[key])
		elif control is OptionButton: _select_metadata(control,values[key])
	action_buttons.apply.pressed.emit()

func _select_object_by_id(kind: String, id: String) -> void:
	var values: Array = semantic_map.get(COLLECTIONS[kind])
	for index in values.size():
		if _object_id(kind,values[index]) == id: _select_entry(kind,index); return

func _emit_canvas_click(world: Vector2) -> void:
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true; event.position = canvas.world_to_canvas(world); canvas.gui_input.emit(event)

func _emit_canvas_drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = canvas.world_to_canvas(from); canvas.gui_input.emit(press)
	var release := InputEventMouseButton.new(); release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false; release.position = canvas.world_to_canvas(to); canvas.gui_input.emit(release)

func _counts() -> Dictionary:
	return {"regions":semantic_map.regions.size(),"routes":semantic_map.routes.size(),"anchors":semantic_map.anchors.size(),"portals":semantic_map.portals.size(),"camera_zones":semantic_map.camera_zones.size()}
