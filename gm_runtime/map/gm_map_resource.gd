@tool
class_name GMMapResource
extends Resource

const SCHEMA := "gm.map.v1"

@export var map_id: StringName
@export_enum("square", "isometric", "hex_smoke") var grid_type: String = "square"
@export var map_size: Vector2i = Vector2i(32, 32)
@export var tile_size: Vector2i = Vector2i(32, 32)
@export var backend_id: StringName = &"gm.map_backend.tile_map_dual_2d"
@export var adapter_schema: String = "gm.tile-map-dual-adapter.v1"
@export var plugin_version: String = "v5.0.2"
@export var layers: Array[GMMapLayerDefinition] = []
@export var visual_cells: Dictionary = {}
@export var logic_cells: Dictionary = {}
@export var layer_references: Dictionary = {}
@export var schema_version: String = SCHEMA

static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_size.x and cell.y < map_size.y

func get_layer(layer_id: StringName) -> GMMapLayerDefinition:
	for layer in layers:
		if layer.layer_id == layer_id: return layer
	return null

func add_layer(layer: GMMapLayerDefinition) -> Dictionary:
	if layer == null: return _failure("map.layer_null", "不能添加空图层")
	var validation := layer.validate()
	if not validation.ok: return {"ok": false, "code": "map.layer_invalid", "errors_zh": validation.errors_zh}
	if get_layer(layer.layer_id) != null: return _failure("map.layer_duplicate", "图层ID重复：%s" % layer.layer_id)
	layers.append(layer)
	layers.sort_custom(func(a, b): return a.draw_order < b.draw_order)
	if layer.kind != GMMapLayerDefinition.LayerKind.LOGIC: visual_cells[str(layer.layer_id)] = {}
	return {"ok": true, "layer_id": str(layer.layer_id)}

func remove_layer(layer_id: StringName) -> Dictionary:
	var refs: Array = layer_references.get(str(layer_id), [])
	if not refs.is_empty(): return {"ok": false, "code": "map.layer_referenced", "error_zh": "图层仍被逻辑或对象引用，拒绝删除：%s" % layer_id, "references": refs}
	var layer := get_layer(layer_id)
	if layer == null: return _failure("map.layer_missing", "找不到图层：%s" % layer_id)
	layers.erase(layer)
	visual_cells.erase(str(layer_id))
	return {"ok": true}

func set_visual_cell(layer_id: StringName, cell: Vector2i, terrain_id: int) -> Dictionary:
	if not in_bounds(cell): return _failure("map.cell_out_of_bounds", "单元越界：%s" % cell)
	var layer := get_layer(layer_id)
	if layer == null: return _failure("map.layer_missing", "找不到图层：%s" % layer_id)
	if layer.kind == GMMapLayerDefinition.LayerKind.LOGIC: return _failure("map.visual_on_logic_layer", "逻辑层不能写入表现瓦片")
	var permission := layer.can_edit()
	if not permission.ok: return permission
	var cells: Dictionary = visual_cells.get(str(layer_id), {})
	var key := cell_key(cell)
	if terrain_id < 0: cells.erase(key)
	else: cells[key] = terrain_id
	visual_cells[str(layer_id)] = cells
	return {"ok": true}

func set_logic_cell(cell: Vector2i, value: Dictionary) -> Dictionary:
	if not in_bounds(cell): return _failure("map.cell_out_of_bounds", "逻辑单元越界：%s" % cell)
	var normalized := {
		"ground_type": str(value.get("ground_type", "default")),
		"walkable": bool(value.get("walkable", true)),
		"cost": maxf(0.0, float(value.get("cost", 1.0))),
		"water": bool(value.get("water", false)),
		"height_level": int(value.get("height_level", 0))
	}
	logic_cells[cell_key(cell)] = normalized
	return {"ok": true, "value": normalized}

func validate() -> Dictionary:
	var errors: Array[Dictionary] = []
	if str(map_id).strip_edges().is_empty(): errors.append({"code": "map.id_empty", "error_zh": "地图ID不能为空"})
	if map_size.x <= 0 or map_size.y <= 0: errors.append({"code": "map.size_invalid", "error_zh": "地图尺寸必须大于零"})
	if grid_type not in ["square", "isometric", "hex_smoke"]: errors.append({"code": "map.grid_invalid", "error_zh": "不支持的网格类型：%s" % grid_type})
	var ids := {}
	for layer in layers:
		if str(layer.layer_id) in ids: errors.append({"code": "map.layer_duplicate", "error_zh": "图层ID重复：%s" % layer.layer_id})
		ids[str(layer.layer_id)] = true
		for message in layer.validate().get("errors_zh", []): errors.append({"code": "map.layer_invalid", "error_zh": message})
	return {"ok": errors.is_empty(), "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh)}

func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": message}
