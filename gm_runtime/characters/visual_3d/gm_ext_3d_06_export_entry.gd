extends Node

## Minimal runtime/export probe for GM-EXT-3D-06.  Player and fixed NPC are
## deliberately assembled through the same GMCharacterAssembler3D API.

const LIBRARY_SCRIPT := preload("res://gm_runtime/content/gm_content_library.gd")
const RESOLVER_SCRIPT := preload("res://gm_runtime/characters/visual_3d/gm_character_visual_3d_resolver.gd")
const ASSEMBLER_SCRIPT := preload("res://gm_runtime/characters/visual_3d/gm_character_assembler_3d.gd")
const CACHE_SCRIPT := preload("res://gm_runtime/characters/visual_3d/gm_character_visual_compile_cache.gd")
const RECIPE_PATH := "res://gm_runtime/content/3d/neutral/character_visual_recipe_neutral.tres"

func _ready() -> void:
	var library := LIBRARY_SCRIPT.new()
	var scan: Dictionary = library.scan(PackedStringArray(["res://gm_runtime/content/3d"]))
	var recipe := ResourceLoader.load(RECIPE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	var resolver := RESOLVER_SCRIPT.new(library)
	var shared_cache := CACHE_SCRIPT.new()
	var player_parent := Node3D.new()
	player_parent.name = "PlayerVisualOwner"
	add_child(player_parent)
	var npc_parent := Node3D.new()
	npc_parent.name = "FixedNPCVisualOwner"
	add_child(npc_parent)
	var player_assembler := ASSEMBLER_SCRIPT.new(shared_cache)
	var npc_assembler := ASSEMBLER_SCRIPT.new(shared_cache)
	var player_result: Dictionary = player_assembler.assemble(player_parent, recipe, resolver, "player", "gm.actor.player.ext06") if recipe is GMCharacterVisualRecipe else {"ok": false, "code": "gm.ext3d06.recipe_missing"}
	var npc_result: Dictionary = npc_assembler.assemble(npc_parent, recipe, resolver, "npc", "gm.actor.npc.ext06") if recipe is GMCharacterVisualRecipe else {"ok": false, "code": "gm.ext3d06.recipe_missing"}
	var hide_result: Dictionary = player_assembler.set_body_hide("torso", true) if player_result.get("ok", false) else {"ok": false}
	var cache_result: Dictionary = player_assembler.compile_current() if player_result.get("ok", false) else {"ok": false}
	var player_snapshot := player_assembler.snapshot()
	var npc_snapshot := npc_assembler.snapshot()
	var api_methods: Array = GMCharacterAssembler3D.API_METHODS.duplicate()
	var shared_api: bool = player_result.get("api_methods", []) == npc_result.get("api_methods", []) and player_result.get("shared_assembler", false) and npc_result.get("shared_assembler", false)
	var ok: bool = bool(scan.get("committed", false)) and bool(player_result.get("ok", false)) and bool(npc_result.get("ok", false)) and shared_api and bool(hide_result.get("ok", false)) and bool(cache_result.get("ok", false)) and not bool(player_snapshot.get("visual", {}).get("domain_facts_written", true)) and not bool(npc_snapshot.get("visual", {}).get("domain_facts_written", true))
	var report := {
		"ok": ok,
		"event": "GM_EXT_3D_06_ENABLED_RUNTIME_SENTINEL",
		"module": "character.assembly_3d",
		"content_scan": {"committed": bool(scan.get("committed", false)), "entry_count": library.entries.size(), "registry": "GMContentLibrary"},
		"player": player_result,
		"npc": npc_result,
		"shared_player_npc_api": shared_api,
		"api_methods": api_methods,
		"body_hide": hide_result,
		"cache": cache_result,
		"player_snapshot": player_snapshot,
		"npc_snapshot": npc_snapshot,
		"domain_facts_written": false,
		"recipe_contains_runtime_nodes": false,
		"animation_copies_per_character": 0,
		"failure_closed": true,
	}
	print(JSON.stringify(report))
	var output_path: String = OS.get_environment("GM_EXT_3D_06_RUNTIME_OUTPUT").strip_edges()
	if not output_path.is_empty():
		var absolute: String = output_path if output_path.contains(":") else ProjectSettings.globalize_path(output_path)
		DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		var file := FileAccess.open(absolute, FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report, "  ") + "\n")
	if OS.get_environment("GM_EXT_3D_06_RUNTIME_AUTO_QUIT") == "1": get_tree().quit(0 if ok else 255)
