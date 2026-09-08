@tool
class_name GMAnimationLibrary
extends GMContent

const CONTENT_TYPE_ID := "gm.character.animation_library"
const REQUIRED_CATEGORIES := ["locomotion", "work", "interaction", "social", "combat", "reaction"]

@export_group("共享动画库")
@export var library_version: String = "1.0.0"
@export var animation_asset_ids: PackedStringArray = PackedStringArray()
@export var profiles: Array[Resource] = []

func validate_animation_library() -> Dictionary:
	var issues: Array[Dictionary] = []
	if content_type_id.is_empty(): content_type_id = CONTENT_TYPE_ID
	issues.append_array(GMCharacter3DContract.unique_strings(animation_asset_ids, "character.animation_asset", "共享动画资产列表不能包含空项或重复项。"))
	var profile_ids := {}
	var categories := {}
	for raw_profile in profiles:
		if not raw_profile is GMAnimationProfile:
			issues.append(GMCharacter3DContract.failure("character.animation_profile_type_invalid", "Animation Library 只能引用 GMAnimationProfile。")); continue
		var profile: GMAnimationProfile = raw_profile
		if profile_ids.has(profile.content_id): issues.append(GMCharacter3DContract.failure("character.animation_profile_duplicate", "Animation Profile ID 重复。", {"content_id": profile.content_id}))
		profile_ids[profile.content_id] = true
		var profile_check := profile.validate_animation_profile()
		issues.append_array(profile_check.issues)
		for action_id in profile.semantic_action_map:
			categories[str(action_id).get_slice(".", 0)] = true
	for category in REQUIRED_CATEGORIES:
		if not categories.has(category): issues.append(GMCharacter3DContract.failure("character.animation_library_category_missing", "共享动画库缺少动作类别。", {"category": category}))
	return {"ok": issues.is_empty(), "issues": issues, "required_categories": REQUIRED_CATEGORIES.duplicate(), "profile_count": profiles.size(), "animation_asset_count": animation_asset_ids.size(), "shared": true, "character_copies": 0}

func profile_for(profile_id: String) -> GMAnimationProfile:
	for raw_profile in profiles:
		if raw_profile is GMAnimationProfile and (raw_profile as GMAnimationProfile).content_id == profile_id: return raw_profile
	return null

func resolve(profile_id: String, semantic_action_id: StringName) -> Dictionary:
	var profile := profile_for(profile_id)
	if profile == null: return GMCharacter3DContract.failure("character.animation_profile_not_found", "共享 Animation Profile 不存在。", {"profile_id": profile_id})
	return profile.resolve_semantic_action(semantic_action_id)
