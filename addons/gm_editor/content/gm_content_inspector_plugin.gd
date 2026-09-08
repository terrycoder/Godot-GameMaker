@tool
class_name GMContentInspectorPlugin
extends EditorInspectorPlugin

const REGISTRY_SCRIPT := preload("res://gm_runtime/content/gm_content_type_registry.gd")
const PROPERTY_SCRIPT := preload("res://addons/gm_editor/content/gm_chinese_editor_property.gd")
const PROFILE_SCRIPT := preload("res://gm_runtime/gm_project_profile.gd")

const BASE_LABELS := {
	"display_name_zh": "中文名称",
	"content_id": "稳定业务 ID",
	"content_type_id": "内容类型 ID",
	"tags": "标签",
	"content_version": "内容版本",
	"source": "来源",
	"deprecated": "已废弃",
	"aliases": "别名",
	"migration_from_ids": "迁移旧 ID",
	"migration_target_id": "迁移目标 ID",
	"migration_notes_zh": "迁移说明",
	"content_reference_ids": "业务引用 ID",
	"ability_package_ids": "能力包 ID",
	"thumbnail": "缩略图",
	"thumbnail_path": "缩略图路径",
}

const BASE_HELP := {
	"display_name_zh": "内容在编辑器和资源库中的中文显示名称。",
	"content_id": "跨文件移动仍保持不变的稳定业务身份，格式为 namespace.name。",
	"content_type_id": "由类型注册 Resource 声明的稳定内容类型。",
	"tags": "用于内容浏览器筛选的标签集合。",
	"content_version": "内容版本，不等同于文件路径或 ResourceUID。",
	"source": "内容来源说明，不会被引用图当作强引用。",
	"deprecated": "标记为废弃后仍可由迁移/别名链兼容读取。",
	"thumbnail": "真实 Texture2D Resource 缩略图；缺失时内容浏览器使用占位。",
}

const PROFILE_LABELS := {
	"template_id": "项目模板 ID",
	"enabled_modules": "启用模块",
	"spatial_domain_id": "空间域 ID",
	"spatial_backend_id": "空间后端 ID",
	"spatial_backend_enabled": "空间后端启用",
}

const PROFILE_HELP := {
	"template_id": "项目模板稳定 ID；模板切换仍由工作台执行验证和保存。",
	"enabled_modules": "现有 ModuleManifest 选择；空间后端只通过这里注册的模块加载。",
	"spatial_domain_id": "空间域稳定 ID。平面3D目前只保留声明，启用时会中文失败关闭。",
	"spatial_backend_id": "空间后端稳定 ID；不保存节点、RID或后端实例。",
	"spatial_backend_enabled": "启用同一 SceneContext 的空间执行后端；失败不会写入无效配置。",
}

var _registry_snapshot: Dictionary = {}
var _last_snapshot: Dictionary = {}

func _can_handle(object: Object) -> bool:
	return object is GMContent or _is_profile(object)

func _parse_begin(object: Object) -> void:
	if _is_profile(object):
		var profile = object
		_last_snapshot = {
			"sentinel": "GM_CHINESE_PROFILE_INSPECTOR",
			"same_resource": true,
			"resource_path": profile.resource_path,
			"spatial_domain_id": str(_profile_value(profile, "spatial_domain_id", "")),
			"spatial_backend_id": str(_profile_value(profile, "spatial_backend_id", "")),
			"spatial_backend_enabled": bool(_profile_value(profile, "spatial_backend_enabled", false)),
			"rendered_properties": [],
		}
		var header := VBoxContainer.new()
		header.name = "GM中文项目ProfileInspector标题"
		var title := Label.new()
		title.text = "GM 项目配置 · 空间域与后端"
		title.add_theme_font_size_override("font_size", 16)
		header.add_child(title)
		var summary := Label.new()
		summary.text = "空间域：%s\n空间后端：%s；启用：%s\nPLANAR_3D当前仅保留声明，保存与运行均失败关闭。" % [str(_profile_value(profile, "spatial_domain_id", "")), str(_profile_value(profile, "spatial_backend_id", "")), "是" if bool(_profile_value(profile, "spatial_backend_enabled", false)) else "否"]
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header.add_child(summary)
		add_custom_control(header)
		return
	var content: GMContent = object
	_registry_snapshot = REGISTRY_SCRIPT.scan(["res://gm_runtime/content"])
	var definition: GMContentTypeDefinition = _registry_snapshot.get("by_id", {}).get(content.content_type_id, null)
	var type_title := definition.display_name_zh if definition != null else content.content_type_id
	_last_snapshot = {
		"sentinel": "GM_CHINESE_INSPECTOR",
		"same_resource": true,
		"resource_path": content.resource_path,
		"content_id": content.content_id,
		"content_type_id": content.content_type_id,
		"type_title_zh": type_title,
		"base_field_summary": {"中文名称":content.display_name_zh,"稳定业务 ID":content.content_id,"标签":content.tags,"内容版本":content.content_version,"来源":content.source},
		"rendered_properties": [],
		"field_metadata": definition.get_editable_field_metadata() if definition != null else [],
	}
	var header := VBoxContainer.new()
	header.name = "GM中文Inspector标题"
	var title := Label.new()
	title.text = "GM 内容 · %s" % type_title
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)
	var identity := Label.new()
	identity.text = "稳定业务 ID：%s    类型：%s" % [content.content_id, content.content_type_id]
	identity.tooltip_text = "正在编辑当前 Resource：%s" % content.resource_path
	header.add_child(identity)
	var summary := Label.new()
	summary.name = "GM中文Inspector稳定字段摘要"
	summary.text = "中文名称：%s    标签：%s\n内容版本：%s    来源：%s" % [content.display_name_zh, ", ".join(Array(content.tags)), content.content_version, content.source]
	summary.tooltip_text = "以下字段仍由本 Inspector 的原生 EditorProperty 直接编辑同一 Resource。"
	header.add_child(summary)
	add_custom_control(header)

func _parse_property(object, _type, name: String, _hint_type, _hint_string, _usage_flags, _wide) -> bool:
	if _is_profile(object):
		if not PROFILE_LABELS.has(name): return false
		var profile_editor: GMChineseEditorProperty = PROPERTY_SCRIPT.new()
		var profile_kind := "bool" if name == "spatial_backend_enabled" else ("string_array" if name == "enabled_modules" else "string")
		profile_editor.configure(profile_kind, str(PROFILE_HELP.get(name, "在同一项目Profile上直接编辑。")))
		add_property_editor(name, profile_editor, false, str(PROFILE_LABELS[name]))
		var profile_rendered: Array = _last_snapshot.get("rendered_properties", [])
		profile_rendered.append({"property_name":name,"label_zh":str(PROFILE_LABELS[name]),"help_zh":str(PROFILE_HELP.get(name, "")),"kind":profile_kind})
		_last_snapshot["rendered_properties"] = profile_rendered
		return true
	if not object is GMContent: return false
	var label := ""
	var help_text := ""
	var kind := "string"
	if BASE_LABELS.has(name):
		label = str(BASE_LABELS[name])
		help_text = str(BASE_HELP.get(name, "在当前 Resource 上直接编辑，不生成第二份配置。"))
		kind = _kind_for_base_property(name)
	else:
		var definition: GMContentTypeDefinition = _registry_snapshot.get("by_id", {}).get(str(object.content_type_id), null)
		if definition == null: return false
		var metadata := definition.get_editable_field_metadata_for(name)
		if metadata.is_empty(): return false
		label = str(metadata.label_zh)
		help_text = str(metadata.help_zh)
		kind = "multiline" if name.ends_with("_zh") or name.contains("description") else "string"
		if name == "linked_content": kind = "resource"
	if label.is_empty() or help_text.is_empty(): return false
	var editor: GMChineseEditorProperty = PROPERTY_SCRIPT.new()
	editor.configure(kind, help_text)
	add_property_editor(name, editor, false, label)
	var rendered: Array = _last_snapshot.get("rendered_properties", [])
	rendered.append({"property_name":name,"label_zh":label,"help_zh":help_text,"kind":kind})
	_last_snapshot["rendered_properties"] = rendered
	return true

func _kind_for_base_property(name: String) -> String:
	if name == "deprecated": return "bool"
	if name in ["tags", "aliases", "migration_from_ids", "content_reference_ids", "ability_package_ids"]: return "string_array"
	if name == "migration_notes_zh": return "multiline"
	if name == "thumbnail": return "texture"
	return "string"

func get_capture_snapshot() -> Dictionary:
	return _last_snapshot.duplicate(true)

func _is_profile(object: Object) -> bool:
	return object is Resource and object.get_script() == PROFILE_SCRIPT

func _profile_value(profile: Resource, property_name: String, fallback: Variant) -> Variant:
	var value = profile.get(property_name)
	return fallback if value == null else value
