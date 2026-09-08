@tool
class_name GMEventTriggerDock
extends VBoxContainer

## 任务07真实 EditorPlugin 面板。
##
## 面板只负责编辑器局部通信、触发器资源摘要和两张分离审计图；领域事实
## 仍由 GMGameplayEventTrigger → GMAbilitySystemHost → 事务入口提交。

const TRIGGER := preload("res://gm_runtime/events/gm_gameplay_event_trigger.gd")
const CONDITION := preload("res://gm_runtime/events/gm_event_condition.gd")
const HANDLER := preload("res://gm_runtime/events/gm_event_handler.gd")
const SELECTOR := preload("res://gm_runtime/events/gm_target_selector.gd")
const ACTION := preload("res://gm_runtime/events/gm_event_action.gd")
const EXPRESSION := preload("res://gm_runtime/content/gm_expression_field.gd")
const EVENT_GRAPH := preload("res://gm_runtime/events/gm_gameplay_event_audit_graph.gd")
const SIGNAL_CONNECTION := preload("res://addons/gm_editor/signals/gm_signal_connection.gd")
const SIGNAL_AUDIT := preload("res://addons/gm_editor/signals/gm_signal_audit.gd")
const AUDIT_LOCATOR := preload("res://addons/gm_editor/triggers/gm_editor_audit_locator.gd")
const SCENE_REFERENCE := preload("res://addons/gm_editor/scene_refs/gm_scene_reference.gd")

const CAPTURE_GATE := "GM_TASK07_EDITOR_CAPTURE_GATE"
const SENTINEL := "GM_TASK07_CAPTURE_SENTINEL"
const AUDIT_SCENE_PATH := "user://gm_event_trigger/audit_scene.tscn"
const AUDIT_RESOURCE_ROOT := "user://gm_event_trigger/editor_locator"

var editor_interface
var editor_undo_redo
var trigger_rows: Array[GMGameplayEventTrigger] = []
var local_graph: Dictionary = {}
var event_graph: Dictionary = {}
var local_connections: Array[GMSignalConnection] = []
var persistent_connection: GMSignalConnection
var runtime_connection: GMSignalConnection
var undo_connection_enabled: bool = true
var undo_probe: Dictionary = {}
var capture_state: String = "graphs"
var node_registry: Dictionary = {}
var resource_registry: Dictionary = {}
var location_results: Dictionary = {}
var location_audit: Array[Dictionary] = []
var last_location: Dictionary = {}
var locator_scene_root: Node
var locator_resource_paths: Array[String] = []

var sentinel_label: Label
var status_label: Label
var trigger_label: Label
var connection_label: Label
var graph_label: Label
var local_graph_actions: VBoxContainer
var event_graph_actions: VBoxContainer

func configure(p_editor_interface, p_undo_redo) -> void:
	editor_interface = p_editor_interface
	editor_undo_redo = p_undo_redo
	set_meta("editor_undo_redo", p_undo_redo)

func _ready() -> void:
	if editor_interface == null: editor_interface = get_meta("editor_interface", null)
	if editor_undo_redo == null: editor_undo_redo = get_meta("editor_undo_redo", null)
	custom_minimum_size = Vector2(900, 420)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_shell()
	_build_model()
	call_deferred("_refresh")

func _build_shell() -> void:
	for child in get_children(): child.queue_free()
	var title := Label.new()
	title.text = "GM 事件触发器与连接审计 · 任务包07"
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)
	var subtitle := Label.new()
	subtitle.text = "真实 EditorPlugin 门控面板 | Trigger资源：事件 Schema/Tag → 条件 → 目标 → 能力/事件 | 局部 signal 与 GameplayEvent 图严格分离"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(subtitle)
	sentinel_label = Label.new()
	sentinel_label.name = "任务07机器哨兵"
	sentinel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sentinel_label.modulate = Color("8ff0b2")
	add_child(sentinel_label)
	var button_row := HBoxContainer.new()
	add_child(button_row)
	var refresh_button := Button.new()
	refresh_button.text = "重新发现/刷新两图"
	refresh_button.pressed.connect(_refresh)
	button_row.add_child(refresh_button)
	var undo_button := Button.new()
	undo_button.text = "Undo/Redo连接探针"
	undo_button.pressed.connect(_run_undo_redo_probe)
	button_row.add_child(undo_button)
	var connect_button := Button.new()
	connect_button.text = "连接局部信号"
	connect_button.pressed.connect(func(): _apply_connection_state(true))
	button_row.add_child(connect_button)
	var disconnect_button := Button.new()
	disconnect_button.text = "断开局部信号"
	disconnect_button.pressed.connect(func(): _apply_connection_state(false))
	button_row.add_child(disconnect_button)
	status_label = Label.new()
	status_label.name = "任务07操作反馈"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	var trigger_heading := Label.new()
	trigger_heading.text = "Gameplay Event Trigger资源"
	trigger_heading.add_theme_font_size_override("font_size", 17)
	left.add_child(trigger_heading)
	trigger_label = Label.new()
	trigger_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trigger_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(trigger_label)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var connection_heading := Label.new()
	connection_heading.text = "Godot局部信号图 · 连接表"
	connection_heading.add_theme_font_size_override("font_size", 17)
	right.add_child(connection_heading)
	connection_label = Label.new()
	connection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(connection_label)
	var local_action_heading := Label.new()
	local_action_heading.text = "局部信号图定位操作（真实 EditorSelection）"
	local_action_heading.add_theme_font_size_override("font_size", 14)
	right.add_child(local_action_heading)
	local_graph_actions = VBoxContainer.new()
	local_graph_actions.name = "局部信号图定位按钮"
	right.add_child(local_graph_actions)
	var graph_heading := Label.new()
	graph_heading.text = "GameplayEvent→条件→目标→能力/事件图"
	graph_heading.add_theme_font_size_override("font_size", 17)
	right.add_child(graph_heading)
	graph_label = Label.new()
	graph_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(graph_label)
	var event_action_heading := Label.new()
	event_action_heading.text = "GameplayEvent图定位操作（真实 Resource Inspector）"
	event_action_heading.add_theme_font_size_override("font_size", 14)
	right.add_child(event_action_heading)
	event_graph_actions = VBoxContainer.new()
	event_graph_actions.name = "GameplayEvent图定位按钮"
	right.add_child(event_graph_actions)

func _build_model() -> void:
	trigger_rows.clear()
	trigger_rows.append(_make_death_trigger())
	trigger_rows.append(_make_area_trigger())
	trigger_rows.append(_make_production_trigger())
	for trigger in trigger_rows:
		trigger.set_meta("gm_content_id", trigger.trigger_id)
	persistent_connection = SIGNAL_CONNECTION.new()
	persistent_connection.connection_id = "gm.signal.task07.editor.persistent"
	persistent_connection.configure("gm.scene.task07.editor", "visibility_changed", "gm.scene.task07.editor", "_on_local_signal", true)
	persistent_connection.source_scene_id = "gm.scene.task07.editor"
	persistent_connection.target_scene_id = "gm.scene.task07.editor"
	runtime_connection = SIGNAL_CONNECTION.new()
	runtime_connection.connection_id = "gm.signal.task07.editor.runtime"
	runtime_connection.configure("gm.scene.task07.editor", "resized", "gm.scene.task07.editor", "_on_runtime_signal", false)
	runtime_connection.source_scene_id = "gm.scene.task07.editor"
	runtime_connection.target_scene_id = "gm.scene.task07.editor"
	local_connections = [persistent_connection, runtime_connection]
	_apply_connection_state(true)
	undo_connection_enabled = true

func _make_death_trigger() -> GMGameplayEventTrigger:
	var tag := CONDITION.new()
	tag.condition_id = "gm.condition.task07.editor.death.tag"
	tag.condition_kind = CONDITION.KIND_TAG
	tag.tag_query = "gm.event.actor.death"
	var health := CONDITION.new()
	health.condition_id = "gm.condition.task07.editor.death.health"
	health.condition_kind = CONDITION.KIND_ATTRIBUTE
	health.attribute_id = "health"
	health.attribute_comparison = "小于等于"
	health.attribute_expected_value = 0.0
	var selector := SELECTOR.new()
	selector.selector_id = "gm.selector.task07.editor.death.actor"
	selector.selector_kind = SELECTOR.EVENT_TARGET
	var action := ACTION.new()
	action.action_id = "gm.action.task07.editor.death.drop"
	action.ability_id = "gm.ability.task07.drop_on_death"
	var trigger := TRIGGER.new()
	trigger.trigger_id = "gm.trigger.task07.editor.death.drop"
	trigger.display_name_zh = "死亡→掉落"
	trigger.event_tag = "gm.event.actor.death"
	trigger.event_schema = {"required": {"drop_item_id": "String", "quantity": "int"}}
	trigger.conditions = [tag, health]
	trigger.target_selector = selector
	trigger.actions = [action]
	return trigger

func _make_area_trigger() -> GMGameplayEventTrigger:
	var condition := CONDITION.new()
	condition.condition_id = "gm.condition.task07.editor.area.locked"
	condition.condition_kind = CONDITION.KIND_CONTENT_STATE
	condition.content_state_key = "door_locked"
	condition.content_comparison = "等于"
	condition.content_expected_value = true
	var selector := SELECTOR.new()
	selector.selector_id = "gm.selector.task07.editor.area.door"
	selector.selector_kind = SELECTOR.PAYLOAD_ID
	selector.payload_field = "door_id"
	var action := ACTION.new()
	action.action_id = "gm.action.task07.editor.area.open"
	action.ability_id = "gm.ability.task07.open_door"
	var trigger := TRIGGER.new()
	trigger.trigger_id = "gm.trigger.task07.editor.area.open"
	trigger.display_name_zh = "进入区域→开门"
	trigger.event_tag = "gm.event.area.entered"
	trigger.event_schema = {"required": {"door_id": "String"}}
	trigger.conditions = [condition]
	trigger.target_selector = selector
	trigger.actions = [action]
	return trigger

func _make_production_trigger() -> GMGameplayEventTrigger:
	var expression := EXPRESSION.new()
	expression.expression = "quantity >= 1"
	expression.input_names = PackedStringArray(["quantity"])
	expression.expected_type = "bool"
	var condition := CONDITION.new()
	condition.condition_id = "gm.condition.task07.editor.production.quantity"
	condition.condition_kind = CONDITION.KIND_EXPRESSION
	condition.expression = expression
	var selector := SELECTOR.new()
	selector.selector_id = "gm.selector.task07.editor.production.task"
	selector.selector_kind = SELECTOR.PAYLOAD_ID
	selector.payload_field = "task_id"
	var handler := HANDLER.new()
	handler.handler_id = "gm.handler.task07.editor.production.update"
	handler.display_name_zh = "生产完成任务处理器"
	var action := ACTION.new()
	action.action_id = "gm.action.task07.editor.production.update"
	action.ability_id = "gm.ability.task07.update_task"
	var trigger := TRIGGER.new()
	trigger.trigger_id = "gm.trigger.task07.editor.production.update"
	trigger.display_name_zh = "生产完成→任务更新"
	trigger.event_tag = "gm.event.production.completed"
	trigger.event_schema = {"required": {"task_id": "String", "quantity": "int"}}
	trigger.conditions = [condition]
	trigger.target_selector = selector
	trigger.handler = handler
	trigger.actions = [action]
	return trigger

func _refresh() -> void:
	var validations: Array[Dictionary] = []
	for trigger in trigger_rows:
		validations.append(trigger.validate_definition(null, {"validate_expression_values": false}))
	var graph_context := {"location_results": location_results, "node_registry": node_registry, "resource_registry": resource_registry}
	local_graph = SIGNAL_AUDIT.build(local_connections, graph_context)
	event_graph = EVENT_GRAPH.build_from_triggers(trigger_rows, graph_context)
	if not is_instance_valid(trigger_label): return
	var trigger_lines: Array[String] = []
	for index in trigger_rows.size():
		var trigger: GMGameplayEventTrigger = trigger_rows[index]
		var check: Dictionary = validations[index]
		trigger_lines.append("[%s] %s\n  Tag=%s\n  Schema=%s\n  条件=%d  目标=%s  动作=%s\n  验证=%s" % [trigger.trigger_id, trigger.display_name_zh, trigger.event_tag, JSON.stringify(trigger.event_schema), trigger.conditions.size(), trigger.target_selector.selector_kind if trigger.target_selector != null else "无", trigger.actions.size(), "通过" if bool(check.get("ok", false)) else "阻断：%s" % ";".join(check.get("errors_zh", []))])
	trigger_label.text = "\n\n".join(trigger_lines)
	var local_locatable := _locatable_count(local_graph.get("edges", []))
	var event_locatable := _locatable_count(event_graph.get("edges", []))
	connection_label.text = _local_connection_table(local_locatable, int(local_graph.get("edge_count", 0)))
	var separation := SIGNAL_AUDIT.validate_separation(local_graph, event_graph)
	graph_label.text = "图类型：%s\n标题：%s\n节点=%d  边=%d  可定位=%d/%d\n分离断言：%s\n定位必须由下方真实 Resource Inspector 操作确认。" % [str(event_graph.get("graph_kind", "")), str(event_graph.get("title_zh", "")), int(event_graph.get("node_count", 0)), int(event_graph.get("edge_count", 0)), event_locatable, int(event_graph.get("edge_count", 0)), "通过" if bool(separation.get("ok", false)) else "阻断"]
	if is_instance_valid(sentinel_label):
		sentinel_label.text = "%s | capture_gate=%s | trigger_count=%d | local_edges=%d/%d | event_edges=%d/%d | undo_probe=%s" % [SENTINEL, CAPTURE_GATE, trigger_rows.size(), local_locatable, int(local_graph.get("edge_count", 0)), event_locatable, int(event_graph.get("edge_count", 0)), JSON.stringify(undo_probe)]
	if is_instance_valid(status_label):
		status_label.text = "已重新发现：%d 条触发器资源；两类审计图已分别生成；定位成功 %d/%d。" % [trigger_rows.size(), location_results.size(), local_connections.size() + trigger_rows.size()]
	_rebuild_locator_buttons()

func _rebuild_locator_buttons() -> void:
	if is_instance_valid(local_graph_actions):
		for child in local_graph_actions.get_children(): child.queue_free()
		for index in local_connections.size():
			var connection: GMSignalConnection = local_connections[index]
			var button := Button.new()
			button.text = "定位局部连接：%s（%s→%s）" % [connection.connection_id, connection.source_business_id, connection.target_business_id]
			button.pressed.connect(_on_local_graph_row_clicked.bind(index))
			local_graph_actions.add_child(button)
	if is_instance_valid(event_graph_actions):
		for child in event_graph_actions.get_children(): child.queue_free()
		for trigger in trigger_rows:
			var button := Button.new()
			button.text = "定位 GameplayEvent Trigger：%s" % trigger.trigger_id
			button.pressed.connect(_on_event_graph_row_clicked.bind(trigger.trigger_id))
			event_graph_actions.add_child(button)

func _on_local_graph_row_clicked(index: int) -> void:
	if index < 0 or index >= local_connections.size(): return
	var connection: GMSignalConnection = local_connections[index]
	var source_result := _locate_node_id(connection.source_business_id)
	var target_result := _locate_node_id(connection.target_business_id)
	location_results[connection.source_business_id] = source_result
	location_results[connection.target_business_id] = target_result
	if bool(source_result.get("ok", false)): connection.source_locator = str(source_result.get("resolved_locator", ""))
	if bool(target_result.get("ok", false)): connection.target_locator = str(target_result.get("resolved_locator", ""))
	var row := {"kind": "GodotLocalSignal", "connection_id": connection.connection_id, "stable_source_id": connection.source_business_id, "stable_target_id": connection.target_business_id, "source": source_result, "target": target_result, "selection_before": source_result.get("selection_before", {}), "selection_after": target_result.get("selection_after", {}), "ok": bool(source_result.get("ok", false)) and bool(target_result.get("ok", false)), "action": "EditorSelection.add_node + EditorInterface.edit_node/inspect_object"}
	location_audit.append(row)
	last_location = row
	_refresh()

func _on_event_graph_row_clicked(trigger_id: String) -> void:
	var resource: Resource = null
	var registry_row: Variant = resource_registry.get(trigger_id, null)
	if registry_row is Resource:
		resource = registry_row
	elif registry_row is Dictionary and registry_row.get("resource", null) is Resource:
		resource = registry_row.get("resource")
	else:
		for trigger in trigger_rows:
			if trigger.trigger_id == trigger_id:
				resource = trigger
				break
	var result := AUDIT_LOCATOR.locate_resource(editor_interface, resource, trigger_id)
	location_results[trigger_id] = result
	var row := {"kind": "GameplayEvent", "stable_resource_id": trigger_id, "resource": result, "inspected_before": result.get("inspector_before", {}), "inspected_after": result.get("inspector_after", {}), "ok": bool(result.get("ok", false)), "action": "EditorInterface.edit_resource + inspect_object"}
	location_audit.append(row)
	last_location = row
	_refresh()

func _locate_node_id(stable_id: String) -> Dictionary:
	return AUDIT_LOCATOR.locate_node_by_id(editor_interface, locator_scene_root, stable_id)

func _locatable_count(value: Variant) -> int:
	if not value is Array: return 0
	var count := 0
	for row in value:
		if row is Dictionary and bool(row.get("locatable", false)): count += 1
	return count

func _local_connection_table(locatable_count: int, edge_count: int) -> String:
	var lines: Array[String] = ["图类型：GodotLocalSignal", "标题：Godot局部信号图", "局部连接：%d  可定位：%d/%d" % [local_connections.size(), locatable_count, edge_count]]
	for connection in local_connections:
		lines.append("%s | %s→%s | %s" % [connection.persistence_kind, connection.source_business_id, connection.target_business_id, "已连接" if connection.is_live_connected() else "未连接"])
		lines.append("  source=%s" % _display_locator(connection.source_locator))
		lines.append("  target=%s" % _display_locator(connection.target_locator))
	lines.append("未执行真实定位时 locatable=false；下方按钮会调用 EditorSelection/Inspector。")
	return "\n".join(lines)

func _display_locator(value: String) -> String:
	var raw := str(value)
	return raw if raw.length() <= 96 else "…" + raw.right(96)

func _prepare_capture_scene() -> Dictionary:
	if editor_interface == null or not is_instance_valid(editor_interface):
		return {"ok": false, "code": "editor.locator_unavailable", "reason_zh": "EditorInterface 不可用，不能准备真实定位场景。"}
	_apply_connection_state(false)
	if editor_interface.has_method("open_scene_from_path"):
		editor_interface.open_scene_from_path(AUDIT_SCENE_PATH)
	if not editor_interface.has_method("get_edited_scene_root"):
		return {"ok": false, "code": "editor.scene_root_api_missing", "reason_zh": "EditorInterface 没有 get_edited_scene_root。"}
	var root_value: Variant = editor_interface.get_edited_scene_root()
	if root_value == null or not root_value is Node:
		return {"ok": false, "code": "editor.scene_root_missing", "reason_zh": "编辑器没有加载任务07真实定位场景：%s。" % AUDIT_SCENE_PATH}
	locator_scene_root = root_value
	var source_resolution := AUDIT_LOCATOR.resolve_node(locator_scene_root, "gm.entity.task07.editor.source")
	var target_resolution := AUDIT_LOCATOR.resolve_node(locator_scene_root, "gm.entity.task07.editor.target")
	var source: Node = source_resolution.get("resolved", null) if source_resolution.get("resolved", null) is Node else null
	var target: Node = target_resolution.get("resolved", null) if target_resolution.get("resolved", null) is Node else null
	if source == null or target == null:
		var failed_resolution: Dictionary = source_resolution if not bool(source_resolution.get("ok", false)) else target_resolution
		return {"ok": false, "code": str(failed_resolution.get("code", "editor.scene_node_missing")), "reason_zh": str(failed_resolution.get("reason_zh", "真实定位场景缺少唯一稳定业务 ID 节点。")), "scene_path": AUDIT_SCENE_PATH, "resolution": failed_resolution}
	node_registry = {"gm.entity.task07.editor.source": source, "gm.entity.task07.editor.target": target, "gm.scene.task07.editor": locator_scene_root}
	return {"ok": true, "scene_path": AUDIT_SCENE_PATH, "root_id": SCENE_REFERENCE.read_business_id(locator_scene_root), "source_locator": str(source.get_path()), "target_locator": str(target.get_path()), "source_resolution": source_resolution, "target_resolution": target_resolution}

func _prepare_capture_resources() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUDIT_RESOURCE_ROOT))
	resource_registry.clear()
	locator_resource_paths.clear()
	var loaded_rows: Array[GMGameplayEventTrigger] = []
	for trigger in trigger_rows:
		trigger.set_meta("gm_content_id", trigger.trigger_id)
		var path := AUDIT_RESOURCE_ROOT.path_join(_slug(trigger.trigger_id) + ".tres")
		var save_error := ResourceSaver.save(trigger, path)
		if save_error != OK:
			return {"ok": false, "code": "editor.resource_save_failed", "reason_zh": "审计定位 Resource 保存失败：%s。" % path, "error": save_error, "path": path}
		var loaded: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if loaded == null or not loaded is GMGameplayEventTrigger:
			return {"ok": false, "code": "editor.resource_reopen_failed", "reason_zh": "审计定位 Resource 保存后重开失败：%s。" % path, "path": path}
		var trigger_loaded: GMGameplayEventTrigger = loaded
		resource_registry[trigger_loaded.trigger_id] = trigger_loaded
		loaded_rows.append(trigger_loaded)
		locator_resource_paths.append(path)
	trigger_rows.clear()
	for trigger_loaded in loaded_rows: trigger_rows.append(trigger_loaded)
	return {"ok": true, "root": AUDIT_RESOURCE_ROOT, "resource_count": loaded_rows.size(), "paths": locator_resource_paths.duplicate()}

func _configure_capture_connections() -> Dictionary:
	_apply_connection_state(false)
	persistent_connection.configure("gm.entity.task07.editor.source", "completed", "gm.entity.task07.editor.target", "on_completed", true)
	persistent_connection.source_scene_id = "gm.scene.task07.editor"
	persistent_connection.target_scene_id = "gm.scene.task07.editor"
	runtime_connection.configure("gm.entity.task07.editor.source", "runtime_completed", "gm.entity.task07.editor.target", "on_runtime_completed", false)
	runtime_connection.source_scene_id = "gm.scene.task07.editor"
	runtime_connection.target_scene_id = "gm.scene.task07.editor"
	_apply_connection_state(true)
	var connected := local_connections.all(func(connection: GMSignalConnection) -> bool: return connection.is_live_connected())
	return {"ok": connected, "persistent": persistent_connection.to_dict(), "runtime": runtime_connection.to_dict()}

func _find_node_by_id(root: Node, stable_id: String) -> Node:
	return GMSceneReference.find_by_business_id(root, stable_id) if root != null else null

func _apply_connection_state(enabled: bool) -> void:
	undo_connection_enabled = enabled
	var rows: Array[String] = []
	for connection in local_connections:
		var source_object: Object = _connection_object(connection.source_business_id)
		var target_object: Object = _connection_object(connection.target_business_id)
		var result: Dictionary
		if enabled:
			result = connection.connect_to(source_object, target_object)
			if str(result.get("code", "")) == "signal.duplicate_connection": result["ok"] = true
		else:
			result = connection.disconnect_from(source_object, target_object)
			if str(result.get("code", "")) == "signal.not_connected": result["ok"] = true
		rows.append("%s=%s" % [connection.persistence_kind, "已连接" if connection.is_live_connected() else "未连接"])
	if is_instance_valid(status_label): status_label.text = "；".join(rows)
	if is_instance_valid(connection_label):
		connection_label.text = _local_connection_table(_locatable_count(local_graph.get("edges", [])), int(local_graph.get("edge_count", 0)))

func _connection_object(stable_id: String) -> Object:
	var value: Variant = node_registry.get(stable_id, null)
	if value != null and is_instance_valid(value) and value is Object: return value
	return self

func _run_undo_redo_probe() -> void:
	if editor_undo_redo == null:
		undo_probe = {"ok": false, "code": "editor.undo_redo_missing", "reason_zh": "EditorUndoRedoManager 不可用。"}
		_refresh()
		return
	var before := undo_connection_enabled
	var manager_methods: Array[String] = []
	for raw_method in editor_undo_redo.get_method_list():
		if raw_method is Dictionary and str(raw_method.get("name", "")).to_lower().contains("undo"):
			manager_methods.append(str(raw_method.get("name", "")))
	editor_undo_redo.create_action("任务07：局部信号连接 Undo/Redo")
	editor_undo_redo.add_do_method(self, "_apply_connection_state", not before)
	editor_undo_redo.add_undo_method(self, "_apply_connection_state", before)
	editor_undo_redo.commit_action()
	var after_commit := undo_connection_enabled
	var history: Variant = null
	var history_id := -1
	if editor_undo_redo.has_method("get_object_history_id"):
		history_id = int(editor_undo_redo.call("get_object_history_id", self))
	if history_id >= 0 and editor_undo_redo.has_method("get_history_undo_redo"):
		history = editor_undo_redo.call("get_history_undo_redo", history_id)
	var history_can_undo: bool = history != null and history.has_method("undo")
	var history_can_redo: bool = history != null and history.has_method("redo")
	var after_undo := after_commit
	var after_redo := after_commit
	if history_can_undo:
		history.call("undo")
		after_undo = undo_connection_enabled
	if history_can_redo:
		history.call("redo")
		after_redo = undo_connection_enabled
	_apply_connection_state(before)
	undo_probe = {"ok": before != after_commit and (not history_can_undo or after_undo == before) and (not history_can_redo or after_redo == after_commit), "before": before, "after_commit": after_commit, "after_undo": after_undo, "after_redo": after_redo, "manager": "EditorUndoRedoManager", "history_id": history_id, "history_can_undo": history_can_undo, "history_can_redo": history_can_redo, "manager_undo_methods": manager_methods, "inverse_callbacks_registered": true}
	_refresh()

func prepare_capture(state: String) -> void:
	capture_state = state if not state.is_empty() else "graphs"
	location_results.clear()
	location_audit.clear()
	last_location = {}
	var scene_result := _prepare_capture_scene()
	var resource_result := _prepare_capture_resources() if bool(scene_result.get("ok", false)) else {"ok": false, "code": "editor.scene_prepare_failed", "reason_zh": "真实定位场景准备失败，不能执行 Resource 定位。"}
	var connection_result := _configure_capture_connections() if bool(scene_result.get("ok", false)) else {"ok": false, "code": "editor.connection_prepare_failed", "reason_zh": "真实定位场景准备失败，不能切换局部信号端点。"}
	location_audit.append({"kind": "capture_prepare", "scene": scene_result, "resources": resource_result, "connections": connection_result, "ok": bool(scene_result.get("ok", false)) and bool(resource_result.get("ok", false)) and bool(connection_result.get("ok", false))})
	if bool(resource_result.get("ok", false)) and bool(connection_result.get("ok", false)):
		_run_capture_location_probes()
	_refresh()

func _run_capture_location_probes() -> void:
	for index in local_connections.size(): _on_local_graph_row_clicked(index)
	for trigger in trigger_rows: _on_event_graph_row_clicked(trigger.trigger_id)

func get_capture_snapshot() -> Dictionary:
	return {"capture_gate": CAPTURE_GATE, "sentinel": SENTINEL, "capture_state": capture_state, "trigger_count": trigger_rows.size(), "trigger_summaries": trigger_rows.map(func(value): return value.summary()), "local_graph": local_graph.duplicate(true), "event_graph": event_graph.duplicate(true), "connections": local_connections.map(func(value): return value.to_dict()), "undo_redo": undo_probe.duplicate(true), "editor_undo_redo_available": editor_undo_redo != null, "resource_source": "GMGameplayEventTrigger Resource 实例", "formal_pipeline": "GMGameplayEventTrigger -> GMAbilitySystemHost -> GMAbilityActivationRequest -> 既有事务/Fact/EventStore", "locator_scene_path": AUDIT_SCENE_PATH, "locator_scene_root_id": SCENE_REFERENCE.read_business_id(locator_scene_root), "locator_resource_paths": locator_resource_paths.duplicate(), "location_audit": location_audit.duplicate(true), "location_results": location_results.duplicate(true), "last_location": last_location.duplicate(true), "locator_controls": {"local_graph_buttons": local_connections.size(), "event_graph_buttons": trigger_rows.size(), "actual_editor_apis": ["EditorInterface.get_selection", "EditorSelection.clear", "EditorSelection.add_node", "EditorInterface.edit_node", "EditorInterface.edit_resource", "EditorInterface.inspect_object"]}}

func _on_local_signal() -> void:
	if is_instance_valid(status_label): status_label.text = "持久 Godot 局部 signal 已到达 Callable。"

func _on_runtime_signal() -> void:
	if is_instance_valid(status_label): status_label.text = "运行时动态 Godot 局部 signal 已到达 Callable。"

func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in raw.length():
		var code := raw.unicode_at(index)
		result += raw.substr(index, 1) if ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45) else "_"
	return result.trim_prefix("_").trim_suffix("_") if not result.is_empty() else "trigger"

func _exit_tree() -> void:
	for connection in local_connections:
		if connection != null: connection.disconnect_from(_connection_object(connection.source_business_id), _connection_object(connection.target_business_id))
