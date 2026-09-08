class_name GMWorldViewportCompositor
extends RefCounted

## 只负责表现层的 World Viewport 管线：3D World -> 低分辨率 Viewport ->
## Nearest Upscale。UI 始终以原生分辨率渲染，窗口比例不参与规则计算。

const PIPELINE := ["3D World", "Low Resolution Viewport", "Nearest Upscale"]
var window_size: Vector2i = Vector2i.ZERO
var world_viewport_size: Vector2i = Vector2i.ZERO
var ui_canvas_size: Vector2i = Vector2i.ZERO
var nearest_upsample: bool = true
var configured: bool = false

func configure(p_window_size: Vector2i, p_world_size: Vector2i, p_ui_size: Vector2i = Vector2i.ZERO) -> Dictionary:
	if not _valid_size(p_window_size, 16, 16384): return _failure("world_viewport.window_invalid", "窗口分辨率无效，World Viewport未配置。")
	if not _valid_size(p_world_size, 16, 4096): return _failure("world_viewport.world_invalid", "World Viewport低分辨率无效，配置已关闭。")
	var resolved_ui := p_window_size if p_ui_size == Vector2i.ZERO else p_ui_size
	if not _valid_size(resolved_ui, 16, 16384): return _failure("world_viewport.ui_invalid", "UI原生分辨率无效，配置已关闭。")
	window_size = p_window_size
	world_viewport_size = p_world_size
	ui_canvas_size = resolved_ui
	nearest_upsample = true
	configured = true
	return {"ok": true, "code": "world_viewport.configured", "pipeline": PIPELINE.duplicate(), "window_size": _size_native(window_size), "world_viewport_size": _size_native(world_viewport_size), "ui_canvas_size": _size_native(ui_canvas_size), "upscale_filter": "nearest", "ui_native_resolution": true, "window_ratio_affects_rules": false}

func configure_from_profile(profile: GMRenderStyleProfile, p_window_size: Vector2i) -> Dictionary:
	if profile == null: return _failure("world_viewport.profile_missing", "Render Style Profile缺失，Viewport未配置。")
	var checked := profile.validate_style()
	if not bool(checked.get("ok", false)): return _failure("world_viewport.profile_invalid", str(checked.get("error_zh", "Profile无效。")))
	return configure(p_window_size, profile.world_render_resolution, profile.ui_render_resolution)

func build_world_viewport(parent: Node) -> Dictionary:
	if not configured: return _failure("world_viewport.not_configured", "World Viewport尚未配置。")
	if parent == null: return _failure("world_viewport.parent_missing", "Viewport父节点缺失，未创建运行时节点。")
	var viewport := SubViewport.new()
	viewport.name = "GMWorldLowResolutionViewport"
	viewport.size = world_viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	return {"ok": true, "code": "world_viewport.created", "viewport": viewport, "viewport_size": _size_native(world_viewport_size), "filter": "nearest", "ui_native_resolution": true}

func apply_to_viewport(viewport: SubViewport) -> Dictionary:
	if not configured: return _failure("world_viewport.not_configured", "World Viewport尚未配置。")
	if viewport == null: return _failure("world_viewport.viewport_missing", "目标Viewport缺失。")
	viewport.size = world_viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return {"ok": true, "code": "world_viewport.applied", "viewport_size": _size_native(world_viewport_size), "filter": "nearest"}

func pipeline_contract() -> Dictionary:
	return {"world": PIPELINE.duplicate(), "ui": ["UI Canvas", "Native Resolution"], "world_viewport_size": _size_native(world_viewport_size), "ui_canvas_size": _size_native(ui_canvas_size), "nearest_upsample": nearest_upsample, "window_ratio_affects_rules": false, "presentation_only": true}

func snapshot() -> Dictionary:
	return {"configured": configured, "window_size": _size_native(window_size), "world_viewport_size": _size_native(world_viewport_size), "ui_canvas_size": _size_native(ui_canvas_size), "nearest_upsample": nearest_upsample, "pipeline": pipeline_contract(), "contains_runtime_nodes": false, "domain_facts_written": false}

static func _valid_size(value: Vector2i, minimum: int, maximum: int) -> bool:
	return value.x >= minimum and value.y >= minimum and value.x <= maximum and value.y <= maximum

static func _size_native(value: Vector2i) -> Dictionary:
	return {"x": value.x, "y": value.y}

static func _failure(code: String, error_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": error_zh, "errors_zh": [error_zh], "failure_closed": true}
