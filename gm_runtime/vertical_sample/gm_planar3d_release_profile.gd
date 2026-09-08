@tool
class_name GMPlanar3DReleaseProfile
extends GMNeutralVerticalSampleProfile

const RELEASE_SCHEMA := "gm.planar3d.release_profile.v1"

@export_group("发布冻结")
@export var release_id := "gm.release.ext3d11.planar3d"
@export var release_version := "1.0.0"
@export var module_manifest_index := "res://gm_runtime/manifests/gm_ext_3d_11_manifest_index.tres"
@export var two_d_manifest_index := "res://gm_runtime/manifests/gm_ext_3d_11_2d_manifest_index.tres"
@export var enabled_entry_scene := "res://gm_runtime/vertical_sample/gm_ext_3d_11_entry.tscn"
@export var disabled_entry_scene := "res://gm_runtime/vertical_sample/gm_ext_3d_11_2d_entry.tscn"
@export var cache_schema := "gm.character.visual_compile_cache.v1"
@export var budget_profile_path := "res://gm_runtime/vertical_sample/gm_ext_3d_11_budget_profile.tres"

func validate() -> Dictionary:
	var checked := super.validate()
	if not checked.ok:
		return checked
	for value in [release_id, release_version]:
		if str(value).strip_edges().is_empty():
			return _failure("release.profile_identity_invalid", "Planar3D 发布Profile缺少冻结身份。")
	for path in [module_manifest_index, two_d_manifest_index, enabled_entry_scene, disabled_entry_scene, budget_profile_path]:
		if not str(path).begins_with("res://") or str(path).strip_edges() != str(path):
			return _failure("release.profile_path_invalid", "Planar3D 发布Profile包含非法res://入口。")
	if cache_schema != "gm.character.visual_compile_cache.v1":
		return _failure("release.profile_cache_schema_invalid", "Planar3D 发布Profile引用了未冻结的视觉缓存Schema。")
	return {"ok": true, "code": "release.profile_valid", "schema": RELEASE_SCHEMA}

func to_release_native() -> Dictionary:
	var value := to_native()
	value["release_schema"] = RELEASE_SCHEMA
	value["release_id"] = release_id
	value["release_version"] = release_version
	value["module_manifest_index"] = module_manifest_index
	value["two_d_manifest_index"] = two_d_manifest_index
	value["enabled_entry_scene"] = enabled_entry_scene
	value["disabled_entry_scene"] = disabled_entry_scene
	value["cache_schema"] = cache_schema
	value["budget_profile_path"] = budget_profile_path
	return value
