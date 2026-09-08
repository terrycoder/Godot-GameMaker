extends Node

const HERO_CHARACTER = preload("res://samples/task11_characters/hero_complete.tres")

@export var character_definition: GMCharacterDefinition

func _ready() -> void:
	var definition = character_definition if character_definition != null else HERO_CHARACTER
	var result := {"event":"TASK11_EXPORT_STARTUP_SENTINEL", "ok":false, "godot":Engine.get_version_info().string}
	if definition is GMCharacterDefinition:
		var resolved: Dictionary = definition.resolve_visual_set()
		if resolved.ok:
			var presenter := GMCharacterPresenter2D.new(); add_child(presenter)
			var configured := presenter.configure(resolved.visual_set)
			var played := presenter.play_semantic_action(&"attack", &"right")
			var frame := presenter.seek_frame(1)
			result.merge({"ok":configured.ok and played.ok and frame.ok, "content_id":definition.content_id, "visual_set_id":resolved.visual_set.visual_set_id, "snapshot":presenter.snapshot(), "anchor":presenter.anchor_position(&"weapon")}, true)
	print(JSON.stringify(result))
	if OS.get_environment("GM_TASK11_RUNTIME_AUTO_QUIT") == "1": get_tree().quit(0 if result.ok else 51)
