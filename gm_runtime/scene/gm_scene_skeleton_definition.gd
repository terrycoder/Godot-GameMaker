class_name GMSceneSkeletonDefinition
extends RefCounted

## 人工维护的语义骨架。它只列出区域与插槽约束，不知道 TileMap、节点层级
## 或 2D/3D 的世界坐标；具体后端由 GMSceneRecipeBuilder 注入。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const SLOT := preload("res://gm_runtime/scene/gm_semantic_slot_2d.gd")
const SPATIAL_DOMAIN := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")

const SCHEMA_VERSION := "gm.scene.skeleton.v1"
const FIELDS: Array[String] = ["schema_version", "skeleton_id", "display_name_zh", "backend_domains", "regions", "slots", "variation_tokens"]

var skeleton_id: String
var display_name_zh: String
var backend_domains: Array
var regions: Array
var slots: Array
var variation_tokens: Array

func _init(
	p_skeleton_id: String = "",
	p_display_name_zh: String = "",
	p_backend_domains: Array = [],
	p_regions: Array = [],
	p_slots: Array = [],
	p_variation_tokens: Array = []
) -> void:
	skeleton_id = p_skeleton_id
	display_name_zh = p_display_name_zh
	backend_domains = VALUE.duplicate_value(p_backend_domains)
	regions = VALUE.duplicate_value(p_regions)
	slots = VALUE.duplicate_value(p_slots)
	variation_tokens = VALUE.duplicate_value(p_variation_tokens)

static func from_dict(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var stable := VALUE.persistence(value)
	if not stable.ok:
		return stable
	if value.schema_version != SCHEMA_VERSION:
		return {"ok": false, "code": "scene.skeleton.schema", "error_zh": "SceneSkeletonDefinition Schema版本不匹配。"}
	if not VALUE.stable_id(value.skeleton_id) or typeof(value.display_name_zh) != TYPE_STRING:
		return {"ok": false, "code": "scene.skeleton.identity", "error_zh": "骨架标识或名称无效。"}
	var domain_check := VALUE.string_array(value.backend_domains, false)
	if not domain_check.ok or domain_check.value.is_empty():
		return {"ok": false, "code": "scene.skeleton.backend_domains", "error_zh": "骨架必须声明至少一个空间后端域。"}
	for domain_id in domain_check.value:
		var parsed_domain := SPATIAL_DOMAIN.validate_id(domain_id)
		if not parsed_domain.ok or str(domain_id) == SPATIAL_DOMAIN.FULL_3D_RESERVED:
			return {"ok": false, "code": "scene.skeleton.backend_domain_invalid", "error_zh": "骨架声明了不可执行或保留空间域。"}
	if typeof(value.regions) != TYPE_ARRAY or value.regions.is_empty():
		return {"ok": false, "code": "scene.skeleton.regions", "error_zh": "骨架至少需要一个语义区域。"}
	var normalized_regions: Array = []
	var region_ids := {}
	for region in value.regions:
		var region_check := _validate_region(region)
		if not region_check.ok:
			return region_check
		var region_value: Dictionary = region_check.value
		if region_ids.has(region_value.region_id):
			return {"ok": false, "code": "scene.skeleton.region_duplicate", "error_zh": "骨架区域ID重复。"}
		region_ids[region_value.region_id] = true
		normalized_regions.append(region_value)
	if typeof(value.slots) != TYPE_ARRAY or value.slots.is_empty():
		return {"ok": false, "code": "scene.skeleton.slots", "error_zh": "骨架至少需要一个语义插槽。"}
	var normalized_slots: Array = []
	var slot_ids := {}
	var has_entry := false
	var has_exit := false
	for raw_slot in value.slots:
		var slot_check := SLOT.from_dict(raw_slot)
		if not slot_check.ok:
			return {"ok": false, "code": "scene.skeleton.slot_invalid", "error_zh": "骨架包含非法语义插槽。", "detail": slot_check}
		var slot_value: GMSemanticSlot2D = slot_check.value
		if slot_ids.has(slot_value.slot_id):
			return {"ok": false, "code": "scene.skeleton.slot_duplicate", "error_zh": "骨架插槽ID重复。"}
		slot_ids[slot_value.slot_id] = true
		has_entry = has_entry or slot_value.slot_kind == "entry"
		has_exit = has_exit or slot_value.slot_kind == "exit"
		normalized_slots.append(slot_value.to_dict())
	if not has_entry or not has_exit:
		return {"ok": false, "code": "scene.skeleton.entry_exit_missing", "error_zh": "人工骨架必须声明入口与出口插槽。"}
	var variation_check := VALUE.string_array(value.variation_tokens, false)
	if not variation_check.ok:
		return {"ok": false, "code": "scene.skeleton.variation", "error_zh": "骨架变化选项必须是稳定字符串数组。", "detail": variation_check}
	var skeleton := GMSceneSkeletonDefinition.new(
		str(value.skeleton_id), str(value.display_name_zh), domain_check.value,
		normalized_regions, normalized_slots, variation_check.value
	)
	return {"ok": true, "value": skeleton}

static func from_json(text: String) -> Dictionary:
	var parsed := VALUE.parse_json(text)
	if not parsed.ok:
		return parsed
	return from_dict(parsed.value)

static func _validate_region(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, ["region_id", "region_kind", "required", "tags"])
	if not fields.ok:
		return fields
	if not VALUE.persistence(value).ok:
		return {"ok": false, "code": "scene.region.persistence", "error_zh": "语义区域必须是可持久化纯值。"}
	if not VALUE.stable_id(value.region_id) or not VALUE.stable_id(value.region_kind):
		return {"ok": false, "code": "scene.region.identity", "error_zh": "语义区域标识无效。"}
	if typeof(value.required) != TYPE_BOOL:
		return {"ok": false, "code": "scene.region.required", "error_zh": "语义区域required必须是布尔值。"}
	var tags := VALUE.string_array(value.tags, true)
	if not tags.ok:
		return {"ok": false, "code": "scene.region.tags", "error_zh": "语义区域tags无效。"}
	return {"ok": true, "value": {
		"region_id": str(value.region_id),
		"region_kind": str(value.region_kind),
		"required": bool(value.required),
		"tags": tags.value
	}}

func validate() -> Dictionary:
	return GMSceneSkeletonDefinition.from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"skeleton_id": skeleton_id,
		"display_name_zh": display_name_zh,
		"backend_domains": VALUE.duplicate_value(backend_domains),
		"regions": VALUE.duplicate_value(regions),
		"slots": VALUE.duplicate_value(slots),
		"variation_tokens": VALUE.duplicate_value(variation_tokens)
	}

func to_json() -> String:
	return VALUE.json_string(to_dict())

func fingerprint() -> String:
	return VALUE.digest(to_dict())
