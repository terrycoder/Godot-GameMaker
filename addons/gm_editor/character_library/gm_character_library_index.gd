@tool
class_name GMCharacterLibraryIndex
extends RefCounted

var entries: Array[Dictionary] = []
var issues: Array[Dictionary] = []

func scan(roots: PackedStringArray) -> Dictionary:
	entries.clear()
	issues.clear()
	for root in roots: _scan_dir(root)
	entries.sort_custom(func(a, b): return str(a.content_id) < str(b.content_id))
	return {"ok": true, "count": entries.size(), "issues": issues.duplicate(true)}

func build_from_definitions(definitions: Array) -> Dictionary:
	entries.clear()
	issues.clear()
	for index in definitions.size():
		var definition = definitions[index]
		if definition is GMCharacterDefinition: _append_definition(definition, "memory://%d" % index)
		elif definition is Dictionary: entries.append(definition.duplicate(true))
		else: issues.append(_issue("character.index_entry_invalid", "角色索引项不是 GMCharacterDefinition。", "memory://%d" % index))
	return {"ok": true, "count": entries.size(), "issues": issues.duplicate(true)}

func query(text: String = "", stable_id: String = "", art_style: String = "", category: String = "", tag: String = "", completeness_filter: String = "all") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var needle := text.strip_edges().to_lower()
	for entry in entries:
		if not needle.is_empty() and needle not in (str(entry.display_name_zh) + " " + str(entry.content_id)).to_lower(): continue
		if not stable_id.is_empty() and stable_id.to_lower() not in str(entry.content_id).to_lower(): continue
		if not art_style.is_empty() and art_style != str(entry.art_style): continue
		if not category.is_empty() and category != str(entry.category): continue
		if not tag.is_empty() and not Array(entry.tags).has(tag): continue
		if completeness_filter == "complete" and not bool(entry.complete): continue
		if completeness_filter == "incomplete" and bool(entry.complete): continue
		result.append(entry)
	return result

func generate_bounded_fixture(count: int = 1500) -> Array[Dictionary]:
	var safe_count := clampi(count, 1000, 5000)
	var fixture: Array[Dictionary] = []
	var styles := ["pixel", "painted", "vector"]
	var categories := ["hero", "npc", "enemy", "animal"]
	for index in safe_count:
		fixture.append({
			"display_name_zh": "夹具角色%04d" % index,
			"content_id": "fixture.character.%04d" % index,
			"art_style": styles[index % styles.size()],
			"category": categories[index % categories.size()],
			"tags": ["batch", "even" if index % 2 == 0 else "odd"],
			"complete": index % 5 != 0,
			"completeness_ratio": 1.0 if index % 5 != 0 else 0.8,
			"usage_locations": ["fixture/map_%03d" % (index % 40)],
			"identity_configuration_label": "身份配置%02d" % (index % 12),
			"thumbnail": null, "thumbnail_state": "generated_fixture", "path": "memory://fixture/%04d" % index,
			"definition": null, "visual_set": null, "issues": []
		})
	return fixture

func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: issues.append(_issue("character.scan_root_missing", "角色资源根目录不存在。", path)); return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."): _scan_dir(child)
		elif name.get_extension().to_lower() in ["tres", "res"]:
			if _has_pending_import_dependency(child):
				issues.append(_issue("character.resource_import_pending", "角色资源依赖仍在导入，已延迟到文件系统刷新后重试。", child))
				name = dir.get_next()
				continue
			var resource = ResourceLoader.load(child, "", ResourceLoader.CACHE_MODE_IGNORE)
			if resource is GMCharacterDefinition: _append_definition(resource, child)
			elif resource == null: issues.append(_issue("character.resource_load_failed", "角色资源加载失败，已隔离并继续扫描。", child))
		name = dir.get_next()
	dir.list_dir_end()

func _has_pending_import_dependency(resource_path: String) -> bool:
	var source := FileAccess.get_file_as_string(resource_path)
	if source.is_empty(): return false
	var matcher := RegEx.new()
	if matcher.compile("path=\\\"(res://[^\\\"]+\\.(?:svg|png|jpg|jpeg|webp))\\\"") != OK: return false
	for match in matcher.search_all(source):
		var dependency_path := match.get_string(1)
		if FileAccess.file_exists(dependency_path) and not ResourceLoader.exists(dependency_path):
			return true
	return false

func _append_definition(definition: GMCharacterDefinition, path: String) -> void:
	var resolution := definition.resolve_visual_set()
	var visual_set: GMCharacterVisualSet2D = resolution.get("visual_set", null)
	var validation := definition.validate_definition()
	var complete := visual_set.completeness() if visual_set != null else {"complete": false, "ratio": 0.0, "missing": GMCharacterVisualSet2D.REQUIRED_SEMANTICS}
	var thumbnail: Texture2D = null
	var thumbnail_state := "missing"
	if visual_set != null:
		for candidate in [visual_set.avatar, visual_set.main_image, visual_set.portrait]:
			if candidate is Texture2D: thumbnail = candidate; thumbnail_state = "valid"; break
	entries.append({
		"display_name_zh": definition.display_name_zh, "content_id": definition.content_id,
		"art_style": str(visual_set.art_style) if visual_set != null else "", "category": str(visual_set.category) if visual_set != null else "",
		"tags": Array(definition.tags) + (Array(visual_set.tags) if visual_set != null else []),
		"complete": bool(complete.complete), "completeness_ratio": float(complete.ratio),
		"usage_locations": Array(definition.usage_locations), "identity_configuration_label": definition.identity_configuration_label,
		"thumbnail": thumbnail, "thumbnail_state": thumbnail_state, "path": path,
		"definition": definition, "visual_set": visual_set, "issues": validation.issues
	})

func _issue(code: String, message: String, path: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": message, "path": path, "component": "GMCharacterLibraryIndex"}
