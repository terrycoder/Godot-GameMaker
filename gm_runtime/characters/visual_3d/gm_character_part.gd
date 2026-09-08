@tool
class_name GMCharacterPart
extends GMContent

const CONTENT_TYPE_ID := "gm.character.part"
const PART_SLOTS := ["head", "hair", "outfit", "feature", "accessory"]

@export_group("角色部件")
@export_enum("head", "hair", "outfit", "feature", "accessory") var part_slot: String = "feature"
@export var mesh_asset_id: String = ""
@export var mesh: Mesh
@export var material_asset_ids: PackedStringArray = PackedStringArray()
@export var attachment_socket_id: String = ""
@export var skeleton_contract_id: String = ""
@export var optional: bool = true

func validate_part() -> Dictionary:
	var issues: Array[Dictionary] = []
	if content_type_id.is_empty(): content_type_id = CONTENT_TYPE_ID
	if part_slot not in PART_SLOTS: issues.append(GMCharacter3DContract.failure("character.part_slot_invalid", "角色部件槽位不受支持。", {"part_slot": part_slot}))
	if not GMCharacter3DContract.validate_id(mesh_asset_id, "part_mesh_asset").ok: issues.append(GMCharacter3DContract.failure("character.part_mesh_missing", "角色部件缺少 Mesh 资产引用。"))
	if mesh == null: issues.append(GMCharacter3DContract.failure("character.part_mesh_resource_missing", "角色部件缺少可渲染 Mesh 资源。", {"part_slot": part_slot}))
	if not attachment_socket_id.is_empty() and not GMCharacter3DContract.validate_id(attachment_socket_id, "attachment_socket").ok: issues.append(GMCharacter3DContract.failure("character.part_socket_invalid", "部件 Socket 引用格式无效。"))
	if not skeleton_contract_id.is_empty() and not GMCharacter3DContract.validate_id(skeleton_contract_id, "part_skeleton_contract").ok: issues.append(GMCharacter3DContract.failure("character.part_skeleton_invalid", "部件 Skeleton 合同引用格式无效。"))
	issues.append_array(GMCharacter3DContract.unique_strings(material_asset_ids, "character.part_material", "部件材质引用不能包含空项或重复项。"))
	return {"ok": issues.is_empty(), "issues": issues, "part_slot": part_slot, "mesh_asset_id": mesh_asset_id, "optional": optional}

func to_part_descriptor() -> Dictionary:
	return {"content_id": content_id, "part_slot": part_slot, "mesh_asset_id": mesh_asset_id, "material_asset_ids": Array(material_asset_ids), "attachment_socket_id": attachment_socket_id, "skeleton_contract_id": skeleton_contract_id, "optional": optional, "has_mesh": mesh != null}
