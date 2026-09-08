@tool
class_name GMObjectAssemblerDock
extends PanelContainer

const BatchRepairService = preload("res://addons/gm_editor/object_assembler/gm_object_batch_repair_service.gd")

var editor_plugin: EditorPlugin
var undo_redo: EditorUndoRedoManager
var placement: GMObjectPlacementService
var assembler := GMObjectAssembler.new()
var batch_repair: RefCounted
var library: GMObjectLibraryList
var canvas: GMObjectMapDropSurface
var status: RichTextLabel
var selected_instance: GMObjectInstance
var last_facts: Dictionary = {}
var definitions: Array[GMObjectDefinition] = []

func configure(plugin: EditorPlugin) -> void:
	editor_plugin = plugin
	undo_redo = plugin.get_undo_redo()
	placement = GMObjectPlacementService.new(undo_redo)
	batch_repair = BatchRepairService.new(undo_redo)
	_build_ui()
	_load_library()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	add_child(root)
	var heading := Label.new()
	heading.text = "对象装配与地图拖放"
	heading.add_theme_font_size_override("font_size", 22)
	root.add_child(heading)
	var hint := Label.new()
	hint.text = "从任务03内容对象库拖入地图；自动装配Owner、稳定ID、GAS交互、保存身份与锚点。"
	root.add_child(hint)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	library = GMObjectLibraryList.new()
	library.custom_minimum_size = Vector2(280, 280)
	library.select_mode = ItemList.SELECT_SINGLE
	split.add_child(library)
	canvas = GMObjectMapDropSurface.new()
	canvas.definition_dropped.connect(_on_definition_dropped)
	split.add_child(canvas)
	var actions := HBoxContainer.new()
	root.add_child(actions)
	_add_button(actions, "复制（新ID）", _duplicate_selected)
	_add_button(actions, "删除", _delete_selected)
	_add_button(actions, "撤销", _undo)
	_add_button(actions, "重做", _redo)
	_add_button(actions, "修复预览", _preview_repair)
	_add_button(actions, "应用修复", _apply_repair)
	_add_button(actions, "运行交互", _interact_selected)
	status = RichTextLabel.new()
	status.custom_minimum_size.y = 120
	status.fit_content = true
	root.add_child(status)
	_set_status("对象库已连接，等待拖放。")

func _load_library() -> void:
	for path in ["res://samples/task10_objects/locked_chest.tres", "res://samples/task10_objects/plain_door.tres"]:
		var definition := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GMObjectDefinition
		if definition != null: definitions.append(definition)
	library.set_definitions(definitions)
	if not definitions.is_empty(): library.select(0)

func _on_definition_dropped(definition: GMObjectDefinition, world_position: Vector2, drag_fact: Dictionary) -> void:
	var parent := _object_parent()
	if parent == null:
		_set_status("当前编辑场景没有可编辑Node2D对象层。")
		last_facts = {"ok": false, "code": "object.editor_parent_missing", "drag": drag_fact}
		return
	var map_id := str(parent.get_meta("gm_map_id", parent.get_parent().get_meta("gm_map_id", "map.editor") if parent.get_parent() != null else "map.editor"))
	var result := placement.drop_definition(parent, definition, map_id, world_position)
	result["drag"] = drag_fact
	last_facts = result
	if result.ok:
		selected_instance = result.instance
		canvas.show_state("已放置 %s\n实例ID：%s" % [definition.display_name_zh, result.stable_instance_id])
		_set_status("拖放成功；已通过EditorUndoRedo登记，Owner和标准组件已装配。")
	else: _set_status("拖放被拒绝：%s" % result.get("error_zh", result.get("reason_zh", "未知错误")))

func get_capture_snapshot() -> Dictionary:
	return {"formal_dock": true, "title": "对象装配与地图拖放", "library_count": definitions.size(), "object_count": _object_count(), "selected_instance_id": selected_instance.stable_instance_id if is_instance_valid(selected_instance) else "", "last_facts": _serializable_drop(last_facts), "can_drag_to_map": true, "editor_undo_redo": undo_redo != null}

func _duplicate_selected() -> Dictionary:
	if not is_instance_valid(selected_instance): return {"ok": false, "code": "object.selection_missing"}
	var result := placement.duplicate_instance(selected_instance)
	if result.ok: selected_instance = result.instance
	last_facts = result
	_set_status("复制完成，新实例ID：%s" % result.get("stable_instance_id", "") if result.ok else "复制失败。")
	return result

func _delete_selected() -> Dictionary:
	if not is_instance_valid(selected_instance): return {"ok": false, "code": "object.selection_missing"}
	var result := placement.delete_instance(selected_instance)
	last_facts = result
	_set_status("对象已删除，可撤销。" if result.ok else "删除失败。")
	return result

func _undo() -> void:
	var history := _history_undo_redo()
	if history != null and history.has_undo(): history.undo()
	_set_status("已执行EditorUndoRedo撤销。")

func _redo() -> void:
	var history := _history_undo_redo()
	if history != null and history.has_redo(): history.redo()
	_set_status("已执行EditorUndoRedo重做。")

func _preview_repair() -> Dictionary:
	var values: Array[GMObjectInstance] = []
	for node in _object_nodes(): values.append(node)
	var result: Dictionary = batch_repair.preview(values)
	last_facts = result
	_set_status("修复预览：%d项变更；不会覆盖人工子节点或变换。" % result.change_count)
	return result

func _apply_repair() -> Dictionary:
	var values: Array[GMObjectInstance] = []
	for node in _object_nodes(): values.append(node)
	if values.is_empty(): return {"ok": false, "code": "object.selection_missing"}
	var result: Dictionary = batch_repair.apply(values)
	last_facts = result
	_set_status("修复完成，可通过EditorUndoRedo撤回。" if result.ok else "修复失败。")
	return result

func _interact_selected() -> Dictionary:
	if not is_instance_valid(selected_instance): return {"ok": false, "code": "object.selection_missing"}
	var host := selected_instance.get_node_or_null("AbilityHost") as GMObjectAbilityHostNode
	if host == null: return {"ok": false, "code": "object.host_missing"}
	var context := {"item_ids": ["item.key.iron"], "loot_table_id": "loot.chest.basic", "item_id": "item.sample", "damage": 10}
	var result := host.interact(context)
	last_facts = result
	_set_status("交互已通过统一GAS完成。" if result.ok else "交互被安全拒绝：%s" % result.get("reason_zh", result.get("error_zh", "")))
	return result

func _object_parent() -> Node2D:
	if editor_plugin == null: return null
	var scene_root := editor_plugin.get_editor_interface().get_edited_scene_root()
	if scene_root == null or not scene_root is Node2D: return null
	var objects := scene_root.get_node_or_null("Objects")
	return objects as Node2D if objects is Node2D else scene_root as Node2D

func _object_nodes() -> Array[GMObjectInstance]:
	var result: Array[GMObjectInstance] = []
	var parent := _object_parent()
	if parent == null: return result
	for child in parent.get_children():
		if child is GMObjectInstance: result.append(child)
	return result

func _object_count() -> int:
	return _object_nodes().size()

func _history_undo_redo() -> UndoRedo:
	if undo_redo == null: return null
	var parent := _object_parent()
	if parent == null: return null
	return undo_redo.get_history_undo_redo(undo_redo.get_object_history_id(parent))

func _serializable_drop(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	result.erase("instance")
	return result

func _set_status(text: String) -> void:
	if status != null: status.text = text

func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
