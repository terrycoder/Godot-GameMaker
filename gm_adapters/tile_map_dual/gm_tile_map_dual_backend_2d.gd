@tool
class_name GMTileMapDualBackend2D
extends GMMapBackend

const EXPECTED_VERSION := "v5.0.2"
const PLUGIN_CFG := "res://addons/TileMapDual/plugin.cfg"
const PUBLIC_SCRIPT := "res://addons/TileMapDual/tile_map_dual.gd"

var availability_override: Dictionary = {}

func backend_id() -> StringName:
	return &"gm.map_backend.tile_map_dual_2d"

func availability() -> Dictionary:
	if not availability_override.is_empty(): return availability_override.duplicate(true)
	if not FileAccess.file_exists(PLUGIN_CFG): return _closed("map.plugin_missing", "TileMapDual插件缺失，地图已关闭式进入只读；资源未改写")
	var cfg := ConfigFile.new()
	if cfg.load(PLUGIN_CFG) != OK: return _closed("map.plugin_config_invalid", "TileMapDual插件配置无法读取，地图已进入只读")
	var version := str(cfg.get_value("plugin", "version", ""))
	if version != EXPECTED_VERSION: return _closed("map.plugin_version_mismatch", "TileMapDual版本错误：需要%s，实际%s；地图已进入只读" % [EXPECTED_VERSION, version])
	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	if not enabled.has(PLUGIN_CFG): return _closed("map.plugin_disabled", "TileMapDual插件未启用，地图已关闭式进入只读")
	if not FileAccess.file_exists(PUBLIC_SCRIPT): return _closed("map.plugin_lock_conflict", "TileMapDual锁路径冲突或运行时脚本缺失，地图已进入只读")
	return {"ok": true, "read_only": false, "plugin_version": version, "plugin_path": PLUGIN_CFG}

func create_layer_node(definition: GMMapLayerDefinition, tile_set: TileSet = null) -> Dictionary:
	var health := availability()
	if not health.ok: return health
	if definition == null: return _closed("map.layer_null", "不能为缺失图层创建节点")
	var script: Script = load(PUBLIC_SCRIPT)
	if script == null: return _closed("map.plugin_load_failed", "TileMapDual公共节点脚本加载失败，地图已进入只读")
	var node: Node = script.new()
	node.name = str(definition.layer_id).validate_node_name()
	node.set("tile_set", tile_set)
	node.visible = definition.visible
	node.z_index = definition.draw_order
	node.set_meta("gm_layer_id", str(definition.layer_id))
	return {"ok": true, "node": node, "adapter_boundary": PUBLIC_SCRIPT}

func apply_visual_batch(node: Node, changes: Dictionary) -> Dictionary:
	var health := availability()
	if not health.ok: return health
	if node == null or not node.has_method("draw_cell"): return _closed("map.backend_node_invalid", "TileMapDual节点无公共draw_cell接口")
	for key in changes:
		var parts := str(key).split(",")
		if parts.size() != 2: return _closed("map.cell_key_invalid", "无效单元坐标：%s" % key)
		node.call("draw_cell", Vector2i(int(parts[0]), int(parts[1])), int(changes[key]))
	return {"ok": true, "changed_count": changes.size()}

func _closed(code: String, message: String) -> Dictionary:
	return {"ok": false, "read_only": true, "code": code, "error_zh": message, "resource_mutated": false}
