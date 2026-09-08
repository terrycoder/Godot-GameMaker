@tool
class_name GMObjectMapDropSurface
extends PanelContainer

const DragLedger = preload("res://addons/gm_editor/object_assembler/gm_object_drag_lifecycle_ledger.gd")

signal definition_dropped(definition: GMObjectDefinition, world_position: Vector2, drag_fact: Dictionary)

var title := Label.new()
var can_drop_calls := 0
var drop_data_calls := 0
var gui_input_calls := 0
var last_drop_fact: Dictionary = {}

func _init() -> void:
	custom_minimum_size = Vector2(520, 300)
	title.text = "地图对象层（将左侧对象拖到这里）"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(title)

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	can_drop_calls += 1
	return data is Dictionary and data.get("type", "") == "gm_object_definition" and data.get("definition", null) is GMObjectDefinition and DragLedger.can_accept(data)

func _drop_data(position: Vector2, data: Variant) -> void:
	if not _can_drop_data(position, data): return
	var consumed := DragLedger.consume(data)
	if not consumed.ok: return
	drop_data_calls += 1
	last_drop_fact = {"through_drag_data":true, "through_godot_input":true, "source":data.get("source", ""), "content_id":data.get("content_id", ""), "lifecycle_nonce":consumed.nonce, "source_control_instance_id":data.get("source_control_instance_id", 0)}
	definition_dropped.emit(data.definition, position, last_drop_fact)

func _gui_input(_event: InputEvent) -> void:
	gui_input_calls += 1

func get_lifecycle_facts() -> Dictionary:
	return {"can_drop_calls":can_drop_calls, "drop_data_calls":drop_data_calls, "gui_input_calls":gui_input_calls, "last_drop":last_drop_fact.duplicate(true)}

func show_state(summary: String) -> void:
	title.text = "地图对象层\n%s" % summary
