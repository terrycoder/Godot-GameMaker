@tool
class_name GMBodyFitClass
extends GMContent

## A small shared fit vocabulary. Bodies reference this value instead of
## duplicating per-outfit geometry or storing runtime nodes.

const CONTENT_TYPE_ID := "gm.character.body_fit_class"
const ALLOWED_FIT_IDS := ["slim", "standard", "broad", "compact"]

@export_group("体型适配")
@export var fit_id: String = "standard"
@export_range(0.1, 4.0, 0.01) var height_scale: float = 1.0
@export_range(0.1, 4.0, 0.01) var width_scale: float = 1.0
@export_range(0.0, 1.0, 0.001) var outfit_clearance: float = 0.04
@export var compatible_outfit_ids: PackedStringArray = PackedStringArray()

func validate_fit_class() -> Dictionary:
	var issues: Array[Dictionary] = []
	if content_type_id.is_empty(): content_type_id = CONTENT_TYPE_ID
	if fit_id not in ALLOWED_FIT_IDS:
		issues.append(GMCharacter3DContract.failure("character.fit_class_unsupported", "体型适配类别不受支持。", {"fit_id": fit_id, "allowed": ALLOWED_FIT_IDS}))
	for check in [
		GMCharacter3DContract.validate_positive(height_scale, "height_scale", "高度缩放"),
		GMCharacter3DContract.validate_positive(width_scale, "width_scale", "宽度缩放"),
		GMCharacter3DContract.validate_nonnegative(outfit_clearance, "outfit_clearance", "服装间隙"),
	]:
		if not check.ok: issues.append(check)
	issues.append_array(GMCharacter3DContract.unique_strings(compatible_outfit_ids, "character.fit_outfit", "体型适配服装列表不能包含空项或重复项。"))
	return {"ok": issues.is_empty(), "issues": issues, "fit_id": fit_id, "shared": true}

func to_fit_descriptor() -> Dictionary:
	return {
		"fit_id": fit_id,
		"height_scale": height_scale,
		"width_scale": width_scale,
		"outfit_clearance": outfit_clearance,
		"compatible_outfit_ids": Array(compatible_outfit_ids),
	}
