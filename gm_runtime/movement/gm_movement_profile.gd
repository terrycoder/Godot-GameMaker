@tool
class_name GMMovementProfile
extends Resource

@export_category("移动参数")
@export_range(1.0, 2000.0, 1.0, "suffix:px/s") var speed: float = 120.0
@export_range(1.0, 5000.0, 1.0, "suffix:px/s²") var acceleration: float = 480.0
@export_range(0.0, 256.0, 1.0, "suffix:px") var stop_distance: float = 4.0
@export_range(0.0, 512.0, 1.0, "suffix:px") var follow_distance: float = 24.0

@export_category("语义目标")
@export var map_id: String = ""
@export var anchor_id: String = ""
@export var follow_actor_id: String = ""
@export var patrol_route_id: String = ""
@export var patrol_loop: bool = true

@export_category("旅行交接（不创建SceneSession）")
@export var target_map_id: String = ""
@export var entry_anchor_id: String = ""
@export var exit_anchor_id: String = ""
@export var return_anchor_id: String = ""

func validate_profile() -> Dictionary:
	for pair in [["speed", speed], ["acceleration", acceleration], ["stop_distance", stop_distance], ["follow_distance", follow_distance]]:
		if not is_finite(float(pair[1])): return _fail("movement.profile_numeric_nonfinite", "移动配置“%s”必须是有限数值。" % pair[0], "请移除NaN或Infinity后重试。")
	if speed <= 0.0 or acceleration <= 0.0: return _fail("movement.profile_speed_invalid", "移动速度和加速度必须大于0。", "请在Inspector的“移动参数”中修正数值。")
	if stop_distance < 0.0 or follow_distance < 0.0: return _fail("movement.profile_distance_invalid", "停止距离和跟随距离不能为负数。", "请将距离设为0或正数。")
	if speed > 2000.0 or acceleration > 5000.0 or stop_distance > 256.0 or follow_distance > 512.0: return _fail("movement.profile_numeric_range_invalid", "移动配置数值超出正式控件业务范围。", "请将速度、加速度和距离调整到界面标示范围内。")
	if map_id.strip_edges().is_empty(): return _fail("movement.profile_map_missing", "移动配置缺少地图稳定ID。", "请在“语义目标”中填写map_id。")
	for pair in [["map_id", map_id], ["anchor_id", anchor_id], ["follow_actor_id", follow_actor_id], ["patrol_route_id", patrol_route_id], ["target_map_id", target_map_id], ["entry_anchor_id", entry_anchor_id], ["exit_anchor_id", exit_anchor_id], ["return_anchor_id", return_anchor_id]]:
		if not str(pair[1]).is_empty() and str(pair[1]) != str(pair[1]).strip_edges(): return _fail("movement.profile_id_format_invalid", "移动配置“%s”包含首尾空白，不能作为稳定ID。" % pair[0], "请移除稳定ID首尾空白后重试。")
	var travel_values := [target_map_id, entry_anchor_id, exit_anchor_id, return_anchor_id]
	var travel_count := 0
	for value in travel_values:
		if not str(value).is_empty(): travel_count += 1
	if travel_count not in [0, travel_values.size()]: return _fail("movement.profile_travel_incomplete", "旅行交接ID必须全部为空或全部填写。", "请同时填写目标地图、入口、出口与返回锚点。")
	return {"ok": true}

func request_data(kind: String, source: String, owner_id: String, actor_id: String) -> Dictionary:
	return {"schema": GMMovementRequest.SCHEMA, "kind": kind, "source": source, "owner_id": owner_id, "actor_id": actor_id, "map_id": map_id, "anchor_id": anchor_id, "target_actor_id": follow_actor_id, "route_id": patrol_route_id, "speed": speed, "acceleration": acceleration, "stop_distance": stop_distance, "follow_distance": follow_distance, "loop": patrol_loop, "target_map_id": target_map_id, "entry_anchor_id": entry_anchor_id, "exit_anchor_id": exit_anchor_id, "return_anchor_id": return_anchor_id}

func _fail(code: String, reason_zh: String, fix_zh: String = "请修正移动配置后重试。") -> Dictionary:
	return {"ok": false, "code": code, "error_zh": reason_zh, "reason_zh": reason_zh, "fix_zh": fix_zh}
