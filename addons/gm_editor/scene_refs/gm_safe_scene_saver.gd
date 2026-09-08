@tool
class_name GMSafeSceneSaver
extends RefCounted

## Owner/PackedScene 安全保存工具。
##
## 先验证树上的 owner，再 Pack 和 ResourceSaver.save；保存结果独立从磁盘
## 重载并对比稳定节点 ID。不会把运行中 Node 对象或临时编辑器状态写进场景。

static func validate_owner_tree(root: Node) -> Dictionary:
	var errors: Array[Dictionary] = []
	if root == null or not is_instance_valid(root): return {"ok": false, "code": "scene.root_missing", "reason_zh": "安全保存缺少场景根节点。", "errors": [{"code": "scene.root_missing", "reason_zh": "安全保存缺少场景根节点。"}]}
	_validate_owner_node(root, root, "", errors)
	return {"ok": errors.is_empty(), "code": "scene.owner_valid" if errors.is_empty() else "scene.owner_invalid", "errors": errors, "errors_zh": _messages(errors), "root_id": GMSceneReference.read_business_id(root), "node_count": _node_count(root)}

static func assign_owner(root: Node, include_root: bool = false) -> Dictionary:
	if root == null or not is_instance_valid(root): return {"ok": false, "code": "scene.root_missing", "reason_zh": "无法为已释放场景设置 owner。"}
	_assign_owner_recursive(root, root, include_root)
	return validate_owner_tree(root)

static func pack_and_save(root: Node, path: String, require_owner: bool = true) -> Dictionary:
	var before := snapshot_tree(root)
	if not before.ok: return before
	var owner_check := validate_owner_tree(root)
	if require_owner and not owner_check.ok:
		return {"ok": false, "code": "scene.owner_invalid", "reason_zh": "场景 owner 错误，PackedScene 保存被阻断；新增节点不会被静默丢弃。", "owner_validation": owner_check, "before": before}
	if path.strip_edges().is_empty(): return {"ok": false, "code": "scene.path_missing", "reason_zh": "场景保存缺少资源路径。", "before": before}
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK: return {"ok": false, "code": "scene.pack_failed", "reason_zh": "PackedScene.pack 失败：%s。" % pack_error, "pack_error": pack_error, "before": before, "owner_validation": owner_check}
	var save_error := ResourceSaver.save(packed, path)
	if save_error != OK: return {"ok": false, "code": "scene.save_failed", "reason_zh": "ResourceSaver 保存场景失败：%s。" % save_error, "save_error": save_error, "before": before, "owner_validation": owner_check}
	var reopened: Variant = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if reopened == null or not reopened is PackedScene: return {"ok": false, "code": "scene.reopen_failed", "reason_zh": "保存后无法重新加载 PackedScene：%s。" % path, "path": path, "before": before, "owner_validation": owner_check}
	var state := _state_snapshot(reopened)
	var compare := compare_snapshots(before, state)
	return {"ok": bool(compare.get("ok", false)), "code": "scene.save_verified" if compare.ok else "scene.save_compare_failed", "path": path, "before": before, "after": state, "comparison": compare, "owner_validation": owner_check, "resource_size": FileAccess.get_file_as_bytes(path).size() if FileAccess.file_exists(path) else 0}

static func snapshot_tree(root: Node) -> Dictionary:
	if root == null or not is_instance_valid(root): return {"ok": false, "code": "scene.root_missing", "reason_zh": "场景快照根节点不存在。"}
	var nodes: Array[Dictionary] = []
	_collect_tree(root, "", nodes)
	return {"ok": true, "root_id": GMSceneReference.read_business_id(root), "node_count": nodes.size(), "nodes": nodes}

static func compare_snapshots(before: Dictionary, after: Dictionary) -> Dictionary:
	var before_nodes: Array = before.get("nodes", []) if before.get("nodes", []) is Array else []
	var after_nodes: Array = after.get("nodes", []) if after.get("nodes", []) is Array else []
	var before_ids: Array[String] = []
	var after_ids: Array[String] = []
	for row in before_nodes: before_ids.append(str(row.get("business_id", "")))
	for row in after_nodes: after_ids.append(str(row.get("business_id", "")))
	var missing: Array[String] = []
	for id in before_ids:
		if not id.is_empty() and not after_ids.has(id): missing.append(id)
	var duplicate_ids: Array[String] = []
	for id in after_ids:
		if not id.is_empty() and after_ids.count(id) > 1 and not duplicate_ids.has(id): duplicate_ids.append(id)
	var ok := missing.is_empty() and duplicate_ids.is_empty() and after_nodes.size() >= before_nodes.size()
	return {"ok": ok, "before_node_count": before_nodes.size(), "after_node_count": after_nodes.size(), "missing_business_ids": missing, "duplicate_business_ids": duplicate_ids, "reason_zh": "" if ok else "保存后场景节点业务 ID 与保存前不一致。"}

static func _validate_owner_node(node: Node, root: Node, parent_locator: String, errors: Array[Dictionary]) -> void:
	var locator := parent_locator.path_join(node.name) if not parent_locator.is_empty() else node.name
	if node != root and node.owner != root:
		errors.append({"code": "scene.owner_invalid", "reason_zh": "节点 %s 的 owner 不是场景根，Pack 会丢失该节点。" % locator, "locator": locator, "business_id": GMSceneReference.read_business_id(node), "owner_id": GMSceneReference.read_business_id(node.owner) if node.owner != null else ""})
	for child in node.get_children(): _validate_owner_node(child, root, locator, errors)

static func _assign_owner_recursive(node: Node, root: Node, include_root: bool) -> void:
	if include_root or node != root: node.owner = root
	for child in node.get_children(): _assign_owner_recursive(child, root, false)

static func _collect_tree(node: Node, locator: String, result: Array[Dictionary]) -> void:
	var current_locator := locator.path_join(node.name) if not locator.is_empty() else node.name
	result.append({"business_id": GMSceneReference.read_business_id(node), "name": node.name, "class": node.get_class(), "locator": current_locator, "owner_business_id": GMSceneReference.read_business_id(node.owner) if node.owner != null else ""})
	for child in node.get_children(): _collect_tree(child, current_locator, result)

static func _state_snapshot(packed: PackedScene) -> Dictionary:
	var state := packed.get_state()
	var nodes: Array[Dictionary] = []
	for node_index in state.get_node_count():
		var node_name := str(state.get_node_name(node_index))
		var business_id := ""
		var content_id := ""
		for property_index in state.get_node_property_count(node_index):
			var property_name := str(state.get_node_property_name(node_index, property_index))
			var value: Variant = state.get_node_property_value(node_index, property_index)
			var identity_property := property_name.get_slice("/", property_name.get_slice_count("/") - 1) if property_name.contains("/") else property_name
			if identity_property in ["gm_id", "gm_content_id", "content_id", "anchor_id"]:
				if business_id.is_empty(): business_id = str(value)
				if identity_property == "content_id": content_id = str(value)
		nodes.append({"business_id": business_id, "content_id": content_id, "name": node_name, "index": node_index})
	return {"ok": true, "node_count": nodes.size(), "nodes": nodes, "root_id": nodes[0].get("business_id", "") if not nodes.is_empty() else ""}

static func _node_count(root: Node) -> int:
	var count := 1
	for child in root.get_children(): count += _node_count(child)
	return count

static func _messages(errors: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for row in errors: result.append(str(row.get("reason_zh", "场景 owner 无效。")))
	return result
