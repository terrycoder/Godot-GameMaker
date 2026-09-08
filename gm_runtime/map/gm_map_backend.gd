@tool
class_name GMMapBackend
extends RefCounted

func backend_id() -> StringName:
	return &"gm.map_backend.abstract"

func availability() -> Dictionary:
	return {"ok": false, "read_only": true, "code": "map.backend_abstract", "error_zh": "地图后端未配置"}

func create_layer_node(_definition: GMMapLayerDefinition, _tile_set: TileSet = null) -> Dictionary:
	return availability()

func apply_visual_batch(_node: Node, _changes: Dictionary) -> Dictionary:
	return availability()
