@tool
class_name GMObjectLibraryList
extends ItemList

const DragLedger = preload("res://addons/gm_editor/object_assembler/gm_object_drag_lifecycle_ledger.gd")

var definitions: Array[GMObjectDefinition] = []
var gui_press_observed := false
var gui_motion_observed := false
var get_drag_data_calls := 0
var lifecycle_trace: Array[String] = []
var last_lifecycle_nonce := ""
var _formal_drag_issue_definition: GMObjectDefinition

func _enter_tree() -> void:
	DragLedger.register_formal_source(self)

func _exit_tree() -> void:
	DragLedger.unregister_formal_source(self)
	_formal_drag_issue_definition = null

func set_definitions(values: Array[GMObjectDefinition]) -> void:
	definitions = values
	clear()
	for definition in definitions:
		add_item("%s\n%s" % [definition.display_name_zh, definition.content_id])

func _get_drag_data(_position: Vector2) -> Variant:
	get_drag_data_calls += 1
	# Godot only invokes this virtual after a pressed-pointer motion crosses the
	# control drag threshold, so this is an engine-observed motion fact too.
	gui_motion_observed = true
	if not lifecycle_trace.has("engine_drag_threshold"):
		lifecycle_trace.append("engine_drag_threshold")
	lifecycle_trace.append("_get_drag_data")
	if not gui_press_observed: return null
	var selected := get_selected_items()
	if selected.is_empty() or selected[0] >= definitions.size(): return null
	var definition := definitions[selected[0]]
	_formal_drag_issue_definition = definition
	var issued := DragLedger._issue_from_formal_drag(self, definition)
	_formal_drag_issue_definition = null
	if not issued.get("ok", false): return null
	last_lifecycle_nonce = str(issued.nonce)
	var payload := {"type":"gm_object_definition", "definition":definition, "content_id":definition.content_id, "source":"GM内容资源库", "source_control_instance_id":get_instance_id(), "lifecycle_nonce":last_lifecycle_nonce, "lifecycle_sequence":issued.sequence, "evidence_path":"godot_control_drag_lifecycle"}
	if payload == null: return null
	var preview := Label.new()
	preview.text = "拖放对象：%s" % payload.definition.display_name_zh
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_drag_preview(preview)
	return payload

func make_drag_payload() -> Variant:
	var selected := get_selected_items()
	if selected.is_empty() or selected[0] >= definitions.size(): return null
	var definition := definitions[selected[0]]
	return {"type": "gm_object_definition", "definition": definition, "content_id": definition.content_id, "source": "GM内容资源库", "evidence_path":"direct_helper_rejected"}

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			gui_press_observed = true
			gui_motion_observed = false
			lifecycle_trace.append("gui_press")
		else: lifecycle_trace.append("gui_release")
	elif event is InputEventMouseMotion and gui_press_observed and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		gui_motion_observed = true
		if not lifecycle_trace.has("gui_motion"): lifecycle_trace.append("gui_motion")

func get_lifecycle_facts() -> Dictionary:
	return {"gui_press":gui_press_observed, "gui_motion":gui_motion_observed, "get_drag_data_calls":get_drag_data_calls, "nonce":last_lifecycle_nonce, "trace":lifecycle_trace.duplicate(), "source_control_instance_id":get_instance_id()}

func _is_formal_drag_issue_active(definition: GMObjectDefinition) -> bool:
	return definition != null and definition == _formal_drag_issue_definition
