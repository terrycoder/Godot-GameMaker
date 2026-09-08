@tool
class_name GMHeadAsset
extends GMCharacterPart

func _init() -> void:
	part_slot = "head"
	optional = false

func validate_part() -> Dictionary:
	var result := super.validate_part()
	if part_slot != "head": result.issues.append(GMCharacter3DContract.failure("character.head_slot_invalid", "Head 资源必须使用 head 槽位。")); result.ok = false
	return result
