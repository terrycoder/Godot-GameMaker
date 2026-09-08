class_name GMInteractionQuery3D
extends RefCounted

## Query-only Planar 3D interaction surface.  Raycasts select stable targets;
## final output is an existing GMAbilityActivationRequest or P21 request value.
## No method here invokes a domain interaction or writes a Fact/Cue.

const SPATIAL_DOMAIN := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")
const SPATIAL_CAPABILITIES := preload("res://gm_runtime/spatial_core/gm_spatial_backend_capabilities.gd")
const QUERY_RESULT := preload("res://gm_runtime/spatial_core/gm_spatial_query_result.gd")
const TARGET_REF := preload("res://gm_runtime/spatial_core/gm_spatial_target_ref.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const SCREEN_BRIDGE := preload("res://gm_adapters/spatial3d/gm_screen_world_bridge_3d.gd")
const P21_SUPPORT := preload("res://gm_runtime/p21/gm_p21_backend_support.gd")
const INTERACTION_REQUEST := preload("res://gm_runtime/p21/gm_interaction_request.gd")

var spatial_adapter: Object
var runtime_context: Object
var screen_bridge: GMScreenWorldBridge3D
var last_candidate: Dictionary = {}

func _init(p_adapter: Object = null, p_context: Object = null) -> void:
	spatial_adapter = p_adapter
	runtime_context = p_context
	screen_bridge = SCREEN_BRIDGE.new(p_adapter, p_context)

func query_ray(origin: Variant, direction: Variant, max_distance: float = 1000.0, context: Dictionary = {}) -> Dictionary:
	var origin_result := _vector3(origin)
	var direction_result := _vector3(direction)
	if not origin_result.ok or not direction_result.ok or direction_result.value.length_squared() <= 0.000001:
		return _blocked("interaction.ray_invalid", "交互射线必须包含有限原点与非零方向。", {"origin": origin, "direction": direction})
	if not is_finite(max_distance) or max_distance <= 0.0:
		return _blocked("interaction.range_invalid", "交互射线范围必须是正的有限数值。", {})
	var hits: Array = []
	if context.get("ray_hits", null) is Array:
		hits = context.ray_hits.duplicate(true)
	elif context.get("space_state", null) != null and context.space_state.has_method("intersect_ray"):
		var query := PhysicsRayQueryParameters3D.create(origin_result.value, origin_result.value + direction_result.value.normalized() * max_distance)
		var hit: Dictionary = context.space_state.intersect_ray(query)
		if not hit.is_empty(): hits.append(hit)
	if hits.is_empty(): return _blocked("interaction.ray_no_hit", "射线没有命中可交互对象。", {"max_distance": max_distance})
	var selected := select_controller_candidate(hits, {"max_distance": max_distance})
	return selected

func query_object(candidate: Variant, context: Dictionary = {}) -> Dictionary:
	var normalized := _normalize_candidate(candidate, context)
	if not normalized.ok: return _blocked(str(normalized.get("code", "interaction.candidate_invalid")), str(normalized.get("reason_zh", "交互对象候选无效。")), normalized)
	last_candidate = normalized.candidate.duplicate(true)
	return QUERY_RESULT.success(SPATIAL_DOMAIN.PLANAR_3D, "gm.spatial.capability.resolve_target", normalized.target_ref, normalized.value)

func query_ground(world_position: Variant, context: Dictionary = {}) -> Dictionary:
	var point := _vector3(world_position)
	if not point.ok: return _blocked("interaction.world_invalid", "地面查询世界位置无效。", {})
	var result := _adapter_call("find_nearest_surface", [point.value, context])
	if not result.ok: return _blocked(str(result.get("code", "interaction.ground_missing")), str(result.get("error_zh", "没有唯一可用地面。")), result)
	return QUERY_RESULT.success(SPATIAL_DOMAIN.PLANAR_3D, "gm.spatial.capability.find_nearest_surface", result.target, {"planar_position": result.value.get("planar_position", {}), "world_position": result.value.get("world_position", {"x": point.value.x, "y": point.value.y, "z": point.value.z}), "ground_height": result.value.get("ground_height", 0.0), "surface_id": result.value.get("surface_id", ""), "map_id": result.value.get("map_id", "")})

func query_screen(screen_position: Variant, context: Dictionary = {}) -> Dictionary:
	var result := screen_bridge.screen_to_target(screen_position, context)
	if not result.ok: return result
	last_candidate = {"target_ref": result.target.duplicate(true), "value": result.value.duplicate(true)}
	return result

func select_controller_candidate(candidates: Array, context: Dictionary = {}) -> Dictionary:
	var rows: Array = []
	for candidate in candidates:
		var normalized := _normalize_candidate(candidate, context)
		if normalized.ok: rows.append(normalized.candidate)
	if rows.is_empty(): return _blocked("interaction.candidate_missing", "控制器候选没有可用稳定目标。", {})
	rows.sort_custom(func(left: Dictionary, right: Dictionary):
		var lp := int(left.get("priority", 0)); var rp := int(right.get("priority", 0))
		if lp != rp: return lp > rp
		var ld := float(left.get("distance", INF)); var rd := float(right.get("distance", INF))
		if not is_equal_approx(ld, rd): return ld < rd
		return str(left.get("semantic_id", "")) < str(right.get("semantic_id", "")))
	if rows.size() > 1 and int(rows[0].get("priority", 0)) == int(rows[1].get("priority", 0)) and is_equal_approx(float(rows[0].get("distance", 0.0)), float(rows[1].get("distance", 0.0))):
		return _blocked("interaction.candidate_ambiguous", "多个交互候选优先级与距离相同，未猜测目标。", {"candidates": rows.map(func(row): return row.get("semantic_id", ""))})
	var selected: Dictionary = rows[0]
	last_candidate = selected.duplicate(true)
	return QUERY_RESULT.success(SPATIAL_DOMAIN.PLANAR_3D, "gm.spatial.capability.resolve_target", selected.target_ref, selected.value)

func within_range(source_position: Variant, target_position: Variant, max_range: float, context: Dictionary = {}) -> Dictionary:
	if not is_finite(max_range) or max_range < 0.0: return _blocked("interaction.range_invalid", "交互范围必须是有限非负数值。", {})
	var distance := _adapter_call("get_planar_distance", [source_position, target_position, context])
	if not distance.ok: return _blocked(str(distance.get("code", "interaction.distance_unavailable")), str(distance.get("error_zh", "交互距离无法计算。")), distance)
	var value := float(distance.value.get("distance", INF))
	return QUERY_RESULT.success(SPATIAL_DOMAIN.PLANAR_3D, "gm.spatial.capability.planar_distance", {}, {"distance": value, "max_range": max_range, "in_range": value <= max_range, "surface_transitions": distance.value.get("surface_transitions", [])})

func build_activation_request(host: GMAbilitySystemHost, ability_id: String, source: String, target_value: Variant, payload: Dictionary = {}, idempotency_key: String = "") -> Dictionary:
	var target := TARGET_REF.from_native(target_value)
	if not target.ok: return {"ok": false, "code": "interaction.target_invalid", "reason_zh": "交互激活目标必须是稳定空间TargetRef。", "details": target}
	var data := payload.duplicate(true)
	data["spatial_target"] = target.target.to_native()
	data["target_id"] = target.target.semantic_id() if not target.target.semantic_id().is_empty() else target.target.map_id()
	return P21_SUPPORT.build_ability_request(INTERACTION_REQUEST.ability("gm.interaction.planar3d", source, target.target.to_native(), data, idempotency_key), ability_id, data, host)

func build_interaction_request(interaction_id: String, source: Variant, target_value: Variant, payload: Dictionary, idempotency_key: String) -> GMInteractionRequest:
	return INTERACTION_REQUEST.ability(interaction_id, source, target_value, payload, idempotency_key)

func _normalize_candidate(candidate: Variant, context: Dictionary) -> Dictionary:
	var source: Dictionary = candidate if candidate is Dictionary else {}
	var collider: Object = source.get("collider", null)
	if collider != null and is_instance_valid(collider):
		var collider_identity := _authoritative_collider_identity(collider)
		if not collider_identity.ok: return collider_identity
		var semantic_id := str(collider_identity.stable_id)
		var map_id := str(collider.get("map_id")) if "map_id" in collider else str(context.get("map_id", ""))
		source = source.duplicate(true)
		source["semantic_id"] = semantic_id
		source["map_id"] = map_id
		if "spatial_position" in collider: source["planar_position"] = collider.get("spatial_position")
	var ref_value = source.get("target_ref", source.get("target", null))
	if ref_value == null:
		var kind := str(source.get("kind", "entity"))
		var semantic_id := str(source.get("semantic_id", source.get("entity_id", "")))
		var map_id := str(source.get("map_id", context.get("map_id", "")))
		ref_value = {"schema_version": 1, "domain_id": SPATIAL_DOMAIN.PLANAR_3D, "kind": kind, "semantic_id": semantic_id, "map_id": map_id}
	var target := TARGET_REF.from_native(ref_value)
	if not target.ok: return {"ok": false, "code": "interaction.target_ref_invalid", "reason_zh": "候选无法生成稳定TargetRef。", "details": target}
	var distance := float(source.get("distance", 0.0))
	if not is_finite(distance) or distance < 0.0: return {"ok": false, "code": "interaction.distance_invalid", "reason_zh": "交互候选距离无效。"}
	var value := {"semantic_id": target.target.semantic_id(), "kind": target.target.kind(), "map_id": target.target.map_id(), "distance": distance, "priority": int(source.get("priority", 0)), "target_ref": target.target.to_native()}
	if source.has("planar_position"):
		var position := PLANAR_POSITION.from_native(source.planar_position)
		if position.ok: value["planar_position"] = position.position.to_native()
	return {"ok": true, "target_ref": target.target.to_native(), "value": value, "candidate": {"target_ref": target.target.to_native(), "value": value, "semantic_id": target.target.semantic_id(), "priority": int(source.get("priority", 0)), "distance": distance}}

func _authoritative_collider_identity(collider: Object) -> Dictionary:
	if collider == null or not is_instance_valid(collider):
		return {"ok": false, "code": "interaction.collider_missing", "reason_zh": "交互Collider不存在。"}
	var raw_identity: Variant = null
	if "stable_instance_id" in collider:
		raw_identity = collider.get("stable_instance_id")
	elif collider is Node and (collider as Node).has_meta("gm_stable_instance_id"):
		raw_identity = (collider as Node).get_meta("gm_stable_instance_id")
	if not raw_identity is String and not raw_identity is StringName:
		return {"ok": false, "code": "interaction.collider_identity_missing", "reason_zh": "交互Collider缺少已注册的稳定对象身份；不能使用Node名称。"}
	var stable_id := str(raw_identity)
	if stable_id.is_empty():
		return {"ok": false, "code": "interaction.collider_identity_missing", "reason_zh": "交互Collider缺少已注册的稳定对象身份；不能使用Node名称。"}
	if not PLANAR_POSITION.is_valid_stable_id(stable_id):
		return {"ok": false, "code": "interaction.collider_identity_invalid", "reason_zh": "交互Collider的稳定对象身份无效。"}
	return {"ok": true, "stable_id": stable_id}

func _adapter_call(method_name: String, arguments: Array) -> Dictionary:
	var raw: Variant = null
	if spatial_adapter != null and is_instance_valid(spatial_adapter) and spatial_adapter.has_method(method_name): raw = spatial_adapter.callv(method_name, arguments)
	elif runtime_context != null and is_instance_valid(runtime_context) and runtime_context.has_method("query_spatial"): raw = runtime_context.call("query_spatial", _capability_for(method_name), method_name, arguments)
	return raw if raw is Dictionary else _blocked("interaction.adapter_missing", "交互查询缺少现有空间适配器。", {})

func _capability_for(method_name: String) -> String:
	return {"find_nearest_surface": SPATIAL_CAPABILITIES.FIND_NEAREST_SURFACE, "get_planar_distance": SPATIAL_CAPABILITIES.PLANAR_DISTANCE}.get(method_name, "")

func _vector3(value: Variant) -> Dictionary:
	var result := Vector3.ZERO
	if value is Vector3: result = value
	elif value is Dictionary and value.has("x") and value.has("y") and value.has("z"): result = Vector3(float(value.x), float(value.y), float(value.z))
	else: return {"ok": false}
	return {"ok": is_finite(result.x) and is_finite(result.y) and is_finite(result.z), "value": result}

func _blocked(code: String, reason_zh: String, details: Dictionary) -> Dictionary:
	return QUERY_RESULT.blocked(code, reason_zh, SPATIAL_DOMAIN.PLANAR_3D, "gm.spatial.capability.resolve_target", details)
