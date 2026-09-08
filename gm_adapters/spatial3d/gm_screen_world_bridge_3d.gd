class_name GMScreenWorldBridge3D
extends RefCounted

## Screen/world conversion is a pure query bridge: screen -> ray/plane ->
## Surface -> PlanarPosition.  It never guesses an origin or writes a fact.

const SPATIAL_DOMAIN := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")
const TARGET_REF := preload("res://gm_runtime/spatial_core/gm_spatial_target_ref.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const QUERY_RESULT := preload("res://gm_runtime/spatial_core/gm_spatial_query_result.gd")

var spatial_adapter: Object
var runtime_context: Object

func _init(p_adapter: Object = null, p_context: Object = null) -> void:
	spatial_adapter = p_adapter
	runtime_context = p_context

func screen_to_world(screen_position: Variant, context: Dictionary = {}) -> Dictionary:
	return _adapter_call("screen_to_world", [screen_position, context])

func world_to_screen(world_position: Variant, context: Dictionary = {}) -> Dictionary:
	return _adapter_call("world_to_screen", [world_position, context])

func screen_to_planar(screen_position: Variant, context: Dictionary = {}) -> Dictionary:
	var world := screen_to_world(screen_position, context)
	if not world.ok:
		return _blocked("spatial.screen.no_world_hit", "屏幕射线没有有效世界交点，未回退到原点。", {"world_query": world})
	var world_value: Variant = world.value.get("world_position", null)
	var logical := _adapter_call("world_to_logical", [world_value, context])
	if not logical.ok:
		return _blocked(str(logical.get("code", "spatial.screen.surface_unresolved")), str(logical.get("error_zh", "屏幕世界交点无法唯一解析到Surface。")), {"world_query": world, "logical_query": logical})
	var position: Dictionary = PLANAR_POSITION.from_native(logical.value.get("planar_position", null))
	if not position.ok:
		return _blocked("spatial.screen.planar_invalid", "屏幕世界交点没有有效PlanarPosition。", {"logical_query": logical})
	return QUERY_RESULT.success(SPATIAL_DOMAIN.PLANAR_3D, "gm.spatial.capability.screen_to_world", {"screen_position": _vector2_native(screen_position), "world_position": world_value}, {"planar_position": position.position.to_native(), "world_position": world_value, "surface_id": position.position.surface_id, "map_id": position.position.map_id})

func planar_to_screen(position_value: Variant, context: Dictionary = {}) -> Dictionary:
	var parsed := PLANAR_POSITION.from_native(position_value)
	if not parsed.ok:
		return _blocked("spatial.screen.planar_invalid", "PlanarPosition无效，无法映射到屏幕。", parsed)
	var world := _adapter_call("logical_to_world", [parsed.position, context])
	if not world.ok: return _blocked(str(world.get("code", "spatial.planar.world_unresolved")), str(world.get("error_zh", "PlanarPosition无法映射到世界。")), world)
	var screen := world_to_screen(world.value.world_position, context)
	if not screen.ok: return _blocked(str(screen.get("code", "spatial.world.screen_unresolved")), str(screen.get("error_zh", "世界位置无法映射到屏幕。")), screen)
	return QUERY_RESULT.success(SPATIAL_DOMAIN.PLANAR_3D, "gm.spatial.capability.world_to_screen", {"planar_position": parsed.position.to_native(), "world_position": world.value.world_position}, {"screen_position": screen.value.screen_position, "world_position": world.value.world_position, "planar_position": parsed.position.to_native()})

func screen_to_target(screen_position: Variant, context: Dictionary = {}) -> Dictionary:
	var projected := screen_to_planar(screen_position, context)
	if not projected.ok: return projected
	var position: Variant = projected.value.planar_position
	var target := TARGET_REF.from_planar_position(PLANAR_POSITION.from_native(position).position, SPATIAL_DOMAIN.PLANAR_3D)
	if not target.ok: return _blocked("spatial.screen.target_invalid", "屏幕位置未能生成稳定空间目标。", target)
	return QUERY_RESULT.success(SPATIAL_DOMAIN.PLANAR_3D, "gm.spatial.capability.screen_to_world", target.target.to_native(), {"planar_position": position, "world_position": projected.value.world_position, "target_ref": target.target.to_native()})

func world_to_planar(world_position: Variant, context: Dictionary = {}) -> Dictionary:
	var result := _adapter_call("world_to_logical", [world_position, context])
	if not result.ok: return _blocked(str(result.get("code", "spatial.world.surface_unresolved")), str(result.get("error_zh", "世界位置无法唯一解析到Surface。")), result)
	return result

func planar_to_world(position_value: Variant, context: Dictionary = {}) -> Dictionary:
	return _adapter_call("logical_to_world", [position_value, context])

func _adapter_call(method_name: String, arguments: Array = []) -> Dictionary:
	var raw: Variant = null
	if spatial_adapter != null and is_instance_valid(spatial_adapter) and spatial_adapter.has_method(method_name): raw = spatial_adapter.callv(method_name, arguments)
	elif runtime_context != null and is_instance_valid(runtime_context) and runtime_context.has_method("query_spatial"): raw = runtime_context.call("query_spatial", _capability_for(method_name), method_name, arguments)
	if raw is Dictionary: return raw
	return _blocked("spatial.bridge_adapter_missing", "屏幕世界桥缺少现有空间适配器。", {})

func _capability_for(method_name: String) -> String:
	return {"screen_to_world": "gm.spatial.capability.screen_to_world", "world_to_screen": "gm.spatial.capability.world_to_screen", "world_to_logical": "gm.spatial.capability.world_to_logical", "logical_to_world": "gm.spatial.capability.logical_to_world"}.get(method_name, "")

func _blocked(code: String, reason_zh: String, details: Dictionary) -> Dictionary:
	return QUERY_RESULT.blocked(code, reason_zh, SPATIAL_DOMAIN.PLANAR_3D, "gm.spatial.capability.screen_to_world", details)

func _vector2_native(value: Variant) -> Dictionary:
	if value is Vector2: return {"x": value.x, "y": value.y}
	if value is Dictionary: return {"x": float(value.get("x", 0.0)), "y": float(value.get("y", 0.0))}
	return {"x": 0.0, "y": 0.0}
