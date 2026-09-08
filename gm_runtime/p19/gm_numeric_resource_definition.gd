@tool
class_name GMNumericResourceDefinition
extends Resource

## P19 numeric resource identity. Values are integer minor units only.

const SCHEMA_VERSION := "gm.numeric_resource_definition.v1"

@export var resource_id: String = ""
@export var display_name_zh: String = ""
@export var unit_id: String = "gm.unit.whole"
@export var minimum_value: int = 0
@export var maximum_capacity: int = -1
@export var metadata: Dictionary = {}

func configure(p_resource_id: String, p_unit_id: String = "gm.unit.whole", p_options: Dictionary = {}) -> GMNumericResourceDefinition:
	resource_id = p_resource_id.strip_edges()
	display_name_zh = str(p_options.get("display_name_zh", ""))
	unit_id = p_unit_id.strip_edges()
	minimum_value = int(p_options.get("minimum_value", p_options.get("minimum", 0)))
	maximum_capacity = int(p_options.get("maximum_capacity", p_options.get("capacity", -1)))
	metadata = p_options.get("metadata", {}).duplicate(true) if p_options.get("metadata", {}) is Dictionary else {}
	return self

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not _stable_id(resource_id) or not resource_id.begins_with("gm.resource."):
		errors.append("Numeric Resource ID 必须使用 gm.resource.* 稳定身份。")
	if not _stable_id(unit_id) or not unit_id.begins_with("gm.unit."):
		errors.append("Numeric Resource 必须声明 gm.unit.* 整数单位。")
	if minimum_value < 0:
		errors.append("Numeric Resource minimum_value 不能为负数。")
	if maximum_capacity == 0 or maximum_capacity < -1:
		errors.append("Numeric Resource maximum_capacity 必须是-1或正整数。")
	if maximum_capacity >= 0 and minimum_value > maximum_capacity:
		errors.append("Numeric Resource minimum_value 不能超过 maximum_capacity。")
	var stable := GMStableData.validate(metadata)
	if not stable.ok:
		errors.append_array(stable.errors)
	return {"ok": errors.is_empty(), "code": "numeric_resource_definition.valid" if errors.is_empty() else "numeric_resource_definition.invalid", "errors": errors}

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"resource_id": resource_id,
		"display_name_zh": display_name_zh,
		"unit_id": unit_id,
		"minimum_value": minimum_value,
		"maximum_capacity": maximum_capacity,
		"metadata": metadata.duplicate(true),
	}

static func from_dict(value: Dictionary) -> GMNumericResourceDefinition:
	var result := GMNumericResourceDefinition.new()
	result.resource_id = str(value.get("resource_id", value.get("id", "")))
	result.display_name_zh = str(value.get("display_name_zh", value.get("display_name", "")))
	result.unit_id = str(value.get("unit_id", value.get("unit", "gm.unit.whole")))
	result.minimum_value = int(value.get("minimum_value", value.get("minimum", 0)))
	result.maximum_capacity = int(value.get("maximum_capacity", value.get("capacity", -1)))
	result.metadata = value.get("metadata", {}).duplicate(true) if value.get("metadata", {}) is Dictionary else {}
	return result

static func _stable_id(value: String) -> bool:
	return not value.strip_edges().is_empty() and not value.contains(" ") and not value.contains("\t") and not value.contains("res://") and not value.contains("user://") and not value.begins_with("/")
