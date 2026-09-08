class_name GMPlanar3DDebugOverlay
extends PanelContainer

@export var character_id: String = ""
var _manager: WeakRef
var _label: Label
var _elapsed := 0.0

func bind_manager(manager: GMVisualBudgetManager3D) -> void:
	_manager = weakref(manager) if manager != null else null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.custom_minimum_size.x = 460
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 16)
	add_child(_label)
	refresh()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.25:
		_elapsed = 0.0
		refresh()

func refresh() -> void:
	if _label == null: return
	var manager = _manager.get_ref() if _manager != null else null
	if not is_instance_valid(manager):
		_label.text = "平面3D诊断（只读）\n预算管理器已释放"
		return
	var row: Dictionary = manager.character_snapshot(character_id)
	if row.is_empty():
		_label.text = "平面3D诊断（只读）\n角色已释放或尚未注册"
		return
	var spatial: Dictionary = row.spatial
	var command: Dictionary = row.movement.get("command", {})
	var path_summary := {"path": command.get("path_points", []), "target": command.get("target", {}), "phase": command.get("phase", "未移动")}
	var report: Dictionary = manager.snapshot()
	var lod_name: String = {"Near": "近景", "Mid": "中景", "Far": "远景", "Offscreen": "屏外"}.get(row.lod, "未知")
	_label.text = "平面3D诊断（只读）\n角色：%s\n层级：%s　采样：%s Hz　次数：%s\n逻辑位置 / 平面：%s\n朝向：%s\n路径 / 目标：%s\n配方：%s\n工位 / 插槽：%s\n动画更新：%s　耗时：%.3f ms\n绘制调用：%d　内存：%.1f MB\n%s" % [character_id, lod_name, str(row.sampling_hz), str(row.sample_count), str(spatial.get("spatial_position", "未绑定空间角色")), str(spatial.get("facing", "不可用")), str(path_summary), str(row.visual.get("recipe_id", "")), str(_socket_snapshot(manager, row)), str(report.get("animation_updates", 0)), float(report.get("animation_cost_ms", 0)), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, "\n".join(report.get("warnings_zh", []))]

func _socket_snapshot(_manager_value: Object, row: Dictionary) -> Dictionary:
	var ids: Array = []
	for socket in row.get("sockets", []): ids.append(socket.get("socket_id", ""))
	return {"workspot_target": row.movement.get("command", {}).get("request", {}).get("target_ref", {}), "sockets": ids}

func displayed_text() -> String:
	return _label.text if _label != null else ""
