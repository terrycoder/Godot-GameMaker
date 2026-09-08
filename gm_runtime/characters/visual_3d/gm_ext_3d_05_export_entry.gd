extends Node

## Minimal runtime proof for the character visual module.  It only constructs
## derived presentation nodes from the existing content library.

func _ready() -> void:
	var result := {"event": "GM_EXT_3D_05_ENABLED_RUNTIME_SENTINEL", "ok": false, "godot": Engine.get_version_info().string, "module": "character.visual_3d", "domain_facts_written": false}
	var library := GMContentLibrary.new()
	var scan := library.scan(["res://gm_runtime/content/3d"])
	result["content_scan"] = {"ok": scan.ok, "committed": scan.committed, "count": scan.stats.get("content_count", 0), "issues": scan.issues}
	var recipe_resource = ResourceLoader.load("res://gm_runtime/content/3d/neutral/character_visual_recipe_neutral.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var recipe := recipe_resource as GMCharacterVisualRecipe
	var validator := GMCharacterAssetValidator.validate_recipe(recipe, library)
	result["validation"] = validator
	if scan.ok and recipe != null and validator.ok:
		var visual := GMCharacterVisual3D.new()
		visual.name = "NeutralCharacterVisual3D"
		add_child(visual)
		var configured := visual.configure(recipe, GMCharacterVisual3DResolver.new(library))
		var action := visual.play_semantic_action(&"locomotion.idle") if configured.ok else {"ok": false}
		var posture := visual.apply_posture() if configured.ok else {"ok": false}
		result["runtime"] = {"configured": configured, "action": action, "posture": posture, "snapshot": visual.snapshot()}
		result["ok"] = configured.ok and action.ok and posture.ok
	print(JSON.stringify(result))
	if OS.get_environment("GM_EXT_3D_05_RUNTIME_AUTO_QUIT") == "1": get_tree().quit(0 if result.ok else 251)
