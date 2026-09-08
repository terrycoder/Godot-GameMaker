@tool
class_name GMAccessoryAsset
extends GMCharacterPart

@export_group("Accessory 连接")
@export var accessory_category: String = "prop"
@export var compatible_outfit_family_ids: PackedStringArray = PackedStringArray()
@export var compatible_outfit_variant_ids: PackedStringArray = PackedStringArray()

func _init() -> void:
	part_slot = "accessory"

func validate_part() -> Dictionary:
	var result := super.validate_part()
	if part_slot != "accessory": result.issues.append(GMCharacter3DContract.failure("character.accessory_slot_invalid", "Accessory 资源必须使用 accessory 槽位。")); result.ok = false
	if accessory_category.strip_edges().is_empty(): result.issues.append(GMCharacter3DContract.failure("character.accessory_category_missing", "Accessory 类别不能为空。")); result.ok = false
	result.issues.append_array(GMCharacter3DContract.unique_strings(compatible_outfit_family_ids, "character.accessory_outfit_family", "Accessory Outfit Family 列表不能包含空项或重复项。"))
	result.issues.append_array(GMCharacter3DContract.unique_strings(compatible_outfit_variant_ids, "character.accessory_outfit_variant", "Accessory Outfit Variant 列表不能包含空项或重复项。"))
	return result

func supports_outfit(outfit_family_id: String, outfit_variant_id: String) -> bool:
	var family_ok := compatible_outfit_family_ids.is_empty() or compatible_outfit_family_ids.has(outfit_family_id)
	var variant_ok := compatible_outfit_variant_ids.is_empty() or compatible_outfit_variant_ids.has(outfit_variant_id)
	return family_ok and variant_ok

func to_accessory_descriptor() -> Dictionary:
	return {"content_id": content_id, "accessory_category": accessory_category, "attachment_socket_id": attachment_socket_id, "compatible_outfit_family_ids": Array(compatible_outfit_family_ids), "compatible_outfit_variant_ids": Array(compatible_outfit_variant_ids)}
