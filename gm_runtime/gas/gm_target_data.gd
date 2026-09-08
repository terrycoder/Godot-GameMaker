class_name GMTargetData
extends RefCounted

## 目标数据只保存业务身份、位置和可序列化上下文，不保存 NodePath。

const TYPE_NONE := "none"
const TYPE_ENTITY := "entity"
const TYPE_LOCATION := "location"
const TYPE_AREA := "area"
const TYPE_ROUTE := "route"

var target_type: String = TYPE_NONE
var target_business_id: String = ""
var target_scene_id: String = ""
var area_id: String = ""
var route_id: String = ""
var location: Vector2 = Vector2.ZERO
var payload: Dictionary = {}
var target_runtime_id: int = 0
var _target_ref: WeakRef

var target: Object:
	get:
		return _target_ref.get_ref() if _target_ref != null else null
	set(value):
		_target_ref = weakref(value) if value != null else null
		target_runtime_id = value.get_instance_id() if value != null and is_instance_valid(value) else 0

func _init(p_target: Object = null, p_location: Vector2 = Vector2.ZERO, p_payload: Dictionary = {}, p_target_type: String = "") -> void:
	target = p_target
	location = p_location
	payload = p_payload.duplicate(true)
	if not p_target_type.is_empty(): target_type = p_target_type
	elif p_target != null: target_type = TYPE_ENTITY
	if p_target != null:
		target_business_id = _read_stable_id(p_target)
		target_scene_id = _read_scene_id(p_target)

static func from_entity(entity: Object, business_id: String = "", p_payload: Dictionary = {}) -> GMTargetData:
	var data := GMTargetData.new(entity, Vector2.ZERO, p_payload, TYPE_ENTITY)
	if not business_id.is_empty(): data.target_business_id = business_id
	return data

static func from_location(p_location: Vector2, p_payload: Dictionary = {}) -> GMTargetData:
	return GMTargetData.new(null, p_location, p_payload, TYPE_LOCATION)

static func from_area(p_area_id: String, p_payload: Dictionary = {}) -> GMTargetData:
	var data := GMTargetData.new(null, Vector2.ZERO, p_payload, TYPE_AREA)
	data.area_id = p_area_id
	return data

static func from_route(p_route_id: String, p_payload: Dictionary = {}) -> GMTargetData:
	var data := GMTargetData.new(null, Vector2.ZERO, p_payload, TYPE_ROUTE)
	data.route_id = p_route_id
	return data

func is_entity() -> bool:
	return target_type == TYPE_ENTITY

func is_valid() -> bool:
	return validate().ok

func validate() -> Dictionary:
	match target_type:
		TYPE_NONE:
			return {"ok": true, "target_type": TYPE_NONE}
		TYPE_ENTITY:
			var current := target
			if current == null or not is_instance_valid(current):
				return {"ok": false, "code": "target.released", "reason_zh": "实体目标已释放或跨场景失效。", "target_type": target_type, "target_business_id": target_business_id, "target_runtime_id": target_runtime_id}
			return {"ok": true, "target_type": target_type, "target_business_id": target_business_id, "target_runtime_id": target_runtime_id}
		TYPE_LOCATION:
			return {"ok": true, "target_type": target_type, "location": location}
		TYPE_AREA:
			return {"ok": not area_id.strip_edges().is_empty(), "code": "target.area_missing" if area_id.strip_edges().is_empty() else "", "reason_zh": "区域目标缺少稳定区域 ID。" if area_id.strip_edges().is_empty() else "", "target_type": target_type, "area_id": area_id}
		TYPE_ROUTE:
			return {"ok": not route_id.strip_edges().is_empty(), "code": "target.route_missing" if route_id.strip_edges().is_empty() else "", "reason_zh": "路线目标缺少稳定路线 ID。" if route_id.strip_edges().is_empty() else "", "target_type": target_type, "route_id": route_id}
		_:
			return {"ok": false, "code": "target.type_invalid", "reason_zh": "未知目标类型：%s" % target_type}

func resolve(resolver: Variant) -> Dictionary:
	if not target_business_id.is_empty() and (target == null or not is_instance_valid(target)):
		var resolved: Variant = null
		if resolver is Callable and resolver.is_valid(): resolved = resolver.call(target_business_id, target_scene_id)
		elif resolver is Dictionary: resolved = resolver.get(target_business_id, null)
		if resolved != null and is_instance_valid(resolved):
			target = resolved
			target_runtime_id = resolved.get_instance_id()
			return {"ok": true, "resolved": true, "target_business_id": target_business_id, "target_runtime_id": target_runtime_id}
	return {"ok": is_valid(), "resolved": false, "validation": validate()}

func to_dict() -> Dictionary:
	return {
		"target_type": target_type,
		"target_id": target_runtime_id,
		"target_runtime_id": target_runtime_id,
		"target_business_id": target_business_id,
		"target_scene_id": target_scene_id,
		"area_id": area_id,
		"route_id": route_id,
		"location": location,
		"location_xy": {"x": location.x, "y": location.y},
		"payload": payload.duplicate(true),
		"has_live_target": target != null and is_instance_valid(target),
	}

static func from_dict(value: Dictionary) -> GMTargetData:
	var location_value: Variant = value.get("location", Vector2.ZERO)
	var p_location := Vector2.ZERO
	if location_value is Vector2: p_location = location_value
	elif location_value is Dictionary: p_location = Vector2(float(location_value.get("x", 0.0)), float(location_value.get("y", 0.0)))
	var data := GMTargetData.new(null, p_location, value.get("payload", {}), str(value.get("target_type", TYPE_NONE)))
	data.target_business_id = str(value.get("target_business_id", ""))
	data.target_scene_id = str(value.get("target_scene_id", ""))
	data.area_id = str(value.get("area_id", ""))
	data.route_id = str(value.get("route_id", ""))
	data.target_runtime_id = int(value.get("target_runtime_id", value.get("target_id", 0)))
	return data

func _read_stable_id(value: Object) -> String:
	if value.has_method("get_business_id"): return str(value.get_business_id())
	if value.has_method("get_gm_id"): return str(value.get_gm_id())
	if value is Node and value.has_meta("gm_id"): return str(value.get_meta("gm_id"))
	if value is Resource and not str(value.resource_name).is_empty(): return str(value.resource_name)
	return ""

func _read_scene_id(value: Object) -> String:
	if value is Node:
		var scene_root: Node = value.get_tree().current_scene if value.is_inside_tree() else null
		if scene_root != null: return str(scene_root.scene_file_path)
	return ""
