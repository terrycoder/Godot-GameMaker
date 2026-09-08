@tool
class_name GMContentLibrary
extends RefCounted

const VALID_RESOURCE_EXTENSIONS := [".tres", ".res"]

var entries: Array[Dictionary] = []
var by_id: Dictionary = {}
var by_alias: Dictionary = {}
var by_path: Dictionary = {}
var issues: Array[Dictionary] = []
var roots: Array[String] = []
var scan_stats: Dictionary = {}
var last_scan_committed := false

func scan(scan_roots: Array[String] = ["res://gm_runtime/content"]) -> Dictionary:
	var staged_entries: Array[Dictionary] = []
	var staged_by_id := {}
	var staged_by_alias := {}
	var staged_by_path := {}
	var staged_issues: Array[Dictionary] = []
	var start_usec := Time.get_ticks_usec()
	var collected_files: Array[String] = []
	for root in scan_roots: _collect_files(root, collected_files)
	collected_files.sort()
	var files: Array[String] = []
	var seen_paths := {}
	for raw_path in collected_files:
		var path := str(raw_path).replace("\\", "/")
		# Godot's resource export stores a source path beside a compiled
		# resource as `<path>.remap`.  Keep the durable source identity and let
		# ResourceLoader resolve the remap, so runtime content scans work in both
		# the editor tree and a PCK without a second index.
		if path.ends_with(".remap"): path = path.trim_suffix(".remap")
		if seen_paths.has(path): continue
		seen_paths[path] = true
		files.append(path)
	var seen_ids := {}
	var seen_uids := {}
	var loaded_count := 0
	var invalid_count := 0
	for path in files:
		if not _is_content_file(path): continue
		var resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
		if resource == null:
			invalid_count += 1
			staged_issues.append({"code":"content.load_failed","path":path,"reason_zh":"Resource 无法加载，已隔离该项，内容浏览器继续工作。","suggestion_zh":"检查损坏的 .tres/.res 或未知脚本。"})
			continue
		loaded_count += 1
		if not resource is GMContent:
			# 类型注册 Resource、普通预览 Resource 等不属于内容条目，正常跳过。
			continue
		var content: GMContent = resource
		var validation := GMContentValidator.validate_content(content, path, seen_ids, _is_platform_path(path))
		staged_issues.append_array(validation.errors)
		if not content.content_id.is_empty() and not seen_ids.has(content.content_id): seen_ids[content.content_id] = path
		# The serialized .tres header is the durable source for a checked-in
		# ResourceUID.  Headless/editor caches can expose a transient UID after a
		# move, so never replace the stored identity with that cache value.
		var stored_uid_text := _stored_uid_text(path)
		var uid := ResourceUID.text_to_id(stored_uid_text) if not stored_uid_text.is_empty() else ResourceLoader.get_resource_uid(path)
		if stored_uid_text.is_empty() and uid > 0: stored_uid_text = ResourceUID.id_to_text(uid)
		var thumbnail_info := inspect_thumbnail(content)
		if not stored_uid_text.is_empty():
			if seen_uids.has(stored_uid_text) and str(seen_uids[stored_uid_text]) != path:
				staged_issues.append({"code":"content.duplicate_uid","path":path,"reason_zh":"ResourceUID 重复：%s；已有位置：%s" % [stored_uid_text, seen_uids[stored_uid_text]],"suggestion_zh":"为资源生成唯一 ResourceUID。"})
			else: seen_uids[stored_uid_text] = path
		var entry := {
			"path": path,
			"resource": content,
			"resource_uid": uid,
			"resource_uid_text": stored_uid_text,
			"display_name_zh": content.display_name_zh,
			"content_id": content.content_id,
			"content_type_id": content.content_type_id,
			"tags": Array(content.tags),
			"content_version": content.content_version,
			"source": content.source,
			"deprecated": content.deprecated,
			"aliases": Array(content.aliases),
			"validation": validation,
			"thumbnail_texture": thumbnail_info.get("texture", null),
			"thumbnail_state": thumbnail_info.get("state", "missing"),
			"thumbnail_ok": bool(thumbnail_info.get("ok", false)),
			"thumbnail_resource_path": str(thumbnail_info.get("path", "")),
			"thumbnail_reason_zh": str(thumbnail_info.get("reason_zh", "")),
			"usage_status": "未扫描引用",
			"usage_count": 0,
		}
		staged_entries.append(entry)
		staged_by_path[path] = entry
		if not content.content_id.is_empty() and not staged_by_id.has(content.content_id): staged_by_id[content.content_id] = entry
		for alias in content.aliases:
			if not staged_by_alias.has(str(alias)): staged_by_alias[str(alias)] = entry
	var duplicate_ids := {}
	for entry in staged_entries:
		var id := str(entry.content_id)
		if id.is_empty(): continue
		if duplicate_ids.has(id):
			staged_issues.append({"code":"content.duplicate_id","path":entry.path,"reason_zh":"业务 ID 重复：%s；已有位置：%s" % [id, duplicate_ids[id]],"suggestion_zh":"修改业务 ID，移动文件不会自动改变业务身份。"})
		else: duplicate_ids[id] = entry.path
	_append_identity_conflicts(staged_entries, staged_issues)
	var attempted_stats := {
		"roots": scan_roots.duplicate(),
		"files_scanned": files.size(),
		"resource_files_loaded": loaded_count,
		"content_count": staged_entries.size(),
		"invalid_count": invalid_count,
		"issue_count": staged_issues.size(),
		"elapsed_ms": float(Time.get_ticks_usec() - start_usec) / 1000.0,
	}
	if staged_issues.is_empty():
		entries = staged_entries
		by_id = staged_by_id
		by_alias = staged_by_alias
		by_path = staged_by_path
		issues = staged_issues
		roots = scan_roots.duplicate()
		scan_stats = attempted_stats
		last_scan_committed = true
		return snapshot()
	# A failed scan is diagnostic-only.  Keep the previous indexed facts and expose
	# the candidate errors, so callers can repair and rescan without a partial index.
	issues = staged_issues.duplicate(true)
	roots = scan_roots.duplicate()
	scan_stats = attempted_stats
	last_scan_committed = false
	var failure := snapshot()
	failure["ok"] = false
	failure["committed"] = false
	failure["previous_snapshot_preserved"] = true
	failure["previous_entry_count"] = entries.size()
	failure["attempted_content_count"] = staged_entries.size()
	return failure

func reload(scan_roots: Array[String] = roots) -> Dictionary:
	return scan(scan_roots if not scan_roots.is_empty() else ["res://gm_runtime/content"])

func query(search_text: String = "", type_id: String = "", tag: String = "", usage: String = "", include_deprecated: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var needle := search_text.strip_edges().to_lower()
	for entry in entries:
		if not include_deprecated and bool(entry.deprecated): continue
		if not type_id.is_empty() and str(entry.content_type_id) != type_id: continue
		if not tag.is_empty() and not Array(entry.tags).has(tag): continue
		if not usage.is_empty() and str(entry.usage_status) != usage: continue
		var haystack := "%s|%s|%s|%s" % [entry.display_name_zh, entry.content_id, entry.content_type_id, ",".join(entry.tags)]
		if not needle.is_empty() and not haystack.to_lower().contains(needle): continue
		result.append(entry)
	return result

func entry_for_id(value: String) -> Dictionary:
	if by_id.has(value): return by_id[value]
	if by_alias.has(value): return by_alias[value]
	return {}

func entry_for_path(path: String) -> Dictionary:
	return by_path.get(path, {})

func inspect_thumbnail(content: GMContent) -> Dictionary:
	if content == null:
		return {"ok":false,"state":"missing","path":"","reason_zh":"内容对象为空，使用缩略图占位。","texture":null}
	if content.thumbnail != null and content.thumbnail is Texture2D:
		return {"ok":true,"state":"valid","path":content.thumbnail.resource_path,"reason_zh":"","texture":content.thumbnail}
	var requested := content.thumbnail_path.strip_edges()
	if requested.is_empty():
		return {"ok":false,"state":"missing","path":"","reason_zh":"未配置缩略图，使用占位图。","texture":null}
	if not FileAccess.file_exists(requested):
		return {"ok":false,"state":"missing","path":requested,"reason_zh":"缩略图文件不存在，使用占位图。","texture":null}
	var texture = ResourceLoader.load(requested, "", ResourceLoader.CACHE_MODE_IGNORE)
	if texture is Texture2D:
		return {"ok":true,"state":"valid","path":requested,"reason_zh":"","texture":texture}
	return {"ok":false,"state":"broken","path":requested,"reason_zh":"缩略图资源损坏或类型错误，使用占位图。","texture":null}

func set_usage_status(content_id: String, status: String, count: int) -> void:
	var entry := entry_for_id(content_id)
	if entry.is_empty(): return
	entry.usage_status = status
	entry.usage_count = count

func snapshot() -> Dictionary:
	return {
		"ok": issues.is_empty(),
		"entries": entries.duplicate(true),
		"issues": issues.duplicate(true),
		"stats": scan_stats.duplicate(true),
		"committed": last_scan_committed,
	}

func _append_identity_conflicts(candidate_entries: Array[Dictionary], target_issues: Array[Dictionary]) -> void:
	var canonical_by_value := {}
	var aliases_by_value := {}
	for entry in candidate_entries:
		var canonical_id := str(entry.get("content_id", ""))
		var source := str(entry.get("path", ""))
		if not canonical_id.is_empty():
			if not canonical_by_value.has(canonical_id): canonical_by_value[canonical_id] = []
			canonical_by_value[canonical_id].append({"canonical_id":canonical_id,"source":source,"kind":"canonical"})
		for alias_value in entry.get("aliases", []):
			var alias := str(alias_value).strip_edges()
			if alias.is_empty(): continue
			if not aliases_by_value.has(alias): aliases_by_value[alias] = []
			aliases_by_value[alias].append({"canonical_id":canonical_id,"source":source,"kind":"alias"})
	for alias in aliases_by_value:
		var alias_records: Array = aliases_by_value[alias]
		var canonical_records: Array = canonical_by_value.get(alias, [])
		var owner_ids: Array[String] = []
		var sources: Array[String] = []
		var participants: Array[Dictionary] = []
		for record in alias_records + canonical_records:
			var record_id := str(record.get("canonical_id", ""))
			var record_source := str(record.get("source", ""))
			if not record_id.is_empty() and not owner_ids.has(record_id): owner_ids.append(record_id)
			if not record_source.is_empty() and not sources.has(record_source): sources.append(record_source)
			participants.append(record.duplicate(true))
		if owner_ids.size() > 1 and alias_records.size() > 1:
			target_issues.append({
				"code":"content.alias_collision",
				"path":sources[0] if not sources.is_empty() else "",
				"alias":alias,
				"canonical_ids":owner_ids,
				"sources":sources,
				"conflicts":participants,
				"reason_zh":"别名冲突：%s 同时指向不同 canonical ID：%s；来源：%s" % [alias, ", ".join(owner_ids), "; ".join(sources)],
				"suggestion_zh":"每个别名只能归属于一个 canonical ID；修复后重新扫描。",
			})
		var cross_occupied := false
		for alias_record in alias_records:
			for canonical_record in canonical_records:
				if str(alias_record.get("canonical_id", "")) != str(canonical_record.get("canonical_id", "")) or str(alias_record.get("source", "")) != str(canonical_record.get("source", "")):
					cross_occupied = true
					break
			if cross_occupied: break
		if cross_occupied:
			target_issues.append({
				"code":"content.canonical_alias_collision",
				"path":sources[0] if not sources.is_empty() else "",
				"alias":alias,
				"canonical_ids":owner_ids,
				"sources":sources,
				"conflicts":participants,
				"reason_zh":"稳定身份冲突：canonical ID %s 同时被另一个内容作为 alias 占用；来源：%s" % [alias, "; ".join(sources)],
				"suggestion_zh":"canonical ID 与 alias 不能跨内容交叉占用；修复后重新扫描。",
			})

func _is_platform_path(path: String) -> bool:
	var normalized := path.replace("\\", "/")
	return normalized.begins_with("res://gm_runtime/content/")

func _is_content_file(path: String) -> bool:
	for extension in VALID_RESOURCE_EXTENSIONS:
		if path.ends_with(extension): return true
	return false

func _collect_files(path: String, result: Array[String]) -> void:
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

func _stored_uid_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	var first_line := file.get_line()
	file.close()
	var regex := RegEx.new()
	regex.compile("uid=\\\"(uid://[^\\\"]+)\\\"")
	var match := regex.search(first_line)
	return match.get_string(1) if match != null else ""
