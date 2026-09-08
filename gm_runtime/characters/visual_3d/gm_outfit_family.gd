@tool
class_name GMOutfitFamily
extends Resource

const SCHEMA := "gm.character.outfit_family.v1"

@export var family_id: String = ""
@export var display_name_zh: String = ""
@export var job_tags: PackedStringArray = PackedStringArray()
@export var style_tags: PackedStringArray = PackedStringArray()

func validate() -> Dictionary:
	var id_check := GMCharacter3DContract.validate_id(family_id, "outfit_family")
	var issues: Array = []
	if not id_check.ok: issues.append(id_check)
	issues.append_array(GMCharacter3DContract.unique_strings(job_tags, "character.outfit_family_job", "Outfit Family 职位标签不能包含空项或重复项。"))
	issues.append_array(GMCharacter3DContract.unique_strings(style_tags, "character.outfit_family_style", "Outfit Family 风格标签不能包含空项或重复项。"))
	return {"ok": issues.is_empty(), "schema": SCHEMA, "issues": issues, "family_id": family_id}

func to_descriptor() -> Dictionary:
	return {"schema": SCHEMA, "family_id": family_id, "display_name_zh": display_name_zh, "job_tags": Array(job_tags), "style_tags": Array(style_tags)}
