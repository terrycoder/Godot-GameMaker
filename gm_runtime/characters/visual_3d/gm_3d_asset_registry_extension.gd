@tool
class_name GM3DAssetRegistryExtension
extends RefCounted

## Adapter over the existing GMContentLibrary.  It has no disk index, no
## duplicate authority and no independent registration root.

const EXTENSION_ID := "gm.character.asset_registry_extension.v1"
const ASSET_TYPE_IDS := {
	"Mesh": "gm.asset.mesh",
	"SkinnedMesh": "gm.asset.skinned_mesh",
	"Skeleton": "gm.asset.skeleton",
	"Animation": "gm.asset.animation",
	"Material": "gm.asset.material",
	"PackedScene3D": "gm.asset.packed_scene_3d",
	"CharacterPart": "gm.character.part",
}

static func supported_types() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for kind in ASSET_TYPE_IDS.keys(): result.append({"kind": str(kind), "content_type_id": str(ASSET_TYPE_IDS[kind]), "registry": "GMContentLibrary", "extension": EXTENSION_ID})
	result.sort_custom(func(left: Dictionary, right: Dictionary): return str(left.kind) < str(right.kind))
	return result

static func query(library: GMContentLibrary, type_id: String = "") -> Dictionary:
	if library == null: return GMCharacter3DContract.failure("character.asset_registry_library_missing", "资产注册扩展缺少既有 GMContentLibrary。")
	var rows := library.query("", type_id)
	return {"ok": true, "extension": EXTENSION_ID, "registry": "GMContentLibrary", "entries": rows, "type_count": supported_types().size(), "second_registry": false}

static func classify_resource(resource: Resource) -> String:
	if resource == null: return ""
	if resource is GMCharacterPart: return "CharacterPart"
	if resource is Mesh: return "SkinnedMesh" if resource is ArrayMesh and resource.get_meta("skinned", false) else "Mesh"
	if resource is Animation: return "Animation"
	if resource is Material: return "Material"
	if resource is PackedScene: return "PackedScene3D"
	return ""

static func asset_type_id(kind: String) -> String:
	return str(ASSET_TYPE_IDS.get(kind, ""))
