extends Control

const VERSION := preload("res://gm_runtime/gm_platform_version.tres")

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--gm-ext-3d-11"):
		OS.set_environment("GM_MODULE_INDEX_PATH", "res://gm_runtime/manifests/gm_ext_3d_11_manifest_index.tres")
		call_deferred("_open_release_entry", "res://gm_runtime/vertical_sample/gm_ext_3d_11_entry.tscn", 311)
		return
	if OS.get_cmdline_user_args().has("--gm-ext-3d-11-2d-only"):
		OS.set_environment("GM_MODULE_INDEX_PATH", "res://gm_runtime/manifests/gm_ext_3d_11_2d_manifest_index.tres")
		call_deferred("_open_release_entry", "res://gm_runtime/vertical_sample/gm_ext_3d_11_2d_entry.tscn", 312)
		return
	if OS.has_feature("p25_2d_only") or OS.get_cmdline_user_args().has("--p25-2d-only-check"):
		OS.set_environment("GM_MODULE_INDEX_PATH", "res://gm_runtime/manifests/p25_2d_only_manifest_index.tres")
		call_deferred("_open_release_entry", "res://gm_runtime/player_shell/gm_p25_2d_only_delivery.tscn", 325)
		return
	if OS.has_feature("gm_ext_3d_04"):
		call_deferred("_open_release_entry", "res://gm_runtime/map/3d/gm_scene_3d_export_entry.tscn", 248)
		return
	if OS.has_feature("gm_ext_3d_05"):
		call_deferred("_open_release_entry", "res://gm_runtime/characters/visual_3d/gm_ext_3d_05_export_entry.tscn", 251)
		return
	if OS.has_feature("gm_ext_3d_08"):
		call_deferred("_open_release_entry", "res://gm_runtime/presentation/planar3d/gm_ext_3d_08_export_entry.tscn", 308)
		return
	if OS.has_feature("p17_agent_planner"):
		call_deferred("_open_release_entry", "res://gm_runtime/agent_planner/gm_p17_export_entry.tscn", 157)
		return
	if OS.has_feature("p22_combat"):
		call_deferred("_open_release_entry", "res://gm_runtime/combat/gm_combat_export_entry.tscn", 172)
		return
	if OS.has_feature("task12_character_runtime"):
		call_deferred("_open_release_entry", "res://gm_runtime/characters/gm_task12_export_entry.tscn", 155)
		return
	if OS.has_feature("task11_characters"):
		call_deferred("_open_release_entry", "res://gm_runtime/characters/visual/gm_character_export_entry.tscn", 154)
		return
	if OS.has_feature("task10_objects"):
		call_deferred("_open_release_entry", "res://gm_runtime/objects/gm_object_export_entry.tscn", 151)
		return
	if OS.has_feature("task09_semantic"):
		call_deferred("_open_release_entry", "res://gm_runtime/map/semantic/gm_semantic_export_entry.tscn", 152)
		return
	if OS.has_feature("task08_map"):
		call_deferred("_open_release_entry", "res://gm_runtime/map/gm_map_export_entry.tscn", 153)
		return
	call_deferred("_open_release_entry", "res://gm_runtime/player_shell/gm_p25_player_shell.tscn", 325)
	return
	var label := Label.new()
	label.text = "GameMaker Platform\n最小运行时入口\nGodot %s · 平台 %s" % [VERSION.godot_baseline, VERSION.platform_version]
	label.position = Vector2(48, 48)
	label.add_theme_font_size_override("font_size", 24)
	add_child(label)

func _open_release_entry(scene_path: String, failure_code: int) -> void:
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		push_error("GM_RELEASE_ENTRY_FAILED scene=%s code=%d" % [scene_path, change_error])
		get_tree().quit(failure_code)
