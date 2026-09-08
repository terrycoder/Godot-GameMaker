class_name GMMovementExecutor3D
extends RefCounted

## Planar 3D backend for the existing P15 movement AbilityTask.  It owns only
## runtime command projections; requests, targets, routes and snapshots remain
## the existing stable-value contracts.

const SERVICE_ID := "gm.movement.executor"
const SNAPSHOT_SCHEMA := "gm.movement.3d.snapshot.v1"
const SNAPSHOT_VERSION := 1
const SNAPSHOT_FIELDS := ["schema_version", "schema", "actor_id", "map_id", "position", "facing", "active", "command"]
const SNAPSHOT_POSITION_FIELDS := ["schema_version", "map_id", "surface_id", "x", "y"]
const SNAPSHOT_FACING_FIELDS := ["x", "y"]
const SNAPSHOT_COMMAND_FIELDS := ["command_id", "actor_id", "owner_id", "source", "request", "phase", "target", "target_fact", "path_points", "path_index", "route_points", "route_index", "patrol_stage", "wait_remaining", "terminal"]
const SNAPSHOT_REQUEST_FIELDS := ["schema", "kind", "source", "owner_id", "actor_id", "map_id", "anchor_id", "target_actor_id", "route_id", "direction", "target_position", "speed", "acceleration", "stop_distance", "follow_distance", "loop", "entry_anchor_id", "exit_anchor_id", "return_anchor_id", "target_map_id", "idempotency_key"]
const SNAPSHOT_TARGET_FACT_FIELDS := ["schema", "kind", "target_actor_id", "anchor_id", "route_id", "resolved_position", "route_index", "target_phase"]
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const TARGET_REF := preload("res://gm_runtime/spatial_core/gm_spatial_target_ref.gd")
const SPATIAL_DOMAIN := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")
const SPATIAL_CAPABILITIES := preload("res://gm_runtime/spatial_core/gm_spatial_backend_capabilities.gd")

var spatial_adapter: Object
var runtime_context: Object
var _actors: Dictionary = {}
var _active_by_actor: Dictionary = {}
var _commands: Dictionary = {}
var _sequence: int = 0

var actors: Dictionary:
	get: return _actor_observations()
var active_by_actor: Dictionary:
	get: return _active_by_actor.duplicate(true)
var commands: Dictionary:
	get: return _command_observations()
var sequence: int:
	get: return _sequence

func _init(p_adapter: Object = null, p_context: Object = null) -> void:
	spatial_adapter = p_adapter
	runtime_context = p_context

func install_on_host(host: GMAbilitySystemHost) -> Dictionary:
	if host == null or not is_instance_valid(host):
		return _fail("movement.3d.host_missing", "Planar 3D移动执行器缺少AbilityHost。", "请先挂载现有GMAbilitySystemHost。")
	return host.set_domain_service(SERVICE_ID, self)

func register_actor(actor_id: String, actor: Object, map_id: String = "", position_value: Variant = null) -> Dictionary:
	if not _stable_id(actor_id) or actor == null or not is_instance_valid(actor):
		return _fail("movement.3d.actor_registration_invalid", "3D角色注册缺少稳定ID或有效运行时对象。", "请先完成Planar 3D角色装配。")
	var resolved_map := map_id.strip_edges()
	if resolved_map.is_empty():
		resolved_map = str(_read_property(actor, "map_id", ""))
	if resolved_map.is_empty():
		return _fail("movement.3d.map_missing", "3D角色注册缺少稳定地图ID。", "请先绑定SemanticMap地图ID。")
	var position_result := _resolve_actor_position(actor, resolved_map, position_value)
	if not position_result.ok:
		return position_result
	var position = position_result.position
	var valid := _validate_position(position)
	if not valid.ok:
		return valid
	_actors[actor_id] = {"actor": actor, "map_id": resolved_map, "position": position.duplicate_position()}
	_apply_position_to_actor(actor, position)
	return {"ok": true, "actor_id": actor_id, "map_id": resolved_map, "position": position.to_native()}

func unregister_actor(actor_id: String) -> void:
	var command_id := str(_active_by_actor.get(actor_id, ""))
	if not command_id.is_empty() and _commands.has(command_id):
		var state: Dictionary = _commands[command_id]
		state["terminal"] = true
		state["result"] = _fail("movement.3d.actor_unregistered", "3D角色已卸载，移动命令安全终止。", "请重新装配角色后提交移动请求。")
		_commands[command_id] = state
	_active_by_actor.erase(actor_id)
	_actors.erase(actor_id)

func preflight(request: GMMovementRequest, actor: Object) -> Dictionary:
	if request == null:
		return _fail("movement.request_missing", "移动执行器没有收到请求。", "请重新提交ActivationRequest。")
	var checked := request.validate()
	if not checked.ok:
		return checked
	if actor == null or not is_instance_valid(actor):
		return _fail("movement.actor_released", "移动角色已释放。", "请重新加载角色。")
	if not _actors.has(request.actor_id):
		return _fail("movement.3d.actor_unregistered", "Planar 3D角色尚未注册到统一移动执行器。", "请先注册角色运行时投影。")
	var record: Dictionary = _actors[request.actor_id]
	if record.get("actor", null) != actor:
		return _fail("movement.actor_identity_mismatch", "移动请求与已注册3D角色身份不一致。", "请选择与请求匹配的角色。")
	if str(record.get("map_id", "")) != request.map_id:
		return _fail("movement.map_mismatch", "角色当前地图与移动请求地图不一致。", "请在正确地图重新提交请求。")
	var actor_position := _current_actor_position(request.actor_id)
	if not actor_position.ok:
		return actor_position
	var actor_valid := _validate_position(actor_position.position)
	if not actor_valid.ok:
		return actor_valid
	match request.kind:
		"anchor", "follow", "patrol", "direct":
			var target_result := _resolve_request_target(request, actor_position.position)
			if not target_result.ok:
				return target_result
			if request.kind != "follow":
				var target_valid := _validate_position(target_result.position) if target_result.get("position", null) != null else {"ok": true}
				if not target_valid.ok:
					return target_valid
			if request.kind in ["anchor", "direct"]:
				var path := _request_path(actor_position.position, target_result.position)
				if not path.ok:
					return path
		"direction":
			if request.direction.length_squared() <= 0.000001:
				return _fail("movement.direction_missing", "方向移动缺少有效方向。", "请输入非零方向。")
			var direction_valid := _finite_vector(request.direction)
			if not direction_valid:
				return _fail("movement.vector_nonfinite", "移动方向包含非有限分量。", "请提供有限方向。")
		"face":
			if not _finite_vector(request.direction):
				return _fail("movement.vector_nonfinite", "朝向包含非有限分量。", "请提供有限方向。")
		"cancel":
			pass
		"travel":
			return _fail("movement.3d.travel_deferred", "Planar 3D旅行交接需要P23旅行域，当前请求被安全延后。", "请使用已配置的旅行交接域。")
	return {"ok": true}

func start_request(request: GMMovementRequest, actor: Object) -> Dictionary:
	var checked := preflight(request, actor)
	if not checked.ok:
		return checked
	var frozen_result := GMMovementRequest.from_dict(request.to_dict())
	if not frozen_result.ok:
		return frozen_result
	var frozen: GMMovementRequest = frozen_result.request
	var existing_id := str(_active_by_actor.get(frozen.actor_id, ""))
	if frozen.kind == "cancel":
		return cancel_owner(frozen.actor_id, frozen.owner_id, "移动请求已由统一入口取消。")
	if not existing_id.is_empty() and _commands.has(existing_id):
		var existing: Dictionary = _commands[existing_id]
		if str(existing.get("fingerprint", "")) == frozen.fingerprint():
			return {"ok": true, "pending": true, "idempotent": true, "command_id": existing_id, "phase": str(existing.get("phase", "running"))}
		if str(existing.get("owner_id", "")) != frozen.owner_id:
			return _fail("movement.owner_conflict", "角色已有其他owner的3D移动执行。", "请由当前owner取消后再提交。")
		return _fail("movement.target_replace_conflict", "同一owner不能静默替换正在执行的3D移动目标。", "请先取消原移动，再提交新目标。")
	_sequence += 1
	var command_id := "gm.movement.3d.command.%06d" % _sequence
	var current_result := _current_actor_position(frozen.actor_id)
	if not current_result.ok:
		return current_result
	var current = current_result.position
	var facing := _current_facing(actor)
	var state := {
		"command_id": command_id,
		"actor_id": frozen.actor_id,
		"owner_id": frozen.owner_id,
		"source": frozen.source,
		"request": frozen,
		"fingerprint": frozen.fingerprint(),
		"actor": actor,
		"position": current.duplicate_position(),
		"velocity": Vector2.ZERO,
		"facing": facing,
		"phase": "starting",
		"target": null,
		"target_fact": {},
		"path_points": [],
		"path_index": 1,
		"route_points": [],
		"route_index": 0,
		"patrol_stage": "",
		"wait_remaining": 0.0,
		"terminal": false,
		"result": {},
	}
	if frozen.kind == "face":
		var face := _safe_normalized(frozen.direction)
		_apply_actor_motion(actor, current, Vector2.ZERO, face)
		return {"ok": true, "completed": true, "command_id": command_id, "phase": "faced", "position": current.to_native(), "facing": _vector2_native(face)}
	if frozen.kind == "direction":
		state["phase"] = "direction"
	else:
		var target_result := _resolve_request_target(frozen, current)
		if not target_result.ok:
			return target_result
		if frozen.kind == "patrol":
			state["route_points"] = target_result.route_points
			state["target"] = target_result.route_points[0].duplicate_position()
			state["phase"] = "patrolling"
			state["patrol_stage"] = "moving"
		else:
			state["target"] = target_result.position.duplicate_position()
			state["phase"] = "following" if frozen.kind == "follow" else "moving"
		var path_result := _set_path(state, current, state.get("target", null))
		if not path_result.ok:
			return path_result
	state["target_fact"] = _make_target_fact(frozen, state)
	_commands[command_id] = state
	_active_by_actor[frozen.actor_id] = command_id
	return {"ok": true, "pending": true, "command_id": command_id, "phase": state.phase, "position": current.to_native()}

func tick_command(command_id: String, delta: float) -> Dictionary:
	if not _commands.has(command_id):
		return _fail("movement.command_missing", "3D移动命令不存在或已结束。", "请重新提交移动请求。")
	var stored: Dictionary = _commands[command_id]
	if bool(stored.get("terminal", false)):
		return stored.get("result", _fail("movement.3d.command_terminal", "3D移动命令已经结束。", "请重新提交移动请求。"))
	if not is_finite(delta) or delta < 0.0:
		return _fail("movement.delta_invalid", "移动帧间隔必须是0或正的有限数值。", "请检查调用方时钟后重试。")
	var state: Dictionary = stored.duplicate(false)
	state["path_points"] = stored.get("path_points", []).duplicate()
	state["route_points"] = stored.get("route_points", []).duplicate()
	state["target_fact"] = stored.get("target_fact", {}).duplicate(true)
	var request: GMMovementRequest = state.get("request", null)
	if request == null:
		return _fail("movement.command_request_invalid", "活动3D移动命令缺少有效请求。", "请丢弃损坏命令并重新提交。")
	var actor: Object = state.get("actor", null)
	if actor == null or not is_instance_valid(actor):
		return _finish_failure(state, "movement.actor_released", "移动角色已释放。", "请重新加载角色。")
	var current_result := _current_actor_position(request.actor_id)
	if not current_result.ok:
		return _finish_failure(state, str(current_result.get("code", "movement.3d.position_missing")), str(current_result.get("reason_zh", "3D角色位置无效。")), "请恢复有效PlanarPosition后重试。")
	var current = current_result.position
	state["position"] = current
	if request.kind == "direction":
		return _tick_direction(state, request, actor, delta)
	if request.kind == "follow":
		var follow_target := _resolve_follow_target(request)
		if not follow_target.ok:
			return _finish_failure(state, str(follow_target.get("code", "movement.target_lost")), str(follow_target.get("reason_zh", "跟随目标已失效。")), "请取消跟随或选择新的有效目标。")
		var target_position = follow_target.position
		state["target"] = target_position
		state["target_fact"] = _make_target_fact(request, state)
		var follow_distance := _distance_between(current, target_position)
		if follow_distance.ok and follow_distance.value <= request.follow_distance:
			_apply_actor_motion(actor, current, Vector2.ZERO, state.facing)
			state["velocity"] = Vector2.ZERO
			_commands[command_id] = state
			return _pending(state)
		var follow_path := _set_path(state, current, target_position)
		if not follow_path.ok:
			return _finish_failure(state, "movement.unreachable", "跟随目标当前不可达。", "请确认目标仍在可通行Surface上。")
	var advanced := _advance_path(state, actor, delta, request.speed, request.stop_distance if request.kind != "follow" else request.follow_distance)
	if not advanced.ok:
		return advanced
	if bool(advanced.get("arrived", false)):
		if request.kind == "patrol":
			return _handle_patrol_arrival(state, actor, request, delta)
		if request.kind == "follow":
			state["velocity"] = Vector2.ZERO
			_commands[command_id] = state
			return _pending(state)
		return _finish_success(state, "arrived", {"position": state.position.to_native(), "surface_id": state.position.surface_id})
	_commands[command_id] = state
	return _pending(state)

func cancel_move(command_id: String, reason_zh: String = "移动已取消。") -> Dictionary:
	if not _commands.has(command_id):
		return {"ok": true, "completed": true, "idempotent": true, "code": "movement.already_cancelled"}
	var state: Dictionary = _commands[command_id]
	return cancel_owner(str(state.get("actor_id", "")), str(state.get("owner_id", "")), reason_zh)

func cancel_owner(actor_id: String, owner_id: String, reason_zh: String = "移动已取消。") -> Dictionary:
	var command_id := str(_active_by_actor.get(actor_id, ""))
	if command_id.is_empty() or not _commands.has(command_id):
		return {"ok": true, "completed": true, "idempotent": true, "code": "movement.already_cancelled", "reason_zh": "角色当前没有3D移动执行。"}
	var state: Dictionary = _commands[command_id]
	if str(state.get("owner_id", "")) != owner_id:
		return _fail("movement.cancel_not_owner", "取消请求与当前移动owner不一致。", "请由当前owner发起取消。")
	var actor: Object = state.get("actor", null)
	var position = state.get("position", null)
	if actor != null and is_instance_valid(actor) and position != null:
		_apply_actor_motion(actor, position, Vector2.ZERO, state.get("facing", Vector2.DOWN))
	state["velocity"] = Vector2.ZERO
	return _finish_success(state, "cancelled", {"cancelled": true, "reason_zh": reason_zh})

func snapshot_actor(actor_id: String) -> Dictionary:
	if not _actors.has(actor_id):
		return _snapshot_failure("movement.3d.actor_missing", "找不到要快照的Planar 3D角色。")
	var record: Dictionary = _actors[actor_id]
	var current := _current_actor_position(actor_id)
	if not current.ok:
		return _snapshot_failure(str(current.get("code", "movement.3d.position_missing")), str(current.get("reason_zh", "角色空间位置无效。")))
	var active_id := str(_active_by_actor.get(actor_id, ""))
	var command := _command_snapshot(_commands.get(active_id, {})) if not active_id.is_empty() and _commands.has(active_id) else {}
	return {
		"schema_version": SNAPSHOT_VERSION,
		"schema": SNAPSHOT_SCHEMA,
		"actor_id": actor_id,
		"map_id": str(record.get("map_id", current.position.map_id)),
		"position": current.position.to_native(),
		"facing": _vector2_native(_current_facing(record.get("actor", null))),
		"active": not active_id.is_empty() and not command.is_empty() and not bool(command.get("terminal", false)),
		"command": command,
	}

func restore_actor(snapshot: Variant) -> Dictionary:
	var check := _validate_snapshot(snapshot)
	if not check.ok:
		return check
	var value: Dictionary = snapshot
	var actor_id := str(value.actor_id)
	if not _actors.has(actor_id):
		return _snapshot_failure("movement.3d.actor_missing", "恢复快照找不到对应Planar 3D角色。")
	var record: Dictionary = _actors[actor_id]
	var actor: Object = record.get("actor", null)
	if actor == null or not is_instance_valid(actor):
		return _snapshot_failure("movement.actor_released", "恢复快照对应的3D角色已释放。")
	var live_actor_id: Variant = _read_property(actor, "stable_instance_id", null)
	if not _stable_string_id(live_actor_id) or str(live_actor_id) != actor_id:
		return _snapshot_failure("movement.actor_identity_mismatch", "恢复快照角色身份与已注册稳定身份不一致。")
	var live_map_id: Variant = _read_property(actor, "map_id", null)
	if not _stable_string_id(live_map_id) or str(live_map_id) != str(value.map_id):
		return _snapshot_failure("movement.map_identity_mismatch", "恢复快照地图身份与已注册角色不一致。")
	if str(record.get("map_id", "")) != str(value.map_id):
		return _snapshot_failure("movement.map_mismatch", "恢复快照地图与当前3D角色不一致。")
	var parsed := PLANAR_POSITION.from_native(value.position)
	if not parsed.ok:
		return _snapshot_failure("movement.3d.snapshot_position_invalid", "恢复快照的PlanarPosition无效。")
	var position: GMPlanarPosition = parsed.position
	if position.map_id != str(value.map_id):
		return _snapshot_failure("movement.snapshot_position_map_mismatch", "恢复快照位置地图与快照身份不一致。")
	var position_check := _validate_position(position)
	if not position_check.ok:
		return position_check
	var facing_result := _parse_facing(value.facing)
	if not facing_result.ok:
		return facing_result
	var active := bool(value.active)
	var command_value: Dictionary = value.command
	var restored_command: Dictionary = {}
	if active:
		var command_check := _prepare_restored_command(command_value, actor, position)
		if not command_check.ok:
			return command_check
		restored_command = command_check.state
	# All validation above is complete; the following is the atomic apply edge.
	var old_command_id := str(_active_by_actor.get(actor_id, ""))
	if not old_command_id.is_empty():
		_commands.erase(old_command_id)
	_active_by_actor.erase(actor_id)
	_apply_actor_motion(actor, position, Vector2.ZERO, facing_result.value)
	record["position"] = position.duplicate_position()
	_actors[actor_id] = record
	if active:
		var restored_id := str(restored_command.command_id)
		_commands[restored_id] = restored_command
		_active_by_actor[actor_id] = restored_id
	return {"ok": true, "atomic": true, "actor_id": actor_id, "active": active, "cleared_command_id": old_command_id}

func restore_actor_from_json(snapshot: Variant) -> Dictionary:
	if not snapshot is Dictionary:
		if snapshot is String:
			var parsed = JSON.parse_string(snapshot)
			if parsed is Dictionary:
				return restore_actor(parsed)
		return _snapshot_failure("movement.3d.snapshot_json_invalid", "Planar 3D移动快照JSON无效。")
	return restore_actor(snapshot)

func _resolve_request_target(request: GMMovementRequest, from_position) -> Dictionary:
	match request.kind:
		"direct":
			var direct := PLANAR_POSITION.new(request.map_id, from_position.surface_id, request.target_position.x, request.target_position.y)
			return {"ok": true, "position": direct}
		"anchor":
			return _resolve_semantic_target("anchor", request.map_id, request.anchor_id)
		"follow":
			return _resolve_follow_target(request)
		"patrol":
			var route := _resolve_semantic_target("route", request.map_id, request.route_id)
			if not route.ok:
				return route
			var points: Array = []
			for raw in route.value.get("logical_points", []):
				var point := PLANAR_POSITION.from_native(raw)
				if not point.ok:
					return _fail("movement.3d.route_point_invalid", "巡逻路线包含无效PlanarPosition。", "请修正路线的Surface与逻辑坐标。")
				points.append(point.position)
			if points.size() < 2:
				return _fail("movement.path_empty", "巡逻路线至少需要两个有效点。", "请在SemanticMap中补全巡逻路线。")
			return {"ok": true, "route_points": points, "value": route.value}
	return {"ok": true, "position": from_position}

func _resolve_semantic_target(kind: String, map_id: String, semantic_id: String) -> Dictionary:
	var native := {"schema_version": 1, "domain_id": SPATIAL_DOMAIN.PLANAR_3D, "kind": kind, "semantic_id": semantic_id, "map_id": map_id}
	var parsed := TARGET_REF.from_native(native)
	if not parsed.ok:
		return _fail("movement.3d.target_invalid", "3D语义移动目标无效。", "请重新选择稳定锚点或路线。")
	var query := _adapter_call("resolve_target", [parsed.target])
	if not query.ok:
		return _fail(str(query.get("code", "movement.target_missing")), str(query.get("error_zh", query.get("reason_zh", "3D语义目标解析失败。"))), "请修正SemanticMap目标或Surface关系。", query)
	return {"ok": true, "position": _position_from_query(query), "value": query.value} if kind == "anchor" else {"ok": true, "value": query.value}

func _resolve_follow_target(request: GMMovementRequest) -> Dictionary:
	if not _actors.has(request.target_actor_id):
		return _fail("movement.target_lost", "跟随目标不存在或已离场。", "请选择仍在当前地图中的目标角色。")
	var target_record: Dictionary = _actors[request.target_actor_id]
	if str(target_record.get("map_id", "")) != request.map_id:
		return _fail("movement.map_mismatch", "跟随目标位于不同地图。", "请等待目标回到同一地图或取消跟随。")
	var target := _current_actor_position(request.target_actor_id)
	if not target.ok:
		return target
	return {"ok": true, "position": target.position}

func _set_path(state: Dictionary, from_position, to_position) -> Dictionary:
	if to_position == null:
		return {"ok": true}
	var path := _request_path(from_position, to_position)
	if not path.ok:
		return path
	var points: Array = []
	for raw in path.value.get("logical_points", []):
		var parsed := PLANAR_POSITION.from_native(raw)
		if not parsed.ok:
			return _fail("movement.3d.path_point_invalid", "3D路径包含无效PlanarPosition。", "请修正Surface Graph路径数据。")
		points.append(parsed.position)
	if points.is_empty():
		points.append(from_position.duplicate_position())
		points.append(to_position.duplicate_position())
	state["path_points"] = points
	state["path_index"] = 1
	state["target"] = to_position.duplicate_position()
	return {"ok": true, "path": path.value, "point_count": points.size()}

func _request_path(from_position, to_position) -> Dictionary:
	return _adapter_call("request_path", [from_position, to_position])

func _advance_path(state: Dictionary, actor: Object, delta: float, speed: float, stop_distance: float) -> Dictionary:
	var points: Array = state.get("path_points", [])
	var current = state.get("position", null)
	if current == null:
		return _fail("movement.3d.position_missing", "3D移动命令缺少当前PlanarPosition。", "请重新注册角色。")
	var remaining := speed * delta
	if not is_finite(remaining):
		return _fail("movement.calculation_overflow", "3D移动步进超出有限范围。", "请降低速度或拆分极端时间跨度。")
	var arrived := false
	while state.path_index < points.size():
		var next = points[state.path_index]
		var segment := _distance_between(current, next)
		if not segment.ok:
			return _fail("movement.3d.path_segment_invalid", "3D路径段无法计算稳定距离。", "请修正Surface Graph连接端点。")
		var distance: float = segment.value
		if distance <= maxf(stop_distance, 0.0001):
			current = next.duplicate_position()
			state.path_index = int(state.path_index) + 1
			continue
		if current.surface_id != next.surface_id:
			# A Surface Connection is the only legal cross-Surface handoff.  The
			# backend supplied this point, so no arbitrary world-space flight is used.
			current = next.duplicate_position()
			state.path_index = int(state.path_index) + 1
			_apply_actor_motion(actor, current, Vector2.ZERO, state.facing)
			continue
		if remaining <= 0.0:
			break
		if distance <= remaining:
			remaining -= distance
			current = next.duplicate_position()
			state.path_index = int(state.path_index) + 1
		else:
			var ratio := remaining / distance
			var point := Vector2(current.x, current.y).lerp(Vector2(next.x, next.y), ratio)
			var direction := _safe_normalized(Vector2(next.x - current.x, next.y - current.y))
			current = PLANAR_POSITION.new(current.map_id, current.surface_id, point.x, point.y)
			state["facing"] = direction
			remaining = 0.0
			break
		state["facing"] = _safe_normalized(Vector2(next.x - current.x, next.y - current.y)) if current.surface_id == next.surface_id else state.facing
	state["position"] = current
	var motion := Vector2.ZERO if delta <= 0.0 else Vector2(state.facing.x, state.facing.y) * speed
	state["velocity"] = motion
	_apply_actor_motion(actor, current, motion, state.facing)
	if state.path_index >= points.size():
		arrived = true
	return {"ok": true, "arrived": arrived, "position": current.to_native()}

func _tick_direction(state: Dictionary, request: GMMovementRequest, actor: Object, delta: float) -> Dictionary:
	var current = state.position
	var facing := _safe_normalized(request.direction)
	var next_point := Vector2(current.x, current.y) + facing * request.speed * delta
	var next := PLANAR_POSITION.new(current.map_id, current.surface_id, next_point.x, next_point.y)
	var valid := _validate_position(next)
	if not valid.ok:
		return _finish_failure(state, "movement.position_blocked", "方向移动到达当前Surface边界或障碍。", "请停止方向输入或切换到合法Surface。")
	state["position"] = next
	state["facing"] = facing
	state["velocity"] = facing * request.speed
	_apply_actor_motion(actor, next, state.velocity, facing)
	_commands[state.command_id] = state
	return _pending(state)

func _handle_patrol_arrival(state: Dictionary, actor: Object, request: GMMovementRequest, delta: float) -> Dictionary:
	var point = state.route_points[state.route_index]
	_apply_actor_motion(actor, state.position, Vector2.ZERO, state.facing)
	state["velocity"] = Vector2.ZERO
	if state.patrol_stage == "moving":
		state.wait_remaining = maxf(0.0, float(point.get("wait", 0.0)) if point is Dictionary else 0.0)
		state.patrol_stage = "waiting" if state.wait_remaining > 0.0 else "moving"
	if state.wait_remaining > 0.0:
		state.wait_remaining = maxf(0.0, state.wait_remaining - delta)
		state.target_fact = _make_target_fact(request, state)
		if state.wait_remaining > 0.0:
			_commands[state.command_id] = state
			return _pending(state)
	state.route_index = int(state.route_index) + 1
	if state.route_index >= state.route_points.size():
		if request.loop:
			state.route_index = 0
		else:
			return _finish_success(state, "arrived", {"route_id": request.route_id})
	state.patrol_stage = "moving"
	state.wait_remaining = 0.0
	state.target = state.route_points[state.route_index].duplicate_position()
	var path := _set_path(state, state.position, state.target)
	if not path.ok:
		return _finish_failure(state, "movement.unreachable", "巡逻下一点当前不可达。", "请修正路线或Surface连接。")
	state.target_fact = _make_target_fact(request, state)
	_commands[state.command_id] = state
	return _pending(state)

func _finish_success(state: Dictionary, phase: String, details: Dictionary = {}) -> Dictionary:
	state["phase"] = phase
	state["terminal"] = true
	state["velocity"] = Vector2.ZERO
	var result := {"ok": true, "completed": true, "pending": false, "command_id": str(state.command_id), "phase": phase, "actor_id": str(state.actor_id), "position": state.position.to_native() if state.position != null else {}, "facing": _vector2_native(state.facing), "details": details.duplicate(true)}
	state["result"] = result.duplicate(true)
	_commands[str(state.command_id)] = state
	_active_by_actor.erase(str(state.actor_id))
	return result

func _finish_failure(state: Dictionary, code: String, reason_zh: String, fix_zh: String) -> Dictionary:
	state["terminal"] = true
	state["phase"] = "failed"
	var result := {"ok": false, "completed": true, "pending": false, "command_id": str(state.command_id), "phase": "failed", "actor_id": str(state.actor_id), "code": code, "reason_zh": reason_zh, "fix_zh": fix_zh, "position": state.position.to_native() if state.get("position", null) != null else {}}
	state["result"] = result.duplicate(true)
	_commands[str(state.command_id)] = state
	_active_by_actor.erase(str(state.actor_id))
	return result

func _pending(state: Dictionary) -> Dictionary:
	return {"ok": true, "pending": true, "completed": false, "command_id": str(state.command_id), "phase": str(state.get("phase", "running")), "actor_id": str(state.get("actor_id", "")), "owner_id": str(state.get("owner_id", "")), "position": state.position.to_native() if state.get("position", null) != null else {}, "facing": _vector2_native(state.get("facing", Vector2.DOWN)), "path_index": int(state.get("path_index", 0)), "route_index": int(state.get("route_index", 0)), "patrol_stage": str(state.get("patrol_stage", "")), "wait_remaining": float(state.get("wait_remaining", 0.0))}

func _make_target_fact(request: GMMovementRequest, state: Dictionary) -> Dictionary:
	var target = state.get("target", null)
	return {"schema": "gm.movement.3d.target_fact.v1", "kind": request.kind, "target_actor_id": request.target_actor_id, "anchor_id": request.anchor_id, "route_id": request.route_id, "resolved_position": target.to_native() if target != null else {}, "route_index": int(state.get("route_index", 0)), "target_phase": str(state.get("patrol_stage", "moving"))}

func _resolve_actor_position(actor: Object, map_id: String, explicit: Variant) -> Dictionary:
	var candidate: Variant = explicit
	if candidate == null or (candidate is Dictionary and candidate.is_empty()):
		candidate = _read_property(actor, "spatial_position", null)
	if candidate == null or (candidate is Dictionary and candidate.is_empty()):
		candidate = _read_property(actor, "planar_position", null)
	if candidate == null or (candidate is Dictionary and candidate.is_empty()):
		candidate = actor.get_meta("gm_spatial_position", null) if actor is Node and actor.has_meta("gm_spatial_position") else null
	if candidate == null or (candidate is Dictionary and candidate.is_empty()):
		if actor is Node3D and spatial_adapter != null:
			var world := (actor as Node3D).global_position
			var projected := _adapter_call("world_to_logical", [world, {"map_id": map_id}])
			if projected.ok:
				candidate = projected.value.get("planar_position", null)
	if candidate == null:
		return _fail("movement.3d.position_missing", "3D角色缺少可解析的PlanarPosition。", "请配置map_id、surface_id与逻辑x/y。")
	var parsed := PLANAR_POSITION.from_native(candidate)
	if not parsed.ok:
		return _fail("movement.3d.position_invalid", "3D角色的PlanarPosition无效。", "请修正保存位置或角色装配。", parsed)
	if parsed.position.map_id != map_id:
		return _fail("movement.map_mismatch", "角色PlanarPosition地图与注册地图不一致。", "请统一地图稳定ID。")
	return {"ok": true, "position": parsed.position}

func _current_actor_position(actor_id: String) -> Dictionary:
	if not _actors.has(actor_id):
		return _fail("movement.3d.actor_missing", "Planar 3D角色未注册。", "请先注册角色。")
	var record: Dictionary = _actors[actor_id]
	var resolved := _resolve_actor_position(record.get("actor", null), str(record.get("map_id", "")), null)
	if resolved.ok:
		record["position"] = resolved.position.duplicate_position()
		_actors[actor_id] = record
	return resolved

func _apply_position_to_actor(actor: Object, position) -> Dictionary:
	var world_result := _adapter_call("logical_to_world", [position])
	if not world_result.ok:
		return world_result
	var world_native: Dictionary = world_result.value.get("world_position", {})
	if actor.has_method("apply_planar_position"):
		return actor.call("apply_planar_position", position.to_native(), world_native)
	if "spatial_position" in actor: actor.set("spatial_position", position.to_native())
	if "map_id" in actor: actor.set("map_id", position.map_id)
	if actor is Node3D:
		(actor as Node3D).global_position = Vector3(float(world_native.get("x", 0.0)), float(world_native.get("y", 0.0)), float(world_native.get("z", 0.0)))
	return {"ok": true, "position": position.to_native()}

func _apply_actor_motion(actor: Object, position, velocity: Vector2, facing: Vector2) -> void:
	_apply_position_to_actor(actor, position)
	if actor.has_method("set_movement_state"):
		actor.call("set_movement_state", velocity, facing)
	else:
		if "movement_velocity" in actor: actor.set("movement_velocity", velocity)
		if "movement_facing" in actor: actor.set("movement_facing", facing.normalized() if facing.length_squared() > 0.000001 else Vector2.DOWN)

func _validate_position(position) -> Dictionary:
	if position == null:
		return _fail("movement.3d.position_missing", "3D移动位置为空。", "请配置有效PlanarPosition。")
	var parsed := PLANAR_POSITION.from_native(position)
	if not parsed.ok:
		return _fail("movement.3d.position_invalid", "3D移动位置不是有效PlanarPosition。", "请修正map、surface与有限坐标。")
	return _adapter_call("validate_walkable_position", [parsed.position])

func _distance_between(left, right) -> Dictionary:
	var result := _adapter_call("get_planar_distance", [left, right])
	if result.ok:
		return {"ok": true, "value": float(result.value.get("distance", 0.0))}
	if left.map_id == right.map_id and left.surface_id == right.surface_id:
		return {"ok": true, "value": Vector2(left.x - right.x, left.y - right.y).length()}
	return result

func _position_from_query(query: Dictionary):
	var raw = query.value.get("planar_position", null)
	var parsed := PLANAR_POSITION.from_native(raw)
	return parsed.position if parsed.ok else null

func _adapter_call(method_name: String, arguments: Array = []) -> Dictionary:
	var result: Variant = null
	if spatial_adapter != null and is_instance_valid(spatial_adapter) and spatial_adapter.has_method(method_name):
		result = spatial_adapter.callv(method_name, arguments)
	elif runtime_context != null and is_instance_valid(runtime_context) and runtime_context.has_method("query_spatial"):
		var capability := _capability_for_method(method_name)
		result = runtime_context.call("query_spatial", capability, method_name, arguments)
	if not result is Dictionary:
		return _fail("movement.3d.adapter_interface_missing", "Planar 3D空间适配器没有返回结构化结果。", "请检查现有GMRuntimeContext与Manifest后端。")
	return result

func _capability_for_method(method_name: String) -> String:
	var mapping := {"logical_to_world": SPATIAL_CAPABILITIES.LOGICAL_TO_WORLD, "world_to_logical": SPATIAL_CAPABILITIES.WORLD_TO_LOGICAL, "validate_walkable_position": SPATIAL_CAPABILITIES.VALIDATE_WALKABLE_POSITION, "get_planar_distance": SPATIAL_CAPABILITIES.PLANAR_DISTANCE, "request_path": SPATIAL_CAPABILITIES.REQUEST_PATH, "resolve_target": SPATIAL_CAPABILITIES.RESOLVE_TARGET}
	return str(mapping.get(method_name, ""))

func _prepare_restored_command(value: Dictionary, actor: Object, position) -> Dictionary:
	for field in ["command_id", "actor_id", "owner_id", "source", "request", "phase", "target_fact", "path_index", "route_index", "patrol_stage", "wait_remaining"]:
		if not value.has(field):
			return _snapshot_failure("movement.3d.snapshot_command_truncated", "活动3D移动快照缺少字段：%s。" % field)
	if str(value.actor_id) != str(_read_property(actor, "stable_instance_id", value.actor_id)):
		return _snapshot_failure("movement.actor_id_mismatch", "活动3D移动快照角色身份不一致。")
	var parsed_request := GMMovementRequest.from_dict(value.request)
	if not parsed_request.ok:
		return _snapshot_failure("movement.3d.snapshot_request_invalid", "活动3D移动快照请求无效。")
	var request: GMMovementRequest = parsed_request.request
	if request.actor_id != str(value.actor_id) or request.map_id != str(_read_property(actor, "map_id", request.map_id)):
		return _snapshot_failure("movement.3d.snapshot_request_identity_invalid", "活动3D移动快照请求与角色地图身份不一致。")
	var target_result := _resolve_request_target(request, position)
	if not target_result.ok:
		return target_result
	var target = target_result.get("position", position)
	var state := {"command_id": str(value.command_id), "actor_id": str(value.actor_id), "owner_id": str(value.owner_id), "source": str(value.source), "request": request, "fingerprint": request.fingerprint(), "actor": actor, "position": position.duplicate_position(), "velocity": Vector2.ZERO, "facing": _current_facing(actor), "phase": str(value.phase), "target": target.duplicate_position() if target != null else null, "target_fact": value.target_fact.duplicate(true), "path_points": [], "path_index": int(value.path_index), "route_points": [], "route_index": int(value.route_index), "patrol_stage": str(value.patrol_stage), "wait_remaining": float(value.wait_remaining), "terminal": false, "result": {}}
	var path := _set_path(state, position, target) if target != null and request.kind != "direction" else {"ok": true}
	if not path.ok:
		return path
	return {"ok": true, "state": state}

func _validate_snapshot(snapshot: Variant) -> Dictionary:
	if not snapshot is Dictionary:
		return _snapshot_failure("movement.3d.snapshot_type_invalid", "Planar 3D移动快照必须是Dictionary。")
	var value: Dictionary = snapshot
	var shape := _validate_exact_fields(value, SNAPSHOT_FIELDS, "Planar 3D移动快照")
	if not shape.ok: return shape
	if not _snapshot_version(value.get("schema_version", null)):
		return _snapshot_failure("movement.3d.snapshot_version_invalid", "Planar 3D移动快照版本不受支持。")
	if str(value.schema) != SNAPSHOT_SCHEMA:
		return _snapshot_failure("movement.3d.snapshot_schema_invalid", "Planar 3D移动快照Schema不匹配。")
	if not _stable_string_id(value.actor_id) or not _stable_string_id(value.map_id):
		return _snapshot_failure("movement.3d.snapshot_identity_invalid", "Planar 3D移动快照稳定身份无效。")
	var position_check := _validate_snapshot_position(value.position)
	if not position_check.ok: return position_check
	var facing_check := _validate_snapshot_facing(value.facing)
	if not facing_check.ok: return facing_check
	if not value.active is bool or not value.command is Dictionary:
		return _snapshot_failure("movement.3d.snapshot_field_type_invalid", "Planar 3D移动快照字段类型无效。")
	var active := bool(value.active)
	if not active and not value.command.is_empty():
		return _snapshot_failure("movement.3d.snapshot_command_unexpected", "非活动3D移动快照不得包含活动命令。")
	if active:
		var command_check := _validate_snapshot_command(value.command)
		if not command_check.ok: return command_check
	return {"ok": true}

func _validate_snapshot_command(command: Dictionary) -> Dictionary:
	var shape := _validate_exact_fields(command, SNAPSHOT_COMMAND_FIELDS, "活动Planar 3D移动命令")
	if not shape.ok: return shape
	for field in ["command_id", "actor_id", "owner_id", "source", "phase", "patrol_stage"]:
		if not command.get(field) is String and not command.get(field) is StringName:
			return _snapshot_failure("movement.3d.snapshot_command_field_type_invalid", "活动3D移动命令字段类型无效：%s。" % field)
	if not _stable_string_id(command.command_id) or not _stable_string_id(command.actor_id) or not _stable_string_id(command.owner_id):
		return _snapshot_failure("movement.3d.snapshot_command_identity_invalid", "活动3D移动命令包含无效稳定身份。")
	if str(command.source) not in ["player", "ai", "script"]:
		return _snapshot_failure("movement.3d.snapshot_command_source_invalid", "活动3D移动命令来源无效。")
	if not command.request is Dictionary:
		return _snapshot_failure("movement.3d.snapshot_request_type_invalid", "活动3D移动命令请求必须是Dictionary。")
	var request_check := _validate_snapshot_request(command.request)
	if not request_check.ok: return request_check
	if not command.target is Dictionary or not command.target_fact is Dictionary:
		return _snapshot_failure("movement.3d.snapshot_command_target_invalid", "活动3D移动命令目标字段类型无效。")
	var target_check := _validate_snapshot_optional_position(command.target, "movement.3d.snapshot_target_invalid")
	if not target_check.ok: return target_check
	var fact_check := _validate_snapshot_target_fact(command.target_fact)
	if not fact_check.ok: return fact_check
	if not command.path_points is Array or not command.route_points is Array:
		return _snapshot_failure("movement.3d.snapshot_path_type_invalid", "活动3D移动命令路径字段必须是数组。")
	for point in command.path_points:
		var path_check := _validate_snapshot_position(point)
		if not path_check.ok: return path_check
	for point in command.route_points:
		var route_check := _validate_snapshot_position(point)
		if not route_check.ok: return route_check
	if not _snapshot_integer(command.path_index) or not _snapshot_integer(command.route_index):
		return _snapshot_failure("movement.3d.snapshot_index_invalid", "活动3D移动命令索引必须是整数。")
	if int(command.path_index) < 0 or int(command.route_index) < 0:
		return _snapshot_failure("movement.3d.snapshot_index_invalid", "活动3D移动命令索引不能为负数。")
	if not _snapshot_number(command.wait_remaining) or float(command.wait_remaining) < 0.0:
		return _snapshot_failure("movement.3d.snapshot_wait_invalid", "活动3D移动命令等待时长必须是有限非负数。")
	if not command.terminal is bool:
		return _snapshot_failure("movement.3d.snapshot_terminal_invalid", "活动3D移动命令terminal字段必须是布尔值。")
	return {"ok": true}

func _validate_snapshot_request(request: Dictionary) -> Dictionary:
	var shape := _validate_exact_fields(request, SNAPSHOT_REQUEST_FIELDS, "活动3D移动请求")
	if not shape.ok: return shape
	var parsed := GMMovementRequest.from_dict(request)
	if not parsed.ok:
		return _snapshot_failure("movement.3d.snapshot_request_invalid", "活动3D移动快照请求无效。")
	var request_value: GMMovementRequest = parsed.request
	for field in ["owner_id", "actor_id", "map_id", "anchor_id", "target_actor_id", "route_id", "entry_anchor_id", "exit_anchor_id", "return_anchor_id", "target_map_id", "idempotency_key"]:
		if not _stable_string_id(request.get(field), true):
			return _snapshot_failure("movement.3d.snapshot_request_identity_invalid", "活动3D移动请求身份字段无效：%s。" % field)
	if request_value.source not in ["player", "ai", "script"]:
		return _snapshot_failure("movement.3d.snapshot_request_source_invalid", "活动3D移动请求来源无效。")
	return {"ok": true}

func _validate_snapshot_target_fact(fact: Dictionary) -> Dictionary:
	var shape := _validate_exact_fields(fact, SNAPSHOT_TARGET_FACT_FIELDS, "活动3D移动目标事实投影")
	if not shape.ok: return shape
	if str(fact.schema) != "gm.movement.3d.target_fact.v1":
		return _snapshot_failure("movement.3d.snapshot_target_fact_schema_invalid", "活动3D移动目标事实投影Schema无效。")
	for field in ["kind", "target_actor_id", "anchor_id", "route_id", "target_phase"]:
		if not _stable_string_id(fact.get(field), true):
			return _snapshot_failure("movement.3d.snapshot_target_fact_identity_invalid", "活动3D移动目标事实字段无效：%s。" % field)
	if not _snapshot_integer(fact.route_index) or int(fact.route_index) < 0:
		return _snapshot_failure("movement.3d.snapshot_target_fact_index_invalid", "活动3D移动目标事实route_index无效。")
	if not fact.resolved_position is Dictionary:
		return _snapshot_failure("movement.3d.snapshot_target_fact_position_invalid", "活动3D移动目标事实位置必须是Dictionary。")
	var position_check := _validate_snapshot_optional_position(fact.resolved_position, "movement.3d.snapshot_target_fact_position_invalid")
	if not position_check.ok: return position_check
	return {"ok": true}

func _validate_snapshot_position(position: Variant) -> Dictionary:
	if not position is Dictionary:
		return _snapshot_failure("movement.3d.snapshot_position_type_invalid", "Planar 3D快照位置必须是Dictionary。")
	var shape := _validate_exact_fields(position, SNAPSHOT_POSITION_FIELDS, "Planar 3D快照位置")
	if not shape.ok: return shape
	var parsed := PLANAR_POSITION.validate_native(position)
	if not parsed.ok:
		return _snapshot_failure("movement.3d.snapshot_position_invalid", "Planar 3D快照位置不是严格有效的PlanarPosition。")
	return {"ok": true}

func _validate_snapshot_optional_position(position: Dictionary, code: String) -> Dictionary:
	if position.is_empty(): return {"ok": true}
	var checked := _validate_snapshot_position(position)
	if checked.ok: return checked
	return _snapshot_failure(code, "活动3D移动快照包含无效PlanarPosition。")

func _validate_snapshot_facing(facing: Variant) -> Dictionary:
	if not facing is Dictionary:
		return _snapshot_failure("movement.3d.snapshot_facing_invalid", "Planar 3D快照朝向必须是Dictionary。")
	var shape := _validate_exact_fields(facing, SNAPSHOT_FACING_FIELDS, "Planar 3D快照朝向")
	if not shape.ok: return shape
	return _parse_facing(facing)

func _validate_exact_fields(value: Dictionary, allowed: Array, label: String) -> Dictionary:
	for field in allowed:
		if not value.has(field):
			return _snapshot_failure("movement.3d.snapshot_field_missing", "%s缺少字段：%s。" % [label, field])
	for key in value.keys():
		if not key is String and not key is StringName:
			return _snapshot_failure("movement.3d.snapshot_field_unknown", "%s字段名必须是字符串。" % label)
		if str(key) not in allowed:
			return _snapshot_failure("movement.3d.snapshot_field_unknown", "%s包含未知字段：%s。" % [label, str(key)])
	return {"ok": true}

func _snapshot_version(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and is_equal_approx(float(value), float(SNAPSHOT_VERSION))

func _snapshot_integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(float(value)) and is_equal_approx(float(value), round(float(value))))

func _snapshot_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _command_snapshot(state: Dictionary) -> Dictionary:
	if state.is_empty(): return {}
	var request: GMMovementRequest = state.get("request", null)
	var points: Array = []
	for point in state.get("path_points", []):
		if point != null and point.has_method("to_native"): points.append(point.to_native())
	var route_points: Array = []
	for point in state.get("route_points", []):
		if point != null and point.has_method("to_native"): route_points.append(point.to_native())
	return {"command_id": str(state.get("command_id", "")), "actor_id": str(state.get("actor_id", "")), "owner_id": str(state.get("owner_id", "")), "source": str(state.get("source", "")), "request": request.to_dict() if request != null else {}, "phase": str(state.get("phase", "")), "target": state.target.to_native() if state.get("target", null) != null else {}, "target_fact": state.get("target_fact", {}).duplicate(true), "path_points": points, "path_index": int(state.get("path_index", 0)), "route_points": route_points, "route_index": int(state.get("route_index", 0)), "patrol_stage": str(state.get("patrol_stage", "")), "wait_remaining": float(state.get("wait_remaining", 0.0)), "terminal": bool(state.get("terminal", false))}

func _actor_observations() -> Dictionary:
	var result: Dictionary = {}
	for actor_id in _actors:
		var row: Dictionary = _actors[actor_id]
		var actor: Object = row.get("actor", null)
		result[str(actor_id)] = {"actor_id": str(actor_id), "map_id": str(row.get("map_id", "")), "position": row.position.to_native() if row.get("position", null) != null else {}, "live": actor != null and is_instance_valid(actor)}
	return result

func _command_observations() -> Dictionary:
	var result: Dictionary = {}
	for command_id in _commands:
		var row: Dictionary = _commands[command_id]
		result[str(command_id)] = _command_snapshot(row)
	return result

func _current_facing(actor: Object) -> Vector2:
	if actor == null or not is_instance_valid(actor): return Vector2.DOWN
	var facing = _read_property(actor, "movement_facing", Vector2.DOWN)
	return facing if facing is Vector2 and _finite_vector(facing) and facing.length_squared() > 0.000001 else Vector2.DOWN

func _parse_facing(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.has("x") or not value.has("y"):
		return _snapshot_failure("movement.3d.snapshot_facing_invalid", "Planar 3D移动快照朝向必须包含有限x/y。")
	var facing := Vector2(float(value.x), float(value.y))
	if not _finite_vector(facing):
		return _snapshot_failure("movement.3d.snapshot_facing_invalid", "Planar 3D移动快照朝向包含非有限数值。")
	return {"ok": true, "value": _safe_normalized(facing)}

func _read_property(actor: Object, property: String, fallback: Variant) -> Variant:
	if actor == null or not is_instance_valid(actor): return fallback
	if property in actor: return actor.get(property)
	return fallback

func _stable_id(value: Variant) -> bool:
	return PLANAR_POSITION.is_valid_stable_id(str(value)) and not str(value).is_empty()

func _stable_string_id(value: Variant, allow_empty: bool = false) -> bool:
	if not value is String and not value is StringName:
		return false
	return PLANAR_POSITION.is_valid_stable_id(value, allow_empty)

func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)

func _safe_normalized(value: Vector2) -> Vector2:
	return value.normalized() if _finite_vector(value) and value.length_squared() > 0.000001 else Vector2.DOWN

func _vector2_native(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}

func _snapshot_failure(code: String, reason_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "atomic": true}

func _fail(code: String, reason_zh: String, fix_zh: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "error_zh": reason_zh, "fix_zh": fix_zh, "details": details.duplicate(true)}
