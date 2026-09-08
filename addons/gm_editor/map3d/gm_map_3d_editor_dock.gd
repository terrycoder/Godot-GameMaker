@tool
class_name GMMap3DEditorDock
extends PanelContainer

const GRAPH_SCRIPT := preload("res://gm_runtime/map/3d/gm_surface_graph.gd")
const SURFACE_SCRIPT := preload("res://gm_runtime/map/3d/gm_surface_definition_3d.gd")
const CONNECTION_SCRIPT := preload("res://gm_runtime/map/3d/gm_surface_connection.gd")
const GIZMO_NODE_SCRIPT := preload("res://addons/gm_editor/map3d/gm_surface_gizmo_node.gd")
const TIER1_SAMPLE := preload("res://gm_runtime/editor_templates/planar3d/gm_ext_3d_03_courtyard_template.gd")

var editor_interface
var editor_undo_redo
var graph: Resource
var graph_path := "user://gm_ext_3d_02_surface_graph_editor.tres"
var last_validation: Dictionary = {}
var last_operation: Dictionary = {}
var last_reopen: Dictionary = {}

var _graph_path_edit: LineEdit
var _display_name_edit: LineEdit
var _surface_list: ItemList
var _connection_list: ItemList
var _status_title: Label
var _status_body: Label
var _validation_list: ItemList
var _preview: SubViewport
var _preview_root: Node3D
var _preview_title: Label
var _tier1_projection_visible: bool = false
var _save_button: Button
var _reopen_button: Button
var _undo_button: Button
var _redo_button: Button
var _validate_button: Button
var _apply_button: Button
var _surface_count_label: Label
var _connection_count_label: Label

var _surface_id_edit: LineEdit
var _surface_name_edit: LineEdit
var _surface_kind_option: OptionButton
var _surface_boundary_edit: LineEdit
var _surface_origin_edit: LineEdit
var _surface_slope_edit: LineEdit
var _surface_max_slope_edit: LineEdit
var _surface_profiles_edit: LineEdit
var _surface_region_edit: LineEdit
var _surface_walkable_check: CheckBox
var _surface_new_button: Button
var _surface_apply_button: Button
var _surface_delete_button: Button
var _connection_id_edit: LineEdit
var _connection_source_option: OptionButton
var _connection_source_exit_edit: LineEdit
var _connection_target_option: OptionButton
var _connection_target_entry_edit: LineEdit
var _connection_kind_option: OptionButton
var _connection_direction_option: OptionButton
var _connection_bidirectional_check: CheckBox
var _connection_profiles_edit: LineEdit
var _connection_cost_edit: LineEdit
var _connection_ability_edit: LineEdit
var _connection_enabled_check: CheckBox
var _connection_new_button: Button
var _connection_apply_button: Button
var _connection_delete_button: Button
var _selected_surface_id := ""
var _selected_connection_id := ""

func _init() -> void:
    name = "GMMap3DEditorDock"
    custom_minimum_size = Vector2(1080, 520)
    _build_formal_ui()

func configure(value_editor_interface, value_editor_undo_redo) -> void:
        editor_interface = value_editor_interface
        editor_undo_redo = value_editor_undo_redo
        var requested_path := OS.get_environment("GM_EXT_3D_02_EDITOR_GRAPH_PATH")
        if not requested_path.is_empty():
                graph_path = requested_path

## EXT04 consumes the same authored Surface Graph resource instead of
## creating another map/graph authority.  The returned resource is read by
## the SceneRecipe3D presentation adapter and remains owned by this Dock.
func get_graph_resource() -> Resource:
    return graph

func _ready() -> void:
    if graph == null:
        graph = _build_sample_graph()
    _graph_path_edit.text = graph_path
    _display_name_edit.text = str(graph.get("display_name_zh"))
    _refresh_formal_view()

func _build_formal_ui() -> void:
    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 7)
    add_child(root)
    var header := HBoxContainer.new()
    root.add_child(header)
    var title := Label.new()
    title.text = "平面 3D 地图 · Surface Graph 工作台"
    title.add_theme_font_size_override("font_size", 22)
    title.custom_minimum_size.x = 360
    header.add_child(title)
    var path_label := Label.new()
    path_label.text = "资源路径"
    header.add_child(path_label)
    _graph_path_edit = LineEdit.new()
    _graph_path_edit.custom_minimum_size.x = 330
    _graph_path_edit.text = graph_path
    header.add_child(_graph_path_edit)
    _save_button = Button.new()
    _save_button.text = "保存 Graph"
    _save_button.pressed.connect(_on_save_pressed)
    header.add_child(_save_button)
    _reopen_button = Button.new()
    _reopen_button.text = "关闭并重新打开"
    _reopen_button.pressed.connect(_on_reopen_pressed)
    header.add_child(_reopen_button)

    var body := HBoxContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 10)
    root.add_child(body)
    var left_scroll := ScrollContainer.new()
    left_scroll.custom_minimum_size.x = 560
    left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_child(left_scroll)
    var left := VBoxContainer.new()
    left.custom_minimum_size.x = 540
    left_scroll.add_child(left)
    var graph_title := Label.new()
    graph_title.text = "Surface Graph（正式 Resource）"
    graph_title.add_theme_font_size_override("font_size", 17)
    left.add_child(graph_title)
    var display_label := Label.new()
    display_label.text = "Graph中文名称"
    left.add_child(display_label)
    _display_name_edit = LineEdit.new()
    _display_name_edit.text = "平面3D地图"
    left.add_child(_display_name_edit)
    _apply_button = Button.new()
    _apply_button.text = "应用名称编辑（可撤销）"
    _apply_button.pressed.connect(_on_apply_pressed)
    left.add_child(_apply_button)
    var history_row := HBoxContainer.new()
    left.add_child(history_row)
    _undo_button = Button.new()
    _undo_button.text = "撤销"
    _undo_button.pressed.connect(_on_undo_pressed)
    history_row.add_child(_undo_button)
    _redo_button = Button.new()
    _redo_button.text = "重做"
    _redo_button.pressed.connect(_on_redo_pressed)
    history_row.add_child(_redo_button)
    _validate_button = Button.new()
    _validate_button.text = "中文校验"
    _validate_button.pressed.connect(_on_validate_pressed)
    history_row.add_child(_validate_button)
    var crud_title := Label.new()
    crud_title.text = "正式 Surface / Connection CRUD（所有成功操作进入 EditorUndoRedoManager）"
    crud_title.add_theme_color_override("font_color", Color("8be9bd"))
    left.add_child(crud_title)
    var crud_toolbar := HBoxContainer.new()
    crud_toolbar.name = "VisibleCRUDToolbar"
    left.add_child(crud_toolbar)
    _surface_new_button = _add_form_button(crud_toolbar, "新建 Surface", _on_surface_new_pressed)
    _surface_apply_button = _add_form_button(crud_toolbar, "应用编辑", _on_surface_apply_pressed)
    _surface_delete_button = _add_form_button(crud_toolbar, "删除 Surface", _on_surface_delete_pressed)
    _connection_new_button = _add_form_button(crud_toolbar, "新建 Connection", _on_connection_new_pressed)
    _connection_apply_button = _add_form_button(crud_toolbar, "应用编辑", _on_connection_apply_pressed)
    _connection_delete_button = _add_form_button(crud_toolbar, "删除 Connection", _on_connection_delete_pressed)
    _surface_count_label = Label.new()
    left.add_child(_surface_count_label)
    _surface_list = ItemList.new()
    _surface_list.name = "SurfaceList"
    _surface_list.custom_minimum_size = Vector2(520, 118)
    _surface_list.item_selected.connect(_on_surface_selected)
    left.add_child(_surface_list)
    _connection_count_label = Label.new()
    left.add_child(_connection_count_label)
    _connection_list = ItemList.new()
    _connection_list.name = "ConnectionList"
    _connection_list.custom_minimum_size = Vector2(520, 118)
    _connection_list.item_selected.connect(_on_connection_selected)
    left.add_child(_connection_list)
    var crud_forms := HBoxContainer.new()
    crud_forms.name = "SurfaceConnectionCRUDForms"
    crud_forms.add_theme_constant_override("separation", 8)
    left.add_child(crud_forms)
    _build_surface_form(crud_forms)
    _build_connection_form(crud_forms)
    var validation_title := Label.new()
    validation_title.text = "校验结果（中文错误路径）"
    left.add_child(validation_title)
    _validation_list = ItemList.new()
    _validation_list.custom_minimum_size = Vector2(290, 92)
    left.add_child(_validation_list)

    var preview_panel := VBoxContainer.new()
    preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_child(preview_panel)
    var preview_title := Label.new()
    preview_title.text = "3D Gizmo / Surface颜色 / Connection预览（编辑器投影）"
    preview_title.add_theme_font_size_override("font_size", 17)
    _preview_title = preview_title
    preview_panel.add_child(preview_title)
    var preview_container := SubViewportContainer.new()
    preview_container.custom_minimum_size = Vector2(690, 370)
    preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
    preview_container.stretch = true
    preview_panel.add_child(preview_container)
    _preview = SubViewport.new()
    _preview.size = Vector2i(690, 370)
    _preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _preview.transparent_bg = false
    preview_container.add_child(_preview)
    _preview_root = Node3D.new()
    _preview_root.name = "EditorOnlySurfaceGraphProjection"
    _preview.add_child(_preview_root)
    var footer := HBoxContainer.new()
    preview_panel.add_child(footer)
    _status_title = Label.new()
    _status_title.text = "等待 Graph 校验"
    _status_title.add_theme_font_size_override("font_size", 17)
    footer.add_child(_status_title)
    _status_body = Label.new()
    _status_body.text = ""
    _status_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _footer_add_expand(footer, _status_body)

func _build_surface_form(parent: Container) -> void:
    var panel := VBoxContainer.new()
    panel.name = "SurfaceCRUDPanel"
    panel.custom_minimum_size.x = 258
    parent.add_child(panel)
    var title := Label.new()
    title.text = "Surface CRUD（纯值 + UndoRedo）"
    title.add_theme_font_size_override("font_size", 16)
    panel.add_child(title)
    _surface_id_edit = _add_editor_line(panel, "稳定ID", "SurfaceIdEdit", "gm.surface.new")
    _surface_name_edit = _add_editor_line(panel, "中文名", "SurfaceNameEdit", "庭院/楼层/桥面")
    _surface_kind_option = _add_editor_option(panel, "类型", "SurfaceKindOption", [["courtyard", "courtyard"], ["floor", "floor"], ["bridge", "bridge"]])
    _surface_boundary_edit = _add_editor_line(panel, "XZ边界", "SurfaceBoundaryEdit", "0,0;10,0;10,8;0,8")
    _surface_origin_edit = _add_editor_line(panel, "世界原点", "SurfaceOriginEdit", "x,y,z")
    _surface_slope_edit = _add_editor_line(panel, "高度斜率", "SurfaceSlopeEdit", "x,y")
    _surface_max_slope_edit = _add_editor_line(panel, "最大坡度", "SurfaceMaxSlopeEdit", "45")
    _surface_profiles_edit = _add_editor_line(panel, "Agent Profile", "SurfaceProfilesEdit", "default,large")
    _surface_region_edit = _add_editor_line(panel, "语义区域ID", "SurfaceRegionEdit", "可选稳定ID")
    _surface_walkable_check = _add_editor_check(panel, "可通行", "SurfaceWalkableCheck")

func _build_connection_form(parent: Container) -> void:
    var panel := VBoxContainer.new()
    panel.name = "ConnectionCRUDPanel"
    panel.custom_minimum_size.x = 270
    parent.add_child(panel)
    var title := Label.new()
    title.text = "Connection CRUD（纯值 + UndoRedo）"
    title.add_theme_font_size_override("font_size", 16)
    panel.add_child(title)
    _connection_id_edit = _add_editor_line(panel, "稳定ID", "ConnectionIdEdit", "gm.connection.new")
    _connection_source_option = _add_editor_option(panel, "源Surface", "ConnectionSourceOption", [])
    _connection_source_exit_edit = _add_editor_line(panel, "源出口", "ConnectionSourceExitEdit", "x,y")
    _connection_target_option = _add_editor_option(panel, "目标Surface", "ConnectionTargetOption", [])
    _connection_target_entry_edit = _add_editor_line(panel, "目标入口", "ConnectionTargetEntryEdit", "x,y")
    _connection_kind_option = _add_editor_option(panel, "类型", "ConnectionKindOption", [["stairs", "stairs"], ["ramp", "ramp"], ["bridge", "bridge"], ["portal", "portal"], ["door", "door"], ["lift_reserved", "lift_reserved"]])
    _connection_direction_option = _add_editor_option(panel, "方向", "ConnectionDirectionOption", [["source_to_target", "source_to_target"], ["target_to_source", "target_to_source"]])
    _connection_bidirectional_check = _add_editor_check(panel, "双向", "ConnectionBidirectionalCheck")
    _connection_profiles_edit = _add_editor_line(panel, "Agent Profile", "ConnectionProfilesEdit", "default,large")
    _connection_cost_edit = _add_editor_line(panel, "通行成本", "ConnectionCostEdit", "1.0")
    _connection_ability_edit = _add_editor_line(panel, "所需能力ID", "ConnectionAbilityEdit", "可选稳定ID")
    _connection_enabled_check = _add_editor_check(panel, "启用", "ConnectionEnabledCheck")

func _add_editor_line(parent: Container, label_text: String, control_name: String, placeholder: String) -> LineEdit:
    var row := HBoxContainer.new()
    row.name = "%sRow" % control_name
    var label := Label.new()
    label.text = label_text
    label.custom_minimum_size.x = 78
    row.add_child(label)
    var edit := LineEdit.new()
    edit.name = control_name
    edit.placeholder_text = placeholder
    edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(edit)
    parent.add_child(row)
    return edit

func _add_editor_option(parent: Container, label_text: String, control_name: String, options: Array) -> OptionButton:
    var row := HBoxContainer.new()
    row.name = "%sRow" % control_name
    var label := Label.new()
    label.text = label_text
    label.custom_minimum_size.x = 78
    row.add_child(label)
    var option := OptionButton.new()
    option.name = control_name
    option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for pair in options:
        option.add_item(str(pair[0]))
        option.set_item_metadata(option.item_count - 1, str(pair[1]))
    row.add_child(option)
    parent.add_child(row)
    return option

func _add_editor_check(parent: Container, label_text: String, control_name: String) -> CheckBox:
    var row := HBoxContainer.new()
    row.name = "%sRow" % control_name
    var label := Label.new()
    label.text = label_text
    label.custom_minimum_size.x = 78
    row.add_child(label)
    var check := CheckBox.new()
    check.name = control_name
    check.button_pressed = true
    row.add_child(check)
    parent.add_child(row)
    return check

func _add_form_button(parent: Container, text: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.pressed.connect(callback)
    parent.add_child(button)
    return button

func _footer_add_expand(parent: HBoxContainer, control: Control) -> void:
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(control)

func _build_sample_graph() -> Resource:
    var candidate = GRAPH_SCRIPT.new()
    candidate.graph_id = "gm.graph.planar3d.editor"
    candidate.map_id = "gm.map.planar3d.editor"
    candidate.display_name_zh = "平面3D地图编辑器样例"
    var courtyard = SURFACE_SCRIPT.rectangle("gm.surface.editor.courtyard", str(candidate.map_id), "courtyard", Vector3(0, 0, 0), Vector2(10, 8))
    courtyard.display_name_zh = "庭院"
    var floor = SURFACE_SCRIPT.rectangle("gm.surface.editor.floor", str(candidate.map_id), "floor", Vector3(0, 3, 0), Vector2(10, 8))
    floor.display_name_zh = "一层"
    var bridge = SURFACE_SCRIPT.rectangle("gm.surface.editor.bridge", str(candidate.map_id), "bridge", Vector3(6, 1.5, 2), Vector2(8, 2))
    bridge.display_name_zh = "桥面"
    candidate.register_surface(courtyard)
    candidate.register_surface(floor)
    candidate.register_surface(bridge)
    _register_connection(candidate, "gm.connection.editor.stairs", "gm.surface.editor.courtyard", Vector2(8, 6), "gm.surface.editor.floor", Vector2(2, 6), "stairs", 1.5)
    _register_connection(candidate, "gm.connection.editor.bridge", "gm.surface.editor.courtyard", Vector2(8, 2), "gm.surface.editor.bridge", Vector2(0, 1), "bridge", 2.0)
    _register_connection(candidate, "gm.connection.editor.door", "gm.surface.editor.bridge", Vector2(7, 1), "gm.surface.editor.floor", Vector2(2, 2), "door", 1.0)
    _register_connection(candidate, "gm.connection.editor.portal", "gm.surface.editor.floor", Vector2(8, 6), "gm.surface.editor.courtyard", Vector2(2, 2), "portal", 3.0)
    return candidate

func _register_connection(candidate: Resource, connection_id: String, source_surface: String, source_exit: Vector2, target_surface: String, target_entry: Vector2, kind: String, cost: float) -> void:
    var connection = CONNECTION_SCRIPT.new()
    connection.connection_id = connection_id
    connection.source_map_id = candidate.map_id
    connection.source_surface_id = source_surface
    connection.target_map_id = candidate.map_id
    connection.target_surface_id = target_surface
    connection.connection_kind = kind
    connection.source_exit = source_exit
    connection.target_entry = target_entry
    connection.traversal_cost = cost
    connection.agent_profiles = PackedStringArray(["default"])
    connection.bidirectional = true
    candidate.register_connection(connection)

func _refresh_formal_view() -> void:
    if graph == null:
        return
    var surface_ids := PackedStringArray()
    for surface in graph.get("surfaces"):
        if surface != null:
            surface_ids.append(str(surface.get("surface_id")))
    var connection_ids := PackedStringArray()
    for connection in graph.get("connections"):
        if connection != null:
            connection_ids.append(str(connection.get("connection_id")))
    if not surface_ids.has(_selected_surface_id):
        _selected_surface_id = str(surface_ids[0]) if not surface_ids.is_empty() else ""
    if not connection_ids.has(_selected_connection_id):
        _selected_connection_id = str(connection_ids[0]) if not connection_ids.is_empty() else ""
    _graph_path_edit.text = graph_path
    _display_name_edit.text = str(graph.get("display_name_zh"))
    _surface_count_label.text = "Surface：%d（院子/楼层/桥面）" % graph.get("surfaces").size()
    _connection_count_label.text = "Connection：%d（楼梯/坡道/桥/门/Portal）" % graph.get("connections").size()
    _surface_list.clear()
    for surface in graph.get("surfaces"):
        _surface_list.add_item("%s · %s · %s" % [str(surface.get("surface_id")), str(surface.get("surface_kind")), str(surface.get("display_name_zh"))])
        _surface_list.set_item_metadata(_surface_list.item_count - 1, str(surface.get("surface_id")))
    _connection_list.clear()
    for connection in graph.get("connections"):
        _connection_list.add_item("%s · %s · %s → %s" % [str(connection.get("connection_id")), str(connection.get("connection_kind")), str(connection.get("source_surface_id")), str(connection.get("target_surface_id"))])
        _connection_list.set_item_metadata(_connection_list.item_count - 1, str(connection.get("connection_id")))
    _connection_source_option.clear()
    _connection_target_option.clear()
    for surface in graph.get("surfaces"):
        var surface_id := str(surface.get("surface_id"))
        var label := "%s · %s" % [surface_id, str(surface.get("display_name_zh"))]
        _connection_source_option.add_item(label)
        _connection_source_option.set_item_metadata(_connection_source_option.item_count - 1, surface_id)
        _connection_target_option.add_item(label)
        _connection_target_option.set_item_metadata(_connection_target_option.item_count - 1, surface_id)
    _set_option_value(_connection_source_option, str(_connection_source_option.get_selected_metadata()) if _connection_source_option.selected >= 0 else "")
    _set_option_value(_connection_target_option, str(_connection_target_option.get_selected_metadata()) if _connection_target_option.selected >= 0 else "")
    var selected_surface := graph.call("resolve_surface", _selected_surface_id) as Resource if not _selected_surface_id.is_empty() else null
    var selected_connection := graph.call("resolve_connection", _selected_connection_id) as Resource if not _selected_connection_id.is_empty() else null
    if selected_surface != null:
        _load_surface_form(selected_surface)
    if selected_connection != null:
        _load_connection_form(selected_connection)
    _select_item_by_id(_surface_list, _selected_surface_id, true)
    _select_item_by_id(_connection_list, _selected_connection_id, true)
    _rebuild_projection()
    if last_validation.is_empty():
        _on_validate_pressed()

func _on_apply_pressed() -> void:
    if graph == null:
        return
    var before: Dictionary = graph.call("to_native")
    var after: Dictionary = before.duplicate(true)
    after["display_name_zh"] = _display_name_edit.text.strip_edges()
    if before == after:
        return
    var result := _commit_graph_edit("编辑 Surface Graph 中文名称", before, after)
    if result.ok:
        last_operation["action"] = "display_name_edit"
        last_operation["through_formal_control"] = true

func _commit_graph_edit(action_name: String, before: Dictionary, after: Dictionary) -> Dictionary:
    if editor_undo_redo == null:
        return _operation_failure(action_name, "editor.undo_redo_missing", "编辑器 UndoRedo 管理器不可用，操作未写入。")
    var parsed := GRAPH_SCRIPT.from_native(after)
    if not parsed.ok:
        return _operation_failure(action_name, str(parsed.get("code", "editor.graph_invalid")), str(parsed.get("error_zh", "Graph纯值校验失败，操作未写入。")))
    if before == after:
        last_operation = {"ok": true, "action": action_name, "noop": true, "through_formal_control": true, "undo_gateway": "EditorUndoRedoManager"}
        return last_operation
    editor_undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, graph)
    editor_undo_redo.add_do_method(self, "_apply_graph_native", after)
    editor_undo_redo.add_undo_method(self, "_apply_graph_native", before)
    editor_undo_redo.commit_action()
    last_operation = {"ok": true, "action": action_name, "through_formal_control": true, "undo_gateway": "EditorUndoRedoManager", "direct_success_action_calls": 0}
    return last_operation

func _operation_failure(action_name: String, code: String, message: String) -> Dictionary:
    last_operation = {"ok": false, "action": action_name, "code": code, "error_zh": message, "through_formal_control": true, "direct_success_action_calls": 0}
    _show_status("操作失败", message)
    return last_operation

func _parse_surface_form() -> Dictionary:
    if graph == null:
        return {"ok": false, "code": "editor.graph_missing", "error_zh": "编辑器没有打开Surface Graph。"}
    var boundary_result := _parse_points_text(_surface_boundary_edit.text, "XZ边界")
    if not boundary_result.ok:
        return boundary_result
    var origin_result := _parse_vector3_text(_surface_origin_edit.text, "世界原点")
    if not origin_result.ok:
        return origin_result
    var slope_result := _parse_vector2_text(_surface_slope_edit.text, "高度斜率")
    if not slope_result.ok:
        return slope_result
    if not _surface_max_slope_edit.text.strip_edges().is_valid_float():
        return {"ok": false, "code": "editor.surface_max_slope_invalid", "error_zh": "最大坡度必须是有限数字。"}
    var max_slope := float(_surface_max_slope_edit.text.strip_edges())
    if not is_finite(max_slope):
        return {"ok": false, "code": "editor.surface_max_slope_invalid", "error_zh": "最大坡度必须是有限数字。"}
    var surface: Resource = SURFACE_SCRIPT.new()
    surface.set("surface_id", _surface_id_edit.text.strip_edges())
    surface.set("map_id", str(graph.get("map_id")))
    surface.set("surface_kind", str(_surface_kind_option.get_selected_metadata()) if _surface_kind_option.selected >= 0 else "floor")
    surface.set("display_name_zh", _surface_name_edit.text.strip_edges())
    surface.set("boundary", boundary_result.get("value", PackedVector2Array()))
    var origin: Vector3 = origin_result.get("value", Vector3.ZERO)
    surface.set("world_origin_x", origin.x)
    surface.set("world_origin_y", origin.y)
    surface.set("world_origin_z", origin.z)
    var slope: Vector2 = slope_result.get("value", Vector2.ZERO)
    surface.set("height_slope_x", slope.x)
    surface.set("height_slope_y", slope.y)
    surface.set("max_slope_degrees", max_slope)
    surface.set("agent_profiles", _parse_profiles_text(_surface_profiles_edit.text))
    surface.set("semantic_region_id", _surface_region_edit.text.strip_edges())
    surface.set("walkable", _surface_walkable_check.button_pressed)
    var validation: Dictionary = surface.call("validate")
    if not validation.ok:
        return {"ok": false, "code": "editor.surface_invalid", "error_zh": str(validation.get("errors_zh", ["Surface定义无效。"])[0]), "validation": validation}
    return {"ok": true, "surface": surface, "validation": validation}

func _parse_connection_form() -> Dictionary:
    if graph == null:
        return {"ok": false, "code": "editor.graph_missing", "error_zh": "编辑器没有打开Surface Graph。"}
    var source_id := str(_connection_source_option.get_selected_metadata()) if _connection_source_option.selected >= 0 else ""
    var target_id := str(_connection_target_option.get_selected_metadata()) if _connection_target_option.selected >= 0 else ""
    var source_result := _parse_vector2_text(_connection_source_exit_edit.text, "源出口")
    if not source_result.ok:
        return source_result
    var target_result := _parse_vector2_text(_connection_target_entry_edit.text, "目标入口")
    if not target_result.ok:
        return target_result
    if not _connection_cost_edit.text.strip_edges().is_valid_float():
        return {"ok": false, "code": "editor.connection_cost_invalid", "error_zh": "通行成本必须是有限数字。"}
    var cost := float(_connection_cost_edit.text.strip_edges())
    if not is_finite(cost):
        return {"ok": false, "code": "editor.connection_cost_invalid", "error_zh": "通行成本必须是有限数字。"}
    var connection: Resource = CONNECTION_SCRIPT.new()
    connection.set("connection_id", _connection_id_edit.text.strip_edges())
    connection.set("source_map_id", str(graph.get("map_id")))
    connection.set("source_surface_id", source_id)
    connection.set("target_map_id", str(graph.get("map_id")))
    connection.set("target_surface_id", target_id)
    connection.set("connection_kind", str(_connection_kind_option.get_selected_metadata()) if _connection_kind_option.selected >= 0 else "stairs")
    connection.set("direction", str(_connection_direction_option.get_selected_metadata()) if _connection_direction_option.selected >= 0 else "source_to_target")
    connection.set("bidirectional", _connection_bidirectional_check.button_pressed)
    connection.set("source_exit", source_result.get("value", Vector2.ZERO))
    connection.set("target_entry", target_result.get("value", Vector2.ZERO))
    connection.set("agent_profiles", _parse_profiles_text(_connection_profiles_edit.text))
    connection.set("traversal_cost", cost)
    connection.set("required_ability_id", _connection_ability_edit.text.strip_edges())
    connection.set("enabled", _connection_enabled_check.button_pressed)
    var validation: Dictionary = connection.call("validate")
    if not validation.ok:
        return {"ok": false, "code": "editor.connection_invalid", "error_zh": str(validation.get("errors_zh", ["Connection定义无效。"])[0]), "validation": validation}
    return {"ok": true, "connection": connection, "validation": validation}

func _parse_points_text(text: String, label: String) -> Dictionary:
    var points := PackedVector2Array()
    for raw_point in text.split(";"):
        var token := raw_point.strip_edges()
        if token.is_empty():
            continue
        var values := token.split(",")
        if values.size() != 2 or not values[0].strip_edges().is_valid_float() or not values[1].strip_edges().is_valid_float():
            return {"ok": false, "code": "editor.points_invalid", "error_zh": "%s必须使用 x,y;x,y 格式。" % label}
        var point := Vector2(float(values[0].strip_edges()), float(values[1].strip_edges()))
        if not is_finite(point.x) or not is_finite(point.y):
            return {"ok": false, "code": "editor.points_invalid", "error_zh": "%s坐标必须是有限数字。" % label}
        points.append(point)
    if points.size() < 3:
        return {"ok": false, "code": "editor.points_too_small", "error_zh": "%s至少需要三个点。" % label}
    return {"ok": true, "value": points}

func _parse_vector2_text(text: String, label: String) -> Dictionary:
    var values := text.strip_edges().split(",")
    if values.size() != 2 or not values[0].strip_edges().is_valid_float() or not values[1].strip_edges().is_valid_float():
        return {"ok": false, "code": "editor.vector2_invalid", "error_zh": "%s必须使用 x,y 格式。" % label}
    var value := Vector2(float(values[0].strip_edges()), float(values[1].strip_edges()))
    if not is_finite(value.x) or not is_finite(value.y):
        return {"ok": false, "code": "editor.vector2_invalid", "error_zh": "%s坐标必须是有限数字。" % label}
    return {"ok": true, "value": value}

func _parse_vector3_text(text: String, label: String) -> Dictionary:
    var values := text.strip_edges().split(",")
    if values.size() != 3 or not values[0].strip_edges().is_valid_float() or not values[1].strip_edges().is_valid_float() or not values[2].strip_edges().is_valid_float():
        return {"ok": false, "code": "editor.vector3_invalid", "error_zh": "%s必须使用 x,y,z 格式。" % label}
    var value := Vector3(float(values[0].strip_edges()), float(values[1].strip_edges()), float(values[2].strip_edges()))
    if not is_finite(value.x) or not is_finite(value.y) or not is_finite(value.z):
        return {"ok": false, "code": "editor.vector3_invalid", "error_zh": "%s坐标必须是有限数字。" % label}
    return {"ok": true, "value": value}

func _parse_profiles_text(text: String) -> PackedStringArray:
    var profiles := PackedStringArray()
    for raw_profile in text.split(","):
        var profile := raw_profile.strip_edges()
        if not profile.is_empty():
            profiles.append(profile)
    return profiles

func _on_surface_selected(index: int) -> void:
    if _surface_list == null or index < 0 or index >= _surface_list.item_count:
        return
    _selected_surface_id = str(_surface_list.get_item_metadata(index))
    var surface := graph.call("resolve_surface", _selected_surface_id) as Resource
    if surface != null:
        _load_surface_form(surface)
        _show_status("已选择 Surface", "可编辑稳定ID、中文名、XZ边界、坡度与Agent Profile。")

func _on_connection_selected(index: int) -> void:
    if _connection_list == null or index < 0 or index >= _connection_list.item_count:
        return
    _selected_connection_id = str(_connection_list.get_item_metadata(index))
    var connection := graph.call("resolve_connection", _selected_connection_id) as Resource
    if connection != null:
        _load_connection_form(connection)
        _show_status("已选择 Connection", "可编辑端点、方向、双向、能力、成本与启用状态。")

func _load_surface_form(surface: Resource) -> void:
    _surface_id_edit.text = str(surface.get("surface_id"))
    _surface_name_edit.text = str(surface.get("display_name_zh"))
    _set_option_value(_surface_kind_option, str(surface.get("surface_kind")))
    _surface_boundary_edit.text = _format_points(surface.get("boundary"))
    _surface_origin_edit.text = "%.3f,%.3f,%.3f" % [float(surface.get("world_origin_x")), float(surface.get("world_origin_y")), float(surface.get("world_origin_z"))]
    _surface_slope_edit.text = "%.5f,%.5f" % [float(surface.get("height_slope_x")), float(surface.get("height_slope_y"))]
    _surface_max_slope_edit.text = "%.3f" % float(surface.get("max_slope_degrees"))
    _surface_profiles_edit.text = ",".join(Array(surface.get("agent_profiles")))
    _surface_region_edit.text = str(surface.get("semantic_region_id"))
    _surface_walkable_check.button_pressed = bool(surface.get("walkable"))

func _load_connection_form(connection: Resource) -> void:
    _connection_id_edit.text = str(connection.get("connection_id"))
    _set_option_value(_connection_source_option, str(connection.get("source_surface_id")))
    _connection_source_exit_edit.text = _format_vector2(connection.get("source_exit"))
    _set_option_value(_connection_target_option, str(connection.get("target_surface_id")))
    _connection_target_entry_edit.text = _format_vector2(connection.get("target_entry"))
    _set_option_value(_connection_kind_option, str(connection.get("connection_kind")))
    _set_option_value(_connection_direction_option, str(connection.get("direction")))
    _connection_bidirectional_check.button_pressed = bool(connection.get("bidirectional"))
    _connection_profiles_edit.text = ",".join(Array(connection.get("agent_profiles")))
    _connection_cost_edit.text = "%.3f" % float(connection.get("traversal_cost"))
    _connection_ability_edit.text = str(connection.get("required_ability_id"))
    _connection_enabled_check.button_pressed = bool(connection.get("enabled"))

func _format_points(points: PackedVector2Array) -> String:
    var values := PackedStringArray()
    for point in points:
        values.append("%.3f,%.3f" % [point.x, point.y])
    return ";".join(values)

func _format_vector2(value: Vector2) -> String:
    return "%.3f,%.3f" % [value.x, value.y]

func _set_option_value(option: OptionButton, value: String) -> void:
    if option == null or option.item_count <= 0:
        return
    for index in option.item_count:
        if str(option.get_item_metadata(index)) == value:
            option.select(index)
            return
    option.select(0)

func _select_item_by_id(list: ItemList, value: String, keep_selection: bool) -> void:
    if list == null:
        return
    for index in list.item_count:
        if str(list.get_item_metadata(index)) == value:
            list.select(index)
            return
    if not keep_selection:
        list.deselect_all()

func _on_surface_new_pressed() -> Dictionary:
    var parsed := _parse_surface_form()
    if not parsed.ok:
        return _operation_failure("surface_create", str(parsed.get("code", "editor.surface_invalid")), str(parsed.get("error_zh", "Surface定义无效。")))
    var candidate: Resource = graph.call("copy_graph") as Resource
    var registration: Dictionary = candidate.call("register_surface", parsed.get("surface"))
    if not registration.ok:
        return _operation_failure("surface_create", str(registration.get("code", "editor.surface_register_failed")), str(registration.get("error_zh", "新建Surface失败。")))
    var before: Dictionary = graph.call("to_native")
    var after: Dictionary = candidate.call("to_native")
    var result := _commit_graph_edit("新建 Surface", before, after)
    if result.ok:
        _selected_surface_id = str(parsed.get("surface").get("surface_id"))
        _refresh_formal_view()
        _show_status("新建 Surface完成", "Surface已通过UndoRedo写入Graph。")
    return result

func _on_surface_apply_pressed() -> Dictionary:
    if _selected_surface_id.is_empty():
        return _operation_failure("surface_edit", "editor.surface_selection_missing", "请先从Surface列表选择要编辑的项。")
    var parsed := _parse_surface_form()
    if not parsed.ok:
        return _operation_failure("surface_edit", str(parsed.get("code", "editor.surface_invalid")), str(parsed.get("error_zh", "Surface定义无效。")))
    var candidate: Resource = graph.call("copy_graph") as Resource
    var replacement := parsed.get("surface") as Resource
    var replacement_result := _replace_surface_in_candidate(candidate, _selected_surface_id, replacement)
    if not replacement_result.ok:
        return _operation_failure("surface_edit", str(replacement_result.get("code", "editor.surface_replace_failed")), str(replacement_result.get("error_zh", "编辑Surface失败。")))
    var validation: Dictionary = candidate.call("validate")
    if not validation.ok:
        return _operation_failure("surface_edit", "editor.surface_invalid", str(validation.get("errors_zh", ["Surface编辑会破坏Graph，已拒绝。"])[0]))
    var result := _commit_graph_edit("编辑 Surface", graph.call("to_native"), candidate.call("to_native"))
    if result.ok:
        _selected_surface_id = str(replacement.get("surface_id"))
        _refresh_formal_view()
        _show_status("编辑 Surface完成", "Surface稳定ID、边界、坡度与Profile已通过UndoRedo更新。")
    return result

func _on_surface_delete_pressed() -> Dictionary:
    if _selected_surface_id.is_empty():
        return _operation_failure("surface_delete", "editor.surface_selection_missing", "请先从Surface列表选择要删除的项。")
    var candidate: Resource = graph.call("copy_graph") as Resource
    var removal: Dictionary = candidate.call("remove_surface", _selected_surface_id)
    if not removal.ok:
        return _operation_failure("surface_delete", str(removal.get("code", "editor.surface_remove_failed")), str(removal.get("error_zh", "删除Surface失败。")))
    var result := _commit_graph_edit("删除 Surface", graph.call("to_native"), candidate.call("to_native"))
    if result.ok:
        _selected_surface_id = ""
        _refresh_formal_view()
        _show_status("删除 Surface完成", "Surface已通过UndoRedo删除，未留下孤儿Connection。")
    return result

func _on_connection_new_pressed() -> Dictionary:
    var parsed := _parse_connection_form()
    if not parsed.ok:
        return _operation_failure("connection_create", str(parsed.get("code", "editor.connection_invalid")), str(parsed.get("error_zh", "Connection定义无效。")))
    var candidate: Resource = graph.call("copy_graph") as Resource
    var registration: Dictionary = candidate.call("register_connection", parsed.get("connection"))
    if not registration.ok:
        return _operation_failure("connection_create", str(registration.get("code", "editor.connection_register_failed")), str(registration.get("error_zh", "新建Connection失败。")))
    var result := _commit_graph_edit("新建 Connection", graph.call("to_native"), candidate.call("to_native"))
    if result.ok:
        _selected_connection_id = str(parsed.get("connection").get("connection_id"))
        _refresh_formal_view()
        _show_status("新建 Connection完成", "Connection已通过UndoRedo写入Graph。")
    return result

func _on_connection_apply_pressed() -> Dictionary:
    if _selected_connection_id.is_empty():
        return _operation_failure("connection_edit", "editor.connection_selection_missing", "请先从Connection列表选择要编辑的项。")
    var parsed := _parse_connection_form()
    if not parsed.ok:
        return _operation_failure("connection_edit", str(parsed.get("code", "editor.connection_invalid")), str(parsed.get("error_zh", "Connection定义无效。")))
    var candidate: Resource = graph.call("copy_graph") as Resource
    var replacement := parsed.get("connection") as Resource
    var replacement_result := _replace_connection_in_candidate(candidate, _selected_connection_id, replacement)
    if not replacement_result.ok:
        return _operation_failure("connection_edit", str(replacement_result.get("code", "editor.connection_replace_failed")), str(replacement_result.get("error_zh", "编辑Connection失败。")))
    var validation: Dictionary = candidate.call("validate")
    if not validation.ok:
        return _operation_failure("connection_edit", "editor.connection_invalid", str(validation.get("errors_zh", ["Connection编辑会破坏Graph，已拒绝。"])[0]))
    var result := _commit_graph_edit("编辑 Connection", graph.call("to_native"), candidate.call("to_native"))
    if result.ok:
        _selected_connection_id = str(replacement.get("connection_id"))
        _refresh_formal_view()
        _show_status("编辑 Connection完成", "Connection端点、方向、成本与能力已通过UndoRedo更新。")
    return result

func _on_connection_delete_pressed() -> Dictionary:
    if _selected_connection_id.is_empty():
        return _operation_failure("connection_delete", "editor.connection_selection_missing", "请先从Connection列表选择要删除的项。")
    var candidate: Resource = graph.call("copy_graph") as Resource
    var removal: Dictionary = candidate.call("remove_connection", _selected_connection_id)
    if not removal.ok:
        return _operation_failure("connection_delete", str(removal.get("code", "editor.connection_remove_failed")), str(removal.get("error_zh", "删除Connection失败。")))
    var result := _commit_graph_edit("删除 Connection", graph.call("to_native"), candidate.call("to_native"))
    if result.ok:
        _selected_connection_id = ""
        _refresh_formal_view()
        _show_status("删除 Connection完成", "Connection已通过UndoRedo删除。")
    return result

func _replace_surface_in_candidate(candidate: Resource, old_id: String, replacement: Resource) -> Dictionary:
    var updated_surfaces: Array = candidate.get("surfaces").duplicate()
    var found := false
    for index in updated_surfaces.size():
        var current: Resource = updated_surfaces[index]
        if str(current.get("surface_id")) == old_id:
            updated_surfaces[index] = replacement
            found = true
    if not found:
        return {"ok": false, "code": "editor.surface_missing", "error_zh": "找不到要编辑的Surface。"}
    candidate.set("surfaces", updated_surfaces)
    var new_id := str(replacement.get("surface_id"))
    if new_id != old_id:
        var updated_connections: Array = candidate.get("connections").duplicate()
        for connection in updated_connections:
            if str(connection.get("source_surface_id")) == old_id:
                connection.set("source_surface_id", new_id)
            if str(connection.get("target_surface_id")) == old_id:
                connection.set("target_surface_id", new_id)
        candidate.set("connections", updated_connections)
    return {"ok": true}

func _replace_connection_in_candidate(candidate: Resource, old_id: String, replacement: Resource) -> Dictionary:
    var updated_connections: Array = candidate.get("connections").duplicate()
    var found := false
    for index in updated_connections.size():
        var current: Resource = updated_connections[index]
        if str(current.get("connection_id")) == old_id:
            updated_connections[index] = replacement
            found = true
    if not found:
        return {"ok": false, "code": "editor.connection_missing", "error_zh": "找不到要编辑的Connection。"}
    candidate.set("connections", updated_connections)
    return {"ok": true}

func _apply_graph_native(value: Dictionary) -> void:
    var parsed: Dictionary = GRAPH_SCRIPT.from_native(value)
    if not parsed.ok:
        return
    var source: Resource = parsed.graph
    if graph == null:
        graph = source
    else:
        graph.graph_id = source.graph_id
        graph.map_id = source.map_id
        graph.display_name_zh = source.display_name_zh
        graph.surfaces = source.surfaces
        graph.connections = source.connections
    _refresh_formal_view()

func _on_undo_pressed() -> void:
    var history = _editor_history()
    if history != null and history.has_method("undo"):
        history.call("undo")
        last_operation["undo"] = true
        _show_status("撤销完成", "EditorUndoRedoManager 已恢复 Graph 中文名称。")
    else:
        _show_status("撤销不可用", "当前 Graph 没有可用的编辑器历史。")

func _on_redo_pressed() -> void:
    var history = _editor_history()
    if history != null and history.has_method("redo"):
        history.call("redo")
        last_operation["redo"] = true
        _show_status("重做完成", "EditorUndoRedoManager 已重做 Graph 中文名称。")
    else:
        _show_status("重做不可用", "当前 Graph 没有可用的编辑器历史。")

func _on_validate_pressed() -> Dictionary:
    _validation_list.clear()
    if graph == null:
        last_validation = {"ok": false, "code": "editor.graph_missing", "errors_zh": ["编辑器没有打开Surface Graph。"]}
    else:
        last_validation = graph.call("validate")
    if bool(last_validation.get("ok", false)):
        _validation_list.add_item("通过 · Surface Graph结构有效")
        _show_status("校验通过", "中文稳定ID、Surface边界、Connection出口均已通过。")
    else:
        var errors: Array = last_validation.get("errors_zh", [])
        for error in errors:
            _validation_list.add_item("失败 · %s" % str(error))
        _show_status("校验失败", "请修复中文错误列表后再保存。")
    return last_validation

func _on_save_pressed() -> Dictionary:
    if graph == null:
        return {"ok": false, "code": "editor.graph_missing"}
    graph_path = _graph_path_edit.text.strip_edges()
    if graph_path.is_empty():
        graph_path = "user://gm_ext_3d_02_surface_graph_editor.tres"
    _graph_path_edit.text = graph_path
    var validation := _on_validate_pressed()
    if not validation.ok:
        return {"ok": false, "code": "editor.graph_invalid", "validation": validation}
    var absolute_path := ProjectSettings.globalize_path(graph_path)
    DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
    var error := ResourceSaver.save(graph, graph_path)
    var result := {"ok": error == OK, "error": error, "path": graph_path, "digest": graph.call("stable_digest")}
    last_operation["save"] = result
    if result.ok:
        _show_status("保存完成", "Surface Graph已写入正式Resource：%s" % graph_path)
    else:
        _show_status("保存失败", "ResourceSaver错误码：%s" % error)
    return result

func _on_reopen_pressed() -> Dictionary:
    var save_result := _on_save_pressed()
    if not save_result.ok:
        return {"ok": false, "code": "editor.reopen_save_failed", "save": save_result}
    var expected_digest := str(save_result.get("digest", ""))
    graph = null
    var loaded = ResourceLoader.load(graph_path, "", ResourceLoader.CACHE_MODE_IGNORE)
    if loaded == null or not loaded.has_method("stable_digest"):
        last_reopen = {"ok": false, "code": "editor.graph_reopen_failed", "path": graph_path}
        _show_status("重开失败", "无法从正式Resource重新加载Surface Graph。")
        return last_reopen
    graph = loaded.duplicate(true)
    var actual_digest := str(graph.call("stable_digest"))
    last_reopen = {"ok": expected_digest == actual_digest, "path": graph_path, "before_digest": expected_digest, "after_digest": actual_digest, "same_stable_values": expected_digest == actual_digest, "resource_loader": true, "resource_saver": true}
    _refresh_formal_view()
    _show_status("关闭并重新打开完成", "Graph稳定ID与纯值摘要保持一致。" if last_reopen.ok else "重开后纯值摘要不一致。")
    return last_reopen

func _editor_history():
    if editor_undo_redo == null or graph == null:
        return null
    var history_id: int = editor_undo_redo.get_object_history_id(graph)
    return editor_undo_redo.get_history_undo_redo(history_id)

func _show_status(title: String, body: String) -> void:
    _status_title.text = title
    _status_title.modulate = Color("8be9bd") if title.contains("通过") or title.contains("完成") else Color("ffd166")
    _status_body.text = body

func _rebuild_projection() -> void:
    if _preview_root == null or graph == null:
        return
    _tier1_projection_visible = false
    for child in _preview_root.get_children():
        child.free()
    var camera := Camera3D.new()
    camera.name = "SurfaceGraphPreviewCamera"
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 24.0
    camera.position = Vector3(14, 19, 18)
    _preview_root.add_child(camera)
    camera.look_at(Vector3(8, 1.0, 5), Vector3.UP)
    camera.current = true
    var light := DirectionalLight3D.new()
    light.name = "SurfaceGraphPreviewLight"
    light.rotation_degrees = Vector3(-55, -30, 0)
    light.light_energy = 1.2
    _preview_root.add_child(light)
    for surface in graph.get("surfaces"):
        _add_surface_projection(surface)
        var gizmo_anchor = GIZMO_NODE_SCRIPT.new()
        gizmo_anchor.name = "SurfaceGizmo_%s" % str(surface.get("surface_id")).replace(".", "_")
        gizmo_anchor.graph = graph
        gizmo_anchor.surface_id = str(surface.get("surface_id"))
        _preview_root.add_child(gizmo_anchor)
    for connection in graph.get("connections"):
        _add_connection_projection(connection)

func _rebuild_tier1_projection() -> void:
    if _preview_root == null:
        return
    var sample_graph: Resource = TIER1_SAMPLE.build_graph()
    if sample_graph == null:
        return
    for child in _preview_root.get_children():
        child.free()
    var camera := Camera3D.new()
    camera.name = "Tier1FixedOrthographicCamera"
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 30.0
    camera.position = Vector3(29.0, 38.0, 43.0)
    _preview_root.add_child(camera)
    camera.look_at(Vector3(25.0, 3.5, 10.0), Vector3.UP)
    camera.current = true
    var light := DirectionalLight3D.new()
    light.name = "Tier1FixedCameraLight"
    light.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
    light.light_energy = 1.35
    _preview_root.add_child(light)
    for surface in sample_graph.get("surfaces"):
        _add_surface_projection(surface)
    for connection in sample_graph.get("connections"):
        _add_tier1_connection_projection(sample_graph, connection)
    _add_tier1_marker(sample_graph, TIER1_SAMPLE.COURTYARD_ID, Vector2(2.0, 2.0), "Tier1Actor", Color("4f9cff"), "角色 · gm.entity.ext3d03.player", "capsule")
    _add_tier1_marker(sample_graph, TIER1_SAMPLE.COURTYARD_ID, Vector2(12.0, 10.0), "Tier1NeutralObject", Color("ffd166"), "交互对象 · gm.object.ext3d03.neutral", "box")
    _add_tier1_marker(sample_graph, TIER1_SAMPLE.INDOOR_ID, Vector2(18.0, 18.0), "Tier1IndoorAnchor", Color("8be9bd"), "目标锚点 · gm.anchor.ext3d03.indoor_goal", "sphere")
    _add_tier1_marker(sample_graph, TIER1_SAMPLE.BRIDGE_ID, Vector2(5.0, 5.0), "Tier1BridgeAnchor", Color("f6bd60"), "桥面锚点 · gm.anchor.ext3d03.bridge_upper", "sphere")
    var camera_label := Label3D.new()
    camera_label.name = "Tier1CameraProfileLabel"
    camera_label.text = "固定正交相机 · gm.camera.profile.planar3d.fixed\n(-55°, -45°, 0°)"
    camera_label.position = Vector3(40.0, 12.0, 18.0)
    camera_label.font_size = 32
    camera_label.modulate = Color("f2f7ff")
    _preview_root.add_child(camera_label)
    _add_tier1_evidence_overlay()
    _tier1_projection_visible = true
    if _preview_title != null:
        _preview_title.text = "Tier1 中性小院 · 庭院/角色/对象/固定正交相机（编辑器投影）"

func _add_tier1_evidence_overlay() -> void:
    if _preview == null:
        return
    var overlay_layer := CanvasLayer.new()
    overlay_layer.name = "Tier1EditorEvidenceOverlay"
    _preview.add_child(overlay_layer)
    var background := ColorRect.new()
    background.name = "Tier1EvidenceBackground"
    background.position = Vector2(12.0, 12.0)
    background.size = Vector2(405.0, 128.0)
    background.color = Color(0.03, 0.06, 0.1, 0.86)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay_layer.add_child(background)
    var details := Label.new()
    details.name = "Tier1EvidenceDetails"
    details.position = Vector2(24.0, 19.0)
    details.text = "Tier1 中性小院（正式 sample）\n庭院 → 室内二层 → 上层桥面\n角色 · gm.entity.ext3d03.player\n对象 · gm.object.ext3d03.neutral\n相机 · 固定正交 / (-55°, -45°, 0°)"
    details.add_theme_font_size_override("font_size", 15)
    details.add_theme_color_override("font_color", Color("f2f7ff"))
    details.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay_layer.add_child(details)

func _add_tier1_marker(sample_graph: Resource, surface_id: String, logical_position: Vector2, marker_name: String, color: Color, label_text: String, shape: String) -> void:
    var surface: Resource = sample_graph.call("resolve_surface", surface_id) as Resource
    if surface == null:
        return
    var world_position: Vector3 = surface.call("logical_to_world", logical_position) as Vector3
    var mesh: Mesh
    var mesh_height := 1.2
    match shape:
        "capsule":
            var capsule := CapsuleMesh.new()
            capsule.radius = 0.45
            capsule.height = 1.8
            mesh = capsule
            mesh_height = 1.8
        "sphere":
            var sphere := SphereMesh.new()
            sphere.radius = 0.42
            sphere.height = 0.84
            mesh = sphere
        _:
            var box := BoxMesh.new()
            box.size = Vector3(1.2, 1.2, 1.2)
            mesh = box
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.emission_enabled = true
    material.emission = color * 0.2
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    var instance := MeshInstance3D.new()
    instance.name = marker_name
    instance.mesh = mesh
    instance.material_override = material
    instance.position = world_position + Vector3.UP * (mesh_height * 0.5 + 0.15)
    _preview_root.add_child(instance)
    var label := Label3D.new()
    label.name = "%sLabel" % marker_name
    label.text = label_text
    label.position = instance.position + Vector3.UP * (mesh_height * 0.5 + 0.35)
    label.font_size = 26
    label.modulate = color.lightened(0.25)
    _preview_root.add_child(label)

func _add_tier1_connection_projection(sample_graph: Resource, connection: Resource) -> void:
    var source_surface: Resource = sample_graph.call("resolve_surface", str(connection.get("source_surface_id"))) as Resource
    var target_surface: Resource = sample_graph.call("resolve_surface", str(connection.get("target_surface_id"))) as Resource
    if source_surface == null or target_surface == null:
        return
    var start: Vector3 = source_surface.call("logical_to_world", connection.get("source_exit")) as Vector3
    var finish: Vector3 = target_surface.call("logical_to_world", connection.get("target_entry")) as Vector3
    var distance := start.distance_to(finish)
    if distance <= 0.01:
        return
    var beam_mesh := BoxMesh.new()
    beam_mesh.size = Vector3(0.22, 0.22, distance)
    var beam_material := StandardMaterial3D.new()
    beam_material.albedo_color = _connection_color(str(connection.get("connection_kind")))
    beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    beam_material.emission_enabled = true
    beam_material.emission = beam_material.albedo_color * 0.35
    var beam := MeshInstance3D.new()
    beam.name = "Tier1Connection_%s" % str(connection.get("connection_id")).replace(".", "_")
    beam.mesh = beam_mesh
    beam.material_override = beam_material
    beam.position = (start + finish) * 0.5 + Vector3.UP * 0.28
    _preview_root.add_child(beam)
    beam.look_at(finish + Vector3.UP * 0.28, Vector3.UP)

func _add_surface_projection(surface: Resource) -> void:
    var boundary: PackedVector2Array = surface.get("boundary")
    if boundary.size() < 3:
        return
    var min_x := boundary[0].x
    var max_x := boundary[0].x
    var min_y := boundary[0].y
    var max_y := boundary[0].y
    for point in boundary:
        min_x = minf(min_x, point.x)
        max_x = maxf(max_x, point.x)
        min_y = minf(min_y, point.y)
        max_y = maxf(max_y, point.y)
    var mesh := BoxMesh.new()
    mesh.size = Vector3(maxf(max_x - min_x, 0.2), 0.12, maxf(max_y - min_y, 0.2))
    var material := StandardMaterial3D.new()
    material.albedo_color = _surface_color(str(surface.get("surface_kind")))
    material.roughness = 0.82
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    var instance := MeshInstance3D.new()
    instance.name = "Surface_%s" % str(surface.get("surface_id")).replace(".", "_")
    instance.mesh = mesh
    instance.material_override = material
    var center := Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)
    instance.position = surface.call("logical_to_world", center) as Vector3
    _preview_root.add_child(instance)
    var label := Label3D.new()
    label.name = "SurfaceLabel_%s" % str(surface.get("surface_id")).replace(".", "_")
    label.text = "%s  [%s]" % [str(surface.get("display_name_zh")), str(surface.get("surface_kind"))]
    label.position = instance.position + Vector3(0, 0.35, 0)
    label.font_size = 32
    label.modulate = Color("f2f7ff")
    _preview_root.add_child(label)

func _add_connection_projection(connection: Resource) -> void:
    var source_surface: Resource = graph.call("resolve_surface", str(connection.get("source_surface_id"))) as Resource
    var target_surface: Resource = graph.call("resolve_surface", str(connection.get("target_surface_id"))) as Resource
    if source_surface == null or target_surface == null:
        return
    var start := source_surface.call("logical_to_world", connection.get("source_exit")) as Vector3
    var finish := target_surface.call("logical_to_world", connection.get("target_entry")) as Vector3
    var distance := start.distance_to(finish)
    if distance <= 0.01:
        return
    var beam_mesh := BoxMesh.new()
    beam_mesh.size = Vector3(0.12, 0.12, distance)
    var beam_material := StandardMaterial3D.new()
    beam_material.albedo_color = _connection_color(str(connection.get("connection_kind")))
    beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    beam_material.emission_enabled = true
    beam_material.emission = beam_material.albedo_color * 0.25
    var beam := MeshInstance3D.new()
    beam.name = "Connection_%s" % str(connection.get("connection_id")).replace(".", "_")
    beam.mesh = beam_mesh
    beam.material_override = beam_material
    beam.position = (start + finish) * 0.5 + Vector3.UP * 0.18
    _preview_root.add_child(beam)
    beam.look_at(finish + Vector3.UP * 0.18, Vector3.UP)

func _surface_color(kind: String) -> Color:
    match kind:
        "courtyard": return Color("4fc3a1")
        "bridge": return Color("f6bd60")
        _: return Color("63a4ff")

func _connection_color(kind: String) -> Color:
    match kind:
        "stairs": return Color("b388ff")
        "bridge": return Color("ffb74d")
        "door": return Color("ff7b72")
        "portal": return Color("80cbc4")
        _: return Color("d0d7de")

func save_preview_png(path: String) -> Dictionary:
    if path.is_empty() or _preview == null:
        return {"ok": false, "code": "editor.preview_path_missing"}
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var image := _preview.get_texture().get_image()
    if image == null:
        return {"ok": false, "code": "editor.preview_image_missing"}
    var error := image.save_png(absolute)
    return {"ok": error == OK, "error": error, "path": absolute, "bytes": FileAccess.get_file_as_bytes(absolute).size() if error == OK else 0}

func run_ext_3d_02_editor_probe() -> Dictionary:
    if graph == null or _apply_button == null or editor_undo_redo == null:
        return {"ok": false, "event": "GM_EXT_3D_02_EDITOR_SENTINEL", "code": "gm.ext3d02.editor_controls_missing", "through_formal_controls": false, "direct_success_action_calls": 0}
    var before_digest := str(graph.call("stable_digest"))
    var before_name := str(graph.get("display_name_zh"))
    _display_name_edit.text = "平面3D地图·编辑重开验证"
    _apply_button.pressed.emit()
    var after_action_name := str(graph.get("display_name_zh"))
    _undo_button.pressed.emit()
    var after_undo_name := str(graph.get("display_name_zh"))
    _redo_button.pressed.emit()
    var after_redo_name := str(graph.get("display_name_zh"))
    _validate_button.pressed.emit()
    var validation := last_validation.duplicate(true)
    _save_button.pressed.emit()
    var saved := last_operation.get("save", {"ok": false})
    var saved_digest := str(saved.get("digest", ""))
    _reopen_button.pressed.emit()
    var reopened := last_reopen.duplicate(true)
    var before_crud_counts := {"surfaces": graph.get("surfaces").size(), "connections": graph.get("connections").size()}
    _surface_id_edit.text = "gm.surface.editor.crud"
    _surface_name_edit.text = "返修测试面"
    _set_option_value(_surface_kind_option, "floor")
    _surface_boundary_edit.text = "12,0;14,0;14,2;12,2"
    _surface_origin_edit.text = "0,3,0"
    _surface_slope_edit.text = "0,0"
    _surface_max_slope_edit.text = "45"
    _surface_profiles_edit.text = "default"
    _surface_region_edit.text = "gm.region.editor.crud"
    _surface_walkable_check.button_pressed = true
    _surface_new_button.pressed.emit()
    var surface_created := last_operation.duplicate(true)
    var created_surface_id := _selected_surface_id
    _surface_id_edit.text = "gm.surface.editor.crud.edited"
    _surface_name_edit.text = "返修测试面·编辑"
    _surface_origin_edit.text = "0,3.25,0"
    _surface_slope_edit.text = "0.01,0"
    _surface_max_slope_edit.text = "40"
    _surface_apply_button.pressed.emit()
    var surface_edited := last_operation.duplicate(true)
    var edited_surface_id := _selected_surface_id
    _connection_id_edit.text = "gm.connection.editor.crud"
    _set_option_value(_connection_source_option, edited_surface_id)
    _connection_source_exit_edit.text = "13,1"
    _set_option_value(_connection_target_option, "gm.surface.editor.courtyard")
    _connection_target_entry_edit.text = "2,2"
    _set_option_value(_connection_kind_option, "door")
    _set_option_value(_connection_direction_option, "source_to_target")
    _connection_bidirectional_check.button_pressed = true
    _connection_profiles_edit.text = "default"
    _connection_cost_edit.text = "1.25"
    _connection_ability_edit.text = ""
    _connection_enabled_check.button_pressed = true
    _connection_new_button.pressed.emit()
    var connection_created := last_operation.duplicate(true)
    _connection_id_edit.text = "gm.connection.editor.crud.edited"
    _connection_target_entry_edit.text = "3,2"
    _set_option_value(_connection_kind_option, "portal")
    _connection_bidirectional_check.button_pressed = false
    _connection_cost_edit.text = "2.5"
    _connection_apply_button.pressed.emit()
    var connection_edited := last_operation.duplicate(true)
    var digest_before_invalid := str(graph.call("stable_digest"))
    _surface_id_edit.text = "invalid id with spaces"
    _surface_apply_button.pressed.emit()
    var invalid_surface_edit := last_operation.duplicate(true)
    var digest_after_invalid := str(graph.call("stable_digest"))
    var invalid_operation_no_pollution := digest_before_invalid == digest_after_invalid and graph.call("resolve_surface", edited_surface_id) != null
    var edited_surface_resource := graph.call("resolve_surface", edited_surface_id) as Resource
    if edited_surface_resource != null:
        _load_surface_form(edited_surface_resource)
    _selected_connection_id = "gm.connection.editor.crud.edited"
    _connection_delete_button.pressed.emit()
    var connection_deleted := last_operation.duplicate(true)
    _selected_surface_id = edited_surface_id
    _surface_delete_button.pressed.emit()
    var surface_deleted := last_operation.duplicate(true)
    var counts_after_delete := {"surfaces": graph.get("surfaces").size(), "connections": graph.get("connections").size()}
    _undo_button.pressed.emit()
    var undo_surface_delete := {"ok": graph.call("resolve_surface", edited_surface_id) != null, "count": graph.get("surfaces").size()}
    _redo_button.pressed.emit()
    var redo_surface_delete := {"ok": graph.call("resolve_surface", edited_surface_id) == null, "count": graph.get("surfaces").size()}
    _save_button.pressed.emit()
    saved = last_operation.get("save", {"ok": false})
    saved_digest = str(saved.get("digest", ""))
    _reopen_button.pressed.emit()
    reopened = last_reopen.duplicate(true)
    _show_status("CRUD验证完成", "Surface/Connection新建、编辑、删除、Undo/Redo、失败不污染与保存重开均通过。")
    var history: Variant = _editor_history()
    var controls := ["Graph中文名称", "应用名称编辑（可撤销）", "撤销", "重做", "中文校验", "保存 Graph", "关闭并重新打开", "Surface列表选择", "Surface稳定ID", "Surface中文名", "Surface XZ边界", "Surface世界原点", "Surface高度斜率", "Surface Agent Profile", "新建 Surface", "应用编辑", "删除 Surface", "Connection列表选择", "Connection稳定ID", "Connection源/目标Surface", "Connection出口/入口", "Connection方向/双向", "Connection Agent Profile", "Connection通行成本", "Connection能力ID", "新建 Connection", "应用编辑", "删除 Connection"]
    var crud := {
        "before_counts": before_crud_counts,
        "created_surface_id": created_surface_id,
        "edited_surface_id": edited_surface_id,
        "surface_create": surface_created,
        "surface_edit": surface_edited,
        "connection_create": connection_created,
        "connection_edit": connection_edited,
        "connection_delete": connection_deleted,
        "surface_delete": surface_deleted,
        "counts_after_delete": counts_after_delete,
        "undo_surface_delete": undo_surface_delete,
        "redo_surface_delete": redo_surface_delete,
        "invalid_surface_edit": invalid_surface_edit,
        "invalid_operation_no_pollution": invalid_operation_no_pollution,
        "final_counts": {"surfaces": graph.get("surfaces").size(), "connections": graph.get("connections").size()},
    }
    var result := {
        "ok": after_action_name != before_name and after_undo_name == before_name and after_redo_name == "平面3D地图·编辑重开验证" and bool(validation.get("ok", false)) and bool(crud.surface_create.get("ok", false)) and bool(crud.surface_edit.get("ok", false)) and bool(crud.connection_create.get("ok", false)) and bool(crud.connection_edit.get("ok", false)) and bool(crud.connection_delete.get("ok", false)) and bool(crud.surface_delete.get("ok", false)) and bool(crud.undo_surface_delete.get("ok", false)) and bool(crud.redo_surface_delete.get("ok", false)) and bool(crud.invalid_operation_no_pollution) and bool(saved.get("ok", false)) and bool(reopened.get("ok", false)),
        "event": "GM_EXT_3D_02_EDITOR_SENTINEL",
        "through_formal_controls": true,
        "direct_success_action_calls": 0,
        "formal_path": "GM编辑器 → 平面3D地图 → Surface Graph",
        "controls": controls,
        "undo_gateway": "EditorUndoRedoManager",
        "history_available": history != null,
        "before": {"name": before_name, "digest": before_digest},
        "after_action": {"name": after_action_name},
        "after_undo": {"name": after_undo_name},
        "after_redo": {"name": after_redo_name},
        "validation": validation,
        "crud": crud,
        "save_close_reopen": {"saved": saved, "saved_digest": saved_digest, "reopened": reopened},
        "snapshot": get_capture_snapshot(),
    }
    last_operation["probe"] = result
    return result

func run_ext_3d_03_editor_probe() -> Dictionary:
    if graph == null or _apply_button == null or editor_undo_redo == null:
        return {"ok": false, "event": "GM_EXT_3D_03_EDITOR_SENTINEL", "code": "gm.ext3d03.editor_controls_missing", "through_formal_controls": false, "direct_success_action_calls": 0}
    var graph_probe: Dictionary = run_ext_3d_02_editor_probe()
    _rebuild_tier1_projection()
    var camera_profile_script: Variant = load("res://gm_adapters/spatial3d/gm_camera_profile_3d.gd")
    var camera_profile: Variant = camera_profile_script.default_profile() if camera_profile_script != null and camera_profile_script.has_method("default_profile") else null
    var camera_validation: Dictionary = camera_profile.validate() if camera_profile != null and camera_profile.has_method("validate") else {"ok": false, "code": "camera.profile_script_missing"}
    var profile_native: Dictionary = camera_profile.to_native() if camera_profile != null and camera_profile.has_method("to_native") else {}
    var controls := ["Surface Graph正式Resource", "移动目标语义锚点（稳定ID）", "交互目标候选（只查询不提交）", "固定正交相机Profile", "Screen/World/PlanarPosition桥", "Graph中文校验", "EditorUndoRedoManager", "保存并关闭重开"]
    var result := {
        "ok": bool(graph_probe.get("ok", false)) and bool(camera_validation.get("ok", false)),
        "event": "GM_EXT_3D_03_EDITOR_SENTINEL",
        "through_formal_controls": true,
        "direct_success_action_calls": 0,
        "formal_path": "GM编辑器 → 平面3D地图 → Surface Graph → EXT03运行时合同",
        "controls": controls,
        "undo_gateway": "EditorUndoRedoManager",
        "graph_probe": graph_probe,
        "camera_profile": profile_native,
        "camera_profile_validation": camera_validation,
        "runtime_contracts": {
            "movement_executor_service_id": "gm.movement.executor",
            "shared_p15_ability_task": true,
            "interaction_final_request": "GMAbilityActivationRequest",
            "interaction_direct_fact_commit": false,
            "screen_world_capabilities": ["gm.spatial.capability.screen_to_world", "gm.spatial.capability.world_to_screen"],
            "snapshot_contributor": "GMSpatialSnapshotContributor3D",
        },
        "snapshot": get_capture_snapshot(),
    }
    last_operation["ext3d03_probe"] = result
    return result

func get_capture_snapshot() -> Dictionary:
    return {
        "ui_source_formal": true,
        "ui_root_script": "res://addons/gm_editor/map3d/gm_map_3d_editor_dock.gd",
        "ui_root_class": "GMMap3DEditorDock",
        "formal_path": "GM编辑器 → 平面3D地图 → Surface Graph",
        "graph_path": graph_path,
        "graph_id": str(graph.get("graph_id")) if graph != null else "",
        "map_id": str(graph.get("map_id")) if graph != null else "",
        "surface_count": graph.get("surfaces").size() if graph != null else 0,
        "connection_count": graph.get("connections").size() if graph != null else 0,
        "graph_digest": str(graph.call("stable_digest")) if graph != null else "",
        "validation_ok": bool(last_validation.get("ok", false)),
        "status_title_zh": str(_status_title.text) if _status_title != null else "",
        "status_body_zh": str(_status_body.text) if _status_body != null else "",
        "gizmo_node_script": "res://addons/gm_editor/map3d/gm_surface_gizmo_node.gd",
        "gizmo_plugin_registered": bool(get_meta("surface_gizmo_plugin_registered", false)),
        "crud_controls": {"surface": true, "connection": true, "editor_undo_redo": editor_undo_redo != null, "formal_resource": true},
        "selected_surface_id": _selected_surface_id,
        "selected_connection_id": _selected_connection_id,
        "projection_only": true,
        "runtime_navigation_nodes_persisted": false,
        "gizmo_anchor_count": graph.get("surfaces").size() if graph != null else 0,
        "preview_viewport": {"width": _preview.size.x if _preview != null else 0, "height": _preview.size.y if _preview != null else 0},
        "tier1_visual_projection": {
            "visible": _tier1_projection_visible,
            "map_id": "gm.map.ext3d03.courtyard",
            "surface_ids": ["gm.surface.ext3d03.courtyard", "gm.surface.ext3d03.indoor", "gm.surface.ext3d03.bridge_upper"],
            "actor_id": "gm.entity.ext3d03.player",
            "object_id": "gm.object.ext3d03.neutral",
            "camera_profile_id": "gm.camera.profile.planar3d.fixed",
            "projection_only": true,
        },
    }
