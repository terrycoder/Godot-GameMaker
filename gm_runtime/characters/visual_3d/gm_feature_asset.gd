@tool
class_name GMFeatureAsset
extends GMCharacterPart

@export_group("Feature 连接")
@export_enum("socket", "surface", "world") var attach_mode: String = "socket"
@export_enum("static", "animated") var module_kind: String = "static"
## Features may use a socket, but are never silently promoted into the core
## humanoid skeleton.
@export var required_core_bones: PackedStringArray = PackedStringArray()
@export var local_skeleton_bones: PackedStringArray = PackedStringArray()
@export_enum("x", "y", "z") var secondary_motion_axis: String = "y"
@export_range(0.0, 2.0, 0.01) var secondary_motion_amplitude: float = 0.0
@export_range(0.0, 12.0, 0.01) var secondary_motion_frequency: float = 0.0

func _init() -> void:
	part_slot = "feature"

func validate_part() -> Dictionary:
	var result := super.validate_part()
	if part_slot != "feature": result.issues.append(GMCharacter3DContract.failure("character.feature_slot_invalid", "Feature 资源必须使用 feature 槽位。")); result.ok = false
	if not required_core_bones.is_empty():
		result.issues.append(GMCharacter3DContract.failure("character.feature_core_skeleton_forbidden", "Feature 不得强制加入 Humanoid 核心骨骼。", {"required_core_bones": Array(required_core_bones)})); result.ok = false
	result.issues.append_array(GMCharacter3DContract.unique_strings(local_skeleton_bones, "character.feature_local_bone", "Feature Local Skeleton 骨骼不能包含空项或重复项。"))
	if module_kind not in ["static", "animated"]:
		result.issues.append(GMCharacter3DContract.failure("character.feature_module_kind_invalid", "Feature 模块类型不受支持。", {"module_kind": module_kind})); result.ok = false
	if not is_finite(secondary_motion_amplitude) or secondary_motion_amplitude < 0.0:
		result.issues.append(GMCharacter3DContract.failure("character.feature_motion_amplitude_invalid", "Feature Secondary Motion 振幅必须是非负有限数。")); result.ok = false
	if not is_finite(secondary_motion_frequency) or secondary_motion_frequency < 0.0:
		result.issues.append(GMCharacter3DContract.failure("character.feature_motion_frequency_invalid", "Feature Secondary Motion 频率必须是非负有限数。")); result.ok = false
	if not local_skeleton_bones.is_empty() and module_kind != "animated":
		result.issues.append(GMCharacter3DContract.failure("character.feature_local_skeleton_static", "只有 Animated Feature 可以声明 Local Skeleton。")); result.ok = false
	return result

func to_feature_descriptor() -> Dictionary:
	return {
		"content_id": content_id,
		"attach_mode": attach_mode,
		"module_kind": module_kind,
		"attachment_socket_id": attachment_socket_id,
		"local_skeleton_bones": Array(local_skeleton_bones),
		"secondary_motion_axis": secondary_motion_axis,
		"secondary_motion_amplitude": secondary_motion_amplitude,
		"secondary_motion_frequency": secondary_motion_frequency,
		"feature_bones_forced": false,
	}
