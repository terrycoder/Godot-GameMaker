class_name GMProjectilePresentation3D
extends Node3D

## Presentation-only projectile.  It moves a Node3D and records no rule,
## damage, task, ability or domain state.

const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")
const SCHEMA := "gm.combat.projectile_presentation_3d.v1"

var presentation_id := ""
var idempotency_key := ""
var active := false
var status := "pooled"
var elapsed_seconds := 0.0
var duration_seconds := 0.0
var speed := 0.0
var max_hits := 1
var cancel_reason := ""
var _start_world: Dictionary = {}
var _target_world: Dictionary = {}
var _hit_ids: Dictionary = {}

func launch(p_presentation_id: String, p_idempotency_key: String, p_start_world: Dictionary, p_target_world: Dictionary, p_speed: float, p_max_hits: int = 1) -> Dictionary:
	if active:
		if presentation_id == p_presentation_id and idempotency_key == p_idempotency_key:
			return {"ok": true, "code": "combat.projectile.idempotent_replay", "idempotent": true, "snapshot": snapshot()}
		return _failure("combat.projectile.active_conflict", "ProjectilePresentation3D已有不同活动实例。")
	if not CONTRACT.stable_id(p_presentation_id) or not p_presentation_id.begins_with("gm.projectile.presentation."):
		return _failure("combat.projectile.presentation_id_invalid", "ProjectilePresentation3D身份无效。")
	if not CONTRACT.text(p_idempotency_key):
		return _failure("combat.projectile.idempotency_invalid", "ProjectilePresentation3D幂等键无效。")
	var start_check := _world(p_start_world)
	var target_check := _world(p_target_world)
	if not start_check.ok or not target_check.ok:
		return _failure("combat.projectile.world_invalid", "ProjectilePresentation3D起点和终点必须是有限三维纯值。")
	if typeof(p_speed) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(p_speed)) or float(p_speed) <= 0.0:
		return _failure("combat.projectile.speed_invalid", "ProjectilePresentation3D速度必须是有限正数。")
	if typeof(p_max_hits) != TYPE_INT or p_max_hits <= 0:
		return _failure("combat.projectile.max_hits_invalid", "ProjectilePresentation3D max_hits必须是正整数。")
	presentation_id = p_presentation_id
	idempotency_key = p_idempotency_key
	_start_world = p_start_world.duplicate(true)
	_target_world = p_target_world.duplicate(true)
	speed = float(p_speed)
	max_hits = p_max_hits
	var distance := _vector3(p_start_world).distance_to(_vector3(p_target_world))
	duration_seconds = maxf(distance / speed, 0.01)
	elapsed_seconds = 0.0
	_hit_ids.clear()
	cancel_reason = ""
	active = true
	status = "playing"
	global_position = _vector3(p_start_world)
	return {"ok": true, "code": "combat.projectile.started", "idempotent": false, "snapshot": snapshot()}

func tick(delta_seconds: float) -> Dictionary:
	if not active:
		return _failure("combat.projectile.not_active", "ProjectilePresentation3D当前没有活动实例。", {"status": status})
	if typeof(delta_seconds) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(delta_seconds)) or float(delta_seconds) < 0.0:
		return _failure("combat.projectile.delta_invalid", "ProjectilePresentation3D时间步必须是有限非负数。")
	elapsed_seconds = minf(duration_seconds, elapsed_seconds + float(delta_seconds))
	var progress := clampf(elapsed_seconds / duration_seconds, 0.0, 1.0)
	global_position = _vector3(_start_world).lerp(_vector3(_target_world), progress)
	if is_equal_approx(progress, 1.0):
		active = false
		status = "completed"
	return {"ok": true, "code": "combat.projectile.completed" if not active else "combat.projectile.advanced", "snapshot": snapshot()}

func register_hit(hit_id: String) -> Dictionary:
	if not active:
		return _failure("combat.projectile.not_active", "ProjectilePresentation3D当前没有可登记命中的活动实例。")
	if not CONTRACT.stable_id(hit_id):
		return _failure("combat.projectile.hit_id_invalid", "ProjectilePresentation3D命中ID无效。")
	if _hit_ids.has(hit_id):
		return _failure("combat.projectile.duplicate_hit", "ProjectilePresentation3D拒绝重复命中。", {"hit_id": hit_id})
	if _hit_ids.size() >= max_hits:
		return _failure("combat.projectile.hit_limit", "ProjectilePresentation3D已达到命中次数上限。")
	_hit_ids[hit_id] = true
	return {"ok": true, "code": "combat.projectile.hit_registered", "hit_id": hit_id, "hit_count": _hit_ids.size(), "presentation_only": true}

func cancel(reason_code: String = "presentation.cancelled") -> Dictionary:
	if not active:
		return _failure("combat.projectile.not_active", "ProjectilePresentation3D当前没有活动实例。")
	if not CONTRACT.stable_id(reason_code):
		return _failure("combat.projectile.cancel_reason_invalid", "ProjectilePresentation3D取消原因必须是稳定代码。")
	active = false
	status = "cancelled"
	cancel_reason = reason_code
	return {"ok": true, "code": "combat.projectile.cancelled", "reason_code": reason_code, "snapshot": snapshot(), "domain_facts_written": false}

func release_to_pool() -> Dictionary:
	active = false
	status = "pooled"
	presentation_id = ""
	idempotency_key = ""
	elapsed_seconds = 0.0
	duration_seconds = 0.0
	speed = 0.0
	max_hits = 1
	cancel_reason = ""
	_start_world.clear()
	_target_world.clear()
	_hit_ids.clear()
	return {"ok": true, "code": "combat.projectile.pooled", "snapshot": snapshot(), "domain_facts_written": false}

func snapshot() -> Dictionary:
	var hit_ids: Array = _hit_ids.keys()
	hit_ids.sort()
	return {"schema": SCHEMA, "presentation_id": presentation_id, "idempotency_key": idempotency_key, "active": active, "status": status, "elapsed_seconds": elapsed_seconds, "duration_seconds": duration_seconds, "speed": speed, "max_hits": max_hits, "hit_ids": hit_ids, "position": {"x": global_position.x, "y": global_position.y, "z": global_position.z}, "cancel_reason": cancel_reason, "presentation_only": true, "domain_facts_written": false}

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
