class_name GMMovementAbilityExecutor
extends RefCounted

const SERVICE_ID := "gm.movement.executor"
const SNAPSHOT_SCHEMA := "gm.movement.snapshot.v2"
const LEGACY_SNAPSHOT_SCHEMA := "gm.movement.snapshot.v1"
const TARGET_FACT_SCHEMA := "gm.movement.target_fact.v1"
# IEEE-754 binary64精确可表示的排他边界2^53。安全整数闭区间
# [-2^53+1, 2^53-1]等价于 value > -2^53 and value < 2^53。
const JSON_SAFE_INTEGER_EXCLUSIVE_BOUND: float = 9007199254740992.0

var semantic_registry: GMMapSemanticRegistry
var _actors: Dictionary = {}
var _active_by_actor: Dictionary = {}
var _commands: Dictionary = {}
var _sequence: int = 0

# 兼容既有只读诊断面，但永不泄漏内部Dictionary、Array、Resource或Node引用。
var actors: Dictionary:
	get: return _actor_observations()
var active_by_actor: Dictionary:
	get: return _active_by_actor.duplicate(true)
var commands: Dictionary:
	get: return _command_observations()
var sequence: int:
	get: return _sequence

func _init(registry: GMMapSemanticRegistry = null) -> void:
	semantic_registry = registry if registry != null else GMMapSemanticRegistry.new()

func register_actor(actor_id: String, actor: Node2D, map_id: String = "") -> Dictionary:
	if actor_id.strip_edges().is_empty() or actor == null or not is_instance_valid(actor): return _fail("movement.actor_registration_invalid", "角色注册缺少稳定ID或有效Node2D。", "请先完成P14角色装配。")
	var numeric_check := _validate_actor_numeric(actor)
	if not numeric_check.ok: return numeric_check
	_actors[actor_id] = {"node": actor, "map_id": map_id if not map_id.is_empty() else str(actor.get("map_id")) if "map_id" in actor else ""}
	return {"ok": true, "actor_id": actor_id}

func unregister_actor(actor_id: String) -> void:
	_actors.erase(actor_id)

func preflight(request: GMMovementRequest, actor: Node2D) -> Dictionary:
	if request == null: return _fail("movement.request_missing", "移动执行器没有收到请求。", "请重新提交ActivationRequest。")
	var checked := request.validate()
	if not checked.ok: return checked
	if actor == null or not is_instance_valid(actor): return _fail("movement.actor_released", "移动角色已释放。", "请重新装配或加载角色。")
	var actor_numeric := _validate_actor_numeric(actor)
	if not actor_numeric.ok: return actor_numeric
	if "stable_instance_id" in actor and str(actor.get("stable_instance_id")) != request.actor_id:
		return _fail("movement.actor_id_mismatch", "移动请求与角色稳定ID不一致。", "请选择与请求匹配的角色。")
	if "map_id" in actor and str(actor.get("map_id")) != request.map_id:
		return _fail("movement.map_mismatch", "角色当前地图与移动请求地图不一致。", "请在正确地图重新提交请求。")
	var control_check := _validate_control_owner(actor, request)
	if not control_check.ok: return control_check
	if request.kind not in ["direct", "direction", "face", "cancel"]:
		var map_result := semantic_registry.resolve_map(request.map_id)
		if not map_result.ok: return _wrap(map_result, "请先注册请求引用的SemanticMap。")
	match request.kind:
		"anchor":
			var anchor_result := semantic_registry.resolve_anchor(request.map_id, request.anchor_id)
			if not anchor_result.ok: return _wrap(anchor_result, "请在SemanticMap中创建或修正目标锚点。")
			var anchor_check := _validate_anchor_numeric(anchor_result.anchor)
			if not anchor_check.ok: return anchor_check
			var walkable := _position_walkable(anchor_result.get("map_id", request.map_id), anchor_result.anchor.position)
			if not walkable.ok: return walkable
		"follow":
			if not _actors.has(request.target_actor_id): return _fail("movement.target_lost", "跟随目标不存在或已离场。", "请选择仍在当前地图中的目标角色。")
			var target_record: Dictionary = _actors[request.target_actor_id]
			if str(target_record.get("map_id", "")) != request.map_id: return _fail("movement.map_mismatch", "跟随目标位于不同地图。", "请等待目标回到同一地图或取消跟随。")
			var target_numeric := _validate_actor_numeric(target_record.node)
			if not target_numeric.ok: return _fail("movement.follow_target_numeric_invalid", "跟随目标包含非有限运动数值。", "请修复目标角色状态后重试。")
		"patrol":
			var map_result: Dictionary = semantic_registry.resolve_map(request.map_id)
			var route_result: Dictionary = map_result.map.resolve_route(request.route_id) if map_result.ok else map_result
			if not route_result.ok: return _wrap(route_result, "请在SemanticMap中创建或修正巡逻路线。")
			var numeric_route_check := _validate_route_numeric(route_result.route, map_result.map.terrain_map)
			if not numeric_route_check.ok: return numeric_route_check
			var route_check: Dictionary = route_result.route.validate_definition()
			if not route_check.ok: return _fail("movement.path_empty", "巡逻路线为空或定义无效。", "请为路线配置至少两个有效点。", {"route_errors": route_check.errors})
			if map_result.map.terrain_map != null:
				var reachability: Dictionary = route_result.route.validate_reachability(map_result.map.terrain_map)
				if not reachability.ok: return _fail("movement.unreachable", "巡逻路线包含不可通行区段。", "请修正路线或地图通行数据。", {"route_errors": reachability.errors})
		"travel":
			return GMTravelHandoff.build(request, semantic_registry)
	return {"ok": true}

func start_request(request: GMMovementRequest, actor: Node2D) -> Dictionary:
	var checked := preflight(request, actor)
	if not checked.ok: return checked
	var frozen_result := _freeze_request(request)
	if not frozen_result.ok: return frozen_result
	var frozen: GMMovementRequest = frozen_result.request
	# 规范化副本再次经过所有动态贡献者预检；此后不再读取调用方Resource。
	var frozen_checked := preflight(frozen, actor)
	if not frozen_checked.ok: return frozen_checked
	var existing_id := str(_active_by_actor.get(frozen.actor_id, ""))
	if frozen.kind == "cancel": return cancel_owner(frozen.actor_id, frozen.owner_id, "移动请求已由统一入口取消。")
	if frozen.kind == "travel": return frozen_checked
	if not existing_id.is_empty() and _commands.has(existing_id):
		var existing: Dictionary = _commands[existing_id]
		if str(existing.fingerprint) == frozen.fingerprint(): return {"ok": true, "pending": true, "idempotent": true, "command_id": existing_id, "phase": str(existing.phase)}
		if str(existing.owner_id) != frozen.owner_id: return _fail("movement.owner_conflict", "角色已有其他owner的移动执行。", "请由当前owner取消后再提交。", {"active_owner": existing.owner_id, "requested_owner": frozen.owner_id, "active_command_id": existing_id})
		return _fail("movement.target_replace_conflict", "同一owner不能静默替换正在执行的移动目标。", "请先取消原移动，再提交新目标。", {"active_command_id": existing_id})
	_sequence += 1
	var command_id := "gm.movement.command.%06d" % _sequence
	var state := {"command_id": command_id, "actor_id": frozen.actor_id, "owner_id": frozen.owner_id, "source": frozen.source, "request": frozen, "fingerprint": frozen.fingerprint(), "actor": actor, "velocity": Vector2.ZERO, "facing": _current_facing(actor), "phase": "starting", "target": frozen.target_position, "target_fact": {}, "route_points": [], "route_index": 0, "patrol_stage": "", "wait_remaining": 0.0, "terminal": false, "result": {}}
	match frozen.kind:
		"anchor":
			state.target = semantic_registry.resolve_anchor(frozen.map_id, frozen.anchor_id).anchor.position
			state.phase = "moving"
		"follow":
			state.target = _actors[frozen.target_actor_id].node.position
			state.phase = "following"
		"patrol":
			var map_result: Dictionary = semantic_registry.resolve_map(frozen.map_id)
			var route_result: Dictionary = map_result.map.resolve_route(frozen.route_id)
			state.route_points = route_result.route.points.duplicate(true)
			state.target = state.route_points[0].position
			state.patrol_stage = "moving"
			state.phase = "patrolling"
		"direction":
			state.target = Vector2.ZERO
			state.phase = "direction"
		"face":
			var face_direction := _safe_normalized(frozen.direction)
			_apply_motion(actor, actor.position, Vector2.ZERO, face_direction)
			return {"ok": true, "completed": true, "command_id": command_id, "phase": "faced", "facing": face_direction}
		_: state.phase = "moving"
	state.target_fact = _make_target_fact(frozen, state)
	_commands[command_id] = state
	_active_by_actor[frozen.actor_id] = command_id
	return {"ok": true, "pending": true, "command_id": command_id, "phase": state.phase}

func tick_command(command_id: String, delta: float) -> Dictionary:
	if not _commands.has(command_id): return _fail("movement.command_missing", "移动命令不存在或已结束。", "请重新提交移动请求。")
	var stored_state: Dictionary = _commands[command_id]
	var state: Dictionary = stored_state.duplicate(false)
	state.route_points = stored_state.route_points.duplicate(true) if stored_state.get("route_points", null) is Array else []
	state.target_fact = stored_state.target_fact.duplicate(true) if stored_state.get("target_fact", null) is Dictionary else {}
	if bool(state.terminal): return state.result.duplicate(true)
	if not is_finite(delta) or delta < 0.0: return _fail("movement.delta_invalid", "移动帧间隔必须是0或正的有限数值。", "请检查调用方时钟后重试。", {"field": "delta"})
	var state_numeric := _validate_command_numeric(state)
	if not state_numeric.ok: return state_numeric
	if not state.get("request", null) is GMMovementRequest: return _fail("movement.command_request_invalid", "活动移动命令缺少有效请求。", "请丢弃损坏命令并重新提交。")
	var request: GMMovementRequest = state.request
	var target_fact_check := _validate_target_fact_relation(state, request)
	if not target_fact_check.ok: return target_fact_check
	var actor: Node2D = state.actor
	if actor == null or not is_instance_valid(actor): return _finish_failure(state, "movement.actor_released", "移动角色已释放。", "请重新加载角色。")
	var actor_numeric := _validate_actor_numeric(actor)
	if not actor_numeric.ok: return actor_numeric
	var request_numeric := request.validate()
	if not request_numeric.ok: return request_numeric
	if "map_id" in actor and str(actor.get("map_id")) != request.map_id: return _finish_failure(state, "movement.map_mismatch", "角色在移动期间切换了地图。", "请在新地图重新提交请求。")
	var control_check := _validate_control_owner(actor, request)
	if not control_check.ok: return _finish_failure(state, "movement.control_lost", "移动期间统一控制权已释放或移交。", "请由当前控制owner重新提交移动请求。")
	var target: Vector2 = state.target
	match request.kind:
		"direction":
			var direction := _safe_normalized(request.direction)
			var motion := _calculate_motion(actor.position, state.velocity, direction, request.speed, request.acceleration, delta)
			if not motion.ok: return motion
			var velocity: Vector2 = motion.velocity
			_apply_motion(actor, motion.position, velocity, direction)
			state.velocity = velocity; state.facing = direction; _commands[command_id] = state
			return _pending(state)
		"follow":
			if not _actors.has(request.target_actor_id): return _finish_failure(state, "movement.target_lost", "跟随目标在移动期间消失。", "请取消或选择新的有效目标。")
			var target_record: Dictionary = _actors[request.target_actor_id]
			if str(target_record.get("map_id", "")) != request.map_id: return _finish_failure(state, "movement.map_mismatch", "跟随目标移动到其他地图。", "请取消跟随，旅行后重新请求。")
			var target_node: Node2D = target_record.node
			if target_node == null or not is_instance_valid(target_node): return _finish_failure(state, "movement.target_lost", "跟随目标已释放。", "请选择仍在场景中的角色。")
			var target_numeric := _validate_actor_numeric(target_node)
			if not target_numeric.ok: return _fail("movement.follow_target_numeric_invalid", "跟随目标包含非有限运动数值。", "请修复目标角色状态后重试。")
			target = target_node.position
			state.target = target
			state.target_fact = _make_target_fact(request, state)
		"patrol":
			if state.route_points.is_empty(): return _finish_failure(state, "movement.path_empty", "巡逻路线在执行期间为空。", "请修复路线资源后重新开始。")
			target = state.route_points[state.route_index].position
			state.target = target
			state.target_fact = _make_target_fact(request, state)
	var displacement := target - actor.position
	if not _vector_finite(displacement): return _fail("movement.calculation_overflow", "移动坐标差超出可计算范围。", "请拆分极端跨度后重试。")
	var distance := _stable_length(displacement)
	if not is_finite(distance): return _fail("movement.calculation_overflow", "移动距离超出可计算范围。", "请拆分极端跨度后重试。")
	var desired_stop := request.follow_distance if request.kind == "follow" else request.stop_distance
	if distance <= desired_stop:
		_apply_motion(actor, actor.position, Vector2.ZERO, state.facing)
		state.velocity = Vector2.ZERO
		if request.kind == "follow": _commands[command_id] = state; return _pending(state)
		if request.kind == "patrol":
			var point: Dictionary = state.route_points[state.route_index]
			if state.patrol_stage == "moving":
				state.wait_remaining = float(point.get("wait", 0.0))
				if state.wait_remaining > 0.0: state.patrol_stage = "waiting"
			if state.wait_remaining > 0.0:
				state.wait_remaining = maxf(0.0, state.wait_remaining - delta)
				state.target_fact = _make_target_fact(request, state)
				if state.wait_remaining > 0.0: _commands[command_id] = state; return _pending(state)
			state.route_index += 1
			if state.route_index >= state.route_points.size():
				if request.loop: state.route_index = 0
				else: return _finish_success(state, "arrived", {"route_id": request.route_id})
			state.patrol_stage = "moving"; state.wait_remaining = 0.0
			state.target = state.route_points[state.route_index].position
			state.target_fact = _make_target_fact(request, state)
			_commands[command_id] = state
			return _pending(state)
		return _finish_success(state, "arrived", {"position": actor.position, "anchor_id": request.anchor_id})
	var direction := _safe_normalized(displacement)
	var motion := _calculate_motion(actor.position, state.velocity, direction, request.speed, request.acceleration, delta)
	if not motion.ok: return motion
	var velocity: Vector2 = motion.velocity
	var next_position: Vector2 = motion.position
	var travelled := _stable_length(velocity) * delta
	var remaining_vector := target - next_position
	if not is_finite(travelled) or not _vector_finite(remaining_vector): return _fail("movement.calculation_overflow", "移动步进比较超出有限范围。", "请降低参数或拆分极端坐标跨度。")
	if travelled >= distance or _stable_length(remaining_vector) > distance: next_position = target
	_apply_motion(actor, next_position, velocity, direction)
	state.velocity = velocity; state.facing = direction; _commands[command_id] = state
	return _pending(state)

func cancel_move(command_id: String, reason_zh: String = "移动已取消。") -> Dictionary:
	if not _commands.has(command_id): return {"ok": true, "completed": true, "idempotent": true, "code": "movement.already_cancelled"}
	var state: Dictionary = _commands[command_id]
	return cancel_owner(str(state.actor_id), str(state.owner_id), reason_zh)

func cancel_owner(actor_id: String, owner_id: String, reason_zh: String = "移动已取消。") -> Dictionary:
	var command_id := str(_active_by_actor.get(actor_id, ""))
	if command_id.is_empty() or not _commands.has(command_id): return {"ok": true, "completed": true, "idempotent": true, "code": "movement.already_cancelled", "reason_zh": "角色当前没有移动执行。"}
	var state: Dictionary = _commands[command_id]
	if str(state.owner_id) != owner_id: return _fail("movement.cancel_not_owner", "取消请求与当前移动owner不一致。", "请由当前owner发起取消。", {"active_owner": state.owner_id, "requested_owner": owner_id})
	var state_numeric := _validate_command_numeric(state)
	if not state_numeric.ok: return state_numeric
	var actor: Node2D = state.actor
	var actor_numeric := _validate_actor_numeric(actor)
	if not actor_numeric.ok: return actor_numeric
	if actor != null and is_instance_valid(actor): _apply_motion(actor, actor.position, Vector2.ZERO, state.facing)
	return _finish_success(state, "cancelled", {"cancelled": true, "reason_zh": reason_zh})

func snapshot_actor(actor_id: String) -> Dictionary:
	if _actors.has(actor_id):
		var registered_actor: Node2D = _actors[actor_id].node
		var registered_numeric := _validate_actor_numeric(registered_actor)
		if not registered_numeric.ok: return registered_numeric
	var command_id := str(_active_by_actor.get(actor_id, ""))
	if command_id.is_empty() or not _commands.has(command_id): return {"schema": SNAPSHOT_SCHEMA, "actor_id": actor_id, "active": false, "command_id": "", "owner_id": "", "source": "", "phase": "idle", "request": {}, "velocity": {"x": 0.0, "y": 0.0}, "facing": {"x": 0.0, "y": 1.0}, "route_index": 0, "patrol_stage": "", "wait_remaining": 0.0, "target_fact": {}}
	var state: Dictionary = _commands[command_id]
	var snapshot_check := _validate_active_command_for_snapshot(state, actor_id, command_id)
	if not snapshot_check.ok: return snapshot_check
	return {"schema": SNAPSHOT_SCHEMA, "actor_id": actor_id, "active": true, "command_id": command_id, "owner_id": str(state.owner_id), "source": str(state.source), "phase": str(state.phase), "request": snapshot_check.request_data.duplicate(true), "velocity": {"x": state.velocity.x, "y": state.velocity.y}, "facing": {"x": state.facing.x, "y": state.facing.y}, "route_index": int(state.route_index), "patrol_stage": str(state.patrol_stage), "wait_remaining": float(state.wait_remaining), "target_fact": snapshot_check.target_fact_data.duplicate(true)}

func restore_actor(snapshot: Variant) -> Dictionary:
	if not snapshot is Dictionary: return _fail("movement.snapshot_type_invalid", "移动快照类型错误。", "请使用完整Dictionary快照。")
	if not snapshot.has("schema"): return _fail("movement.snapshot_truncated", "移动快照缺少字段“schema”。", "请使用完整快照。", {"field": "schema"})
	if typeof(snapshot.schema) != TYPE_STRING: return _fail("movement.snapshot_field_type_invalid", "移动快照字段“schema”类型错误。", "请检查存档写入器。", {"field": "schema"})
	if str(snapshot.schema) != SNAPSHOT_SCHEMA:
		return _fail("movement.snapshot_schema_invalid", "移动快照schema不匹配；v1不含目标事实，不能安全恢复。", "请使用gm.movement.snapshot.v2重新生成快照。", {"legacy_v1_rejected": str(snapshot.schema) == LEGACY_SNAPSHOT_SCHEMA})
	# 共同贡献者必须先于active分支验证；活动专属字段不能参与分支判定。
	var common_required := ["actor_id", "active", "velocity", "facing"]
	for field in common_required:
		if not snapshot.has(field): return _fail("movement.snapshot_truncated", "移动快照缺少字段“%s”。" % field, "请使用完整快照。", {"field": field})
	if typeof(snapshot.actor_id) != TYPE_STRING or typeof(snapshot.active) != TYPE_BOOL:
		return _fail("movement.snapshot_field_type_invalid", "移动快照actor_id或active类型错误。", "请检查存档写入器。")
	var actor_id := str(snapshot.actor_id)
	if actor_id.strip_edges().is_empty() or not _actors.has(actor_id): return _fail("movement.actor_released", "移动快照引用的角色未注册。", "请先恢复P14角色装配。")
	var actor: Node2D = _actors[actor_id].node
	var actor_numeric := _validate_actor_numeric(actor)
	if not actor_numeric.ok: return actor_numeric
	var velocity_check := GMMovementRequest._strict_vector2(snapshot.velocity, "velocity")
	if not velocity_check.ok: return velocity_check
	var facing_check := GMMovementRequest._strict_vector2(snapshot.facing, "facing")
	if not facing_check.ok: return facing_check
	if not bool(snapshot.active):
		# v2 inactive采用snapshot_actor自产的完整规范空值；不要求空target_fact伪造route_index。
		var inactive_required := ["command_id", "owner_id", "source", "phase", "request", "route_index", "patrol_stage", "wait_remaining", "target_fact"]
		for field in inactive_required:
			if not snapshot.has(field): return _fail("movement.snapshot_truncated", "非活动移动快照缺少字段“%s”。" % field, "请使用snapshot_actor自产的完整v2快照。", {"field": field})
		for field in ["command_id", "owner_id", "source", "phase", "patrol_stage"]:
			if typeof(snapshot[field]) != TYPE_STRING: return _fail("movement.snapshot_field_type_invalid", "非活动移动快照字段“%s”类型错误。" % field, "请检查存档写入器。", {"field": field})
		if not snapshot.request is Dictionary or not snapshot.target_fact is Dictionary or typeof(snapshot.route_index) != TYPE_INT or typeof(snapshot.wait_remaining) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(snapshot.wait_remaining)):
			return _fail("movement.snapshot_field_type_invalid", "非活动移动快照的规范空值类型错误。", "请使用snapshot_actor自产的完整v2快照。")
		if not str(snapshot.command_id).is_empty() or not str(snapshot.owner_id).is_empty() or not str(snapshot.source).is_empty() or str(snapshot.phase) != "idle" or not snapshot.request.is_empty() or int(snapshot.route_index) != 0 or not str(snapshot.patrol_stage).is_empty() or float(snapshot.wait_remaining) != 0.0 or not snapshot.target_fact.is_empty() or velocity_check.value != Vector2.ZERO or facing_check.value != Vector2.DOWN:
			return _fail("movement.snapshot_inactive_contributor_invalid", "非活动移动快照包含活动命令贡献者。", "请使用由snapshot_actor生成的完整快照。")
		# Commit begins here. All inactive contributors passed before clearing an existing command.
		var previous_command_id := str(_active_by_actor.get(actor_id, ""))
		if not previous_command_id.is_empty(): _commands.erase(previous_command_id)
		_active_by_actor.erase(actor_id)
		_apply_motion(actor, actor.position, velocity_check.value, facing_check.value)
		return {"ok": true, "active": false, "atomic": true, "cleared_command_id": previous_command_id}
	var active_required := ["command_id", "owner_id", "source", "phase", "request", "route_index", "patrol_stage", "wait_remaining", "target_fact"]
	for field in active_required:
		if not snapshot.has(field): return _fail("movement.snapshot_truncated", "活动移动快照缺少字段“%s”。" % field, "请使用完整快照。", {"field": field})
	for field in ["command_id", "owner_id", "source", "phase", "patrol_stage"]:
		if typeof(snapshot[field]) != TYPE_STRING: return _fail("movement.snapshot_field_type_invalid", "活动移动快照字段“%s”类型错误。" % field, "请检查存档写入器。", {"field": field})
	if typeof(snapshot.route_index) != TYPE_INT or not snapshot.request is Dictionary or not snapshot.target_fact is Dictionary or typeof(snapshot.wait_remaining) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(snapshot.wait_remaining)) or float(snapshot.wait_remaining) < 0.0:
		return _fail("movement.snapshot_field_type_invalid", "活动移动快照索引、请求或等待字段类型错误。", "请检查存档写入器。")
	var parsed := GMMovementRequest.from_dict(snapshot.request)
	if not parsed.ok: return parsed
	if parsed.request.actor_id != actor_id or parsed.request.owner_id != str(snapshot.owner_id) or parsed.request.source != str(snapshot.source):
		return _fail("movement.snapshot_identity_mismatch", "移动快照身份、owner或来源贡献者不一致。", "请使用同一次snapshot_actor产生的完整快照。")
	if str(snapshot.command_id).is_empty() or not str(snapshot.command_id).begins_with("gm.movement.command."):
		return _fail("movement.snapshot_command_id_invalid", "移动快照命令ID无效。", "请使用由统一移动执行器生成的快照。")
	var expected_phases := {"direct": "moving", "anchor": "moving", "direction": "direction", "follow": "following", "patrol": "patrolling"}
	if not expected_phases.has(parsed.request.kind):
		return _fail("movement.snapshot_request_not_restorable", "移动快照包含不可恢复的一次性请求类型。", "仅恢复直达、锚点、方向、跟随或巡逻活动请求。")
	if str(snapshot.phase) != str(expected_phases[parsed.request.kind]):
		return _fail("movement.snapshot_phase_mismatch", "移动快照阶段与请求类型不一致。", "请使用未拼接、未截断的活动快照。")
	var preflight_result := preflight(parsed.request, actor)
	if not preflight_result.ok: return preflight_result
	if _active_by_actor.has(actor_id): return _fail("movement.restore_conflict", "角色已有移动执行，不能覆盖恢复。", "请先停止当前移动。")
	var route_index: int = int(snapshot.route_index)
	if route_index < 0: return _fail("movement.snapshot_route_index_invalid", "移动快照巡逻索引越界。", "请使用未截断快照。")
	if parsed.request.kind == "patrol":
		var map_result: Dictionary = semantic_registry.resolve_map(parsed.request.map_id)
		if not map_result.ok: return map_result
		var route_result: Dictionary = map_result.map.resolve_route(parsed.request.route_id)
		if not route_result.ok: return route_result
		if route_index >= route_result.route.points.size(): return _fail("movement.snapshot_route_index_invalid", "移动快照巡逻索引越界。", "请使用未截断快照。")
	elif route_index != 0:
		return _fail("movement.snapshot_route_index_invalid", "非巡逻移动快照的路线索引必须为0。", "请使用未拼接的快照。")
	var fact_result := _target_fact_from_snapshot(snapshot.target_fact)
	if not fact_result.ok: return fact_result
	var fact_state := {"target": fact_result.fact.resolved_position, "target_fact": fact_result.fact, "route_points": [], "route_index": route_index, "patrol_stage": str(snapshot.patrol_stage), "wait_remaining": float(snapshot.wait_remaining), "phase": str(snapshot.phase)}
	if parsed.request.kind == "patrol":
		var fact_map: Dictionary = semantic_registry.resolve_map(parsed.request.map_id)
		var fact_route: Dictionary = fact_map.map.resolve_route(parsed.request.route_id) if fact_map.ok else fact_map
		if not fact_route.ok: return fact_route
		fact_state.route_points = fact_route.route.points.duplicate(true)
	var fact_relation := _validate_target_fact_relation(fact_state, parsed.request)
	if not fact_relation.ok: return _fail("movement.snapshot_target_fact_mismatch", "移动快照目标事实与请求或路线不一致。", "请拒绝拼接或损坏的目标事实。", {"contributor_code": str(fact_relation.get("code", ""))})
	# Commit begins here. Every schema, identity, actor, request, route and value
	# contributor has passed before start_request can advance sequence or commands.
	var started := start_request(parsed.request, actor)
	if not started.ok: return started
	var state: Dictionary = _commands[started.command_id]
	state.velocity = velocity_check.value; state.facing = facing_check.value; state.route_index = route_index
	state.patrol_stage = str(snapshot.patrol_stage); state.wait_remaining = float(snapshot.wait_remaining)
	state.target = fact_result.fact.resolved_position; state.target_fact = fact_result.fact.duplicate(true)
	_commands[started.command_id] = state
	_apply_motion(actor, actor.position, state.velocity, state.facing)
	return {"ok": true, "active": true, "atomic": true, "command_id": started.command_id}

## 明确的JSON持久化入口。先验证schema、active、actor_id共同边界，再按active
## 分支规范化适用的安全整数。inactive空target_fact不会被当作活动事实读取。
func restore_actor_from_json(snapshot: Variant) -> Dictionary:
	if not snapshot is Dictionary: return _fail("movement.snapshot_type_invalid", "JSON移动快照类型错误。", "请传入JSON.parse_string得到的Dictionary。")
	for field in ["schema", "active", "actor_id"]:
		if not snapshot.has(field): return _fail("movement.snapshot_truncated", "JSON移动快照缺少字段“%s”。" % field, "请使用完整JSON快照。", {"field": field})
	if typeof(snapshot.schema) != TYPE_STRING or typeof(snapshot.actor_id) != TYPE_STRING or typeof(snapshot.active) != TYPE_BOOL:
		return _fail("movement.snapshot_field_type_invalid", "JSON移动快照schema、actor_id或active类型错误。", "请检查存档写入器。")
	if str(snapshot.schema) != SNAPSHOT_SCHEMA:
		return _fail("movement.snapshot_schema_invalid", "JSON移动快照schema不匹配；v1不能安全恢复。", "请使用gm.movement.snapshot.v2重新生成快照。", {"legacy_v1_rejected": str(snapshot.schema) == LEGACY_SNAPSHOT_SCHEMA})
	var normalized: Dictionary = snapshot.duplicate(true)
	if not bool(snapshot.active):
		# inactive只规范化自身规范空索引；绝不读取空target_fact内部字段。
		if normalized.has("route_index"):
			var inactive_index := _normalize_json_safe_integer(normalized.route_index, "route_index")
			if not inactive_index.ok: return inactive_index
			normalized.route_index = inactive_index.value
		return restore_actor(normalized)
	# active分支先确认request kind，再读取任何活动专属目标事实。
	if not normalized.has("request") or not normalized.request is Dictionary or not normalized.request.has("kind") or typeof(normalized.request.kind) != TYPE_STRING:
		return _fail("movement.snapshot_truncated", "JSON活动移动快照缺少可判定的request.kind。", "请使用完整活动v2快照。", {"field": "request.kind"})
	if str(normalized.request.kind) not in ["direct", "anchor", "direction", "follow", "patrol", "face"]:
		return _fail("movement.snapshot_request_not_restorable", "JSON活动移动快照包含不可恢复的请求类型。", "请使用可持续移动kind的自产快照。")
	if not normalized.has("route_index"):
		return _fail("movement.snapshot_truncated", "JSON活动移动快照缺少字段“route_index”。", "请使用完整JSON快照。", {"field": "route_index"})
	var normalized_index := _normalize_json_safe_integer(normalized.route_index, "route_index")
	if not normalized_index.ok: return normalized_index
	normalized.route_index = normalized_index.value
	if not normalized.has("target_fact") or not normalized.target_fact is Dictionary or not normalized.target_fact.has("route_index"):
		return _fail("movement.snapshot_truncated", "JSON移动快照缺少target_fact.route_index。", "请使用完整v2快照。")
	var fact_raw_index: Variant = normalized.target_fact.route_index
	var fact_normalized_index := _normalize_json_safe_integer(fact_raw_index, "target_fact.route_index")
	if not fact_normalized_index.ok: return fact_normalized_index
	normalized.target_fact.route_index = fact_normalized_index.value
	return restore_actor(normalized)

func _position_walkable(map_id: String, world_position: Vector2) -> Dictionary:
	if not _vector_finite(world_position): return _fail("movement.semantic_position_nonfinite", "语义目标位置必须为有限坐标。", "请修正SemanticMap目标后重试。")
	var map_result := semantic_registry.resolve_map(map_id)
	if not map_result.ok: return map_result
	var terrain: GMMapResource = map_result.map.terrain_map
	if terrain == null: return {"ok": true, "unchecked": true}
	if terrain.tile_size.x <= 0 or terrain.tile_size.y <= 0: return _fail("movement.semantic_tile_size_invalid", "语义地图网格尺寸必须为正数。", "请修正任务08地图尺寸。")
	var cell_x := world_position.x / float(terrain.tile_size.x); var cell_y := world_position.y / float(terrain.tile_size.y)
	if not is_finite(cell_x) or not is_finite(cell_y) or absf(cell_x) >= 9.22e18 or absf(cell_y) >= 9.22e18: return _fail("movement.semantic_position_range_invalid", "语义目标坐标超出地图索引安全范围。", "请将目标移入可表示的地图坐标范围。")
	var cell := Vector2i(floori(cell_x), floori(cell_y))
	var logic: Dictionary = terrain.logic_cells.get(GMMapResource.cell_key(cell), {})
	if not terrain.in_bounds(cell) or logic.is_empty() or not bool(logic.get("walkable", false)):
		return _fail("movement.unreachable", "目标锚点位于不可通行单元。", "请移动锚点或修正任务08通行数据。", {"cell": cell})
	return {"ok": true}

func _finish_success(state: Dictionary, phase: String, details: Dictionary = {}) -> Dictionary:
	state.terminal = true; state.phase = phase
	state.result = {"ok": true, "completed": true, "command_id": state.command_id, "phase": phase, "details": details}
	_commands[state.command_id] = state; _active_by_actor.erase(state.actor_id)
	return state.result.duplicate(true)

func _finish_failure(state: Dictionary, code: String, reason_zh: String, fix_zh: String) -> Dictionary:
	state.terminal = true; state.phase = "blocked"
	state.result = _fail(code, reason_zh, fix_zh, {"command_id": state.command_id}); state.result["failed"] = true; state.result["completed"] = false
	_commands[state.command_id] = state; _active_by_actor.erase(state.actor_id)
	return state.result.duplicate(true)

func _pending(state: Dictionary) -> Dictionary:
	return {"ok": true, "pending": true, "completed": false, "command_id": state.command_id, "phase": state.phase, "position": state.actor.position, "velocity": state.velocity, "facing": state.facing}

func _calculate_motion(current_position: Vector2, current_velocity: Vector2, direction: Vector2, speed: float, acceleration: float, delta: float) -> Dictionary:
	var desired_velocity := direction * speed
	var max_delta := acceleration * delta
	if not _vector_finite(desired_velocity) or not is_finite(max_delta): return _fail("movement.calculation_overflow", "移动速度或加速度计算超出有限范围。", "请降低参数或帧间隔后重试。")
	var velocity := current_velocity.move_toward(desired_velocity, max_delta)
	var offset := velocity * delta
	var next_position := current_position + offset
	if not _vector_finite(velocity) or not _vector_finite(offset) or not _vector_finite(next_position): return _fail("movement.calculation_overflow", "移动积分结果超出有限范围。", "请降低参数、帧间隔或拆分极端坐标跨度。")
	return {"ok": true, "velocity": velocity, "position": next_position}

func _validate_actor_numeric(actor: Node2D) -> Dictionary:
	if actor == null or not is_instance_valid(actor): return _fail("movement.actor_released", "移动角色已释放。", "请重新装配或加载角色。")
	if not _vector_finite(actor.position): return _fail("movement.actor_position_nonfinite", "角色当前位置包含非有限分量。", "请先恢复有效角色位置。")
	if "movement_velocity" in actor and not _variant_vector_finite(actor.get("movement_velocity")): return _fail("movement.actor_velocity_nonfinite", "角色当前速度不是有限二维向量。", "请先恢复有效角色速度。")
	if "movement_facing" in actor and not _variant_vector_finite(actor.get("movement_facing")): return _fail("movement.actor_facing_nonfinite", "角色当前朝向不是有限二维向量。", "请先恢复有效角色朝向。")
	return {"ok": true}

func _validate_command_numeric(state: Dictionary) -> Dictionary:
	for pair in [["velocity", state.get("velocity", null)], ["facing", state.get("facing", null)], ["target", state.get("target", null)]]:
		if not _variant_vector_finite(pair[1]): return _fail("movement.command_vector_invalid", "活动移动命令“%s”包含无效或非有限向量。" % pair[0], "请丢弃损坏命令并重新提交。", {"field": pair[0]})
	var wait_value: Variant = state.get("wait_remaining", null)
	if typeof(wait_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(wait_value)) or float(wait_value) < 0.0: return _fail("movement.command_time_invalid", "活动移动命令的等待时间无效。", "请丢弃损坏命令并重新提交。", {"field": "wait_remaining"})
	if typeof(state.get("route_index", null)) != TYPE_INT or int(state.route_index) < 0: return _fail("movement.command_route_index_invalid", "活动移动命令的路线索引无效。", "请丢弃损坏命令并重新提交。")
	var route_points: Variant = state.get("route_points", null)
	if not route_points is Array: return _fail("movement.command_route_invalid", "活动移动命令的路线集合类型无效。", "请丢弃损坏命令并重新提交。")
	if state.get("request", null) is GMMovementRequest and state.request.kind == "patrol" and int(state.route_index) >= route_points.size(): return _fail("movement.command_route_index_invalid", "活动移动命令的路线索引越界。", "请丢弃损坏命令并重新提交。")
	for point in route_points:
		if not point is Dictionary or not point.get("position", null) is Vector2 or not _vector_finite(point.position): return _fail("movement.command_route_invalid", "活动移动命令的路线位置无效。", "请丢弃损坏命令并重新提交。")
		for numeric_field in ["speed", "wait"]:
			var raw: Variant = point.get(numeric_field, 1.0 if numeric_field == "speed" else 0.0)
			if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)) or (numeric_field == "speed" and float(raw) <= 0.0) or (numeric_field == "wait" and float(raw) < 0.0): return _fail("movement.command_route_invalid", "活动移动命令的路线数值无效。", "请丢弃损坏命令并重新提交。", {"field": numeric_field})
	return {"ok": true}

func _freeze_request(request: GMMovementRequest) -> Dictionary:
	if request == null: return _fail("movement.request_missing", "移动请求为空，无法建立内部事实。", "请重新提交有效请求。")
	var payload: Dictionary = request.to_dict().duplicate(true)
	var parsed := GMMovementRequest.from_dict(payload)
	if not parsed.ok: return parsed
	return {"ok": true, "request": parsed.request, "request_data": parsed.request.to_dict().duplicate(true)}

func _make_target_fact(request: GMMovementRequest, state: Dictionary) -> Dictionary:
	var source_type := "request_position"
	var source_id := ""
	var target_phase := "fixed"
	var route_fingerprint := ""
	match request.kind:
		"anchor": source_type = "semantic_anchor"; source_id = request.anchor_id
		"direction": source_type = "direction"; target_phase = "unbounded"
		"follow": source_type = "actor_sample"; source_id = request.target_actor_id; target_phase = "sampled"
		"patrol":
			source_type = "semantic_route_point"; source_id = request.route_id
			target_phase = str(state.get("patrol_stage", "moving"))
			route_fingerprint = _route_fingerprint(state.get("route_points", []))
	return {"schema": TARGET_FACT_SCHEMA, "kind": request.kind, "source_type": source_type, "source_id": source_id, "request_fingerprint": request.fingerprint(), "resolved_position": state.target, "route_id": request.route_id if request.kind == "patrol" else "", "route_fingerprint": route_fingerprint, "route_index": int(state.get("route_index", 0)), "command_phase": str(state.phase), "target_phase": target_phase}

func _target_fact_to_snapshot(fact: Dictionary) -> Dictionary:
	return {"schema": str(fact.schema), "kind": str(fact.kind), "source_type": str(fact.source_type), "source_id": str(fact.source_id), "request_fingerprint": str(fact.request_fingerprint), "resolved_position": {"x": fact.resolved_position.x, "y": fact.resolved_position.y}, "route_id": str(fact.route_id), "route_fingerprint": str(fact.route_fingerprint), "route_index": int(fact.route_index), "command_phase": str(fact.command_phase), "target_phase": str(fact.target_phase)}

func _target_fact_from_snapshot(value: Variant) -> Dictionary:
	if not value is Dictionary: return _fail("movement.snapshot_target_fact_type_invalid", "移动快照target_fact类型错误。", "请使用完整v2快照。")
	var required := ["schema", "kind", "source_type", "source_id", "request_fingerprint", "resolved_position", "route_id", "route_fingerprint", "route_index", "command_phase", "target_phase"]
	for field in required:
		if not value.has(field): return _fail("movement.snapshot_target_fact_truncated", "移动快照target_fact缺少字段“%s”。" % field, "请使用完整v2快照。")
	for field in ["schema", "kind", "source_type", "source_id", "request_fingerprint", "route_id", "route_fingerprint", "command_phase", "target_phase"]:
		if typeof(value[field]) != TYPE_STRING: return _fail("movement.snapshot_target_fact_type_invalid", "移动快照target_fact字段“%s”类型错误。" % field, "请拒绝拼接快照。")
	if typeof(value.route_index) != TYPE_INT: return _fail("movement.snapshot_target_fact_type_invalid", "移动快照target_fact.route_index类型错误。", "内存恢复只接受严格整数。")
	var position_check := GMMovementRequest._strict_vector2(value.resolved_position, "target_fact.resolved_position")
	if not position_check.ok: return _fail("movement.snapshot_target_fact_numeric_invalid", "移动快照target_fact位置不是有限二维坐标。", "请拒绝非有限目标事实。", {"contributor_code": str(position_check.get("code", ""))})
	if str(value.schema) != TARGET_FACT_SCHEMA: return _fail("movement.snapshot_target_fact_schema_invalid", "移动快照target_fact schema不匹配。", "请使用当前目标事实版本。")
	var fact: Dictionary = value.duplicate(true); fact.resolved_position = position_check.value
	return {"ok": true, "fact": fact}

func _validate_target_fact_relation(state: Dictionary, request: GMMovementRequest) -> Dictionary:
	if not state.get("target_fact", null) is Dictionary: return _fail("movement.target_fact_missing", "活动移动命令缺少目标事实。", "请丢弃损坏命令并重新提交。")
	var fact: Dictionary = state.target_fact
	var parsed_fact := _target_fact_from_snapshot(_target_fact_to_snapshot(fact)) if fact.get("resolved_position", null) is Vector2 else _target_fact_from_snapshot(fact)
	if not parsed_fact.ok: return parsed_fact
	fact = parsed_fact.fact
	if fact.kind != request.kind or fact.request_fingerprint != request.fingerprint() or fact.command_phase != str(state.phase) or int(fact.route_index) != int(state.route_index): return _fail("movement.target_fact_identity_mismatch", "目标事实与请求、阶段或路线索引不一致。", "请丢弃损坏命令并重新提交。")
	if not state.get("target", null) is Vector2 or state.target != fact.resolved_position: return _fail("movement.target_fact_target_mismatch", "活动target与已解析目标事实不一致。", "请丢弃损坏命令并重新提交。")
	var expected_type := "request_position"; var expected_id := ""; var expected_target_phase := "fixed"
	match request.kind:
		"anchor": expected_type = "semantic_anchor"; expected_id = request.anchor_id
		"direction": expected_type = "direction"; expected_target_phase = "unbounded"
		"follow": expected_type = "actor_sample"; expected_id = request.target_actor_id; expected_target_phase = "sampled"
		"patrol": expected_type = "semantic_route_point"; expected_id = request.route_id; expected_target_phase = str(state.get("patrol_stage", ""))
	if fact.source_type != expected_type or fact.source_id != expected_id or fact.target_phase != expected_target_phase: return _fail("movement.target_fact_source_mismatch", "目标事实来源或阶段与请求不一致。", "请丢弃损坏命令并重新提交。")
	if request.kind == "patrol":
		if not state.get("route_points", null) is Array or state.route_points.is_empty() or int(state.route_index) < 0 or int(state.route_index) >= state.route_points.size(): return _fail("movement.target_fact_route_mismatch", "巡逻目标事实引用无效路线索引。", "请丢弃损坏命令并重新提交。")
		if fact.route_id != request.route_id or fact.route_fingerprint != _route_fingerprint(state.route_points) or fact.resolved_position != state.route_points[state.route_index].position: return _fail("movement.target_fact_route_mismatch", "巡逻目标事实与路线点不一致。", "请丢弃损坏命令并重新提交。")
		if expected_target_phase not in ["moving", "waiting"]: return _fail("movement.target_fact_phase_mismatch", "巡逻目标阶段无效。", "请丢弃损坏命令并重新提交。")
		var wait_value := float(state.get("wait_remaining", -1.0))
		if (expected_target_phase == "moving" and wait_value != 0.0) or (expected_target_phase == "waiting" and wait_value <= 0.0): return _fail("movement.target_fact_phase_mismatch", "巡逻等待阶段与剩余时间不一致。", "请丢弃损坏命令并重新提交。")
	else:
		if not fact.route_id.is_empty() or not fact.route_fingerprint.is_empty() or int(fact.route_index) != 0 or not str(state.get("patrol_stage", "")).is_empty() or float(state.get("wait_remaining", 0.0)) != 0.0: return _fail("movement.target_fact_route_mismatch", "非巡逻命令包含路线目标事实。", "请丢弃损坏命令并重新提交。")
		if request.kind == "direct" and fact.resolved_position != request.target_position: return _fail("movement.target_fact_target_mismatch", "直达目标事实与请求位置不一致。", "请丢弃损坏命令并重新提交。")
		if request.kind == "anchor":
			var anchor_result := semantic_registry.resolve_anchor(request.map_id, request.anchor_id)
			if not anchor_result.ok or fact.resolved_position != anchor_result.anchor.position: return _fail("movement.target_fact_target_mismatch", "锚点目标事实与SemanticMap不一致。", "请丢弃损坏命令并重新提交。")
		if request.kind == "direction" and fact.resolved_position != Vector2.ZERO: return _fail("movement.target_fact_target_mismatch", "方向移动不得携带游离位置目标。", "请丢弃损坏命令并重新提交。")
	return {"ok": true, "fact": fact}

func _route_fingerprint(points: Array) -> String:
	return JSON.stringify(points, "", true, true).sha256_text()

func _normalize_json_safe_integer(value: Variant, field: String) -> Dictionary:
	if typeof(value) == TYPE_INT: return {"ok": true, "value": int(value)}
	if typeof(value) != TYPE_FLOAT: return _fail("movement.snapshot_json_integer_type_invalid", "JSON移动快照的%s类型错误。" % field, "只接受JSON number表示的安全整数。")
	var numeric := float(value)
	if not is_finite(numeric) or numeric != floor(numeric) or numeric <= -JSON_SAFE_INTEGER_EXCLUSIVE_BOUND or numeric >= JSON_SAFE_INTEGER_EXCLUSIVE_BOUND: return _fail("movement.snapshot_json_integer_invalid", "JSON移动快照的%s不是安全整数。" % field, "请拒绝小数、非有限值或超出JSON安全整数范围的索引。")
	return {"ok": true, "value": int(numeric)}

func _validate_active_command_for_snapshot(state: Dictionary, actor_id: String, command_id: String) -> Dictionary:
	var state_numeric := _validate_command_numeric(state)
	if not state_numeric.ok: return _fail("movement.snapshot_command_numeric_invalid", "活动移动命令包含无效数值，不能生成快照。", "请丢弃损坏命令并重新提交。", {"contributor_code": str(state_numeric.get("code", ""))})
	if typeof(state.get("command_id", null)) != TYPE_STRING or typeof(state.get("actor_id", null)) != TYPE_STRING or typeof(state.get("owner_id", null)) != TYPE_STRING or typeof(state.get("source", null)) != TYPE_STRING or typeof(state.get("phase", null)) != TYPE_STRING:
		return _fail("movement.snapshot_command_field_type_invalid", "活动移动命令身份字段类型错误，不能生成快照。", "请丢弃损坏命令并重新提交。")
	if str(state.command_id) != command_id or str(state.actor_id) != actor_id or str(_active_by_actor.get(actor_id, "")) != command_id:
		return _fail("movement.snapshot_command_identity_mismatch", "活动移动命令、角色与active映射不一致。", "请丢弃损坏命令并重新提交。")
	if not _actors.has(actor_id) or not state.get("actor", null) is Node2D or state.actor != _actors[actor_id].node:
		return _fail("movement.snapshot_command_actor_mismatch", "活动移动命令与注册角色实例不一致。", "请重新装配角色并提交移动。")
	var actor_numeric := _validate_actor_numeric(state.actor)
	if not actor_numeric.ok: return _fail("movement.snapshot_actor_numeric_invalid", "角色运动数值无效，不能生成快照。", "请先恢复有效角色运动状态。", {"contributor_code": str(actor_numeric.get("code", ""))})
	if not state.get("request", null) is GMMovementRequest:
		return _fail("movement.snapshot_request_type_invalid", "活动移动命令缺少规范请求事实。", "请丢弃损坏命令并重新提交。")
	var request: GMMovementRequest = state.request
	var frozen := _freeze_request(request)
	if not frozen.ok: return _fail("movement.snapshot_request_invalid", "活动移动请求未通过完整验证，不能生成快照。", "请丢弃损坏命令并重新提交。", {"contributor_code": str(frozen.get("code", ""))})
	var request_data: Dictionary = frozen.request_data
	if request_data != request.to_dict(): return _fail("movement.snapshot_request_noncanonical", "活动移动请求不是规范内部事实。", "请丢弃损坏命令并重新提交。")
	if request.actor_id != actor_id or request.owner_id != str(state.owner_id) or request.source != str(state.source):
		return _fail("movement.snapshot_request_identity_mismatch", "活动移动请求与命令身份、owner或来源不一致。", "请丢弃损坏命令并重新提交。")
	if str(state.fingerprint) != request.fingerprint(): return _fail("movement.snapshot_fingerprint_mismatch", "活动移动请求与提交指纹不一致。", "请丢弃损坏命令并重新提交。")
	if typeof(state.get("terminal", null)) != TYPE_BOOL or bool(state.terminal) or not state.get("result", null) is Dictionary or not state.result.is_empty():
		return _fail("movement.snapshot_command_terminal_invalid", "活动移动命令包含终态或结果污染，不能生成快照。", "请丢弃损坏命令并重新提交。")
	var expected_phases := {"direct": "moving", "anchor": "moving", "direction": "direction", "follow": "following", "patrol": "patrolling"}
	if not expected_phases.has(request.kind) or str(state.phase) != str(expected_phases[request.kind]): return _fail("movement.snapshot_request_phase_mismatch", "活动移动请求类型与命令阶段不一致。", "请丢弃损坏命令并重新提交。")
	var preflight_result := preflight(request, state.actor)
	if not preflight_result.ok: return _fail("movement.snapshot_request_preflight_failed", "活动移动请求当前无法通过完整预检，不能生成快照。", "请修复请求引用或角色状态后重试。", {"contributor_code": str(preflight_result.get("code", ""))})
	if request.kind == "patrol":
		var map_result: Dictionary = semantic_registry.resolve_map(request.map_id)
		var route_result: Dictionary = map_result.map.resolve_route(request.route_id) if map_result.ok else map_result
		if not route_result.ok or state.route_points != route_result.route.points: return _fail("movement.snapshot_route_fact_mismatch", "活动巡逻路线事实与当前请求解析结果不一致。", "请丢弃损坏命令并重新提交。")
	elif not state.route_points.is_empty() or int(state.route_index) != 0:
		return _fail("movement.snapshot_route_fact_mismatch", "非巡逻活动命令包含路线事实污染。", "请丢弃损坏命令并重新提交。")
	var target_fact_result := _validate_target_fact_relation(state, request)
	if not target_fact_result.ok: return _fail("movement.snapshot_target_fact_mismatch", "活动移动目标事实与请求、来源或路线不一致。", "请丢弃损坏命令并重新提交。", {"contributor_code": str(target_fact_result.get("code", ""))})
	return {"ok": true, "request_data": request_data, "target_fact_data": _target_fact_to_snapshot(target_fact_result.fact)}

func _actor_observations() -> Dictionary:
	var result: Dictionary = {}
	for actor_id in _actors:
		var record: Dictionary = _actors[actor_id]
		var node: Variant = record.get("node", null)
		result[actor_id] = {"actor_id": str(actor_id), "map_id": str(record.get("map_id", "")), "instance_valid": node is Node2D and is_instance_valid(node)}
	return result

func _command_observations() -> Dictionary:
	var result: Dictionary = {}
	for command_id in _commands: result[command_id] = _command_observation(_commands[command_id])
	return result

func _command_observation(state: Dictionary) -> Dictionary:
	var request_copy: GMMovementRequest = null
	if state.get("request", null) is GMMovementRequest:
		var copied := _freeze_request(state.request)
		if copied.ok: request_copy = copied.request
	return {"command_id": str(state.get("command_id", "")), "actor_id": str(state.get("actor_id", "")), "owner_id": str(state.get("owner_id", "")), "source": str(state.get("source", "")), "request": request_copy, "fingerprint": str(state.get("fingerprint", "")), "velocity": state.get("velocity", Vector2.ZERO), "facing": state.get("facing", Vector2.ZERO), "phase": str(state.get("phase", "")), "target": state.get("target", Vector2.ZERO), "target_fact": state.get("target_fact", {}).duplicate(true) if state.get("target_fact", null) is Dictionary else {}, "route_points": state.get("route_points", []).duplicate(true) if state.get("route_points", null) is Array else [], "route_index": state.get("route_index", -1), "patrol_stage": str(state.get("patrol_stage", "")), "wait_remaining": state.get("wait_remaining", null), "terminal": state.get("terminal", null), "result": state.get("result", {}).duplicate(true) if state.get("result", null) is Dictionary else {}}

func _validate_anchor_numeric(anchor: Variant) -> Dictionary:
	if not anchor is GMSemanticAnchor or not _vector_finite(anchor.position): return _fail("movement.semantic_numeric_invalid", "目标锚点位置必须是有限二维坐标。", "请修正SemanticMap锚点后重试。", {"field": "anchor.position"})
	return {"ok": true}

func _validate_route_numeric(route: Variant, terrain: GMMapResource = null) -> Dictionary:
	if not route is GMSemanticRoute: return _fail("movement.semantic_route_invalid", "巡逻路线资源类型无效。", "请修正SemanticMap路线后重试。")
	for index in route.points.size():
		var point: Variant = route.points[index]
		if not point is Dictionary or not point.get("position", null) is Vector2 or not _vector_finite(point.position): return _fail("movement.semantic_numeric_invalid", "巡逻路线点位置必须是有限二维坐标。", "请修正SemanticMap路线后重试。", {"field": "route.points[%d].position" % index})
		for numeric_field in ["speed", "wait"]:
			var raw: Variant = point.get(numeric_field, 1.0 if numeric_field == "speed" else 0.0)
			if typeof(raw) not in [TYPE_INT, TYPE_FLOAT]: return _fail("movement.semantic_numeric_type_invalid", "巡逻路线数值字段类型错误。", "请使用数值型路线参数。", {"field": "route.points[%d].%s" % [index, numeric_field]})
			if not is_finite(float(raw)): return _fail("movement.semantic_numeric_invalid", "巡逻路线数值字段必须为有限值。", "请移除NaN或Infinity后重试。", {"field": "route.points[%d].%s" % [index, numeric_field]})
			if numeric_field == "speed" and float(raw) <= 0.0: return _fail("movement.semantic_speed_invalid", "巡逻路线速度必须大于0。", "请修正路线速度。", {"field": "route.points[%d].speed" % index})
			if numeric_field == "wait" and float(raw) < 0.0: return _fail("movement.semantic_wait_invalid", "巡逻路线等待时间不能为负数。", "请修正路线等待时间。", {"field": "route.points[%d].wait" % index})
		if terrain != null:
			if terrain.tile_size.x <= 0 or terrain.tile_size.y <= 0: return _fail("movement.semantic_tile_size_invalid", "语义地图网格尺寸必须为正数。", "请修正任务08地图尺寸。")
			var cell_x: float = point.position.x / float(terrain.tile_size.x); var cell_y: float = point.position.y / float(terrain.tile_size.y)
			if not is_finite(cell_x) or not is_finite(cell_y) or absf(cell_x) >= 9.22e18 or absf(cell_y) >= 9.22e18: return _fail("movement.semantic_position_range_invalid", "巡逻路线坐标超出地图索引安全范围。", "请将路线点移入可表示的地图坐标范围。", {"field": "route.points[%d].position" % index})
	if terrain != null:
		for index in maxi(route.points.size() - 1, 0):
			var displacement: Vector2 = route.points[index + 1].position - route.points[index].position
			var distance := _stable_length(displacement) if _vector_finite(displacement) else INF
			var step_length := maxf(1.0, minf(terrain.tile_size.x, terrain.tile_size.y) * 0.5)
			if not is_finite(distance) or distance / step_length > 1000000.0: return _fail("movement.semantic_route_range_invalid", "巡逻路线段超出安全验证范围。", "请拆分极端跨度路线。", {"field": "route.points"})
	return {"ok": true}

func _vector_finite(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)

func _variant_vector_finite(value: Variant) -> bool:
	return value is Vector2 and _vector_finite(value)

func _stable_length(value: Vector2) -> float:
	var scale := maxf(absf(value.x), absf(value.y))
	if scale == 0.0: return 0.0
	var scaled := value / scale
	return scale * sqrt(scaled.x * scaled.x + scaled.y * scaled.y)

func _safe_normalized(value: Vector2) -> Vector2:
	var scale := maxf(absf(value.x), absf(value.y))
	if scale == 0.0: return Vector2.ZERO
	return (value / scale).normalized()

func _current_facing(actor: Node2D) -> Vector2:
	if "movement_facing" in actor: return actor.get("movement_facing")
	return Vector2.DOWN

func _apply_motion(actor: Node2D, next_position: Vector2, velocity: Vector2, facing: Vector2) -> void:
	actor.position = next_position
	if "movement_velocity" in actor: actor.set("movement_velocity", velocity)
	else: actor.set_meta("gm_movement_velocity", velocity)
	if facing.length_squared() > 0.000001:
		if "movement_facing" in actor: actor.set("movement_facing", facing.normalized())
		else: actor.set_meta("gm_movement_facing", facing.normalized())
	_apply_presentation_semantic(actor, velocity, facing)

func _validate_control_owner(actor: Node2D, request: GMMovementRequest) -> Dictionary:
	if not "control_router" in actor: return {"ok": true, "unchecked": true}
	var router: GMCharacterControlRouter = actor.get("control_router")
	if router == null or router.enabled_sources.is_empty(): return {"ok": true, "unchecked": true}
	if router.active_source() != request.source or router.selected_owner != request.owner_id:
		return _fail("movement.control_lost", "移动请求不再持有角色统一控制权。", "请先取得P14单一控制交接，再重新提交移动请求。", {"active_source": router.active_source(), "active_owner": router.selected_owner, "requested_source": request.source, "requested_owner": request.owner_id})
	return {"ok": true}

func _apply_presentation_semantic(actor: Node2D, velocity: Vector2, facing: Vector2) -> void:
	if not actor is GMCharacterRuntime2D: return
	var runtime := actor as GMCharacterRuntime2D
	if runtime.presenter == null or runtime.presenter.visual_set == null: return
	var semantic := &"move" if velocity.length_squared() > 0.000001 else &"idle"
	var direction_name := _direction_name(facing if facing.length_squared() > 0.000001 else runtime.movement_facing)
	if runtime.presenter.semantic == semantic and runtime.presenter.direction == direction_name: return
	runtime.presenter.play_semantic_action(semantic, direction_name)

func _direction_name(facing: Vector2) -> StringName:
	if absf(facing.x) > absf(facing.y): return &"right" if facing.x >= 0.0 else &"left"
	return &"down" if facing.y >= 0.0 else &"up"

func _wrap(failure: Dictionary, fix_zh: String) -> Dictionary:
	var result := failure.duplicate(true); result["reason_zh"] = str(result.get("error_zh", result.get("reason_zh", "移动预检失败。"))); result["fix_zh"] = fix_zh; return result

func _fail(code: String, reason_zh: String, fix_zh: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": reason_zh, "reason_zh": reason_zh, "fix_zh": fix_zh, "details": details}
