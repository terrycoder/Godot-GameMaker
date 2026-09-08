class_name GMTileMapDualAdapter
extends RefCounted

static func verify() -> Dictionary:
	for plugin in GMPlatform.plugin_report().plugins:
		if plugin.id == "tile_map_dual": return plugin
	return {"ok": false, "error_zh": "TileMapDual适配器未找到正式锁定项"}
