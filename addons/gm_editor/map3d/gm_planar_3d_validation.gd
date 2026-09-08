@tool
class_name GMPlanar3DValidation
extends RefCounted

## Aggregates existing domain validators; validates copies because some legacy
## validators normalize content_type_id. Original assets are never repaired here.
static func validate_resource(resource: Resource, library: GMContentLibrary = null, graph: GMSurfaceGraph = null) -> Dictionary:
	if resource == null: return {"ok": false, "issues": [{"code": "planar3d.resource_missing", "error_zh": "资源无法读取，请重新选择。", "field": "资源路径"}]}
	var copy := resource.duplicate(true)
	var result: Dictionary
	if copy is GMCharacterVisualRecipe:
		var isolated := GMContentLibrary.new()
		if library != null:
			for entry in library.entries:
				var row: Dictionary = entry.duplicate(true)
				if row.get("resource") is Resource: row.resource = row.resource.duplicate(true)
				isolated.entries.append(row)
		result = GMCharacterAssetValidator.validate_recipe(copy, isolated)
	elif copy is GMHumanoidSkeletonContract: result = copy.validate_skeleton_contract()
	elif copy is GMBodyProfile: result = copy.validate_body_profile()
	elif copy is GMPostureProfile: result = copy.validate_posture_profile()
	elif copy is GMCharacterPart: result = copy.validate_part()
	elif copy is GMAnimationProfile: result = copy.validate_animation_profile()
	elif copy is PackedScene: result = _validate_scene(copy)
	elif copy is GMSurfaceGraph or copy is GMFacilityVisualProfile3D or copy is GMScenePlacementDocument3D or copy is GM3DImportPreset or copy is GMSemanticMaterial or copy is GMAnimationSamplingProfile or copy is GMRenderStyleProfile or copy is GMCharacterVisualBudgetProfile:
		result = copy.validate()
	else: result = {"ok": false, "code": "planar3d.type_unsupported", "error_zh": "此资源不是已支持的3D角色、地图、资产或预算配置。"}
	var issues: Array = result.get("issues", result.get("errors", [])).duplicate(true)
	if not result.get("ok", false) and issues.is_empty():
		for message in result.get("errors_zh", [result.get("error_zh", "资源验证失败。")]):
			issues.append({"code": result.get("code", "planar3d.invalid"), "error_zh": str(message)})
	if copy is GMScenePlacementDocument3D and graph != null:
		for placement in copy.placements:
			var surface := graph.resolve_surface(str(placement.surface_id))
			if surface == null:
				issues.append({"code": "planar3d.placement_surface_missing", "field": str(placement.stable_id), "error_zh": "摆放项引用的平面不存在，请选择正确平面。"})
	for issue in issues:
		issue["resource_path"] = resource.resource_path
		issue["field"] = str(issue.get("field", "资源配置"))
		issue["field_name_zh"] = str(issue.get("field_name_zh", issue.field))
	return {"ok": issues.is_empty(), "issues": issues, "resource_path": resource.resource_path}

static func _validate_scene(scene: PackedScene) -> Dictionary:
	var issues: Array = []
	var root := scene.instantiate()
	if not root is Node3D:
		if root != null: root.free()
		return {"ok": false, "issues": [{"code": "planar3d.scene_root_invalid", "field": "根节点", "error_zh": "3D场景根节点必须是 Node3D。"}]}
	_validate_scene_node(root, issues, str(root.name))
	root.free()
	return {"ok": issues.is_empty(), "issues": issues}

static func _validate_scene_node(node: Node, issues: Array, field: String) -> void:
	if node is Node3D:
		var transform: Transform3D = node.transform
		if not transform.origin.is_finite() or not transform.basis.x.is_finite() or not transform.basis.y.is_finite() or not transform.basis.z.is_finite():
			issues.append({"code": "planar3d.transform_non_finite", "field": field, "error_zh": "节点变换包含非有限数值。"})
	if node is MeshInstance3D and node.mesh == null:
		issues.append({"code": "planar3d.mesh_missing", "field": field, "error_zh": "网格节点缺少 Mesh 资源。"})
	if node is GeometryInstance3D and (not is_finite(node.visibility_range_begin) or not is_finite(node.visibility_range_end) or node.visibility_range_begin < 0.0 or node.visibility_range_end < 0.0 or (node.visibility_range_end > 0.0 and node.visibility_range_end < node.visibility_range_begin)):
		issues.append({"code": "planar3d.visibility_range_invalid", "field": field, "error_zh": "可见距离必须为有限非负值，结束距离不得小于开始距离。"})
	if node is CollisionShape3D and node.shape == null:
		issues.append({"code": "planar3d.collision_shape_missing", "field": field, "error_zh": "碰撞节点缺少 Shape3D 资源。"})
	for child in node.get_children(): _validate_scene_node(child, issues, field + "/" + str(child.name))

static func publish(result: Dictionary, center: GMErrorCenter) -> void:
	for issue in result.get("issues", []):
		center.add_error(str(issue.get("code", "planar3d.invalid")), "planar3d", "3D资源", str(issue.get("resource_path", result.get("resource_path", ""))), str(issue.get("field_name_zh", issue.get("field", "资源配置"))), str(issue.get("error_zh", "资源无效。")), "定位资源并修正所列字段；仅安全字段可批量修复。", 0, str(issue.get("field", "")))
