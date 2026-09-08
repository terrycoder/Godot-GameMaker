@tool
class_name GMHumanoidSkeletonSocket
extends Resource

@export var socket_id: String = ""
@export var bone_name: String = ""
@export var local_transform: Transform3D = Transform3D.IDENTITY
@export var allowed_part_slots: PackedStringArray = PackedStringArray()
@export var optional: bool = true

func validate(core_bones: PackedStringArray) -> Dictionary:
	var issues: Array[Dictionary] = []
	if socket_id.strip_edges().is_empty(): issues.append(GMCharacter3DContract.failure("character.socket_id_missing", "Socket 缺少稳定标识。"))
	if bone_name.strip_edges().is_empty(): issues.append(GMCharacter3DContract.failure("character.socket_bone_missing", "Socket 缺少骨骼名称。"))
	elif not core_bones.has(bone_name): issues.append(GMCharacter3DContract.failure("character.socket_bone_unknown", "Socket 绑定了不在核心骨骼合同中的骨骼。", {"socket_id": socket_id, "bone_name": bone_name}))
	for issue in GMCharacter3DContract.unique_strings(allowed_part_slots, "character.socket_slot", "Socket 部件槽列表不能包含空项或重复项。"): issues.append(issue)
	return {"ok": issues.is_empty(), "issues": issues}

func to_descriptor() -> Dictionary:
	return {"socket_id": socket_id, "bone_name": bone_name, "local_transform": local_transform, "allowed_part_slots": Array(allowed_part_slots), "optional": optional}
