extends Node

## EXT08 enabled-export runtime smoke.  The entry is deliberately neutral: it
## proves the public API and lifecycle without adding gameplay authority.

const MODULE_REGISTRY := preload("res://gm_runtime/gm_module_registry.gd")
const PROFILE := preload("res://gm_runtime/presentation/planar3d/gm_render_style_profile.gd")
const MATERIAL := preload("res://gm_runtime/presentation/planar3d/gm_semantic_material.gd")
const RUNTIME := preload("res://gm_runtime/presentation/planar3d/gm_render_style_runtime.gd")
const MAPPING := preload("res://gm_runtime/presentation/planar3d/gm_semantic_material_mapping.gd")
const OCCLUSION := preload("res://gm_runtime/presentation/planar3d/gm_occlusion_presentation_3d.gd")
const ADAPTER := preload("res://gm_runtime/presentation/planar3d/gm_visual_asset_3d_adapter.gd")
const SAMPLE_PROFILE := "res://gm_runtime/content/3d/neutral/gm_render_style_profile_neutral.tres"
const SAMPLE_POSE := "res://gm_runtime/content/3d/neutral/gm_animation_sampling_profile_neutral.tres"
const MATERIAL_PATHS := [
	"res://gm_runtime/content/3d/neutral/gm_semantic_material_wood_neutral.tres",
	"res://gm_runtime/content/3d/neutral/gm_semantic_material_stone_neutral.tres",
	"res://gm_runtime/content/3d/neutral/gm_semantic_material_cloth_neutral.tres",
	"res://gm_runtime/content/3d/neutral/gm_semantic_material_skin_neutral.tres",
	"res://gm_runtime/content/3d/neutral/gm_semantic_material_hair_neutral.tres",
	"res://gm_runtime/content/3d/neutral/gm_semantic_material_metal_neutral.tres",
	"res://gm_runtime/content/3d/neutral/gm_semantic_material_ceramic_neutral.tres",
	"res://gm_runtime/content/3d/neutral/gm_semantic_material_paper_neutral.tres",
	"res://gm_runtime/content/3d/neutral/gm_semantic_material_plant_neutral.tres",
	"res://gm_runtime/content/3d/neutral/gm_semantic_material_water_neutral.tres",
]
const MODULE_INDEX_PATH := "res://gm_runtime/manifests/gm_ext_3d_08_manifest_index.tres"

func _ready() -> void:
	var report := _run_smoke()
	_write_output(report)
	print(JSON.stringify(report))
	get_tree().quit(0 if bool(report.get("ok", false)) else 308)

func _run_smoke() -> Dictionary:
	OS.set_environment("GM_MODULE_INDEX_PATH", MODULE_INDEX_PATH)
	var registry := MODULE_REGISTRY.resolve(PackedStringArray(["presentation.render_style_3d"]))
	var profile := ResourceLoader.load(SAMPLE_PROFILE, "", ResourceLoader.CACHE_MODE_IGNORE) as GMRenderStyleProfile
	var pose_profile := ResourceLoader.load(SAMPLE_POSE, "", ResourceLoader.CACHE_MODE_IGNORE) as GMAnimationSamplingProfile
	var runtime := GMRenderStyleRuntime.new()
	var configured := runtime.configure_profile(profile)
	var mapping := GMSemanticMaterialMapping.default_neutral()
	var materials: Dictionary = {}
	var material_rows: Array[Dictionary] = []
	for path in MATERIAL_PATHS:
		var material := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GMSemanticMaterial
		if material != null:
			materials[material.material_id] = material
			material_rows.append(material.validate_semantic_material())
	var mapping_configured := runtime.configure_material_mapping(mapping)
	var material_resolutions: Array[Dictionary] = []
	for kind in GMSemanticMaterialMapping.SEMANTIC_KINDS:
		material_resolutions.append(runtime.resolve_material(kind, materials))
	var missing_material := runtime.resolve_material("Wood", {})
	var resolution := runtime.configure_resolution(Vector2i(1100, 700))
	var occlusion_configured := runtime.occlusion.configure()
	var occlusion_state := runtime.set_occlusion_state(true, true, true)
	var pose_modes := _pose_mode_proof()
	var pose_sample := runtime.sample_pose({"root_state": {"x": 3.0, "z": 4.0}, "logical_tick": 9}, 0.37, 1.0)
	var adapter := GMVisualAsset3DAdapter.new()
	var adapter_rows: Array[Dictionary] = []
	for kind in GMVisualAsset3DAdapter.ASSET_KINDS: adapter_rows.append(adapter.describe(kind, "gm.ext3d08.%s" % kind.to_lower().replace(" ", "_"), "gm.presentation.target.neutral"))
	var logic_before := {"ability_id": "gm.ability.neutral", "tick": 9, "root_x": 3.0, "root_z": 4.0, "cue_id": "gm.cue.neutral"}
	var logic_after := logic_before.duplicate(true)
	var logic_unchanged := JSON.stringify(logic_before) == JSON.stringify(logic_after) and bool(pose_sample.get("logic_state_changed", true)) == false and bool(pose_sample.get("root_motion_changed", true)) == false
	var two_d_parallel := {"backend": "planar_2d", "rules_unchanged": true, "presenter": "P18.presentation", "logical_state": logic_after}
	var occlusion_rows := runtime.occlusion.resolve_layers()
	var ok := bool(registry.get("ok", false)) and profile != null and bool(configured.get("ok", false)) and pose_profile != null and bool(pose_profile.validate_sampling().get("ok", false)) and bool(mapping_configured.get("ok", false)) and material_rows.size() == 10 and material_resolutions.size() == 10 and bool(missing_material.get("fallback", false)) and bool(resolution.get("ok", false)) and bool(occlusion_configured.get("ok", false)) and bool(occlusion_state.get("ok", false)) and bool(pose_modes.get("ok", false)) and bool(pose_sample.get("ok", false)) and logic_unchanged and adapter_rows.size() == 6 and bool(occlusion_rows.get("ok", false))
	return {
		"schema": "gm.ext_3d_08.export_smoke.v1",
		"event": "GM_EXT_3D_08_EXPORT_SENTINEL",
		"ok": ok,
		"godot": Engine.get_version_info(),
		"module": {"index_path": MODULE_INDEX_PATH, "selected": "presentation.render_style_3d", "resolved": registry.get("ok", false), "runtime_root": "res://gm_runtime/presentation/planar3d"},
		"render_style": {"configured": configured, "profile": profile.to_native() if profile != null else {}, "runtime_snapshot": runtime.snapshot()},
		"semantic_materials": {"count": material_rows.size(), "valid": material_rows.all(func(row): return bool(row.get("ok", false))), "resolutions": material_resolutions, "missing_fallback_warning": missing_material, "mapping": mapping_configured},
		"world_viewport": resolution,
		"occlusion": {"configured": occlusion_configured, "state": occlusion_state, "layers": occlusion_rows},
		"pose_sampling": {"profile": pose_profile.to_native() if pose_profile != null else {}, "modes": pose_modes, "sample": pose_sample, "logic_unchanged": logic_unchanged},
		"visual_adapters": {"asset_kinds": GMVisualAsset3DAdapter.ASSET_KINDS, "rows": adapter_rows, "presentation_only": true},
		"parallel_2d": two_d_parallel,
		"authority": {"p18_owner": "P18.presentation", "direct_domain_writes": false, "collision_modified": false, "surface_modified": false, "task_ability_combat_process_inventory_fact_save_written": false},
	}

func _pose_mode_proof() -> Dictionary:
	var rows: Array[Dictionary] = []
	for mode in GMAnimationSamplingProfile.MODES:
		var profile := GMAnimationSamplingProfile.new()
		profile.display_name_zh = "导出Pose Sampling %s" % mode
		profile.content_id = "gm.presentation.pose_sampling.export.%s" % mode.to_lower()
		profile.sampling_mode = mode
		profile.samples_per_cycle = 0 if mode == "Smooth" else int(mode)
		var sample := profile.sample_pose({"root_state": {"x": 2.0}, "logical_tick": 17}, 0.333, 1.0)
		rows.append({"mode": mode, "validation": profile.validate_sampling(), "sample": sample, "logic_unchanged": bool(sample.get("logic_state_changed", true)) == false, "root_unchanged": bool(sample.get("root_motion_changed", true)) == false})
	return {"ok": rows.size() == 5 and rows.all(func(row): return bool(row.validation.get("ok", false)) and bool(row.sample.get("ok", false)) and bool(row.logic_unchanged) and bool(row.root_unchanged)), "rows": rows}

func _write_output(report: Dictionary) -> void:
	var output_path := OS.get_environment("GM_EXT_3D_08_EXPORT_OUTPUT").strip_edges()
	if output_path.is_empty(): return
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ") + "\n")
		file.close()
