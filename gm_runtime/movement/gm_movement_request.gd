class_name GMMovementRequest
extends RefCounted

const SCHEMA := "gm.movement.request.v1"
const KINDS := ["direction", "direct", "anchor", "follow", "patrol", "face", "cancel", "travel"]
const SOURCES := ["player", "ai", "script"]

var kind: String = ""
var source: String = ""
var owner_id: String = ""
var actor_id: String = ""
var map_id: String = ""
var anchor_id: String = ""
var target_actor_id: String = ""
var route_id: String = ""
var direction: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var speed: float = 120.0
var acceleration: float = 480.0
var stop_distance: float = 4.0
var follow_distance: float = 24.0
var loop: bool = true
var entry_anchor_id: String = ""
var exit_anchor_id: String = ""
var return_anchor_id: String = ""
var target_map_id: String = ""
var idempotency_key: String = ""

static func from_dict(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("movement.request_type_invalid", "移动请求类型错误，应为Dictionary。", "请从正式移动配置或统一适配器重新生成请求。")
	var data: Dictionary = value
	var required := ["schema", "kind", "source", "owner_id", "actor_id", "map_id"]
	for field in required:
		if not data.has(field):
			return _failure("movement.request_truncated", "移动请求缺少必要字段“%s”。" % field, "请补全请求后重试。", {"field": field})
		if typeof(data[field]) != TYPE_STRING:
			return _failure("movement.request_field_type_invalid", "移动请求字段“%s”类型错误，应为字符串。" % field, "请检查请求适配器的字段类型。", {"field": field, "expected_type": "String", "actual_type": type_string(typeof(data[field]))})
	if str(data.schema) != SCHEMA:
		return _failure("movement.request_schema_invalid", "移动请求schema不匹配。", "请使用gm.movement.request.v1重新生成请求。")
	var request := GMMovementRequest.new()
	request.kind = data.kind
	request.source = data.source
	request.owner_id = data.owner_id
	request.actor_id = data.actor_id
	request.map_id = data.map_id
	for field in ["anchor_id", "target_actor_id", "route_id", "entry_anchor_id", "exit_anchor_id", "return_anchor_id", "target_map_id", "idempotency_key"]:
		if data.has(field) and typeof(data[field]) != TYPE_STRING:
			return _failure("movement.request_field_type_invalid", "移动请求字段“%s”类型错误，应为字符串。" % field, "请检查请求适配器的字段类型。", {"field": field, "expected_type": "String", "actual_type": type_string(typeof(data[field]))})
		request.set(field, str(data.get(field, "")))
	for field in ["speed", "acceleration", "stop_distance", "follow_distance"]:
		if data.has(field) and typeof(data[field]) not in [TYPE_INT, TYPE_FLOAT]:
			return _failure("movement.request_field_type_invalid", "移动参数“%s”类型错误，应为数字。" % field, "请在移动配置中输入有效数值。", {"field": field, "expected_type": "number", "actual_type": type_string(typeof(data[field]))})
		request.set(field, float(data.get(field, request.get(field))))
	if data.has("loop") and typeof(data.loop) != TYPE_BOOL:
		return _failure("movement.request_field_type_invalid", "巡逻循环字段类型错误，应为布尔值。", "请使用正式复选框设置循环。", {"field": "loop"})
	request.loop = bool(data.get("loop", true))
	for vector_field in ["direction", "target_position"]:
		if data.has(vector_field):
			var parsed := _strict_vector2(data[vector_field], vector_field)
			if not parsed.ok: return parsed
			request.set(vector_field, parsed.value)
	var validation := request.validate()
	if not validation.ok: return validation
	return {"ok": true, "request": request}

func validate() -> Dictionary:
	if kind not in KINDS: return _failure("movement.kind_unknown", "未知移动类型：%s。" % kind, "请从正式类型列表选择移动方式。")
	if source not in SOURCES: return _failure("movement.source_unknown", "未知请求来源：%s。" % source, "请使用player、ai或script稳定值。")
	if owner_id.strip_edges().is_empty(): return _failure("movement.owner_missing", "移动请求缺少执行owner。", "请提供稳定owner标识后重试。")
	if actor_id.strip_edges().is_empty(): return _failure("movement.actor_missing", "移动请求缺少角色稳定ID。", "请选择已装配角色后重试。")
	if map_id.strip_edges().is_empty(): return _failure("movement.map_missing", "移动请求缺少地图稳定ID。", "请选择语义地图后重试。")
	for pair in [["speed", speed], ["acceleration", acceleration], ["stop_distance", stop_distance], ["follow_distance", follow_distance]]:
		if not is_finite(float(pair[1])):
			return _failure("movement.numeric_nonfinite", "移动参数“%s”必须是有限数值。" % pair[0], "请移除NaN或Infinity后重试。", {"field": pair[0]})
	if speed <= 0.0: return _failure("movement.speed_invalid", "移动速度必须大于0。", "请在移动参数中设置正数速度。")
	if acceleration <= 0.0: return _failure("movement.acceleration_invalid", "移动加速度必须大于0。", "请在移动参数中设置正数加速度。")
	if stop_distance < 0.0 or follow_distance < 0.0: return _failure("movement.distance_invalid", "停止距离与跟随距离不能为负数。", "请将距离设置为0或正数。")
	for pair in [["direction", direction], ["target_position", target_position]]:
		if not _vector_finite(pair[1]):
			return _failure("movement.vector_nonfinite", "移动向量“%s”包含非有限分量。" % pair[0], "请移除NaN或Infinity后重试。", {"field": pair[0]})
	match kind:
		"direction", "face":
			if direction.length_squared() <= 0.000001: return _failure("movement.direction_missing", "方向移动或朝向请求缺少有效方向。", "请输入非零方向。")
		"anchor":
			if anchor_id.strip_edges().is_empty(): return _failure("movement.anchor_missing", "语义移动缺少锚点稳定ID。", "请从SemanticMap选择锚点。")
		"follow":
			if target_actor_id.strip_edges().is_empty(): return _failure("movement.follow_target_missing", "跟随请求缺少目标角色稳定ID。", "请选择有效跟随目标。")
		"patrol":
			if route_id.strip_edges().is_empty(): return _failure("movement.route_missing", "巡逻请求缺少路线稳定ID。", "请从SemanticMap选择路线。")
		"travel":
			for pair in [["entry_anchor_id", entry_anchor_id], ["exit_anchor_id", exit_anchor_id], ["return_anchor_id", return_anchor_id], ["target_map_id", target_map_id]]:
				if str(pair[1]).strip_edges().is_empty(): return _failure("movement.travel_anchor_missing", "旅行交接缺少%s。" % pair[0], "请补全入口、出口、返回锚点与目标地图。", {"field": pair[0]})
	return {"ok": true}

func fingerprint() -> String:
	return JSON.stringify(to_dict(), "", true, true).sha256_text()

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "kind": kind, "source": source, "owner_id": owner_id, "actor_id": actor_id, "map_id": map_id, "anchor_id": anchor_id, "target_actor_id": target_actor_id, "route_id": route_id, "direction": {"x": direction.x, "y": direction.y}, "target_position": {"x": target_position.x, "y": target_position.y}, "speed": speed, "acceleration": acceleration, "stop_distance": stop_distance, "follow_distance": follow_distance, "loop": loop, "entry_anchor_id": entry_anchor_id, "exit_anchor_id": exit_anchor_id, "return_anchor_id": return_anchor_id, "target_map_id": target_map_id, "idempotency_key": idempotency_key}

static func _strict_vector2(value: Variant, field: String) -> Dictionary:
	if value is Vector2:
		if not _vector_finite(value): return _failure("movement.vector_nonfinite", "移动请求字段“%s”包含非有限分量。" % field, "请提供有限数值x/y。", {"field": field})
		return {"ok": true, "value": value}
	if not value is Dictionary or not value.has("x") or not value.has("y"):
		return _failure("movement.request_vector_invalid", "移动请求字段“%s”不是有效二维向量。" % field, "请提供数值x/y。", {"field": field})
	if typeof(value.x) not in [TYPE_INT, TYPE_FLOAT] or typeof(value.y) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure("movement.request_vector_invalid", "移动请求字段“%s”的x/y必须为数字。" % field, "请检查请求适配器。", {"field": field})
	var parsed := Vector2(float(value.x), float(value.y))
	if not _vector_finite(parsed): return _failure("movement.vector_nonfinite", "移动请求字段“%s”包含非有限分量。" % field, "请提供有限数值x/y。", {"field": field})
	return {"ok": true, "value": parsed}

static func _vector_finite(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)

static func _failure(code: String, reason_zh: String, fix_zh: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": reason_zh, "reason_zh": reason_zh, "fix_zh": fix_zh, "details": details}
