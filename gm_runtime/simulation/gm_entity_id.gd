class_name GMEntityId
extends RefCounted

const PREFIX := "gm.entity."

var value: String = ""

func _init(p_value: String = "") -> void:
	value = normalize(p_value)

func is_valid() -> bool:
	return validate_value(value).ok

func as_string() -> String:
	return value

static func normalize(p_value: String) -> String:
	return p_value.strip_edges()

static func validate_value(p_value: String) -> Dictionary:
	var candidate := normalize(p_value)
	var errors: Array[String] = []
	if candidate.is_empty(): errors.append("实体身份不能为空。")
	if not candidate.begins_with(PREFIX): errors.append("实体身份必须使用 gm.entity.* 命名空间。")
	if candidate.contains(" ") or candidate.contains("\t") or candidate.contains("\r") or candidate.contains("\n"):
		errors.append("实体身份不得包含空白。")
	if candidate.contains("NodePath") or candidate.contains("res://") or candidate.contains("user://") or candidate.begins_with("/"):
		errors.append("实体身份不得使用路径或运行时引用。")
	return {"ok": errors.is_empty(), "code": "entity_id.valid" if errors.is_empty() else "entity_id.invalid", "errors": errors, "entity_id": candidate}

static func make(p_namespace: String, local_id: String) -> String:
	return "%s%s.%s" % [PREFIX, p_namespace.strip_edges().to_lower(), local_id.strip_edges().to_lower()]
