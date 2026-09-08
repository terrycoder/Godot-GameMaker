class_name GMSceneRecipe
extends RefCounted

## 语义场景配方：描述对象、区域、入口/出口、插槽、参与者、目标与结果规则。
## 它从不保存场景节点、TileMap、NodePath 或后端运行时句柄。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const SLOT := preload("res://gm_runtime/scene/gm_semantic_slot_2d.gd")

const SCHEMA_VERSION := "gm.scene.recipe.v1"
const FIELDS: Array[String] = [
	"schema_version", "recipe_id", "display_name_zh", "skeleton_id", "entry", "exit",
	"required_slot_kinds", "semantic_objects", "regions", "slots", "participants",
	"objectives", "results", "variation_tokens"
]
const REQUIRED_SLOT_KINDS: Array[String] = ["entry", "objective", "resource", "hostile", "facility", "extraction"]
const OBJECTIVE_KINDS: Array[String] = ["eliminate", "reach", "collect", "protect", "interact", "escort", "survive", "custom"]
const RESULT_STATUSES: Array[String] = ["success", "partial_success", "failed", "extracted"]

var recipe_id: String
var display_name_zh: String
var skeleton_id: String
var entry: Dictionary
var exit: Dictionary
var required_slot_kinds: Array
var semantic_objects: Array
var regions: Array
var slots: Array
var participants: Array
var objectives: Array
var results: Array
var variation_tokens: Array

func _init(
	p_recipe_id: String = "",
	p_display_name_zh: String = "",
	p_skeleton_id: String = "",
	p_entry: Dictionary = {},
	p_exit: Dictionary = {},
	p_required_slot_kinds: Array = REQUIRED_SLOT_KINDS,
	p_semantic_objects: Array = [],
	p_regions: Array = [],
	p_slots: Array = [],
	p_participants: Array = [],
	p_objectives: Array = [],
	p_results: Array = [],
	p_variation_tokens: Array = []
) -> void:
	recipe_id = p_recipe_id
	display_name_zh = p_display_name_zh
	skeleton_id = p_skeleton_id
	entry = VALUE.duplicate_value(p_entry)
	exit = VALUE.duplicate_value(p_exit)
	required_slot_kinds = VALUE.duplicate_value(p_required_slot_kinds)
	semantic_objects = VALUE.duplicate_value(p_semantic_objects)
	regions = VALUE.duplicate_value(p_regions)
	slots = VALUE.duplicate_value(p_slots)
	participants = VALUE.duplicate_value(p_participants)
	objectives = VALUE.duplicate_value(p_objectives)
	results = VALUE.duplicate_value(p_results)
	variation_tokens = VALUE.duplicate_value(p_variation_tokens)

static func from_dict(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var stable := VALUE.persistence(value)
	if not stable.ok:
		return stable
	if value.schema_version != SCHEMA_VERSION:
		return {"ok": false, "code": "scene.recipe.schema", "error_zh": "SceneRecipe Schema版本不匹配。"}
	if not VALUE.stable_id(value.recipe_id) or not VALUE.stable_id(value.skeleton_id) or typeof(value.display_name_zh) != TYPE_STRING:
		return {"ok": false, "code": "scene.recipe.identity", "error_zh": "配方标识、骨架标识或名称无效。"}
	var entry_check := VALUE.semantic_ref(value.entry, false)
	var exit_check := VALUE.semantic_ref(value.exit, false)
	if not entry_check.ok or not exit_check.ok:
		return {"ok": false, "code": "scene.recipe.entry_exit", "error_zh": "配方入口与出口必须是稳定语义引用。"}
	var required_check := VALUE.string_array(value.required_slot_kinds, false)
	if not required_check.ok or required_check.value.is_empty():
		return {"ok": false, "code": "scene.recipe.required_slots", "error_zh": "配方必须声明需要验证的插槽类型。"}
	for kind in required_check.value:
		if not SLOT.KINDS.has(str(kind)):
			return {"ok": false, "code": "scene.recipe.required_slot_kind", "error_zh": "配方声明了未知插槽类型。"}
	for required_kind in REQUIRED_SLOT_KINDS:
		if not required_check.value.has(required_kind):
			return {"ok": false, "code": "scene.recipe.required_slot_kind_missing", "error_zh": "配方必须声明入口、目标、资源、敌对、设施与撤离插槽。"}
	var objects_check := _validate_semantic_objects(value.semantic_objects)
	if not objects_check.ok:
		return objects_check
	var regions_check := _validate_regions(value.regions)
	if not regions_check.ok:
		return regions_check
	var slots_check := _validate_slots(value.slots, required_check.value)
	if not slots_check.ok:
		return slots_check
	var entry_slot := _slot_for_kind(slots_check.value, "entry")
	var exit_slot := _slot_for_kind(slots_check.value, "exit")
	if entry_slot.is_empty() or VALUE.digest(entry_slot.target_ref) != VALUE.digest(entry_check.get("value", value.entry)):
		return {"ok": false, "code": "scene.recipe.entry_mismatch", "error_zh": "配方entry必须与entry插槽绑定一致。"}
	if exit_slot.is_empty() or VALUE.digest(exit_slot.target_ref) != VALUE.digest(exit_check.get("value", value.exit)):
		return {"ok": false, "code": "scene.recipe.exit_mismatch", "error_zh": "配方exit必须与exit插槽绑定一致。"}
	var participants_check := _validate_refs(value.participants, "scene.recipe.participants")
	if not participants_check.ok:
		return participants_check
	var objectives_check := _validate_objectives(value.objectives)
	if not objectives_check.ok:
		return objectives_check
	var results_check := _validate_results(value.results, objectives_check.value)
	if not results_check.ok:
		return results_check
	var variation_check := VALUE.string_array(value.variation_tokens, false)
	if not variation_check.ok:
		return {"ok": false, "code": "scene.recipe.variation", "error_zh": "配方变化选项必须是稳定字符串数组。"}
	var recipe := GMSceneRecipe.new(
		str(value.recipe_id), str(value.display_name_zh), str(value.skeleton_id), entry_check.get("value", VALUE.duplicate_value(value.entry)), exit_check.get("value", VALUE.duplicate_value(value.exit)),
		required_check.value, objects_check.value, regions_check.value, slots_check.value,
		participants_check.value, objectives_check.value, results_check.value, variation_check.value
	)
	return {"ok": true, "value": recipe}

static func from_json(text: String) -> Dictionary:
	var parsed := VALUE.parse_json(text)
	if not parsed.ok:
		return parsed
	return from_dict(parsed.value)

static func _validate_semantic_objects(values: Variant) -> Dictionary:
	if typeof(values) != TYPE_ARRAY:
		return {"ok": false, "code": "scene.recipe.objects_type", "error_zh": "语义对象必须是数组。"}
	var normalized: Array = []
	var ids := {}
	for value in values:
		var fields := VALUE.exact_fields(value, ["object_id", "object_kind", "required", "tags"])
		if not fields.ok:
			return fields
		if not VALUE.stable_id(value.object_id) or not VALUE.stable_id(value.object_kind):
			return {"ok": false, "code": "scene.recipe.object_identity", "error_zh": "语义对象标识无效。"}
		if ids.has(str(value.object_id)):
			return {"ok": false, "code": "scene.recipe.object_duplicate", "error_zh": "语义对象ID重复。"}
		ids[str(value.object_id)] = true
		if typeof(value.required) != TYPE_BOOL:
			return {"ok": false, "code": "scene.recipe.object_required", "error_zh": "语义对象required必须是布尔值。"}
		var tags := VALUE.string_array(value.tags, true)
		if not tags.ok:
			return {"ok": false, "code": "scene.recipe.object_tags", "error_zh": "语义对象tags无效。"}
		normalized.append({"object_id": str(value.object_id), "object_kind": str(value.object_kind), "required": bool(value.required), "tags": tags.value})
	return {"ok": true, "value": normalized}

static func _validate_regions(values: Variant) -> Dictionary:
	if typeof(values) != TYPE_ARRAY:
		return {"ok": false, "code": "scene.recipe.regions_type", "error_zh": "语义区域必须是数组。"}
	var normalized: Array = []
	var ids := {}
	for value in values:
		var fields := VALUE.exact_fields(value, ["region_id", "region_kind", "required", "tags"])
		if not fields.ok:
			return fields
		if not VALUE.stable_id(value.region_id) or not VALUE.stable_id(value.region_kind):
			return {"ok": false, "code": "scene.recipe.region_identity", "error_zh": "配方区域标识无效。"}
		if ids.has(str(value.region_id)):
			return {"ok": false, "code": "scene.recipe.region_duplicate", "error_zh": "配方区域ID重复。"}
		ids[str(value.region_id)] = true
		if typeof(value.required) != TYPE_BOOL:
			return {"ok": false, "code": "scene.recipe.region_required", "error_zh": "配方区域required必须是布尔值。"}
		var tags := VALUE.string_array(value.tags, true)
		if not tags.ok:
			return {"ok": false, "code": "scene.recipe.region_tags", "error_zh": "配方区域tags无效。"}
		normalized.append({"region_id": str(value.region_id), "region_kind": str(value.region_kind), "required": bool(value.required), "tags": tags.value})
	return {"ok": true, "value": normalized}

static func _validate_slots(values: Variant, required_kinds: Array) -> Dictionary:
	if typeof(values) != TYPE_ARRAY or values.is_empty():
		return {"ok": false, "code": "scene.recipe.slots_type", "error_zh": "配方必须提供语义插槽。"}
	var normalized: Array = []
	var ids := {}
	var kind_counts := {}
	var entry_ref := {}
	var exit_ref := {}
	for value in values:
		var slot_check := SLOT.from_dict(value)
		if not slot_check.ok:
			return {"ok": false, "code": "scene.recipe.slot_invalid", "error_zh": "配方包含非法语义插槽。", "detail": slot_check}
		var slot_value: GMSemanticSlot2D = slot_check.value
		if ids.has(slot_value.slot_id):
			return {"ok": false, "code": "scene.recipe.slot_duplicate", "error_zh": "配方插槽ID重复。"}
		ids[slot_value.slot_id] = true
		kind_counts[slot_value.slot_kind] = int(kind_counts.get(slot_value.slot_kind, 0)) + 1
		if slot_value.slot_kind == "entry": entry_ref = slot_value.target_ref
		if slot_value.slot_kind == "exit": exit_ref = slot_value.target_ref
		if slot_value.required and slot_value.target_ref.is_empty():
			return {"ok": false, "code": "scene.recipe.slot_unbound", "error_zh": "required语义插槽不得没有目标绑定。"}
		normalized.append(slot_value.to_dict())
	for required_kind in required_kinds:
		if int(kind_counts.get(str(required_kind), 0)) < 1:
			return {"ok": false, "code": "scene.recipe.slot_kind_missing", "error_zh": "配方缺少需要验证的语义插槽：%s。" % str(required_kind)}
		var required_slot := _slot_for_kind(normalized, str(required_kind))
		if required_slot.is_empty() or typeof(required_slot.get("target_ref", null)) != TYPE_DICTIONARY or required_slot.target_ref.is_empty():
			return {"ok": false, "code": "scene.recipe.required_slot_unbound", "error_zh": "需要验证的语义插槽必须绑定稳定目标：%s。" % str(required_kind)}
	if entry_ref.is_empty() or exit_ref.is_empty():
		return {"ok": false, "code": "scene.recipe.entry_exit_slot_missing", "error_zh": "配方入口与出口插槽必须绑定目标。"}
	return {"ok": true, "value": normalized}

static func _slot_for_kind(values: Array, kind: String) -> Dictionary:
	for value in values:
		if typeof(value) == TYPE_DICTIONARY and str(value.get("slot_kind", "")) == kind:
			return value
	return {}

static func _validate_refs(values: Variant, code_prefix: String) -> Dictionary:
	if typeof(values) != TYPE_ARRAY:
		return {"ok": false, "code": code_prefix + ".type", "error_zh": "语义引用集合必须是数组。"}
	var normalized: Array = []
	for value in values:
		var check := VALUE.semantic_ref(value, false)
		if not check.ok:
			return {"ok": false, "code": code_prefix + ".invalid", "error_zh": "语义引用集合包含非法值。", "detail": check}
		normalized.append(VALUE.duplicate_value(check.get("value", value)))
	return {"ok": true, "value": normalized}

static func _validate_objectives(values: Variant) -> Dictionary:
	if typeof(values) != TYPE_ARRAY or values.is_empty():
		return {"ok": false, "code": "scene.recipe.objectives", "error_zh": "配方至少需要一个目标。"}
	var normalized: Array = []
	var ids := {}
	for value in values:
		var fields := VALUE.exact_fields(value, ["objective_id", "kind", "target_value", "contribution_field", "target_ref", "requires_hostile_clear"])
		if not fields.ok:
			return fields
		if not VALUE.stable_id(value.objective_id) or not OBJECTIVE_KINDS.has(str(value.kind)) or not VALUE.stable_id(value.contribution_field):
			return {"ok": false, "code": "scene.recipe.objective_identity", "error_zh": "目标标识、类型或贡献字段无效。"}
		if ids.has(str(value.objective_id)):
			return {"ok": false, "code": "scene.recipe.objective_duplicate", "error_zh": "目标ID重复。"}
		ids[str(value.objective_id)] = true
		var target_value := VALUE.integer_field(value.target_value, false)
		if not target_value.ok or target_value.value < 1:
			return {"ok": false, "code": "scene.recipe.objective_target", "error_zh": "目标target_value必须是正整数。"}
		var target_check := VALUE.semantic_ref(value.target_ref, true)
		if not target_check.ok:
			return {"ok": false, "code": "scene.recipe.objective_target_ref", "error_zh": "目标target_ref无效。"}
		if typeof(value.requires_hostile_clear) != TYPE_BOOL:
			return {"ok": false, "code": "scene.recipe.objective_hostiles", "error_zh": "目标requires_hostile_clear必须是布尔值。"}
		if str(value.kind) != "eliminate" and bool(value.requires_hostile_clear):
			return {"ok": false, "code": "scene.recipe.non_elimination_hostile_gate", "error_zh": "非歼灭目标不得隐式要求清空敌对角色。"}
		normalized.append({
			"objective_id": str(value.objective_id), "kind": str(value.kind), "target_value": int(target_value.value),
			"contribution_field": str(value.contribution_field), "target_ref": VALUE.duplicate_value(target_check.get("value", value.target_ref)),
			"requires_hostile_clear": bool(value.requires_hostile_clear)
		})
	return {"ok": true, "value": normalized}

static func _validate_results(values: Variant, objectives: Array = []) -> Dictionary:
	if typeof(values) != TYPE_ARRAY or values.is_empty():
		return {"ok": false, "code": "scene.recipe.results", "error_zh": "配方至少需要一个结果规则。"}
	var normalized: Array = []
	var ids := {}
	var statuses := {}
	var known_objectives := {}
	for objective in objectives:
		if typeof(objective) == TYPE_DICTIONARY:
			known_objectives[str(objective.get("objective_id", ""))] = true
	for value in values:
		var fields := VALUE.exact_fields(value, ["result_id", "status", "required_objective_ids", "reason_code"])
		if not fields.ok:
			return fields
		if not VALUE.stable_id(value.result_id) or not RESULT_STATUSES.has(str(value.status)) or not VALUE.stable_id(value.reason_code, true):
			return {"ok": false, "code": "scene.recipe.result_identity", "error_zh": "结果规则标识、状态或原因码无效。"}
		if ids.has(str(value.result_id)):
			return {"ok": false, "code": "scene.recipe.result_duplicate", "error_zh": "结果规则ID重复。"}
		ids[str(value.result_id)] = true
		statuses[str(value.status)] = true
		var objective_ids := VALUE.string_array(value.required_objective_ids, false)
		if not objective_ids.ok:
			return {"ok": false, "code": "scene.recipe.result_objectives", "error_zh": "结果规则的目标ID集合无效。"}
		var rule_objectives := {}
		for objective_id in objective_ids.value:
			if rule_objectives.has(objective_id):
				return {"ok": false, "code": "scene.recipe.result_objective_duplicate", "error_zh": "结果规则不得重复引用同一目标。"}
			if not known_objectives.has(objective_id):
				return {"ok": false, "code": "scene.recipe.result_objective_unknown", "error_zh": "结果规则引用了不存在的目标：%s。" % objective_id}
			rule_objectives[objective_id] = true
		normalized.append({"result_id": str(value.result_id), "status": str(value.status), "required_objective_ids": objective_ids.value, "reason_code": str(value.reason_code)})
	for status in RESULT_STATUSES:
		if not statuses.has(status):
			return {"ok": false, "code": "scene.recipe.result_status_missing", "error_zh": "配方必须声明success、partial_success、failed与extracted结果规则。"}
	return {"ok": true, "value": normalized}

func validate() -> Dictionary:
	return GMSceneRecipe.from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"recipe_id": recipe_id,
		"display_name_zh": display_name_zh,
		"skeleton_id": skeleton_id,
		"entry": VALUE.duplicate_value(entry),
		"exit": VALUE.duplicate_value(exit),
		"required_slot_kinds": VALUE.duplicate_value(required_slot_kinds),
		"semantic_objects": VALUE.duplicate_value(semantic_objects),
		"regions": VALUE.duplicate_value(regions),
		"slots": VALUE.duplicate_value(slots),
		"participants": VALUE.duplicate_value(participants),
		"objectives": VALUE.duplicate_value(objectives),
		"results": VALUE.duplicate_value(results),
		"variation_tokens": VALUE.duplicate_value(variation_tokens)
	}

func to_json() -> String:
	return VALUE.json_string(to_dict())

func fingerprint() -> String:
	return VALUE.digest(to_dict())
