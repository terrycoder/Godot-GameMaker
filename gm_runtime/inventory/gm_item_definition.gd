@tool
class_name GMItemDefinition
extends Resource

## Static identity for a reusable item kind. Dynamic state never belongs here.

const SCHEMA_VERSION := "gm.item_definition.v1"

@export var definition_id: String = ""
@export var display_name_zh: String = ""
@export var tags: PackedStringArray = PackedStringArray()
@export var stackable: bool = true
@export var max_stack: int = 99
@export var unit_weight: float = 0.0
@export var variant_keys: PackedStringArray = PackedStringArray()
@export var metadata: Dictionary = {}

func configure(p_definition_id: String, p_tags: PackedStringArray = PackedStringArray(), p_options: Dictionary = {}) -> GMItemDefinition:
	definition_id = p_definition_id.strip_edges()
	display_name_zh = str(p_options.get("display_name_zh", ""))
	tags = _unique_strings(p_tags)
	stackable = bool(p_options.get("stackable", true))
	max_stack = int(p_options.get("max_stack", 99))
	unit_weight = float(p_options.get("unit_weight", 0.0))
	variant_keys = _unique_strings(p_options.get("variant_keys", PackedStringArray()))
	metadata = p_options.get("metadata", {}).duplicate(true) if p_options.get("metadata", {}) is Dictionary else {}
	return self

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not _stable_id(definition_id): errors.append("物品定义 ID 必须是非空稳定业务身份。")
	if definition_id.contains("/item/") or definition_id.contains("NodePath"):
		errors.append("物品定义 ID 不得保存 NodePath 或文件路径。")
	if max_stack < 1: errors.append("物品定义最大堆叠数必须大于0。")
	if not stackable and max_stack != 1: errors.append("不可堆叠物品的最大堆叠数必须为1。")
	if unit_weight < 0.0: errors.append("单位重量不能为负数。")
	if not _unique(tags): errors.append("物品标签不能重复。")
	if not _unique(variant_keys): errors.append("变体键不能重复。")
	var stable := GMStableData.validate(metadata)
	if not stable.ok: errors.append_array(stable.errors)
	return {"ok": errors.is_empty(), "code": "item_definition.valid" if errors.is_empty() else "item_definition.invalid", "errors": errors}

func is_valid() -> bool:
	return bool(validate().get("ok", false))

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"definition_id": definition_id,
		"display_name_zh": display_name_zh,
		"tags": Array(tags),
		"stackable": stackable,
		"max_stack": max_stack,
		"unit_weight": unit_weight,
		"variant_keys": Array(variant_keys),
		"metadata": metadata.duplicate(true)
	}

static func from_dict(value: Dictionary) -> GMItemDefinition:
	var result := GMItemDefinition.new()
	result.definition_id = str(value.get("definition_id", value.get("id", "")))
	result.display_name_zh = str(value.get("display_name_zh", value.get("display_key", "")))
	result.tags = _string_array(value.get("tags", []))
	result.stackable = bool(value.get("stackable", true))
	result.max_stack = int(value.get("max_stack", 99))
	result.unit_weight = float(value.get("unit_weight", 0.0))
	result.variant_keys = _string_array(value.get("variant_keys", []))
	result.metadata = value.get("metadata", {}).duplicate(true) if value.get("metadata", {}) is Dictionary else {}
	return result

static func _stable_id(value: String) -> bool:
	return not value.strip_edges().is_empty() and not value.contains(" ") and not value.contains("\t") and not value.contains("res://") and not value.contains("user://") and not value.begins_with("/")

static func _unique(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		var key := str(value)
		if seen.has(key): return false
		seen[key] = true
	return true

static func _unique_strings(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	var values: Array = Array(value) if value is PackedStringArray else value if value is Array else []
	var seen: Dictionary = {}
	for item in values:
		var text := str(item).strip_edges()
		if text.is_empty() or seen.has(text): continue
		seen[text] = true
		result.append(text)
	return result

static func _string_array(value: Variant) -> PackedStringArray:
	return _unique_strings(value)
