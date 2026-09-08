@tool
class_name GMErrorCenter
extends RefCounted

const PLATFORM := preload("res://gm_runtime/gm_platform.gd")
const TEMPLATES := preload("res://addons/gm_editor/templates/gm_template_catalog.gd")
const EXPORT_PLANNER := preload("res://gm_runtime/gm_export_planner.gd")

var errors: Array[Dictionary] = []
var last_scan: Dictionary = {}

func clear() -> void:
	errors.clear()

func add_error(code: String, source: String, object_name_zh: String, resource_path: String, field_name_zh: String, reason_zh: String, suggestion_zh: String, line: int = 0, field_name: String = "") -> void:
	errors.append({
		"id": "%s.%d" % [code, errors.size() + 1],
		"code": code,
		"source": source,
		"severity": "error",
		"object_name_zh": object_name_zh,
		"resource_path": resource_path,
		"field_name_zh": field_name_zh,
		"field_name": field_name,
		"reason_zh": reason_zh,
		"suggestion_zh": suggestion_zh,
		"line": line,
		"locatable": _path_exists(resource_path),
		"location_state": "可定位" if _path_exists(resource_path) else "定位已失效",
	})

func scan(profile: Resource, subject: Resource = null, export_fixture: String = "") -> Array[Dictionary]:
	clear()
	if profile == null:
		add_error("profile.invalid", "validation", "项目配置", "res://gm_runtime/gm_module_profile.tres", "项目配置", "GMProjectProfile 不存在。", "恢复 Profile 后重新扫描。")
	else:
		var validation := TEMPLATES.validate_profile(profile)
		if not validation.ok:
			for reason in validation.errors_zh:
				var code := "template.missing_module" if str(reason).contains("模块") else "template.missing_terminology"
				add_error(code, "validation", "策划模板", "res://addons/gm_editor/templates/%s.tres" % profile.template_id, "模板配置", str(reason), "打开模板帮助并修复 Profile 或模板定义。")
		var platform := PLATFORM.environment()
		if not platform.ok:
			for failure in platform.plugins.required_failures:
				add_error("plugin.failure", "plugin", str(failure), "res://addons/gm_editor/plugin.cfg", "插件锁定", "插件或平台基线验证失败。", "修复插件版本或启停状态后重载项目。")
	if subject != null:
		var project_name := str(subject.get("project_name_zh"))
		if project_name.strip_edges().is_empty():
			add_error("content.missing_name", "validation", "工作台演示项目", subject.resource_path, "项目名称", "项目名称不能为空。", "在策划模式或高级 Inspector 中填写中文项目名称。")
	if not export_fixture.is_empty():
		var profile_for_export: Resource = profile
		var result := EXPORT_PLANNER.plan(profile_for_export, export_fixture)
		if not result.ok:
			var detail := str(result.get("error_zh", "导出预检被阻断"))
			add_error("export.blocked", "export", "导出预检", export_fixture, "导出依赖", detail, "按 source→target 原因链修复非法依赖后重新导出。")
	last_scan = {"count": errors.size(), "sources": _source_counts(), "ok": errors.is_empty()}
	return errors.duplicate(true)

func add_missing_location_error(path: String, object_name_zh: String = "已删除资源") -> void:
	add_error("resource.invalid_location", "validation", object_name_zh, path, "资源路径", "资源已删除、移动或插件已关闭，当前定位失效。", "重新扫描引用图或从资源库选择新的位置。")

func locate(index: int, editor_interface: EditorInterface) -> Dictionary:
	if index < 0 or index >= errors.size():
		return {"ok": false, "state": "不存在", "message_zh": "错误项已不存在，请重新扫描。"}
	var entry := errors[index]
	var path := str(entry.resource_path)
	if path.is_empty() or not _path_exists(path):
		entry.locatable = false
		entry.location_state = "定位已失效"
		entry.location_message_zh = "定位已失效：资源已删除、移动或插件已关闭；错误中心仍可安全显示。"
		errors[index] = entry
		return {"ok": false, "state": "失效", "message_zh": entry.location_message_zh}
	if path.ends_with(".tscn"):
		editor_interface.open_scene_from_path(path)
	else:
		var resource = load(path)
		if resource != null:
			editor_interface.edit_resource(resource)
			var stable_field := str(entry.get("field_name", ""))
			if not stable_field.is_empty() and editor_interface.has_method("inspect_object"):
				editor_interface.inspect_object(resource, stable_field)
				entry["located_field"] = stable_field
		else:
			entry.locatable = false
			entry.location_state = "定位已失效"
			errors[index] = entry
			return {"ok": false, "state": "失效", "message_zh": "资源无法加载，定位已失效。"}
	entry.location_state = "已打开原生编辑器并定位字段" if not str(entry.get("located_field", "")).is_empty() else "已打开原生编辑器"
	errors[index] = entry
	return {"ok": true, "state": "已定位", "field": str(entry.get("located_field", "")), "message_zh": "已打开 Godot 原生资源或场景编辑器，并定位字段：%s。" % entry.located_field if entry.has("located_field") else "已打开 Godot 原生资源或场景编辑器。"}

func _source_counts() -> Dictionary:
	var counts := {}
	for entry in errors: counts[entry.source] = int(counts.get(entry.source, 0)) + 1
	return counts

func _path_exists(path: String) -> bool:
	return not path.is_empty() and FileAccess.file_exists(path)
