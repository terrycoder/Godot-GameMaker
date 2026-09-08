@tool
extends PanelContainer

const RULE_PATH := "res://gm_runtime/vertical_sample/p26/gm_p26_sample_rules.tres"

var editor_interface: EditorInterface
var editor_undo_redo: EditorUndoRedoManager
var rules: GMP26SampleRules
var capacity_box: SpinBox
var apply_button: Button
var undo_button: Button
var redo_button: Button
var reopen_button: Button
var status_label: Label
var last_operation: Dictionary = {}

func configure(value_editor_interface: EditorInterface, value_undo_redo: EditorUndoRedoManager) -> void:
	editor_interface = value_editor_interface
	editor_undo_redo = value_undo_redo
	_build_ui()
	_reopen()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	add_child(root)
	var title := Label.new(); title.text = "P26 中性跨模块样板规则"; root.add_child(title)
	var help := Label.new(); help.text = "策划调整仓库恢复容量；提交、撤销与重做均进入 EditorUndoRedoManager。"; help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; root.add_child(help)
	var row := HBoxContainer.new(); root.add_child(row)
	var label := Label.new(); label.text = "库存维护恢复容量"; row.add_child(label)
	capacity_box = SpinBox.new(); capacity_box.min_value = 1; capacity_box.max_value = 64; capacity_box.step = 1; row.add_child(capacity_box)
	apply_button = Button.new(); apply_button.text = "应用容量恢复规则"; apply_button.pressed.connect(_apply); root.add_child(apply_button)
	var history := HBoxContainer.new(); root.add_child(history)
	undo_button = Button.new(); undo_button.text = "撤销"; undo_button.pressed.connect(_undo); history.add_child(undo_button)
	redo_button = Button.new(); redo_button.text = "重做"; redo_button.pressed.connect(_redo); history.add_child(redo_button)
	reopen_button = Button.new(); reopen_button.text = "保存关闭重开"; reopen_button.pressed.connect(_save_close_reopen); root.add_child(reopen_button)
	status_label = Label.new(); status_label.text = "等待载入正式规则资源。"; status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; root.add_child(status_label)

func _reopen() -> void:
	rules = ResourceLoader.load(RULE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GMP26SampleRules
	if rules == null:
		_fail("p26.editor.rule_missing", "正式规则资源无法载入，未执行修改。")
		return
	capacity_box.value = rules.recovery_warehouse_slot_limit
	status_label.text = "已载入：%s" % rules.display_name_zh

func _apply() -> void:
	if rules == null or editor_undo_redo == null:
		_fail("p26.editor.undo_redo_missing", "EditorUndoRedoManager不可用，修改已拒绝。")
		return
	var before := rules.recovery_warehouse_slot_limit
	var after := int(capacity_box.value)
	if after <= rules.initial_warehouse_slot_limit:
		_fail("p26.editor.capacity_invalid", "恢复容量必须大于初始容量，资源保持不变。")
		return
	editor_undo_redo.create_action("P26：调整中性仓库恢复容量", UndoRedo.MERGE_DISABLE, rules)
	editor_undo_redo.add_do_property(rules, "recovery_warehouse_slot_limit", after)
	editor_undo_redo.add_undo_property(rules, "recovery_warehouse_slot_limit", before)
	editor_undo_redo.commit_action()
	last_operation = {"ok":true, "code":"p26.editor.capacity_committed", "before":before, "after":after, "through_formal_control":true, "undo_gateway":"EditorUndoRedoManager", "direct_success_action_calls":0}
	status_label.text = "容量规则已通过UndoRedo提交：%d → %d" % [before, after]

func _history() -> UndoRedo:
	if rules == null or editor_undo_redo == null: return null
	return editor_undo_redo.get_history_undo_redo(editor_undo_redo.get_object_history_id(rules))

func _undo() -> void:
	var history := _history()
	if history == null or not history.has_undo(): _fail("p26.editor.undo_unavailable", "没有可撤销的容量规则修改。"); return
	history.undo(); capacity_box.value = rules.recovery_warehouse_slot_limit
	last_operation = {"ok":true, "code":"p26.editor.undo", "through_formal_control":true, "undo_gateway":"EditorUndoRedoManager"}
	status_label.text = "已撤销容量规则修改。"

func _redo() -> void:
	var history := _history()
	if history == null or not history.has_redo(): _fail("p26.editor.redo_unavailable", "没有可重做的容量规则修改。"); return
	history.redo(); capacity_box.value = rules.recovery_warehouse_slot_limit
	last_operation = {"ok":true, "code":"p26.editor.redo", "through_formal_control":true, "undo_gateway":"EditorUndoRedoManager"}
	status_label.text = "已重做容量规则修改。"

func _save_close_reopen() -> void:
	if rules == null: _fail("p26.editor.rule_missing", "规则资源缺失，无法保存。"); return
	var validation := rules.validate()
	if not validation.ok: _fail("p26.editor.validation_failed", "保存被拒绝：%s" % "；".join(validation.errors_zh)); return
	var saved := ResourceSaver.save(rules, RULE_PATH)
	if saved != OK: _fail("p26.editor.save_failed", "规则资源保存失败：%d" % saved); return
	_reopen()
	last_operation = {"ok":true, "code":"p26.editor.save_close_reopen", "through_formal_control":true, "undo_gateway":"EditorUndoRedoManager"}
	status_label.text = "规则已保存、关闭并从磁盘重开。"

func run_p26_editor_probe() -> Dictionary:
	var disk_original := ResourceLoader.load(RULE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	var before := rules.to_dict()
	capacity_box.value = before.recovery_warehouse_slot_limit + 1
	apply_button.pressed.emit()
	var applied := rules.to_dict()
	undo_button.pressed.emit()
	var undone := rules.to_dict()
	redo_button.pressed.emit()
	var redone := rules.to_dict()
	reopen_button.pressed.emit()
	var reopened := rules.to_dict()
	capacity_box.value = rules.initial_warehouse_slot_limit
	apply_button.pressed.emit()
	var failure_unchanged := rules.to_dict() == reopened
	var result := {
		"event":"P26_EDITOR_SENTINEL",
		"ok":applied != before and undone == before and redone == applied and reopened == applied and failure_unchanged,
		"formal_path":"GM编辑器 → P26中性跨模块样板",
		"labels_zh":[apply_button.text, undo_button.text, redo_button.text, reopen_button.text],
		"through_formal_controls":true,
		"undo_gateway":"EditorUndoRedoManager",
		"direct_success_action_calls":0,
		"undo_redo":{"before":before, "applied":applied, "undone":undone, "redone":redone},
		"save_close_reopen":reopened,
		"structured_failure":{"code":last_operation.get("code", ""), "state_unchanged":failure_unchanged, "reason_zh":status_label.text},
	}
	if disk_original is GMP26SampleRules:
		ResourceSaver.save(disk_original, RULE_PATH)
		rules = disk_original
		capacity_box.value = rules.recovery_warehouse_slot_limit
	return result

func _fail(code: String, reason_zh: String) -> void:
	last_operation = {"ok":false, "code":code, "reason_zh":reason_zh, "through_formal_control":true, "state_unchanged":true, "direct_success_action_calls":0}
	if status_label != null: status_label.text = reason_zh
