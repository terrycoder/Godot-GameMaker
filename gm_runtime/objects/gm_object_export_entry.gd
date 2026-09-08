extends Node2D

func _ready() -> void:
	await get_tree().process_frame
	var object := get_node("LockedChest") as GMObjectInstance
	var host := object.get_node("AbilityHost") as GMObjectAbilityHostNode
	var result := host.interact({"item_ids":["item.key.iron"],"loot_table_id":"loot.chest.export"})
	$Title.text = "任务10 运行时对象样板\n上锁宝箱：%s\nGAS：%s" % ["已打开" if object.object_state.get("opened",false) else "未打开", "COMPLETED" if result.get("ok",false) else result.get("code", "FAILED")]
	await get_tree().process_frame
	var capture_path := OS.get_environment("GM_TASK10_RUNTIME_CAPTURE_OUTPUT")
	var capture := {"ok": true, "path": "", "bytes": 0}
	if not capture_path.is_empty():
		var image := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
		var error := image.save_png(capture_path)
		capture = {"ok":error == OK,"path":capture_path,"bytes":FileAccess.get_file_as_bytes(capture_path).size() if error == OK else 0,"width":image.get_width(),"height":image.get_height()}
	var facts := {"event":"TASK10_EXPORT_STARTUP_SENTINEL","ok":result.get("ok",false) and capture.get("ok",false),"godot":Engine.get_version_info().string,"stable_instance_id":object.stable_instance_id,"state":object.object_state,"gas_path":result.get("gas_path", ""),"timeline":result.get("phase_trace",[]),"capture":capture}
	print(JSON.stringify(facts))
	if OS.get_environment("GM_TASK10_RUNTIME_AUTO_QUIT") == "1":
		var exit_code := 0 if facts.ok else 121
		host.reset_runtime_host()
		for child in get_children(): child.queue_free()
		object = null
		host = null
		result = {}
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit(exit_code)
