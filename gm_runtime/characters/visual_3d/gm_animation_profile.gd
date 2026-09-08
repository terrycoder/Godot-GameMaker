@tool
class_name GMAnimationProfile
extends GMContent

const CONTENT_TYPE_ID := "gm.character.animation_profile"
const SEMANTIC_CATEGORIES := ["locomotion", "work", "interaction", "social", "combat", "reaction"]

@export_group("共享动画 Profile")
@export var animation_library_id: String = ""
## semantic_action_id -> shared animation asset ID.  The value is never copied
## into a character instance.
@export var semantic_action_map: Dictionary = {}
@export var fallback_by_category: Dictionary = {}

func validate_animation_profile() -> Dictionary:
	var issues: Array[Dictionary] = []
	if content_type_id.is_empty(): content_type_id = CONTENT_TYPE_ID
	if not GMCharacter3DContract.validate_id(animation_library_id, "animation_library").ok: issues.append(GMCharacter3DContract.failure("character.animation_library_missing", "Animation Profile 缺少共享动画库引用。"))
	var seen := {}
	for action_id in semantic_action_map:
		var action := str(action_id)
		var animation_id := str(semantic_action_map[action_id])
		if action.strip_edges().is_empty() or animation_id.strip_edges().is_empty():
			issues.append(GMCharacter3DContract.failure("character.animation_mapping_empty", "语义动作与共享动画引用不能为空。")); continue
		if seen.has(action): issues.append(GMCharacter3DContract.failure("character.animation_mapping_duplicate", "语义动作映射不能重复。", {"semantic_action_id": action}))
		seen[action] = true
		if not GMCharacter3DContract.validate_id(animation_id, "animation_asset").ok: issues.append(GMCharacter3DContract.failure("character.animation_asset_invalid", "共享动画资产 ID 无效。", {"semantic_action_id": action, "animation_asset_id": animation_id}))
	for category in SEMANTIC_CATEGORIES:
		var has_category := false
		for action_id in semantic_action_map.keys():
			if str(action_id).begins_with(category + "."): has_category = true; break
		if not has_category and not fallback_by_category.has(category): issues.append(GMCharacter3DContract.failure("character.animation_category_missing", "Animation Profile 缺少语义动作类别。", {"category": category}))
	for category in fallback_by_category:
		if str(category) not in SEMANTIC_CATEGORIES: issues.append(GMCharacter3DContract.failure("character.animation_fallback_category_invalid", "动画降级类别不受支持。", {"category": str(category)}))
	return {"ok": issues.is_empty(), "issues": issues, "semantic_action_count": semantic_action_map.size(), "categories": SEMANTIC_CATEGORIES.duplicate(), "shared_library": true, "copies_per_character": 0}

func resolve_semantic_action(semantic_action_id: StringName) -> Dictionary:
	var key := str(semantic_action_id)
	if semantic_action_map.has(key): return {"ok": true, "semantic_action_id": key, "animation_asset_id": str(semantic_action_map[key]), "source": "explicit", "shared": true}
	var category := key.get_slice(".", 0)
	if fallback_by_category.has(category): return {"ok": true, "semantic_action_id": key, "animation_asset_id": str(fallback_by_category[category]), "source": "category_fallback", "shared": true, "degraded": true}
	return GMCharacter3DContract.failure("character.animation_action_unmapped", "语义动作没有可用的共享动画映射或降级。", {"semantic_action_id": key})
