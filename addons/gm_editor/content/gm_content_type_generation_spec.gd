@tool
class_name GMContentTypeGenerationSpec
extends RefCounted

var display_name_zh: String = ""
var content_type_id: String = ""
var generated_class_name: String = ""
var base_class_name: String = "GMContent"
var base_script_path: String = "res://gm_runtime/content/gm_content.gd"
var default_directory: String = "res://gm_runtime/content/generated"
var icon_path: String = ""
var description_zh: String = ""
var editable_fields: PackedStringArray = PackedStringArray(["notes_zh"])
var editable_field_labels_zh: PackedStringArray = PackedStringArray(["设计说明"])
var editable_field_help_zh: PackedStringArray = PackedStringArray(["填写该内容类型的设计说明，内容会直接保存到同一 Resource。"])

func to_dictionary() -> Dictionary:
	return {
		"display_name_zh": display_name_zh,
		"content_type_id": content_type_id,
		"generated_class_name": generated_class_name,
		"base_class_name": base_class_name,
		"base_script_path": base_script_path,
		"default_directory": default_directory,
		"icon_path": icon_path,
		"description_zh": description_zh,
		"editable_fields": Array(editable_fields),
		"editable_field_labels_zh": Array(editable_field_labels_zh),
		"editable_field_help_zh": Array(editable_field_help_zh),
	}
