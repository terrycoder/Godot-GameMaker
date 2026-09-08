class_name GMCharacterObjectVisualService
extends RefCounted

const BINDING_SCRIPT := preload("res://gm_runtime/characters/visual/gm_character_object_visual_binding_2d.gd")

func swap_on_task10_object(target: GMObjectInstance, visual_set: GMCharacterVisualSet2D) -> Dictionary:
	if target == null or not is_instance_valid(target): return _failure("character.object_target_invalid", "VisualSet 替换目标不是正式 GMObjectInstance。")
	var presenter_root := target.get_node_or_null("Presenter") as Node2D
	if presenter_root == null or str(presenter_root.get_meta("gm_standard_role", "")) != "presenter": return _failure("character.object_presenter_role_missing", "任务10正式 Presenter 角色不存在。")
	var before := task10_closure_snapshot(target)
	var binding: Node = presenter_root.get_node_or_null("CharacterVisualBinding")
	var created := false
	if binding == null:
		binding = BINDING_SCRIPT.new(); binding.name = "CharacterVisualBinding"; presenter_root.add_child(binding); binding.owner = target.owner if target.owner != null else target; created = true
	var previous = binding.get("visual_set")
	var swapped: Dictionary = binding.call("swap_visual_set", visual_set)
	if not swapped.ok:
		if created: presenter_root.remove_child(binding); binding.free()
		return swapped.merged({"closure_before":before}, true)
	var after := task10_closure_snapshot(target)
	var unchanged := _same_closure(before, after)
	if not unchanged:
		if previous != null: binding.call("swap_visual_set", previous)
		elif created: presenter_root.remove_child(binding); binding.free()
		return _failure("character.object_closure_changed", "外观替换触碰任务10身份/状态闭包，已回滚。", {"before":before,"after":after})
	return {"ok":true,"visual_set_id":visual_set.visual_set_id,"closure_before":before,"closure_after":after,"closure_preserved":true,"binding_path":str(target.get_path_to(binding)),"presenter_class":"GMCharacterPresenter2D"}

func task10_closure_snapshot(target: GMObjectInstance) -> Dictionary:
	var host_node := target.get_node_or_null("AbilityHost") as GMObjectAbilityHostNode
	var host = host_node.ability_host if host_node != null else null
	var custom_paths: Array[String] = []
	for child in target.get_children():
		if not child.has_meta("gm_standard_role"): custom_paths.append(str(target.get_path_to(child)))
	custom_paths.sort()
	var owner_rows: Array[Dictionary] = []
	_collect_owners(target, target, owner_rows)
	return {
		"stable_instance_id":target.stable_instance_id, "map_id":str(target.map_id), "definition_id":target.definition.content_id if target.definition != null else "",
		"ability_host_instance_id":host.get_instance_id() if host != null else 0, "ability_ids":host.specs.keys() if host != null else [],
		"object_state":target.object_state.duplicate(true), "persistent":target.persistent, "owner_rows":owner_rows, "custom_paths":custom_paths,
	}

func _same_closure(before: Dictionary, after: Dictionary) -> bool:
	for key in ["stable_instance_id","map_id","definition_id","ability_host_instance_id","ability_ids","object_state","persistent","owner_rows","custom_paths"]:
		if before.get(key) != after.get(key): return false
	return true

func _collect_owners(node: Node, root: Node, rows: Array[Dictionary]) -> void:
	if node != root and (node.has_meta("gm_standard_role") or node.has_meta("gm_standard_internal_role")):
		rows.append({"path":str(root.get_path_to(node)),"owner":str(node.owner.name) if node.owner != null else ""})
	for child in node.get_children():
		# The task11 binding is visual-only and intentionally excluded from the
		# pre-existing task10 owner closure comparison.
		if child.get_script() == BINDING_SCRIPT: continue
		_collect_owners(child, root, rows)

func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok":false,"code":code,"error_zh":message,"details":details,"failure_closed":true}
