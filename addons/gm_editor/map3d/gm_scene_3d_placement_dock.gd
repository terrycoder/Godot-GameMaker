class_name GMScene3DPlacementDock
extends PanelContainer

## Formal Chinese SceneRecipe3D placement tool.  It is attached by the
## existing GMMap3DEditorDock/plugin lifecycle and shares its UndoRedo gateway;
## all saved authoring values remain stable-ID presentation data.

const SAMPLE := preload("res://gm_runtime/editor_templates/planar3d/gm_ext_3d_04_neutral_template.gd")
const PROFILE_SCRIPT := preload("res://gm_runtime/map/3d/gm_facility_visual_profile_3d.gd")
const DOCUMENT_SCRIPT := preload("res://gm_runtime/map/3d/gm_scene_placement_document_3d.gd")
const SNAP_DISPLAY_NAMES_ZH := {
    "grid_snap_enabled": "网格吸附",
    "surface_snap_enabled": "平面吸附",
    "rotation_snap_enabled": "旋转吸附",
    "socket_snap_enabled": "插槽吸附",
    "ground_snap_enabled": "地面吸附",
}
const BUILDER_SCRIPT := preload("res://gm_runtime/map/3d/gm_scene_builder_3d.gd")
const CACHE_SCRIPT := preload("res://gm_runtime/map/3d/gm_scene_recipe_compile_cache.gd")
const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const PALETTE_SCRIPT := preload("res://addons/gm_editor/map3d/gm_scene_3d_palette.gd")
const DROP_SCRIPT := preload("res://addons/gm_editor/map3d/gm_scene_3d_drop_surface.gd")
const GIZMO_SCRIPT := preload("res://addons/gm_editor/map3d/gm_scene_placement_gizmo_node.gd")
const SAFE_SAVER := preload("res://addons/gm_editor/scene_refs/gm_safe_scene_saver.gd")

const DOCUMENT_PATH := "user://gm_ext_3d_04_scene_placement.tres"
const CACHE_ROOT := "user://gm_ext_3d_04_editor_compile_cache"
const FALLBACK_IDENTITY_NAMESPACE := "gm.scene3d.editor"

var editor_interface
var editor_undo_redo
var surface_graph_dock
var fixture: Dictionary = {}
var adapter
var backend
var graph: Resource
var recipe
var skeleton
var context
var profile: GMFacilityVisualProfile3D
var document: GMScenePlacementDocument3D
var lifecycle := GMScene3DDragLifecycleLedger.new()
var cache := GMSceneRecipeCompileCache.new()
var selected_id := ""
var initialized := false

var _palette: GMScene3DPalette
var _drop_surface: GMScene3DDropSurface
var _placement_list: ItemList
var _preview: SubViewport
var _built_root: Node3D
var _camera: Camera3D
var _light: DirectionalLight3D
var _gizmo_node: GMScenePlacementGizmoNode
var _status_title: Label
var _status_body: Label
var _document_path_label: Label
var _snap_checks: Dictionary = {}
var _new_button: Button
var _save_button: Button
var _reopen_button: Button
var _undo_button: Button
var _redo_button: Button
var _validate_button: Button
var _delete_cache_button: Button
var _rebuild_cache_button: Button
var _last_operation: Dictionary = {}
var _last_validation: Dictionary = {}
var _last_save: Dictionary = {}
var _last_reopen: Dictionary = {}
var _last_cache: Dictionary = {}
var _last_snap_trace: Dictionary = {}
var _last_target_source := ""
var _drag_count := 0
var _drop_count := 0
var _drop_rejection_count := 0
var _direct_success_action_calls := 0

func _init() -> void:
    name = "GMScene3DPlacementDock"
    custom_minimum_size = Vector2(1180, 600)
    _build_formal_ui()

func configure(value_editor_interface, value_editor_undo_redo, value_surface_graph_dock = null) -> void:
    editor_interface = value_editor_interface
    editor_undo_redo = value_editor_undo_redo
    surface_graph_dock = value_surface_graph_dock

func _ready() -> void:
    call_deferred("_initialize_neutral")

func _build_formal_ui() -> void:
    var root := VBoxContainer.new()
    root.name = "SceneRecipe3DFormalRoot"
    root.add_theme_constant_override("separation", 7)
    add_child(root)

    var header := HBoxContainer.new()
    root.add_child(header)
    var title := Label.new()
    title.text = "SceneRecipe3D · 世界对象 / 设施 · 正式三维策划摆放"
    title.add_theme_font_size_override("font_size", 21)
    title.custom_minimum_size.x = 420
    header.add_child(title)
    _document_path_label = Label.new()
    _document_path_label.text = "文档：%s" % DOCUMENT_PATH
    _document_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(_document_path_label)
    _new_button = _add_button(header, "新建中性场景", _on_new_pressed)
    _save_button = _add_button(header, "保存场景", _on_save_pressed)
    _reopen_button = _add_button(header, "关闭并重新打开", _on_reopen_pressed)
    _undo_button = _add_button(header, "撤销", _on_undo_pressed)
    _redo_button = _add_button(header, "重做", _on_redo_pressed)
    _validate_button = _add_button(header, "中文校验", _on_validate_pressed)

    var body := HBoxContainer.new()
    body.name = "SceneRecipe3DBody"
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 10)
    root.add_child(body)

    var left_scroll := ScrollContainer.new()
    left_scroll.custom_minimum_size.x = 325
    left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_child(left_scroll)
    var left := VBoxContainer.new()
    left.custom_minimum_size.x = 305
    left.add_theme_constant_override("separation", 5)
    left_scroll.add_child(left)
    var palette_title := Label.new()
    palette_title.text = "正式对象面板（拖入三维视口）"
    palette_title.add_theme_font_size_override("font_size", 17)
    left.add_child(palette_title)
    var palette_hint := Label.new()
    palette_hint.text = "引擎拖放：建筑 / 设施 / 非玩家角色点位 / 入口 / 工作位 / 语义槽 / 导航锚点"
    palette_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    palette_hint.add_theme_color_override("font_color", Color("8be9bd"))
    left.add_child(palette_hint)
    _palette = PALETTE_SCRIPT.new()
    _palette.name = "SceneRecipe3DPalette"
    _palette.custom_minimum_size = Vector2(300, 190)
    _palette.configure(lifecycle)
    _palette.formal_drag_issued.connect(_on_formal_drag_issued)
    left.add_child(_palette)
    var snap_title := Label.new()
    snap_title.text = "吸附与操作手柄（进入撤销重做）"
    snap_title.add_theme_font_size_override("font_size", 16)
    left.add_child(snap_title)
    for key in SNAP_DISPLAY_NAMES_ZH:
        _snap_checks[key] = _add_snap_check(left, _snap_display_name(key), key)
    _delete_cache_button = _add_button(left, "删除派生编译缓存", _on_delete_cache_pressed)
    _rebuild_cache_button = _add_button(left, "重建编译缓存", _on_rebuild_cache_pressed)
    var placement_title := Label.new()
    placement_title.text = "当前摆放（选择后显示操作范围与插槽）"
    placement_title.add_theme_font_size_override("font_size", 16)
    left.add_child(placement_title)
    _placement_list = ItemList.new()
    _placement_list.name = "SceneRecipe3DPlacementList"
    _placement_list.custom_minimum_size = Vector2(300, 190)
    _placement_list.item_selected.connect(_on_placement_selected)
    left.add_child(_placement_list)

    var right := VBoxContainer.new()
    right.name = "SceneRecipe3DViewportColumn"
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_child(right)
    var viewport_title := Label.new()
    viewport_title.text = "三维视口：选择 / 操作手柄 / 平面 / 插槽 / 地面吸附"
    viewport_title.add_theme_font_size_override("font_size", 17)
    right.add_child(viewport_title)
    _drop_surface = DROP_SCRIPT.new()
    _drop_surface.name = "SceneRecipe3DDropSurface"
    _drop_surface.custom_minimum_size = Vector2(800, 455)
    _drop_surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _drop_surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _drop_surface.formal_drop.connect(_on_formal_drop)
    _drop_surface.formal_drop_rejected.connect(_on_drop_rejected)
    right.add_child(_drop_surface)
    var canvas := Control.new()
    canvas.name = "SceneRecipe3DViewportCanvas"
    canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _drop_surface.add_child(canvas)
    var viewport_container := SubViewportContainer.new()
    viewport_container.name = "SceneRecipe3DSubViewportContainer"
    viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    viewport_container.stretch = true
    viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(viewport_container)
    _preview = SubViewport.new()
    _preview.name = "SceneRecipe3DPreviewViewport"
    _preview.size = Vector2i(800, 455)
    _preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _preview.transparent_bg = false
    viewport_container.add_child(_preview)
    var overlay := Label.new()
    overlay.name = "SceneRecipe3DViewportOverlay"
    overlay.text = "拖放到此处 · 网格 / 平面 / 旋转 / 插槽 / 地面吸附"
    overlay.position = Vector2(12, 10)
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_theme_color_override("font_color", Color("d6e4ff"))
    canvas.add_child(overlay)
    var footer := HBoxContainer.new()
    right.add_child(footer)
    _status_title = Label.new()
    _status_title.text = "等待 SceneRecipe3D"
    _status_title.add_theme_font_size_override("font_size", 17)
    footer.add_child(_status_title)
    _status_body = Label.new()
    _status_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    footer.add_child(_status_body)

func _add_button(parent: Container, text_value: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = text_value
    button.pressed.connect(callback)
    parent.add_child(button)
    return button

func _add_snap_check(parent: Container, label_text: String, key: String) -> CheckBox:
    var check := CheckBox.new()
    check.name = "SceneRecipe3D_%s" % key
    check.text = label_text
    check.button_pressed = true
    check.toggled.connect(_on_snap_toggled.bind(key))
    parent.add_child(check)
    return check

func _initialize_neutral() -> void:
    if initialized:
        return
    var source_graph = null
    if surface_graph_dock != null and surface_graph_dock.has_method("get_graph_resource"):
        source_graph = surface_graph_dock.get_graph_resource()
    fixture = SAMPLE.build_fixture(source_graph)
    if not fixture.ok and source_graph != null:
        fixture = SAMPLE.build_fixture()
    if not fixture.ok:
        _show_status("初始化失败", str(fixture.get("error_zh", "中性SceneRecipe3D夹具初始化失败。")))
        return
    adapter = fixture.adapter
    backend = fixture.backend
    graph = fixture.graph
    recipe = fixture.recipe
    skeleton = fixture.skeleton
    context = fixture.context
    profile = fixture.profile
    document = DOCUMENT_SCRIPT.neutral_document(str(recipe.recipe_id), str(recipe.fingerprint()), str(skeleton.skeleton_id), str(graph.get("graph_id")), str(profile.profile_id), "user://gm_ext_3d_04_scene.tscn")
    _drop_surface.configure(lifecycle, _palette.get_instance_id())
    initialized = true
    _refresh_snap_checks()
    _refresh_placement_list()
    _rebuild_preview()
    _show_status("SceneRecipe3D已就绪", "P23配方 → 平面三维构建器 → 平面/语义对象/设施外观呈现；内容事实仍只有配方。")

func set_authoring_document(value: GMScenePlacementDocument3D) -> Dictionary:
    if not initialized:
        return _operation_failure("set_authoring_document", "editor.scene3d.not_ready", "SceneRecipe3D正式Dock尚未完成初始化。")
    if value == null:
        return _operation_failure("set_authoring_document", "editor.scene3d.document_missing", "待载入的当前3D场景文档不存在。")
    var parsed := DOCUMENT_SCRIPT.from_native(value.to_native())
    if not parsed.ok:
        return _operation_failure("set_authoring_document", str(parsed.get("code", "editor.scene3d.document_invalid")), str(parsed.get("error_zh", "当前3D场景文档无效。")))
    var candidate: GMScenePlacementDocument3D = parsed.value
    if candidate.recipe_id != str(recipe.recipe_id) or candidate.recipe_fingerprint != recipe.fingerprint() or candidate.skeleton_id != str(skeleton.skeleton_id) or candidate.surface_graph_id != str(graph.get("graph_id")) or candidate.profile_id != str(profile.profile_id):
        return _operation_failure("set_authoring_document", "editor.scene3d.source_mismatch", "当前3D场景文档来源与场景配方、表面图或设施外观配置不一致。")
    _clear_preview()
    document = candidate
    selected_id = ""
    _refresh_snap_checks()
    _refresh_placement_list()
    _rebuild_preview()
    return {"ok": true, "action": "set_authoring_document", "document_id": document.document_id, "scene_business_id": document.scene_business_id, "identity_namespace": _identity_namespace(), "placement_ids": _placement_ids(), "mutates_document": false}

func _on_new_pressed() -> Dictionary:
    if not initialized:
        return _operation_failure("new_scene", "editor.scene3d.not_ready", "SceneRecipe3D正式Dock尚未完成初始化。")
    var fresh := DOCUMENT_SCRIPT.neutral_document(str(recipe.recipe_id), str(recipe.fingerprint()), str(skeleton.skeleton_id), str(graph.get("graph_id")), str(profile.profile_id), "user://gm_ext_3d_04_scene.tscn")
    var result := _commit_document_change("新建中性SceneRecipe3D场景", document.to_native(), fresh.to_native())
    if result.ok:
        selected_id = ""
        _show_status("新建中性场景完成", "建筑、设施、非玩家角色点位、入口、工作位、语义槽、导航锚点可从正式对象面板拖入。")
    return result

func _on_formal_drag_issued(payload: Dictionary) -> void:
    _drag_count += 1
    set_meta("last_formal_drag_payload", payload.duplicate(true))
    _show_status("已开始正式拖放", "来源：SceneRecipe3D 正式对象面板；请拖入右侧三维视口。")

func _on_formal_drop(payload: Dictionary, viewport_position: Vector2) -> void:
    _drop_count += 1
    var placement := _make_placement(str(payload.get("item_kind", "")), viewport_position, payload)
    if not placement.ok:
        _operation_failure("formal_drop", str(placement.get("code", "editor.scene3d.drop_invalid")), str(placement.get("error_zh", "3D摆放位置无效。")))
        return
    var candidate := document.set_placement(placement.value)
    if not candidate.ok:
        _operation_failure("formal_drop", str(candidate.get("code", "editor.scene3d.placement_invalid")), str(candidate.get("error_zh", "3D摆放项校验失败。")))
        return
    var result := _commit_document_change("拖放%s到3D视口" % str(payload.get("item_kind", "对象")), document.to_native(), candidate.value.to_native())
    if result.ok:
        result["payload"] = payload.duplicate(true)
        result["target_source"] = str(placement.get("target_source", _last_target_source))
        result["snap_trace"] = _last_snap_trace.duplicate(true)
        _last_operation = result
        _show_status("正式拖放完成", "%s 已进入稳定ID摆放文档与 EditorUndoRedoManager。" % str(payload.get("item_kind", "对象")))

func _on_drop_rejected(result: Dictionary) -> void:
    _drop_rejection_count += 1
    _operation_failure("formal_drop_rejected", str(result.get("code", "editor.scene3d.drop_rejected")), str(result.get("error_zh", "正式拖放被拒绝。")))

func _on_placement_selected(index: int) -> void:
    if document == null or index < 0 or index >= document.placements.size():
        return
    selected_id = str(document.placements[index].get("stable_id", ""))
    _sync_gizmo()
    _show_status("已选择三维摆放", "%s：显示操作范围、插槽列表与稳定ID。" % selected_id)

func _on_snap_toggled(pressed: bool, key: String) -> void:
    if not initialized or document == null:
        return
    var before := document.to_native()
    var after := before.duplicate(true)
    after.layout_options[key] = pressed
    var display_name := _snap_display_name(key)
    var result := _commit_document_change("编辑%s" % display_name, before, after)
    if result.ok:
        _show_status("吸附设置已更新", "%s：%s；设置变更可撤销。" % [display_name, "开启" if pressed else "关闭"])

func _snap_display_name(key: String) -> String:
    return str(SNAP_DISPLAY_NAMES_ZH.get(key, key))

func _on_undo_pressed() -> void:
    if editor_undo_redo == null:
        _operation_failure("undo", "editor.undo_redo_missing", "EditorUndoRedoManager不可用。")
        return
    var history := _history()
    if history == null or not history.has_undo():
        _operation_failure("undo", "editor.undo_unavailable", "当前SceneRecipe3D没有可撤销的正式操作。")
        return
    history.undo()
    _last_operation = {"ok": true, "action": "undo", "through_formal_control": true, "undo_gateway": "EditorUndoRedoManager", "direct_success_action_calls": 0}
    _show_status("撤销完成", "编辑器撤销管理器已恢复上一笔三维摆放或吸附设置。")

func _on_redo_pressed() -> void:
    if editor_undo_redo == null:
        _operation_failure("redo", "editor.undo_redo_missing", "EditorUndoRedoManager不可用。")
        return
    var history := _history()
    if history == null or not history.has_redo():
        _operation_failure("redo", "editor.redo_unavailable", "当前SceneRecipe3D没有可重做的正式操作。")
        return
    history.redo()
    _last_operation = {"ok": true, "action": "redo", "through_formal_control": true, "undo_gateway": "EditorUndoRedoManager", "direct_success_action_calls": 0}
    _show_status("重做完成", "编辑器撤销管理器已重做上一笔三维摆放或吸附设置。")

func _on_validate_pressed() -> Dictionary:
    if not initialized:
        return _operation_failure("validate", "editor.scene3d.not_ready", "SceneRecipe3D正式Dock尚未完成初始化。")
    var document_validation: Dictionary = document.validate()
    var profile_validation: Dictionary = profile.validate()
    var target_validation: Dictionary = BUILDER_SCRIPT.new().validate_profile_targets(profile, adapter, context)
    _last_validation = {"ok": document_validation.ok and profile_validation.ok and target_validation.ok, "document": document_validation, "profile": profile_validation, "profile_targets": target_validation, "recipe_fingerprint": recipe.fingerprint(), "surface_graph_id": str(graph.get("graph_id"))}
    if _last_validation.ok:
        _show_status("中文校验通过", "配方、设施外观、工作位/导航锚点目标与摆放文档均通过。")
    else:
        var errors: Array = []
        errors.append_array(document_validation.get("errors_zh", []))
        errors.append_array(profile_validation.get("errors_zh", []))
        errors.append_array(target_validation.get("errors", []).map(func(row): return str(row.get("error_zh", "目标失败。"))))
        _show_status("校验失败并关闭", "; ".join(errors.slice(0, 3)))
    return _last_validation

func _on_save_pressed() -> Dictionary:
    if not initialized or document == null:
        return _operation_failure("save", "editor.scene3d.not_ready", "SceneRecipe3D正式Dock尚未完成初始化。")
    var validation := _on_validate_pressed()
    if not validation.ok:
        return _operation_failure("save", "editor.scene3d.validation_failed", "校验失败，未保存半节点或孤儿稳定ID。")
    if _built_root == null or not is_instance_valid(_built_root):
        _rebuild_preview()
    var document_error := ResourceSaver.save(document, DOCUMENT_PATH)
    var owner_result: Dictionary = SAFE_SAVER.assign_owner(_built_root, false) if _built_root != null and is_instance_valid(_built_root) else {"ok": false, "code": "scene.root_missing"}
    var scene_result: Dictionary = SAFE_SAVER.pack_and_save(_built_root, document.scene_resource_path, true) if owner_result.ok else owner_result
    var reloaded_document = ResourceLoader.load(DOCUMENT_PATH, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
    var document_reload_check := DOCUMENT_SCRIPT.from_native(reloaded_document.to_native()) if reloaded_document != null and reloaded_document.has_method("to_native") else {"ok": false, "code": "editor.scene3d.document_reopen_failed", "error_zh": "摆放文档保存后无法重新打开。"}
    var packed_reopen = ResourceLoader.load(document.scene_resource_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) if scene_result.ok else null
    var saved := {"ok": document_error == OK and scene_result.ok and document_reload_check.ok and packed_reopen is PackedScene, "document_error": document_error, "document_path": DOCUMENT_PATH, "scene_path": document.scene_resource_path, "scene_business_id": document.scene_business_id, "owner": owner_result, "scene": scene_result, "document_reopen": document_reload_check.ok, "packed_scene_reopen": packed_reopen is PackedScene, "stable_ids": _placement_ids()}
    _last_save = saved
    _last_operation = {"ok": saved.ok, "action": "save", "save": saved, "through_formal_control": true, "undo_gateway": "EditorUndoRedoManager", "direct_success_action_calls": 0}
    if saved.ok:
        _show_status("保存成功", "SceneRecipe、稳定场景引用与3D摆放已保存，并完成关闭前重新读取校验。")
    else:
        _show_status("保存失败并关闭", "PackedScene/Resource 保存校验未通过，当前文档保持内存态。")
    return saved

func _on_reopen_pressed() -> Dictionary:
    if not initialized:
        return _operation_failure("reopen", "editor.scene3d.not_ready", "SceneRecipe3D正式Dock尚未完成初始化。")
    var before_ids := _placement_ids()
    var loaded = ResourceLoader.load(DOCUMENT_PATH, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
    var parsed := DOCUMENT_SCRIPT.from_native(loaded.to_native()) if loaded != null and loaded.has_method("to_native") else {"ok": false, "code": "editor.scene3d.document_missing", "error_zh": "保存的3D摆放文档不存在。"}
    if not parsed.ok:
        return _operation_failure("reopen", str(parsed.get("code", "editor.scene3d.document_invalid")), str(parsed.get("error_zh", "3D摆放文档重开失败。")))
    var candidate: GMScenePlacementDocument3D = parsed.value
    if candidate.recipe_fingerprint != recipe.fingerprint() or candidate.surface_graph_id != str(graph.get("graph_id")) or candidate.profile_id != str(profile.profile_id):
        return _operation_failure("reopen", "editor.scene3d.source_mismatch", "重开文档来源摘要与当前Recipe/Profile/Surface不一致，已拒绝替换。")
    var packed = ResourceLoader.load(candidate.scene_resource_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
    if packed == null or not packed is PackedScene:
        return _operation_failure("reopen", "editor.scene3d.scene_reference_missing", "重开文档的稳定场景引用无法解析，已拒绝替换。")
    _clear_preview()
    document = candidate
    selected_id = before_ids[0] if not before_ids.is_empty() and candidate.placements.size() > 0 else ""
    _refresh_snap_checks()
    _refresh_placement_list()
    _rebuild_preview()
    var after_ids := _placement_ids()
    _last_reopen = {"ok": before_ids == after_ids and document.validate().ok, "before_ids": before_ids, "after_ids": after_ids, "scene_business_id": document.scene_business_id, "scene_resource_path": document.scene_resource_path, "source_fingerprints": {"recipe": document.recipe_fingerprint, "surface_graph": document.surface_graph_id, "profile": document.profile_id}, "packed_scene_reopened": true}
    _last_operation = {"ok": _last_reopen.ok, "action": "reopen", "reopen": _last_reopen, "through_formal_control": true, "direct_success_action_calls": 0}
    _show_status("关闭并重新打开完成", "配方、平面图、设施外观、场景引用与稳定摆放ID均已恢复。")
    return _last_reopen

func _on_delete_cache_pressed() -> Dictionary:
    var result := cache.delete_cache(CACHE_ROOT)
    _last_cache = {"action": "delete", "result": result, "cache_present_after": cache.has_cache(CACHE_ROOT)}
    _last_operation = {"ok": result.ok and not _last_cache.cache_present_after, "action": "delete_cache", "cache": _last_cache, "through_formal_control": true, "direct_success_action_calls": 0}
    _show_status("已删除派生缓存", "编译缓存删除后不会被加载；配方、外观配置和平面仍是来源。")
    return _last_operation

func _on_rebuild_cache_pressed() -> Dictionary:
    if not initialized:
        return _operation_failure("rebuild_cache", "editor.scene3d.not_ready", "SceneRecipe3D正式Dock尚未完成初始化。")
    _rebuild_preview()
    _last_operation = {"ok": bool(_last_cache.get("ok", false)) and cache.has_cache(CACHE_ROOT), "action": "rebuild_cache", "cache": _cache_summary(), "through_formal_control": true, "direct_success_action_calls": 0}
    _show_status("编译缓存已重建", "已重新编译并写入来源摘要；下次命中前会核对配方、外观配置、平面和摆放指纹。")
    return _last_operation

func _commit_document_change(action_name: String, before: Dictionary, after: Dictionary) -> Dictionary:
    var parsed := DOCUMENT_SCRIPT.from_native(after)
    if not parsed.ok:
        return _operation_failure(action_name, str(parsed.get("code", "editor.scene3d.document_invalid")), str(parsed.get("error_zh", "3D摆放文档校验失败。")))
    if before == after:
        _apply_document_native(after)
        return {"ok": true, "action": action_name, "noop": true, "through_formal_control": true, "undo_gateway": "EditorUndoRedoManager", "direct_success_action_calls": 0}
    if editor_undo_redo == null:
        return _operation_failure(action_name, "editor.undo_redo_missing", "编辑器 UndoRedo 管理器不可用，操作未写入。")
    editor_undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, document)
    editor_undo_redo.add_do_method(self, "_apply_document_native", after)
    editor_undo_redo.add_undo_method(self, "_apply_document_native", before)
    editor_undo_redo.commit_action()
    return {"ok": true, "action": action_name, "through_formal_control": true, "undo_gateway": "EditorUndoRedoManager", "direct_success_action_calls": 0}

func _apply_document_native(value: Dictionary) -> void:
    var parsed := DOCUMENT_SCRIPT.from_native(value)
    if not parsed.ok:
        _show_status("应用失败并关闭", str(parsed.get("error_zh", "3D摆放文档应用失败。")))
        return
    # Preserve the Resource identity used by EditorUndoRedoManager histories.
    if document == null:
        document = parsed.value
    else:
        for property in parsed.value.get_property_list():
            if property.usage & PROPERTY_USAGE_STORAGE and property.name != "script":
                document.set(property.name, parsed.value.get(property.name))
    _refresh_snap_checks()
    _refresh_placement_list()
    _rebuild_preview()

func _history() -> UndoRedo:
    if editor_undo_redo == null or document == null or not editor_undo_redo.has_method("get_object_history_id") or not editor_undo_redo.has_method("get_history_undo_redo"):
        return null
    var history_id := int(editor_undo_redo.get_object_history_id(document))
    if history_id < 0:
        return null
    return editor_undo_redo.get_history_undo_redo(history_id)

func _make_placement(item_kind: String, at_position: Vector2, payload: Dictionary = {}) -> Dictionary:
    if item_kind.is_empty() or fixture.is_empty():
        return {"ok": false, "code": "editor.scene3d.item_missing", "error_zh": "正式对象面板的对象类型不能为空。"}
    var snap := _snap_drop(item_kind, at_position)
    if not snap.ok:
        return snap
    var stable_id := _placement_identity_base(item_kind)
    if stable_id.is_empty():
        return {"ok": false, "code": "editor.scene3d.identity_namespace_invalid", "error_zh": "当前SceneRecipe3D文档没有可用的稳定身份命名空间。"}
    var suffix := 2
    while _has_placement(stable_id):
        stable_id = "%s.%d" % [_placement_identity_base(item_kind), suffix]
        suffix += 1
    var target := _target_for_kind(item_kind, payload)
    if target.is_empty():
        return {"ok": false, "code": "editor.scene3d.target_missing", "error_zh": "当前SceneRecipe3D或对象面板载荷没有为%s提供合法稳定语义目标，已拒绝创建孤儿摆放项。" % item_kind}
    var socket_id := str(snap.get("socket_id", ""))
    if socket_id.is_empty():
        if item_kind == "workspot" and not profile.workspots.is_empty(): socket_id = str(profile.workspots[0].socket_id)
        if item_kind == "navigation_anchor" and not profile.navigation_anchors.is_empty(): socket_id = str(profile.navigation_anchors[0].anchor_id)
    var placement := {"stable_id": stable_id, "kind": item_kind, "display_name_zh": _display_name_for_kind(item_kind), "surface_id": str(snap.get("surface_id", "")), "profile_id": str(profile.profile_id) if item_kind in ["facility", "workspot"] else "", "socket_id": socket_id, "semantic_ref": target, "position": _vector_native(snap.position), "rotation_degrees": _vector_native(snap.rotation), "scale": _vector_native(Vector3.ONE)}
    return {"ok": true, "value": placement, "target_source": _last_target_source, "identity_namespace": _identity_namespace()}

func _snap_drop(item_kind: String, at_position: Vector2) -> Dictionary:
    var surfaces: Array = graph.get("surfaces") if graph != null else []
    if surfaces.is_empty():
        return {"ok": false, "code": "editor.scene3d.surface_missing", "error_zh": "3D摆放没有可吸附的表面。"}
    var surface: Resource = surfaces[0]
    var boundary: PackedVector2Array = surface.get("boundary")
    if boundary.size() < 3:
        return {"ok": false, "code": "editor.scene3d.surface_boundary_invalid", "error_zh": "3D摆放表面边界无效。"}
    var min_x := boundary[0].x
    var max_x := boundary[0].x
    var min_z := boundary[0].y
    var max_z := boundary[0].y
    for point in boundary:
        min_x = minf(min_x, point.x); max_x = maxf(max_x, point.x); min_z = minf(min_z, point.y); max_z = maxf(max_z, point.y)
    var view_size := Vector2(maxf(1.0, _drop_surface.size.x), maxf(1.0, _drop_surface.size.y))
    if view_size.x < 10.0: view_size.x = 800.0
    if view_size.y < 10.0: view_size.y = 455.0
    var logical := Vector2(lerpf(min_x, max_x, clampf(at_position.x / view_size.x, 0.03, 0.97)), lerpf(min_z, max_z, clampf(at_position.y / view_size.y, 0.03, 0.97)))
    var trace := {"item_kind": item_kind, "screen_position": {"x": at_position.x, "y": at_position.y}, "logical_before": _vector2_native(logical), "grid": false, "surface": false, "rotation": false, "socket": false, "ground": false}
    var layout: Dictionary = document.layout_options
    if bool(layout.get("grid_snap_enabled", true)) or (not layout.has("grid_snap_enabled") and bool(layout.get("grid_size", 1.0) > 0.0)):
        var step := maxf(0.1, float(layout.get("grid_size", 1.0)))
        logical = Vector2(snappedf(logical.x, step), snappedf(logical.y, step))
        trace.grid = true
    var surface_id := str(surface.get("surface_id"))
    if bool(layout.get("surface_snap_enabled", layout.get("surface_snap", true))):
        var sample: Dictionary = adapter.find_surface({"map_id": str(fixture.map_id), "surface_id": surface_id, "x": logical.x, "y": logical.y})
        if not sample.ok:
            return {"ok": false, "code": "editor.scene3d.surface_snap_failed", "error_zh": "平面吸附无法解析当前逻辑位置，已关闭。", "detail": sample}
        logical = Vector2(float(sample.value.planar_position.x), float(sample.value.planar_position.y))
        surface_id = str(sample.value.surface_id)
        trace.surface = true
    var world_result: Dictionary = adapter.logical_to_world({"schema_version": 1, "map_id": str(fixture.map_id), "surface_id": surface_id, "x": logical.x, "y": logical.y})
    if not world_result.ok:
        return {"ok": false, "code": "editor.scene3d.world_projection_failed", "error_zh": "表面逻辑位置无法投影到世界坐标。", "detail": world_result}
    var raw_world: Dictionary = world_result.value.world_position
    var world := Vector3(float(raw_world.x), float(raw_world.y), float(raw_world.z))
    var socket_id := ""
    if bool(layout.get("socket_snap_enabled", true)) and item_kind in ["workspot", "semantic_slot", "navigation_anchor"]:
        var facility := _first_placement_of_kind("facility")
        if not facility.is_empty():
            var socket: Resource = profile.workspots[0] if item_kind == "workspot" and not profile.workspots.is_empty() else profile.navigation_anchors[0] if item_kind == "navigation_anchor" and not profile.navigation_anchors.is_empty() else profile.interaction_points[0] if not profile.interaction_points.is_empty() else null
            if socket != null:
                world = _vector3(facility.get("position", {})) + socket.position
                surface_id = str(facility.get("surface_id", surface_id))
                socket_id = str(socket.socket_id) if socket is GMSemanticSocket3D else str(socket.anchor_id)
                trace.socket = true
    if bool(layout.get("ground_snap_enabled", layout.get("ground_snap", true))):
        var ground: Dictionary = adapter.ground_height(world, {"map_id": str(fixture.map_id), "surface_id": surface_id, "max_vertical_distance": 100.0})
        if ground.ok:
            world.y = float(ground.value.height)
            trace.ground = true
    var rotation := Vector3.ZERO
    if bool(layout.get("rotation_snap_enabled", float(layout.get("rotation_snap_degrees", 0.0)) > 0.0)):
        var rotation_step := maxf(1.0, float(layout.get("rotation_snap_degrees", 15.0)))
        rotation.y = snappedf(float(at_position.x) * 0.15, rotation_step)
        trace.rotation = true
    trace["logical_after"] = _vector2_native(logical)
    trace["world_after"] = _vector_native(world)
    trace["surface_id"] = surface_id
    trace["socket_id"] = socket_id
    _last_snap_trace = trace
    return {"ok": true, "position": world, "rotation": rotation, "surface_id": surface_id, "socket_id": socket_id, "trace": trace}

func _target_for_kind(item_kind: String, payload: Dictionary = {}) -> Dictionary:
    _last_target_source = ""
    var payload_target := _valid_semantic_target(payload.get("target_ref", payload.get("target", {})))
    if not payload_target.is_empty():
        _last_target_source = "palette_payload.target_ref"
        return payload_target
    var target := {}
    var source := ""
    match item_kind:
        "entrance":
            target = _valid_semantic_target(recipe.entry) if recipe != null else {}
            source = "recipe.entry"
        "workspot":
            target = _first_profile_target(profile.workspots if profile != null else [])
            source = "profile.workspots"
            if target.is_empty():
                target = _recipe_slot_target("resource")
                source = "recipe.slots.resource"
        "semantic_slot":
            target = _recipe_slot_target("objective")
            source = "recipe.slots.objective"
        "navigation_anchor":
            target = _first_profile_target(profile.navigation_anchors if profile != null else [])
            source = "profile.navigation_anchors"
            if target.is_empty():
                target = _recipe_slot_target("extraction")
                source = "recipe.slots.extraction"
        "facility":
            target = _recipe_slot_target("facility")
            source = "recipe.slots.facility"
            if target.is_empty():
                target = _recipe_object_target("facility")
                source = "recipe.semantic_objects.facility"
        "npc_point":
            target = _recipe_participant_target()
            source = "recipe.participants"
            if target.is_empty():
                target = _recipe_object_target("actor")
                source = "recipe.semantic_objects.actor"
        _:
            target = _recipe_object_target(item_kind)
            source = "recipe.semantic_objects.%s" % item_kind
    if not target.is_empty():
        _last_target_source = source
    else:
        _last_target_source = "unresolved"
    return target

func _valid_semantic_target(value: Variant) -> Dictionary:
    if not value is Dictionary or value.is_empty():
        return {}
    var check := VALUE.semantic_ref(value, false)
    if not check.ok:
        return {}
    var normalized: Variant = check.get("value", value)
    return normalized.duplicate(true) if normalized is Dictionary else {}

func _recipe_slot_target(slot_kind: String) -> Dictionary:
    if recipe == null:
        return {}
    for raw_slot in recipe.slots:
        if raw_slot is Dictionary and str(raw_slot.get("slot_kind", "")) == slot_kind:
            var target := _valid_semantic_target(raw_slot.get("target_ref", {}))
            if not target.is_empty():
                return target
    return {}

func _recipe_object_target(object_kind: String) -> Dictionary:
    if recipe == null:
        return {}
    for raw_object in recipe.semantic_objects:
        if raw_object is Dictionary and str(raw_object.get("object_kind", "")) == object_kind:
            var object_id := str(raw_object.get("object_id", ""))
            var target := _valid_semantic_target({"type": "object", "id": object_id})
            if not target.is_empty():
                return target
    return {}

func _recipe_participant_target() -> Dictionary:
    if recipe == null:
        return {}
    for raw_participant in recipe.participants:
        var target := _valid_semantic_target(raw_participant)
        if not target.is_empty():
            return target
    return {}

func _first_profile_target(values: Array) -> Dictionary:
    for resource in values:
        if resource == null:
            continue
        var target := _valid_semantic_target(resource.get("target_ref"))
        if not target.is_empty():
            return target
    return {}

func _identity_namespace() -> Dictionary:
    var candidates: Array = []
    if document != null:
        candidates = [
            {"source": "document.scene_business_id", "value": str(document.scene_business_id)},
            {"source": "document.document_id", "value": str(document.document_id)},
            {"source": "document.recipe_id", "value": str(document.recipe_id)},
        ]
    if recipe != null:
        candidates.append({"source": "recipe.recipe_id", "value": str(recipe.recipe_id)})
    for candidate in candidates:
        var identity_component := _stable_identity_component(str(candidate.get("value", "")))
        if not identity_component.is_empty():
            return {"schema": "gm.editor.scene3d.identity.v1", "source": str(candidate.get("source", "")), "namespace": identity_component}
    return {"schema": "gm.editor.scene3d.identity.v1", "source": "fallback", "namespace": FALLBACK_IDENTITY_NAMESPACE}

func _stable_identity_component(value: String) -> String:
    var candidate := value.strip_edges()
    if candidate.is_empty() or not PLANAR_POSITION.is_valid_stable_id(candidate):
        return ""
    return candidate

func _placement_identity_base(item_kind: String) -> String:
    var kind := item_kind.strip_edges()
    if kind.is_empty() or not PLANAR_POSITION.is_valid_stable_id(kind):
        return ""
    var identity := _identity_namespace()
    return "gm.placement.%s.%s" % [str(identity.get("namespace", FALLBACK_IDENTITY_NAMESPACE)), kind]

func _display_name_for_kind(item_kind: String) -> String:
    match item_kind:
        "building": return "中性建筑"
        "facility": return "中性设施"
        "npc_point": return "非玩家角色点位"
        "entrance": return "入口"
        "workspot": return "工作位"
        "semantic_slot": return "语义槽"
        "navigation_anchor": return "导航锚点"
        _: return item_kind

func _rebuild_preview() -> void:
    if not initialized:
        return
    _clear_preview()
    var compiled: Dictionary = cache.compile_cached(recipe, skeleton, context, adapter, profile, document.placements, CACHE_ROOT, {"strict_profile_targets": true, "layout_options": document.layout_options})
    _last_cache = compiled.duplicate(true)
    if not compiled.ok:
        _show_status("编译失败并关闭", str(compiled.get("error_zh", "SceneRecipe3D编译失败。")))
        return
    _built_root = compiled.root as Node3D
    if _built_root == null:
        _show_status("编译失败并关闭", "派生PackedScene没有Node3D根节点。")
        return
    _preview.add_child(_built_root)
    var focus := _preview_focus()
    _camera = Camera3D.new()
    _camera.name = "EditorOnlySceneRecipe3DCamera"
    _camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    _camera.size = 30.0
    _camera.position = focus + Vector3(13.0, 22.0, 22.0)
    _preview.add_child(_camera)
    _camera.look_at(focus, Vector3.UP)
    _camera.current = true
    _light = DirectionalLight3D.new()
    _light.name = "EditorOnlySceneRecipe3DLight"
    _light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
    _light.light_energy = 1.25
    _preview.add_child(_light)
    _sync_gizmo()

func _clear_preview() -> void:
    if _gizmo_node != null and is_instance_valid(_gizmo_node):
        _gizmo_node.free()
    _gizmo_node = null
    if _camera != null and is_instance_valid(_camera):
        _camera.free()
    _camera = null
    if _light != null and is_instance_valid(_light):
        _light.free()
    _light = null
    if _built_root != null and is_instance_valid(_built_root):
        _built_root.free()
    _built_root = null

func _sync_gizmo() -> void:
    if not initialized or _preview == null:
        return
    if _gizmo_node != null and is_instance_valid(_gizmo_node):
        _gizmo_node.free()
    _gizmo_node = null
    var placement := _find_placement(selected_id)
    if placement.is_empty():
        return
    _gizmo_node = GIZMO_SCRIPT.new()
    _gizmo_node.configure(selected_id, _profile_socket_ids())
    _gizmo_node.position = _vector3(placement.get("position", {}))
    _gizmo_node.gizmo_range = Vector3(1.5, 1.5, 1.5)
    _gizmo_node.set_meta("gm_gizmo_source", "GMScene3DPlacementDock")
    _preview.add_child(_gizmo_node)
    var selection := MeshInstance3D.new()
    selection.name = "SelectionRange"
    var mesh := SphereMesh.new()
    mesh.radius = 1.5
    mesh.height = 3.0
    selection.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(1.0, 0.85, 0.35, 0.16)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    selection.material_override = material
    _gizmo_node.add_child(selection)
    var label := Label3D.new()
    label.text = "操作手柄 · %s · 插槽 %d" % [selected_id, _profile_socket_ids().size()]
    label.position = Vector3(0.0, 2.0, 0.0)
    label.font_size = 20
    label.modulate = Color("ffe082")
    _gizmo_node.add_child(label)

func _refresh_placement_list() -> void:
    if _placement_list == null:
        return
    _placement_list.clear()
    if document == null:
        return
    for placement in document.placements:
        var index := _placement_list.add_item("%s · %s" % [str(placement.get("display_name_zh", "")), str(placement.get("stable_id", ""))])
        _placement_list.set_item_metadata(index, str(placement.get("stable_id", "")))
    if not selected_id.is_empty():
        for index in _placement_list.item_count:
            if str(_placement_list.get_item_metadata(index)) == selected_id:
                _placement_list.select(index)
                break

func _refresh_snap_checks() -> void:
    if document == null:
        return
    for key in _snap_checks.keys():
        var check: CheckBox = _snap_checks[key]
        check.set_pressed_no_signal(bool(document.layout_options.get(str(key), true)))

func _show_status(title: String, body: String) -> void:
    if _status_title != null:
        _status_title.text = title
    if _status_body != null:
        _status_body.text = body

func _operation_failure(action_name: String, code: String, message: String) -> Dictionary:
    _last_operation = {"ok": false, "action": action_name, "code": code, "error_zh": message, "through_formal_control": true, "direct_success_action_calls": 0}
    _show_status("操作失败并关闭", message)
    return _last_operation

func _preview_focus() -> Vector3:
    if graph == null or graph.get("surfaces").is_empty():
        return Vector3.ZERO
    var surface: Resource = graph.get("surfaces")[0]
    var boundary: PackedVector2Array = surface.get("boundary")
    if boundary.is_empty():
        return Vector3.ZERO
    var min_x := boundary[0].x; var max_x := boundary[0].x; var min_z := boundary[0].y; var max_z := boundary[0].y
    for point in boundary:
        min_x = minf(min_x, point.x); max_x = maxf(max_x, point.x); min_z = minf(min_z, point.y); max_z = maxf(max_z, point.y)
    return surface.call("logical_to_world", Vector2((min_x + max_x) * 0.5, (min_z + max_z) * 0.5)) as Vector3

func _find_placement(value_id: String) -> Dictionary:
    if document == null:
        return {}
    for placement in document.placements:
        if str(placement.get("stable_id", "")) == value_id:
            return placement
    return {}

func _first_placement_of_kind(kind: String) -> Dictionary:
    if document == null:
        return {}
    for placement in document.placements:
        if str(placement.get("kind", "")) == kind:
            return placement
    return {}

func _has_placement(value_id: String) -> bool:
    return not _find_placement(value_id).is_empty()

func _placement_ids() -> Array:
    var result: Array = []
    if document != null:
        for placement in document.placements:
            result.append(str(placement.get("stable_id", "")))
    return result

func _profile_socket_ids() -> PackedStringArray:
    var result := PackedStringArray()
    if profile == null:
        return result
    for socket in profile.interaction_points + profile.workspots + profile.input_sockets + profile.output_sockets + profile.vfx_sockets + profile.audio_sockets:
        if socket is GMSemanticSocket3D:
            result.append(str(socket.socket_id))
    for anchor in profile.navigation_anchors:
        if anchor is GMSemanticAnchor3D:
            result.append(str(anchor.anchor_id))
    return result

func _vector3(value: Variant) -> Vector3:
    if value is Vector3:
        return value
    if value is Dictionary:
        return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
    return Vector3.ZERO

func _vector_native(value: Vector3) -> Dictionary:
    return {"x": value.x, "y": value.y, "z": value.z}

func _vector2_native(value: Vector2) -> Dictionary:
    return {"x": value.x, "y": value.y}

func _cache_summary() -> Dictionary:
    return {"ok": bool(_last_cache.get("ok", false)), "cache_hit": bool(_last_cache.get("cache_hit", false)), "invalidated": bool(_last_cache.get("invalidated", false)), "cache_key": str(_last_cache.get("cache_key", "")), "source_digest": str(_last_cache.get("source_digest", "")), "record": _last_cache.get("record", {}).duplicate(true) if _last_cache.get("record", {}) is Dictionary else {}}

func get_capture_snapshot() -> Dictionary:
    return {
        "ui_source_formal": true,
        "ui_root_script": "res://addons/gm_editor/map3d/gm_scene_3d_placement_dock.gd",
        "ui_root_class": "GMScene3DPlacementDock",
        "formal_path": "GM编辑器 → 平面三维地图 → SceneRecipe3D世界对象/设施策划摆放",
        "controls": ["新建中性场景", "正式对象面板拖放", "三维视口选择", "网格吸附", "平面吸附", "旋转吸附", "插槽吸附", "地面吸附", "操作手柄范围", "中文校验", "撤销", "重做", "保存场景", "关闭并重新打开", "删除派生编译缓存", "重建编译缓存"],
        "undo_gateway": "EditorUndoRedoManager",
        "drag_drop": {"drag_count": _drag_count, "drop_count": _drop_count, "rejection_count": _drop_rejection_count, "source_script": "res://addons/gm_editor/map3d/gm_scene_3d_palette.gd", "drop_surface_script": "res://addons/gm_editor/map3d/gm_scene_3d_drop_surface.gd"},
        "recipe": {"recipe_id": str(recipe.recipe_id) if recipe != null else "", "fingerprint": recipe.fingerprint() if recipe != null else "", "sole_content_fact_source": true},
        "surface_graph": {"graph_id": str(graph.get("graph_id")) if graph != null else "", "source": "GMMap3DEditorDock.get_graph_resource", "surface_ids": fixture.get("surface_ids", [])},
        "profile": {"profile_id": str(profile.profile_id) if profile != null else "", "fingerprint": profile.fingerprint() if profile != null else "", "validation": profile.validate() if profile != null else {"ok": false}, "replaceable_presentation_only": true, "socket_ids": _profile_socket_ids()},
        "identity_namespace": _identity_namespace(),
        "document": {"document_id": str(document.document_id) if document != null else "", "fingerprint": document.fingerprint() if document != null else "", "placement_ids": _placement_ids(), "scene_business_id": str(document.scene_business_id) if document != null else "", "scene_resource_path": str(document.scene_resource_path) if document != null else ""},
        "selected_id": selected_id,
        "gizmo": {"visible": _gizmo_node != null and is_instance_valid(_gizmo_node), "script": "res://addons/gm_editor/map3d/gm_scene_placement_gizmo_node.gd", "range": {"x": 1.5, "y": 1.5, "z": 1.5}, "socket_count": _profile_socket_ids().size()},
        "snap_trace": _last_snap_trace.duplicate(true),
        "validation": _last_validation.duplicate(true),
        "save_close_reopen": {"save": _last_save.duplicate(true), "reopen": _last_reopen.duplicate(true)},
        "cache": _cache_summary(),
        "projection_only": true,
        "runtime_editor_api_dependency": false,
        "substitute_ui": false,
        "direct_success_action_calls": _direct_success_action_calls,
    }

func run_ext_3d_04_editor_probe() -> Dictionary:
    if not initialized or editor_undo_redo == null or _palette == null or _drop_surface == null:
        return {"ok": false, "event": "GM_EXT_3D_04_EDITOR_SENTINEL", "code": "gm.ext3d04.editor_controls_missing", "through_formal_controls": false, "direct_success_action_calls": 0}
    _delete_cache_button.pressed.emit()
    _new_button.pressed.emit()
    for key in _snap_checks.keys():
        var check: CheckBox = _snap_checks[key]
        check.button_pressed = true
    var drag_drop_trace: Array = []
    var kinds := ["building", "facility", "npc_point", "entrance", "workspot", "semantic_slot", "navigation_anchor"]
    var positions := [Vector2(110, 90), Vector2(260, 150), Vector2(380, 210), Vector2(500, 270), Vector2(600, 320), Vector2(280, 350), Vector2(420, 390)]
    for index in kinds.size():
        var payload := _palette.make_formal_payload(kinds[index])
        _drop_surface._drop_data(positions[index], payload)
        drag_drop_trace.append({"kind": kinds[index], "payload": payload, "operation": _last_operation.duplicate(true), "snap": _last_snap_trace.duplicate(true)})
    var count_after_place := document.placements.size()
    var before_invalid := document.fingerprint()
    var invalid_payload := _palette.make_formal_payload("building")
    invalid_payload["source_script"] = "res://addons/gm_editor/not_formal_palette.gd"
    _drop_surface._drop_data(Vector2(40, 40), invalid_payload)
    var invalid_no_pollution := document.fingerprint() == before_invalid and _drop_rejection_count > 0
    var selected_index := -1
    var facility_identity_base := _placement_identity_base("facility")
    for index in _placement_list.item_count:
        var placement_id := str(_placement_list.get_item_metadata(index))
        if placement_id == facility_identity_base or placement_id.begins_with(facility_identity_base + "."):
            selected_index = index
            break
    if selected_index >= 0:
        _placement_list.item_selected.emit(selected_index)
    var selected_before_history := selected_id
    var count_before_undo := document.placements.size()
    _undo_button.pressed.emit()
    var count_after_undo := document.placements.size()
    _redo_button.pressed.emit()
    var count_after_redo := document.placements.size()
    _validate_button.pressed.emit()
    var validation := _last_validation.duplicate(true)
    _save_button.pressed.emit()
    var saved := _last_save.duplicate(true)
    _reopen_button.pressed.emit()
    var reopened := _last_reopen.duplicate(true)
    _delete_cache_button.pressed.emit()
    var cache_deleted := _last_cache.duplicate(true)
    _rebuild_cache_button.pressed.emit()
    var cache_rebuilt := _last_cache.duplicate(true)
    var good_profile := profile.validate()
    var duplicate_profile: GMFacilityVisualProfile3D = profile.duplicate(true)
    if not profile.workspots.is_empty():
        duplicate_profile.workspots.append(profile.workspots[0].duplicate(true))
    else:
        duplicate_profile.workspots.append(null)
    var duplicate_check := duplicate_profile.validate()
    var type_profile: GMFacilityVisualProfile3D = profile.duplicate(true)
    if not type_profile.workspots.is_empty():
        type_profile.navigation_anchors.append(type_profile.workspots[0])
    var type_check := type_profile.validate()
    var missing_profile: GMFacilityVisualProfile3D = profile.duplicate(true)
    if not missing_profile.workspots.is_empty():
        missing_profile.workspots[0].target_ref = {}
    var missing_check := missing_profile.validate()
    var obstacle_result: Dictionary = backend.update_dynamic_obstacles([{"obstacle_id": "gm.obstacle.ext3d04.editor_probe", "map_id": str(fixture.map_id), "surface_id": str(fixture.primary_surface_id), "min": {"x": -1.0, "y": -1.0}, "max": {"x": 25.0, "y": 25.0}, "enabled": true}])
    var unreachable_check := BUILDER_SCRIPT.new().validate_profile_targets(profile, adapter, context)
    backend.clear_dynamic_obstacles()
    var profile_replacement: GMFacilityVisualProfile3D = profile.duplicate(true)
    profile_replacement.display_name_zh = "中性设施·工坊/居所/训练可替换外观"
    var recipe_fingerprint_after_profile_replace: String = recipe.fingerprint()
    var result := {
        "ok": count_after_place == kinds.size() and invalid_no_pollution and selected_before_history != "" and count_after_undo == count_before_undo - 1 and count_after_redo == count_before_undo and validation.ok and saved.ok and reopened.ok and bool(cache_deleted.get("result", {}).get("ok", false)) and not bool(cache_deleted.get("cache_present_after", true)) and bool(cache_rebuilt.get("ok", false)) and bool(good_profile.ok) and not duplicate_check.ok and not type_check.ok and not missing_check.ok and obstacle_result.ok and not unreachable_check.ok,
        "event": "GM_EXT_3D_04_EDITOR_SENTINEL",
        "through_formal_controls": true,
        "direct_success_action_calls": _direct_success_action_calls,
        "formal_path": "GM编辑器 → 平面三维地图 → SceneRecipe3D世界对象/设施策划摆放",
        "drag_drop_trace": drag_drop_trace,
        "placement_count": count_after_place,
        "invalid_drop_no_pollution": invalid_no_pollution,
        "selection": {"selected_id": selected_before_history, "gizmo": get_capture_snapshot().gizmo},
        "undo_redo": {"before": count_before_undo, "after_undo": count_after_undo, "after_redo": count_after_redo, "gateway": "EditorUndoRedoManager"},
        "validation": validation,
        "profile_boundaries": {"good": good_profile, "duplicate_socket": duplicate_check, "wrong_socket_type": type_check, "missing_target": missing_check, "unreachable_workspot": unreachable_check, "obstacle_update": obstacle_result, "replaceable_profile": {"old_profile_id": str(profile.profile_id), "new_profile_id": str(profile_replacement.profile_id), "recipe_fingerprint_unchanged": recipe_fingerprint_after_profile_replace == recipe.fingerprint(), "domain_logic_changed": false}},
        "save_close_reopen": {"saved": saved, "reopened": reopened},
        "cache": {"deleted": cache_deleted, "rebuilt": cache_rebuilt},
        "stable_ids": _placement_ids(),
        "snapshot": get_capture_snapshot(),
        "substitute_ui": false,
    }
    _last_operation["probe"] = result
    return result

func _make_generality_document(document_id: String, scene_business_id: String, scene_resource_path: String) -> GMScenePlacementDocument3D:
    var value := DOCUMENT_SCRIPT.neutral_document(str(recipe.recipe_id), str(recipe.fingerprint()), str(skeleton.skeleton_id), str(graph.get("graph_id")), str(profile.profile_id), scene_resource_path)
    value.document_id = document_id
    value.scene_business_id = scene_business_id
    value.placements = []
    return value

func _run_generality_scene(value_document: GMScenePlacementDocument3D, scene_label: String, positions: Array) -> Dictionary:
    var context_result := set_authoring_document(value_document)
    if not context_result.ok:
        return {"ok": false, "scene_label": scene_label, "context": context_result}
    var identity := _identity_namespace()
    var operations: Array = []
    for position in positions:
        var payload := _palette.make_formal_payload("facility")
        _drop_surface._drop_data(position, payload)
        operations.append({"payload": payload, "operation": _last_operation.duplicate(true), "snap": _last_snap_trace.duplicate(true)})
    var ids_after_add := _placement_ids()
    var targets_after_add: Array = []
    for placement in document.placements:
        targets_after_add.append({"stable_id": str(placement.get("stable_id", "")), "semantic_ref": placement.get("semantic_ref", {}).duplicate(true)})
    var count_before_undo := document.placements.size()
    _undo_button.pressed.emit()
    var ids_after_undo := _placement_ids()
    var count_after_undo := document.placements.size()
    _redo_button.pressed.emit()
    var ids_after_redo := _placement_ids()
    var count_after_redo := document.placements.size()
    _validate_button.pressed.emit()
    var validation := _last_validation.duplicate(true)
    _save_button.pressed.emit()
    var saved := _last_save.duplicate(true)
    _reopen_button.pressed.emit()
    var reopened := _last_reopen.duplicate(true)
    var ids_after_reopen := _placement_ids()
    var unique_ids := _ids_are_unique(ids_after_add)
    var target_sources: Array = []
    for operation in operations:
        target_sources.append(str(operation.get("operation", {}).get("target_source", "")))
    return {
        "ok": count_before_undo == positions.size() and count_after_undo == count_before_undo - 1 and count_after_redo == count_before_undo and ids_after_redo == ids_after_add and ids_after_reopen == ids_after_add and unique_ids and validation.ok and saved.ok and reopened.ok and not target_sources.has("unresolved"),
        "scene_label": scene_label,
        "document": {"document_id": value_document.document_id, "scene_business_id": value_document.scene_business_id, "scene_resource_path": value_document.scene_resource_path},
        "identity_namespace": identity,
        "operations": operations,
        "target_sources": target_sources,
        "targets_after_add": targets_after_add,
        "placement_ids": ids_after_add,
        "placement_ids_after_undo": ids_after_undo,
        "placement_ids_after_redo": ids_after_redo,
        "placement_ids_after_reopen": ids_after_reopen,
        "no_duplicate_business_ids": unique_ids,
        "undo_redo": {"before": count_before_undo, "after_undo": count_after_undo, "after_redo": count_after_redo, "gateway": "EditorUndoRedoManager"},
        "validation": validation,
        "save_close_reopen": {"saved": saved, "reopened": reopened},
        "reopened_native": document.to_native(),
    }

func _ids_are_unique(values: Array) -> bool:
    var seen: Dictionary = {}
    for value in values:
        var stable_id := str(value)
        if seen.has(stable_id):
            return false
        seen[stable_id] = true
    return true

func _ids_are_disjoint(left: Array, right: Array) -> bool:
    for value in left:
        if right.has(value):
            return false
    return true

func run_ext_3d_04_generality_probe() -> Dictionary:
    if not initialized or editor_undo_redo == null or _palette == null or _drop_surface == null:
        return {"ok": false, "event": "GM_EXT_3D_04_GENERALITY_EDITOR_SENTINEL", "code": "gm.ext3d04.generality_editor_controls_missing", "through_formal_controls": false, "direct_success_action_calls": 0}
    _delete_cache_button.pressed.emit()
    var scene_a_document := _make_generality_document("gm.document.generality.harbor_archive", "gm.scene.generality.harbor_archive", "user://gm_ext_3d_04_generality_harbor_archive.tscn")
    var scene_b_document := _make_generality_document("gm.document.generality.mountain_lab", "gm.scene.generality.mountain_lab", "user://gm_ext_3d_04_generality_mountain_lab.tscn")
    var scene_a := _run_generality_scene(scene_a_document, "harbor_archive", [Vector2(230, 140), Vector2(330, 220)])
    var scene_b := _run_generality_scene(scene_b_document, "mountain_lab", [Vector2(460, 180), Vector2(560, 260)])
    var scene_ids_separated := _ids_are_disjoint(scene_a.get("placement_ids", []), scene_b.get("placement_ids", []))
    var namespace_separated := str(scene_a.get("identity_namespace", {}).get("namespace", "")) != str(scene_b.get("identity_namespace", {}).get("namespace", ""))

    var legacy_document := DOCUMENT_SCRIPT.neutral_document(str(recipe.recipe_id), str(recipe.fingerprint()), str(skeleton.skeleton_id), str(graph.get("graph_id")), str(profile.profile_id), "user://gm_ext_3d_04_generality_legacy_scene.tscn")
    var legacy_context := set_authoring_document(legacy_document)
    var legacy_candidate := _make_placement("facility", Vector2(300, 160))
    var legacy_before_ids: Array = []
    var legacy_id := ""
    var legacy_set := {"ok": false}
    if legacy_context.ok and legacy_candidate.ok:
        legacy_id = "gm.placement.%s.facility" % str(legacy_document.scene_business_id).replace("gm.scene.", "")
        var legacy_placement: Dictionary = legacy_candidate.value.duplicate(true)
        legacy_placement["stable_id"] = legacy_id
        legacy_set = legacy_document.set_placement(legacy_placement)
        if legacy_set.ok:
            var legacy_loaded := set_authoring_document(legacy_set.value)
            if legacy_loaded.ok:
                legacy_before_ids = _placement_ids()
                _save_button.pressed.emit()
                var legacy_saved := _last_save.duplicate(true)
                _reopen_button.pressed.emit()
                var legacy_reopened := _last_reopen.duplicate(true)
                var legacy_after_ids := _placement_ids()
                legacy_set["save"] = legacy_saved
                legacy_set["reopen"] = legacy_reopened
                legacy_set["after_ids"] = legacy_after_ids
                legacy_set["stable_id_preserved"] = legacy_before_ids == legacy_after_ids and legacy_after_ids == [legacy_id]
    var legacy_compatibility := {"ok": bool(legacy_set.get("stable_id_preserved", false)), "derived_legacy_id": legacy_id, "before_ids": legacy_before_ids, "after_ids": legacy_set.get("after_ids", []), "save_close_reopen": {"saved": legacy_set.get("save", {}), "reopened": legacy_set.get("reopen", {})}}

    var scene_b_restore := DOCUMENT_SCRIPT.from_native(scene_b.get("reopened_native", {}))
    var restored_b := set_authoring_document(scene_b_restore.value) if scene_b_restore.ok else {"ok": false, "code": "editor.scene3d.generality_scene_restore_failed"}
    var legacy_namespace := "gm.placement.%s." % str(legacy_document.scene_business_id).replace("gm.scene.", "")
    var new_ids_avoid_legacy := true
    for stable_id in scene_a.get("placement_ids", []) + scene_b.get("placement_ids", []):
        if str(stable_id).begins_with(legacy_namespace):
            new_ids_avoid_legacy = false
            break
    var result := {
        "ok": scene_a.get("ok", false) and scene_b.get("ok", false) and scene_ids_separated and namespace_separated and legacy_compatibility.ok and new_ids_avoid_legacy and restored_b.ok,
        "event": "GM_EXT_3D_04_GENERALITY_EDITOR_SENTINEL",
        "through_formal_controls": true,
        "direct_success_action_calls": _direct_success_action_calls,
        "formal_path": "GM编辑器 → 平面三维地图 → SceneRecipe3D世界对象/设施策划摆放",
        "identity_factory": {"schema": "gm.editor.scene3d.identity.v1", "source_priority": ["document.scene_business_id", "document.document_id", "document.recipe_id", "recipe.recipe_id"], "placement_prefix": "gm.placement.<current-namespace>.<item-kind>", "duplicate_serial": ".2, .3, …"},
        "scene_a": scene_a,
        "scene_b": scene_b,
        "identity_separation": {"namespace_separated": namespace_separated, "placement_ids_disjoint": scene_ids_separated, "new_ids_avoid_legacy_namespace": new_ids_avoid_legacy},
        "legacy_compatibility": legacy_compatibility,
        "restored_scene": restored_b,
        "snapshot": get_capture_snapshot(),
        "substitute_ui": false,
    }
    _last_operation["probe"] = result
    return result
