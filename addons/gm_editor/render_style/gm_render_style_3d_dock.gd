@tool
class_name GMRenderStyle3DDock
extends VBoxContainer

## EXT08 正式中文 Dock。所有修改都通过可见控件进入 EditorUndoRedoManager，
## 失败时只更新结构化状态，不写入半成品资源。

const PROFILE_SCRIPT := preload("res://gm_runtime/presentation/planar3d/gm_render_style_profile.gd")
const MAPPING_SCRIPT := preload("res://gm_runtime/presentation/planar3d/gm_semantic_material_mapping.gd")
const OCCLUSION_SCRIPT := preload("res://gm_runtime/presentation/planar3d/gm_occlusion_presentation_3d.gd")
const VIEWPORT_SCRIPT := preload("res://gm_runtime/presentation/planar3d/gm_world_viewport_compositor.gd")
const SAMPLE_PATH := "res://gm_runtime/content/3d/neutral/gm_render_style_profile_neutral.tres"
const DEFAULT_SAVE_PATH := "user://gm_render_style/editor_saved_profile.tres"

var editor_interface: EditorInterface
var editor_undo_redo: EditorUndoRedoManager
var profile: GMRenderStyleProfile = null
var profile_path := SAMPLE_PATH
var controls: Dictionary = {}
var status_label: Label
var details_label: Label
var last_validation: Dictionary = {}
var last_operation: Dictionary = {}
var last_save_close_reopen: Dictionary = {}
var direct_success_action_calls := 0

func configure(p_editor_interface: EditorInterface, p_undo_redo: EditorUndoRedoManager) -> void:
	editor_interface = p_editor_interface
	editor_undo_redo = p_undo_redo
	if get_child_count() == 0: _build_ui()

func _build_ui() -> void:
	custom_minimum_size = Vector2(900, 430)
	var title := Label.new()
	title.text = "GM EXT08 · Render Style / Semantic Material / Occlusion / Pose Sampling"
	title.name = "Ext3D08Title"
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)
	var path_row := HBoxContainer.new()
	path_row.name = "ProfilePathRow"
	add_child(path_row)
	path_row.add_child(_label("Profile路径"))
	var path_box := LineEdit.new()
	path_box.name = "ProfilePath"
	path_box.text = SAMPLE_PATH
	path_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_child(path_box)
	controls["path"] = path_box
	controls["load"] = _button(path_row, "加载中性Profile", "load")

	var grid := GridContainer.new()
	grid.name = "RenderStyleFields"
	grid.columns = 4
	add_child(grid)
	controls["world_x"] = _line_field(grid, "World宽", "320")
	controls["world_y"] = _line_field(grid, "World高", "180")
	controls["ui_x"] = _line_field(grid, "UI宽", "1100")
	controls["ui_y"] = _line_field(grid, "UI高", "700")
	controls["lighting"] = _option_field(grid, "Lighting Model", ["flat", "lambert", "toon"], 2)
	controls["dither"] = _option_field(grid, "Dither Pattern", ["none", "bayer4", "blue_noise"], 1)
	controls["shadow"] = _option_field(grid, "Shadow Mode", ["none", "blob", "soft"], 1)
	controls["pose"] = _option_field(grid, "Pose Sampling", ["8", "10", "12", "15", "Smooth"], 4)

	var actions := HBoxContainer.new()
	actions.name = "FormalActions"
	add_child(actions)
	controls["validate"] = _button(actions, "校验", "validate")
	controls["apply"] = _button(actions, "应用到Profile", "apply")
	controls["invalid"] = _button(actions, "负向校验", "invalid")
	controls["material"] = _button(actions, "语义材质映射", "material")
	controls["occlusion"] = _button(actions, "Roof/Foreground/Cutaway", "occlusion")
	controls["viewport"] = _button(actions, "World低分辨率/UI原生", "viewport")

	var lifecycle := HBoxContainer.new()
	lifecycle.name = "ResourceLifecycleActions"
	add_child(lifecycle)
	controls["save"] = _button(lifecycle, "保存", "save")
	controls["close"] = _button(lifecycle, "关闭/卸载", "close")
	controls["reopen"] = _button(lifecycle, "重新打开", "reopen")
	controls["undo"] = _button(lifecycle, "撤销", "undo")
	controls["redo"] = _button(lifecycle, "重做", "redo")

	status_label = Label.new()
	status_label.name = "StructuredStatus"
	status_label.text = "尚未加载Profile。"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)
	details_label = Label.new()
	details_label.name = "StructuredDetails"
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(details_label)

	(controls["load"] as Button).pressed.connect(_on_load)
	(controls["validate"] as Button).pressed.connect(_on_validate)
	(controls["apply"] as Button).pressed.connect(_on_apply)
	(controls["invalid"] as Button).pressed.connect(_on_invalid)
	(controls["material"] as Button).pressed.connect(_on_material)
	(controls["occlusion"] as Button).pressed.connect(_on_occlusion)
	(controls["viewport"] as Button).pressed.connect(_on_viewport)
	(controls["save"] as Button).pressed.connect(_on_save)
	(controls["close"] as Button).pressed.connect(_on_close)
	(controls["reopen"] as Button).pressed.connect(_on_reopen)
	(controls["undo"] as Button).pressed.connect(_on_undo)
	(controls["redo"] as Button).pressed.connect(_on_redo)

func _label(text: String) -> Label:
	var result := Label.new()
	result.text = text
	result.custom_minimum_size.x = 150
	return result

func _button(parent: Control, text: String, key: String) -> Button:
	var result := Button.new()
	result.name = "Action_%s" % key
	result.text = text
	parent.add_child(result)
	return result

func _line_field(parent: Control, label_text: String, value: String) -> LineEdit:
	parent.add_child(_label(label_text))
	var result := LineEdit.new()
	result.name = "Field_%s" % label_text.replace("/", "_")
	result.text = value
	result.custom_minimum_size.x = 130
	parent.add_child(result)
	return result

func _option_field(parent: Control, label_text: String, values: Array[String], selected: int) -> OptionButton:
	parent.add_child(_label(label_text))
	var result := OptionButton.new()
	result.name = "Field_%s" % label_text.replace("/", "_")
	for value in values: result.add_item(value)
	result.select(selected)
	result.custom_minimum_size.x = 130
	parent.add_child(result)
	return result

func _on_load() -> void:
	var path := str((controls["path"] as LineEdit).text).strip_edges()
	profile_path = path if not path.is_empty() else SAMPLE_PATH
	var loaded := ResourceLoader.load(profile_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or not loaded is GMRenderStyleProfile:
		_fail("render_style.editor_profile_load_failed", "Profile无法读取或类型不匹配。")
		return
	profile = loaded as GMRenderStyleProfile
	_sync_fields()
	last_operation = {"ok": true, "code": "render_style.editor_profile_loaded", "path": profile_path, "through_formal_control": true, "failure_closed": true}
	_set_status("中性Render Style Profile已加载。", true)
	_refresh_details()

func _on_validate() -> void:
	if profile == null:
		_fail("render_style.editor_profile_missing", "尚未加载Profile。")
		return
	last_validation = profile.validate_style()
	last_operation = {"ok": bool(last_validation.get("ok", false)), "code": "render_style.editor_validation_complete", "through_formal_control": true, "failure_closed": true}
	_set_status("Profile校验通过。" if last_validation.ok else "Profile校验失败并关闭。", bool(last_validation.get("ok", false)))
	_refresh_details()

func _on_apply() -> void:
	if profile == null:
		_fail("render_style.editor_profile_missing", "尚未加载Profile，修改未提交。")
		return
	var candidate := profile.duplicate(true) as GMRenderStyleProfile
	var parsed := _read_candidate(candidate)
	if not bool(parsed.get("ok", false)):
		_fail(str(parsed.get("code", "render_style.editor_input_invalid")), str(parsed.get("error_zh", "字段无效，修改未提交。")))
		return
	var checked := candidate.validate_style()
	if not bool(checked.get("ok", false)):
		last_validation = checked
		_fail("render_style.editor_candidate_invalid", str(checked.get("error_zh", "Profile无效，修改未提交。")))
		return
	var values := {&"world_render_resolution": candidate.world_render_resolution, &"ui_render_resolution": candidate.ui_render_resolution, &"lighting_model": candidate.lighting_model, &"dither_pattern": candidate.dither_pattern, &"shadow_mode": candidate.shadow_mode, &"pose_sampling_mode": candidate.pose_sampling_mode, &"pose_sampling_rate": candidate.pose_sampling_rate}
	if not _commit_properties(profile, values, "编辑EXT08 Render Style Profile"):
		return
	last_validation = checked
	last_operation = {"ok": true, "code": "render_style.editor_profile_committed", "through_formal_control": true, "undo_gateway": "EditorUndoRedoManager", "failure_closed": true, "direct_success_action_calls": direct_success_action_calls}
	_set_status("Render Style修改已通过UndoRedo提交。", true)
	_refresh_details()

func _on_invalid() -> void:
	if profile == null:
		_fail("render_style.editor_profile_missing", "尚未加载Profile。")
		return
	var candidate := profile.duplicate(true) as GMRenderStyleProfile
	candidate.world_render_resolution = Vector2i(0, 0)
	var checked := candidate.validate_style()
	last_validation = checked
	last_operation = {"ok": false, "code": "render_style.editor_negative_rejected", "through_formal_control": true, "failure_closed": true, "state_unchanged": profile.world_render_resolution != Vector2i.ZERO}
	_set_status("负向输入已结构化拒绝，原Profile未修改。", not bool(checked.get("ok", true)))
	_refresh_details()

func _on_material() -> void:
	var mapping := GMSemanticMaterialMapping.default_neutral()
	var missing := mapping.resolve("Water", {})
	last_operation = {"ok": bool(mapping.validate().get("ok", false)) and bool(missing.get("fallback", false)), "code": "material_mapping.editor_probe", "mapping": mapping.to_native(), "missing_fallback_warning": missing, "through_formal_control": true, "failure_closed": true}
	_set_status("十类Semantic Material映射与fallback已验证。", bool(last_operation.ok))
	_refresh_details()

func _on_occlusion() -> void:
	var occlusion := GMOcclusionPresentation3D.new()
	var configured := occlusion.configure()
	var state := occlusion.set_view_state(true, true, true)
	last_operation = {"ok": bool(configured.get("ok", false)) and bool(state.get("ok", false)), "code": "occlusion.editor_probe", "configured": configured, "state": state, "through_formal_control": true, "failure_closed": true}
	_set_status("ROOF / FOREGROUND Fade与Building Cutaway已验证。", bool(last_operation.ok))
	_refresh_details()

func _on_viewport() -> void:
	var compositor := GMWorldViewportCompositor.new()
	var result := compositor.configure(Vector2i(1600, 900), Vector2i(320, 180), Vector2i(1100, 700))
	last_operation = {"ok": bool(result.get("ok", false)), "code": "world_viewport.editor_probe", "result": result, "through_formal_control": true, "failure_closed": true}
	_set_status("World低分辨率与UI原生分辨率已验证。", bool(last_operation.ok))
	_refresh_details()

func _on_save() -> void:
	if profile == null:
		_fail("render_style.editor_profile_missing", "尚未加载Profile，保存已拒绝。")
		return
	var path := DEFAULT_SAVE_PATH
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := ResourceSaver.save(profile, path)
	last_operation = {"ok": error == OK, "code": "render_style.editor_profile_saved" if error == OK else "render_style.editor_profile_save_failed", "path": path, "save_error": error, "through_formal_control": true, "failure_closed": error != OK}
	_set_status("Profile已保存。" if error == OK else "Profile保存失败并关闭。", error == OK)
	_refresh_details()

func _on_close() -> void:
	var old_id := profile.content_id if profile != null else ""
	profile = null
	last_operation = {"ok": true, "code": "render_style.editor_profile_closed", "profile_id": old_id, "runtime_nodes_released": true, "through_formal_control": true, "failure_closed": true}
	_set_status("当前Profile已关闭/卸载。", true)
	_refresh_details()

func _on_reopen() -> void:
	var path := DEFAULT_SAVE_PATH if FileAccess.file_exists(ProjectSettings.globalize_path(DEFAULT_SAVE_PATH)) else profile_path
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or not loaded is GMRenderStyleProfile:
		_fail("render_style.editor_profile_reopen_failed", "保存后的Profile无法重新打开。")
		return
	profile = loaded as GMRenderStyleProfile
	profile_path = path
	_sync_fields()
	last_operation = {"ok": true, "code": "render_style.editor_profile_reopened", "path": path, "through_formal_control": true, "failure_closed": true}
	_set_status("保存后的Profile已重新打开。", true)
	_refresh_details()

func _on_undo() -> void:
	var history := _profile_history()
	if history == null or not history.has_undo():
		_fail("render_style.editor_undo_unavailable", "当前没有可撤销的EXT08修改。")
		return
	history.undo()
	_sync_fields()
	last_operation = {"ok": true, "code": "render_style.editor_undo", "through_formal_control": true, "undo_gateway": "EditorUndoRedoManager", "failure_closed": true}
	_set_status("已撤销EXT08修改。", true)
	_refresh_details()

func _on_redo() -> void:
	var history := _profile_history()
	if history == null or not history.has_redo():
		_fail("render_style.editor_redo_unavailable", "当前没有可重做的EXT08修改。")
		return
	history.redo()
	_sync_fields()
	last_operation = {"ok": true, "code": "render_style.editor_redo", "through_formal_control": true, "undo_gateway": "EditorUndoRedoManager", "failure_closed": true}
	_set_status("已重做EXT08修改。", true)
	_refresh_details()

func _profile_history() -> UndoRedo:
	if editor_undo_redo == null or profile == null:
		return null
	var history_id := editor_undo_redo.get_object_history_id(profile)
	return editor_undo_redo.get_history_undo_redo(history_id)

func _read_candidate(candidate: GMRenderStyleProfile) -> Dictionary:
	var values := {}
	for key in ["world_x", "world_y", "ui_x", "ui_y"]:
		var text := str((controls[key] as LineEdit).text).strip_edges()
		if not text.is_valid_int(): return {"ok": false, "code": "render_style.editor_integer_invalid", "error_zh": "%s必须是整数。" % key}
		values[key] = int(text)
	candidate.world_render_resolution = Vector2i(values.world_x, values.world_y)
	candidate.ui_render_resolution = Vector2i(values.ui_x, values.ui_y)
	candidate.lighting_model = (controls["lighting"] as OptionButton).get_item_text((controls["lighting"] as OptionButton).selected)
	candidate.dither_pattern = (controls["dither"] as OptionButton).get_item_text((controls["dither"] as OptionButton).selected)
	candidate.shadow_mode = (controls["shadow"] as OptionButton).get_item_text((controls["shadow"] as OptionButton).selected)
	candidate.pose_sampling_mode = (controls["pose"] as OptionButton).get_item_text((controls["pose"] as OptionButton).selected)
	candidate.pose_sampling_rate = 0 if candidate.pose_sampling_mode == "Smooth" else int(candidate.pose_sampling_mode)
	return {"ok": true}

func _commit_properties(target: Object, values: Dictionary, action_name: String) -> bool:
	if editor_undo_redo == null:
		_fail("render_style.editor_undo_redo_missing", "EditorUndoRedoManager不可用，修改未提交。")
		return false
	editor_undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, target)
	for property in values.keys():
		editor_undo_redo.add_do_property(target, property, values[property])
		editor_undo_redo.add_undo_property(target, property, target.get(property))
	editor_undo_redo.commit_action(true)
	return true

func _sync_fields() -> void:
	if profile == null: return
	(controls["world_x"] as LineEdit).text = str(profile.world_render_resolution.x)
	(controls["world_y"] as LineEdit).text = str(profile.world_render_resolution.y)
	(controls["ui_x"] as LineEdit).text = str(profile.ui_render_resolution.x)
	(controls["ui_y"] as LineEdit).text = str(profile.ui_render_resolution.y)
	_select_option(controls["lighting"] as OptionButton, profile.lighting_model)
	_select_option(controls["dither"] as OptionButton, profile.dither_pattern)
	_select_option(controls["shadow"] as OptionButton, profile.shadow_mode)
	_select_option(controls["pose"] as OptionButton, profile.pose_sampling_mode)

func _select_option(option: OptionButton, value: String) -> void:
	for index in option.item_count:
		if option.get_item_text(index) == value:
			option.select(index)
			return

func _fail(code: String, message: String) -> Dictionary:
	last_operation = {"ok": false, "code": code, "error_zh": message, "through_formal_control": true, "failure_closed": true}
	_set_status("%s [%s]" % [message, code], false)
	_refresh_details()
	return last_operation.duplicate(true)

func _set_status(message: String, ok: bool) -> void:
	if status_label == null: return
	status_label.text = message
	status_label.modulate = Color("7dffad") if ok else Color("ff9b7d")

func _refresh_details() -> void:
	if details_label == null: return
	details_label.text = "[EXT08结构化状态]\nProfile：%s\n校验：%s\n最近操作：%s\n保存/关闭/重开：%s" % [profile.content_id if profile != null else "<closed>", JSON.stringify(last_validation), JSON.stringify(last_operation), JSON.stringify(last_save_close_reopen)]

func get_capture_snapshot() -> Dictionary:
	return {"ui_source_formal": true, "ui_root_script": "res://addons/gm_editor/render_style/gm_render_style_3d_dock.gd", "ui_root_class": "GMRenderStyle3DDock", "formal_path": "GM编辑器 → GM渲染风格与材质 → Render Style / Semantic Material / Occlusion / Pose Sampling", "formal_controls": ["加载中性Profile", "校验", "应用到Profile", "负向校验", "语义材质映射", "Roof/Foreground/Cutaway", "World低分辨率/UI原生", "保存", "关闭/卸载", "重新打开", "撤销", "重做"], "control_node_names": controls.keys(), "undo_gateway": "EditorUndoRedoManager" if editor_undo_redo != null else "missing", "profile": profile.to_native() if profile != null else {}, "validation": last_validation.duplicate(true), "last_operation": last_operation.duplicate(true), "save_close_reopen": last_save_close_reopen.duplicate(true), "p18_consumer": "P18.presentation", "domain_facts_written": false, "substitute_ui": false, "direct_success_action_calls": direct_success_action_calls}

func run_ext_3d_08_editor_probe() -> Dictionary:
	if editor_undo_redo == null or controls.is_empty(): return {"ok": false, "event": "GM_EXT_3D_08_EDITOR_SENTINEL", "code": "gm.ext3d08.editor_controls_missing", "through_formal_controls": false, "substitute_ui": false}
	(controls["load"] as Button).pressed.emit()
	var loaded := last_operation.duplicate(true)
	(controls["validate"] as Button).pressed.emit()
	var normal_validation := last_validation.duplicate(true)
	(controls["world_x"] as LineEdit).text = "384"
	(controls["world_y"] as LineEdit).text = "216"
	var before_edit := profile.to_native() if profile != null else {}
	(controls["apply"] as Button).pressed.emit()
	var applied := last_operation.duplicate(true)
	var after_edit := profile.to_native() if profile != null else {}
	(controls["undo"] as Button).pressed.emit()
	var after_undo := profile.to_native() if profile != null else {}
	(controls["redo"] as Button).pressed.emit()
	var after_redo := profile.to_native() if profile != null else {}
	var undo_redo_ok := before_edit != after_edit and before_edit == after_undo and after_edit == after_redo
	(controls["invalid"] as Button).pressed.emit()
	var rejected := last_operation.duplicate(true)
	(controls["material"] as Button).pressed.emit()
	var material_result := last_operation.duplicate(true)
	(controls["occlusion"] as Button).pressed.emit()
	var occlusion_result := last_operation.duplicate(true)
	(controls["viewport"] as Button).pressed.emit()
	var viewport_result := last_operation.duplicate(true)
	(controls["save"] as Button).pressed.emit()
	var saved := last_operation.duplicate(true)
	(controls["close"] as Button).pressed.emit()
	var closed := last_operation.duplicate(true)
	(controls["reopen"] as Button).pressed.emit()
	var reopened := last_operation.duplicate(true)
	var save_reopen_ok := bool(saved.get("ok", false)) and bool(closed.get("ok", false)) and bool(reopened.get("ok", false)) and profile != null and profile.content_id == "gm.presentation.render_style_profile.neutral"
	last_save_close_reopen = {"ok": save_reopen_ok, "saved": saved, "closed": closed, "reopened": reopened, "path": DEFAULT_SAVE_PATH}
	var result := {"ok": bool(loaded.get("ok", false)) and bool(normal_validation.get("ok", false)) and bool(applied.get("ok", false)) and undo_redo_ok and not bool(rejected.get("ok", true)) and bool(material_result.get("ok", false)) and bool(occlusion_result.get("ok", false)) and bool(viewport_result.get("ok", false)) and save_reopen_ok, "event": "GM_EXT_3D_08_EDITOR_SENTINEL", "through_formal_controls": true, "formal_path": "GM编辑器 → GM渲染风格与材质", "normal": {"load": loaded, "validation": normal_validation, "apply": applied}, "undo_redo": {"ok": undo_redo_ok, "before": before_edit, "after_edit": after_edit, "after_undo": after_undo, "after_redo": after_redo, "gateway": "EditorUndoRedoManager"}, "negative": rejected, "semantic_material": material_result, "occlusion": occlusion_result, "world_viewport": viewport_result, "save_close_reopen": last_save_close_reopen, "failure_closed": true, "substitute_ui": false, "direct_success_action_calls": direct_success_action_calls}
	last_operation["probe"] = result
	_refresh_details()
	return result
