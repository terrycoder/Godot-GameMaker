class_name GMOcclusionPresentation3D
extends RefCounted

## Occlusion 只投影到视觉层，不读取或修改碰撞、Surface、Fact 或 Save。

const LAYERS := ["BASE", "MID", "ROOF", "FOREGROUND"]
var roof_fade_enabled: bool = true
var foreground_fade_enabled: bool = true
var cutaway_enabled: bool = false
var roof_fade_alpha: float = 0.28
var foreground_fade_alpha: float = 0.42
var cutaway_alpha: float = 0.08
var roof_active: bool = false
var foreground_active: bool = false

func configure(p_roof_fade_alpha: float = 0.28, p_foreground_fade_alpha: float = 0.42, p_cutaway_alpha: float = 0.08) -> Dictionary:
	if not _valid_alpha(p_roof_fade_alpha) or not _valid_alpha(p_foreground_fade_alpha) or not _valid_alpha(p_cutaway_alpha): return _failure("occlusion.alpha_invalid", "遮挡透明度必须在0到1之间，配置已关闭。")
	roof_fade_alpha = p_roof_fade_alpha
	foreground_fade_alpha = p_foreground_fade_alpha
	cutaway_alpha = p_cutaway_alpha
	return {"ok": true, "code": "occlusion.configured", "layers": LAYERS.duplicate(), "presentation_only": true}

func set_view_state(p_roof_active: bool, p_foreground_active: bool, p_cutaway: bool = false) -> Dictionary:
	roof_active = p_roof_active
	foreground_active = p_foreground_active
	cutaway_enabled = p_cutaway
	return resolve_layers()

func evaluate(layer: String) -> Dictionary:
	if layer not in LAYERS: return _failure("occlusion.layer_invalid", "未知遮挡层：%s" % layer)
	var opacity := 1.0
	var mode := "visible"
	if layer == "ROOF" and roof_active:
		opacity = cutaway_alpha if cutaway_enabled else roof_fade_alpha
		mode = "cutaway" if cutaway_enabled else "roof_fade"
	elif layer == "FOREGROUND" and foreground_active:
		opacity = cutaway_alpha if cutaway_enabled else foreground_fade_alpha
		mode = "cutaway" if cutaway_enabled else "foreground_fade"
	return {"ok": true, "code": "occlusion.evaluated", "layer": layer, "visible": opacity > 0.0, "opacity": opacity, "mode": mode, "collision_preserved": true, "surface_preserved": true, "domain_facts_written": false, "presentation_only": true}

func resolve_layers() -> Dictionary:
	var rows: Array[Dictionary] = []
	for layer in LAYERS: rows.append(evaluate(layer))
	return {"ok": true, "code": "occlusion.layers_resolved", "layers": rows, "roof_fade": roof_active, "foreground_fade": foreground_active, "cutaway": cutaway_enabled, "collision_preserved": true, "domain_facts_written": false}

func apply_to_node(node: Node, layer: String) -> Dictionary:
	var result := evaluate(layer)
	if not bool(result.get("ok", false)): return result
	if node == null: return _failure("occlusion.node_missing", "呈现节点缺失，未应用遮挡投影。")
	# 只写呈现元数据；不触碰CollisionObject3D、Surface或领域组件。
	node.set_meta("gm_occlusion_layer", layer)
	node.set_meta("gm_occlusion_opacity", float(result.get("opacity", 1.0)))
	node.set_meta("gm_occlusion_mode", str(result.get("mode", "visible")))
	return result

func snapshot() -> Dictionary:
	return {"layers": LAYERS.duplicate(), "roof_fade_enabled": roof_fade_enabled, "foreground_fade_enabled": foreground_fade_enabled, "roof_active": roof_active, "foreground_active": foreground_active, "cutaway_enabled": cutaway_enabled, "roof_fade_alpha": roof_fade_alpha, "foreground_fade_alpha": foreground_fade_alpha, "cutaway_alpha": cutaway_alpha, "collision_preserved": true, "surface_preserved": true, "domain_facts_written": false, "presentation_only": true}

static func _valid_alpha(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 1.0

static func _failure(code: String, error_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": error_zh, "errors_zh": [error_zh], "failure_closed": true}
