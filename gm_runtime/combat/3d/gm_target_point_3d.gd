@tool
class_name GMTargetPoint3D
extends Node3D

## Runtime marker for a combat target.  The marker is an engine object only at
## the presentation/query edge; capture_context() emits stable pure values.

const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

const SCHEMA := "gm.combat.target_point_3d.v1"
const FIELDS := ["schema", "target_point_id", "target_ref", "map_id", "surface_id", "anchor_id", "height_tolerance", "agent_profile", "world_position"]

@export var target_point_id := ""
@export var target_ref := ""
@export var map_id := ""
@export var surface_id := ""
@export var anchor_id := ""
@export var height_tolerance := 0.75
@export var agent_profile := "default"

func _init() -> void:
	name = "GMTargetPoint3D"

func configure(p_target_point_id: String, p_target_ref: String, p_map_id: String, p_surface_id: String, p_height_tolerance: float = 0.75, p_anchor_id: String = "", p_agent_profile: String = "default") -> GMTargetPoint3D:
	target_point_id = p_target_point_id
	target_ref = p_target_ref
	map_id = p_map_id
	surface_id = p_surface_id
	height_tolerance = p_height_tolerance
	anchor_id = p_anchor_id
	agent_profile = p_agent_profile
	return self

func to_native() -> Dictionary:
	var current_position := global_position if is_inside_tree() else position
	return {
		"schema": SCHEMA,
		"target_point_id": target_point_id,
		"target_ref": target_ref,
		"map_id": map_id,
		"surface_id": surface_id,
		"anchor_id": anchor_id,
		"height_tolerance": height_tolerance,
		"agent_profile": agent_profile,
		"world_position": _world_native(current_position),
	}

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not CONTRACT.exact(to_native(), FIELDS):
		errors.append("TargetPoint3D字段集合必须精确匹配。")
	if str(to_native().get("schema", "")) != SCHEMA:
		errors.append("TargetPoint3D schema无效。")
	if not CONTRACT.stable_id(target_point_id) or not target_point_id.begins_with("gm.target_point."):
		errors.append("TargetPoint3D target_point_id必须使用gm.target_point.*稳定身份。")
	if not CONTRACT.stable_id(target_ref):
		errors.append("TargetPoint3D target_ref必须是稳定目标ID。")
	if not CONTRACT.stable_id(map_id) or not CONTRACT.stable_id(surface_id):
		errors.append("TargetPoint3D map_id/surface_id必须是稳定ID。")
	if not CONTRACT.stable_id(anchor_id, true) or not CONTRACT.stable_id(agent_profile):
		errors.append("TargetPoint3D anchor_id/agent_profile不是稳定值。")
	if not CONTRACT.finite_nonnegative(height_tolerance) or height_tolerance > 100.0:
		errors.append("TargetPoint3D height_tolerance必须是0至100的有限数值。")
	if not _world_valid(global_position):
		errors.append("TargetPoint3D世界坐标必须是有限数值。")
	return {"ok": errors.is_empty(), "code": "combat.target_point_3d.valid" if errors.is_empty() else "combat.target_point_3d.invalid", "errors": errors}

## Capture from the current marker transform.  No Node, RID or NodePath is
## returned; the adapter receives only this dictionary.
func capture_context(map_backend: Object) -> Dictionary:
	var checked := validate()
	if not checked.ok:
		return _failure("combat.3d.target_point_invalid", "TargetPoint3D未通过稳定值校验。", {"errors": checked.errors})
	if map_backend == null or not map_backend.has_method("resolve_surface"):
		return _failure("combat.3d.map_backend_missing", "TargetPoint3D缺少现有Planar 3D Surface后端。")
	var surface: Object = map_backend.call("resolve_surface", map_id, surface_id)
	if surface == null:
		return _failure("combat.3d.surface_missing", "TargetPoint3D引用的Surface不存在。", {"map_id": map_id, "surface_id": surface_id})
	var logical: Vector2 = surface.call("world_to_logical", global_position)
	return capture_context_for_logical(logical, map_backend)

func capture_context_for_logical(logical: Vector2, map_backend: Object) -> Dictionary:
	var checked := validate()
	if not checked.ok:
		return _failure("combat.3d.target_point_invalid", "TargetPoint3D未通过稳定值校验。", {"errors": checked.errors})
	if not _vector2_valid(logical):
		return _failure("combat.3d.target_point_logical_invalid", "TargetPoint3D逻辑位置必须是有限二维值。")
	if map_backend == null or not map_backend.has_method("resolve_surface"):
		return _failure("combat.3d.map_backend_missing", "TargetPoint3D缺少现有Planar 3D Surface后端。")
	var surface: Object = map_backend.call("resolve_surface", map_id, surface_id)
	if surface == null:
		return _failure("combat.3d.surface_missing", "TargetPoint3D引用的Surface不存在。", {"map_id": map_id, "surface_id": surface_id})
	if not bool(surface.get("walkable")) or not bool(surface.call("supports_agent", agent_profile)):
		return _failure("combat.3d.surface_not_walkable", "TargetPoint3D所在Surface不可供当前Agent使用。", {"surface_id": surface_id, "agent_profile": agent_profile})
	if not bool(surface.call("contains_logical", logical)):
		return _failure("combat.3d.target_point_outside_surface", "TargetPoint3D不在其Surface边界内。", {"surface_id": surface_id})
	var position := PLANAR_POSITION.new(map_id, surface_id, logical.x, logical.y)
	var world: Vector3 = surface.call("logical_to_world", logical)
	var target_world := _world_native(global_position)
	return {
		"ok": true,
		"code": "combat.3d.target_point_captured",
		"target_point": to_native(),
		"target_position": position.to_native(),
		"target_world": target_world,
		"surface_height": float(surface.call("world_height_at", logical)),
		"surface_projection": _world_native(world),
		"height_tolerance": height_tolerance,
		"agent_profile": agent_profile,
	}

func _world_native(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}

func _world_valid(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

func _vector2_valid(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)

func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
