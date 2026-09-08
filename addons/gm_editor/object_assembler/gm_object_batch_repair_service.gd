@tool
class_name GMObjectBatchRepairService
extends RefCounted

var assembler := GMObjectAssembler.new()
var undo_redo: Object

func _init(p_undo_redo: Object = null) -> void:
	undo_redo = p_undo_redo

func preview(instances: Array[GMObjectInstance]) -> Dictionary:
	return assembler.preview_repair(instances)

func apply(instances: Array[GMObjectInstance], options: Dictionary = {}) -> Dictionary:
	var before := preview(instances)
	if not before.ok: return before
	if before.change_count == 0:
		return {"ok": true, "idempotent": true, "change_count": 0, "preview": before, "undo_registered": false}
	var states: Array[Dictionary] = []
	for instance in instances:
		states.append({"instance":instance, "state":assembler.capture_integrity_state(instance)})
	var injected_after := int(options.get("fail_after_instances", -1))
	var applied := _apply_transaction(instances, states, injected_after)
	if not applied.ok:
		applied["preview"] = before
		applied["undo_registered"] = false
		return applied
	var after := preview(instances)
	if after.change_count != 0:
		_restore_batch(states)
		return {"ok":false, "code":"object.batch_repair_incomplete", "error_zh":"批量修复复检仍有缺陷，已逐值回滚。", "rolled_back":true, "remaining":after, "preview":before, "undo_registered":false}
	var undo_registered := false
	if undo_redo != null:
		var after_states: Array[Dictionary] = []
		for instance in instances:
			after_states.append({"instance":instance, "state":assembler.capture_integrity_state(instance)})
		_create_action("批量修复GM对象", instances[0])
		_add_repair_do(instances, after_states)
		_add_undo(states)
		undo_redo.commit_action(false)
		undo_registered = _history_has_undo(instances[0])
	return {"ok": true, "idempotent": false, "change_count": before.change_count, "applied_change_count":before.change_count, "remaining_change_count":0, "verified_complete":true, "preview": before, "undo_registered": undo_registered}

func _apply_transaction(instances: Array[GMObjectInstance], states: Array[Dictionary], fail_after_instances: int = -1) -> Dictionary:
	var applied_count := 0
	for instance in instances:
		if fail_after_instances >= 0 and applied_count >= fail_after_instances:
			_restore_batch(states)
			return {"ok":false, "code":"object.batch_repair_injected_failure", "error_zh":"批量修复注入失败，全部对象已逐值回滚。", "rolled_back":true, "applied_before_failure":applied_count, "change_count":0}
		var repaired := assembler.repair(instance)
		if not repaired.ok:
			_restore_batch(states)
			return {"ok":false, "code":"object.batch_repair_failed", "error_zh":"批量修复失败，全部对象已逐值回滚。", "rolled_back":true, "cause":repaired, "change_count":0}
		applied_count += 1
	return {"ok":true, "applied_instances":applied_count}

func _restore_batch(states: Array[Dictionary]) -> void:
	for value in states:
		var instance := value.get("instance", null) as GMObjectInstance
		if instance != null and is_instance_valid(instance): assembler.restore_integrity_state(instance, value.get("state", {}))

func _create_action(action_name: String, context: Object) -> void:
	if undo_redo is EditorUndoRedoManager: undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, context)
	else: undo_redo.create_action(action_name)

func _redo_batch(instances: Array[GMObjectInstance], after_states: Array[Dictionary]) -> void:
	for index in instances.size():
		var instance := instances[index]
		if instance == null or not is_instance_valid(instance): continue
		assembler.repair(instance)
		var state: Dictionary = after_states[index].get("state", {})
		instance.transform = state.get("transform", instance.transform)
		instance.object_state = state.get("object_state", instance.object_state).duplicate(true)
		instance.stable_instance_id = str(state.get("stable_instance_id", instance.stable_instance_id))
		instance.map_id = str(state.get("map_id", instance.map_id))

func _add_repair_do(instances: Array[GMObjectInstance], after_states: Array[Dictionary]) -> void:
	if undo_redo is EditorUndoRedoManager: undo_redo.add_do_method(self, "_redo_batch", instances, after_states)
	else: undo_redo.add_do_method(Callable(self, "_redo_batch").bind(instances, after_states))

func _add_undo(states: Array[Dictionary]) -> void:
	if undo_redo is EditorUndoRedoManager: undo_redo.add_undo_method(self, "_restore_batch", states)
	else: undo_redo.add_undo_method(Callable(self, "_restore_batch").bind(states))

func _history_has_undo(context: Object) -> bool:
	if undo_redo is EditorUndoRedoManager:
		var history_id: int = undo_redo.get_object_history_id(context)
		return undo_redo.get_history_undo_redo(history_id).has_undo()
	return undo_redo.has_undo()
