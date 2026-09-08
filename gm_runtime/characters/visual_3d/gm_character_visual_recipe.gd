@tool
class_name GMCharacterVisualRecipe
extends GMContent

const CONTENT_TYPE_ID := "gm.character.visual_recipe"
const RECIPE_SCHEMA := "gm.character.visual_recipe.v1"

## A recipe is content data only.  It stores stable part/profile references and
## intentionally has no Node, Node3D, RID, AnimationPlayer or PackedScene field.

@export_group("角色视觉配方")
@export var recipe_schema: String = RECIPE_SCHEMA
@export var body_profile_id: String = ""
@export var head_part_id: String = ""
@export var hair_part_id: String = ""
@export var outfit_part_id: String = ""
@export var feature_part_ids: PackedStringArray = PackedStringArray()
@export var accessory_part_ids: PackedStringArray = PackedStringArray()
@export var body_hide_region_ids: PackedStringArray = PackedStringArray()
@export var palette_profile_id: String = ""
@export var palette_overrides: Dictionary = {}
@export var material_variant_id: String = ""

@export_group("Profile 引用")
@export var posture_profile_id: String = ""
@export var skeleton_contract_id: String = ""
@export var animation_profile_id: String = ""

func part_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for value in [head_part_id, hair_part_id, outfit_part_id]:
		if not str(value).strip_edges().is_empty(): result.append(str(value))
	for value in feature_part_ids + accessory_part_ids: result.append(str(value))
	return result

func profile_references() -> Dictionary:
	return {"body_profile_id": body_profile_id, "posture_profile_id": posture_profile_id, "skeleton_contract_id": skeleton_contract_id, "animation_profile_id": animation_profile_id}

func get_declared_reference_specs() -> Array[Dictionary]:
	# Keep the authoring fields as stable business IDs while exposing them to the
	# existing reference graph.  A resource move therefore changes only the
	# target path in the graph; the Recipe identity and edge target ID remain the
	# same.
	var result: Array[Dictionary] = []
	var required := {
		"body_profile_id": [body_profile_id, "gm.character.body_profile", false],
		"posture_profile_id": [posture_profile_id, "gm.character.posture_profile", false],
		"skeleton_contract_id": [skeleton_contract_id, "gm.character.humanoid_skeleton_contract", false],
		"animation_profile_id": [animation_profile_id, "gm.character.animation_profile", false],
		"head_part_id": [head_part_id, "gm.character.head_asset", false],
		"hair_part_id": [hair_part_id, "gm.character.hair_asset", false],
		"outfit_part_id": [outfit_part_id, "gm.character.outfit_asset", false],
	}
	for field_name in required:
		var data: Array = required[field_name]
		_append_reference_spec(result, str(data[0]), str(field_name), str(data[1]), bool(data[2]))
	for part_id in feature_part_ids:
		_append_reference_spec(result, str(part_id), "feature_part_ids", "gm.character.feature_asset", true)
	for part_id in accessory_part_ids:
		_append_reference_spec(result, str(part_id), "accessory_part_ids", "gm.character.accessory_asset", true)
	return result

func validate_recipe() -> Dictionary:
	var issues: Array[Dictionary] = []
	if content_type_id.is_empty(): content_type_id = CONTENT_TYPE_ID
	if recipe_schema != RECIPE_SCHEMA: issues.append(GMCharacter3DContract.failure("character.recipe_schema_invalid", "角色视觉配方版本不受支持。", {"expected": RECIPE_SCHEMA, "actual": recipe_schema}))
	var required_references := {
		"body_profile": body_profile_id,
		"posture_profile": posture_profile_id,
		"skeleton_contract": skeleton_contract_id,
		"animation_profile": animation_profile_id,
		"head_part": head_part_id,
		"hair_part": hair_part_id,
		"outfit_part": outfit_part_id,
	}
	for field_name in required_references.keys():
		var reference_id := str(required_references[field_name])
		if not GMCharacter3DContract.validate_id(reference_id, str(field_name)).ok: issues.append(GMCharacter3DContract.failure("character.recipe_reference_missing", "角色视觉配方缺少必需引用：%s。" % str(field_name), {"field": str(field_name)}))
	issues.append_array(GMCharacter3DContract.unique_strings(feature_part_ids, "character.recipe_feature", "Feature 引用不能包含空项或重复项。"))
	issues.append_array(GMCharacter3DContract.unique_strings(accessory_part_ids, "character.recipe_accessory", "Accessory 引用不能包含空项或重复项。"))
	issues.append_array(GMCharacter3DContract.unique_strings(body_hide_region_ids, "character.recipe_body_hide", "Body Hide 区域不能包含空项或重复项。"))
	for region_id in body_hide_region_ids:
		if str(region_id) not in GMBodyProfile.BODY_REGIONS: issues.append(GMCharacter3DContract.failure("character.recipe_body_region_invalid", "Body Hide 区域不受支持。", {"region_id": str(region_id)}))
	if not palette_profile_id.strip_edges().is_empty() and not GMCharacter3DContract.validate_id(palette_profile_id, "palette_profile").ok:
		issues.append(GMCharacter3DContract.failure("character.recipe_palette_invalid", "Palette Profile 必须使用稳定 ID。"))
	if not material_variant_id.strip_edges().is_empty() and not GMCharacter3DContract.validate_id(material_variant_id, "material_variant").ok:
		issues.append(GMCharacter3DContract.failure("character.recipe_material_invalid", "材质变体必须使用稳定 ID。"))
	var all_ids := part_ids()
	var seen := {}
	for part_id in all_ids:
		if seen.has(str(part_id)): issues.append(GMCharacter3DContract.failure("character.recipe_part_duplicate", "角色视觉配方不能重复引用同一部件。", {"part_id": str(part_id)}))
		seen[str(part_id)] = true
	return {"ok": issues.is_empty(), "issues": issues, "schema": RECIPE_SCHEMA, "part_ids": Array(all_ids), "profiles": profile_references(), "contains_runtime_nodes": false, "contains_animation_copies": false}

func validate_against(index: Dictionary) -> Dictionary:
	var base := validate_recipe()
	var issues: Array[Dictionary] = base.issues.duplicate(true)
	var lookup: Dictionary = index.get("by_id", {}) if index.has("by_id") and index.get("by_id", {}) is Dictionary else index
	for reference_id in [body_profile_id, posture_profile_id, skeleton_contract_id, animation_profile_id, head_part_id, hair_part_id, outfit_part_id] + Array(feature_part_ids) + Array(accessory_part_ids):
		if not lookup.has(str(reference_id)): issues.append(GMCharacter3DContract.failure("character.recipe_reference_unresolved", "角色视觉配方引用无法在 GMContentLibrary 中解析。", {"reference_id": str(reference_id)}))
	return {"ok": issues.is_empty(), "issues": issues, "resolved_reference_count": _resolved_count(lookup), "references": _reference_rows(lookup)}

func to_recipe_record() -> Dictionary:
	return {"schema": RECIPE_SCHEMA, "content_id": content_id, "body_profile_id": body_profile_id, "head_part_id": head_part_id, "hair_part_id": hair_part_id, "outfit_part_id": outfit_part_id, "feature_part_ids": Array(feature_part_ids), "accessory_part_ids": Array(accessory_part_ids), "body_hide_region_ids": Array(body_hide_region_ids), "palette_profile_id": palette_profile_id, "palette_overrides": palette_overrides.duplicate(true), "material_variant_id": material_variant_id, "posture_profile_id": posture_profile_id, "skeleton_contract_id": skeleton_contract_id, "animation_profile_id": animation_profile_id}

func _resolved_count(lookup: Dictionary) -> int:
	var count := 0
	for value in [body_profile_id, posture_profile_id, skeleton_contract_id, animation_profile_id, head_part_id, hair_part_id, outfit_part_id] + Array(feature_part_ids) + Array(accessory_part_ids):
		if lookup.has(str(value)): count += 1
	return count

func _reference_rows(lookup: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for value in [body_profile_id, posture_profile_id, skeleton_contract_id, animation_profile_id, head_part_id, hair_part_id, outfit_part_id] + Array(feature_part_ids) + Array(accessory_part_ids):
		var id := str(value)
		rows.append({"id": id, "resolved": lookup.has(id), "content_type_id": str(lookup.get(id, {}).get("content_type_id", "")) if lookup.get(id, {}) is Dictionary else ""})
	return rows

func _append_reference_spec(target: Array[Dictionary], target_id: String, field_name: String, expected_type_id: String, optional: bool) -> void:
	if target_id.strip_edges().is_empty(): return
	target.append({"target_id": target_id, "kind": "character_visual_reference", "field": field_name, "strength": "strong", "expected_type_id": expected_type_id, "optional": optional})
