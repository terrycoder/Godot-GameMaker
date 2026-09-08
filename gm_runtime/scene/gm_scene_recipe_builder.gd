class_name GMSceneRecipeBuilder
extends RefCounted

## 维度无关装配器。
##
## 后端只通过 capabilities()/resolve_target() 注入；装配输出是纯字典。这里
## 不创建 Node2D/Node3D，不持有 SceneTree，也不定义第二套空间或地图权威。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const CONTEXT := preload("res://gm_runtime/scene/gm_task_execution_context.gd")
const SKELETON := preload("res://gm_runtime/scene/gm_scene_skeleton_definition.gd")
const RECIPE := preload("res://gm_runtime/scene/gm_scene_recipe.gd")
const SPATIAL_TARGET := preload("res://gm_runtime/spatial_core/gm_spatial_target_ref.gd")
const SPATIAL_DOMAIN := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")
const CAPABILITIES := preload("res://gm_runtime/spatial_core/gm_spatial_backend_capabilities.gd")

const BUILD_SCHEMA := "gm.scene.recipe_build.v1"
const BUILD_FIELDS: Array[String] = [
        "schema_version", "recipe_id", "skeleton_id", "task_id", "assignment_id", "backend_domain", "backend_id",
        "seed", "variation", "requirements", "resolved_slots", "build_fingerprint"
]
const VARIATION_FIELDS: Array[String] = ["index", "token"]
const RESOLVED_SLOT_FIELDS: Array[String] = ["slot_id", "slot_kind", "target_ref", "resolution"]

func build(recipe_value: Variant, skeleton_value: Variant, context_value: Variant, backend: Object) -> Dictionary:
	var recipe_check := _as_recipe(recipe_value)
	if not recipe_check.ok:
		return recipe_check
	var skeleton_check := _as_skeleton(skeleton_value)
	if not skeleton_check.ok:
		return skeleton_check
	var context_check := _as_context(context_value)
	if not context_check.ok:
		return context_check
	if backend == null or not is_instance_valid(backend):
		return _blocked("scene.builder.backend_missing", "语义场景装配缺少后端对象。")
	var recipe: GMSceneRecipe = recipe_check.value
	var skeleton: GMSceneSkeletonDefinition = skeleton_check.value
	var context: GMTaskExecutionContext = context_check.value
	if recipe.skeleton_id != skeleton.skeleton_id:
		return _blocked("scene.builder.skeleton_mismatch", "配方与人工骨架标识不一致。")
	var backend_identity := _backend_identity(backend)
	if not backend_identity.ok:
		return backend_identity
	var domain_id := str(backend_identity.domain_id)
	if not skeleton.backend_domains.has(domain_id):
		return _blocked("scene.builder.domain_unsupported", "人工骨架未声明当前执行空间域。", {"domain_id": domain_id})
	var skeleton_slot_map := {}
	for raw_slot in skeleton.slots:
		var slot_check := _slot_dict(raw_slot)
		if not slot_check.ok: return slot_check
		var slot_value: Dictionary = slot_check.value
		skeleton_slot_map[str(slot_value.slot_id)] = slot_value
	var recipe_slot_map := {}
	for raw_slot in recipe.slots:
		var slot_check := _slot_dict(raw_slot)
		if not slot_check.ok: return slot_check
		var slot_value: Dictionary = slot_check.value
		var slot_id := str(slot_value.slot_id)
		if not skeleton_slot_map.has(slot_id):
			return _blocked("scene.builder.slot_not_in_skeleton", "配方插槽未在人工骨架中声明。", {"slot_id": slot_id})
		var skeleton_slot: Dictionary = skeleton_slot_map[slot_id]
		if str(skeleton_slot.slot_kind) != str(slot_value.slot_kind):
			return _blocked("scene.builder.slot_kind_mismatch", "配方插槽类型与人工骨架不一致。", {"slot_id": slot_id})
		if bool(skeleton_slot.required) and slot_value.target_ref.is_empty():
			return _blocked("scene.builder.slot_unbound", "人工骨架required插槽没有配方绑定。", {"slot_id": slot_id})
		recipe_slot_map[slot_id] = slot_value
	for skeleton_slot_id in skeleton_slot_map.keys():
		var skeleton_slot: Dictionary = skeleton_slot_map[skeleton_slot_id]
		if bool(skeleton_slot.required) and not recipe_slot_map.has(str(skeleton_slot_id)):
			return _blocked("scene.builder.required_slot_missing", "配方缺少人工骨架required插槽。", {"slot_id": str(skeleton_slot_id)})
	if not recipe_slot_map.has("entry") and not _has_kind(recipe.slots, "entry"):
		return _blocked("scene.builder.entry_missing", "配方入口插槽缺失。")
	var entry_slot := _find_kind(recipe.slots, "entry")
	var exit_slot := _find_kind(recipe.slots, "exit")
	if entry_slot.is_empty() or exit_slot.is_empty():
		return _blocked("scene.builder.entry_exit_missing", "配方入口或出口插槽缺失。")
	if VALUE.digest(entry_slot.target_ref) != VALUE.digest(recipe.entry) or VALUE.digest(exit_slot.target_ref) != VALUE.digest(recipe.exit):
		return _blocked("scene.builder.entry_exit_mismatch", "配方入口/出口字段与插槽绑定不一致。")
	var context_resolution := _resolve_if_spatial(context.target, backend, domain_id, "context.target")
	if not context_resolution.ok:
		return context_resolution
	var resolved_slots: Array = []
	for raw_slot in recipe.slots:
		var slot: Dictionary = raw_slot
		var resolution := _resolve_if_spatial(slot.target_ref, backend, domain_id, "slot.%s" % str(slot.slot_id))
		if not resolution.ok:
			return resolution
		resolved_slots.append({
			"slot_id": str(slot.slot_id),
			"slot_kind": str(slot.slot_kind),
			"target_ref": VALUE.duplicate_value(slot.target_ref),
			"resolution": VALUE.duplicate_value(resolution.value)
		})
	resolved_slots.sort_custom(func(left, right): return str(left.slot_id) < str(right.slot_id))
	var variations: Array = recipe.variation_tokens if not recipe.variation_tokens.is_empty() else skeleton.variation_tokens
	var variation_index := 0
	if not variations.is_empty():
		variation_index = posmod(context.seed, variations.size())
	var variation_token := ""
	if not variations.is_empty(): variation_token = str(variations[variation_index])
	var requirements := {}
	for kind in RECIPE.REQUIRED_SLOT_KINDS:
		requirements[kind] = _has_kind(recipe.slots, kind)
	var build: Dictionary = VALUE.persistence_canonical({
		"schema_version": BUILD_SCHEMA,
		"recipe_id": recipe.recipe_id,
		"skeleton_id": skeleton.skeleton_id,
		"task_id": context.task_id,
		"assignment_id": context.assignment_id,
		"backend_domain": domain_id,
		"backend_id": str(backend_identity.backend_id),
		"seed": context.seed,
		"variation": {"index": variation_index, "token": variation_token},
		"requirements": requirements,
		"resolved_slots": resolved_slots
	})
	var persistence := VALUE.persistence(build)
	if not persistence.ok:
		return _blocked("scene.builder.output_invalid", "语义装配输出不是可保存纯值。", {"detail": persistence})
	build["build_fingerprint"] = VALUE.digest(build)
	var parsed_build := parse_build(build, recipe, skeleton, context)
	if not parsed_build.ok:
		return parsed_build
	return {"ok": true, "value": parsed_build.value}

static func parse_build(value: Variant, recipe_value: Variant = null, skeleton_value: Variant = null, context_value: Variant = null) -> Dictionary:
	var fields := VALUE.exact_fields(value, BUILD_FIELDS)
	if not fields.ok:
		return _blocked("scene.builder.build_shape_invalid", "SceneRecipeBuild字段集合必须精确匹配。", fields)
	var persistence := VALUE.persistence(value)
	if not persistence.ok:
		return _blocked("scene.builder.build_persistence_invalid", "SceneRecipeBuild必须是可持久化纯值。", persistence)
	if value.schema_version != BUILD_SCHEMA:
		return _blocked("scene.builder.build_schema_invalid", "SceneRecipeBuild Schema版本不匹配。")
	for identity in ["recipe_id", "skeleton_id", "task_id", "assignment_id", "backend_domain", "backend_id"]:
		if not VALUE.stable_id(value.get(identity), false):
			return _blocked("scene.builder.build_identity_invalid", "SceneRecipeBuild包含非法稳定标识。", {"field": identity})
	var seed_check := VALUE.safe_int(value.seed, true)
	if not seed_check.ok:
		return _blocked("scene.builder.build_seed_invalid", "SceneRecipeBuild seed必须是JSON安全整数。", seed_check)
	if typeof(value.variation) != TYPE_DICTIONARY:
		return _blocked("scene.builder.build_variation_invalid", "SceneRecipeBuild variation必须是字典。")
	var variation_fields := VALUE.exact_fields(value.variation, VARIATION_FIELDS)
	if not variation_fields.ok or not VALUE.persistence(value.variation).ok:
		return _blocked("scene.builder.build_variation_invalid", "SceneRecipeBuild variation字段集合无效。", variation_fields)
	var variation_index := VALUE.integer_field(value.variation.index, false)
	if not variation_index.ok or typeof(value.variation.token) != TYPE_STRING:
		return _blocked("scene.builder.build_variation_invalid", "SceneRecipeBuild variation索引或token类型无效。")
	if typeof(value.requirements) != TYPE_DICTIONARY:
		return _blocked("scene.builder.build_requirements_invalid", "SceneRecipeBuild requirements必须是字典。")
	for kind in RECIPE.REQUIRED_SLOT_KINDS:
		if not value.requirements.has(kind) or typeof(value.requirements.get(kind)) != TYPE_BOOL:
			return _blocked("scene.builder.build_requirements_invalid", "SceneRecipeBuild requirements必须完整且只包含布尔插槽要求。", {"field": kind})
	if value.requirements.size() != RECIPE.REQUIRED_SLOT_KINDS.size():
		return _blocked("scene.builder.build_requirements_invalid", "SceneRecipeBuild requirements包含未知字段。")
	if typeof(value.resolved_slots) != TYPE_ARRAY:
		return _blocked("scene.builder.build_slots_invalid", "SceneRecipeBuild resolved_slots必须是数组。")
	var slot_ids := {}
	var normalized_slots: Array = []
	for raw_slot in value.resolved_slots:
		var slot_fields := VALUE.exact_fields(raw_slot, RESOLVED_SLOT_FIELDS)
		if not slot_fields.ok:
			return _blocked("scene.builder.build_slot_shape_invalid", "SceneRecipeBuild resolved slot字段集合无效。", slot_fields)
		if not VALUE.stable_id(raw_slot.slot_id, false) or not VALUE.stable_id(raw_slot.slot_kind, false):
			return _blocked("scene.builder.build_slot_identity_invalid", "SceneRecipeBuild resolved slot标识无效。")
		if slot_ids.has(str(raw_slot.slot_id)):
			return _blocked("scene.builder.build_slot_duplicate", "SceneRecipeBuild resolved slot ID不得重复。")
		slot_ids[str(raw_slot.slot_id)] = true
		var target_check := VALUE.semantic_ref(raw_slot.target_ref, false)
		if not target_check.ok or typeof(raw_slot.resolution) != TYPE_DICTIONARY or not VALUE.persistence(raw_slot.resolution).ok:
			return _blocked("scene.builder.build_slot_invalid", "SceneRecipeBuild resolved slot目标或解析结果无效。")
		normalized_slots.append({
			"slot_id": str(raw_slot.slot_id), "slot_kind": str(raw_slot.slot_kind),
			"target_ref": VALUE.duplicate_value(target_check.get("value", raw_slot.target_ref)),
			"resolution": VALUE.duplicate_value(raw_slot.resolution)
		})
		normalized_slots.sort_custom(func(left, right): return str(left.slot_id) < str(right.slot_id))
	var fingerprint := str(value.build_fingerprint)
	if not VALUE.stable_id(fingerprint, false):
		return _blocked("scene.builder.build_fingerprint_invalid", "SceneRecipeBuild fingerprint无效。")
	var body: Dictionary = VALUE.persistence_canonical({
		"schema_version": BUILD_SCHEMA,
		"recipe_id": str(value.recipe_id), "skeleton_id": str(value.skeleton_id),
		"task_id": str(value.task_id), "assignment_id": str(value.assignment_id),
		"backend_domain": str(value.backend_domain), "backend_id": str(value.backend_id),
		"seed": int(seed_check.value),
		"variation": {"index": int(variation_index.value), "token": str(value.variation.token)},
		"requirements": value.requirements.duplicate(true),
		"resolved_slots": normalized_slots
	})
	if VALUE.digest(body) != fingerprint:
		return _blocked("scene.builder.build_fingerprint_mismatch", "SceneRecipeBuild内容与fingerprint不一致。")
	if recipe_value != null or skeleton_value != null or context_value != null:
		var recipe_check := _as_recipe(recipe_value)
		var skeleton_check := _as_skeleton(skeleton_value)
		var context_check := _as_context(context_value)
		if not recipe_check.ok or not skeleton_check.ok or not context_check.ok:
			return _blocked("scene.builder.build_reference_invalid", "SceneRecipeBuild关联的配方、骨架或上下文无效。")
		var recipe: GMSceneRecipe = recipe_check.value
		var skeleton: GMSceneSkeletonDefinition = skeleton_check.value
		var context: GMTaskExecutionContext = context_check.value
		if str(value.recipe_id) != recipe.recipe_id or str(value.skeleton_id) != skeleton.skeleton_id or str(value.task_id) != context.task_id or str(value.assignment_id) != context.assignment_id:
			return _blocked("scene.builder.build_reference_mismatch", "SceneRecipeBuild身份与配方/骨架/上下文不一致。")
		if str(value.backend_domain) not in skeleton.backend_domains:
			return _blocked("scene.builder.build_domain_invalid", "SceneRecipeBuild后端空间域不在骨架声明中。")
		if int(seed_check.value) != context.seed:
			return _blocked("scene.builder.build_seed_mismatch", "SceneRecipeBuild seed与上下文不一致。")
		for kind in RECIPE.REQUIRED_SLOT_KINDS:
			if not bool(value.requirements.get(kind, false)):
				return _blocked("scene.builder.build_requirements_incomplete", "SceneRecipeBuild未记录完整的必需语义插槽。", {"slot_kind": kind})
	body["build_fingerprint"] = fingerprint
	return {"ok": true, "value": body}

static func _as_recipe(value: Variant) -> Dictionary:
	if value is GMSceneRecipe:
		return {"ok": true, "value": value}
	return RECIPE.from_dict(value)

static func _as_skeleton(value: Variant) -> Dictionary:
	if value is GMSceneSkeletonDefinition:
		return {"ok": true, "value": value}
	return SKELETON.from_dict(value)

static func _as_context(value: Variant) -> Dictionary:
	if value is GMTaskExecutionContext:
		return {"ok": true, "value": value}
	return CONTEXT.from_dict(value)

static func _slot_dict(value: Variant) -> Dictionary:
	var parsed := VALUE.exact_fields(value, ["schema_version", "slot_id", "slot_kind", "target_ref", "required", "capacity", "tags"])
	if not parsed.ok: return parsed
	var validated := preload("res://gm_runtime/scene/gm_semantic_slot_2d.gd").from_dict(value)
	if not validated.ok: return validated
	return {"ok": true, "value": validated.value.to_dict()}

static func _backend_identity(backend: Object) -> Dictionary:
	if not backend.has_method("capabilities"):
		return _blocked("scene.builder.backend_capabilities_missing", "场景后端必须提供既有空间能力声明。")
	var capabilities = backend.capabilities()
	if capabilities == null or not capabilities.has_method("domain_id"):
		return _blocked("scene.builder.backend_capabilities_invalid", "场景后端空间能力声明无效。")
	var domain_id := str(capabilities.domain_id())
	var domain_check := SPATIAL_DOMAIN.validate_id(domain_id)
	if not domain_check.ok or not SPATIAL_DOMAIN.is_execution_available(domain_id):
		return _blocked("scene.builder.backend_domain_invalid", "场景后端空间域不可执行。", {"domain_id": domain_id})
	if not capabilities.has_method("supports") or not capabilities.supports(CAPABILITIES.RESOLVE_TARGET):
		return _blocked("scene.builder.resolve_capability_missing", "场景后端没有既有resolve_target能力。", {"domain_id": domain_id})
	return {"ok": true, "domain_id": domain_id, "backend_id": domain_id}

static func _resolve_if_spatial(value: Dictionary, backend: Object, domain_id: String, label: String) -> Dictionary:
	if value.is_empty():
		return {"ok": false, "code": "scene.builder.unbound", "error_zh": "%s没有绑定语义目标。" % label}
	if value.has("schema_version") and value.has("domain_id") and value.has("kind"):
		var target_check := SPATIAL_TARGET.from_native(value)
		if not target_check.ok:
			return _blocked("scene.builder.spatial_target_invalid", "%s空间目标无效。" % label, {"detail": target_check})
		if target_check.target.domain_id() != domain_id:
			return _blocked("scene.builder.spatial_domain_mismatch", "%s空间域与执行后端不一致。" % label)
		var resolved = backend.resolve_target(target_check.target) if backend.has_method("resolve_target") else null
		if not resolved is Dictionary or not bool(resolved.get("ok", false)):
			return _blocked("scene.builder.target_unresolvable", "%s无法由当前空间后端解析。" % label, {"detail": resolved if resolved is Dictionary else {}})
		var stable := VALUE.persistence(resolved)
		if not stable.ok:
			return _blocked("scene.builder.target_runtime_value", "%s解析结果包含运行时对象。" % label)
		return {"ok": true, "value": resolved}
	var semantic := VALUE.typed_ref(value, false)
	if not semantic.ok:
		return _blocked("scene.builder.semantic_target_invalid", "%s语义目标无效。" % label)
	return {"ok": true, "value": {"kind": "semantic", "ref": VALUE.duplicate_value(value)}}

static func _has_kind(values: Array, kind: String) -> bool:
	return not _find_kind(values, kind).is_empty()

static func _find_kind(values: Array, kind: String) -> Dictionary:
	for value in values:
		if typeof(value) == TYPE_DICTIONARY and str(value.get("slot_kind", "")) == kind:
			return value
	return {}

static func _blocked(code: String, error_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error_zh": error_zh}
	if not details.is_empty(): result["details"] = VALUE.duplicate_value(details)
	return result
