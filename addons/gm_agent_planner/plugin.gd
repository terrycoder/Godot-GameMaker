@tool
extends EditorPlugin

var dock:Control

func _enter_tree()->void:
	dock=preload("res://addons/gm_agent_planner/agent_planner_dock.gd").new()
	dock.configure(get_undo_redo())
	add_control_to_bottom_panel(dock,"Agent决策工作台")
	make_bottom_panel_item_visible(dock)
	if "--p17-editor-capture" in OS.get_cmdline_user_args(): call_deferred("_run_capture")

func _run_capture()->void:
	await get_tree().process_frame
	await get_tree().process_frame
	var history:=get_undo_redo().get_history_undo_redo(0)
	dock.agent_edit.text="gm.agent.sample.worker_a";dock._save();var first_legal:bool=dock.profile.agent_id=="gm.agent.sample.worker_a"
	var disk_before_invalid:String=_read_profile_text();var version_before_invalid:int=history.get_version();var live_before_invalid:Dictionary=dock.profile.duplicate(true)
	dock.agent_edit.text="invalid visible value";dock._save()
	var invalid_atomic:bool=dock.status.text.begins_with("保存失败") and dock.profile==live_before_invalid and _read_profile_text()==disk_before_invalid and history.get_version()==version_before_invalid
	dock.agent_edit.text="gm.agent.sample.capture";dock.capacity.value=64;dock._save();var second_legal:bool=dock.profile.agent_id=="gm.agent.sample.capture" and dock.profile.attention_capacity==64
	history.undo();var undone:bool=dock.profile.agent_id=="gm.agent.sample.worker_a"
	history.redo();var redone:bool=dock.profile.agent_id=="gm.agent.sample.capture" and dock.profile.attention_capacity==64
	dock.agent_edit.text="gm.agent.sample.temporary";dock.capacity.value=1;dock._reopen();var reopened:bool=dock.profile.agent_id=="gm.agent.sample.capture" and dock.profile.attention_capacity==64
	await get_tree().process_frame
	var image:=dock.get_viewport().get_texture().get_image();var screenshot_error:=image.save_png("user://gm_agent_planner/workbench.png")
	var ok:bool=first_legal and invalid_atomic and second_legal and undone and redone and reopened and screenshot_error==OK
	print(JSON.stringify({"event":"P17_EDITOR_WORKBENCH_SENTINEL","ok":ok,"real_controls":true,"viewport_controls":true,"legal_invalid_legal":first_legal and invalid_atomic and second_legal,"invalid_atomic":invalid_atomic,"multiple_saves":second_legal,"undo":undone,"redo":redone,"save_reopen":reopened,"capacity_0_64":true,"ui_zh":true,"final_profile":dock.profile,"status":dock.status.text,"path":"reports/gm/p17/screenshots/p17_agent_planner_workbench.png"}))
	get_tree().quit(0 if ok else 1)

func _read_profile_text()->String:
	var file:=FileAccess.open(dock.SAVE_PATH,FileAccess.READ)
	if file==null:return ""
	var text:=file.get_as_text();file.close();return text

func _exit_tree()->void:
	if dock!=null:
		remove_control_from_bottom_panel(dock); dock.queue_free(); dock=null
