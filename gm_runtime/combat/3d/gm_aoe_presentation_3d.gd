class_name GMAoEPresentation3D
extends Node3D

## Presentation-only Area-of-Effect pulse.  It does not own or apply combat
## rules; P22 remains the only source of hit/damage/effect outcomes.

const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")
const SCHEMA := "gm.combat.aoe_presentation_3d.v1"

var presentation_id := ""
var idempotency_key := ""
var active := false
var status := "pooled"
var elapsed_seconds := 0.0
var duration_seconds := 0.0
var radius := 0.0
var max_hits := 1
var cancel_reason := ""
var _center_world: Dictionary = {}
var _hit_ids: Dictionary = {}

func start(p_presentation_id: String, p_idempotency_key: String, p_center_world: Dictionary, p_radius: float, p_duration_seconds: float = 0.25, p_max_hits: int = 32) -> Dictionary:
	if active:
		if presentation_id == p_presentation_id and idempotency_key == p_idempotency_key:
			return {"ok": true, "code": "combat.aoe.idempotent_replay", "idempotent": true, "snapshot": snapshot()}
		return _failure("combat.aoe.active_conflict", "AoEPresentation3D已有不同活动实例。")
	if not CONTRACT.stable_id(p_presentation_id) or not p_presentation_id.begins_with("gm.aoe.presentation."):
		return _failure("combat.aoe.presentation_id_invalid", "AoEPresentation3D身份无效。")
	if not CONTRACT.text(p_idempotency_key):
		return _failure("combat.aoe.idempotency_invalid", "AoEPresentation3D幂等键无效。")
	if not _world(p_center_world).ok:
		return _failure("combat.aoe.world_invalid", "AoEPresentation3D中心必须是有限三维纯值。")
	if typeof(p_radius) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(p_radius)) or float(p_radius) < 0.0:
		return _failure("combat.aoe.radius_invalid", "AoEPresentation3D半径必须是有限非负数。")
	if typeof(p_duration_seconds) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(p_duration_seconds)) or float(p_duration_seconds) <= 0.0:
		return _failure("combat.aoe.duration_invalid", "AoEPresentation3D时长必须是有限正数。")
	if typeof(p_max_hits) != TYPE_INT or p_max_hits <= 0:
		return _failure("combat.aoe.max_hits_invalid", "AoEPresentation3D max_hits必须是正整数。")
	presentation_id = p_presentation_id
	idempotency_key = p_idempotency_key
	_center_world = p_center_world.duplicate(true)
	radius = float(p_radius)
	duration_seconds = float(p_duration_seconds)
	max_hits = p_max_hits
	elapsed_seconds = 0.0
	_hit_ids.clear()
	cancel_reason = ""
	active = true
	status = "playing"
	global_position = _vector3(p_center_world)
	return {"ok": true, "code": "combat.aoe.started", "idempotent": false, "snapshot": snapshot()}

func tick(delta_seconds: float) -> Dictionary:
	if not active:
		return _failure("combat.aoe.not_active", "AoEPresentation3D当前没有活动实例。")
	if typeof(delta_seconds) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(delta_seconds)) or float(delta_seconds) < 0.0:
		return _failure("combat.aoe.delta_invalid", "AoEPresentation3D时间步必须是有限非负数。")
	elapsed_seconds = minf(duration_seconds, elapsed_seconds + float(delta_seconds))
	if is_equal_approx(elapsed_seconds, duration_seconds):
		active = false
		status = "completed"
	return {"ok": true, "code": "combat.aoe.completed" if not active else "combat.aoe.advanced", "snapshot": snapshot()}

func register_hit(hit_id: String) -> Dictionary:
	if not active:
		return _failure("combat.aoe.not_active", "AoEPresentation3D当前没有活动实例。")
	if not CONTRACT.stable_id(hit_id):
		return _failure("combat.aoe.hit_id_invalid", "AoEPresentation3D命中ID无效。")
	if _hit_ids.has(hit_id):
		return _failure("combat.aoe.duplicate_hit", "AoEPresentation3D拒绝重复命中。", {"hit_id": hit_id})
	if _hit_ids.size() >= max_hits:
		return _failure("combat.aoe.hit_limit", "AoEPresentation3D已达到命中次数上限。")
	_hit_ids[hit_id] = true
	return {"ok": true, "code": "combat.aoe.hit_registered", "hit_id": hit_id, "hit_count": _hit_ids.size(), "presentation_only": true}

func cancel(reason_code: String = "presentation.cancelled") -> Dictionary:
	if not active:
		return _failure("combat.aoe.not_active", "AoEPresentation3D当前没有活动实例。")
	if not CONTRACT.stable_id(reason_code):
		return _failure("combat.aoe.cancel_reason_invalid", "AoEPresentation3D取消原因必须是稳定代码。")
	active = false
	status = "cancelled"
	cancel_reason = reason_code
	return {"ok": true, "code": "combat.aoe.cancelled", "reason_code": reason_code, "snapshot": snapshot(), "domain_facts_written": false}

func release_to_pool() -> Dictionary:
	active = false
	status = "pooled"
	presentation_id = ""
	idempotency_key = ""
	elapsed_seconds = 0.0
	duration_seconds = 0.0
	radius = 0.0
	max_hits = 1
	cancel_reason = ""
	_center_world.clear()
	_hit_ids.clear()
	return {"ok": true, "code": "combat.aoe.pooled", "snapshot": snapshot(), "domain_facts_written": false}

func snapshot() -> Dictionary:
	var hit_ids: Array = _hit_ids.keys()
	hit_ids.sort()
	return {"schema": SCHEMA, "presentation_id": presentation_id, "idempotency_key": idempotency_key, "active": active, "status": status, "elapsed_seconds": elapsed_seconds, "duration_seconds": duration_seconds, "radius": radius, "max_hits": max_hits, "hit_ids": hit_ids, "position": {"x": global_position.x, "y": global_position.y, "z": global_position.z}, "cancel_reason": cancel_reason, "presentation_only": true, "domain_facts_written": false}

func _world(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.has("x") or not value.has("y") or not value.has("z"):
		return {"ok": false}
	for key in ["x", "y", "z"]:
		if typeof(value.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value.get(key))):
			return {"ok": false}
	return {"ok": true}

func _vector3(value: Dictionary) -> Vector3:
	return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))

func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh, "presentation_only": true, "domain_facts_written": false}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
