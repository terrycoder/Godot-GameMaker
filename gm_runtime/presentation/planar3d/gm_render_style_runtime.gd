class_name GMRenderStyleRuntime
extends RefCounted

## EXT08 的唯一运行时协调器。它只接收/产生表现值，并把最终呈现交给P18。

var profile: GMRenderStyleProfile = null
var material_mapping: GMSemanticMaterialMapping = GMSemanticMaterialMapping.new()
var compositor: GMWorldViewportCompositor = GMWorldViewportCompositor.new()
var occlusion: GMOcclusionPresentation3D = GMOcclusionPresentation3D.new()
var sampling: GMAnimationSamplingProfile = GMAnimationSamplingProfile.new()
var pose_adapter: GMPoseSamplingAdapter = GMPoseSamplingAdapter.new()
var visual_adapter: GMVisualAsset3DAdapter = GMVisualAsset3DAdapter.new()
var loaded: bool = false

func configure_profile(candidate: GMRenderStyleProfile) -> Dictionary:
	if candidate == null: return _failure("render_style.profile_missing", "Render Style Profile缺失，配置未提交。")
	var checked := candidate.validate_style()
	if not bool(checked.get("ok", false)): return {"ok": false, "code": "render_style.profile_invalid", "error_zh": str(checked.get("error_zh", "Profile校验失败。")), "details": checked, "failure_closed": true}
	var next_profile := candidate.duplicate(true) as GMRenderStyleProfile
	if next_profile == null: return _failure("render_style.profile_copy_failed", "Render Style Profile无法复制，配置未提交。")
	var next_sampling := GMAnimationSamplingProfile.new()
	next_sampling.display_name_zh = "运行时Pose Sampling"
	next_sampling.content_id = next_profile.pose_sampling_profile_id
	next_sampling.sampling_mode = next_profile.pose_sampling_mode
	next_sampling.samples_per_cycle = next_profile.pose_sampling_rate
	var sampling_check := next_sampling.validate_sampling()
	if not bool(sampling_check.get("ok", false)): return {"ok": false, "code": "render_style.pose_sampling_invalid", "error_zh": str(sampling_check.get("error_zh", "Pose Sampling无效。")), "details": sampling_check, "failure_closed": true}
	profile = next_profile
	sampling = next_sampling
	loaded = true
	return {"ok": true, "code": "render_style.profile_configured", "profile": profile.to_native(), "sampling": sampling.to_native(), "atomic_commit": true, "domain_facts_written": false}

func load_profile(path: String) -> Dictionary:
	if path.strip_edges().is_empty(): return _failure("render_style.path_missing", "Profile路径不能为空。")
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null or not resource is GMRenderStyleProfile: return _failure("render_style.profile_load_failed", "Profile无法读取或类型不匹配。")
	return configure_profile(resource as GMRenderStyleProfile)

func configure_material_mapping(candidate: GMSemanticMaterialMapping) -> Dictionary:
	if candidate == null: return _failure("material_mapping.missing", "Material Mapping缺失。")
	var checked := candidate.validate()
	if not bool(checked.get("ok", false)): return {"ok": false, "code": "material_mapping.invalid", "error_zh": str(checked.get("error_zh", "Material Mapping校验失败。")), "details": checked, "failure_closed": true}
	material_mapping = GMSemanticMaterialMapping.new(candidate.mapping)
	material_mapping.mapping_id = candidate.mapping_id
	material_mapping.fallback_material_id = candidate.fallback_material_id
	return {"ok": true, "code": "material_mapping.configured", "mapping": material_mapping.to_native(), "atomic_commit": true}

func configure_resolution(window_size: Vector2i) -> Dictionary:
	if profile == null: return _failure("render_style.profile_missing", "尚未配置Render Style Profile。")
	return compositor.configure_from_profile(profile, window_size)

func resolve_material(semantic_kind: String, available_materials: Dictionary = {}) -> Dictionary:
	return material_mapping.resolve(semantic_kind, available_materials)

func set_occlusion_state(roof_active: bool, foreground_active: bool, cutaway: bool = false) -> Dictionary:
	return occlusion.set_view_state(roof_active, foreground_active, cutaway)

func evaluate_occlusion(layer: String) -> Dictionary:
	return occlusion.evaluate(layer)

func sample_pose(pose: Variant, logical_time: float, duration: float = 1.0) -> Dictionary:
	return pose_adapter.sample(pose, logical_time, sampling, duration)

func describe_visual_asset(asset_kind: String, asset_id: String, target_ref: String = "") -> Dictionary:
	return visual_adapter.describe(asset_kind, asset_id, target_ref)

func unload() -> Dictionary:
	var old_id := profile.content_id if profile != null else ""
	profile = null
	loaded = false
	compositor = GMWorldViewportCompositor.new()
	occlusion = GMOcclusionPresentation3D.new()
	sampling = GMAnimationSamplingProfile.new()
	return {"ok": true, "code": "render_style.runtime_unloaded", "profile_id": old_id, "loaded": false, "runtime_nodes_released": true, "domain_facts_written": false}

func presentation_contract() -> Dictionary:
	return {"owner": "P18.presentation", "presentation_only": true, "domain_facts_written": false, "collision_authority": false, "surface_authority": false, "logic_time_authority": false, "allowed_outputs": ["RenderStyle", "SemanticMaterial", "ViewportComposite", "OcclusionProjection", "PoseSample", "LightAsset"]}

func snapshot() -> Dictionary:
	return {"loaded": loaded, "profile": profile.to_native() if profile != null else {}, "material_mapping": material_mapping.to_native(), "world_viewport": compositor.snapshot(), "occlusion": occlusion.snapshot(), "sampling": sampling.to_native(), "visual_adapter": visual_adapter.snapshot(), "presentation_contract": presentation_contract(), "contains_runtime_nodes": false}

static func _failure(code: String, error_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": error_zh, "errors_zh": [error_zh], "failure_closed": true}
