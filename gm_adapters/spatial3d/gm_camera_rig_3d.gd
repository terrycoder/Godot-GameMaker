class_name GMCameraRig3D
extends Node3D

## Runtime-only camera projection.  The rig consumes a stable camera Profile,
## applies fixed orthographic rotation and emits no domain facts.

var profile: GMCameraProfile3D
var camera: Camera3D
var follow_target: Node3D
var spatial_adapter: Object
var runtime_context: Object
var current_center_world: Vector3 = Vector3.ZERO
var focus_position: Variant = null
var _focus_remaining: float = 0.0
var _shake_remaining: float = 0.0
var _elapsed: float = 0.0
var _shake_seed: float = 0.0

const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

func _ready() -> void:
	if profile == null: profile = GMCameraProfile3D.default_profile()
	_ensure_camera()
	apply_profile()

func configure_profile(value: GMCameraProfile3D) -> Dictionary:
	if value == null: return {"ok": false, "code": "camera.profile_missing", "reason_zh": "相机Rig缺少Planar 3D Profile。"}
	var checked := value.validate()
	if not checked.ok: return checked
	profile = value.copy_profile()
	apply_profile()
	return {"ok": true, "profile_id": str(profile.profile_id), "orthographic": true, "fixed_rotation": true}

func set_profile(value: GMCameraProfile3D) -> Dictionary:
	return configure_profile(value)

func set_follow_target(target: Node3D) -> Dictionary:
	if target == null or not is_instance_valid(target): return {"ok": false, "code": "camera.follow_target_missing", "reason_zh": "相机跟随目标不存在。"}
	follow_target = target
	return {"ok": true, "follow_entity_id": str(target.get("stable_instance_id")) if "stable_instance_id" in target else ""}

func set_follow_position(position_value: Variant) -> Dictionary:
	var checked := _validate_camera_position(position_value, "camera.follow_position_invalid", "相机跟随位置必须是有效PlanarPosition。")
	if not checked.ok: return checked
	focus_position = checked.position.duplicate(true)
	return {"ok": true, "position": focus_position.duplicate(true)}

func focus(position_value: Variant, duration: float = -1.0) -> Dictionary:
	if not is_finite(duration) or (duration < 0.0 and not is_equal_approx(duration, -1.0)):
		return {"ok": false, "code": "camera.focus_duration_invalid", "reason_zh": "相机聚焦时长必须是-1或有限非负数值。"}
	var checked := _validate_camera_position(position_value, "camera.focus_target_invalid", "相机聚焦目标必须是有效PlanarPosition。")
	if not checked.ok: return checked
	var amount := profile.focus_duration if is_equal_approx(duration, -1.0) and profile != null else maxf(0.0, duration)
	if not is_finite(amount) or amount < 0.0:
		return {"ok": false, "code": "camera.focus_duration_invalid", "reason_zh": "相机Profile的聚焦时长必须是有限非负数值。"}
	focus_position = checked.position.duplicate(true)
	_focus_remaining = amount
	return {"ok": true, "focus_target": focus_position.duplicate(true), "duration": amount}

func add_shake(amplitude: float, duration: float, frequency: float = -1.0) -> Dictionary:
	if not is_finite(amplitude) or not is_finite(duration) or amplitude < 0.0 or duration < 0.0: return {"ok": false, "code": "camera.shake_invalid", "reason_zh": "相机震动参数必须是有限非负数值。"}
	if not is_finite(frequency) or (frequency < 0.0 and not is_equal_approx(frequency, -1.0)):
		return {"ok": false, "code": "camera.shake_frequency_invalid", "reason_zh": "相机震动频率必须是-1或有限非负数值。", "atomic": true}
	_shake_remaining = duration
	_shake_seed = float(Time.get_ticks_usec() % 100000) / 1000.0
	if profile != null:
		profile.shake_amplitude = amplitude
		profile.shake_frequency = maxf(0.0, frequency if frequency >= 0.0 else profile.shake_frequency)
	return {"ok": true, "amplitude": amplitude, "duration": duration}

func apply_profile() -> void:
	if profile == null: return
	_ensure_camera()
	rotation_degrees = profile.fixed_rotation_degrees
	if camera != null and is_instance_valid(camera):
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = profile.orthographic_size / maxf(profile.zoom, 0.0001)
		camera.rotation = Vector3.ZERO

func tick(delta: float) -> Dictionary:
	if not is_finite(delta) or delta < 0.0: return {"ok": false, "code": "camera.delta_invalid", "reason_zh": "相机推进时间必须是有限非负数值。"}
	if profile == null: profile = GMCameraProfile3D.default_profile()
	_ensure_camera()
	_elapsed += delta
	_focus_remaining = maxf(0.0, _focus_remaining - delta)
	_shake_remaining = maxf(0.0, _shake_remaining - delta)
	var target_world := _target_world()
	if not target_world.ok: return target_world
	var desired: Vector3 = target_world.value
	var alpha := 1.0 if _focus_remaining <= 0.0 else clampf(delta / maxf(profile.focus_duration, 0.0001), 0.0, 1.0)
	current_center_world = current_center_world.lerp(desired, alpha) if delta > 0.0 else current_center_world if current_center_world != Vector3.ZERO else desired
	var clamped := _clamp_world_center(current_center_world)
	current_center_world = clamped.value if clamped.ok else current_center_world
	var shake := Vector3.ZERO
	if _shake_remaining > 0.0 and profile.shake_amplitude > 0.0:
		var phase := (_elapsed + _shake_seed) * maxf(profile.shake_frequency, 0.0) * TAU
		shake = Vector3(sin(phase), 0.0, cos(phase * 1.17)) * profile.shake_amplitude
	global_position = current_center_world + shake
	rotation_degrees = profile.fixed_rotation_degrees
	if camera != null and is_instance_valid(camera): camera.size = profile.orthographic_size / maxf(profile.zoom, 0.0001)
	return {"ok": true, "center_world": _vector3_native(current_center_world), "fixed_rotation_degrees": _vector3_native(profile.fixed_rotation_degrees), "orthographic": true, "zoom": profile.zoom, "shake": _vector3_native(shake)}

func snapshot_state() -> Dictionary:
	return {"schema": "gm.camera.rig_state.v1", "profile": profile.to_native() if profile != null else {}, "center_world": _vector3_native(current_center_world), "focus_target": focus_position.duplicate(true) if focus_position is Dictionary else {}, "focus_remaining": _focus_remaining, "shake_remaining": _shake_remaining}

func _ensure_camera() -> void:
	if camera != null and is_instance_valid(camera): return
	camera = get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
		camera.owner = owner

func _target_world() -> Dictionary:
	if follow_target != null and is_instance_valid(follow_target):
		var value := follow_target.global_position
		return {"ok": true, "value": value + Vector3(profile.look_ahead.x, 0.0, profile.look_ahead.y)}
	if focus_position is Dictionary and spatial_adapter != null and is_instance_valid(spatial_adapter) and spatial_adapter.has_method("logical_to_world"):
		var projected: Dictionary = spatial_adapter.logical_to_world(focus_position)
		if projected.ok: return {"ok": true, "value": Vector3(float(projected.value.world_position.x), float(projected.value.world_position.y), float(projected.value.world_position.z))}
		return {"ok": false, "code": str(projected.get("code", "camera.focus_unresolved")), "reason_zh": str(projected.get("error_zh", "相机聚焦目标无法解析。"))}
	return {"ok": true, "value": current_center_world}

func _validate_camera_position(value: Variant, code: String, reason_zh: String) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "code": code, "reason_zh": reason_zh}
	var parsed := PLANAR_POSITION.from_native(value)
	if not parsed.ok:
		return {"ok": false, "code": code, "reason_zh": reason_zh, "details": parsed}
	var spatial := _camera_spatial_call("logical_to_world", [parsed.position, {}])
	if not spatial.ok:
		return {"ok": false, "code": code, "reason_zh": reason_zh, "details": spatial}
	return {"ok": true, "position": parsed.position.to_native()}

func _camera_spatial_call(method_name: String, arguments: Array) -> Dictionary:
	var raw: Variant = null
	if spatial_adapter != null and is_instance_valid(spatial_adapter) and spatial_adapter.has_method(method_name):
		raw = spatial_adapter.callv(method_name, arguments)
	elif runtime_context != null and is_instance_valid(runtime_context) and runtime_context.has_method("query_spatial"):
		raw = runtime_context.call("query_spatial", "gm.spatial.capability.logical_to_world", method_name, arguments)
	if raw is Dictionary: return raw
	return {"ok": false, "code": "camera.spatial_adapter_missing", "reason_zh": "相机缺少可验证Planar 3D空间适配器。"}

func _clamp_world_center(value: Vector3) -> Dictionary:
	if profile == null: return {"ok": true, "value": value}
	var bounds := profile.bounds
	return {"ok": true, "value": Vector3(clampf(value.x, bounds.position.x, bounds.end.x), value.y, clampf(value.z, bounds.position.y, bounds.end.y))}

func _vector3_native(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}
