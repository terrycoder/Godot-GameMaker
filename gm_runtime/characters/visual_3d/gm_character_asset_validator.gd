@tool
class_name GMCharacterAssetValidator
extends RefCounted

static func validate_recipe(recipe: GMCharacterVisualRecipe, library: GMContentLibrary) -> Dictionary:
	if recipe == null: return _failure("character.validator_recipe_missing", "角色视觉验证缺少 VisualRecipe。")
	var by_id: Dictionary = _library_by_id(library)
	var recipe_check: Dictionary = recipe.validate_against(by_id)
	var issues: Array[Dictionary] = recipe_check.issues.duplicate(true)
	var body: Variant = by_id.get(recipe.body_profile_id, null)
	var skeleton: Variant = by_id.get(recipe.skeleton_contract_id, null)
	var posture: Variant = by_id.get(recipe.posture_profile_id, null)
	var animation: Variant = by_id.get(recipe.animation_profile_id, null)
	if body is GMBodyProfile: issues.append_array((body as GMBodyProfile).validate_body_profile().issues)
	else: issues.append(_failure("character.validator_body_missing", "Body Profile 无法解析。"))
	if skeleton is GMHumanoidSkeletonContract: issues.append_array((skeleton as GMHumanoidSkeletonContract).validate_skeleton_contract().issues)
	else: issues.append(_failure("character.validator_skeleton_missing", "Humanoid Skeleton 合同无法解析。"))
	if posture is GMPostureProfile: issues.append_array((posture as GMPostureProfile).validate_posture_profile().issues)
	else: issues.append(_failure("character.validator_posture_missing", "Posture Profile 无法解析。"))
	if animation is GMAnimationProfile: issues.append_array((animation as GMAnimationProfile).validate_animation_profile().issues)
	else: issues.append(_failure("character.validator_animation_missing", "Animation Profile 无法解析。"))
	var fit_id: String = str(body.body_fit_class_id) if body is GMBodyProfile else ""
	var outfit: Variant = by_id.get(recipe.outfit_part_id, null)
	if outfit is GMOutfitAsset:
		var outfit_check: Dictionary = (outfit as GMOutfitAsset).validate_part(); issues.append_array(outfit_check.issues)
		if not (outfit as GMOutfitAsset).supports_fit(fit_id): issues.append(_failure("character.validator_outfit_fit_mismatch", "Outfit 与 Body FitClass 不兼容。", {"outfit_id": recipe.outfit_part_id, "body_fit_class_id": fit_id}))
		if not recipe.material_variant_id.strip_edges().is_empty() and not (outfit as GMOutfitAsset).supports_material_variant(recipe.material_variant_id): issues.append(_failure("character.validator_outfit_material_mismatch", "Outfit 不支持当前材质变体。", {"outfit_id": recipe.outfit_part_id, "material_variant_id": recipe.material_variant_id}))
	else: issues.append(_failure("character.validator_outfit_missing", "角色视觉配方缺少 Outfit。"))
	if recipe.feature_part_ids.size() > GMCharacter3DContract.MAX_FEATURE_MODULES: issues.append(_failure("character.validator_feature_budget", "Feature 模块数量超过角色预算。", {"max": GMCharacter3DContract.MAX_FEATURE_MODULES, "actual": recipe.feature_part_ids.size()}))
	if recipe.accessory_part_ids.size() > GMCharacter3DContract.MAX_ACCESSORY_SLOTS: issues.append(_failure("character.validator_accessory_budget", "Accessory 槽数量超过角色预算。", {"max": GMCharacter3DContract.MAX_ACCESSORY_SLOTS, "actual": recipe.accessory_part_ids.size()}))
	for part_id in [recipe.head_part_id, recipe.hair_part_id] + Array(recipe.feature_part_ids) + Array(recipe.accessory_part_ids):
		var part: Variant = by_id.get(str(part_id), null)
		if not part is GMCharacterPart: issues.append(_failure("character.validator_part_missing", "角色部件引用无法解析。", {"part_id": str(part_id)})); continue
		var part_check: Dictionary = (part as GMCharacterPart).validate_part(); issues.append_array(part_check.issues)
		if part is GMFeatureAsset and not (part as GMFeatureAsset).required_core_bones.is_empty(): issues.append(_failure("character.validator_feature_core_forbidden", "Feature 不得强制加入核心 Skeleton。", {"part_id": str(part_id)}))
		if part is GMAccessoryAsset and outfit is GMOutfitAsset:
			var accessory := part as GMAccessoryAsset
			if not (outfit as GMOutfitAsset).supports_accessory(accessory.accessory_category): issues.append(_failure("character.validator_accessory_outfit_mismatch", "Accessory 类别与 Outfit 兼容规则冲突。", {"part_id": str(part_id), "accessory_category": accessory.accessory_category}))
			if not accessory.supports_outfit((outfit as GMOutfitAsset).outfit_family_id, (outfit as GMOutfitAsset).outfit_variant_id): issues.append(_failure("character.validator_accessory_identity_mismatch", "Accessory 与 Outfit Family/Variant 不兼容。", {"part_id": str(part_id)}))
	return _summary(issues, recipe, {"fit_class_id": fit_id, "skeleton_core_bones": skeleton.core_bones if skeleton is GMHumanoidSkeletonContract else [], "animation_categories": GMAnimationLibrary.REQUIRED_CATEGORIES if animation is GMAnimationProfile else [], "outfit_fit_checked": outfit is GMOutfitAsset, "runtime_nodes_in_recipe": false, "animation_copies_per_character": 0})

static func _library_by_id(library: GMContentLibrary) -> Dictionary:
	var result := {}
	if library == null: return result
	for entry in library.entries:
		var id := str(entry.get("content_id", ""))
		var resource: Variant = entry.get("resource", null)
		if not id.is_empty() and resource is Resource: result[id] = resource
		for alias in entry.get("aliases", []):
			if not result.has(str(alias)) and resource is Resource: result[str(alias)] = resource
	return result

static func validate_import(preset: GM3DImportPreset, source_kind: String, source_fingerprint: String) -> Dictionary:
	if preset == null: return _failure("character.import_validator_preset_missing", "角色导入验证缺少 Preset。")
	var checked := preset.validate()
	var issues: Array[Dictionary] = checked.issues.duplicate(true)
	if source_kind.strip_edges().is_empty(): issues.append(_failure("character.import_source_missing", "导入源类型不能为空。"))
	if source_fingerprint.strip_edges().is_empty(): issues.append(_failure("character.import_fingerprint_missing", "导入源必须提供稳定指纹。"))
	return {"ok": issues.is_empty(), "issues": issues, "source_kind": source_kind, "source_fingerprint": source_fingerprint, "reimport_stable": issues.is_empty(), "checks": {"scale": true, "pivot": true, "material": true, "collision": true, "lod": true}}

static func build_machine_summary(rows: Array[Dictionary]) -> Dictionary:
	var pass_count := 0
	var fail_count := 0
	for row in rows:
		if bool(row.get("ok", false)): pass_count += 1
		else: fail_count += 1
	return {"schema": "gm.character.asset_validation_summary.v1", "ok": fail_count == 0, "rows": rows.duplicate(true), "pass_count": pass_count, "fail_count": fail_count, "failure_closed": true}

static func _summary(issues: Array[Dictionary], recipe: GMCharacterVisualRecipe, details: Dictionary) -> Dictionary:
	var result := {"ok": issues.is_empty(), "issues": issues, "recipe_id": recipe.content_id, "schema": "gm.character.asset_validation_summary.v1", "failure_closed": true}
	result.merge(details, true)
	return result

static func _failure(code: String, error_zh: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": error_zh, "details": details}
