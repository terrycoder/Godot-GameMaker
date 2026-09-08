@tool
extends VBoxContainer

var editor_plugin: EditorPlugin
var undo_redo: EditorUndoRedoManager
var role: GMRoleProfile
var visual_set: GMCharacterVisualSet2D
var collision: Shape2D
var map_id_edit: LineEdit
var anchor_edit: LineEdit
var save_path_edit: LineEdit
var status_label: Label
var selection_label: Label
var resource_palette: GMNPCResourcePalette
var drop_target: GMNPCResourceDropTarget
var assemble_button: Button
var undo_button: Button
var redo_button: Button
var save_button: Button
var assembled: GMCharacterRuntime2D
var last_saved_path := ""
var import_facts: Array[Dictionary] = []

func configure(plugin: EditorPlugin) -> void:
	editor_plugin = plugin
	undo_redo = plugin.get_undo_redo()
	name = "GMNPCAssemblyDock"
	var title := Label.new()
	title.text = "P14 角色 / NPC 装配 · 身份配置 · 最小控制源与激活交接"
	add_child(title)
	var split := HBoxContainer.new()
	add_child(split)
	resource_palette = GMNPCResourcePalette.new()
	resource_palette.name = "AssemblyResourcePalette"
	resource_palette.custom_minimum_size = Vector2(430, 150)
	resource_palette.configure_defaults()
	split.add_child(resource_palette)
	drop_target = GMNPCResourceDropTarget.new()
	drop_target.name = "AssemblyResourceDropTarget"
	drop_target.assembly_resource_dropped.connect(_on_resource_dropped)
	split.add_child(drop_target)
	selection_label = Label.new()
	selection_label.name = "AssemblySelections"
	selection_label.text = _selection_summary()
	add_child(selection_label)
	map_id_edit = LineEdit.new()
	map_id_edit.name = "MapId"
	_add_field_label("地图稳定标识", "来自正式地图资源的稳定标识，例如 map.town；内部值保持不翻译。")
	map_id_edit.placeholder_text = "例如：map.town"
	map_id_edit.tooltip_text = "地图稳定标识只用于引用，不是面向策划翻译的显示名称。"
	add_child(map_id_edit)
	anchor_edit = LineEdit.new()
	anchor_edit.name = "SpawnAnchorId"
	_add_field_label("任务09语义出生锚点", "填写任务09语义地图中已存在的出生锚点稳定标识。")
	anchor_edit.placeholder_text = "例如：spawn.market"
	anchor_edit.tooltip_text = "锚点稳定标识保持英文机器值；界面说明使用中文。"
	add_child(anchor_edit)
	save_path_edit = LineEdit.new()
	save_path_edit.name = "CharacterScenePath"
	_add_field_label("角色场景保存位置", "保存为项目内可独立关闭并重新打开的角色场景。")
	save_path_edit.placeholder_text = "项目路径：res://...tscn"
	save_path_edit.tooltip_text = "路径属于稳定技术边界，必须保持 res:// 与 .tscn 格式。"
	save_path_edit.text = "res://gm_runtime/characters/samples/p14_character.tscn"
	add_child(save_path_edit)
	var actions := HBoxContainer.new()
	add_child(actions)
	assemble_button = Button.new()
	assemble_button.name = "AssembleCharacter"
	assemble_button.text = "装配到当前场景"
	assemble_button.tooltip_text = "校验三类输入、地图与锚点后，把角色节点加入当前二维场景。"
	assemble_button.pressed.connect(_on_assemble)
	actions.add_child(assemble_button)
	undo_button = Button.new()
	undo_button.name = "UndoAssembly"
	undo_button.text = "撤销装配"
	undo_button.tooltip_text = "通过 Godot 编辑器撤销管理器取消最近一次角色装配。"
	undo_button.pressed.connect(_on_undo)
	actions.add_child(undo_button)
	redo_button = Button.new()
	redo_button.name = "RedoAssembly"
	redo_button.text = "重做装配"
	redo_button.tooltip_text = "通过 Godot 编辑器撤销管理器恢复刚撤销的角色装配。"
	redo_button.pressed.connect(_on_redo)
	actions.add_child(redo_button)
	save_button = Button.new()
	save_button.name = "SaveCharacterScene"
	save_button.text = "保存角色场景"
	save_button.tooltip_text = "把当前装配结果保存为可独立重新打开的角色场景。"
	save_button.pressed.connect(_on_save)
	actions.add_child(save_button)
	status_label = Label.new()
	status_label.name = "AssemblyStatus"
	status_label.text = "等待正式拖放：三类输入齐全后才允许装配。"
	add_child(status_label)

func _on_resource_dropped(resource: Resource, path: String, drag_fact: Dictionary) -> void:
	var result := _accept_resource(resource, path)
	result["drag"] = drag_fact
	import_facts.append(result)
	selection_label.text = _selection_summary()
	status_label.text = "已接收装配资源：%s" % path if result.ok else "%s 请确认资源类型后重试（%s）" % [result.get("error_zh","资源不适用于 P14 装配。"),result.get("code","character.drop_rejected")]

func _accept_resource(resource: Resource, path: String) -> Dictionary:
	if resource is GMCharacterDefinition:
		var resolved := (resource as GMCharacterDefinition).resolve_visual_set()
		if not resolved.ok: return resolved
		visual_set = resolved.visual_set
		return {"ok":true,"kind":"VisualSet","path":path,"visual_set_id":visual_set.visual_set_id}
	if resource is GMCharacterVisualSet2D:
		visual_set = resource
		return {"ok":true,"kind":"VisualSet","path":path,"visual_set_id":visual_set.visual_set_id}
	if resource is GMRoleProfile:
		var checked := (resource as GMRoleProfile).validate_profile()
		if not checked.ok: return checked
		role = resource
		return {"ok":true,"kind":"RoleProfile","path":path,"role_id":role.role_id}
	if resource is Shape2D:
		collision = resource
		return {"ok":true,"kind":"Collision","path":path,"shape_class":resource.get_class()}
	if resource is PackedScene:
		var instance := (resource as PackedScene).instantiate()
		var character := _find_character(instance)
		if character == null:
			instance.free()
			return {"ok":false,"code":"character.drop_scene_missing_runtime","error_zh":"场景中没有 GMCharacterRuntime2D。","path":path}
		visual_set = character.visual_set
		role = character.role_profile
		var shape_node := character.get_node_or_null("CollisionShape2D") as CollisionShape2D
		collision = shape_node.shape if shape_node != null else null
		instance.free()
		return {"ok":visual_set != null and role != null and collision != null,"kind":"CharacterScene","path":path}
	return {"ok":false,"code":"character.drop_type_unsupported","error_zh":"只接受任务11角色定义/VisualSet、RoleProfile、Shape2D或已装配角色场景。","path":path}

func _find_character(node: Node) -> GMCharacterRuntime2D:
	if node is GMCharacterRuntime2D: return node
	for child in node.get_children():
		var found := _find_character(child)
		if found != null: return found
	return null

func _on_assemble() -> void:
	var result := GMCharacterAssembler.assemble(visual_set, role, collision, map_id_edit.text, anchor_edit.text)
	if not result.ok:
		status_label.text = "%s 请修正对应字段后重试（%s）" % [result.error_zh,result.code]
		return
	assembled = result.character
	var root := editor_plugin.get_editor_interface().get_edited_scene_root()
	if root == null:
		assembled.free()
		assembled = null
		status_label.text = "当前没有可装配的地图场景，请先打开二维地图场景后重试（character.assemble_scene_missing）。"
		return
	# Keep the node stable in the editor tree while Undo/Redo toggles whether it
	# belongs to the packed scene. This avoids stale SceneTreeEditor paths while
	# still making the real assembly state undoable through the manager.
	root.add_child(assembled)
	assembled.visible = false
	assembled.owner = null
	undo_redo.create_action("装配 P14 GM 角色/NPC", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_property(assembled,"visible",true)
	undo_redo.add_do_property(assembled,"owner",root)
	undo_redo.add_undo_property(assembled,"owner",null)
	undo_redo.add_undo_property(assembled,"visible",false)
	undo_redo.add_do_reference(assembled)
	undo_redo.commit_action()
	status_label.text = "已由正式装配动作加入场景：%s" % assembled.stable_instance_id

func _on_undo() -> void:
	var history := _scene_history()
	if history == null or not history.has_undo(): status_label.text = "没有可撤销的角色装配动作，请先完成一次装配（character.undo_unavailable）。"; return
	editor_plugin.get_editor_interface().get_selection().clear()
	history.undo()
	status_label.text = "已撤销正式装配动作。"

func _on_redo() -> void:
	var history := _scene_history()
	if history == null or not history.has_redo(): status_label.text = "没有可重做的角色装配动作，请先撤销一次装配（character.redo_unavailable）。"; return
	editor_plugin.get_editor_interface().get_selection().clear()
	history.redo()
	status_label.text = "已重做正式装配动作。"

func _scene_history() -> UndoRedo:
	var root := editor_plugin.get_editor_interface().get_edited_scene_root()
	if root == null: return null
	return undo_redo.get_history_undo_redo(undo_redo.get_object_history_id(root))

func _on_save() -> void:
	if assembled == null or not is_instance_valid(assembled) or assembled.get_parent() == null:
		status_label.text = "没有可保存的装配结果，请先装配并确保角色仍属于当前场景（character.save_missing）。"
		return
	var path := save_path_edit.text.strip_edges()
	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		status_label.text = "保存位置无效，请填写 res:// 开头且以 .tscn 结尾的项目路径（character.save_path_invalid）。"
		return
	var result := GMCharacterAssembler.pack_and_save(assembled,path)
	if result.ok:
		last_saved_path = path
		status_label.text = "真实保存完成：%s" % path
	else:
		status_label.text = "角色场景保存失败，请检查路径权限和装配状态后重试（%s）。" % result.get("code","character.pack_failed")

func _selection_summary() -> String:
	var visual_name := "%s（%s）" % [visual_set.display_name_zh,visual_set.visual_set_id] if visual_set != null else "未选择"
	var role_name := "%s（%s）" % [role.display_name_zh,role.role_id] if role != null else "未选择"
	var collision_name := "矩形（RectangleShape2D）" if collision is RectangleShape2D else ("圆形（CircleShape2D）" if collision is CircleShape2D else (collision.get_class() if collision != null else "未选择"))
	return "角色外观：%s | 身份配置：%s | 碰撞形状：%s" % [visual_name,role_name,collision_name]

func _add_field_label(text: String, tooltip: String) -> void:
	var label := Label.new()
	label.text = text
	label.tooltip_text = tooltip
	add_child(label)

func get_capture_snapshot() -> Dictionary:
	var root := editor_plugin.get_editor_interface().get_edited_scene_root() if editor_plugin != null else null
	return {"formal_editor_entry":true,"formal_drag_controls":resource_palette != null and drop_target != null,"undo_redo_manager":undo_redo != null,"selected":{"visual_set_id":visual_set.visual_set_id if visual_set != null else "","role_id":role.role_id if role != null else "","collision":collision.get_class() if collision != null else ""},"assembled_in_scene":assembled != null and is_instance_valid(assembled) and assembled.get_parent() == root and assembled.owner == root and assembled.visible,"stable_instance_id":assembled.stable_instance_id if assembled != null and is_instance_valid(assembled) else "","saved_path":last_saved_path,"status":status_label.text if status_label != null else "","palette":resource_palette.lifecycle_facts() if resource_palette != null else {},"drop_target":drop_target.lifecycle_facts() if drop_target != null else {},"imports":import_facts.duplicate(true),"deferred":{"movement":"P15","reservation":"P16","behavior_schedule_activation_policy":"P17"}}

func cleanup_capture_state() -> void:
	if editor_plugin != null: editor_plugin.get_editor_interface().get_selection().clear()
	var history := _scene_history()
	if history != null: history.clear_history()
	assembled = null
	visual_set = null
	role = null
	collision = null
	import_facts.clear()
	if resource_palette != null: resource_palette.last_payload.clear()
