@tool
class_name GMContentValidator
extends RefCounted

const CONTENT_SCRIPT_PATH := "res://gm_runtime/content/gm_content.gd"

static func validate_content(resource: Resource, path: String = "", seen_ids: Dictionary = {}, allow_platform_namespace: bool = false) -> Dictionary:
	var errors: Array[Dictionary] = []
	if resource == null:
		_add(errors, "content.load_failed", path, "资源无法加载。", "修复损坏的 Resource 或未知脚本后重新扫描。")
		return _result(errors)
	if not resource is GMContent:
		_add(errors, "content.not_gm_content", path, "资源没有继承 GMContent，不能进入 GM 内容资源库。", "让内容脚本继承 GMContent。")
		return _result(errors)
	var content: GMContent = resource
	var id_result := validate_business_id(content.content_id, allow_platform_namespace)
	if not id_result.ok: _append_errors(errors, id_result.errors, path)
	if seen_ids.has(content.content_id) and not str(seen_ids[content.content_id]).is_empty():
		_add(errors, "content.duplicate_id", path, "业务 ID 重复：%s；已有位置：%s" % [content.content_id, seen_ids[content.content_id]], "修改业务 ID 或通过别名/迁移表保留旧 ID。")
	var type_result := validate_business_id(content.content_type_id, true)
	if not type_result.ok: _append_errors(errors, type_result.errors, path)
	if content.display_name_zh.strip_edges().is_empty(): _add(errors, "content.empty_name", path, "中文名称不能为空。", "在 Inspector 中填写可识别的中文名称。")
	if content.content_version.strip_edges().is_empty(): _add(errors, "content.empty_version", path, "内容版本不能为空。", "填写例如 1.0.0 的内容版本。")
	if content.tags.size() != _unique_count(content.tags): _add(errors, "content.duplicate_tag", path, "标签不能重复。", "删除重复标签后重新保存。")
	var aliases := {}
	for alias in content.aliases:
		var alias_result := validate_business_id(str(alias), allow_platform_namespace)
		if not alias_result.ok: _append_errors(errors, alias_result.errors, path)
		if str(alias) == content.content_id: _add(errors, "content.alias_same_id", path, "别名不能与当前业务 ID 相同。", "删除相同别名。")
		if aliases.has(str(alias)): _add(errors, "content.duplicate_alias", path, "别名重复：%s" % str(alias), "保留一条别名。")
		aliases[str(alias)] = true
	for reference_id in content.get_declared_business_references():
		var ref_result := validate_business_id(reference_id, true)
		if not ref_result.ok: _append_errors(errors, ref_result.errors, path)
	if not content.migration_target_id.is_empty():
		var target_result := validate_business_id(content.migration_target_id, allow_platform_namespace)
		if not target_result.ok: _append_errors(errors, target_result.errors, path)
	if not content.thumbnail_path.is_empty() and not FileAccess.file_exists(content.thumbnail_path):
		_add(errors, "content.thumbnail_missing", path, "缩略图路径不存在：%s" % content.thumbnail_path, "清空缩略图或选择存在的图片。")
	return _result(errors)

static func validate_business_id(value: String, allow_platform_namespace: bool = false) -> Dictionary:
	var errors: Array[Dictionary] = []
	var normalized := value.strip_edges()
	if normalized.is_empty():
		_add(errors, "id.empty", "", "业务 ID 不能为空。", "填写命名空间.名称格式的稳定业务 ID。")
		return _result(errors)
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9]*(\\.[a-z0-9][a-z0-9_-]*)+$")
	if regex.search(normalized) == null:
		_add(errors, "id.invalid_format", "", "业务 ID 格式非法：%s；必须使用小写命名空间.名称。" % normalized, "例如 demo.faction.moon；不要使用文件名替代业务 ID。")
	if normalized.begins_with("gm.") and not allow_platform_namespace:
		_add(errors, "id.illegal_gm_namespace", "", "项目内容不能使用 gm.* 命名空间：%s" % normalized, "改用项目自己的命名空间，例如 demo.*、sw.* 或 mom.*。")
	return _result(errors)

static func validate_path(path: String, allowed_root: String = "") -> Dictionary:
	var errors: Array[Dictionary] = []
	var normalized := path.replace("\\", "/")
	if not normalized.begins_with("res://") or normalized.contains(".."):
		_add(errors, "path.illegal", path, "路径必须是没有 .. 的 res:// 路径。", "选择项目内的内容目录。")
	if not allowed_root.is_empty() and not (normalized == allowed_root or normalized.begins_with(allowed_root.trim_suffix("/") + "/")):
		_add(errors, "path.outside_root", path, "路径超出允许目录：%s" % allowed_root, "选择任务03允许的内容目录。")
	return _result(errors)

static func validate_class_name(value: String) -> Dictionary:
	var errors: Array[Dictionary] = []
	var regex := RegEx.new()
	regex.compile("^[A-Z][A-Za-z0-9]*$")
	if regex.search(value.strip_edges()) == null:
		_add(errors, "script.invalid_class_name", "", "GDScript class_name 非法：%s" % value, "使用大写字母开头的 ASCII 类名，例如 GMFactionContent。")
	return _result(errors)

static func scan_class_names(root_paths: Array[String] = ["res://gm_runtime/content"]) -> Dictionary:
	var result := {}
	var files: Array[String] = []
	for root in root_paths: _collect_files(root, files)
	for path in files:
		if not path.ends_with(".gd"): continue
		var source := FileAccess.get_file_as_string(path)
		var regex := RegEx.new()
		regex.compile("(?m)^\\s*class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
		var match := regex.search(source)
		if match == null: continue
		var class_name_value := match.get_string(1)
		if not result.has(class_name_value): result[class_name_value] = []
		result[class_name_value].append(path)
	return result

static func validate_script(path: String, expected_class_name: String = "", expected_base_class: String = "GMContent") -> Dictionary:
	var errors: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		_add(errors, "script.missing", path, "脚本不存在：%s" % path, "恢复脚本或重新生成完整类型。")
		return _result(errors)
	var source := FileAccess.get_file_as_string(path)
	var script = ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	if script == null or not script is Script:
		_add(errors, "script.syntax", path, "GDScript 无法解析，可能存在语法错误或未知脚本。", "打开原生脚本编辑器修复解析错误。")
	elif source.count("(") != source.count(")") or source.count("[") != source.count("]") or source.count("{") != source.count("}"):
		_add(errors, "script.syntax", path, "GDScript 括号结构不完整，无法通过语法验证。", "检查函数参数、数组和字典的括号。")
	var names := scan_class_names([path.get_base_dir()])
	if not expected_class_name.is_empty() and not names.has(expected_class_name):
		_add(errors, "script.class_missing", path, "脚本缺少 class_name：%s" % expected_class_name, "保留可编辑脚本中的 class_name 声明。")
	if not expected_base_class.is_empty():
		var extends_ok := source.contains("extends %s" % expected_base_class) or source.contains('extends "res://gm_runtime/content/gm_content.gd"')
		if not extends_ok:
			_add(errors, "script.base_mismatch", path, "脚本基类错误：期望继承 %s。" % expected_base_class, "修正 extends 行后重新扫描。")
	return _result(errors)

static func validate_type_definition(definition: GMContentTypeDefinition, known_class_names: Dictionary = {}) -> Dictionary:
	var errors: Array[Dictionary] = []
	var id_result := validate_business_id(definition.content_type_id, false)
	if not id_result.ok: _append_errors(errors, id_result.errors, definition.resource_path)
	var class_result := validate_class_name(definition.generated_class_name)
	if not class_result.ok: _append_errors(errors, class_result.errors, definition.resource_path)
	if definition.display_name_zh.strip_edges().is_empty(): _add(errors, "type.empty_name", definition.resource_path, "类型中文名不能为空。", "填写类型在内容浏览器中的中文名。")
	if not known_class_names.is_empty() and known_class_names.has(definition.generated_class_name):
		_add(errors, "script.duplicate_class_name", definition.resource_path, "class_name 重复：%s" % definition.generated_class_name, "更换类名，不能覆盖已有脚本。")
	var path_result := validate_path(definition.default_directory)
	_append_errors(errors, path_result.errors, definition.resource_path)
	return _result(errors)

static func _result(errors: Array[Dictionary]) -> Dictionary:
	var messages: Array[String] = []
	for error in errors: messages.append(str(error.reason_zh))
	return {"ok": errors.is_empty(), "errors": errors, "errors_zh": messages}

static func _add(errors: Array[Dictionary], code: String, path: String, reason: String, suggestion: String) -> void:
	errors.append({"code":code,"path":path,"reason_zh":reason,"suggestion_zh":suggestion})

static func _append_errors(target: Array[Dictionary], source: Array, fallback_path: String) -> void:
	for error in source:
		var copy: Dictionary = error.duplicate(true)
		if str(copy.get("path", "")).is_empty(): copy.path = fallback_path
		target.append(copy)

static func _unique_count(values: PackedStringArray) -> int:
	var unique := {}
	for value in values: unique[str(value)] = true
	return unique.size()

static func _collect_files(path: String, result: Array[String]) -> void:
	if FileAccess.file_exists(path):
		result.append(path)
		return
	var dir := DirAccess.open(path)
	if dir == null: return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty(): break
		if name in [".", "..", ".godot"]: continue
		var child := path.path_join(name)
		if dir.current_is_dir(): _collect_files(child, result)
		else: result.append(child)
	dir.list_dir_end()
