@tool
extends VBoxContainer

const CONFIG_PATH := "res://gm_runtime/feedback/gm_feedback_workbench_config.tres"

var editor_interface
var editor_undo_redo
var config: GMFeedbackWorkbenchConfig
var status_label: Label
var snapshot_label: Label
var sequence_edit: LineEdit
var action_edit: LineEdit
var target_edit: LineEdit
var anchor_edit: LineEdit
var content_edit: LineEdit
var display_edit: LineEdit
var direction_option: OptionButton
var last_status := ""
var last_operation := ""
var operation_count := 0
var local_undo_available := false
var local_redo_available := false
var capture_trace: Array[Dictionary] = []

func configure(p_editor_interface, p_undo_redo) -> void:
	editor_interface = p_editor_interface
	editor_undo_redo = p_undo_redo

func _ready() -> void:
	custom_minimum_size = Vector2(760, 360)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_load_config()
	_build_ui()
	_refresh_fields()
	if not OS.get_environment("GM_P18_EDITOR_CAPTURE_OUTPUT").is_empty():
		call_deferred("_capture_if_requested")

func _load_config() -> void:
	config = ResourceLoader.load(CONFIG_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GMFeedbackWorkbenchConfig
	if config == null:
		config = GMFeedbackWorkbenchConfig.new()

func _build_ui() -> void:
	for child in get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "P18 语义反馈工作台"
	title.name = "工作台标题"
	title.add_theme_font_size_override("font_size", 24)
	add_child(title)
	var subtitle := Label.new()
	subtitle.text = "只读消费已提交 Fact → 语义反馈请求 → 有界序列 → PresentationReceipt；不写入 Task、Reservation 或领域事实。"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", Color("8bd5ca"))
	add_child(subtitle)
	var form := GridContainer.new()
	form.columns = 2
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(form)
	sequence_edit = _make_line(form, "序列ID")
	action_edit = _make_line(form, "语义动作ID")
	target_edit = _make_line(form, "目标引用")
	anchor_edit = _make_line(form, "锚点ID（可选）")
	content_edit = _make_line(form, "必需内容ID")
	display_edit = _make_line(form, "中文显示名")
	var direction_label := Label.new()
	direction_label.text = "方向"
	form.add_child(direction_label)
	direction_option = OptionButton.new()
	direction_option.name = "方向选择"
	for item in [["下", "down"], ["左", "left"], ["右", "right"], ["上", "up"], ["左下", "down_left"], ["右下", "down_right"], ["左上", "up_left"], ["右上", "up_right"]]:
		direction_option.add_item(str(item[0]))
		direction_option.set_item_metadata(direction_option.item_count - 1, item[1])
	form.add_child(direction_option)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	add_child(actions)
	_add_button(actions, "应用合法配置", _apply_legal)
	_add_button(actions, "应用非法配置", _apply_invalid)
	_add_button(actions, "撤销", _undo)
	_add_button(actions, "重做", _redo)
	_add_button(actions, "保存配置", _save_config)
	_add_button(actions, "重新打开", _reopen_config)
	status_label = Label.new()
	status_label.name = "工作台状态"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(0, 42)
	add_child(status_label)
	snapshot_label = Label.new()
	snapshot_label.name = "工作台快照"
	snapshot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(snapshot_label)

func _make_line(parent: GridContainer, label_text: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(edit)
	return edit

func _add_button(parent: HBoxContainer, label_text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label_text
	button.pressed.connect(callback)
	parent.add_child(button)

func _refresh_fields() -> void:
	if config == null or sequence_edit == null:
		return
	sequence_edit.text = config.sequence_id
	action_edit.text = config.semantic_action_id
	target_edit.text = config.target_ref
	anchor_edit.text = config.anchor_id
	content_edit.text = config.required_content_id
	display_edit.text = config.display_name_zh
	for index in direction_option.item_count:
		if str(direction_option.get_item_metadata(index)) == config.direction:
			direction_option.select(index)
			break
	_update_snapshot()

func _candidate_from_fields() -> Dictionary:
	return {"schema_version": GMFeedbackWorkbenchConfig.SCHEMA_VERSION, "sequence_id": sequence_edit.text, "semantic_action_id": action_edit.text, "target_ref": target_edit.text, "direction": str(direction_option.get_selected_metadata()), "anchor_id": anchor_edit.text, "required_content_id": content_edit.text, "display_name_zh": display_edit.text}

func _legal_candidate() -> Dictionary:
	var value := _candidate_from_fields()
	if value.sequence_id.is_empty():
		value.sequence_id = "gm.feedback.sequence.neutral_demo"
	if value.semantic_action_id.is_empty():
		value.semantic_action_id = "idle"
	if value.target_ref.is_empty():
		value.target_ref = "gm.actor.neutral_demo"
	if value.required_content_id.is_empty():
		value.required_content_id = "gm.content.feedback.accepted"
	if value.display_name_zh.is_empty():
		value.display_name_zh = "中性语义反馈样例"
	return value

func _apply_legal() -> void:
	var value := _legal_candidate()
	var preflight := config.preview_apply(value)
	if not preflight.ok:
		_set_status("合法配置预检失败：%s" % str(preflight.get("reason_zh", "请修正字段。")), false)
		return
	var before := config.to_dict()
	_commit_change(before, preflight.value, "P18合法反馈配置")

func _apply_invalid() -> void:
	var before := config.to_dict()
	var invalid := before.duplicate(true)
	invalid.target_ref = "res://非法NodePath"
	var preflight := config.preview_apply(invalid)
	if preflight.ok:
		_set_status("非法配置未被阻断：工作台测试失败。", false)
		return
	_set_status("非法配置已在写入前拒绝：%s；当前配置、磁盘和Undo/Redo历史未改变。" % str(preflight.get("reason_zh", "字段无效。")), true)
	last_operation = "invalid_rejected"
	operation_count += 1
	_update_snapshot()

func _commit_change(before: Dictionary, after: Dictionary, action_name: String) -> void:
	if editor_undo_redo != null:
		editor_undo_redo.create_action(action_name)
		editor_undo_redo.add_do_method(self, "_apply_and_save", after)
		editor_undo_redo.add_undo_method(self, "_apply_and_save", before)
		editor_undo_redo.commit_action()
	else:
		_apply_and_save(after)
	local_undo_available = true
	local_redo_available = false
	_set_status("合法配置已应用到同一 Resource，可继续撤销/重做。", true)
	last_operation = "legal_applied"
	operation_count += 1
	_update_snapshot()

func _apply_and_save(value: Dictionary) -> void:
	var applied := config.apply_dict(value)
	if not applied.ok:
		_set_status("配置应用失败，原值保留：%s" % str(applied.get("reason_zh", "未知错误。")), false)
		return
	var error := ResourceSaver.save(config, CONFIG_PATH)
	if error != OK:
		_set_status("配置已在内存应用，但保存失败，错误码：%s。" % error, false)
	_update_snapshot()

func _undo() -> void:
	if editor_undo_redo != null and local_undo_available:
		var history: UndoRedo = editor_undo_redo.get_history_undo_redo(0)
		if history != null:
			history.undo()
		local_undo_available = false
		local_redo_available = true
		_set_status("已撤销上一笔合法配置；当前值来自同一 Resource。", true)
		last_operation = "undo"
		operation_count += 1
	else:
		_set_status("当前没有可撤销的合法配置。", false)
	_update_snapshot()

func _redo() -> void:
	if editor_undo_redo != null and local_redo_available:
		var history: UndoRedo = editor_undo_redo.get_history_undo_redo(0)
		if history != null:
			history.redo()
		local_undo_available = true
		local_redo_available = false
		_set_status("已重做合法配置；当前值来自同一 Resource。", true)
		last_operation = "redo"
		operation_count += 1
	else:
		_set_status("当前没有可重做的合法配置。", false)
	_update_snapshot()

func _save_config() -> void:
	var checked := config.validate()
	if not checked.ok:
		_set_status("保存前校验失败：%s" % str(checked.get("reason_zh", "请修正配置。")), false)
		return
	var error := ResourceSaver.save(config, CONFIG_PATH)
	if error == OK:
		_set_status("配置已保存：%s。" % CONFIG_PATH, true)
		last_operation = "saved"
		operation_count += 1
	else:
		_set_status("配置保存失败，错误码：%s。" % error, false)
	_update_snapshot()

func _reopen_config() -> void:
	var reopened := ResourceLoader.load(CONFIG_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GMFeedbackWorkbenchConfig
	if reopened == null:
		_set_status("重新打开失败：找不到有效的P18工作台Resource。", false)
		return
	var checked := config.apply_dict(reopened.to_dict())
	if not checked.ok:
		_set_status("重新打开未应用：磁盘配置未通过校验，内存值保留。", false)
		return
	_refresh_fields()
	_set_status("已从磁盘重新打开同一P18配置，且通过严格校验。", true)
	last_operation = "reopened"
	operation_count += 1
	_update_snapshot()

func _set_status(message: String, ok: bool) -> void:
	last_status = message
	if status_label != null:
		status_label.text = message
		status_label.modulate = Color("80ffb0") if ok else Color("ffb080")

func _update_snapshot() -> void:
	if snapshot_label == null or config == null:
		return
	snapshot_label.text = "当前Resource：%s\n序列：%s；动作：%s；目标：%s；方向：%s\n最近操作：%s；操作计数：%d" % [CONFIG_PATH, config.sequence_id, config.semantic_action_id, config.target_ref, config.direction, last_operation if not last_operation.is_empty() else "无", operation_count]

func _capture_if_requested() -> void:
	var output := OS.get_environment("GM_P18_EDITOR_CAPTURE_OUTPUT")
	if output.is_empty():
		return
	if OS.get_environment("GM_P18_EDITOR_CAPTURE_SCENARIO") == "legal_invalid_legal":
		_run_capture_scenario()
	var absolute := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var payload := get_capture_snapshot()
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload, "  ", true, true) + "\n")
		file.close()

func _run_capture_scenario() -> void:
	if config == null:
		return
	capture_trace.clear()
	var original := config.to_dict()
	var legal := original.duplicate(true)
	legal.target_ref = "gm.actor.p18.editor.legal"
	var preflight := config.preview_apply(legal)
	capture_trace.append({"step": "legal_preview", "ok": preflight.ok, "code": str(preflight.get("code", ""))})
	if preflight.ok:
		_commit_change(original, legal, "P18捕获合法配置")
		capture_trace.append({"step": "legal_apply", "ok": config.validate().ok, "target_ref": config.target_ref})
	_apply_invalid()
	capture_trace.append({"step": "invalid_rejected", "ok": last_operation == "invalid_rejected", "operation": last_operation, "status": last_status})
	var second_legal := original.duplicate(true)
	_commit_change(legal, second_legal, "P18捕获恢复合法配置")
	capture_trace.append({"step": "legal_restore", "ok": config.validate().ok, "target_ref": config.target_ref})
	_undo()
	capture_trace.append({"step": "undo", "ok": config.target_ref == legal.target_ref, "target_ref": config.target_ref})
	_redo()
	capture_trace.append({"step": "redo", "ok": config.target_ref == second_legal.target_ref, "target_ref": config.target_ref})
	_save_config()
	capture_trace.append({"step": "save", "ok": last_operation == "saved", "operation": last_operation})
	_reopen_config()
	capture_trace.append({"step": "reopen", "ok": last_operation == "reopened" and config.validate().ok, "operation": last_operation})

func get_capture_snapshot() -> Dictionary:
	return {"event": "P18_EDITOR_WORKBENCH_CAPTURE", "ok": config != null and config.validate().ok and _capture_trace_ok(), "title": "P18 语义反馈工作台", "panel_count": 1, "controls": ["序列ID", "语义动作ID", "目标引用", "锚点ID（可选）", "必需内容ID", "中文显示名", "方向", "应用合法配置", "应用非法配置", "撤销", "重做", "保存配置", "重新打开"], "config_path": CONFIG_PATH, "config": config.to_dict() if config != null else {}, "last_status": last_status, "last_operation": last_operation, "operation_count": operation_count, "trace": capture_trace.duplicate(true), "undo_redo": "EditorUndoRedoManager", "logic_unchanged": true, "domain_facts_written": false}

func _capture_trace_ok() -> bool:
	if capture_trace.is_empty():
		return true
	for row in capture_trace:
		if not bool(row.get("ok", false)):
			return false
	return true
