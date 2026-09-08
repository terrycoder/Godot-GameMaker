@tool
class_name GMRenderStyleProfile
extends GMContent

## EXT08 的声明式渲染风格 Profile。
##
## 这个 Resource 只保存可重开的参数值，不保存 Viewport、Node、材质实例或
## 其他运行时对象。运行时由 GMRenderStyleRuntime 原子地装载它的副本。

const CONTENT_TYPE_ID := "gm.presentation.render_style_profile"
const SCHEMA_VERSION := "gm.presentation.render_style_profile.v1"
const VALID_LIGHTING_MODELS := ["flat", "lambert", "toon"]
const VALID_SHADOW_MODES := ["none", "blob", "soft"]
const VALID_DITHER_PATTERNS := ["none", "bayer4", "blue_noise"]
const VALID_POSE_MODES := ["8", "10", "12", "15", "Smooth"]
const VALID_UPSCALE_FILTERS := ["nearest"]

@export_group("Material Mapping")
@export var material_mapping_id: String = "gm.material.mapping.neutral"

@export_group("Lighting")
@export var lighting_model: String = "toon"
@export_range(0.0, 4.0, 0.01) var light_intensity: float = 1.0
@export_range(0.0, 1.0, 0.01) var ambient_strength: float = 0.35
@export_range(0.0, 1.0, 0.01) var rim_light_strength: float = 0.0

@export_group("Outline")
@export var outline_enabled: bool = true
@export var outline_color: Color = Color(0.08, 0.07, 0.06, 1.0)
@export_range(0.0, 0.2, 0.001) var outline_width: float = 0.025

@export_group("Palette")
@export var palette_id: String = "gm.palette.neutral"
@export var palette_hexes: PackedStringArray = PackedStringArray(["#f4e7d0", "#7d9bb5", "#3f4652", "#b86b51"])
@export var palette_quantization_steps: int = 4

@export_group("Dither")
@export var dither_enabled: bool = false
@export var dither_pattern: String = "bayer4"
@export_range(0.0, 1.0, 0.01) var dither_strength: float = 0.2

@export_group("PostProcess")
@export var post_process_enabled: bool = false
@export var post_process_id: String = "none"
@export_range(0.0, 1.0, 0.01) var post_process_strength: float = 0.0

@export_group("Shadow")
@export var shadow_enabled: bool = true
@export var shadow_mode: String = "blob"
@export_range(0.0, 1.0, 0.01) var shadow_softness: float = 0.55
@export_range(0.0, 2.0, 0.01) var shadow_strength: float = 0.7

@export_group("Resolution")
@export var world_render_resolution: Vector2i = Vector2i(320, 180)
@export var ui_render_resolution: Vector2i = Vector2i(1100, 700)
@export var upscale_filter: String = "nearest"

@export_group("Pose Sampling")
@export var pose_sampling_profile_id: String = "gm.presentation.pose_sampling.neutral"
@export var pose_sampling_mode: String = "Smooth"
@export_range(0, 60, 1) var pose_sampling_rate: int = 0

func _init() -> void:
	content_type_id = CONTENT_TYPE_ID

func validate_style() -> Dictionary:
	var errors: Array[String] = []
	if material_mapping_id.strip_edges().is_empty(): errors.append("render_style.material_mapping_missing：Material Mapping ID不能为空。")
	if lighting_model not in VALID_LIGHTING_MODELS: errors.append("render_style.lighting_invalid：Lighting Model必须是flat、lambert或toon。")
	if not is_finite(light_intensity) or light_intensity < 0.0 or light_intensity > 4.0: errors.append("render_style.light_intensity_invalid：光照强度必须在0到4之间。")
	if not is_finite(ambient_strength) or ambient_strength < 0.0 or ambient_strength > 1.0: errors.append("render_style.ambient_invalid：环境光强度必须在0到1之间。")
	if not is_finite(rim_light_strength) or rim_light_strength < 0.0 or rim_light_strength > 1.0: errors.append("render_style.rim_invalid：轮廓光强度必须在0到1之间。")
	if not is_finite(outline_width) or outline_width < 0.0 or outline_width > 0.2: errors.append("render_style.outline_width_invalid：描边宽度超出范围。")
	if not is_finite(dither_strength) or dither_strength < 0.0 or dither_strength > 1.0: errors.append("render_style.dither_strength_invalid：抖动强度必须在0到1之间。")
	if dither_pattern not in VALID_DITHER_PATTERNS: errors.append("render_style.dither_pattern_invalid：Dither Pattern不受支持。")
	if not is_finite(post_process_strength) or post_process_strength < 0.0 or post_process_strength > 1.0: errors.append("render_style.post_process_strength_invalid：后处理强度必须在0到1之间。")
	if shadow_mode not in VALID_SHADOW_MODES: errors.append("render_style.shadow_mode_invalid：Shadow Profile不受支持。")
	if not is_finite(shadow_softness) or shadow_softness < 0.0 or shadow_softness > 1.0: errors.append("render_style.shadow_softness_invalid：阴影柔化必须在0到1之间。")
	if not is_finite(shadow_strength) or shadow_strength < 0.0 or shadow_strength > 2.0: errors.append("render_style.shadow_strength_invalid：阴影强度超出范围。")
	if not _valid_resolution(world_render_resolution, 16, 4096): errors.append("render_style.world_resolution_invalid：World Render Resolution必须在16到4096之间。")
	if not _valid_resolution(ui_render_resolution, 16, 8192): errors.append("render_style.ui_resolution_invalid：UI分辨率必须在16到8192之间。")
	if upscale_filter not in VALID_UPSCALE_FILTERS: errors.append("render_style.upscale_filter_invalid：正式世界放大只允许nearest。")
	if pose_sampling_mode not in VALID_POSE_MODES: errors.append("render_style.pose_sampling_mode_invalid：Pose Sampling必须是8、10、12、15或Smooth。")
	var expected_rate := 0 if pose_sampling_mode == "Smooth" else int(pose_sampling_mode)
	if pose_sampling_rate != expected_rate: errors.append("render_style.pose_sampling_rate_invalid：Pose Sampling速率必须与模式一致。")
	var identity_errors := GMContentValidator.validate_content(self, resource_path, {}, true)
	if not bool(identity_errors.get("ok", false)):
		for issue in identity_errors.get("errors_zh", []): errors.append(str(issue))
	return _result(errors, "render_style.valid", "Render Style Profile校验通过。")

func validate_profile() -> Dictionary:
	return validate_style()

func to_native() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"display_name_zh": display_name_zh,
		"content_id": content_id,
		"content_type_id": content_type_id,
		"tags": Array(tags),
		"content_version": content_version,
		"source": source,
		"deprecated": deprecated,
		"aliases": Array(aliases),
		"material_mapping_id": material_mapping_id,
		"lighting": {"model": lighting_model, "intensity": light_intensity, "ambient_strength": ambient_strength, "rim_light_strength": rim_light_strength},
		"outline": {"enabled": outline_enabled, "color": _color_native(outline_color), "width": outline_width},
		"palette": {"id": palette_id, "hexes": Array(palette_hexes), "quantization_steps": palette_quantization_steps},
		"dither": {"enabled": dither_enabled, "pattern": dither_pattern, "strength": dither_strength},
		"post_process": {"enabled": post_process_enabled, "id": post_process_id, "strength": post_process_strength},
		"shadow": {"enabled": shadow_enabled, "mode": shadow_mode, "softness": shadow_softness, "strength": shadow_strength},
		"resolution": {"world": {"x": world_render_resolution.x, "y": world_render_resolution.y}, "ui": {"x": ui_render_resolution.x, "y": ui_render_resolution.y}, "upscale_filter": upscale_filter},
		"pose_sampling": {"profile_id": pose_sampling_profile_id, "mode": pose_sampling_mode, "rate": pose_sampling_rate},
		"presentation_only": true,
		"domain_facts_written": false,
	}

func sections_snapshot() -> Dictionary:
	return {"Lighting": to_native().lighting, "Outline": to_native().outline, "Palette": to_native().palette, "Dither": to_native().dither, "PostProcess": to_native().post_process, "Shadow": to_native().shadow, "Resolution": to_native().resolution, "PoseSampling": to_native().pose_sampling}

func unload() -> Dictionary:
	return {"ok": true, "code": "render_style.profile_unloaded", "profile_id": content_id, "runtime_nodes_released": false, "domain_facts_written": false}

static func from_native(value: Variant) -> GMRenderStyleProfile:
	if not value is Dictionary: return null
	var profile := GMRenderStyleProfile.new()
	profile.display_name_zh = str(value.get("display_name_zh", profile.display_name_zh))
	profile.content_id = str(value.get("content_id", ""))
	profile.content_type_id = CONTENT_TYPE_ID
	profile.tags = PackedStringArray(value.get("tags", Array(profile.tags)))
	profile.content_version = str(value.get("content_version", profile.content_version))
	profile.source = str(value.get("source", profile.source))
	profile.deprecated = bool(value.get("deprecated", profile.deprecated))
	profile.aliases = PackedStringArray(value.get("aliases", Array(profile.aliases)))
	profile.material_mapping_id = str(value.get("material_mapping_id", profile.material_mapping_id))
	var lighting: Dictionary = value.get("lighting", {})
	profile.lighting_model = str(lighting.get("model", profile.lighting_model))
	profile.light_intensity = float(lighting.get("intensity", profile.light_intensity))
	profile.ambient_strength = float(lighting.get("ambient_strength", profile.ambient_strength))
	profile.rim_light_strength = float(lighting.get("rim_light_strength", profile.rim_light_strength))
	var outline: Dictionary = value.get("outline", {})
	profile.outline_enabled = bool(outline.get("enabled", profile.outline_enabled))
	profile.outline_color = _color_from_native(outline.get("color", {}), profile.outline_color)
	profile.outline_width = float(outline.get("width", profile.outline_width))
	var palette: Dictionary = value.get("palette", {})
	profile.palette_id = str(palette.get("id", profile.palette_id))
	profile.palette_hexes = PackedStringArray(palette.get("hexes", Array(profile.palette_hexes)))
	profile.palette_quantization_steps = int(palette.get("quantization_steps", profile.palette_quantization_steps))
	var dither: Dictionary = value.get("dither", {})
	profile.dither_enabled = bool(dither.get("enabled", profile.dither_enabled))
	profile.dither_pattern = str(dither.get("pattern", profile.dither_pattern))
	profile.dither_strength = float(dither.get("strength", profile.dither_strength))
	var post_process: Dictionary = value.get("post_process", {})
	profile.post_process_enabled = bool(post_process.get("enabled", profile.post_process_enabled))
	profile.post_process_id = str(post_process.get("id", profile.post_process_id))
	profile.post_process_strength = float(post_process.get("strength", profile.post_process_strength))
	var shadow: Dictionary = value.get("shadow", {})
	profile.shadow_enabled = bool(shadow.get("enabled", profile.shadow_enabled))
	profile.shadow_mode = str(shadow.get("mode", profile.shadow_mode))
	profile.shadow_softness = float(shadow.get("softness", profile.shadow_softness))
	profile.shadow_strength = float(shadow.get("strength", profile.shadow_strength))
	var resolution: Dictionary = value.get("resolution", {})
	var world: Dictionary = resolution.get("world", {})
	var ui: Dictionary = resolution.get("ui", {})
	profile.world_render_resolution = Vector2i(int(world.get("x", profile.world_render_resolution.x)), int(world.get("y", profile.world_render_resolution.y)))
	profile.ui_render_resolution = Vector2i(int(ui.get("x", profile.ui_render_resolution.x)), int(ui.get("y", profile.ui_render_resolution.y)))
	profile.upscale_filter = str(resolution.get("upscale_filter", profile.upscale_filter))
	var pose: Dictionary = value.get("pose_sampling", {})
	profile.pose_sampling_profile_id = str(pose.get("profile_id", profile.pose_sampling_profile_id))
	profile.pose_sampling_mode = str(pose.get("mode", profile.pose_sampling_mode))
	profile.pose_sampling_rate = int(pose.get("rate", profile.pose_sampling_rate))
	return profile

static func _valid_resolution(value: Vector2i, minimum: int, maximum: int) -> bool:
	return value.x >= minimum and value.y >= minimum and value.x <= maximum and value.y <= maximum

static func _color_native(value: Color) -> Dictionary:
	return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}

static func _color_from_native(value: Variant, fallback: Color) -> Color:
	if not value is Dictionary: return fallback
	return Color(float(value.get("r", fallback.r)), float(value.get("g", fallback.g)), float(value.get("b", fallback.b)), float(value.get("a", fallback.a)))

static func _result(errors: Array[String], success_code: String, success_message: String) -> Dictionary:
	return {"ok": errors.is_empty(), "code": success_code if errors.is_empty() else "render_style.invalid", "errors_zh": errors, "error_zh": success_message if errors.is_empty() else str(errors[0]), "failure_closed": true}
