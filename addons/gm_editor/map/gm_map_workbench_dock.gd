@tool
class_name GMMapWorkbenchDock
extends PanelContainer

class FormalMapCanvas:
	extends Control
	var map_resource: GMMapResource
	var read_only := false

	func set_map(value: GMMapResource) -> void:
		map_resource = value
		queue_redraw()

	func set_read_only(value: bool) -> void:
		read_only = value
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("101723"), true)
		if map_resource == null: return
		var is_iso := map_resource.grid_type == "isometric"
		var cell_size := Vector2(48, 34) if is_iso else Vector2(42, 42)
		var origin := Vector2(58, 38)
		for y in mini(map_resource.map_size.y, 7):
			for x in mini(map_resource.map_size.x, 10):
				var key := GMMapResource.cell_key(Vector2i(x, y))
				var terrain := int(map_resource.visual_cells.get("ground", {}).get(key, -1))
				var logic: Dictionary = map_resource.logic_cells.get(key, {})
				var color := Color("26364a") if terrain < 0 else Color("357a55")
				if not logic.is_empty(): color = Color("43a66a") if bool(logic.get("walkable", false)) else Color("c55353")
				if terrain >= 8: color = Color("d49b38")
				if is_iso:
					var center := origin + Vector2((x - y) * cell_size.x * 0.5 + 190, (x + y) * cell_size.y * 0.5)
					var diamond := PackedVector2Array([center + Vector2(0, -cell_size.y * 0.5), center + Vector2(cell_size.x * 0.5, 0), center + Vector2(0, cell_size.y * 0.5), center + Vector2(-cell_size.x * 0.5, 0)])
					draw_colored_polygon(diamond, color)
					draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("90a4ae"), 1.0)
				else:
					var rect := Rect2(origin + Vector2(x, y) * cell_size, cell_size - Vector2(2, 2))
					draw_rect(rect, color, true)
					draw_rect(rect, Color("90a4ae"), false, 1.0)
		if read_only: draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.05, 0.05, 0.25), true)

const SQUARE_PATH := "res://gm_runtime/editor_templates/maps/square_map_template.tres"
const ISOMETRIC_PATH := "res://gm_runtime/editor_templates/maps/isometric_map_template.tres"

var editor_plugin: EditorPlugin
var controller: GMMapWorkbenchController
var current_map: GMMapResource
var current_resource_path := ""
var backend := GMTileMapDualBackend2D.new()
var read_only := false
var last_operation_trace: Dictionary = {}
var _map_choice: OptionButton
var _resource_label: Label
var _grid_label: Label
var _layer_list: ItemList
var _canvas: FormalMapCanvas
var _status_title: Label
var _status_body: Label
var _paint_button: Button
var _undo_button: Button
var _redo_button: Button

func _init() -> void:
	name = "GMMapWorkbenchDock"
	custom_minimum_size = Vector2(1040, 480)
	_build_formal_ui()

func configure(value_plugin: EditorPlugin, value_controller: GMMapWorkbenchController) -> Dictionary:
	editor_plugin = value_plugin
	controller = value_controller
	var result := open_resource_path(SQUARE_PATH)
	refresh_dependency_state()
	return result

func open_resource_path(path: String) -> Dictionary:
	var loaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded is GMMapResource:
		return {"ok":false,"code":"map.resource_invalid","error_zh":"无法打开地图资源：%s" % path}
	current_map = loaded.duplicate(true)
	current_resource_path = path
	var opened := controller.configure(current_map, editor_plugin) if controller != null else {"ok":false,"code":"map.workbench_controller_missing"}
	_map_choice.select(1 if path == ISOMETRIC_PATH else 0)
	_refresh_map_view()
	return opened

func paint_cells(layer_id: StringName, cells: Array[Vector2i], terrain_id: int) -> Dictionary:
	if read_only: return {"ok":false,"code":"map.read_only","error_zh":_status_body.text,"resource_mutated":false}
	var before_count: int = current_map.visual_cells.get(str(layer_id), {}).size()
	var result := controller.draw_brush(layer_id, cells, terrain_id)
	last_operation_trace = {"action":"draw","result":result,"before_count":before_count,"after_draw_count":current_map.visual_cells.get(str(layer_id), {}).size()}
	_show_operation_state("绘制完成", "正式画笔已通过 EditorUndoRedoManager 提交；当前地表单元：%s" % last_operation_trace.after_draw_count)
	_refresh_map_view()
	return result

func undo_last() -> Dictionary:
	var history := _formal_history()
	if history == null or not history.has_undo(): return {"ok":false,"code":"map.undo_unavailable"}
	history.undo()
	last_operation_trace["after_undo_count"] = current_map.visual_cells.get("ground", {}).size()
	_show_operation_state("撤销完成", "正式撤销已执行；当前地表单元：%s" % last_operation_trace.after_undo_count)
	_refresh_map_view()
	return {"ok":true,"count":last_operation_trace.after_undo_count}

func redo_last() -> Dictionary:
	var history := _formal_history()
	if history == null or not history.has_redo(): return {"ok":false,"code":"map.redo_unavailable"}
	history.redo()
	last_operation_trace["after_redo_count"] = current_map.visual_cells.get("ground", {}).size()
	_show_operation_state("重做完成", "绘制 → 撤销 → 重做 已完成；当前地表单元：%s" % last_operation_trace.after_redo_count)
	_refresh_map_view()
	return {"ok":true,"count":last_operation_trace.after_redo_count}

func refresh_dependency_state() -> Dictionary:
	var health := backend.availability()
	read_only = not bool(health.get("ok", false))
	_paint_button.disabled = read_only
	_undo_button.disabled = read_only
	_redo_button.disabled = read_only
	_canvas.set_read_only(read_only)
	if read_only:
		_status_title.text = "只读模式 · TileMapDual 不可用"
		_status_title.modulate = Color("ff7777")
		_status_body.text = "%s\n错误码：%s\n关闭式保护：绘制已禁用，地图资源不会被改写。" % [health.get("error_zh", "地图后端不可用"), health.get("code", "map.backend_unavailable")]
	else:
		_status_title.text = "可编辑 · TileMapDual %s" % health.get("plugin_version", "")
		_status_title.modulate = Color("8be28b")
		_status_body.text = "正式地图工作台已连接 GMMapWorkbenchController 与 EditorUndoRedoManager。"
	return health

func show_layer_configuration() -> void:
	_layer_list.grab_focus()
	_status_title.text = "图层配置 · 三表现层 + 一逻辑层"
	_status_title.modulate = Color.WHITE
	_status_body.text = "图层来源：GMMapResource.layers；顺序、类型、锁定和可见状态来自实际资源。"

func get_capture_snapshot() -> Dictionary:
	var script_path: String = get_script().resource_path if get_script() != null else ""
	return {"ui_source_formal":script_path.begins_with("res://addons/gm_editor/map/"),"ui_root_script":script_path,"ui_root_class":"GMMapWorkbenchDock","current_resource_path":current_resource_path,"grid_type":current_map.grid_type if current_map != null else "","layer_count":current_map.layers.size() if current_map != null else 0,"presentation_layer_count":_presentation_layer_count(),"logic_layer_count":_logic_layer_count(),"read_only":read_only,"controller_script":controller.get_script().resource_path if controller != null else "","manager_class":controller.editor_undo_redo.get_class() if controller != null and controller.editor_undo_redo != null else "","operation_trace":last_operation_trace.duplicate(true)}

func _build_formal_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)
	var title := Label.new()
	title.text = "GM 地图工作台"
	title.add_theme_font_size_override("font_size", 23)
	title.custom_minimum_size.x = 220
	toolbar.add_child(title)
	_map_choice = OptionButton.new()
	_map_choice.add_item("方格样板")
	_map_choice.add_item("等距样板")
	_map_choice.item_selected.connect(_on_map_selected)
	toolbar.add_child(_map_choice)
	_paint_button = Button.new()
	_paint_button.text = "画笔绘制"
	_paint_button.pressed.connect(_paint_demo_cells)
	toolbar.add_child(_paint_button)
	_undo_button = Button.new()
	_undo_button.text = "撤销"
	_undo_button.pressed.connect(undo_last)
	toolbar.add_child(_undo_button)
	_redo_button = Button.new()
	_redo_button.text = "重做"
	_redo_button.pressed.connect(redo_last)
	toolbar.add_child(_redo_button)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 270
	body.add_child(left)
	_resource_label = Label.new()
	_resource_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_resource_label)
	_grid_label = Label.new()
	left.add_child(_grid_label)
	var layers_title := Label.new()
	layers_title.text = "图层（实际资源配置）"
	layers_title.add_theme_font_size_override("font_size", 17)
	left.add_child(layers_title)
	_layer_list = ItemList.new()
	_layer_list.custom_minimum_size = Vector2(270, 250)
	left.add_child(_layer_list)
	_canvas = FormalMapCanvas.new()
	_canvas.custom_minimum_size = Vector2(560, 340)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_canvas)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 330
	body.add_child(right)
	_status_title = Label.new()
	_status_title.add_theme_font_size_override("font_size", 18)
	right.add_child(_status_title)
	_status_body = Label.new()
	_status_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_body.custom_minimum_size = Vector2(320, 180)
	right.add_child(_status_body)
	var legend := Label.new()
	legend.text = "地图画布图例\n绿色：可通行逻辑单元\n红色：不可通行逻辑单元\n金色：本次画笔结果\n深蓝：空单元"
	right.add_child(legend)

func _refresh_map_view() -> void:
	_resource_label.text = "资源：%s" % current_resource_path
	_grid_label.text = "网格：%s　尺寸：%s　瓦片：%s" % [current_map.grid_type, current_map.map_size, current_map.tile_size]
	_layer_list.clear()
	for layer in current_map.layers:
		var kind_name := "逻辑" if layer.kind == GMMapLayerDefinition.LayerKind.LOGIC else "表现"
		_layer_list.add_item("%s  [%s]  %s  顺序 %s" % [layer.display_name_zh, layer.layer_id, kind_name, layer.draw_order])
	_canvas.set_map(current_map)

func _show_operation_state(title: String, body: String) -> void:
	_status_title.text = title
	_status_title.modulate = Color("ffd166")
	_status_body.text = body

func _formal_history() -> UndoRedo:
	if controller == null or controller.editor_undo_redo == null or controller.session == null: return null
	var history_id := controller.editor_undo_redo.get_object_history_id(current_map)
	last_operation_trace["formal_editor_history_id"] = history_id
	last_operation_trace["manager_class"] = controller.editor_undo_redo.get_class()
	return controller.editor_undo_redo.get_history_undo_redo(history_id)

func _presentation_layer_count() -> int:
	var count := 0
	if current_map != null:
		for layer in current_map.layers:
			if layer.kind != GMMapLayerDefinition.LayerKind.LOGIC: count += 1
	return count

func _logic_layer_count() -> int:
	var count := 0
	if current_map != null:
		for layer in current_map.layers:
			if layer.kind == GMMapLayerDefinition.LayerKind.LOGIC: count += 1
	return count

func _on_map_selected(index: int) -> void:
	open_resource_path(ISOMETRIC_PATH if index == 1 else SQUARE_PATH)
	refresh_dependency_state()

func _paint_demo_cells() -> void:
	var cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)]
	paint_cells(&"ground", cells, 8)
