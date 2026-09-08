@tool
class_name GMContentTypeDefinition
extends Resource

## 新内容类型的可重载注册信息。生成后仍是普通可编辑 Resource/GDScript。
@export var content_type_id: String = ""
@export var display_name_zh: String = ""
@export var generated_class_name: String = ""
@export var base_class_name: String = "GMContent"
@export var base_script_path: String = "res://gm_runtime/content/gm_content.gd"
@export var default_directory: String = ""
@export var icon_path: String = ""
@export var generated_script_path: String = ""
@export var validator_script_path: String = ""
@export var list_entry_script_path: String = ""
@export var test_template_path: String = ""
@export var sample_resource_path: String = ""
@export var editable_fields: PackedStringArray = PackedStringArray()
## 编辑字段元数据按索引一一对应：稳定属性名、中文显示名、中文帮助文本。
## 生成器和 Inspector 不从属性名猜测中文，字段缺元数据会被注册表拒绝。
@export var editable_field_labels_zh: PackedStringArray = PackedStringArray()
@export var editable_field_help_zh: PackedStringArray = PackedStringArray()
@export var registration_version: String = "1.0.0"
@export_multiline var description_zh: String = ""

func get_editable_field_metadata() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in editable_fields.size():
		var property_name := str(editable_fields[index])
		result.append({
			"property_name": property_name,
			"label_zh": str(editable_field_labels_zh[index]) if index < editable_field_labels_zh.size() else "",
			"help_zh": str(editable_field_help_zh[index]) if index < editable_field_help_zh.size() else "",
		})
	return result

func get_editable_field_metadata_for(property_name: String) -> Dictionary:
	for metadata in get_editable_field_metadata():
		if str(metadata.property_name) == property_name: return metadata
	return {}

func to_summary() -> Dictionary:
	return {
		"content_type_id": content_type_id,
		"display_name_zh": display_name_zh,
		"generated_class_name": generated_class_name,
		"base_class_name": base_class_name,
		"base_script_path": base_script_path,
		"default_directory": default_directory,
		"icon_path": icon_path,
		"generated_script_path": generated_script_path,
		"validator_script_path": validator_script_path,
		"list_entry_script_path": list_entry_script_path,
		"test_template_path": test_template_path,
		"sample_resource_path": sample_resource_path,
		"editable_fields": Array(editable_fields),
		"editable_field_labels_zh": Array(editable_field_labels_zh),
		"editable_field_help_zh": Array(editable_field_help_zh),
		"editable_field_metadata": get_editable_field_metadata(),
		"registration_version": registration_version,
		"description_zh": description_zh,
		"resource_path": resource_path,
	}
