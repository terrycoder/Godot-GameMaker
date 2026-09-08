@tool
class_name GMNPCResourcePalette
extends ItemList

var entries: Array[Dictionary] = []
var gui_press_observed := false
var gui_press_seen := false
var gui_motion_observed := false
var get_drag_data_calls := 0
var last_payload: Dictionary = {}

func configure_defaults() -> void:
	entries = [
		{"label":"任务11角色外观包（CharacterDefinition → VisualSet）", "path":"res://samples/task11_characters/hero_complete.tres"},
		{"label":"P14角色身份配置（RoleProfile）", "path":"res://samples/task12_characters/merchant_role.tres"},
		{"label":"P14二维碰撞形状（Shape2D）", "path":"res://samples/task12_characters/character_collision.tres"},
	]
	tooltip_text = "依次把角色外观、身份配置和碰撞形状拖到右侧装配输入区。也可直接从文件系统拖入资源或已装配角色场景。"
	clear()
	for entry in entries: add_item("%s\n%s" % [entry.label, entry.path])

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		gui_press_observed = event.pressed
		if event.pressed: gui_press_seen = true
	elif event is InputEventMouseMotion and gui_press_observed and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		gui_motion_observed = true

func _get_drag_data(_position: Vector2) -> Variant:
	get_drag_data_calls += 1
	if not gui_press_observed: return null
	var selected := get_selected_items()
	if selected.is_empty() or selected[0] >= entries.size(): return null
	var entry: Dictionary = entries[selected[0]]
	var resource := ResourceLoader.load(entry.path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null: return null
	last_payload = {"type":"gm_character_assembly_resource","path":entry.path,"resource":resource,"source_control_instance_id":get_instance_id(),"through_godot_input":true}
	var preview := Label.new()
	preview.text = "拖放：%s" % entry.label
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_drag_preview(preview)
	return last_payload

func lifecycle_facts() -> Dictionary:
	return {"gui_press":gui_press_seen,"gui_motion":gui_motion_observed,"get_drag_data_calls":get_drag_data_calls,"last_payload_path":str(last_payload.get("path",""))}
