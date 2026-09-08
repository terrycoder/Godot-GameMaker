class_name GMGameplayTag
extends RefCounted

## GameplayTag 的不可变值对象。平台标签使用 gm.*；项目标签禁止写入该命名空间。

var value: String = ""
var platform_owned: bool = false

func _init(tag_value: String = "", is_platform: bool = false) -> void:
	value = normalize(tag_value)
	platform_owned = is_platform

static func normalize(tag_value: String) -> String:
	return tag_value.strip_edges().replace(" ", "").replace("/", ".")

static func validate(tag_value: String, allow_platform_namespace: bool = false) -> Dictionary:
	var normalized := normalize(tag_value)
	if normalized.is_empty():
		return {"ok": false, "code": "tag.empty", "reason_zh": "GameplayTag 不能为空。"}
	if normalized.begins_with("gm.") and not allow_platform_namespace:
		return {"ok": false, "code": "tag.illegal_namespace", "reason_zh": "项目 GameplayTag 不得写入 gm.* 命名空间：%s" % normalized}
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$")
	if regex.search(normalized) == null:
		return {"ok": false, "code": "tag.invalid_format", "reason_zh": "GameplayTag 格式非法：%s；只允许小写字母、数字、下划线和层级点号。" % normalized}
	return {"ok": true, "value": normalized}

func is_empty() -> bool:
	return value.is_empty()

func is_child_of(parent_tag: String) -> bool:
	var parent := normalize(parent_tag)
	return not parent.is_empty() and value.begins_with(parent + ".")

func is_parent_of(child_tag: String) -> bool:
	var child := normalize(child_tag)
	return not child.is_empty() and child.begins_with(value + ".")

func parent() -> String:
	var parts: Array = Array(value.split("."))
	if parts.size() <= 1:
		return ""
	parts.pop_back()
	return ".".join(parts)

func matches_exact(other: String) -> bool:
	return value == normalize(other)

func matches_hierarchy(other: String) -> bool:
	var candidate := normalize(other)
	return value == candidate or is_child_of(candidate) or candidate.begins_with(value + ".")

func to_dict() -> Dictionary:
	return {"value": value, "platform_owned": platform_owned, "parent": parent()}
