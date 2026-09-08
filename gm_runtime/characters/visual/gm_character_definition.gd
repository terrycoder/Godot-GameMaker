@tool
class_name GMCharacterDefinition
extends GMContent

## 角色内容身份与可替换外观映射。玩法能力、NPC、商店和对象实例身份不存入视觉包。
@export var visual_sets: Array[GMCharacterVisualSet2D] = []
@export var default_visual_set_id: String = ""
@export var usage_locations: PackedStringArray = PackedStringArray()
@export var identity_configuration_label: String = ""

func resolve_visual_set(requested_id: String = "") -> Dictionary:
	var target := requested_id if not requested_id.is_empty() else default_visual_set_id
	for visual_set in visual_sets:
		if visual_set != null and visual_set.visual_set_id == target:
			return {"ok": true, "visual_set": visual_set, "character_content_id": content_id}
	return {"ok": false, "code": "character.visual_set_not_found", "error_zh": "角色外观映射不存在。", "details": {"character_content_id": content_id, "visual_set_id": target}}

func validate_definition() -> Dictionary:
	var issues: Array[Dictionary] = []
	if content_id.strip_edges().is_empty(): issues.append({"ok": false, "code": "character.content_id_missing", "error_zh": "角色定义缺少任务03稳定内容ID。"})
	var ids := {}
	for visual_set in visual_sets:
		if visual_set == null: issues.append({"ok": false, "code": "character.visual_set_null", "error_zh": "角色外观列表包含空项。"}); continue
		if ids.has(visual_set.visual_set_id): issues.append({"ok": false, "code": "character.visual_set_duplicate", "error_zh": "角色外观ID重复。", "details": {"visual_set_id": visual_set.visual_set_id}})
		ids[visual_set.visual_set_id] = true
		var checked: Dictionary = visual_set.validate_visual_set()
		issues.append_array(checked.issues)
	if not ids.has(default_visual_set_id): issues.append({"ok": false, "code": "character.default_visual_missing", "error_zh": "默认外观ID无法解析。"})
	return {"ok": issues.is_empty(), "issues": issues}
