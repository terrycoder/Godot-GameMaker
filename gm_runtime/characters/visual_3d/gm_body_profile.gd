@tool
class_name GMBodyProfile
extends GMContent

const CONTENT_TYPE_ID := "gm.character.body_profile"
const BODY_REGIONS := ["head", "torso", "arm_l", "arm_r", "hand_l", "hand_r", "thigh_l", "thigh_r", "foot_l", "foot_r"]

@export_group("Body Profile")
@export var body_mesh_asset_id: String = ""
@export var skeleton_contract_id: String = ""
@export var body_fit_class_id: String = "gm.character.fit.standard"
@export var posture_profile_id: String = ""
@export var height_meters: float = 1.8
@export var mesh: Mesh
## Optional derived region meshes.  The complete `mesh` remains the Body Master
## source; these meshes are never written back or used as a replacement asset.
@export var region_meshes: Dictionary = {}

func validate_body_profile() -> Dictionary:
	var issues: Array[Dictionary] = []
	if content_type_id.is_empty(): content_type_id = CONTENT_TYPE_ID
	for check in [
		GMCharacter3DContract.validate_id(body_mesh_asset_id, "body_mesh_asset"),
		GMCharacter3DContract.validate_id(skeleton_contract_id, "skeleton_contract"),
		GMCharacter3DContract.validate_id(body_fit_class_id, "body_fit_class"),
		GMCharacter3DContract.validate_id(posture_profile_id, "posture_profile"),
		GMCharacter3DContract.validate_positive(height_meters, "height_meters", "身体高度"),
	]:
		if not check.ok: issues.append(check)
	if mesh == null: issues.append(GMCharacter3DContract.failure("character.body_mesh_missing", "Body Profile 缺少可渲染 Mesh。"))
	for region_id in region_meshes.keys():
		if str(region_id) not in BODY_REGIONS:
			issues.append(GMCharacter3DContract.failure("character.body_region_unknown", "Body Region 不受支持。", {"region_id": str(region_id)}))
		elif not region_meshes[region_id] is Mesh:
			issues.append(GMCharacter3DContract.failure("character.body_region_mesh_invalid", "Body Region 必须引用 Mesh。", {"region_id": str(region_id)}))
	return {"ok": issues.is_empty(), "issues": issues, "shared_fit_class": body_fit_class_id, "mesh_asset_id": body_mesh_asset_id}

func to_body_descriptor() -> Dictionary:
	return {
		"body_mesh_asset_id": body_mesh_asset_id,
		"skeleton_contract_id": skeleton_contract_id,
		"body_fit_class_id": body_fit_class_id,
		"posture_profile_id": posture_profile_id,
		"height_meters": height_meters,
		"has_mesh": mesh != null,
		"body_regions": Array(region_meshes.keys()),
		"body_master_preserved": mesh != null,
	}
