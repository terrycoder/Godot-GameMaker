@tool
class_name GMPostureProfile
extends GMContent

const CONTENT_TYPE_ID := "gm.character.posture_profile"

@export_group("姿态语义")
@export_range(-45.0, 45.0, 0.1) var idle_spine_pitch_degrees: float = 0.0
@export_range(0.1, 3.0, 0.01) var walk_stride_scale: float = 1.0
@export_range(0.1, 3.0, 0.01) var interaction_reach_scale: float = 1.0
@export var root_offset: Vector3 = Vector3.ZERO
@export var semantic_pose_offsets: Dictionary = {}

func validate_posture_profile() -> Dictionary:
	var issues: Array[Dictionary] = []
	if content_type_id.is_empty(): content_type_id = CONTENT_TYPE_ID
	if not is_finite(idle_spine_pitch_degrees): issues.append(GMCharacter3DContract.failure("character.posture_pitch_invalid", "Idle 脊柱角度必须是有限数。"))
	for check in [
		GMCharacter3DContract.validate_positive(walk_stride_scale, "walk_stride_scale", "行走步幅缩放"),
		GMCharacter3DContract.validate_positive(interaction_reach_scale, "interaction_reach_scale", "交互触及缩放"),
	]:
		if not check.ok: issues.append(check)
	for key in semantic_pose_offsets.keys():
		if str(key).strip_edges().is_empty(): issues.append(GMCharacter3DContract.failure("character.posture_semantic_empty", "姿态语义名称不能是空值。"))
		if not semantic_pose_offsets[key] is Vector3: issues.append(GMCharacter3DContract.failure("character.posture_offset_invalid", "姿态偏移必须是 Vector3。", {"semantic": str(key)}))
	return {"ok": issues.is_empty(), "issues": issues, "does_not_duplicate_model": true}

func offset_for(semantic_action_id: StringName) -> Vector3:
	var value: Variant = semantic_pose_offsets.get(str(semantic_action_id), Vector3.ZERO)
	return value if value is Vector3 else Vector3.ZERO
