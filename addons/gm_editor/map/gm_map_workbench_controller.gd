@tool
class_name GMMapWorkbenchController
extends RefCounted

var session: GMMapEditSession
var editor_undo_redo: EditorUndoRedoManager

func attach_editor_plugin(editor_plugin: EditorPlugin) -> Dictionary:
	if editor_plugin == null:
		return {"ok": false, "code": "map.workbench_editor_missing", "error_zh": "地图工作台缺少编辑器插件上下文"}
	editor_undo_redo = editor_plugin.get_undo_redo()
	return {"ok": editor_undo_redo != null, "undo_gateway": "EditorUndoRedoManager", "title_zh": "GM地图工作台"}

func configure(target_map: GMMapResource, editor_plugin: EditorPlugin) -> Dictionary:
	if target_map == null or editor_plugin == null:
		return {"ok": false, "code": "map.workbench_context_missing", "error_zh": "地图工作台缺少地图资源或编辑器上下文"}
	var attached := attach_editor_plugin(editor_plugin)
	if not attached.ok:
		return attached
	session = GMMapEditSession.new(target_map)
	return {"ok": editor_undo_redo != null, "undo_gateway": "EditorUndoRedoManager", "title_zh": "GM地图工作台"}

func draw_brush(layer_id: StringName, cells: Array[Vector2i], terrain_id: int) -> Dictionary:
	return session.brush(layer_id, cells, terrain_id, editor_undo_redo)

func draw_rectangle(layer_id: StringName, area: Rect2i, terrain_id: int) -> Dictionary:
	return session.rectangle(layer_id, area, terrain_id, editor_undo_redo)

func flood_fill(layer_id: StringName, origin: Vector2i, terrain_id: int) -> Dictionary:
	return session.fill(layer_id, origin, terrain_id, editor_undo_redo)

func replace_terrain(layer_id: StringName, from_terrain: int, to_terrain: int) -> Dictionary:
	return session.replace(layer_id, from_terrain, to_terrain, editor_undo_redo)

func paint_selection(layer_id: StringName, cells: Array[Vector2i], terrain_id: int) -> Dictionary:
	return session.selection(layer_id, cells, terrain_id, editor_undo_redo)
