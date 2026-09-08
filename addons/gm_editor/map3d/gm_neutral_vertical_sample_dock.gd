@tool
class_name GMNeutralVerticalSampleDock
extends VBoxContainer

const PROFILE_SCRIPT := preload("res://gm_runtime/vertical_sample/gm_neutral_vertical_sample_profile.gd")
const DEFAULT_PATH := "res://gm_runtime/vertical_sample/" + "gm_ext_3d_10_profile.tres"

var editor_interface: EditorInterface
var undo_redo: EditorUndoRedoManager
var profile: GMNeutralVerticalSampleProfile
var profile_path := DEFAULT_PATH
var profile_load_error: Dictionary = {}
var name_box: LineEdit
var npc_box: SpinBox
var status_label: Label
var create_button: Button
var apply_button: Button
var save_button: Button
var reopen_button: Button

func configure(p_editor_interface: EditorInterface, p_undo_redo: EditorUndoRedoManager, p_profile_path: String = DEFAULT_PATH) -> void:
	editor_interface = p_editor_interface
	undo_redo = p_undo_redo
	profile_path = str(p_profile_path).strip_edges() if not str(p_profile_path).strip_edges().is_empty() else DEFAULT_PATH
	_build_ui()
	_load_default()

func _build_ui() -> void:
	if get_child_count() > 0: return
	var title := Label.new(); title.text = "Planar 3D 中性纵向样板"; title.add_theme_font_size_override("font_size", 22); add_child(title)
	var hint := Label.new(); hint.text = "同一规则链：Task → Planner → 移动 → Facility/Process → Transaction → Fact/Change/Cue；可切换2D对照。"; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(hint)
	var row := HBoxContainer.new(); add_child(row)
	name_box = LineEdit.new(); name_box.placeholder_text = "中文样板名称"; name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(name_box)
	npc_box = SpinBox.new(); npc_box.min_value = 10; npc_box.max_value = 64; npc_box.value = 10; npc_box.tooltip_text = "模块化NPC数量（至少10）"; row.add_child(npc_box)
	create_button = _button("新建中性样板", "新建包含小院、一层、二层、桥面、Facility与10个NPC的中性配置。")
	apply_button = _button("应用配置", "通过正式Undo/Redo写入当前Profile。")
	save_button = _button("保存样板", "保存当前Profile资源。")
	reopen_button = _button("关闭并重新打开", "从磁盘重新加载并核对稳定引用。")
	var actions := HBoxContainer.new(); add_child(actions)
	for button in [create_button, apply_button, save_button, reopen_button]: actions.add_child(button)
	create_button.pressed.connect(_on_create_pressed)
	apply_button.pressed.connect(_on_apply_pressed)
	save_button.pressed.connect(_on_save_pressed)
	reopen_button.pressed.connect(_on_reopen_pressed)
	status_label = Label.new(); status_label.text = "等待操作"; status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(status_label)

func _button(text_value: String, tooltip: String) -> Button:
	var button := Button.new(); button.text = text_value; button.tooltip_text = tooltip; return button

func _load_default() -> void:
	_load_profile_at(profile_path)

func _load_profile_at(path: String) -> Dictionary:
	var requested_path := str(path).strip_edges()
	if not requested_path.begins_with("res://") or requested_path.get_extension().to_lower() != "tres":
		return _set_profile_load_error(requested_path, {"ok": false, "code": "editor.profile_path_invalid", "reason_zh": "编辑器目标Profile必须是明确的res:// .tres资源。"})
	var loaded := ResourceLoader.load(requested_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded is GMNeutralVerticalSampleProfile:
		return _set_profile_load_error(requested_path, {"ok": false, "code": "editor.profile_load_failed", "reason_zh": "编辑器目标Profile不存在或类型不匹配；拒绝回退到其他资源。"})
	var loaded_profile: GMNeutralVerticalSampleProfile = loaded
	var checked: Dictionary = loaded_profile.validate()
	if not checked.ok:
		return _set_profile_load_error(requested_path, checked)
	profile_path = requested_path
	profile = loaded_profile
	profile_load_error = {}
	_sync_form()
	return {"ok": true, "path": profile_path, "profile_id": profile.profile_id}

func _set_profile_load_error(path: String, error: Dictionary) -> Dictionary:
	profile_path = path
	profile = null
	profile_load_error = error.duplicate(true)
	if is_instance_valid(status_label):
		status_label.text = "目标Profile加载失败：%s" % str(error.get("reason_zh", "未能加载目标资源。"))
	return profile_load_error

func _sync_form() -> void:
	if profile == null: return
	name_box.text = profile.display_name_zh
	npc_box.value = profile.actor_specs.size()

func _on_create_pressed() -> void:
	if profile == null:
		status_label.text = "当前目标Profile未加载，拒绝创建以避免误写其他资源。"
		return
	var candidate := profile.duplicate(true) as GMNeutralVerticalSampleProfile
	if candidate == null:
		status_label.text = "当前目标Profile无法复制，拒绝创建。"
		return
	_set_profile_with_undo(candidate, "新建Planar 3D中性纵向样板")
	status_label.text = "已在当前目标Profile命名空间中创建可编辑副本。"

func _on_apply_pressed() -> void:
	if profile == null: return
	var next_name := name_box.text.strip_edges()
	var next_count := int(npc_box.value)
	if next_name.is_empty() or next_count < 10:
		status_label.text = "校验错误：中文名称不能为空，NPC数量不得少于10；旧状态未改变。"
		return
	var next_actor_specs := _actor_specs_for_count(next_count)
	if next_actor_specs.size() != next_count:
		status_label.text = "校验错误：角色声明数量无法生成；旧状态未改变。"
		return
	var previous_actor_specs: Array[Dictionary] = []
	for actor in profile.actor_specs:
		if actor is Dictionary: previous_actor_specs.append(actor.duplicate(true))
	undo_redo.create_action("应用中性纵向样板配置")
	undo_redo.add_do_property(profile, "display_name_zh", next_name)
	# npc_count is a read-only projection. The authored actor_specs array
	# is the single role-declaration authority persisted by the Profile.
	undo_redo.add_do_property(profile, "actor_specs", next_actor_specs)
	undo_redo.add_undo_property(profile, "display_name_zh", profile.display_name_zh)
	undo_redo.add_undo_property(profile, "actor_specs", previous_actor_specs)
	undo_redo.add_do_method(self, "_sync_form")
	undo_redo.add_undo_method(self, "_sync_form")
	undo_redo.commit_action()
	status_label.text = "配置已应用：已更新真实角色声明，可撤销/重做。"

func _actor_specs_for_count(next_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if profile == null: return result
	for actor in profile.actor_specs:
		if actor is Dictionary: result.append(actor.duplicate(true))
	while result.size() > next_count: result.pop_back()
	var actor_namespace := _identity_namespace("actor")
	var entity_namespace := _identity_namespace("entity")
	var suffix := result.size() + 1
	while result.size() < next_count:
		while _actor_spec_id_exists(result, actor_namespace, entity_namespace, suffix): suffix += 1
		var index := result.size()
		result.append({
			"actor_id": "%s.npc_%02d" % [actor_namespace, suffix],
			"entity_id": "%s.npc_%02d" % [entity_namespace, suffix],
			"spawn_logical": {"x": 5.0 + float(index % 10) * 0.3, "y": 9.7 + float((index / 10) % 2) * 0.3},
			"target_workspot_id": profile.player_target_workspot_id,
		})
		suffix += 1
	return result

func _identity_namespace(kind: String) -> String:
	if profile == null: return "gm.%s.neutral" % kind
	var prefix := "gm.%s." % kind
	var profile_namespace := str(profile.profile_id).trim_prefix("gm.profile.")
	var profile_separator := profile_namespace.find(".")
	if profile_separator > 0: profile_namespace = profile_namespace.substr(0, profile_separator)
	if not profile_namespace.is_empty() and profile_namespace != str(profile.profile_id):
		return prefix + profile_namespace
	for actor in profile.actor_specs:
		if not actor is Dictionary: continue
		var candidate := str(actor.get(kind + "_id", ""))
		if not candidate.begins_with(prefix): continue
		var separator := candidate.find(".", prefix.length())
		if separator > prefix.length(): return candidate.substr(0, separator)
	return prefix + "neutral"

func _actor_spec_id_exists(rows: Array[Dictionary], actor_namespace: String, entity_namespace: String, suffix: int) -> bool:
	var actor_id := "%s.npc_%02d" % [actor_namespace, suffix]
	var entity_id := "%s.npc_%02d" % [entity_namespace, suffix]
	for actor in rows:
		if str(actor.get("actor_id", "")) == actor_id or str(actor.get("entity_id", "")) == entity_id: return true
	return false

func _set_profile_with_undo(candidate: GMNeutralVerticalSampleProfile, action_name: String) -> void:
	var old_profile := profile
	undo_redo.create_action(action_name)
	undo_redo.add_do_property(self, "profile", candidate)
	undo_redo.add_undo_property(self, "profile", old_profile)
	undo_redo.add_do_method(self, "_sync_form")
	undo_redo.add_undo_method(self, "_sync_form")
	undo_redo.commit_action()

func _on_save_pressed() -> void:
	if profile == null: return
	var checked := profile.validate()
	if not checked.ok:
		status_label.text = "保存失败：%s" % checked.reason_zh
		return
	var error := ResourceSaver.save(profile, profile_path)
	status_label.text = "样板已保存。" if error == OK else "保存失败：错误码 %d" % error

func _on_reopen_pressed() -> void:
	var reopened := _load_profile_at(profile_path)
	if not reopened.ok: return
	status_label.text = "关闭并重新打开完成：目标Profile、稳定ID、Surface、Facility、Process与NPC数量已恢复。"

func run_ext_3d_10_editor_probe() -> Dictionary:
	var disk_original := ResourceLoader.load(profile_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not disk_original is GMNeutralVerticalSampleProfile or profile == null:
		return {"event": "GM_EXT_3D_10_EDITOR_SENTINEL", "ok": false, "formal_path": "GM编辑器 → Planar 3D中性纵向样板", "through_formal_controls": true, "substitute_ui": false, "direct_success_action_calls": 0, "failure_state_unchanged": true, "blocked_reason_zh": "目标Profile不可用；拒绝对替代资源误报成功。"}
	var before := profile.to_native() if profile != null else {}
	create_button.pressed.emit()
	name_box.text = "独立中性纵向样板"
	npc_box.value = 12
	apply_button.pressed.emit()
	var applied := profile.to_native()
	var history := undo_redo.get_history_undo_redo(undo_redo.get_object_history_id(profile))
	if history != null and history.has_undo(): history.undo()
	var undone := profile.to_native()
	if history != null and history.has_redo(): history.redo()
	var redone := profile.to_native()
	save_button.pressed.emit()
	reopen_button.pressed.emit()
	var reopened := profile.to_native()
	name_box.text = ""
	apply_button.pressed.emit()
	var failed_unchanged := profile.to_native() == reopened
	var result := {"event": "GM_EXT_3D_10_EDITOR_SENTINEL", "ok": applied.display_name_zh == "独立中性纵向样板" and Array(applied.get("actor_specs", [])).size() == 12 and undone != applied and redone == applied and reopened == applied and failed_unchanged, "formal_path": "GM编辑器 → Planar 3D中性纵向样板", "profile_path": profile_path, "profile_id": profile.profile_id, "identity_namespace": _identity_namespace("actor"), "through_formal_controls": true, "substitute_ui": false, "direct_success_action_calls": 0, "undo_redo": {"before": before, "applied": applied, "undone": undone, "redone": redone}, "save_reopen": reopened, "failure_state_unchanged": failed_unchanged, "labels_zh": [create_button.text, apply_button.text, save_button.text, reopen_button.text], "blocked_reason_zh": status_label.text}
	if disk_original is GMNeutralVerticalSampleProfile and OS.get_environment("GM_EXT_3D_10_EDITOR_PRESERVE_TARGET") != "1":
		ResourceSaver.save(disk_original, profile_path)
		profile = disk_original
		_sync_form()
	return result
