@tool
class_name GMPlanar3DToolsDock
extends VBoxContainer

const PROFILE_FIELDS := {
	"near_distance": "近景距离", "far_distance": "远景距离", "hysteresis": "距离滞回",
	"max_visible_animated_characters": "可动画角色上限", "max_full_quality_characters": "完整质量角色上限",
	"max_skinned_meshes": "蒙皮网格上限", "animation_update_budget": "每帧动画更新上限",
	"feature_module_budget": "附加模块上限", "mid_sampling_hz": "中景采样率", "far_sampling_hz": "远景采样率",
	"animation_budget_ms": "动画耗时预算（毫秒）", "frame_warning_ms": "帧耗时警戒（毫秒）"}
var editor: EditorInterface
var undo: EditorUndoRedoManager
var center: GMErrorCenter
var library := GMContentLibrary.new()
var resources: Array = []
var fields: Dictionary = {}
var buttons: Dictionary = {}
var paths: TextEdit
var result_label: Label
var errors_list: ItemList
var last_result: Dictionary = {}
var _dialog: EditorFileDialog
var _history_context := Resource.new()

func configure(p_editor: EditorInterface, p_undo: EditorUndoRedoManager, p_center: GMErrorCenter) -> void:
	editor = p_editor
	undo = p_undo
	center = p_center

func _ready() -> void:
	name = "GMPlanar3DTools"
	custom_minimum_size = Vector2(700, 420)
	var title := Label.new()
	title.text = "平面3D预算与验证｜仅修复安全表现字段，修改可撤销"
	add_child(title)
	var row := HBoxContainer.new()
	add_child(row)
	_button(row, "选择多个资源", "choose", func(): _dialog.popup_centered_ratio(0.6))
	_button(row, "加载路径", "load", _load_paths)
	_button(row, "验证并定位错误", "validate", _validate)
	_button(row, "预览安全修复", "preview", _preview)
	_button(row, "应用安全修复", "repair", _repair)
	paths = TextEdit.new()
	paths.placeholder_text = "每行一个 res:// 资源路径；可批量选择材质和姿态采样配置。"
	paths.custom_minimum_size.y = 54
	add_child(paths)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 330
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	scroll.add_child(grid)
	for field in PROFILE_FIELDS:
		var label := Label.new()
		label.text = PROFILE_FIELDS[field]
		grid.add_child(label)
		var input := SpinBox.new()
		input.min_value = -1000
		input.max_value = 100000
		input.step = 0.1 if field in ["near_distance", "far_distance", "hysteresis", "animation_budget_ms", "frame_warning_ms"] else 1
		input.custom_minimum_size.x = 110
		grid.add_child(input)
		fields[field] = input
	errors_list = ItemList.new()
	errors_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	errors_list.item_activated.connect(_locate)
	body.add_child(errors_list)
	var actions := HBoxContainer.new()
	add_child(actions)
	_button(actions, "应用预算字段", "apply", _apply_profile)
	_button(actions, "撤销", "undo", _undo)
	_button(actions, "重做", "redo", _redo)
	_button(actions, "保存所选资源", "save", _save)
	result_label = Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.text = "请选择预算、角色、地图或资产配置；双击错误可定位。"
	add_child(result_label)
	_dialog = EditorFileDialog.new()
	_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILES
	_dialog.add_filter("*.tres", "资源")
	_dialog.add_filter("*.tscn", "3D场景")
	_dialog.files_selected.connect(func(selected: PackedStringArray): paths.text = "\n".join(selected); _load_paths())
	add_child(_dialog)

func _button(parent: Node, title: String, key: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)
	buttons[key] = button

func _load_paths() -> void:
	var candidate: Array = []
	for path in paths.text.split("\n", false):
		var clean := path.strip_edges()
		if not clean.begins_with("res://") or (not clean.ends_with(".tres") and not clean.ends_with(".tscn")):
			_status({"ok": false, "error_zh": "请输入项目内 .tres 或 .tscn 资源路径；原选择保持不变。"}); return
		var resource := ResourceLoader.load(clean)
		if resource == null:
			_status({"ok": false, "error_zh": "无法读取资源：" + clean}); return
		if not candidate.has(resource): candidate.append(resource)
	if candidate.is_empty():
		_status({"ok": false, "error_zh": "请至少选择一个资源。"}); return
	resources = candidate
	_sync_fields()
	_status({"ok": true, "message_zh": "已载入%d个资源。" % resources.size()})

func _sync_fields() -> void:
	if resources.size() == 1 and resources[0] is GMCharacterVisualBudgetProfile:
		for field in PROFILE_FIELDS: fields[field].value = resources[0].get(field)

func _validate() -> void:
	center.errors = center.errors.filter(func(row): return row.source != "planar3d")
	library.scan()
	var graph: GMSurfaceGraph
	for resource in resources:
		if resource is GMSurfaceGraph: graph = resource
	var ok := not resources.is_empty()
	for resource in resources:
		var result := GMPlanar3DValidation.validate_resource(resource, library, graph)
		GMPlanar3DValidation.publish(result, center)
		ok = ok and result.ok
	errors_list.clear()
	for i in center.errors.size():
		var entry: Dictionary = center.errors[i]
		if entry.source != "planar3d": continue
		errors_list.add_item("%s：%s" % [str(entry.resource_path).get_file(), entry.reason_zh])
		errors_list.set_item_metadata(errors_list.item_count - 1, i)
	_status({"ok": ok, "message_zh": "验证通过。" if ok else "验证失败：双击错误定位；资产未被修改。"})

func _locate(index: int) -> void:
	_status(center.locate(int(errors_list.get_item_metadata(index)), editor))

func _preview() -> void:
	var plan := GMPlanar3DSafeRepair.preview(resources)
	var descriptions: Array[String] = []
	for change in plan.get("changes", []): descriptions.append("%s / %s：%s → %s" % [change.resource.resource_path.get_file(), change.field, str(change.before), str(change.after)])
	_status({"ok": plan.ok, "message_zh": "安全字段预览：\n" + "\n".join(descriptions) if plan.ok else plan.error_zh})

func _repair() -> void:
	_status(GMPlanar3DSafeRepair.apply(resources, undo, _history_context))

func _apply_profile() -> void:
	if resources.size() != 1 or not resources[0] is GMCharacterVisualBudgetProfile:
		_status({"ok": false, "error_zh": "请仅选择一个角色视觉预算资源。"}); return
	var candidate: Resource = resources[0].duplicate(true)
	for field in PROFILE_FIELDS: candidate.set(field, fields[field].value)
	var check: Dictionary = candidate.validate()
	if not check.ok:
		_status({"ok": false, "error_zh": check.errors[0].error_zh}); return
	undo.create_action("编辑角色视觉预算", UndoRedo.MERGE_DISABLE, _history_context)
	for field in PROFILE_FIELDS:
		undo.add_do_property(resources[0], field, candidate.get(field))
		undo.add_undo_property(resources[0], field, resources[0].get(field))
	undo.commit_action()
	_status({"ok": true, "message_zh": "预算已更新，可撤销；保存后供运行时配置使用。"})

func _undo() -> void:
	var history := undo.get_history_undo_redo(undo.get_object_history_id(_history_context))
	var ok := history.has_undo() and history.undo()
	_sync_fields()
	_status({"ok": ok, "message_zh": "撤销完成。" if ok else "没有可撤销操作。"})

func _redo() -> void:
	var history := undo.get_history_undo_redo(undo.get_object_history_id(_history_context))
	var ok := history.has_redo() and history.redo()
	_sync_fields()
	_status({"ok": ok, "message_zh": "重做完成。" if ok else "没有可重做操作。"})

func _save() -> void:
	if resources.is_empty():
		_status({"ok": false, "error_zh": "尚未选择资源。"}); return
	for resource in resources:
		var error := ResourceSaver.save(resource, resource.resource_path)
		if error != OK:
			_status({"ok": false, "error_zh": "保存失败：" + resource.resource_path, "error": error}); return
	_status({"ok": true, "message_zh": "所选资源保存完成。"})

func _status(result: Dictionary) -> void:
	last_result = result
	result_label.text = str(result.get("error_zh", result.get("message_zh", "操作完成。" if result.get("ok", false) else "操作失败。")))
