@tool
class_name GMCharacterVisual3D
extends Node3D

## Unified derived 3D character visual.  The public appearance API is shared by
## players and NPCs; only the owner/control layer differs outside this node.
## `GMCharacterVisualRecipe` remains stable content data and is never mutated by
## this runtime tree.

const SLOT_NAMES := ["Body", "Head", "Hair", "Outfit", "Feature", "Accessory"]

var recipe: GMCharacterVisualRecipe
var resolver: GMCharacterVisual3DResolver
var current_semantic_action_id: StringName = &""
var current_shared_animation_asset_id := ""
var degraded_action := false
var last_validation: Dictionary = {}
var _part_nodes: Array[MeshInstance3D] = []
var _animated_nodes: Array[Node3D] = []
var _runtime_roots: Array[Node] = []
var _body_master: MeshInstance3D
var _body_region_nodes: Dictionary = {}
var _feature_module_nodes: Dictionary = {}
var _accessory_module_nodes: Dictionary = {}
var _body_hide_degraded := false
## Optional artist-authored simplified meshes keyed by part slot (head, outfit...).
@export var mid_lod_meshes: Dictionary = {}
@export var far_lod_meshes: Dictionary = {}
var _visual_lod := "Near"
var _lod_originals: Dictionary = {}
var _visual_sample_count := 0

func set_visual_quality(lod: String, show_features: bool = true, show_skinned: bool = true) -> Dictionary:
	if lod not in ["Near", "Mid", "Far", "Offscreen"]:
		return _failure("character.lod_invalid", "视觉层级必须是近景、中景、远景或屏外。")
	# Near is the unconditional recovery path. Invalid authored LOD mappings must
	# never prevent unload/unregister from restoring the original presentation.
	if lod != "Near":
		var checked := validate_lod_meshes()
		if not checked.ok: return checked
	_visual_lod = lod
	for node in _part_nodes:
		if not is_instance_valid(node): continue
		if not _lod_originals.has(node): _lod_originals[node] = {"mesh": node.mesh, "visible": node.visible, "lod_bias": node.lod_bias}
		var original: Dictionary = _lod_originals[node]
		var slot := str(node.get_meta("gm_character_part_slot", ""))
		var mapping: Dictionary = mid_lod_meshes if lod == "Mid" else far_lod_meshes if lod == "Far" else {}
		node.mesh = mapping.get(slot, original.mesh)
		node.lod_bias = 0.5 if lod == "Mid" else 0.15 if lod == "Far" else original.lod_bias
		var skinned := original.mesh != null and (node.skin != null or bool(original.mesh.get_meta("skinned", false)))
		node.visible = original.visible and lod != "Offscreen" and (show_skinned or not skinned)
		if slot.begins_with("feature") or slot.begins_with("accessory"):
			node.visible = node.visible and show_features
	return {"ok": true, "lod": lod}

func validate_lod_meshes() -> Dictionary:
	for mapping in [mid_lod_meshes, far_lod_meshes]:
		for mesh in mapping.values():
			if not mesh is Mesh: return _failure("character.lod_mesh_invalid", "简化网格必须引用 Mesh 资源，旧表现保持不变。")
	return {"ok": true}

func visual_sampling_snapshot() -> Dictionary:
	return {"lod": _visual_lod, "sample_count": _visual_sample_count}

func configure(p_recipe: GMCharacterVisualRecipe, p_resolver: GMCharacterVisual3DResolver) -> Dictionary:
	if p_recipe == null or p_resolver == null: return _failure("character.runtime_config_missing", "3D 角色视觉配置缺少配方或解析器。")
	var check := p_resolver.validate(p_recipe)
	if not check.ok: return check
	return _commit_candidate(p_recipe, p_resolver, check)

func play_semantic_action(semantic_action_id: StringName) -> Dictionary:
	if recipe == null or resolver == null: return _failure("character.runtime_not_configured", "3D 角色视觉尚未配置。")
	var profile := resolver.resolve(recipe.animation_profile_id)
	if not profile is GMAnimationProfile: return _failure("character.runtime_animation_profile_missing", "运行时无法解析共享 Animation Profile。")
	var resolved := (profile as GMAnimationProfile).resolve_semantic_action(semantic_action_id)
	if not resolved.ok: return resolved
	current_semantic_action_id = semantic_action_id
	current_shared_animation_asset_id = str(resolved.animation_asset_id)
	degraded_action = bool(resolved.get("degraded", false))
	return {"ok": true, "semantic_action_id": str(semantic_action_id), "shared_animation_asset_id": current_shared_animation_asset_id, "degraded": degraded_action, "animation_copied": false, "domain_facts_written": false}

func apply_posture() -> Dictionary:
	if recipe == null or resolver == null: return _failure("character.runtime_not_configured", "3D 角色视觉尚未配置。")
	var body := resolver.resolve(recipe.body_profile_id)
	var posture := resolver.resolve(recipe.posture_profile_id)
	if not body is GMBodyProfile or not posture is GMPostureProfile: return _failure("character.runtime_posture_missing", "运行时无法解析 Body/Posture Profile。")
	var fit := resolver.resolve((body as GMBodyProfile).body_fit_class_id)
	var height_scale := 1.0
	var width_scale := 1.0
	if fit is GMBodyFitClass:
		height_scale = (fit as GMBodyFitClass).height_scale
		width_scale = (fit as GMBodyFitClass).width_scale
	scale = Vector3(width_scale, height_scale, width_scale)
	position = (posture as GMPostureProfile).root_offset
	return {"ok": true, "scale": scale, "root_offset": position, "semantic_action_id": str(current_semantic_action_id), "model_copies": 0}

## Unified appearance API -----------------------------------------------------

func set_body_profile(value: Variant) -> Dictionary:
	return _replace_recipe_field("body_profile_id", _content_id(value), "Body Profile")

func set_head(value: Variant) -> Dictionary:
	return _replace_recipe_field("head_part_id", _content_id(value), "Head")

func set_hair(value: Variant) -> Dictionary:
	return _replace_recipe_field("hair_part_id", _content_id(value), "Hair")

func set_outfit(value: Variant) -> Dictionary:
	return _replace_recipe_field("outfit_part_id", _content_id(value), "Outfit")

func add_feature(value: Variant) -> Dictionary:
	if recipe == null: return _failure("character.runtime_not_configured", "3D 角色视觉尚未配置。")
	var feature_id := _content_id(value)
	if feature_id.is_empty(): return _failure("character.api_feature_missing", "添加 Feature 需要稳定 Feature ID。")
	if recipe.feature_part_ids.has(feature_id): return {"ok": true, "changed": false, "idempotent": true, "feature_id": feature_id}
	var candidate := _candidate_recipe()
	candidate.feature_part_ids.append(feature_id)
	return _commit_candidate_recipe(candidate, "add_feature")

func remove_feature(value: Variant) -> Dictionary:
	if recipe == null: return _failure("character.runtime_not_configured", "3D 角色视觉尚未配置。")
	var feature_id := _content_id(value)
	if feature_id.is_empty(): return _failure("character.api_feature_missing", "移除 Feature 需要稳定 Feature ID。")
	if not recipe.feature_part_ids.has(feature_id): return {"ok": true, "changed": false, "idempotent": true, "feature_id": feature_id}
	var candidate := _candidate_recipe()
	candidate.feature_part_ids.remove_at(candidate.feature_part_ids.find(feature_id))
	return _commit_candidate_recipe(candidate, "remove_feature")

func set_palette(value: Variant) -> Dictionary:
	if recipe == null: return _failure("character.runtime_not_configured", "3D 角色视觉尚未配置。")
	var candidate := _candidate_recipe()
	if value is Dictionary:
		var palette: Dictionary = value
		candidate.palette_profile_id = str(palette.get("palette_profile_id", palette.get("id", "")))
		var colors: Variant = palette.get("colors", {})
		if not colors is Dictionary: return _failure("character.api_palette_invalid", "Palette 颜色必须是纯数据字典。")
		candidate.palette_overrides = colors.duplicate(true)
	elif value is String or value is StringName:
		candidate.palette_profile_id = str(value)
		candidate.palette_overrides = {}
	else:
		return _failure("character.api_palette_invalid", "Palette 必须是稳定 ID 或纯数据字典。")
	if not candidate.palette_profile_id.is_empty() and not GMCharacter3DContract.validate_id(candidate.palette_profile_id, "palette_profile").ok:
		return _failure("character.api_palette_invalid", "Palette Profile 必须使用稳定 ID。")
	if candidate.palette_profile_id == recipe.palette_profile_id and candidate.palette_overrides == recipe.palette_overrides:
		return {"ok": true, "changed": false, "idempotent": true, "palette_profile_id": candidate.palette_profile_id}
	return _commit_candidate_recipe(candidate, "set_palette")

func set_body_hide(region_id: String, hidden: bool = true) -> Dictionary:
	if recipe == null: return _failure("character.runtime_not_configured", "3D 角色视觉尚未配置。")
	if region_id not in GMBodyProfile.BODY_REGIONS: return _failure("character.api_body_region_invalid", "Body Hide 区域不受支持。", {"region_id": region_id})
	var candidate := _candidate_recipe()
	if hidden and not candidate.body_hide_region_ids.has(region_id): candidate.body_hide_region_ids.append(region_id)
	if not hidden and candidate.body_hide_region_ids.has(region_id): candidate.body_hide_region_ids.remove_at(candidate.body_hide_region_ids.find(region_id))
	candidate.body_hide_region_ids.sort()
	if candidate.body_hide_region_ids == recipe.body_hide_region_ids: return {"ok": true, "changed": false, "idempotent": true, "region_id": region_id, "hidden": hidden}
	return _commit_candidate_recipe(candidate, "set_body_hide")

func set_material_variant(value: Variant) -> Dictionary:
	return _replace_recipe_field("material_variant_id", _content_id(value), "材质变体")

func appearance_snapshot() -> Dictionary:
	if recipe == null: return {"schema": "gm.character.appearance.v1", "visual_recipe_id": "", "configured": false}
	return {"schema": "gm.character.appearance.v1", "visual_recipe_id": recipe.content_id, "body_profile_id": recipe.body_profile_id, "head_part_id": recipe.head_part_id, "hair_part_id": recipe.hair_part_id, "outfit_part_id": recipe.outfit_part_id, "feature_part_ids": Array(recipe.feature_part_ids), "accessory_part_ids": Array(recipe.accessory_part_ids), "body_hide_region_ids": Array(recipe.body_hide_region_ids), "palette_profile_id": recipe.palette_profile_id, "palette_overrides": recipe.palette_overrides.duplicate(true), "material_variant_id": recipe.material_variant_id}

## Visual contributor for the existing WorldSnapshot/Store chain.  It is pure
## data and intentionally contains no NodePath or RID.
func to_persistence_record() -> Dictionary:
	var result := appearance_snapshot()
	result["runtime_action"] = str(current_semantic_action_id)
	result["shared_animation_asset_id"] = current_shared_animation_asset_id
	return result

func restore_appearance_record(value: Dictionary) -> Dictionary:
	if recipe == null: return _failure("character.restore_not_configured", "恢复外观前必须先配置基础 VisualRecipe。")
	var candidate := _candidate_recipe()
	for field in ["body_profile_id", "head_part_id", "hair_part_id", "outfit_part_id", "palette_profile_id", "material_variant_id"]:
		if value.has(field): candidate.set(field, str(value.get(field, "")))
	if value.has("feature_part_ids") and value.feature_part_ids is Array: candidate.feature_part_ids = PackedStringArray(value.feature_part_ids)
	if value.has("accessory_part_ids") and value.accessory_part_ids is Array: candidate.accessory_part_ids = PackedStringArray(value.accessory_part_ids)
	if value.has("body_hide_region_ids") and value.body_hide_region_ids is Array: candidate.body_hide_region_ids = PackedStringArray(value.body_hide_region_ids)
	if value.has("palette_overrides") and value.palette_overrides is Dictionary: candidate.palette_overrides = value.palette_overrides.duplicate(true)
	var result := _commit_candidate_recipe(candidate, "restore_appearance")
	if result.ok and value.has("runtime_action"):
		result["restored_action"] = play_semantic_action(StringName(str(value.runtime_action)))
	return result

func snapshot() -> Dictionary:
	var parts: Array = []
	for node in _part_nodes:
		if node != null and is_instance_valid(node): parts.append({"name": node.name, "mesh_class": node.mesh.get_class() if node.mesh != null else "", "mesh_resource_path": node.mesh.resource_path if node.mesh != null else "", "slot": str(node.get_meta("gm_character_part_slot", ""))})
	return {"schema": "gm.character.visual_runtime.v2", "recipe_id": recipe.content_id if recipe != null else "", "current_semantic_action_id": str(current_semantic_action_id), "shared_animation_asset_id": current_shared_animation_asset_id, "degraded_action": degraded_action, "parts": parts, "animation_copy_count": 0, "recipe_contains_runtime_nodes": false, "domain_facts_written": false, "root_slots": SLOT_NAMES.duplicate(), "body_master_preserved": _body_master != null and is_instance_valid(_body_master), "body_master_visible": _body_master.visible if _body_master != null and is_instance_valid(_body_master) else false, "body_hide_region_ids": Array(recipe.body_hide_region_ids) if recipe != null else [], "body_hide_degraded": _body_hide_degraded, "feature_module_count": _feature_module_nodes.size(), "accessory_slot_count": _accessory_module_nodes.size(), "local_skeleton_count": _local_skeleton_count(), "node_budget": budget_report()}

func budget_report() -> Dictionary:
	var node_count := _count_nodes(self)
	var skinned_mesh_count := 0
	for node in _part_nodes:
		if node != null and is_instance_valid(node):
			var original: Mesh = _lod_originals.get(node, {}).get("mesh", node.mesh)
			if original != null and (node.skin != null or bool(original.get_meta("skinned", false))): skinned_mesh_count += 1
	return {"ok": node_count <= GMCharacter3DContract.MAX_CHARACTER_NODES and skinned_mesh_count <= GMCharacter3DContract.MAX_SKINNED_MESHES, "node_count": node_count, "max_nodes": GMCharacter3DContract.MAX_CHARACTER_NODES, "skinned_mesh_count": skinned_mesh_count, "max_skinned_meshes": GMCharacter3DContract.MAX_SKINNED_MESHES, "feature_module_count": _feature_module_nodes.size(), "max_feature_modules": GMCharacter3DContract.MAX_FEATURE_MODULES, "accessory_slot_count": _accessory_module_nodes.size(), "max_accessory_slots": GMCharacter3DContract.MAX_ACCESSORY_SLOTS, "local_skeleton_count": _local_skeleton_count(), "max_local_skeletons": GMCharacter3DContract.MAX_LOCAL_SKELETONS}

func unload() -> Dictionary:
	_clear_runtime_tree()
	recipe = null
	resolver = null
	current_semantic_action_id = &""
	current_shared_animation_asset_id = ""
	degraded_action = false
	last_validation = {}
	return {"ok": true, "cleared": true, "animation_copy_count": 0}

func _commit_candidate_recipe(candidate: GMCharacterVisualRecipe, operation: String) -> Dictionary:
	if resolver == null: return _failure("character.runtime_resolver_missing", "3D 角色视觉缺少内容解析器。")
	var check := resolver.validate(candidate)
	if not check.ok: return _failure("character.runtime_candidate_rejected", "外观候选未通过校验，旧角色状态保持不变。", {"operation": operation, "validation": check, "failure_state_unchanged": true})
	return _commit_candidate(candidate, resolver, check, operation)

func _commit_candidate(p_recipe: GMCharacterVisualRecipe, p_resolver: GMCharacterVisual3DResolver, check: Dictionary, operation: String = "configure") -> Dictionary:
	var staged := Node3D.new()
	var build := _build_staged(staged, p_recipe, p_resolver)
	if not build.ok:
		staged.free()
		return build
	var old_recipe_id := recipe.content_id if recipe != null else ""
	_clear_runtime_tree()
	for child in staged.get_children():
		staged.remove_child(child)
		add_child(child)
		_runtime_roots.append(child)
	staged.free()
	recipe = p_recipe
	resolver = p_resolver
	last_validation = check
	current_semantic_action_id = &""
	current_shared_animation_asset_id = ""
	degraded_action = false
	_reindex_runtime_nodes()
	_apply_palette_to_nodes()
	var budget := budget_report()
	if not budget.ok: return _failure("character.runtime_budget_exceeded", "角色视觉运行树超过节点或 SkinnedMesh 预算。", {"budget": budget})
	return {"ok": true, "operation": operation, "recipe_id": recipe.content_id, "previous_recipe_id": old_recipe_id, "part_count": _part_nodes.size(), "animation_copy_count": 0, "runtime_nodes_outside_recipe": true, "root_slots": SLOT_NAMES.duplicate(), "budget": budget, "body_master_preserved": _body_master != null and is_instance_valid(_body_master)}

func _build_staged(staged: Node3D, p_recipe: GMCharacterVisualRecipe, p_resolver: GMCharacterVisual3DResolver) -> Dictionary:
	var body := p_resolver.resolve(p_recipe.body_profile_id)
	var skeleton_contract := p_resolver.resolve(p_recipe.skeleton_contract_id)
	if not body is GMBodyProfile or (body as GMBodyProfile).mesh == null: return _failure("character.runtime_body_mesh_missing", "运行时 Body Mesh 不可用。")
	if not skeleton_contract is GMHumanoidSkeletonContract: return _failure("character.runtime_skeleton_missing", "运行时 Humanoid Skeleton 合同不可用。")
	var body_slot := _slot(staged, "Body")
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	skeleton.set_meta("gm_core_skeleton", true)
	body_slot.add_child(skeleton)
	_build_skeleton(skeleton, skeleton_contract as GMHumanoidSkeletonContract)
	var body_master := MeshInstance3D.new()
	body_master.name = "BodyMaster"
	body_master.mesh = (body as GMBodyProfile).mesh
	body_master.set_meta("gm_character_part_slot", "body")
	body_master.set_meta("gm_body_master_preserved", true)
	body_slot.add_child(body_master)
	if not (body as GMBodyProfile).region_meshes.is_empty():
		body_master.visible = false
		for region_id in (body as GMBodyProfile).region_meshes.keys():
			var region_mesh: Variant = (body as GMBodyProfile).region_meshes[region_id]
			if not region_mesh is Mesh: continue
			var region_node := MeshInstance3D.new()
			region_node.name = "BodyRegion_%s" % str(region_id)
			region_node.mesh = region_mesh
			region_node.visible = not p_recipe.body_hide_region_ids.has(str(region_id))
			region_node.set_meta("gm_character_part_slot", "body_region:%s" % str(region_id))
			region_node.set_meta("gm_body_region", str(region_id))
			body_slot.add_child(region_node)
	var head := _resolve_required_part(p_resolver, p_recipe.head_part_id, "head", "Head")
	if not head.ok: return head
	var hair := _resolve_required_part(p_resolver, p_recipe.hair_part_id, "hair", "Hair")
	if not hair.ok: return hair
	var outfit := _resolve_required_part(p_resolver, p_recipe.outfit_part_id, "outfit", "Outfit")
	if not outfit.ok: return outfit
	_add_part_mesh(_slot(staged, "Head"), "Head", head.part.mesh, "head")
	_add_part_mesh(_slot(staged, "Hair"), "Hair", hair.part.mesh, "hair")
	_add_part_mesh(_slot(staged, "Outfit"), "Outfit", outfit.part.mesh, "outfit")
	var feature_slot := _slot(staged, "Feature")
	var accessory_slot := _slot(staged, "Accessory")
	var feature_result := _build_optional_modules(feature_slot, accessory_slot, skeleton, skeleton_contract as GMHumanoidSkeletonContract, p_recipe, p_resolver)
	if not feature_result.ok: return feature_result
	return {"ok": true}

func _resolve_required_part(p_resolver: GMCharacterVisual3DResolver, part_id: String, expected_slot: String, label: String) -> Dictionary:
	var part := p_resolver.resolve(part_id)
	if not part is GMCharacterPart or (part as GMCharacterPart).mesh == null: return _failure("character.runtime_part_mesh_missing", "运行时%s Mesh 不可用。" % label, {"part_id": part_id})
	if (part as GMCharacterPart).part_slot != expected_slot: return _failure("character.runtime_part_slot_invalid", "运行时%s 槽位不匹配。" % label, {"part_id": part_id, "expected": expected_slot})
	return {"ok": true, "part": part}

func _build_optional_modules(feature_slot: Node3D, accessory_slot: Node3D, skeleton: Skeleton3D, contract: GMHumanoidSkeletonContract, p_recipe: GMCharacterVisualRecipe, p_resolver: GMCharacterVisual3DResolver) -> Dictionary:
	if p_recipe.feature_part_ids.size() > GMCharacter3DContract.MAX_FEATURE_MODULES: return _failure("character.runtime_feature_budget", "Feature 模块数量超过预算。")
	if p_recipe.accessory_part_ids.size() > GMCharacter3DContract.MAX_ACCESSORY_SLOTS: return _failure("character.runtime_accessory_budget", "Accessory 槽数量超过预算。")
	var outfit := p_resolver.resolve(p_recipe.outfit_part_id) as GMOutfitAsset
	for feature_id in p_recipe.feature_part_ids:
		var feature := p_resolver.resolve(str(feature_id))
		if not feature is GMFeatureAsset or (feature as GMFeatureAsset).mesh == null: return _failure("character.runtime_feature_missing", "运行时 Feature 模块不可用。", {"feature_id": str(feature_id)})
		var feature_asset := feature as GMFeatureAsset
		var module_root := Node3D.new()
		module_root.name = "Feature_%s" % str(feature_id).get_file()
		module_root.set_meta("gm_feature_id", str(feature_id))
		module_root.set_meta("gm_module_kind", feature_asset.module_kind)
		module_root.set_meta("gm_motion_axis", feature_asset.secondary_motion_axis)
		module_root.set_meta("gm_motion_amplitude", feature_asset.secondary_motion_amplitude)
		module_root.set_meta("gm_motion_frequency", feature_asset.secondary_motion_frequency)
		var attach_parent: Node = feature_slot
		if feature_asset.attach_mode == "socket" and not feature_asset.attachment_socket_id.is_empty():
			var socket := contract.socket_for(feature_asset.attachment_socket_id)
			if socket == null: return _failure("character.runtime_feature_socket_missing", "Feature Socket 无法解析，装配失败且旧状态不变。", {"feature_id": str(feature_id), "socket_id": feature_asset.attachment_socket_id})
			var attachment := BoneAttachment3D.new()
			attachment.name = "FeatureSocket_%s" % str(feature_asset.attachment_socket_id).get_file()
			attachment.set("bone_name", socket.bone_name)
			attachment.transform = socket.local_transform
			attachment.set_meta("gm_socket_id", feature_asset.attachment_socket_id)
			skeleton.add_child(attachment)
			attach_parent = attachment
			attach_parent.add_child(module_root)
		else:
			feature_slot.add_child(module_root)
		if feature_asset.module_kind == "animated" and not feature_asset.local_skeleton_bones.is_empty():
			var local_skeleton := Skeleton3D.new()
			local_skeleton.name = "LocalSkeleton"
			local_skeleton.set_meta("gm_local_skeleton", true)
			_build_local_skeleton(local_skeleton, feature_asset.local_skeleton_bones)
			module_root.add_child(local_skeleton)
		var mesh_node := _add_part_mesh(module_root, "FeatureMesh", feature_asset.mesh, "feature")
		mesh_node.set_meta("gm_feature_id", str(feature_id))
		if feature_asset.module_kind == "animated": module_root.set_meta("gm_animated_feature", true)
		feature_slot.add_child(_slot_marker("FeatureSlot_%s" % str(feature_id).get_file()))
	for accessory_id in p_recipe.accessory_part_ids:
		var accessory := p_resolver.resolve(str(accessory_id))
		if not accessory is GMAccessoryAsset or (accessory as GMAccessoryAsset).mesh == null: return _failure("character.runtime_accessory_missing", "运行时 Accessory 槽不可用。", {"accessory_id": str(accessory_id)})
		var accessory_asset := accessory as GMAccessoryAsset
		if outfit != null and not outfit.supports_accessory(accessory_asset.accessory_category): return _failure("character.runtime_accessory_outfit_mismatch", "Accessory 与 Outfit 兼容规则冲突。", {"accessory_id": str(accessory_id)})
		if outfit != null and not accessory_asset.supports_outfit(outfit.outfit_family_id, outfit.outfit_variant_id): return _failure("character.runtime_accessory_identity_mismatch", "Accessory 与 Outfit Family/Variant 不兼容。", {"accessory_id": str(accessory_id)})
		var module_root := Node3D.new()
		module_root.name = "Accessory_%s" % str(accessory_id).get_file()
		module_root.set_meta("gm_accessory_id", str(accessory_id))
		var attach_parent: Node = accessory_slot
		if not accessory_asset.attachment_socket_id.is_empty():
			var socket := contract.socket_for(accessory_asset.attachment_socket_id)
			if socket == null: return _failure("character.runtime_accessory_socket_missing", "Accessory Socket 无法解析，装配失败且旧状态不变。", {"accessory_id": str(accessory_id), "socket_id": accessory_asset.attachment_socket_id})
			var attachment := BoneAttachment3D.new()
			attachment.name = "AccessorySocket_%s" % str(accessory_asset.attachment_socket_id).get_file()
			attachment.set("bone_name", socket.bone_name)
			attachment.transform = socket.local_transform
			attachment.set_meta("gm_socket_id", accessory_asset.attachment_socket_id)
			skeleton.add_child(attachment)
			attach_parent = attachment
			attach_parent.add_child(module_root)
		else:
			accessory_slot.add_child(module_root)
		_add_part_mesh(module_root, "AccessoryMesh", accessory_asset.mesh, "accessory")
		accessory_slot.add_child(_slot_marker("AccessorySlot_%s" % str(accessory_id).get_file()))
	return {"ok": true}

func _slot(parent: Node3D, slot_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = slot_name
	node.set_meta("gm_character_slot", slot_name.to_lower())
	parent.add_child(node)
	return node

func _slot_marker(marker_name: String) -> Node3D:
	var marker := Node3D.new()
	marker.name = marker_name
	marker.set_meta("gm_slot_marker", true)
	return marker

func _add_part_mesh(parent: Node, node_name: String, mesh: Mesh, slot_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.set_meta("gm_character_part_slot", slot_name)
	instance.set_meta("gm_visual_derived", true)
	parent.add_child(instance)
	return instance

func _build_skeleton(skeleton: Skeleton3D, contract: GMHumanoidSkeletonContract) -> void:
	var bone_indices := {}
	for bone_name in contract.core_bones:
		var index := skeleton.add_bone(str(bone_name))
		bone_indices[str(bone_name)] = index
	for bone_name in contract.core_bones:
		var parent_name := _parent_bone_name(str(bone_name), contract.core_bones)
		if not parent_name.is_empty(): skeleton.set_bone_parent(int(bone_indices[str(bone_name)]), int(bone_indices[parent_name]))

func _build_local_skeleton(skeleton: Skeleton3D, bone_names: PackedStringArray) -> void:
	var parent_index := -1
	for bone_name in bone_names:
		var index := skeleton.add_bone(str(bone_name))
		if parent_index >= 0: skeleton.set_bone_parent(index, parent_index)
		parent_index = index

func _parent_bone_name(bone_name: String, core_bones: PackedStringArray) -> String:
	if bone_name == "root": return ""
	if bone_name == "pelvis": return "root" if core_bones.has("root") else ""
	if bone_name == "spine": return "pelvis" if core_bones.has("pelvis") else "root"
	if bone_name == "chest": return "spine" if core_bones.has("spine") else "pelvis"
	if bone_name == "neck": return "chest" if core_bones.has("chest") else "spine"
	if bone_name == "head": return "neck" if core_bones.has("neck") else "chest"
	if bone_name.begins_with("upper_arm_"): return "chest"
	if bone_name.begins_with("lower_arm_"): return "upper_arm_" + bone_name.get_slice("_", 2)
	if bone_name.begins_with("hand_"): return "lower_arm_" + bone_name.get_slice("_", 1)
	if bone_name.begins_with("upper_leg_"): return "pelvis"
	if bone_name.begins_with("lower_leg_"): return "upper_leg_" + bone_name.get_slice("_", 2)
	if bone_name.begins_with("foot_"): return "lower_leg_" + bone_name.get_slice("_", 1)
	return ""

func _reindex_runtime_nodes() -> void:
	_part_nodes.clear()
	_animated_nodes.clear()
	_body_master = null
	_body_region_nodes.clear()
	_feature_module_nodes.clear()
	_accessory_module_nodes.clear()
	_body_hide_degraded = false
	for root in _runtime_roots: _index_node(root)
	if recipe != null:
		for region_id in recipe.body_hide_region_ids:
			if not _body_region_nodes.has(str(region_id)): _body_hide_degraded = true

func _index_node(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		_part_nodes.append(mesh_node)
		if mesh_node.name == "BodyMaster": _body_master = mesh_node
		var region_id := str(mesh_node.get_meta("gm_body_region")) if mesh_node.has_meta("gm_body_region") else ""
		if not region_id.is_empty(): _body_region_nodes[region_id] = mesh_node
	if node is Node3D and node.has_meta("gm_animated_feature") and bool(node.get_meta("gm_animated_feature")): _animated_nodes.append(node as Node3D)
	if node is Node3D and node.has_meta("gm_feature_id"): _feature_module_nodes[str(node.get_meta("gm_feature_id"))] = node
	if node is Node3D and node.has_meta("gm_accessory_id"): _accessory_module_nodes[str(node.get_meta("gm_accessory_id"))] = node
	for child in node.get_children(): _index_node(child)

func _apply_palette_to_nodes() -> void:
	if recipe == null: return
	var overrides: Dictionary = recipe.palette_overrides
	for node in _part_nodes:
		if node == null or not is_instance_valid(node): continue
		var slot := str(node.get_meta("gm_character_part_slot")) if node.has_meta("gm_character_part_slot") else ""
		var key := slot.split(":")[0]
		if not overrides.has(key) and not overrides.has("all"): continue
		var raw_color := str(overrides.get(key, overrides.get("all", "#ffffff")))
		if not raw_color.begins_with("#"): raw_color = "#" + raw_color
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(raw_color)
		node.material_override = material

func _process(_delta: float) -> void:
	if _visual_lod == "Offscreen": return
	sample_visual_pose(float(Time.get_ticks_msec()) / 1000.0)

func sample_visual_pose(now: float) -> void:
	if not is_finite(now) or _visual_lod == "Offscreen": return
	_visual_sample_count += 1
	if _animated_nodes.is_empty(): return
	for node in _animated_nodes:
		if node == null or not is_instance_valid(node): continue
		if not node.is_visible_in_tree(): continue
		var amplitude := float(node.get_meta("gm_motion_amplitude")) if node.has_meta("gm_motion_amplitude") else 0.0
		var frequency := float(node.get_meta("gm_motion_frequency")) if node.has_meta("gm_motion_frequency") else 0.0
		if amplitude <= 0.0 or frequency <= 0.0: continue
		var angle := sin(now * frequency * TAU) * amplitude
		var axis := str(node.get_meta("gm_motion_axis")) if node.has_meta("gm_motion_axis") else "y"
		if axis == "x": node.rotation.x = angle
		elif axis == "z": node.rotation.z = angle
		else: node.rotation.y = angle

func _clear_runtime_tree() -> void:
	_lod_originals.clear()
	_visual_lod = "Near"
	_visual_sample_count = 0
	for child in get_children(): child.free()
	_runtime_roots.clear()
	_part_nodes.clear()
	_animated_nodes.clear()
	_body_master = null
	_body_region_nodes.clear()
	_feature_module_nodes.clear()
	_accessory_module_nodes.clear()

func _replace_recipe_field(field_name: String, value: String, label: String) -> Dictionary:
	if recipe == null: return _failure("character.runtime_not_configured", "3D 角色视觉尚未配置。")
	if value.is_empty(): return _failure("character.api_value_missing", "%s 需要稳定 ID。" % label)
	if str(recipe.get(field_name)) == value: return {"ok": true, "changed": false, "idempotent": true, "field": field_name, "value": value}
	var candidate := _candidate_recipe()
	candidate.set(field_name, value)
	return _commit_candidate_recipe(candidate, "set_%s" % field_name)

func _candidate_recipe() -> GMCharacterVisualRecipe:
	return recipe.duplicate(true) as GMCharacterVisualRecipe

func _content_id(value: Variant) -> String:
	if value is GMContent: return str((value as GMContent).content_id)
	if value is Resource:
		var id := str(value.get("content_id"))
		if not id.is_empty(): return id
	return str(value).strip_edges()

func _count_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children(): count += _count_nodes(child)
	return count

func _local_skeleton_count() -> int:
	var count := 0
	for root in _runtime_roots: count += _count_named_nodes(root, "LocalSkeleton")
	return count

func _count_named_nodes(root: Node, target_name: String) -> int:
	var count := 1 if root.name == target_name else 0
	for child in root.get_children(): count += _count_named_nodes(child, target_name)
	return count

func _failure(code: String, error_zh: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": error_zh, "details": details, "failure_closed": true}
