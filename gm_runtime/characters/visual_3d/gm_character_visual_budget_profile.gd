@tool
class_name GMCharacterVisualBudgetProfile
extends Resource

## Project-owned presentation limits. None of these values schedules world logic.
@export var display_name_zh: String = "角色视觉预算"
@export var near_distance: float = 12.0
@export var far_distance: float = 32.0
@export var hysteresis: float = 1.0
@export var max_visible_animated_characters: int = 30
@export var max_full_quality_characters: int = 10
@export var max_skinned_meshes: int = 60
@export var animation_update_budget: int = 20
@export var feature_module_budget: int = 20
@export var mid_sampling_hz: float = 12.0
@export var far_sampling_hz: float = 8.0
@export var animation_budget_ms: float = 4.0
@export var frame_warning_ms: float = 33.4
@export var world_viewport_resolution: Vector2i = Vector2i(640, 360)

func validate() -> Dictionary:
	var errors: Array[Dictionary] = []
	for field in ["near_distance", "far_distance", "mid_sampling_hz", "far_sampling_hz", "animation_budget_ms", "frame_warning_ms"]:
		if not is_finite(float(get(field))) or float(get(field)) <= 0.0:
			errors.append(_issue(field, "必须为有限正数。"))
	if not is_finite(hysteresis) or hysteresis < 0.0 or near_distance + hysteresis * 2.0 >= far_distance:
		errors.append(_issue("hysteresis", "滞回范围必须非负，且近远距离之间留有间隔。"))
	if far_sampling_hz > mid_sampling_hz: errors.append(_issue("far_sampling_hz", "远景采样率不能高于中景。"))
	for field in ["mid_sampling_hz", "far_sampling_hz"]:
		if float(get(field)) not in [8.0, 10.0, 12.0, 15.0]: errors.append(_issue(field, "采样率须为既有姿态合同支持的8、10、12或15。"))
	for field in ["max_visible_animated_characters", "max_full_quality_characters", "max_skinned_meshes", "animation_update_budget", "feature_module_budget"]:
		if int(get(field)) < 0: errors.append(_issue(field, "预算不能为负数；零表示关闭对应表现质量。"))
	if max_full_quality_characters > max_visible_animated_characters:
		errors.append(_issue("max_full_quality_characters", "完整质量角色数不能超过可动画角色数。"))
	if world_viewport_resolution.x <= 0 or world_viewport_resolution.y <= 0:
		errors.append(_issue("world_viewport_resolution", "世界视口分辨率必须为正数。"))
	return {"ok": errors.is_empty(), "errors": errors, "code": "visual_budget.valid" if errors.is_empty() else "visual_budget.invalid"}

func _issue(field: String, message: String) -> Dictionary:
	return {"code": "visual_budget." + field, "field": field, "error_zh": "角色视觉预算：" + message}
