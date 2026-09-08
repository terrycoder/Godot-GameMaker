@tool
class_name GMContentTypeRegistry
extends RefCounted

const DEFINITION_SCRIPT := preload("res://gm_runtime/content/gm_content_type_definition.gd")

## 注册表只建立内存索引；磁盘上的每个 GMContentTypeDefinition Resource 才是事实源。
## 不生成 JSON 主库，也不缓存一份运行时内容副本。
static func scan(root_paths: Array[String] = ["res://gm_runtime/content"]) -> Dictionary:
	var definitions: Array[GMContentTypeDefinition] = []
	var issues: Array[Dictionary] = []
	var files: Array[String] = []
	for root in root_paths:
		_collect_files(root, files)
	for path in files:
		if not path.ends_with(".tres") and not path.ends_with(".res"): continue
		var resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
		if resource == null:
			issues.append({"code": "type.invalid_resource", "path": path, "reason_zh": "类型注册 Resource 无法加载。"})
			continue
		if resource is GMContentTypeDefinition:
			var definition: GMContentTypeDefinition = resource
			var validation := _validate_definition(definition, path)
			issues.append_array(validation.issues)
			if validation.ok: definitions.append(definition)
	var by_id := {}
	for definition in definitions:
		if by_id.has(definition.content_type_id):
			issues.append({"code": "type.duplicate_id", "path": definition.resource_path, "reason_zh": "内容类型 ID 重复：%s" % definition.content_type_id})
		else: by_id[definition.content_type_id] = definition
	return {"ok": issues.is_empty(), "definitions": definitions, "by_id": by_id, "issues": issues, "file_count": files.size()}

static func get_definition(content_type_id: String, root_paths: Array[String] = ["res://gm_runtime/content"]) -> GMContentTypeDefinition:
	var result := scan(root_paths)
	return result.by_id.get(content_type_id, null)

static func _validate_definition(definition: GMContentTypeDefinition, path: String) -> Dictionary:
	var issues: Array[Dictionary] = []
	if definition.content_type_id.strip_edges().is_empty(): issues.append({"code":"type.empty_id","path":path,"reason_zh":"内容类型 ID 不能为空。"})
	if definition.display_name_zh.strip_edges().is_empty(): issues.append({"code":"type.empty_name","path":path,"reason_zh":"内容类型中文名不能为空。"})
	if definition.generated_class_name.strip_edges().is_empty(): issues.append({"code":"type.empty_class","path":path,"reason_zh":"内容类型 class_name 不能为空。"})
	if not definition.default_directory.begins_with("res://") or definition.default_directory.contains(".."):
		issues.append({"code":"type.illegal_path","path":path,"reason_zh":"内容类型默认目录不是合法 res:// 路径。"})
	if definition.editable_fields.size() != definition.editable_field_labels_zh.size() or definition.editable_fields.size() != definition.editable_field_help_zh.size():
		issues.append({"code":"type.field_metadata_count","path":path,"reason_zh":"可编辑字段必须同时提供稳定属性名、中文显示名和中文帮助文本。"})
	for metadata in definition.get_editable_field_metadata():
		if str(metadata.property_name).strip_edges().is_empty() or str(metadata.label_zh).strip_edges().is_empty() or str(metadata.help_zh).strip_edges().is_empty():
			issues.append({"code":"type.field_metadata_empty","path":path,"reason_zh":"可编辑字段元数据不能有空的属性名、中文显示名或帮助文本。"})
	return {"ok": issues.is_empty(), "issues": issues}

static func _collect_files(path: String, result: Array[String]) -> void:
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
