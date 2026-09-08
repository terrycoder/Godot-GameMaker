@tool
class_name GMHairAsset
extends GMCharacterPart

func _init() -> void:
	part_slot = "hair"

func validate_part() -> Dictionary:
	var result := super.validate_part()
	if part_slot != "hair": result.issues.append(GMCharacter3DContract.failure("character.hair_slot_invalid", "Hair 资源必须使用 hair 槽位。")); result.ok = false
	return result
