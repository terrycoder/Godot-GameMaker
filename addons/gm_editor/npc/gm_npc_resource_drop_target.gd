@tool
class_name GMNPCResourceDropTarget
extends PanelContainer

signal assembly_resource_dropped(resource: Resource, path: String, drag_fact: Dictionary)

var label := Label.new()
var can_drop_calls := 0
var drop_data_calls := 0
var last_drop: Dictionary = {}

func _init() -> void:
	custom_minimum_size = Vector2(440, 116)
	label.text = "把角色外观 / 身份配置 / 碰撞形状 / 已装配角色场景拖到这里"
	tooltip_text = "接受任务11角色外观、P14身份配置、二维碰撞形状，或包含角色运行节点的场景。"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	can_drop_calls += 1
	if not data is Dictionary: return false
	if data.get("type", "") == "gm_character_assembly_resource": return data.get("resource", null) is Resource and bool(data.get("through_godot_input", false))
	if data.get("type", "") == "files":
		var files: PackedStringArray = data.get("files", PackedStringArray())
		if files.is_empty(): return false
		for file in files:
			if not ResourceLoader.exists(str(file)): return false
		return true
	return false

func _drop_data(position: Vector2, data: Variant) -> void:
	if not _can_drop_data(position, data): return
	drop_data_calls += 1
	if data.get("type", "") == "files":
		for file_path in data.get("files", PackedStringArray()):
			var resource := ResourceLoader.load(str(file_path), "", ResourceLoader.CACHE_MODE_IGNORE)
			if resource != null:
				last_drop = {"path":str(file_path),"through_godot_input":true,"source":"EditorFileSystemDock","position":position}
				assembly_resource_dropped.emit(resource, str(file_path), last_drop)
		return
	last_drop = {"path":str(data.path),"through_godot_input":true,"source_control_instance_id":int(data.source_control_instance_id),"position":position}
	assembly_resource_dropped.emit(data.resource, str(data.path), last_drop)
	# Do not keep editor-drag payload resources alive after the synchronous import.
	data["resource"] = null

func lifecycle_facts() -> Dictionary:
	return {"can_drop_calls":can_drop_calls,"drop_data_calls":drop_data_calls,"last_drop":last_drop.duplicate(true)}
