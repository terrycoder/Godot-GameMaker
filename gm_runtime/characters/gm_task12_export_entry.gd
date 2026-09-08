extends Node

func _ready() -> void:
	var host := GMAbilitySystemHost.new()
	var router := GMCharacterControlRouter.new()
	var configured := router.configure(host,PackedStringArray(["ai","story","debug"]))
	var acquired := router.acquire("ai","export.character")
	var request := router.activation_request("ai","gm.character.interact")
	var duplicate_story := router.acquire("story","export.story")
	var duplicate_debug := router.acquire("debug","export.debug")
	var wrong_release := router.release("ai","wrong.owner")
	var preserved := router.active_source() == "ai"
	var released := router.release("ai","export.character")
	var ok: bool = bool(configured.ok) and bool(acquired.ok) and bool(request.ok) and request.kind == "ActivationRequest" and duplicate_story.code == "control.handoff_conflict" and duplicate_debug.code == "control.handoff_conflict" and wrong_release.code == "control.release_not_owner" and preserved and bool(released.ok)
	print(JSON.stringify({"event":"GM_TASK12_STARTUP_SENTINEL","ok":ok,"godot":Engine.get_version_info().string,"scope":"P14_character_assembly_minimal_control_activation_handoff","deferred":{"movement":"P15","reservation":"P16","behavior_schedule_activation_policy":"P17"},"duplicate_overwrite_retired":true}))
	router.reset()
	host.dispose()
	get_tree().quit(0 if ok else 125)
