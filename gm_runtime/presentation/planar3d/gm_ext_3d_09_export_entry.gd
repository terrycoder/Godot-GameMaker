extends Node

const MODULE_INDEX_PATH := "res://gm_runtime/manifests/gm_ext_3d_09_manifest_index.tres"

func _ready() -> void:
	OS.set_environment("GM_MODULE_INDEX_PATH", MODULE_INDEX_PATH)
	var modules := GMModuleRegistry.resolve(PackedStringArray(["presentation.render_style_3d"]))
	var profile := GMCharacterVisualBudgetProfile.new()
	var manager := GMVisualBudgetManager3D.new()
	add_child(manager)
	manager.set_process(false)
	var configured := manager.configure(profile)
	var camera := Camera3D.new()
	add_child(camera)
	var visual := GMCharacterVisual3D.new()
	add_child(visual)
	var registered := manager.register_character("gm.actor.ext09.export", visual)
	var updated := manager.update_visuals(1.0 / 60.0, camera)
	var before_failure := manager.snapshot()
	var rejected := manager.update_visuals(-1.0, camera)
	var unloaded := manager.snapshot()
	manager.unload()
	var report := {
		"event": "GM_EXT_3D_09_EXPORT_SENTINEL",
		"ok": modules.get("ok", false) and configured.get("ok", false) and registered.get("ok", false) and updated.get("ok", false) and not rejected.get("ok", true) and before_failure == unloaded and manager.snapshot().is_empty(),
		"manifest": MODULE_INDEX_PATH,
		"visual_budget": before_failure,
		"invalid_input_atomic": before_failure == unloaded,
		"unloaded": manager.snapshot().is_empty(),
		"presentation_only": true,
		"direct_domain_writes": false,
	}
	var output_path := OS.get_environment("GM_EXT_3D_09_EXPORT_OUTPUT")
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "  ") + "\n")
			file.close()
	print("EXT09_EXPORT ", JSON.stringify(report))
	get_tree().quit(0 if report.ok else 309)
