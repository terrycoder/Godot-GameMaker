class_name GMPlanarCombatAdapter3D
extends "res://gm_runtime/combat/gm_combat_hit_query_adapter.gd"

## P22 query adapter for planar 3D.  It never computes damage or writes a
## fact; it validates Surface/TargetPoint and returns a pure hit query result.

const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

const BACKEND_ID := "planar_3d_hit_query"
const EPSILON := 0.001
const MAX_HEIGHT_TOLERANCE := 100.0

var map_backend: Object
var default_height_tolerance := 0.75

func _init(p_map_backend: Object = null, p_default_height_tolerance: float = 0.75) -> void:
	map_backend = p_map_backend
	default_height_tolerance = p_default_height_tolerance

func configure(p_map_backend: Object, p_default_height_tolerance: float = 0.75) -> GMPlanarCombatAdapter3D:
	map_backend = p_map_backend
	default_height_tolerance = p_default_height_tolerance
	return self

func query(spec, context: Dictionary = {}) -> Dictionary:
	if spec == null:
		return _blocked("combat.hit_query.spec_missing", "Planar 3D命中查询缺少HitSpec。")
	var spec_check: Dictionary = spec.validate() if spec is Object and spec.has_method("validate") else {"ok": false, "errors": ["HitSpec类型无效。"]}
	if not spec_check.ok:
		return _blocked("combat.hit_query.spec_invalid", "Planar 3D命中查询的HitSpec未通过校验。", {"errors": spec_check.get("errors", [])})
	var pure_context := CONTRACT.pure(context)
	if not pure_context.ok:
		return _blocked("combat.hit_query_context_invalid", "Planar 3D命中查询上下文只能是纯数据。")
	if map_backend == null or not map_backend.has_method("resolve_surface"):
		return _blocked("combat.3d.map_backend_missing", "Planar 3D命中查询未安装现有Surface Graph后端。")
	if context.has("blocked_target_ids") and not CONTRACT.string_array(context.get("blocked_target_ids")):
		return _blocked("combat.hit_query_context_invalid", "blocked_target_ids必须是稳定ID数组。")
	if context.has("force_hit") and typeof(context.get("force_hit")) != TYPE_BOOL:
		return _blocked("combat.hit_query_context_invalid", "force_hit必须是布尔值。")
	var source_parsed := PLANAR_POSITION.from_native(context.get("source_position", null))
	if not source_parsed.ok:
		return _blocked("combat.3d.source_position_missing", "Planar 3D命中查询缺少有效源逻辑位置。", {"details": source_parsed})
	var target_parsed := PLANAR_POSITION.from_native(context.get("target_position", null))
	if not target_parsed.ok:
		return _blocked("combat.3d.target_point_missing", "Planar 3D命中查询缺少有效TargetPoint逻辑位置。", {"details": target_parsed})
	var source: GMPlanarPosition = source_parsed.position
	var target: GMPlanarPosition = target_parsed.position
	if source.map_id != target.map_id:
		return _blocked("combat.3d.map_mismatch", "Planar 3D战斗源与目标不在同一语义地图。")
	var profile := str(context.get("agent_profile", "default"))
	var source_surface_check := _validate_surface(source, profile, "source")
	if not source_surface_check.ok:
		return source_surface_check
	var target_surface_check := _validate_surface(target, profile, "target")
	if not target_surface_check.ok:
		return target_surface_check
	var target_point_check := _validate_target_point(spec, context, target)
	if not target_point_check.ok:
		return target_point_check
	var tolerance := float(context.get("height_tolerance", default_height_tolerance))
	if not is_finite(tolerance) or tolerance < 0.0 or tolerance > MAX_HEIGHT_TOLERANCE:
		return _blocked("combat.3d.height_tolerance_invalid", "TargetPoint高度容差必须是有界有限数值。")
	var target_surface: Object = target_surface_check.surface
	var expected_target_height := float(target_surface.call("world_height_at", Vector2(target.x, target.y)))
	var target_world: Dictionary = context.get("target_world", {}) if context.get("target_world", {}) is Dictionary else {}
	var world_check := _world_value(target_world)
	if not world_check.ok:
		return _blocked("combat.3d.target_point_missing", "TargetPoint缺少可验证的三维世界位置。")
	if absf(float(target_world.y) - expected_target_height) > tolerance:
		return _blocked("combat.3d.height_tolerance_exceeded", "TargetPoint高度超出当前Surface容差，命中被安全阻断。", {"expected_height": expected_target_height, "actual_height": float(target_world.y), "tolerance": tolerance})
	var source_world_y: Variant = context.get("source_world_y", null)
	if source_world_y != null:
		if typeof(source_world_y) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(source_world_y)):
			return _blocked("combat.3d.source_height_invalid", "源点高度必须是有限数值。")
		var source_surface: Object = source_surface_check.surface
		var expected_source_height := float(source_surface.call("world_height_at", Vector2(source.x, source.y)))
		if absf(float(source_world_y) - expected_source_height) > tolerance:
			return _blocked("combat.3d.height_tolerance_exceeded", "源点高度超出当前Surface容差，命中被安全阻断。", {"expected_height": expected_source_height, "actual_height": float(source_world_y), "tolerance": tolerance})
	var planar_delta := Vector2(target.x - source.x, target.y - source.y)
	var planar_distance := planar_delta.length()
	if is_zero_approx(planar_distance):
		return _blocked("combat.3d.planar_direction_missing", "Planar 3D命中查询不能使用零Planar方向。")
	if absf(float(spec.distance) - planar_distance) > EPSILON:
		return _blocked("combat.3d.planar_distance_mismatch", "HitSpec距离与源/目标Vector2平面距离不一致。", {"spec_distance": spec.distance, "planar_distance": planar_distance})
	if spec.max_distance > 0.0 and planar_distance > spec.max_distance + EPSILON:
		return _result(false, "combat.miss.out_of_range", "目标超出Planar规则距离。", spec.target_id, target, planar_distance, expected_target_height, tolerance)
	if str(source.surface_id) == str(target.surface_id) and map_backend.has_method("is_logical_segment_blocked") and bool(map_backend.call("is_logical_segment_blocked", source.map_id, source.surface_id, Vector2(source.x, source.y), Vector2(target.x, target.y), float(spec.shape_radius))):
		return _result(false, "combat.miss.dynamic_obstacle", "源到目标的Planar路径被动态障碍阻断。", spec.target_id, target, planar_distance, expected_target_height, tolerance)
	var blocked_targets: Array = context.get("blocked_target_ids", []) if context.get("blocked_target_ids", []) is Array else []
	if blocked_targets.has(spec.target_id):
		return _result(false, "combat.miss.blocked_target", "目标被查询规则阻断。", spec.target_id, target, planar_distance, expected_target_height, tolerance)
	var forced_hit := bool(context.get("force_hit", true))
	return _result(forced_hit, "combat.hit" if forced_hit else "combat.miss", "命中。" if forced_hit else "未命中。", spec.target_id, target, planar_distance, expected_target_height, tolerance)

func _validate_surface(position: GMPlanarPosition, profile: String, side: String) -> Dictionary:
	var surface: Object = map_backend.call("resolve_surface", position.map_id, position.surface_id)
	if surface == null:
		return _blocked("combat.3d.surface_missing", "%s侧引用的Surface不存在。" % side, {"map_id": position.map_id, "surface_id": position.surface_id})
	if not bool(surface.get("walkable")):
		return _blocked("combat.3d.surface_not_walkable", "%s侧Surface不可行走。" % side, {"surface_id": position.surface_id})
	if not bool(surface.call("supports_agent", profile)):
		return _blocked("combat.3d.surface_agent_profile_invalid", "%s侧Surface不支持当前Agent Profile。" % side, {"surface_id": position.surface_id, "agent_profile": profile})
	if not bool(surface.call("contains_logical", Vector2(position.x, position.y))):
		return _blocked("combat.3d.position_outside_surface", "%s侧逻辑位置不在Surface内。" % side, {"surface_id": position.surface_id})
	return {"ok": true, "surface": surface}

func _validate_target_point(spec, context: Dictionary, target: GMPlanarPosition) -> Dictionary:
	var raw_point: Variant = context.get("target_point", null)
	if not raw_point is Dictionary:
		return _blocked("combat.3d.target_point_missing", "命中查询必须由TargetPoint3D提供稳定目标点。")
	for field in ["schema", "target_point_id", "target_ref", "map_id", "surface_id", "height_tolerance", "agent_profile", "world_position"]:
		if not raw_point.has(field):
			return _blocked("combat.3d.target_point_missing", "TargetPoint3D缺少字段：%s。" % field)
	if str(raw_point.get("schema", "")) != "gm.combat.target_point_3d.v1":
		return _blocked("combat.3d.target_point_invalid", "TargetPoint3D Schema无效。")
	if not CONTRACT.stable_id(str(raw_point.get("target_point_id", ""))) or not str(raw_point.target_point_id).begins_with("gm.target_point."):
		return _blocked("combat.3d.target_point_invalid", "TargetPoint3D身份无效。")
	if not CONTRACT.stable_id(str(raw_point.get("target_ref", ""))) or str(raw_point.target_ref) != str(spec.target_id):
		return _blocked("combat.3d.target_point_target_mismatch", "TargetPoint3D目标身份与HitSpec不一致。")
	if str(raw_point.get("map_id", "")) != target.map_id or str(raw_point.get("surface_id", "")) != target.surface_id:
		return _blocked("combat.3d.target_point_surface_mismatch", "TargetPoint3D与目标逻辑Surface不一致。")
	return {"ok": true, "code": "combat.3d.target_point_valid"}

func _world_value(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.has("x") or not value.has("y") or not value.has("z"):
		return {"ok": false}
	for key in ["x", "y", "z"]:
		if typeof(value.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value.get(key))):
			return {"ok": false}
	return {"ok": true}

func _result(hit: bool, code: String, reason_zh: String, target_id: String, target: GMPlanarPosition, distance: float, surface_height: float, tolerance: float) -> Dictionary:
	return {
		"ok": true,
		"hit": hit,
		"code": code,
		"reason_zh": reason_zh,
		"backend_id": BACKEND_ID,
		"target_id": target_id,
		"distance": distance,
		"planar_distance": distance,
		"surface_id": target.surface_id,
		"surface_height": surface_height,
		"height_tolerance": tolerance,
		"height_ignored_for_rule": true,
	}

func _blocked(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh, "backend_id": BACKEND_ID}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
