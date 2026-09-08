@tool
class_name GMObjectPlacementService
extends RefCounted

var assembler := GMObjectAssembler.new()
var undo_redo: Object

func _init(p_undo_redo: Object = null) -> void:
	undo_redo = p_undo_redo

func drop_definition(parent: Node, definition: GMObjectDefinition, map_id: String, world_position: Vector2) -> Dictionary:
	var parent_check := _validate_parent(parent)
	if not parent_check.ok: return parent_check
	if bool(parent.get_meta("gm_read_only_map_layer", false)): return _failure("object.target_layer_read_only", "目标地图层只读，拖放已安全拒绝。")
	var instance := GMObjectInstance.new()
	instance.name = definition.content_id.to_pascal_case()
	instance.position = world_position
	var assembled := assembler.assemble(instance, definition, {"map_id": map_id, "allocation_hint": "drop:%s:%s" % [world_position.x, world_position.y]})
	if not assembled.ok:
		instance.free()
		return assembled
	_commit_add_action(parent, instance, "拖放GM对象")
	return {"ok": true, "operation": "drop", "instance": instance, "stable_instance_id": instance.stable_instance_id, "position": world_position, "undo_registered": undo_redo != null, "assembly": assembled}

func duplicate_instance(source: GMObjectInstance, target_parent: Node = null, target_map_id: String = "") -> Dictionary:
	if source == null or source.definition == null: return _failure("object.copy_source_invalid", "复制对象缺少有效来源或定义。")
	var parent := target_parent if target_parent != null else source.get_parent()
	var parent_check := _validate_parent(parent)
	if not parent_check.ok: return parent_check
	var copy := GMObjectInstance.new()
	copy.name = "%sCopy" % source.name
	copy.definition = source.definition
	copy.object_state = source.object_state.duplicate(true)
	copy.position = source.position + Vector2(24, 24)
	copy.map_id = StringName(target_map_id if not target_map_id.is_empty() else str(source.map_id))
	copy.regenerate_identity_for_copy(str(copy.map_id))
	var assembled := assembler.assemble(copy, source.definition, {"map_id": str(copy.map_id), "allocation_hint": "copy"})
	if not assembled.ok:
		copy.free()
		return assembled
	_commit_add_action(parent, copy, "复制GM对象")
	return {"ok": true, "operation": "copy", "instance": copy, "source_id": source.stable_instance_id, "stable_instance_id": copy.stable_instance_id, "new_identity": copy.stable_instance_id != source.stable_instance_id, "undo_registered": undo_redo != null}

func move_instance(source: GMObjectInstance, target_parent: Node, target_map_id: String, world_position: Vector2) -> Dictionary:
	var parent_check := _validate_parent(target_parent)
	if not parent_check.ok: return parent_check
	if bool(target_parent.get_meta("gm_read_only_map_layer", false)): return _failure("object.target_layer_read_only", "目标地图层只读，跨地图移动已安全拒绝。")
	var old_parent := source.get_parent()
	var old_position := source.position
	var old_map := str(source.map_id)
	var stable_id := source.stable_instance_id
	if undo_redo != null:
		_create_action("跨地图移动GM对象", target_parent)
		_add_do(self, "_move_now", [source, target_parent, target_map_id, world_position])
		_add_undo(self, "_move_now", [source, old_parent, old_map, old_position])
		undo_redo.commit_action()
	else: _move_now(source, target_parent, target_map_id, world_position)
	return {"ok": true, "operation": "move", "stable_instance_id": stable_id, "identity_preserved": source.stable_instance_id == stable_id, "from_map": old_map, "to_map": target_map_id, "undo_registered": undo_redo != null}

func delete_instance(source: GMObjectInstance) -> Dictionary:
	if source == null or source.get_parent() == null: return _failure("object.delete_source_invalid", "删除对象不在可编辑场景中。")
	var parent := source.get_parent()
	if undo_redo != null:
		_create_action("删除GM对象", parent)
		_add_do(parent, "remove_child", [source])
		_add_undo(parent, "add_child", [source])
		undo_redo.add_do_reference(source)
		undo_redo.commit_action()
	else: parent.remove_child(source)
	return {"ok": true, "operation": "delete", "stable_instance_id": source.stable_instance_id, "undo_registered": undo_redo != null}

func _commit_add_action(parent: Node, instance: GMObjectInstance, action_name: String) -> void:
	var scene_owner := parent.owner if parent.owner != null else parent
	if undo_redo != null:
		_create_action(action_name, parent)
		_add_do(parent, "add_child", [instance])
		_add_do(assembler, "assign_scene_owner", [instance, scene_owner])
		_add_undo(parent, "remove_child", [instance])
		undo_redo.add_do_reference(instance)
		undo_redo.commit_action()
	else:
		parent.add_child(instance)
		assembler.assign_scene_owner(instance, scene_owner)

func _create_action(action_name: String, context: Object) -> void:
	if undo_redo is EditorUndoRedoManager: undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, context)
	else: undo_redo.create_action(action_name)

func _add_do(target: Object, method: StringName, args: Array) -> void:
	if undo_redo is EditorUndoRedoManager:
		match args.size():
			1: undo_redo.add_do_method(target, method, args[0])
			2: undo_redo.add_do_method(target, method, args[0], args[1])
			4: undo_redo.add_do_method(target, method, args[0], args[1], args[2], args[3])
			_: undo_redo.add_do_method(target, method)
	else:
		undo_redo.add_do_method(Callable(target, method).bindv(args))

func _add_undo(target: Object, method: StringName, args: Array) -> void:
	if undo_redo is EditorUndoRedoManager:
		match args.size():
			1: undo_redo.add_undo_method(target, method, args[0])
			4: undo_redo.add_undo_method(target, method, args[0], args[1], args[2], args[3])
			_: undo_redo.add_undo_method(target, method)
	else:
		undo_redo.add_undo_method(Callable(target, method).bindv(args))

func _move_now(source: GMObjectInstance, parent: Node, target_map_id: String, target_position: Vector2) -> void:
	if source.get_parent() != null: source.get_parent().remove_child(source)
	parent.add_child(source)
	source.position = target_position
	source.move_to_map(target_map_id)
	source.owner = parent.owner if parent.owner != null else parent

func _validate_parent(parent: Node) -> Dictionary:
	if parent == null or not is_instance_valid(parent): return _failure("object.target_parent_invalid", "目标父节点无效。")
	if not (parent is Node2D): return _failure("object.target_parent_invalid", "对象只能拖入Node2D地图父节点。")
	return {"ok": true}

func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": message}
