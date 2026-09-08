extends RefCounted

## P24 后端适配边界。
##
## 同一 Definition/Ability/Resolver 可以把对象绑定到实际 Planar2D 或
## Planar3D 空间后端。适配器只处理 visual/collision/interaction_point/
## navigation 四类派生值，并把解析结果保持为纯值；它不创建节点、不保存对象
## 状态，也不向 SceneSession、World 或 Store 提交事实。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const DEFINITION := preload("res://gm_runtime/level/gm_level_object_definition.gd")
const RECIPE := preload("res://gm_runtime/level/gm_level_object_recipe.gd")
const SPATIAL_DOMAIN := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")
const CAPABILITIES := preload("res://gm_runtime/spatial_core/gm_spatial_backend_capabilities.gd")
const SPATIAL_TARGET := preload("res://gm_runtime/spatial_core/gm_spatial_target_ref.gd")

const SCHEMA_VERSION := "gm.level.object_projection.v1"
const PRESENTATION_FIELDS: Array[String] = ["visual", "collision", "interaction_point", "navigation"]
const FIELDS: Array[String] = [
	"schema_version", "backend_domain", "backend_id", "object_id", "definition_id", "object_kind",
	"slot_id", "slot_kind", "resolved_target", "projection_only", "visual", "collision", "interaction_point", "navigation"
]

var _backend: Object

func _init(backend: Object = null) -> void:
	_backend = backend

func backend() -> Object:
	return _backend

func materialize(definition_value: Variant, object_value: Variant, slot_value: Variant, presentation: Dictionary = {}) -> Dictionary:
	var backend_check := _backend_identity()
	if not backend_check.ok:
		return backend_check
	var definition_check := _as_definition(definition_value)
	if not definition_check.ok:
		return definition_check
	var definition = definition_check.value
	var object_check := _validate_object_binding(object_value)
	if not object_check.ok:
		return object_check
	var object: Dictionary = object_check.value
	var slot_check := _validate_slot(slot_value)
	if not slot_check.ok:
		return slot_check
	var slot: Dictionary = slot_check.value
	if str(object.definition_id) != definition.definition_id:
		return _blocked("level_object.adapter.definition_mismatch", "对象绑定与Definition不一致。")
	if str(object.slot_id) != str(slot.slot_id):
		return _blocked("level_object.adapter.slot_mismatch", "对象绑定与语义槽不一致。")
	var presentation_check := _validate_presentation(presentation)
	if not presentation_check.ok:
		return presentation_check
	var resolved_target := _resolve_target(slot.target_ref, str(backend_check.domain_id))
	if not resolved_target.ok:
		return resolved_target
	var result: Dictionary = VALUE.persistence_canonical({
		"schema_version": SCHEMA_VERSION,
		"backend_domain": str(backend_check.domain_id),
		"backend_id": str(backend_check.backend_id),
		"object_id": str(object.object_id),
		"definition_id": definition.definition_id,
		"object_kind": definition.object_kind,
		"slot_id": str(slot.slot_id),
		"slot_kind": str(slot.slot_kind),
		"resolved_target": resolved_target.value,
		"projection_only": true,
		"visual": presentation_check.value.visual,
		"collision": presentation_check.value.collision,
		"interaction_point": presentation_check.value.interaction_point,
		"navigation": presentation_check.value.navigation
	})
	var persistence := VALUE.persistence(result)
	if not persistence.ok:
		return _blocked("level_object.adapter.output_persistence", "对象后端投影包含非纯值。", persistence)
	var parsed := parse_projection(result)
	if not parsed.ok:
		return parsed
	return {"ok": true, "value": parsed.value}

static func parse_projection(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var persistence := VALUE.persistence(value)
	if not persistence.ok:
		return {"ok": false, "code": "level_object.projection.persistence", "error_zh": "对象后端投影必须是可持久化纯值。"}
	if str(value.schema_version) != SCHEMA_VERSION:
		return _blocked("level_object.projection.schema", "对象后端投影Schema版本不匹配。")
	for identity in ["backend_domain", "backend_id", "object_id", "definition_id", "object_kind", "slot_id", "slot_kind"]:
		if not VALUE.stable_id(value.get(identity, ""), false):
			return _blocked("level_object.projection.identity", "对象后端投影包含非法稳定标识。", {"field": identity})
	if typeof(value.projection_only) != TYPE_BOOL or not bool(value.projection_only):
		return _blocked("level_object.projection.authority", "对象后端投影必须明确标记为presentation-only。")
	if typeof(value.resolved_target) != TYPE_DICTIONARY or not VALUE.persistence(value.resolved_target).ok:
		return _blocked("level_object.projection.target", "对象后端投影目标必须是纯字典。")
	for field in PRESENTATION_FIELDS:
		if typeof(value.get(field, null)) != TYPE_DICTIONARY or not VALUE.persistence(value.get(field)).ok:
			return _blocked("level_object.projection.presentation", "对象后端投影的适配值必须是纯字典。", {"field": field})
	return {"ok": true, "value": VALUE.persistence_canonical(value)}

func _backend_identity() -> Dictionary:
	if _backend == null or not is_instance_valid(_backend):
		return _blocked("level_object.adapter.backend_missing", "P24对象适配缺少空间后端。")
	if not _backend.has_method("capabilities") or not _backend.has_method("resolve_target"):
		return _blocked("level_object.adapter.backend_contract", "P24对象适配后端必须复用既有capabilities/resolve_target合同。")
	var capabilities = _backend.capabilities()
	if capabilities == null or not capabilities.has_method("domain_id") or not capabilities.has_method("supports"):
		return _blocked("level_object.adapter.capabilities", "P24对象适配后端空间能力声明无效。")
	var domain_id := str(capabilities.domain_id())
	if not SPATIAL_DOMAIN.is_execution_available(domain_id):
		return _blocked("level_object.adapter.domain", "P24对象适配只支持可执行的Planar2D/Planar3D后端。", {"domain_id": domain_id})
	if not capabilities.supports(CAPABILITIES.RESOLVE_TARGET):
		return _blocked("level_object.adapter.resolve_capability", "P24对象适配后端没有既有resolve_target能力。")
	return {"ok": true, "domain_id": domain_id, "backend_id": domain_id}

func _resolve_target(value: Dictionary, domain_id: String) -> Dictionary:
	var target_check := VALUE.semantic_ref(value, false)
	if not target_check.ok:
		return _blocked("level_object.adapter.target", "P24对象语义槽目标无效。", target_check)
	var normalized: Dictionary = target_check.value
	if normalized.has("schema_version") and normalized.has("domain_id") and normalized.has("kind"):
		var spatial_check := SPATIAL_TARGET.from_native(normalized)
		if not spatial_check.ok:
			return _blocked("level_object.adapter.spatial_target", "P24对象空间目标无效。", spatial_check)
		if spatial_check.target.domain_id() != domain_id:
			return _blocked("level_object.adapter.domain_mismatch", "P24对象目标空间域与后端不一致。")
		var resolved = _backend.resolve_target(spatial_check.target)
		if not resolved is Dictionary or not bool(resolved.get("ok", false)):
			return _blocked("level_object.adapter.target_unresolvable", "P24对象语义槽目标无法由当前空间后端解析。", resolved if resolved is Dictionary else {})
		var persistence := VALUE.persistence(resolved)
		if not persistence.ok:
			return _blocked("level_object.adapter.target_runtime_value", "空间后端解析结果包含运行时对象。", persistence)
		return {"ok": true, "value": VALUE.duplicate_value(resolved)}
	return {"ok": true, "value": {"kind": "semantic", "ref": VALUE.duplicate_value(normalized)}}

static func _validate_object_binding(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, RECIPE.OBJECT_FIELDS)
	if not fields.ok:
		return fields
	for identity in ["object_id", "definition_id", "slot_id"]:
		if not VALUE.stable_id(value.get(identity, ""), false):
			return _blocked("level_object.adapter.object_identity", "P24对象绑定标识无效。", {"field": identity})
	if typeof(value.initial_state) != TYPE_DICTIONARY or not VALUE.persistence(value.initial_state).ok:
		return _blocked("level_object.adapter.object_state", "P24对象初始状态必须是纯字典。")
	var tags := VALUE.string_array(value.tags, true)
	if not tags.ok:
		return _blocked("level_object.adapter.object_tags", "P24对象标签无效。")
	return {"ok": true, "value": {"object_id": str(value.object_id), "definition_id": str(value.definition_id), "slot_id": str(value.slot_id), "initial_state": VALUE.duplicate_value(value.initial_state), "tags": tags.value}}

static func _validate_slot(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, ["schema_version", "slot_id", "slot_kind", "target_ref", "required", "capacity", "tags"])
	if not fields.ok:
		return fields
	if not VALUE.stable_id(value.slot_id, false) or not VALUE.stable_id(value.slot_kind, false):
		return _blocked("level_object.adapter.slot_identity", "P24对象语义槽标识无效。")
	var target := VALUE.semantic_ref(value.target_ref, false)
	if not target.ok:
		return _blocked("level_object.adapter.slot_target", "P24对象语义槽目标无效。")
	return {"ok": true, "value": {"schema_version": str(value.schema_version), "slot_id": str(value.slot_id), "slot_kind": str(value.slot_kind), "target_ref": target.value, "required": bool(value.required), "capacity": int(value.capacity), "tags": VALUE.duplicate_value(value.tags)}}

static func _validate_presentation(value: Dictionary) -> Dictionary:
	var normalized := {}
	for field in PRESENTATION_FIELDS:
		var candidate = value.get(field, {})
		if typeof(candidate) != TYPE_DICTIONARY or not VALUE.persistence(candidate).ok:
			return _blocked("level_object.adapter.presentation", "P24对象适配值必须是纯字典。", {"field": field})
		normalized[field] = VALUE.duplicate_value(candidate)
	return {"ok": true, "value": normalized}

static func _as_definition(value: Variant) -> Dictionary:
	if value is RefCounted and value.get_script() == DEFINITION:
		return {"ok": true, "value": value}
	return DEFINITION.from_dict(value)

static func _blocked(code: String, error_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error_zh": error_zh}
	if not details.is_empty():
		result["details"] = VALUE.duplicate_value(details)
	return result
