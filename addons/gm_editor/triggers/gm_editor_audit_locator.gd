@tool
class_name GMEditorAuditLocator
extends RefCounted

const SCENE_REFERENCE := preload("res://addons/gm_editor/scene_refs/gm_scene_reference.gd")

## Editor-only locator used by both audit graphs. A graph may only mark an
## entry locatable after this helper has completed a real editor operation.

static func resolve_node(root: Node, stable_id: String) -> Dictionary:
	# Keep editor lookup on the same 0/1/many resolver as runtime semantic
	# references. A locator must never turn an ambiguous ID into a first match.
	return SCENE_REFERENCE.resolve_unique_node(root, stable_id)

static func locate_node_by_id(editor_interface, root: Node, stable_id: String) -> Dictionary:
	var resolution := resolve_node(root, stable_id)
	if not resolution.ok:
		var failure := _failure(str(resolution.get("code", "editor.node_missing")), str(resolution.get("reason_zh", "稳定业务 ID 无法唯一解析。")), stable_id, selection_snapshot(editor_interface), inspector_snapshot(editor_interface), ["GMSceneReference.resolve_unique_node", "EditorInterface.get_selection"])
		failure["candidate_count"] = int(resolution.get("candidate_count", 0))
		failure["candidates"] = resolution.get("candidates", [])
		failure["cause_chain"] = resolution.get("cause_chain", [stable_id])
		return failure
	return locate_node(editor_interface, resolution.get("resolved", null), stable_id)

static func locate_node(editor_interface, node: Node, stable_id: String) -> Dictionary:
	var before := selection_snapshot(editor_interface)
	if editor_interface == null or not is_instance_valid(editor_interface):
		return _failure("editor.locator_unavailable", "EditorInterface 不可用，不能定位场景节点。", stable_id, before, {}, ["EditorInterface"])
	if node == null or not is_instance_valid(node):
		return _failure("editor.node_missing", "稳定业务 ID 对应的场景节点不存在或已释放：%s。" % stable_id, stable_id, before, {}, ["EditorInterface.get_selection"])
	if not node.is_inside_tree():
		return _failure("editor.node_not_in_tree", "场景节点尚未进入编辑器场景树，不能定位：%s。" % stable_id, stable_id, before, {}, ["EditorInterface.get_selection"])
	var actual_id := SCENE_REFERENCE.read_business_id(node)
	if actual_id != stable_id:
		return _failure("editor.identity_mismatch", "场景节点业务 ID 不匹配：期望 %s，实际 %s。" % [stable_id, actual_id], stable_id, before, {}, ["EditorInterface.get_selection"])
	if not editor_interface.has_method("get_selection"):
		return _failure("editor.selection_api_missing", "EditorInterface 没有 get_selection，不能完成真实节点定位。", stable_id, before, {}, ["EditorInterface.get_selection"])
	var selection: Variant = editor_interface.get_selection()
	if selection == null or not selection.has_method("clear") or not selection.has_method("add_node"):
		return _failure("editor.selection_api_missing", "EditorSelection 不支持 clear/add_node，不能完成真实节点定位。", stable_id, before, {}, ["EditorInterface.get_selection"])
	selection.clear()
	selection.add_node(node)
	if editor_interface.has_method("edit_node"):
		editor_interface.edit_node(node)
	if editor_interface.has_method("inspect_object"):
		editor_interface.inspect_object(node)
	var after := selection_snapshot(editor_interface)
	var inspected := inspector_snapshot(editor_interface)
	var locator := str(node.get_path())
	var selected: bool = after.get("selected_business_ids", []).has(stable_id) or after.get("selected_instance_ids", []).has(node.get_instance_id())
	var inspected_ok := int(inspected.get("instance_id", -1)) == node.get_instance_id()
	var ok: bool = selected and inspected_ok and not locator.is_empty()
	return {"ok": ok, "code": "editor.node_located" if ok else "editor.node_location_failed", "reason_zh": "" if ok else "EditorSelection 或 Inspector 未确认节点定位：%s。" % stable_id, "kind": "scene_node", "stable_id": stable_id, "resolved_locator": locator, "selected": selected, "inspected": inspected_ok, "selection_before": before, "selection_after": after, "inspector_after": inspected, "api_calls": ["EditorInterface.get_selection", "EditorSelection.clear", "EditorSelection.add_node", "EditorInterface.edit_node", "EditorInterface.inspect_object"], "identity_policy": "stable_business_id; NodePath_is_locator_only"}

static func locate_resource(editor_interface, resource: Resource, stable_id: String) -> Dictionary:
	var before := inspector_snapshot(editor_interface)
	if editor_interface == null or not is_instance_valid(editor_interface):
		return _failure("editor.locator_unavailable", "EditorInterface 不可用，不能定位 Resource。", stable_id, {}, before, ["EditorInterface"])
	if resource == null or not is_instance_valid(resource):
		return _failure("editor.resource_missing", "稳定资源 ID 对应的 Resource 不存在或已释放：%s。" % stable_id, stable_id, {}, before, ["EditorInterface.edit_resource"])
	if not editor_interface.has_method("edit_resource") or not editor_interface.has_method("inspect_object"):
		return _failure("editor.resource_api_missing", "EditorInterface 没有 edit_resource/inspect_object，不能完成真实 Resource 定位。", stable_id, {}, before, ["EditorInterface.edit_resource", "EditorInterface.inspect_object"])
	editor_interface.edit_resource(resource)
	editor_interface.inspect_object(resource)
	var after := inspector_snapshot(editor_interface)
	var resource_path := str(resource.resource_path)
	var inspected := int(after.get("instance_id", -1)) == resource.get_instance_id()
	var ok: bool = inspected
	return {"ok": ok, "code": "editor.resource_located" if ok else "editor.resource_location_failed", "reason_zh": "" if ok else "Inspector 未确认已检查 Resource：%s。" % stable_id, "kind": "resource", "stable_id": stable_id, "resolved_locator": resource_path, "selected": false, "inspected": inspected, "inspector_before": before, "inspector_after": after, "api_calls": ["EditorInterface.edit_resource", "EditorInterface.inspect_object"], "identity_policy": "stable_resource_id; resource_path_is_locator_only"}

static func selection_snapshot(editor_interface) -> Dictionary:
	if editor_interface == null or not is_instance_valid(editor_interface) or not editor_interface.has_method("get_selection"):
		return {"available": false, "selected_business_ids": [], "selected_instance_ids": [], "selected_locators": []}
	var selection: Variant = editor_interface.get_selection()
	if selection == null or not selection.has_method("get_selected_nodes"):
		return {"available": false, "selected_business_ids": [], "selected_instance_ids": [], "selected_locators": []}
	var ids: Array[String] = []
	var instances: Array[int] = []
	var locators: Array[String] = []
	for node in selection.get_selected_nodes():
		if node == null or not is_instance_valid(node): continue
		ids.append(SCENE_REFERENCE.read_business_id(node))
		instances.append(node.get_instance_id())
		locators.append(str(node.get_path()))
	return {"available": true, "selected_business_ids": ids, "selected_instance_ids": instances, "selected_locators": locators}

static func inspector_snapshot(editor_interface) -> Dictionary:
	if editor_interface == null or not is_instance_valid(editor_interface) or not editor_interface.has_method("get_inspector"):
		return {"available": false, "instance_id": -1, "resource_path": "", "class": ""}
	var inspector: Variant = editor_interface.get_inspector()
	if inspector == null or not inspector.has_method("get_edited_object"):
		return {"available": false, "instance_id": -1, "resource_path": "", "class": ""}
	var object: Variant = inspector.get_edited_object()
	if object == null or not is_instance_valid(object):
		return {"available": true, "instance_id": -1, "resource_path": "", "class": ""}
	var resource_path := str(object.resource_path) if object is Resource else ""
	var locator := str(object.get_path()) if object is Node and object.is_inside_tree() else resource_path
	return {"available": true, "instance_id": object.get_instance_id(), "resource_path": resource_path, "locator": locator, "class": object.get_class()}

static func _failure(code: String, reason_zh: String, stable_id: String, selection_before: Dictionary, inspector_before: Dictionary, api_calls: Array) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "kind": "unlocatable", "stable_id": stable_id, "resolved_locator": "", "selected": false, "inspected": false, "selection_before": selection_before, "selection_after": {}, "inspector_before": inspector_before, "inspector_after": {}, "api_calls": api_calls, "identity_policy": "stable_business_id_or_resource_id; locator_only"}
