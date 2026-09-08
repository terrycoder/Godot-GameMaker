@tool
class_name GMOutfitAsset
extends GMCharacterPart

@export_group("服装适配")
@export var outfit_family_id: String = "gm.character.outfit_family.neutral"
@export var outfit_variant_id: String = "gm.character.outfit_variant.neutral"
@export var compatible_body_fit_class_ids: PackedStringArray = PackedStringArray()
@export var hide_body_surface_ids: PackedStringArray = PackedStringArray()
@export var job_tags: PackedStringArray = PackedStringArray()
@export var style_tags: PackedStringArray = PackedStringArray()
@export var material_variant_ids: PackedStringArray = PackedStringArray()
@export var compatible_accessory_category_ids: PackedStringArray = PackedStringArray()

func _init() -> void:
	part_slot = "outfit"
	optional = false

func validate_part() -> Dictionary:
	var result := super.validate_part()
	if part_slot != "outfit": result.issues.append(GMCharacter3DContract.failure("character.outfit_slot_invalid", "Outfit 资源必须使用 outfit 槽位。")); result.ok = false
	for field in [[outfit_family_id, "outfit_family"], [outfit_variant_id, "outfit_variant"]]:
		if not GMCharacter3DContract.validate_id(str(field[0]), str(field[1])).ok:
			result.issues.append(GMCharacter3DContract.failure("character.outfit_identity_invalid", "Outfit Family/Variant 必须使用稳定 ID。", {"field": str(field[1])})); result.ok = false
	result.issues.append_array(GMCharacter3DContract.unique_strings(compatible_body_fit_class_ids, "character.outfit_fit", "Outfit FitClass 列表不能包含空项或重复项。"))
	result.issues.append_array(GMCharacter3DContract.unique_strings(hide_body_surface_ids, "character.outfit_hide", "Outfit 隐藏表面列表不能包含空项或重复项。"))
	result.issues.append_array(GMCharacter3DContract.unique_strings(job_tags, "character.outfit_job", "Outfit 职位标签不能包含空项或重复项。"))
	result.issues.append_array(GMCharacter3DContract.unique_strings(style_tags, "character.outfit_style", "Outfit 风格标签不能包含空项或重复项。"))
	result.issues.append_array(GMCharacter3DContract.unique_strings(material_variant_ids, "character.outfit_material", "Outfit 材质变体不能包含空项或重复项。"))
	result.issues.append_array(GMCharacter3DContract.unique_strings(compatible_accessory_category_ids, "character.outfit_accessory", "Outfit 附件兼容类别不能包含空项或重复项。"))
	return result

func supports_fit(fit_class_id: String) -> bool:
	return compatible_body_fit_class_ids.is_empty() or compatible_body_fit_class_ids.has(fit_class_id)

func supports_accessory(category_id: String) -> bool:
	return compatible_accessory_category_ids.is_empty() or compatible_accessory_category_ids.has(category_id)

func supports_material_variant(variant_id: String) -> bool:
	return material_variant_ids.is_empty() or material_variant_ids.has(variant_id)

func to_outfit_descriptor() -> Dictionary:
	return {
		"content_id": content_id,
		"outfit_family_id": outfit_family_id,
		"outfit_variant_id": outfit_variant_id,
		"fit_classes": Array(compatible_body_fit_class_ids),
		"job_tags": Array(job_tags),
		"style_tags": Array(style_tags),
		"material_variant_ids": Array(material_variant_ids),
		"compatible_accessory_category_ids": Array(compatible_accessory_category_ids),
		"hide_body_surface_ids": Array(hide_body_surface_ids),
	}
