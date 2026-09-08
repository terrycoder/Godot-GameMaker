@tool
class_name GMTemplateDefinition
extends Resource

## 编辑器模板只描述策划入口，不携带任何运行时代码或第二份内容数据。
@export var template_id: String = ""
@export var display_name_zh: String = ""
@export_multiline var description_zh: String = ""
@export var layout_sections: PackedStringArray = []
@export var terminology: Dictionary = {}
@export var required_terminology_keys: PackedStringArray = []
@export var common_ability_bundles: PackedStringArray = []
@export var creation_wizards: Array[Dictionary] = []
@export var validation_rules: PackedStringArray = []
@export var required_modules: PackedStringArray = []
@export var default_enabled_modules: PackedStringArray = []
@export var optional_modules: PackedStringArray = []
@export var preserved_content_kinds: PackedStringArray = []
@export var help_entry_id: String = ""

func has_terminology(key: String) -> bool:
	return terminology.has(key) and not str(terminology.get(key, "")).is_empty()

func display_section(key: String) -> String:
	return str(terminology.get(key, key))

func to_summary() -> Dictionary:
	return {
		"template_id": template_id,
		"display_name_zh": display_name_zh,
		"description_zh": description_zh,
		"layout_sections": Array(layout_sections),
		"terminology_keys": terminology.keys(),
		"common_ability_bundles": Array(common_ability_bundles),
		"creation_wizards": creation_wizards.duplicate(true),
		"validation_rules": Array(validation_rules),
		"required_modules": Array(required_modules),
		"default_enabled_modules": Array(default_enabled_modules),
		"optional_modules": Array(optional_modules),
		"preserved_content_kinds": Array(preserved_content_kinds),
	}
