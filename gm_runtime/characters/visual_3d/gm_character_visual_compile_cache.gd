@tool
class_name GMCharacterVisualCompileCache
extends RefCounted

## Derived VisualRecipe compile cache.  The cache keeps a serializable build
## plan and source fingerprints; the VisualRecipe and GMContentLibrary remain
## authoritative.  No Node, RID, NodePath or editor object is persisted here.

const CACHE_SCHEMA := "gm.character.visual_compile_cache.v1"

var entries: Dictionary = {}
var hit_count: int = 0
var miss_count: int = 0

func get_or_compile(recipe: GMCharacterVisualRecipe, resolver: GMCharacterVisual3DResolver) -> Dictionary:
	if recipe == null or resolver == null:
		return _failure("character.cache_input_missing", "Visual Cache 缺少 VisualRecipe 或解析器。")
	var check := resolver.validate(recipe)
	if not check.ok: return _failure("character.cache_recipe_invalid", "VisualRecipe 未通过校验，缓存不会发布候选产物。", {"validation": check})
	var plan := _build_plan(recipe, resolver)
	if not plan.ok: return plan
	var source := _source_snapshot(recipe, resolver)
	var source_fingerprint := _source_fingerprint(recipe, source)
	var recipe_id := recipe.content_id
	var existing: Dictionary = entries.get(recipe_id, {})
	if not existing.is_empty() and _entry_matches(existing, recipe, source, source_fingerprint, plan):
		hit_count += 1
		return {"ok": true, "cache_status": "hit", "cache_id": _cache_id(recipe_id), "entry": _public_entry(existing), "authority": "VisualRecipe", "cache_authority": false}
	var compiled := {
		"schema": CACHE_SCHEMA,
		"cache_id": _cache_id(recipe_id),
		"recipe_id": recipe_id,
		"recipe_record": recipe.to_recipe_record(),
		"source_snapshot": source,
		"source_fingerprint": source_fingerprint,
		"node_plan": plan.node_plan,
		"product_fingerprint": _product_fingerprint(recipe, plan.node_plan),
		"compiled_from": "VisualRecipe",
		"cache_authority": false,
	}
	entries[recipe_id] = compiled
	miss_count += 1
	return {"ok": true, "cache_status": "miss", "cache_id": compiled.cache_id, "entry": _public_entry(compiled), "authority": "VisualRecipe", "cache_authority": false}

func rebuild(recipe: GMCharacterVisualRecipe, resolver: GMCharacterVisual3DResolver) -> Dictionary:
	if recipe != null: entries.erase(recipe.content_id)
	return get_or_compile(recipe, resolver)

func invalidate_changed(recipe: GMCharacterVisualRecipe, resolver: GMCharacterVisual3DResolver) -> Dictionary:
	if recipe == null or resolver == null: return _failure("character.cache_input_missing", "Visual Cache 缺少 VisualRecipe 或解析器。")
	var existing: Dictionary = entries.get(recipe.content_id, {})
	if existing.is_empty(): return {"ok": true, "invalidated": false, "reason": "missing"}
	var source := _source_snapshot(recipe, resolver)
	var current_fingerprint := _source_fingerprint(recipe, source)
	var invalidated := str(existing.get("source_fingerprint", "")) != current_fingerprint
	if invalidated: entries.erase(recipe.content_id)
	return {"ok": true, "invalidated": invalidated, "recipe_id": recipe.content_id, "source_fingerprint": current_fingerprint}

func delete(recipe_id: String) -> Dictionary:
	if recipe_id.strip_edges().is_empty(): return _failure("character.cache_id_missing", "Visual Cache 删除需要 Recipe 稳定 ID。")
	var existed := entries.has(recipe_id)
	entries.erase(recipe_id)
	return {"ok": true, "deleted": existed, "recipe_id": recipe_id, "cache_authority": false}

func clear() -> Dictionary:
	var count := entries.size()
	entries.clear()
	return {"ok": true, "deleted_count": count, "cache_authority": false}

func has_valid_entry(recipe: GMCharacterVisualRecipe, resolver: GMCharacterVisual3DResolver) -> bool:
	if recipe == null or resolver == null: return false
	var source := _source_snapshot(recipe, resolver)
	var plan := _build_plan(recipe, resolver)
	if not plan.ok: return false
	var existing: Dictionary = entries.get(recipe.content_id, {})
	return not existing.is_empty() and _entry_matches(existing, recipe, source, _source_fingerprint(recipe, source), plan)

func snapshot() -> Dictionary:
	var public_entries: Array = []
	for recipe_id in entries.keys(): public_entries.append(_public_entry(entries[recipe_id]))
	public_entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left.get("recipe_id", "")) < str(right.get("recipe_id", "")))
	return {"schema": CACHE_SCHEMA, "entries": public_entries, "entry_count": public_entries.size(), "hit_count": hit_count, "miss_count": miss_count, "cache_authority": false}

func _build_plan(recipe: GMCharacterVisualRecipe, resolver: GMCharacterVisual3DResolver) -> Dictionary:
	var body := resolver.resolve(recipe.body_profile_id)
	var skeleton := resolver.resolve(recipe.skeleton_contract_id)
	var outfit := resolver.resolve(recipe.outfit_part_id)
	if not body is GMBodyProfile or not skeleton is GMHumanoidSkeletonContract or not outfit is GMOutfitAsset:
		return _failure("character.cache_plan_reference_missing", "Visual Cache 无法从当前 Recipe 解析核心装配输入。")
	var feature_rows: Array = []
	for feature_id in recipe.feature_part_ids:
		var feature := resolver.resolve(str(feature_id))
		if not feature is GMFeatureAsset: return _failure("character.cache_plan_feature_missing", "Visual Cache 无法解析 Feature 模块。", {"feature_id": str(feature_id)})
		feature_rows.append((feature as GMFeatureAsset).to_feature_descriptor())
	var accessory_rows: Array = []
	for accessory_id in recipe.accessory_part_ids:
		var accessory := resolver.resolve(str(accessory_id))
		if not accessory is GMAccessoryAsset: return _failure("character.cache_plan_accessory_missing", "Visual Cache 无法解析 Accessory 槽位。", {"accessory_id": str(accessory_id)})
		accessory_rows.append((accessory as GMAccessoryAsset).to_accessory_descriptor())
	var part_count := 4 + feature_rows.size() + accessory_rows.size()
	var local_skeleton_count := 0
	for row in feature_rows:
		if not Array(row.get("local_skeleton_bones", [])).is_empty(): local_skeleton_count += 1
	var skinned_mesh_count := 0
	for part_id in recipe.part_ids():
		var part := resolver.resolve(str(part_id))
		if part is GMCharacterPart and (part as GMCharacterPart).mesh != null and (part as GMCharacterPart).mesh.has_meta("skinned") and bool((part as GMCharacterPart).mesh.get_meta("skinned")): skinned_mesh_count += 1
	if body is GMBodyProfile and (body as GMBodyProfile).mesh != null and (body as GMBodyProfile).mesh.has_meta("skinned") and bool((body as GMBodyProfile).mesh.get_meta("skinned")): skinned_mesh_count += 1
	var node_count := 1 + 6 + 1 + part_count + local_skeleton_count + feature_rows.size() + accessory_rows.size()
	var node_plan := {
		"root_slots": ["Body", "Head", "Hair", "Outfit", "Feature", "Accessory"],
		"part_count": part_count,
		"feature_module_count": feature_rows.size(),
		"accessory_slot_count": accessory_rows.size(),
		"local_skeleton_count": local_skeleton_count,
		"skinned_mesh_count": skinned_mesh_count,
		"node_count": node_count,
		"skeleton_core_bone_count": (skeleton as GMHumanoidSkeletonContract).core_bones.size(),
		"body_hide_region_ids": Array(recipe.body_hide_region_ids),
		"outfit_family_id": (outfit as GMOutfitAsset).outfit_family_id,
		"outfit_variant_id": (outfit as GMOutfitAsset).outfit_variant_id,
		"material_variant_id": recipe.material_variant_id,
		"feature_modules": feature_rows,
		"accessories": accessory_rows,
	}
	if node_count > GMCharacter3DContract.MAX_CHARACTER_NODES: return _failure("character.cache_node_budget", "Visual Cache 产物超过角色节点预算。", {"node_count": node_count, "max": GMCharacter3DContract.MAX_CHARACTER_NODES})
	if skinned_mesh_count > GMCharacter3DContract.MAX_SKINNED_MESHES: return _failure("character.cache_skinned_mesh_budget", "Visual Cache 产物超过 SkinnedMesh 预算。", {"skinned_mesh_count": skinned_mesh_count, "max": GMCharacter3DContract.MAX_SKINNED_MESHES})
	if local_skeleton_count > GMCharacter3DContract.MAX_LOCAL_SKELETONS: return _failure("character.cache_local_skeleton_budget", "Visual Cache 产物超过 Local Skeleton 预算。", {"local_skeleton_count": local_skeleton_count, "max": GMCharacter3DContract.MAX_LOCAL_SKELETONS})
	return {"ok": true, "node_plan": node_plan}

func _source_snapshot(recipe: GMCharacterVisualRecipe, resolver: GMCharacterVisual3DResolver) -> Dictionary:
	var ids: Array[String] = []
	for value in [recipe.body_profile_id, recipe.posture_profile_id, recipe.skeleton_contract_id, recipe.animation_profile_id, recipe.head_part_id, recipe.hair_part_id, recipe.outfit_part_id, recipe.palette_profile_id]:
		var id := str(value)
		if not id.is_empty() and not ids.has(id): ids.append(id)
	for value in recipe.feature_part_ids + recipe.accessory_part_ids:
		var id := str(value)
		if not id.is_empty() and not ids.has(id): ids.append(id)
	ids.sort()
	var rows := {}
	for id in ids: rows[id] = _resource_fingerprint(resolver.resolve(id))
	return {"recipe_record": recipe.to_recipe_record(), "dependencies": rows}

func _entry_matches(entry: Dictionary, recipe: GMCharacterVisualRecipe, source: Dictionary, source_fingerprint: String, plan: Dictionary) -> bool:
	if str(entry.get("schema", "")) != CACHE_SCHEMA: return false
	if str(entry.get("recipe_id", "")) != recipe.content_id: return false
	if str(entry.get("source_fingerprint", "")) != source_fingerprint: return false
	if GMCharacter3DContract.digest(entry.get("source_snapshot", {})) != GMCharacter3DContract.digest(source): return false
	var node_plan: Dictionary = entry.get("node_plan", {})
	if GMCharacter3DContract.digest(node_plan) != GMCharacter3DContract.digest(plan.node_plan): return false
	return str(entry.get("product_fingerprint", "")) == _product_fingerprint(recipe, node_plan)

func _source_fingerprint(recipe: GMCharacterVisualRecipe, source: Dictionary) -> String:
	return GMCharacter3DContract.digest({"recipe_id": recipe.content_id, "recipe_record": recipe.to_recipe_record(), "source": source})

func _product_fingerprint(recipe: GMCharacterVisualRecipe, node_plan: Dictionary) -> String:
	return GMCharacter3DContract.digest({"recipe_id": recipe.content_id, "recipe_record": recipe.to_recipe_record(), "node_plan": node_plan})

func _resource_fingerprint(resource: Resource) -> String:
	if resource == null: return "missing"
	var path := resource.resource_path
	var file_hash := ""
	if not path.is_empty() and FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
		if file != null:
			var context := HashingContext.new()
			context.start(HashingContext.HASH_SHA256)
			while file.get_position() < file.get_length():
				var remaining := file.get_length() - file.get_position()
				context.update(file.get_buffer(mini(remaining, 1048576)))
			file_hash = context.finish().hex_encode()
	var revision := str(resource.get_meta("gm_cache_revision")) if resource.has_meta("gm_cache_revision") else ""
	var values := {"class": resource.get_class(), "path": path, "file_hash": file_hash, "revision": revision}
	for property in resource.get_property_list():
		var usage := int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_STORAGE) == 0: continue
		var name := str(property.get("name", ""))
		if name in ["resource_path", "resource_name", "script", "resource_local_to_scene"]: continue
		values[name] = _portable(resource.get(name))
	return GMCharacter3DContract.digest(values)

func _portable(value: Variant) -> Variant:
	if value == null or value is String or value is StringName or value is bool or value is int or value is float: return value
	if value is Resource:
		var revision := str(value.get_meta("gm_cache_revision")) if value.has_meta("gm_cache_revision") else ""
		return {"class": value.get_class(), "path": value.resource_path, "revision": revision}
	if value is Array or value is PackedStringArray:
		var result: Array = []
		for item in value: result.append(_portable(item))
		return result
	if value is Dictionary:
		var result := {}
		for key in value.keys(): result[str(key)] = _portable(value[key])
		return result
	return str(value)

func _public_entry(entry: Dictionary) -> Dictionary:
	var result := entry.duplicate(true)
	result.erase("packed_scene")
	result["cache_authority"] = false
	return result

func _cache_id(recipe_id: String) -> String:
	return "gm.character.visual_cache.%s" % recipe_id

func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "details": details, "failure_closed": true}
