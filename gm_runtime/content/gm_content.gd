@tool
class_name GMContent
extends Resource

## GM 内容的唯一运行时事实源。
##
## 这里故意只保存可序列化的内容身份与声明式引用，不保存缓存、计时器、节点
## 或其他运行时状态。文件路径由 Godot ResourceUID 管理，业务身份由 content_id
## 管理，两者始终分离。

@export_group("GM 内容身份")
@export var display_name_zh: String = ""
@export var content_id: String = ""
@export var content_type_id: String = ""
@export var tags: PackedStringArray = PackedStringArray()
@export var content_version: String = "1.0.0"
@export var source: String = "authoring"

@export_group("废弃与迁移")
@export var deprecated: bool = false
@export var aliases: PackedStringArray = PackedStringArray()
@export var migration_from_ids: PackedStringArray = PackedStringArray()
@export var migration_target_id: String = ""
@export_multiline var migration_notes_zh: String = ""

@export_group("声明式引用")
## 只有这些字段中的业务 ID 才会被引用图作为强引用解析。
@export var content_reference_ids: PackedStringArray = PackedStringArray()
## 能力包是声明式业务 ID，不会通过普通备注字符串猜测。
@export var ability_package_ids: PackedStringArray = PackedStringArray()
@export var structured_references: Array[GMContentReference] = []

@export_group("预览")
## 真实 Texture2D Resource 缩略图；它和内容身份一起保存在同一 Resource 中。
@export var thumbnail: Texture2D
@export_file("*.png", "*.jpg", "*.jpeg", "*.svg") var thumbnail_path: String = ""

func get_declared_business_references(include_ability_packages: bool = true) -> Array[String]:
	var result: Array[String] = []
	for value in content_reference_ids:
		_append_unique(result, str(value))
	for reference in structured_references:
		if reference != null:
			_append_unique(result, reference.target_id)
	if include_ability_packages:
		for value in ability_package_ids:
			_append_unique(result, str(value))
	return result

func get_declared_reference_specs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in content_reference_ids:
		result.append({"target_id": str(value), "kind": "business_id", "field": "content_reference_ids", "strength": "strong"})
	for reference in structured_references:
		if reference == null: continue
		result.append({
			"target_id": reference.target_id,
			"kind": reference.relation_kind,
			"field": reference.field_name_zh,
			"expected_type_id": reference.expected_type_id,
			"optional": reference.optional,
			"strength": "optional" if reference.optional else "strong",
		})
	for value in ability_package_ids:
		result.append({"target_id": str(value), "kind": "ability_package", "field": "ability_package_ids", "strength": "strong"})
	return result

func canonical_or_alias_matches(value: String) -> bool:
	return value == content_id or aliases.has(value)

func identity_snapshot() -> Dictionary:
	return {
		"display_name_zh": display_name_zh,
		"content_id": content_id,
		"content_type_id": content_type_id,
		"tags": Array(tags),
		"content_version": content_version,
		"source": source,
		"deprecated": deprecated,
		"aliases": Array(aliases),
		"migration_from_ids": Array(migration_from_ids),
		"migration_target_id": migration_target_id,
		"thumbnail_resource_path": thumbnail.resource_path if thumbnail != null else "",
		"thumbnail_path": thumbnail_path,
	}

func _append_unique(values: Array[String], value: String) -> void:
	var normalized := value.strip_edges()
	if not normalized.is_empty() and not values.has(normalized): values.append(normalized)
