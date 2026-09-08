@tool
class_name GMCameraZoneConfig
extends Resource

@export var camera_id: StringName
@export var bounds: Rect2
@export var zoom: Vector2 = Vector2.ONE
@export_enum("lock_on", "smooth_follow", "room_center") var follow_mode: String = "smooth_follow"
@export var target_role_id: StringName = &"player"
@export var priority: int = 0
@export var pixel_align_placeholder: bool = true

func validate_definition() -> Dictionary:
	var errors: Array[Dictionary] = []
	if str(camera_id).strip_edges().is_empty(): errors.append(_error("semantic.camera_id_missing", "相机区ID不能为空", "camera_id"))
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0: errors.append(_error("semantic.camera_bounds_invalid", "Camera2D边界必须大于零", "bounds"))
	if zoom.x <= 0.0 or zoom.y <= 0.0: errors.append(_error("semantic.camera_zoom_invalid", "相机缩放必须大于零", "zoom"))
	if str(target_role_id).strip_edges().is_empty(): errors.append(_error("semantic.camera_target_missing", "相机区缺少目标角色", "target_role_id"))
	return {"ok": errors.is_empty(), "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh), "camera_id": str(camera_id)}

func contains_point(world_position: Vector2) -> bool:
	return bounds.has_point(world_position)

func apply_to(camera: Camera2D) -> Dictionary:
	if camera == null: return {"ok": false, "code": "semantic.camera_node_missing", "error_zh": "没有可配置的Camera2D"}
	var validation := validate_definition()
	if not validation.ok: return {"ok": false, "code": "semantic.camera_invalid", "errors": validation.errors}
	camera.limit_left = floori(bounds.position.x)
	camera.limit_top = floori(bounds.position.y)
	camera.limit_right = ceili(bounds.end.x)
	camera.limit_bottom = ceili(bounds.end.y)
	camera.zoom = zoom
	camera.position_smoothing_enabled = follow_mode == "smooth_follow"
	return {"ok": true, "camera_id": str(camera_id), "pixel_align_placeholder": pixel_align_placeholder}

func _error(code: String, message: String, field: String) -> Dictionary:
	return {"code": code, "error_zh": message, "field": field, "object_id": str(camera_id)}
