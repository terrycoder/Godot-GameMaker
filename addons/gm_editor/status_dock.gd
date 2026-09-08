@tool
extends VBoxContainer

func _ready() -> void:
	name = "GM平台状态"
	custom_minimum_size = Vector2(360, 320)
	var title := Label.new()
	title.text = "GM平台状态"
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)
	var info := Label.new()
	info.name = "检测结果"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(info)
	var hint := Label.new()
	hint.text = "发布 CLI：help / environment / compatibility / validate / modules"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	var module_label := Label.new()
	module_label.text = "生产模块配置：res://gm_runtime/gm_module_profile.tres"
	add_child(module_label)
	_refresh(info)

func _refresh(info: Label) -> void:
	var env: Dictionary = GMPlatform.environment()
	var lines: Array[String] = [
		"主基线：%s" % env.get("godot_baseline", "4.6.2-stable (official)"),
		"平台版本：%s" % env.get("platform_version", "1.0.0"),
		"环境状态：%s" % env.get("status", "unknown"),
	]
	if not bool(env.get("validation_complete", false)):
		lines.append("验证完整性：请运行发布 CLI validate 检查当前生产树。")
	info.text = "\n".join(lines)
