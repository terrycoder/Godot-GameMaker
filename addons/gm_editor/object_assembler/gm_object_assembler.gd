@tool
class_name GMObjectAssembler
extends RefCounted

const STANDARD_ROLES := {
	"ability_host": "AbilityHost",
	"interaction_area": "InteractionArea",
	"presenter": "Presenter",
	"cue_receiver": "CueReceiver",
	"save_identity": "SaveIdentity",
	"anchors": "Anchors",
}

func assemble(root: GMObjectInstance, definition: GMObjectDefinition, options: Dictionary = {}) -> Dictionary:
	if root == null or not is_instance_valid(root): return _failure("assembler.root_invalid", "装配目标不是有效GMObjectInstance。")
	if definition == null: return _failure("assembler.definition_missing", "装配缺少对象定义。")
	var resolved := definition.resolve_effective()
	if not resolved.ok: return resolved
	if root.get_parent() != null and not root.get_parent() is Node: return _failure("assembler.parent_invalid", "装配目标父节点不合法。")
	var duplicate := _find_duplicate_identity(root, root.stable_instance_id)
	if not root.stable_instance_id.is_empty() and duplicate != null:
		return _failure("object.instance_id_duplicate", "场景内存在重复对象实例ID，已安全拒绝装配。", {"stable_instance_id": root.stable_instance_id, "other_path": str(duplicate.get_path())})
	var before := _snapshot_root(root)
	var staged: Array[Node] = []
	var present := _role_index(root)
	for role in STANDARD_ROLES:
		if present.has(role): continue
		var component := _make_component(role, resolved.effective)
		if component == null:
			_free_staged(staged)
			return _failure("assembler.component_stage_failed", "标准组件创建失败，未改动场景。", {"role": role})
		component.name = STANDARD_ROLES[role]
		component.set_meta("gm_standard_role", role)
		staged.append(component)
	var fail_after := int(options.get("fail_after_additions", -1))
	var added: Array[Node] = []
	root.definition = definition
	root.persistent = bool(resolved.effective.persistent)
	if root.object_state.is_empty(): root.object_state = resolved.effective.state_defaults.duplicate(true)
	if root.stable_instance_id.is_empty():
		var identity := root.ensure_identity(str(options.get("map_id", root.map_id)), str(options.get("allocation_hint", definition.content_id)))
		if not identity.ok:
			_restore_root(root, before)
			_free_staged(staged)
			return identity
	for component in staged:
		root.add_child(component)
		var scene_owner := root.owner if root.owner != null else root
		component.owner = scene_owner
		_set_owner_recursive(component, scene_owner)
		added.append(component)
		if fail_after >= 0 and added.size() > fail_after:
			_rollback_added(root, added, before)
			for pending in staged:
				if is_instance_valid(pending): pending.free()
			return _failure("assembler.injected_failure", "装配中途失败，已完整回滚且未留下半装配场景。", {"rolled_back": true, "added_before_failure": added.size()})
	var host_node := _role_index(root).get("ability_host", null) as GMObjectAbilityHostNode
	if host_node != null and host_node.ability_host == null:
		var initialized := host_node.initialize(root, resolved.effective.ability_definitions)
		if not initialized.ok:
			_rollback_added(root, added, before)
			return _failure("assembler.host_initialize_failed", "能力宿主初始化失败，装配已回滚。", {"cause": initialized})
	var tree := scene_tree_snapshot(root)
	return {"ok": true, "created_roles": added.map(func(node): return str(node.get_meta("gm_standard_role"))), "created_count": added.size(), "idempotent": added.is_empty(), "stable_instance_id": root.stable_instance_id, "owner_complete": _owners_complete(root), "scene_tree": tree}

func inspect(root: GMObjectInstance) -> Dictionary:
	if root == null: return _failure("assembler.root_invalid", "完整性检查目标为空。")
	var roles := _role_index(root)
	var missing: Array[String] = []
	for role in STANDARD_ROLES:
		if not roles.has(role): missing.append(role)
	var internal_repairs: Array[Dictionary] = []
	var resolved := root.definition.resolve_effective() if root.definition != null else _failure("object.definition_missing", "对象缺少定义。")
	if resolved.ok:
		var area := roles.get("interaction_area", null) as Area2D
		if area != null:
			var collision := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if collision == null: internal_repairs.append({"kind":"add_collision_shape", "path":"InteractionArea/CollisionShape2D"})
			elif collision.shape == null: internal_repairs.append({"kind":"restore_collision_shape", "path":"InteractionArea/CollisionShape2D"})
		var anchors := roles.get("anchors", null) as Node2D
		if anchors != null:
			for anchor_id in resolved.effective.anchor_names:
				if _find_anchor(anchors, str(anchor_id)) == null: internal_repairs.append({"kind":"add_anchor", "path":"Anchors/%s" % str(anchor_id).to_pascal_case(), "anchor_id":str(anchor_id)})
	var owner_issues: Array[String] = []
	var expected_owner := root.owner if root.owner != null else root
	for entry in _managed_nodes(root):
		var node: Node = entry.node
		if node.owner != expected_owner: owner_issues.append(str(entry.path))
	var ability_issues: Array[String] = []
	if resolved.ok:
		var host_node := roles.get("ability_host", null) as GMObjectAbilityHostNode
		if host_node != null and host_node.ability_host == null:
			for ability in resolved.effective.ability_definitions: ability_issues.append(ability.ability_id)
		elif host_node != null:
			for ability in resolved.effective.ability_definitions:
				if not host_node.ability_host.has_ability(ability.ability_id): ability_issues.append(ability.ability_id)
	else: ability_issues.append("definition_invalid")
	if root.stable_instance_id.is_empty(): ability_issues.append("stable_instance_id_missing")
	return {"ok": missing.is_empty() and internal_repairs.is_empty() and owner_issues.is_empty() and ability_issues.is_empty(), "missing_roles": missing, "internal_repairs":internal_repairs, "owner_issues": owner_issues, "ability_issues": ability_issues, "custom_children_preserved": _custom_child_paths(root), "stable_instance_id": root.stable_instance_id}

func preview_repair(roots: Array[GMObjectInstance]) -> Dictionary:
	var rows: Array[Dictionary] = []
	for root in roots:
		var inspection := inspect(root)
		rows.append({"instance_id": root.stable_instance_id, "node_path": str(root.get_path()), "add_roles": inspection.get("missing_roles", []).duplicate(), "internal_repairs":inspection.get("internal_repairs", []).duplicate(true), "owner_roles": inspection.get("owner_issues", []).duplicate(), "ability_repairs": inspection.get("ability_issues", []).duplicate(), "preserve_custom_children": inspection.get("custom_children_preserved", []).duplicate(), "preserve_transform": true})
	return {"ok": true, "preview_only": true, "rows": rows, "change_count": rows.reduce(func(total, row): return total + row.add_roles.size() + row.internal_repairs.size() + row.owner_roles.size() + row.ability_repairs.size(), 0)}

func repair(root: GMObjectInstance, map_id_override: String = "") -> Dictionary:
	if root == null or root.definition == null: return _failure("assembler.repair_target_invalid", "修复目标或对象定义无效。")
	var before_transform := root.transform
	var before_custom := _custom_child_paths(root)
	var before := capture_integrity_state(root)
	var preview := preview_repair([root])
	var result := _apply_integrity_repair(root, map_id_override)
	if not result.ok:
		restore_integrity_state(root, before)
		result["rolled_back"] = true
		return result
	var verified := inspect(root)
	if not verified.ok:
		restore_integrity_state(root, before)
		return _failure("assembler.repair_incomplete", "修复后完整性复检失败，已回滚全部变化。", {"rolled_back":true, "inspection":verified})
	result["change_count"] = preview.change_count
	result["verified_complete"] = true
	result["transform_preserved"] = root.transform == before_transform
	result["custom_children_preserved"] = before_custom == _custom_child_paths(root)
	return result

func capture_integrity_state(root: GMObjectInstance) -> Dictionary:
	var managed_paths: Array[String] = []
	var owners: Array[Dictionary] = []
	for entry in _managed_nodes(root):
		managed_paths.append(str(entry.path))
		owners.append({"node":entry.node, "owner":entry.node.owner})
	var collision_shapes: Array[Dictionary] = []
	for entry in _managed_nodes(root):
		if entry.node is CollisionShape2D: collision_shapes.append({"node":entry.node, "shape":entry.node.shape})
	var host := root.get_node_or_null("AbilityHost") as GMObjectAbilityHostNode
	var ability_state := {}
	if host != null:
		ability_state = {"host_node":host, "ability_host":host.ability_host, "runtime_context":host.runtime_context, "interaction_service":host.interaction_service, "grant_state":host.ability_host._snapshot_ability_grant_state() if host.ability_host != null else {}}
	return {"transform":root.transform, "object_state":root.object_state.duplicate(true), "stable_instance_id":root.stable_instance_id, "map_id":root.map_id, "managed_paths":managed_paths, "owners":owners, "collision_shapes":collision_shapes, "ability_state":ability_state, "custom_paths":_custom_child_paths(root)}

func restore_integrity_state(root: GMObjectInstance, state: Dictionary) -> Dictionary:
	var original_paths: Array = state.get("managed_paths", [])
	var current := _managed_nodes(root)
	current.sort_custom(func(a, b): return str(a.path).count("/") > str(b.path).count("/"))
	for entry in current:
		if not original_paths.has(str(entry.path)) and is_instance_valid(entry.node) and entry.node.get_parent() != null:
			entry.node.get_parent().remove_child(entry.node)
			entry.node.free()
	for value in state.get("collision_shapes", []):
		if is_instance_valid(value.node): value.node.shape = value.shape
	for value in state.get("owners", []):
		if is_instance_valid(value.node): value.node.owner = value.owner
	var ability_state: Dictionary = state.get("ability_state", {})
	var host := ability_state.get("host_node", null) as GMObjectAbilityHostNode
	if host != null and is_instance_valid(host):
		var original_host = ability_state.get("ability_host", null)
		if original_host == null and host.ability_host != null:
			host.reset_runtime_host()
		else:
			host.ability_host = original_host
			host.runtime_context = ability_state.get("runtime_context", null)
			host.interaction_service = ability_state.get("interaction_service", null)
			if host.ability_host != null: host.ability_host._restore_ability_grant_state(ability_state.get("grant_state", {}))
	root.transform = state.get("transform", root.transform)
	root.object_state = state.get("object_state", root.object_state).duplicate(true)
	root.stable_instance_id = str(state.get("stable_instance_id", root.stable_instance_id))
	root.map_id = str(state.get("map_id", root.map_id))
	return {"ok":true, "restored":true, "custom_children_preserved":state.get("custom_paths", []) == _custom_child_paths(root)}

func _apply_integrity_repair(root: GMObjectInstance, map_id_override: String) -> Dictionary:
	var assembled := assemble(root, root.definition, {"map_id": map_id_override if not map_id_override.is_empty() else str(root.map_id), "allocation_hint":"repair"})
	if not assembled.ok: return assembled
	var resolved := root.definition.resolve_effective()
	if not resolved.ok: return resolved
	var roles := _role_index(root)
	var area := roles.get("interaction_area", null) as Area2D
	if area == null: return _failure("assembler.interaction_area_missing", "交互区域修复失败。")
	var collision := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		collision = CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		collision.set_meta("gm_standard_internal_role", "collision_shape")
		area.add_child(collision)
	if collision.shape == null: collision.shape = resolved.effective.collision_shape
	var anchors := roles.get("anchors", null) as Node2D
	if anchors == null: return _failure("assembler.anchors_missing", "锚点容器修复失败。")
	for anchor_id in resolved.effective.anchor_names:
		if _find_anchor(anchors, str(anchor_id)) == null:
			var marker := Marker2D.new()
			marker.name = str(anchor_id).to_pascal_case()
			marker.set_meta("gm_anchor_id", str(anchor_id))
			marker.set_meta("gm_standard_internal_role", "anchor")
			anchors.add_child(marker)
	var expected_owner := root.owner if root.owner != null else root
	for entry in _managed_nodes(root): entry.node.owner = expected_owner
	var host := roles.get("ability_host", null) as GMObjectAbilityHostNode
	if host == null: return _failure("assembler.ability_host_missing", "能力宿主修复失败。")
	if host.ability_host == null:
		var initialized := host.initialize(root, resolved.effective.ability_definitions)
		if not initialized.ok: return initialized
	else:
		for ability in resolved.effective.ability_definitions:
			if not host.ability_host.has_ability(ability.ability_id):
				var granted := host.ability_host.grant_ability(ability, "object_definition:%s" % root.definition.content_id)
				if not granted.ok: return granted
	return {"ok":true, "created_count":assembled.created_count, "idempotent":false}

func assign_scene_owner(root: GMObjectInstance, scene_owner: Node) -> Dictionary:
	if root == null or scene_owner == null: return _failure("assembler.owner_target_invalid", "场景Owner目标无效。")
	root.owner = scene_owner
	var stack: Array[Node] = []
	for child in root.get_children(): stack.append(child)
	while not stack.is_empty():
		var child := stack.pop_back()
		child.owner = scene_owner
		for nested in child.get_children(): stack.append(nested)
	return {"ok": true, "owner": str(scene_owner.name), "node_count": scene_tree_snapshot(root).size()}

func scene_tree_snapshot(root: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	_collect_tree(root, root, rows)
	return rows

func _make_component(role: String, effective: Dictionary) -> Node:
	match role:
		"ability_host": return GMObjectAbilityHostNode.new()
		"interaction_area":
			var area := Area2D.new()
			var collision := CollisionShape2D.new()
			collision.name = "CollisionShape2D"
			collision.set_meta("gm_standard_internal_role", "collision_shape")
			collision.shape = effective.collision_shape
			area.add_child(collision)
			collision.owner = area
			return area
		"presenter":
			var presenter := Node2D.new()
			var appearance: PackedScene = effective.appearance_scene
			if appearance != null:
				var visual := appearance.instantiate()
				visual.name = "Appearance"
				presenter.add_child(visual)
				visual.owner = presenter
			return presenter
		"cue_receiver", "save_identity": return Node.new()
		"anchors":
			var anchors := Node2D.new()
			for anchor_name in effective.anchor_names:
				var marker := Marker2D.new()
				marker.name = str(anchor_name).to_pascal_case()
				marker.set_meta("gm_anchor_id", str(anchor_name))
				marker.set_meta("gm_standard_internal_role", "anchor")
				anchors.add_child(marker)
				marker.owner = anchors
			return anchors
	return null

func _role_index(root: Node) -> Dictionary:
	var result := {}
	for child in root.get_children():
		if child.has_meta("gm_standard_role"): result[str(child.get_meta("gm_standard_role"))] = child
	return result

func _owners_complete(root: Node) -> bool:
	var expected_owner := root.owner if root.owner != null else root
	var stack: Array[Node] = []
	for child in root.get_children():
		if child.has_meta("gm_standard_role"): stack.append(child)
	while not stack.is_empty():
		var child := stack.pop_back()
		if child.owner != expected_owner: return false
		for nested in child.get_children(): stack.append(nested)
	return true

func _set_owner_recursive(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_set_owner_recursive(child, root)

func _find_duplicate_identity(root: GMObjectInstance, identity: String) -> GMObjectInstance:
	if identity.is_empty(): return null
	var scene_root: Node = root
	while scene_root.get_parent() != null: scene_root = scene_root.get_parent()
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var candidate := stack.pop_back()
		if candidate != root and candidate is GMObjectInstance and candidate.stable_instance_id == identity: return candidate
		for child in candidate.get_children(): stack.append(child)
	return null

func _snapshot_root(root: GMObjectInstance) -> Dictionary:
	return {"definition": root.definition, "persistent": root.persistent, "object_state": root.object_state.duplicate(true), "stable_instance_id": root.stable_instance_id, "map_id": root.map_id}

func _restore_root(root: GMObjectInstance, snapshot: Dictionary) -> void:
	root.definition = snapshot.definition
	root.persistent = snapshot.persistent
	root.object_state = snapshot.object_state.duplicate(true)
	root.stable_instance_id = snapshot.stable_instance_id
	root.map_id = snapshot.map_id

func _rollback_added(root: GMObjectInstance, added: Array[Node], before: Dictionary) -> void:
	for component in added:
		if is_instance_valid(component):
			root.remove_child(component)
			component.free()
	_restore_root(root, before)

func _free_staged(staged: Array[Node]) -> void:
	for node in staged:
		if is_instance_valid(node): node.free()

func _custom_child_paths(root: Node) -> Array[String]:
	var result: Array[String] = []
	for child in root.get_children():
		if not child.has_meta("gm_standard_role"): result.append(str(root.get_path_to(child)))
	return result

func _managed_nodes(root: GMObjectInstance) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for child in root.get_children():
		if not child.has_meta("gm_standard_role"): continue
		result.append({"node":child, "path":str(root.get_path_to(child))})
		if str(child.get_meta("gm_standard_role")) == "interaction_area":
			var collision := child.get_node_or_null("CollisionShape2D")
			if collision != null: result.append({"node":collision, "path":str(root.get_path_to(collision))})
		elif str(child.get_meta("gm_standard_role")) == "anchors":
			for marker in child.get_children():
				if marker.has_meta("gm_anchor_id"): result.append({"node":marker, "path":str(root.get_path_to(marker))})
	return result

func _find_anchor(anchors: Node, anchor_id: String) -> Node:
	for child in anchors.get_children():
		if str(child.get_meta("gm_anchor_id", "")) == anchor_id: return child
	return null

func _collect_tree(node: Node, root: Node, rows: Array[Dictionary]) -> void:
	rows.append({"path": str(root.get_path_to(node)), "name": node.name, "type": node.get_class(), "role": str(node.get_meta("gm_standard_role", "custom")), "owner": node.owner.name if node.owner != null else ""})
	for child in node.get_children(): _collect_tree(child, root, rows)

func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": message, "details": details}
