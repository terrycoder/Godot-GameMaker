@tool
class_name GMHumanoidSkeletonContract
extends GMContent

const CONTENT_TYPE_ID := "gm.character.humanoid_skeleton_contract"
const CONTRACT_VERSION := "1.0.0"
const REQUIRED_CORE_BONES := [
	"root", "pelvis", "spine", "chest", "neck", "head",
	"upper_arm_l", "lower_arm_l", "hand_l", "upper_arm_r", "lower_arm_r", "hand_r",
	"upper_leg_l", "lower_leg_l", "foot_l", "upper_leg_r", "lower_leg_r", "foot_r",
]
const ALLOWED_FORWARD_AXES := ["negative_z", "positive_z", "negative_x", "positive_x"]

@export_group("核心骨骼合同")
@export var contract_version: String = CONTRACT_VERSION
@export var core_bones: PackedStringArray = PackedStringArray(REQUIRED_CORE_BONES)
@export var root_bone: String = "root"
@export_enum("negative_z", "positive_z", "negative_x", "positive_x") var forward_axis: String = "negative_z"
@export_enum("y", "negative_y") var up_axis: String = "y"
@export_range(0.0001, 100.0, 0.0001) var meters_per_unit: float = 1.0
@export var sockets: Array[Resource] = []

@export_group("外部动画映射")
## source bone name -> canonical GM humanoid bone name.  This is a map, not a
## copied Animation resource or a per-character animation library.
@export var external_bone_mapping: Dictionary = {}

func validate_skeleton_contract() -> Dictionary:
	var issues: Array[Dictionary] = []
	if content_type_id.is_empty(): content_type_id = CONTENT_TYPE_ID
	if contract_version != CONTRACT_VERSION: issues.append(GMCharacter3DContract.failure("character.skeleton_version_unsupported", "Humanoid Skeleton 合同版本不受支持。", {"expected": CONTRACT_VERSION, "actual": contract_version}))
	if forward_axis not in ALLOWED_FORWARD_AXES: issues.append(GMCharacter3DContract.failure("character.skeleton_forward_axis_invalid", "Skeleton 朝向轴不受支持。"))
	if up_axis not in ["y", "negative_y"]: issues.append(GMCharacter3DContract.failure("character.skeleton_up_axis_invalid", "Skeleton 上方向轴不受支持。"))
	if not GMCharacter3DContract.validate_positive(meters_per_unit, "meters_per_unit", "Skeleton 尺度").ok: issues.append(GMCharacter3DContract.failure("character.skeleton_scale_invalid", "Skeleton Scale 必须是大于零的有限数。"))
	if root_bone.is_empty() or not core_bones.has(root_bone): issues.append(GMCharacter3DContract.failure("character.skeleton_root_invalid", "Skeleton Root 必须属于核心骨骼。", {"root_bone": root_bone}))
	var seen := {}
	for bone in core_bones:
		if str(bone).strip_edges().is_empty(): issues.append(GMCharacter3DContract.failure("character.skeleton_bone_empty", "核心骨骼名称不能为空。"))
		elif seen.has(str(bone)): issues.append(GMCharacter3DContract.failure("character.skeleton_bone_duplicate", "核心骨骼名称不能重复。", {"bone_name": str(bone)}))
		else: seen[str(bone)] = true
	for required in REQUIRED_CORE_BONES:
		if not core_bones.has(required): issues.append(GMCharacter3DContract.failure("character.skeleton_core_missing", "核心骨骼合同缺少必需骨骼。", {"bone_name": required}))
	var socket_ids := {}
	for raw_socket in sockets:
		if not raw_socket is GMHumanoidSkeletonSocket:
			issues.append(GMCharacter3DContract.failure("character.socket_type_invalid", "Skeleton Socket 必须使用 GMHumanoidSkeletonSocket。")); continue
		var socket: GMHumanoidSkeletonSocket = raw_socket
		if socket_ids.has(socket.socket_id): issues.append(GMCharacter3DContract.failure("character.socket_duplicate", "Skeleton Socket 稳定标识重复。", {"socket_id": socket.socket_id}))
		socket_ids[socket.socket_id] = true
		var socket_check := socket.validate(core_bones)
		issues.append_array(socket_check.issues)
	for source_bone in external_bone_mapping:
		var target_bone := str(external_bone_mapping[source_bone])
		if target_bone.is_empty() or not core_bones.has(target_bone):
			issues.append(GMCharacter3DContract.failure("character.external_bone_mapping_invalid", "外部动画骨骼映射目标不在核心合同中。", {"source": str(source_bone), "target": target_bone}))
	return {"ok": issues.is_empty(), "issues": issues, "core_bone_count": core_bones.size(), "socket_count": sockets.size(), "root_bone": root_bone, "forward_axis": forward_axis, "meters_per_unit": meters_per_unit, "feature_bones_forced": false}

func map_external_bones(source_bones: PackedStringArray) -> Dictionary:
	var mapped := {}
	var missing: Array[String] = []
	for source_bone in source_bones:
		if not external_bone_mapping.has(source_bone):
			missing.append(str(source_bone)); continue
		mapped[str(source_bone)] = str(external_bone_mapping[source_bone])
	missing.sort()
	return {"ok": missing.is_empty(), "mapped": mapped, "missing": missing, "unmapped_is_failure_closed": true}

func socket_for(socket_id: String) -> GMHumanoidSkeletonSocket:
	for raw_socket in sockets:
		if raw_socket is GMHumanoidSkeletonSocket and (raw_socket as GMHumanoidSkeletonSocket).socket_id == socket_id: return raw_socket
	return null

func to_contract_report() -> Dictionary:
	var socket_rows: Array = []
	for raw_socket in sockets:
		if raw_socket is GMHumanoidSkeletonSocket: socket_rows.append((raw_socket as GMHumanoidSkeletonSocket).to_descriptor())
	socket_rows.sort_custom(func(left: Dictionary, right: Dictionary): return str(left.socket_id) < str(right.socket_id))
	return {"schema": "gm.character.humanoid_skeleton_contract.v1", "content_id": content_id, "contract_version": contract_version, "core_bones": Array(core_bones), "root_bone": root_bone, "forward_axis": forward_axis, "up_axis": up_axis, "meters_per_unit": meters_per_unit, "sockets": socket_rows, "external_bone_mapping": external_bone_mapping.duplicate(true), "feature_bones_forced": false}
