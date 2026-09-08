@tool
class_name GMMapEditSession
extends RefCounted

const CHUNK_SIZE := 256

var map: GMMapResource
var last_operation: Dictionary = {}

func _init(target_map: GMMapResource = null) -> void:
	map = target_map

func brush(layer_id: StringName, cells: Array[Vector2i], terrain_id: int, undo_redo: Object) -> Dictionary:
	var values := {}
	for cell in cells: values[GMMapResource.cell_key(cell)] = terrain_id
	return _commit("地图画笔", layer_id, values, undo_redo)

func rectangle(layer_id: StringName, area: Rect2i, terrain_id: int, undo_redo: Object) -> Dictionary:
	var values := {}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x): values[GMMapResource.cell_key(Vector2i(x, y))] = terrain_id
	return _commit("地图矩形", layer_id, values, undo_redo)

func replace(layer_id: StringName, from_terrain: int, to_terrain: int, undo_redo: Object) -> Dictionary:
	var values := {}
	for key in map.visual_cells.get(str(layer_id), {}):
		if int(map.visual_cells[str(layer_id)][key]) == from_terrain: values[key] = to_terrain
	return _commit("地图替换", layer_id, values, undo_redo)

func selection(layer_id: StringName, cells: Array[Vector2i], terrain_id: int, undo_redo: Object) -> Dictionary:
	return brush(layer_id, cells, terrain_id, undo_redo).merged({"tool": "selection"}, true)

func fill(layer_id: StringName, origin: Vector2i, terrain_id: int, undo_redo: Object) -> Dictionary:
	if map == null or not map.in_bounds(origin): return {"ok": false, "code": "map.fill_out_of_bounds", "error_zh": "填充起点越界：%s" % origin}
	var layer := map.get_layer(layer_id)
	if layer == null: return {"ok": false, "code": "map.layer_missing", "error_zh": "找不到图层：%s" % layer_id}
	var permission := layer.can_edit()
	if not permission.ok: return permission
	var source: Dictionary = map.visual_cells.get(str(layer_id), {})
	var target := int(source.get(GMMapResource.cell_key(origin), -1))
	if target == terrain_id: return {"ok": true, "changed_count": 0, "undo_actions": 0}
	var queue: Array[Vector2i] = [origin]
	var visited := {}
	var values := {}
	while not queue.is_empty():
		var cell := queue.pop_front()
		var key := GMMapResource.cell_key(cell)
		if key in visited or not map.in_bounds(cell): continue
		visited[key] = true
		if int(source.get(key, -1)) != target: continue
		values[key] = terrain_id
		queue.append_array([cell + Vector2i.LEFT, cell + Vector2i.RIGHT, cell + Vector2i.UP, cell + Vector2i.DOWN])
	return _commit("地图填充", layer_id, values, undo_redo)

func _commit(action_name: String, layer_id: StringName, values: Dictionary, undo_redo: Object) -> Dictionary:
	if map == null: return {"ok": false, "code": "map.resource_missing", "error_zh": "地图资源缺失"}
	var layer := map.get_layer(layer_id)
	if layer == null: return {"ok": false, "code": "map.layer_missing", "error_zh": "找不到图层：%s" % layer_id}
	var permission := layer.can_edit()
	if not permission.ok: return permission
	var before := {}
	var cells: Dictionary = map.visual_cells.get(str(layer_id), {})
	for key in values:
		var parts := str(key).split(",")
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		if not map.in_bounds(cell): return {"ok": false, "code": "map.selection_out_of_bounds", "error_zh": "选区包含越界单元：%s" % cell}
		before[key] = cells.get(key, null)
	if undo_redo == null or not undo_redo.has_method("create_action"):
		return {"ok": false, "code": "map.undo_gateway_missing", "error_zh": "缺少正式撤销入口，拒绝批量绘制"}
	var history_id := -99
	if undo_redo is EditorUndoRedoManager:
		undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, map)
		undo_redo.add_do_method(self, &"_apply_values", layer_id, values)
		undo_redo.add_undo_method(self, &"_apply_values", layer_id, before)
		undo_redo.commit_action()
		history_id = undo_redo.get_object_history_id(map)
	else:
		undo_redo.create_action(action_name)
		undo_redo.add_do_method(_apply_values.bind(layer_id, values))
		undo_redo.add_undo_method(_apply_values.bind(layer_id, before))
		undo_redo.commit_action()
	last_operation = {"ok": true, "action": action_name, "changed_count": values.size(), "chunk_count": ceili(float(values.size()) / CHUNK_SIZE), "undo_actions": 1, "per_cell_undo_actions": false, "formal_editor_history_id": history_id, "gateway_class": undo_redo.get_class()}
	return last_operation.duplicate(true)

func _apply_values(layer_id: StringName, values: Dictionary) -> void:
	var cells: Dictionary = map.visual_cells.get(str(layer_id), {})
	for key in values:
		if values[key] == null: cells.erase(key)
		else: cells[key] = values[key]
	map.visual_cells[str(layer_id)] = cells
	map.emit_changed()
