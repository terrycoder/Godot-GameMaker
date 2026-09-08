@tool
class_name GMCameraProfile3D
extends Resource

## Stable camera configuration for Planar 3D.  Rotation is authored as a
## fixed value; runtime camera nodes are projections and never enter saves.

const SCHEMA := "gm.camera.profile.planar_3d.v1"
const NATIVE_FIELDS := ["schema", "schema_version", "profile_id", "display_name_zh", "orthographic", "orthographic_size", "zoom", "min_zoom", "max_zoom", "fixed_rotation_degrees", "follow_entity_id", "look_ahead", "bounds", "shake_amplitude", "shake_frequency", "shake_duration", "focus_duration", "focus_target"]

@export var profile_id: StringName = &"gm.camera.profile.planar3d.fixed"
@export var display_name_zh: String = "平面3D固定正交相机"
@export var orthographic: bool = true
@export_range(0.1, 4096.0, 0.1) var orthographic_size: float = 24.0
@export_range(0.01, 64.0, 0.01) var zoom: float = 1.0
@export_range(0.01, 64.0, 0.01) var min_zoom: float = 0.5
@export_range(0.01, 64.0, 0.01) var max_zoom: float = 4.0
@export var fixed_rotation_degrees: Vector3 = Vector3(-55.0, -45.0, 0.0)
@export var follow_entity_id: String = ""
@export var look_ahead: Vector2 = Vector2.ZERO
@export var bounds: Rect2 = Rect2(-100.0, -100.0, 200.0, 200.0)
@export_range(0.0, 1000.0, 0.01) var shake_amplitude: float = 0.0
@export_range(0.0, 1000.0, 0.01) var shake_frequency: float = 12.0
@export_range(0.0, 60.0, 0.01) var shake_duration: float = 0.0
@export_range(0.0, 60.0, 0.01) var focus_duration: float = 0.35
@export var focus_target: Dictionary = {}

func validate() -> Dictionary:
	var errors: Array[String] = []
	if str(profile_id).strip_edges().is_empty() or not _stable_id(str(profile_id)): errors.append("profile_id必须是稳定ID")
	if not orthographic: errors.append("Planar 3D相机必须保持正交投影")
	for pair in [["orthographic_size", orthographic_size], ["zoom", zoom], ["min_zoom", min_zoom], ["max_zoom", max_zoom], ["shake_amplitude", shake_amplitude], ["shake_frequency", shake_frequency], ["shake_duration", shake_duration], ["focus_duration", focus_duration]]:
		if not is_finite(float(pair[1])): errors.append("%s必须是有限数值" % pair[0])
	if orthographic_size <= 0.0: errors.append("正交视图尺寸必须大于0")
	if zoom <= 0.0 or min_zoom <= 0.0 or max_zoom < min_zoom or zoom < min_zoom or zoom > max_zoom: errors.append("缩放必须落在最小/最大缩放范围内")
	if shake_amplitude < 0.0 or shake_frequency < 0.0 or shake_duration < 0.0 or focus_duration < 0.0: errors.append("震动与聚焦参数不能为负数")
	if not _finite_vector3(fixed_rotation_degrees) or not _finite_vector2(look_ahead): errors.append("固定旋转与预读必须是有限数值")
	if not _finite_rect(bounds) or bounds.size.x <= 0.0 or bounds.size.y <= 0.0: errors.append("相机边界必须是有限且有面积的矩形")
	if not focus_target.is_empty():
		var target_check := PLANAR_POSITION.validate_native(focus_target)
		if not target_check.ok: errors.append("聚焦目标必须是稳定PlanarPosition")
	return {"ok": errors.is_empty(), "code": "camera.profile.valid" if errors.is_empty() else "camera.profile.invalid", "errors": errors, "errors_zh": errors.duplicate()}

func to_native() -> Dictionary:
	return {"schema": SCHEMA, "schema_version": 1, "profile_id": str(profile_id), "display_name_zh": display_name_zh, "orthographic": orthographic, "orthographic_size": orthographic_size, "zoom": zoom, "min_zoom": min_zoom, "max_zoom": max_zoom, "fixed_rotation_degrees": _vector3_native(fixed_rotation_degrees), "follow_entity_id": follow_entity_id, "look_ahead": _vector2_native(look_ahead), "bounds": _rect_native(bounds), "shake_amplitude": shake_amplitude, "shake_frequency": shake_frequency, "shake_duration": shake_duration, "focus_duration": focus_duration, "focus_target": focus_target.duplicate(true)}

static func from_native(value: Variant) -> Dictionary:
	if not value is Dictionary: return _failure("camera.profile.type_invalid", "相机Profile必须是纯Dictionary。")
	var source: Dictionary = value
	for field in NATIVE_FIELDS:
		if not source.has(field): return _failure("camera.profile.field_missing", "相机Profile缺少字段：%s。" % field)
	for key in source.keys():
		if not NATIVE_FIELDS.has(str(key)): return _failure("camera.profile.field_unknown", "相机Profile包含未知字段：%s。" % key)
	var profile := GMCameraProfile3D.new()
	profile.profile_id = str(source.profile_id)
	profile.display_name_zh = str(source.display_name_zh)
	profile.orthographic = bool(source.orthographic)
	profile.orthographic_size = float(source.orthographic_size)
	profile.zoom = float(source.zoom)
	profile.min_zoom = float(source.min_zoom)
	profile.max_zoom = float(source.max_zoom)
	var rotation := _parse_vector3(source.fixed_rotation_degrees)
	var look := _parse_vector2(source.look_ahead)
	var rect := _parse_rect(source.bounds)
	if not rotation.ok or not look.ok or not rect.ok: return _failure("camera.profile.vector_invalid", "相机Profile包含无效旋转、预读或边界。")
	profile.fixed_rotation_degrees = rotation.value
	profile.follow_entity_id = str(source.follow_entity_id)
	profile.look_ahead = look.value
	profile.bounds = rect.value
	profile.shake_amplitude = float(source.shake_amplitude)
	profile.shake_frequency = float(source.shake_frequency)
	profile.shake_duration = float(source.shake_duration)
	profile.focus_duration = float(source.focus_duration)
	profile.focus_target = source.focus_target.duplicate(true)
	var checked := profile.validate()
	return {"ok": true, "profile": profile, "value": profile.to_native()} if checked.ok else checked

func copy_profile() -> GMCameraProfile3D:
	return duplicate(true) as GMCameraProfile3D

static func default_profile() -> GMCameraProfile3D:
	return GMCameraProfile3D.new()

const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

static func _stable_id(value: String) -> bool:
	return PLANAR_POSITION.is_valid_stable_id(value)

static func _finite_vector2(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)

static func _finite_vector3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

static func _finite_rect(value: Rect2) -> bool:
	return _finite_vector2(value.position) and _finite_vector2(value.size)

static func _vector2_native(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}

static func _vector3_native(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}

static func _rect_native(value: Rect2) -> Dictionary:
	return {"x": value.position.x, "y": value.position.y, "w": value.size.x, "h": value.size.y}

static func _parse_vector2(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.has("x") or not value.has("y"): return {"ok": false}
	var result := Vector2(float(value.x), float(value.y))
	return {"ok": _finite_vector2(result), "value": result}

static func _parse_vector3(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.has("x") or not value.has("y") or not value.has("z"): return {"ok": false}
	var result := Vector3(float(value.x), float(value.y), float(value.z))
	return {"ok": _finite_vector3(result), "value": result}

static func _parse_rect(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.has("x") or not value.has("y") or not value.has("w") or not value.has("h"): return {"ok": false}
	var result := Rect2(float(value.x), float(value.y), float(value.w), float(value.h))
	return {"ok": _finite_rect(result), "value": result}

static func _failure(code: String, reason_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "error_zh": reason_zh}
