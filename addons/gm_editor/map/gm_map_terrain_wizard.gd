@tool
class_name GMMapTerrainWizard
extends RefCounted

const SUPPORTED_GRIDS := ["square", "isometric", "hex_smoke"]

static func validate_tileset(tile_set: TileSet, expected_tile_size: Vector2i, grid_type: String, import_facts: Dictionary = {}) -> Dictionary:
	var errors: Array[Dictionary] = []
	if tile_set == null:
		errors.append(_error("map.tileset_missing", "未选择TileSet"))
		return _result(errors, {})
	if tile_set.tile_size != expected_tile_size:
		errors.append(_error("map.tileset_size_mismatch", "TileSet尺寸错误：需要%s，实际%s" % [expected_tile_size, tile_set.tile_size]))
	if grid_type not in SUPPORTED_GRIDS:
		errors.append(_error("map.grid_unsupported", "不支持的网格类型：%s" % grid_type))
	var expected_shape := TileSet.TILE_SHAPE_SQUARE
	if grid_type == "isometric": expected_shape = TileSet.TILE_SHAPE_ISOMETRIC
	elif grid_type == "hex_smoke": expected_shape = TileSet.TILE_SHAPE_HEXAGON
	if tile_set.tile_shape != expected_shape:
		errors.append(_error("map.tileset_grid_mismatch", "TileSet网格形状与地图类型不一致"))
	var terrain_tiles := 0
	var alternatives := 0
	for source_index in tile_set.get_source_count():
		var source := tile_set.get_source(tile_set.get_source_id(source_index))
		if not source is TileSetAtlasSource: continue
		for tile_index in source.get_tiles_count():
			var coords := source.get_tile_id(tile_index)
			alternatives += maxi(0, source.get_alternative_tiles_count(coords) - 1)
			var data: TileData = source.get_tile_data(coords, 0)
			if data != null and (data.terrain >= 0 or data.terrain_set >= 0): terrain_tiles += 1
	if alternatives > 0: errors.append(_error("map.alternative_tiles_unsupported", "TileMapDual v5.0.2不支持alternative tile，请移除后重试"))
	var required := 15 if grid_type in ["square", "isometric"] else 1
	if terrain_tiles < required: errors.append(_error("map.neighbor_tiles_missing", "邻接瓦片不足：需要至少%d个，实际%d个" % [required, terrain_tiles]))
	if not bool(import_facts.get("filter_disabled", false)):
		errors.append(_error("map.import_filter_invalid", "像素瓦片导入参数错误：必须关闭纹理过滤"))
	if bool(import_facts.get("mipmaps_enabled", false)):
		errors.append(_error("map.import_mipmaps_invalid", "像素瓦片导入参数错误：必须关闭mipmap"))
	var config := {"schema": "gm.tile-map-dual-terrain.v1", "grid_type": grid_type, "tile_size": expected_tile_size, "tileset_path": tile_set.resource_path, "plugin_version": "v5.0.2", "copies_source_art": false}
	return _result(errors, config)

static func _error(code: String, message: String) -> Dictionary:
	return {"code": code, "error_zh": message}

static func _result(errors: Array[Dictionary], config: Dictionary) -> Dictionary:
	return {"ok": errors.is_empty(), "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh), "adapter_config": config}
