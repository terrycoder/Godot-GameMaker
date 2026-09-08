@tool
class_name GMMovementDock
extends PanelContainer

const PROFILE_FIELDS: Array[String] = ["map_id", "anchor_id", "follow_actor_id", "patrol_route_id", "speed", "acceleration", "stop_distance", "follow_distance", "patrol_loop", "target_map_id", "entry_anchor_id", "exit_anchor_id", "return_anchor_id"]

var editor_plugin: EditorPlugin
var undo_redo: EditorUndoRedoManager
var profile: GMMovementProfile
var resource_path: String = "res://samples/p15_movement/movement_profile.tres"

var kind_option: OptionButton
var map_edit: LineEdit
var anchor_edit: LineEdit
var follow_edit: LineEdit
var route_edit: LineEdit
var speed_spin: SpinBox
var acceleration_spin: SpinBox
var stop_spin: SpinBox
var follow_spin: SpinBox
var loop_check: CheckBox
var target_map_edit: LineEdit
var entry_edit: LineEdit
var exit_edit: LineEdit
var return_edit: LineEdit
var status_label: Label
var apply_button: Button
var save_button: Button
var undo_button: Button
var redo_button: Button

func _init() -> void:
	name = "P15移动能力"
	custom_minimum_size = Vector2(1040, 360)
	_build_ui()

func configure(plugin: EditorPlugin) -> void:
	editor_plugin = plugin
	undo_redo = plugin.get_undo_redo() if plugin != null else null
	if profile == null: profile = GMMovementProfile.new()
	_load_profile_to_controls()

func _build_ui() -> void:
	var root := VBoxContainer.new(); add_child(root)
	var title := Label.new(); title.text = "P15 移动、朝向、跟随、巡逻与旅行配置"; title.add_theme_font_size_override("font_size", 20); root.add_child(title)
	var boundary := Label.new(); boundary.text = "统一入口：玩家 / AI / 脚本  ·  单owner执行  ·  旅行仅生成交接，不创建SceneSession"; boundary.modulate = Color("a9c7d8"); root.add_child(boundary)
	var columns := HBoxContainer.new(); columns.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(columns)
	var movement := _section(columns, "移动参数与目标")
	kind_option = OptionButton.new()
	for row in [["方向移动", "direction"], ["直达位置", "direct"], ["语义锚点", "anchor"], ["跟随角色", "follow"], ["巡逻路线", "patrol"], ["仅调整朝向", "face"], ["取消移动", "cancel"], ["旅行交接", "travel"]]: kind_option.add_item(row[0]); kind_option.set_item_metadata(kind_option.item_count - 1, row[1])
	_add_row(movement, "请求类型", kind_option, "中文显示名与英文稳定值分离。")
	map_edit = _line(movement, "当前地图ID", "map.neutral.alpha")
	anchor_edit = _line(movement, "目标锚点ID", "anchor.destination")
	follow_edit = _line(movement, "跟随角色ID", "actor.partner")
	route_edit = _line(movement, "巡逻路线ID", "route.neutral.loop")
	var parameters := _section(columns, "速度、距离与巡逻")
	speed_spin = _spin(parameters, "速度", 1.0, 2000.0, 120.0)
	acceleration_spin = _spin(parameters, "加速度", 1.0, 5000.0, 480.0)
	stop_spin = _spin(parameters, "停止距离", 0.0, 256.0, 4.0)
	follow_spin = _spin(parameters, "跟随距离", 0.0, 512.0, 24.0)
	loop_check = CheckBox.new(); loop_check.text = "巡逻到末端后循环"; loop_check.button_pressed = true; parameters.add_child(loop_check)
	var travel := _section(columns, "旅行锚点交接（P23延期）")
	target_map_edit = _line(travel, "目标地图ID", "map.neutral.beta")
	entry_edit = _line(travel, "入口锚点ID", "anchor.entry")
	exit_edit = _line(travel, "出口锚点ID", "anchor.exit")
	return_edit = _line(travel, "返回锚点ID", "anchor.return")
	var note := Label.new(); note.text = "只保存稳定ID；不保存NodePath、RID或导航对象。"; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.modulate = Color("d6b875"); travel.add_child(note)
	var actions := HBoxContainer.new(); root.add_child(actions)
	apply_button = Button.new(); apply_button.text = "应用到移动配置"; apply_button.tooltip_text = "使用EditorUndoRedoManager原子更新当前GMMovementProfile。"; apply_button.pressed.connect(_apply_from_controls); actions.add_child(apply_button)
	save_button = Button.new(); save_button.text = "保存移动配置"; save_button.pressed.connect(_save_profile); actions.add_child(save_button)
	undo_button = Button.new(); undo_button.text = "撤销"; undo_button.pressed.connect(_undo); actions.add_child(undo_button)
	redo_button = Button.new(); redo_button.text = "重做"; redo_button.pressed.connect(_redo); actions.add_child(redo_button)
	status_label = Label.new(); status_label.text = "等待配置。"; status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; actions.add_child(status_label)

func _section(parent: HBoxContainer, title_text: String) -> VBoxContainer:
	var panel := PanelContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(panel)
	var box := VBoxContainer.new(); panel.add_child(box)
	var title := Label.new(); title.text = title_text; title.add_theme_font_size_override("font_size", 16); box.add_child(title)
	return box

func _add_row(parent: VBoxContainer, label_text: String, control: Control, tooltip: String = "") -> void:
	var label := Label.new(); label.text = label_text; parent.add_child(label)
	control.tooltip_text = tooltip if not tooltip.is_empty() else label_text
	parent.add_child(control)

func _line(parent: VBoxContainer, label_text: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new(); edit.placeholder_text = placeholder; _add_row(parent, label_text, edit); return edit

func _spin(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, initial: float) -> SpinBox:
	var spin := SpinBox.new(); spin.min_value = minimum; spin.max_value = maximum; spin.value = initial; spin.step = 1.0; _add_row(parent, label_text, spin); return spin

func _apply_from_controls() -> void:
	var built := _candidate_from_controls()
	if not built.ok: _show_failure(built); return
	var candidate: GMMovementProfile = built.candidate
	var values: Dictionary = built.values
	if profile == null:
		profile = candidate
		_show_status("移动配置已应用（新建配置，当前未连接撤销历史）。")
		return
	var before := _profile_values(profile)
	if before == values:
		_show_status("移动配置未变化，无需新增撤销记录。")
		return
	if undo_redo != null:
		undo_redo.create_action("应用P15移动配置")
		for key in PROFILE_FIELDS:
			undo_redo.add_do_property(profile, key, values[key]); undo_redo.add_undo_property(profile, key, before[key])
		undo_redo.add_do_method(self, "_show_status", "移动配置已应用，可撤销或保存。")
		undo_redo.add_undo_method(self, "_show_status", "已撤销P15移动配置。")
		undo_redo.commit_action()
	else:
		_commit_values(profile, values)
		_show_status("移动配置已应用（当前未连接编辑器撤销管理器）。")

func _save_profile() -> void:
	var built := _candidate_from_controls()
	if not built.ok: _show_failure(built); return
	var path_check := _validate_save_path(resource_path)
	if not path_check.ok: _show_failure(path_check); return
	var candidate: GMMovementProfile = built.candidate
	var target_absolute: String = path_check.absolute
	var temporary_path := "%s/.%s.p15_candidate_%d.tres" % [resource_path.get_base_dir(), resource_path.get_file().get_basename(), Time.get_ticks_usec()]
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var save_error := ResourceSaver.save(candidate, temporary_path)
	if save_error != OK:
		_cleanup_temporary(temporary_absolute)
		_show_failure(_failure("movement.profile_save_failed", "移动配置候选文件保存失败。", "请检查保存目录权限、路径长度或磁盘状态。", {"resource_error": save_error, "temporary_cleaned": not FileAccess.file_exists(temporary_absolute)}))
		return
	var reopened := ResourceLoader.load(temporary_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GMMovementProfile
	var reopen_check := reopened.validate_profile() if reopened != null else _failure("movement.profile_reopen_failed", "移动配置候选文件无法独立重开。", "请检查资源格式与依赖后重试。")
	if reopened == null or not reopen_check.ok or _profile_values(reopened) != built.values:
		_cleanup_temporary(temporary_absolute)
		_show_failure(_failure("movement.profile_reopen_failed", "移动配置候选文件独立重开校验失败。", "请检查资源序列化与依赖后重试。", {"temporary_cleaned": not FileAccess.file_exists(temporary_absolute)}))
		return
	# 同目录rename是正式文件的原子替换边界；失败时原文件仍在，live Profile尚未写入。
	var replace_error := DirAccess.rename_absolute(temporary_absolute, target_absolute)
	if replace_error != OK:
		_cleanup_temporary(temporary_absolute)
		_show_failure(_failure("movement.profile_replace_failed", "移动配置正式文件原子替换失败。", "请关闭占用文件的程序或更换可写路径。", {"resource_error": replace_error, "temporary_cleaned": not FileAccess.file_exists(temporary_absolute)}))
		return
	if profile == null: profile = candidate
	else: _commit_values(profile, built.values)
	_show_status("移动配置已保存并同步当前配置：%s（保存不新增撤销记录）。" % resource_path)

func _candidate_from_controls() -> Dictionary:
	if map_edit == null or anchor_edit == null or follow_edit == null or route_edit == null or speed_spin == null or acceleration_spin == null or stop_spin == null or follow_spin == null or loop_check == null or target_map_edit == null or entry_edit == null or exit_edit == null or return_edit == null or kind_option == null:
		return _failure("movement.profile_controls_missing", "移动配置界面控件不完整。", "请重新打开GM移动能力面板。")
	var values := {"map_id": map_edit.text, "anchor_id": anchor_edit.text, "follow_actor_id": follow_edit.text, "patrol_route_id": route_edit.text, "speed": 0.0, "acceleration": 0.0, "stop_distance": 0.0, "follow_distance": 0.0, "patrol_loop": loop_check.button_pressed, "target_map_id": target_map_edit.text, "entry_anchor_id": entry_edit.text, "exit_anchor_id": exit_edit.text, "return_anchor_id": return_edit.text}
	for key in ["map_id", "anchor_id", "follow_actor_id", "patrol_route_id", "target_map_id", "entry_anchor_id", "exit_anchor_id", "return_anchor_id"]:
		if typeof(values[key]) != TYPE_STRING: return _failure("movement.profile_control_type_invalid", "移动配置ID控件“%s”类型错误。" % key, "请重新打开面板后输入稳定ID。")
	var numeric_controls := {"speed": speed_spin, "acceleration": acceleration_spin, "stop_distance": stop_spin, "follow_distance": follow_spin}
	for key in numeric_controls:
		var numeric_result := _read_numeric_control(numeric_controls[key], key)
		if not numeric_result.ok: return numeric_result
		values[key] = numeric_result.value
	if typeof(values.patrol_loop) != TYPE_BOOL: return _failure("movement.profile_control_type_invalid", "巡逻循环控件类型错误。", "请重新打开面板。")
	var candidate := GMMovementProfile.new()
	_commit_values(candidate, values)
	var profile_check := candidate.validate_profile()
	if not profile_check.ok: return profile_check
	var kind := str(kind_option.get_item_metadata(kind_option.selected))
	var relation_check := _validate_candidate_for_kind(candidate, kind)
	if not relation_check.ok: return relation_check
	return {"ok": true, "candidate": candidate, "values": _profile_values(candidate), "kind": kind}

func _read_numeric_control(spin: SpinBox, field: String) -> Dictionary:
	var raw := spin.get_line_edit().text.strip_edges()
	var lower := raw.to_lower()
	if lower in ["nan", "+nan", "-nan", "inf", "+inf", "-inf", "infinity", "+infinity", "-infinity"]:
		return _failure("movement.profile_numeric_nonfinite", "移动配置数值控件“%s”必须是有限数值。" % field, "请移除NaN或Infinity后重试。")
	if not raw.is_valid_float(): return _failure("movement.profile_control_type_invalid", "移动配置数值控件“%s”不是有效数字。" % field, "请输入有限十进制数值。")
	var value := raw.to_float()
	if not is_finite(value): return _failure("movement.profile_numeric_nonfinite", "移动配置数值控件“%s”必须是有限数值。" % field, "请移除NaN或Infinity后重试。")
	return {"ok": true, "value": value}

func _validate_candidate_for_kind(candidate: GMMovementProfile, kind: String) -> Dictionary:
	match kind:
		"anchor":
			if candidate.anchor_id.is_empty(): return _failure("movement.profile_anchor_missing", "锚点移动缺少目标锚点稳定ID。", "请填写目标锚点ID。")
		"follow":
			if candidate.follow_actor_id.is_empty(): return _failure("movement.profile_follow_actor_missing", "跟随移动缺少目标角色稳定ID。", "请填写跟随角色ID。")
		"patrol":
			if candidate.patrol_route_id.is_empty(): return _failure("movement.profile_route_missing", "巡逻移动缺少路线稳定ID。", "请填写巡逻路线ID。")
		"travel":
			if candidate.target_map_id.is_empty() or candidate.entry_anchor_id.is_empty() or candidate.exit_anchor_id.is_empty() or candidate.return_anchor_id.is_empty(): return _failure("movement.profile_travel_incomplete", "旅行交接缺少目标地图或入口、出口、返回锚点。", "请完整填写四个旅行稳定ID。")
		"direct", "direction", "face", "cancel": pass
		_: return _failure("movement.profile_kind_invalid", "移动配置请求类型无效。", "请从正式下拉列表重新选择请求类型。")
	return {"ok": true}

func _validate_save_path(path: String) -> Dictionary:
	if path.is_empty() or path != path.strip_edges() or not path.begins_with("res://") or not path.to_lower().ends_with(".tres") or ".." in path or "\\" in path:
		return _failure("movement.profile_save_path_invalid", "移动配置保存路径无效。", "请使用项目内现有目录下的.tres路径。")
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute.get_base_dir()) or DirAccess.dir_exists_absolute(absolute):
		return _failure("movement.profile_save_path_invalid", "移动配置保存目录不存在或目标是目录。", "请先选择项目内现有可写目录。")
	return {"ok": true, "absolute": absolute}

func _profile_values(value: GMMovementProfile) -> Dictionary:
	var result: Dictionary = {}
	for key in PROFILE_FIELDS: result[key] = value.get(key)
	return result

func _commit_values(target: GMMovementProfile, values: Dictionary) -> void:
	for key in PROFILE_FIELDS: target.set(key, values[key])

func _cleanup_temporary(absolute: String) -> void:
	if FileAccess.file_exists(absolute): DirAccess.remove_absolute(absolute)

func _show_failure(failure: Dictionary) -> void:
	_show_status("%s 修复建议：%s（%s）" % [str(failure.get("reason_zh", "移动配置操作失败。")), str(failure.get("fix_zh", "请修正后重试。")), str(failure.get("code", "movement.profile_operation_failed"))])

func _failure(code: String, reason_zh: String, fix_zh: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "error_zh": reason_zh, "fix_zh": fix_zh, "details": details}

func _undo() -> void:
	var history := _history()
	if history != null and history.has_undo(): history.undo(); _load_profile_to_controls()

func _redo() -> void:
	var history := _history()
	if history != null and history.has_redo(): history.redo(); _load_profile_to_controls()

func _history() -> UndoRedo:
	if undo_redo == null or profile == null: return null
	return undo_redo.get_history_undo_redo(undo_redo.get_object_history_id(profile))

func _load_profile_to_controls() -> void:
	if profile == null: return
	map_edit.text = profile.map_id; anchor_edit.text = profile.anchor_id; follow_edit.text = profile.follow_actor_id; route_edit.text = profile.patrol_route_id
	speed_spin.value = profile.speed; acceleration_spin.value = profile.acceleration; stop_spin.value = profile.stop_distance; follow_spin.value = profile.follow_distance; loop_check.button_pressed = profile.patrol_loop
	target_map_edit.text = profile.target_map_id; entry_edit.text = profile.entry_anchor_id; exit_edit.text = profile.exit_anchor_id; return_edit.text = profile.return_anchor_id

func _show_status(message: String) -> void:
	status_label.text = message

func set_capture_profile(next_profile: GMMovementProfile, path: String) -> void:
	profile = next_profile; resource_path = path; _load_profile_to_controls()

func get_capture_snapshot() -> Dictionary:
	return {"title": "P15 移动、朝向、跟随、巡逻与旅行配置", "display_language": "zh-CN", "kind_display": kind_option.get_item_text(kind_option.selected), "kind_value": str(kind_option.get_item_metadata(kind_option.selected)), "map_id": map_edit.text, "anchor_id": anchor_edit.text, "follow_actor_id": follow_edit.text, "route_id": route_edit.text, "travel": {"target_map_id": target_map_edit.text, "entry_anchor_id": entry_edit.text, "exit_anchor_id": exit_edit.text, "return_anchor_id": return_edit.text}, "status_zh": status_label.text, "resource_path": resource_path, "uses_editor_undo_redo": undo_redo != null, "scene_session_created": false}
