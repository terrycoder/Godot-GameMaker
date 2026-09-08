class_name GMPlayerShellCameraProfile
extends Resource

## One dimension-neutral P25 camera contract.  2D Camera2D and the existing
## Planar3D GMCameraRig3D are projections of this same authored profile.

const SCHEMA := "gm.player_shell.camera_profile.v1"
const CAMERA_PROFILE_3D_PATH := "res://gm_adapters/spatial3d/gm_camera_profile_3d.gd"

@export var profile_id := "gm.camera.profile.p25.shell"
@export var display_name_zh := "玩家外壳固定正交相机"
@export var orthographic_size := 1088.0
@export var zoom := 1.0
@export var min_zoom := 0.75
@export var max_zoom := 1.5
@export var fixed_rotation_degrees := Vector3(-55.0, -45.0, 0.0)
@export var bounds := Rect2(0.0, 0.0, 1088.0, 640.0)
@export var look_ahead := Vector2.ZERO

func validate() -> Dictionary:
	if profile_id.strip_edges().is_empty(): return _failure("camera.profile_id_missing", "玩家外壳相机Profile缺少稳定ID。")
	if orthographic_size <= 0.0 or not is_finite(orthographic_size): return _failure("camera.profile_size_invalid", "玩家外壳相机视图尺寸必须是正的有限数值。")
	if zoom <= 0.0 or min_zoom <= 0.0 or max_zoom < min_zoom or zoom < min_zoom or zoom > max_zoom:
		return _failure("camera.profile_zoom_invalid", "玩家外壳相机缩放范围无效。")
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0: return _failure("camera.profile_bounds_invalid", "玩家外壳相机边界必须有面积。")
	return {"ok": true, "code": "camera.profile.valid", "profile_id": profile_id}

func to_planar_3d():
	var profile_script: Script = load(CAMERA_PROFILE_3D_PATH)
	if profile_script == null: return null
	var result = profile_script.new()
	result.profile_id = profile_id
	result.display_name_zh = display_name_zh
	result.orthographic = true
	result.orthographic_size = orthographic_size / 32.0
	result.zoom = zoom
	result.min_zoom = min_zoom
	result.max_zoom = max_zoom
	result.fixed_rotation_degrees = fixed_rotation_degrees
	result.look_ahead = look_ahead / 32.0
	result.bounds = Rect2(bounds.position / 32.0, bounds.size / 32.0)
	return result

func to_native() -> Dictionary:
	return {
		"schema": SCHEMA,
		"profile_id": profile_id,
		"display_name_zh": display_name_zh,
		"orthographic_size": orthographic_size,
		"zoom": zoom,
		"min_zoom": min_zoom,
		"max_zoom": max_zoom,
		"fixed_rotation_degrees": {"x": fixed_rotation_degrees.x, "y": fixed_rotation_degrees.y, "z": fixed_rotation_degrees.z},
		"bounds": {"x": bounds.position.x, "y": bounds.position.y, "w": bounds.size.x, "h": bounds.size.y},
		"look_ahead": {"x": look_ahead.x, "y": look_ahead.y},
	}

func _failure(code: String, reason_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "error_zh": reason_zh}
