@tool
class_name GMOutfitVariant
extends Resource

const SCHEMA := "gm.character.outfit_variant.v1"

@export var variant_id: String = ""
@export var family_id: String = ""
@export var material_variant_id: String = ""
@export var compatible_fit_class_ids: PackedStringArray = PackedStringArray()
@export var compatible_accessory_category_ids: PackedStringArray = PackedStringArray()

func validate() -> Dictionary:
	var issues: Array = []
	for row in [[variant_id, "outfit_variant"], [family_id, "outfit_family"], [material_variant_id, "material_variant"]]:
		var check := GMCharacter3DContract.validate_id(str(row[0]), str(row[1]))
		if not check.ok: issues.append(check)
	issues.append_array(GMCharacter3DContract.unique_strings(compatible_fit_class_ids, "character.outfit_variant_fit", "Outfit Variant FitClass 列表不能包含空项或重复项。"))
	issues.append_array(GMCharacter3DContract.unique_strings(compatible_accessory_category_ids, "character.outfit_variant_accessory", "Outfit Variant 附件类别不能包含空项或重复项。"))
	return {"ok": issues.is_empty(), "schema": SCHEMA, "issues": issues, "variant_id": variant_id, "family_id": family_id}

func to_descriptor() -> Dictionary:
	return {"schema": SCHEMA, "variant_id": variant_id, "family_id": family_id, "material_variant_id": material_variant_id, "compatible_fit_class_ids": Array(compatible_fit_class_ids), "compatible_accessory_category_ids": Array(compatible_accessory_category_ids)}
