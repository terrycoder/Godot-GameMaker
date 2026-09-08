@tool
extends RefCounted

static func missing_plugin_message(plugin_name: String, expected_version: String) -> String:
	return "插件“%s”未安装或版本不匹配（期望：%s）。请按插件裁定矩阵安装并重载项目；当前不会静默继续。" % [plugin_name, expected_version]
