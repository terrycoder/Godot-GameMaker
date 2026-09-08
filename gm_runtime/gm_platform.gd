class_name GMPlatform
extends RefCounted

const PLATFORM_VERSION := "1.0.0"
const GODOT_BASELINE := "4.6.2-stable (official)"
const GODOT_BUILD := "4.6.2.stable.official.71f334935"
const COMPATIBILITY_BUILD := "4.7.2.stable.official.ed1daf0bf"
const VERSION_RESOURCE := preload("res://gm_runtime/gm_platform_version.tres")
const LOCK_RESOURCE := preload("res://gm_runtime/gm_plugin_lock.tres")
const ENVIRONMENT_RESOURCE := preload("res://gm_runtime/gm_environment_report.tres")


static func _as_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _normalise_path(value: Variant) -> String:
	var path := str(value).strip_edges().replace("\\", "/")
	if path.is_empty():
		return ""
	if path.begins_with("res://"):
		var remainder := path.trim_prefix("res://")
		while remainder.begins_with("/"):
			remainder = remainder.trim_prefix("/")
		return "res://" + remainder
	while path.begins_with("/"):
		path = path.trim_prefix("/")
	return "res://" + path


static func _path_key(value: Variant) -> String:
	return _normalise_path(value).to_lower()


static func _normalise_id(value: Variant) -> String:
	var id := str(value).strip_edges().to_lower()
	for separator in [" ", "_", "-", ".", "/"]:
		id = id.replace(separator, "")
	if id.begins_with("godot"):
		id = id.trim_prefix("godot")
	return id


static func _is_exact_version(value: Variant) -> bool:
	var version := str(value)
	if version.is_empty() or version != version.strip_edges():
		return false
	for forbidden in [" ", "\t", "\r", "\n", ";", "(", ")", "[", "]", "{", "}"]:
		if version.contains(forbidden):
			return false
	var lower := version.to_lower()
	for metadata_marker in ["commit", "asset library", "godot"]:
		if lower.contains(metadata_marker):
			return false
	var version_pattern := RegEx.new()
	if version_pattern.compile("^[vV]?[0-9]+(\\.[0-9]+)+(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$") != OK:
		return false
	return version_pattern.search(version) != null


static func _read_plugin_cfg(path: Variant) -> Dictionary:
	var normalized_path := _normalise_path(path)
	if normalized_path.is_empty():
		return {"load_error": ERR_FILE_NOT_FOUND, "path": normalized_path}
	var cfg := ConfigFile.new()
	var load_error := cfg.load(ProjectSettings.globalize_path(normalized_path))
	if load_error != OK:
		return {"load_error": load_error, "path": normalized_path}
	return {
		"load_error": OK,
		"path": normalized_path,
		"name": str(cfg.get_value("plugin", "name", "")),
		"version": str(cfg.get_value("plugin", "version", "")),
		"script": str(cfg.get_value("plugin", "script", "")),
	}


static func _append_discovered_plugin(found: Array, path: String) -> void:
	var read := _read_plugin_cfg(path)
	if int(read.get("load_error", FAILED)) != OK:
		return
	found.append({
		"path": read.get("path", ""),
		"name": read.get("name", ""),
		"version": read.get("version", ""),
		"id_key": _normalise_id(read.get("name", "")),
	})


static func _discover_plugin_cfgs(root: String = "res://addons") -> Array:
	var found: Array = []
	_discover_plugin_cfgs_recursive(_normalise_path(root), found)
	return found


static func _discover_plugin_cfgs_recursive(path: String, found: Array) -> void:
	if path.is_empty():
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name in [".", "..", ".godot", ".git", "third_party_optional"]:
			continue
		var child := path.path_join(name)
		if dir.current_is_dir():
			# A plugin package is represented by its direct plugin.cfg. Do not
			# descend into its implementation files, examples, or nested test data.
			var direct_cfg := child.path_join("plugin.cfg")
			if FileAccess.file_exists(ProjectSettings.globalize_path(direct_cfg)):
				_append_discovered_plugin(found, direct_cfg)
			else:
				_discover_plugin_cfgs_recursive(child, found)
		elif name.to_lower() == "plugin.cfg":
			_append_discovered_plugin(found, child)
	dir.list_dir_end()


static func _find_discovered_candidates(entry: Dictionary, discovered: Array) -> Array:
	var expected_id := _normalise_id(entry.get("id", ""))
	var candidates: Array = []
	if expected_id.is_empty():
		return candidates
	for item in discovered:
		if not item is Dictionary:
			continue
		if str(item.get("id_key", "")) == expected_id:
			candidates.append(item)
	return candidates


static func _is_plugin_enabled(path: String) -> bool:
	var enabled_setting: Variant = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	if enabled_setting is PackedStringArray:
		for item in enabled_setting:
			if _path_key(item) == _path_key(path):
				return true
	elif enabled_setting is Array:
		for item in enabled_setting:
			if _path_key(item) == _path_key(path):
				return true
	return false


static func _validation_state(entry: Dictionary) -> String:
	var validation := _as_dictionary(entry.get("validation", {}))
	var state := str(validation.get("status", ""))
	if not state.is_empty():
		return state
	return "verified" if str(entry.get("decision", "")) == "正式接入" else "not_declared"


static func _integration_level(entry: Dictionary) -> String:
	var validation := _as_dictionary(entry.get("validation", {}))
	var level := str(validation.get("integration_level", ""))
	if not level.is_empty():
		return level
	match str(entry.get("decision", "")):
		"正式接入": return "formal"
		"可选接入": return "candidate"
		_: return "reference_only"


static func _adapter_id(entry: Dictionary) -> String:
	var validation := _as_dictionary(entry.get("validation", {}))
	return str(validation.get("adapter_id", entry.get("adapter_id", "")))


static func _default_enabled(entry: Dictionary) -> bool:
	var installation := _as_dictionary(entry.get("installation", {}))
	return bool(installation.get("default_enabled", entry.get("enabled_by_default", false)))


static func _is_pending_validation(state: String) -> bool:
	return state in ["pending_validation", "candidate", "not_started", "not_declared", "unverified"]


static func _plugin_observation(entry: Dictionary, discovered: Array = []) -> Dictionary:
	var configured_path := _normalise_path(entry.get("path", ""))
	var expected_id := _normalise_id(entry.get("id", ""))
	var locked_version := str(entry.get("version", ""))
	var lock_version_valid := _is_exact_version(locked_version)
	var configured := _read_plugin_cfg(configured_path)
	var configured_present := int(configured.get("load_error", FAILED)) == OK
	var candidates: Array = discovered
	if candidates.is_empty() and (not configured_present or _normalise_id(configured.get("name", "")) != expected_id):
		candidates = _discover_plugin_cfgs()
	var matching_candidates := _find_discovered_candidates(entry, candidates)

	var selected := configured
	var observed_path := configured_path
	var path_state := "configured_path" if configured_present else "missing_configured_path"
	var path_matches := configured_present
	var path_conflict := false
	var installed_present := configured_present
	if not configured_present and not matching_candidates.is_empty():
		var candidate: Dictionary = matching_candidates[0]
		var candidate_path := _normalise_path(candidate.get("path", ""))
		var candidate_read := _read_plugin_cfg(candidate_path)
		selected = candidate_read
		observed_path = candidate_path
		installed_present = int(candidate_read.get("load_error", FAILED)) == OK
		if not configured_path.is_empty() and _path_key(candidate_path) == _path_key(configured_path):
			path_state = "case_insensitive_match"
			path_matches = installed_present
		else:
			path_state = "lock_path_mismatch"
			path_matches = false
			path_conflict = installed_present
	elif configured_present and _normalise_id(configured.get("name", "")) != expected_id and not matching_candidates.is_empty():
		var candidate: Dictionary = matching_candidates[0]
		var candidate_path := _normalise_path(candidate.get("path", ""))
		if _path_key(candidate_path) != _path_key(configured_path):
			var candidate_read := _read_plugin_cfg(candidate_path)
			selected = candidate_read
			observed_path = candidate_path
			installed_present = int(candidate_read.get("load_error", FAILED)) == OK
			path_state = "lock_path_mismatch"
			path_matches = false
			path_conflict = installed_present

	var actual_name := str(selected.get("name", entry.get("display_name", ""))) if installed_present else str(entry.get("display_name", ""))
	var actual_version := str(selected.get("version", "")) if installed_present else ""
	var id_ok := installed_present and not expected_id.is_empty() and _normalise_id(actual_name) == expected_id
	var actual_version_valid := installed_present and _is_exact_version(actual_version)
	var version_ok := installed_present and lock_version_valid and actual_version_valid and actual_version == locked_version
	var fact_ok := installed_present and path_matches and id_ok and version_ok
	var decision := str(entry.get("decision", ""))
	var validation_state := _validation_state(entry)
	var pending_validation := _is_pending_validation(validation_state)
	var integration_level := _integration_level(entry)
	var adapter_id := _adapter_id(entry)
	var enabled := installed_present and _is_plugin_enabled(observed_path)
	var default_enabled := _default_enabled(entry)
	var blocking := false
	if not lock_version_valid:
		blocking = true
	elif installed_present:
		blocking = not path_matches or not id_ok or not version_ok
	else:
		blocking = bool(entry.get("required", false))

	var status := ""
	if not lock_version_valid:
		status = "invalid_lock_version"
	elif path_conflict:
		status = "lock_path_mismatch"
	elif not installed_present:
		status = "missing_required" if bool(entry.get("required", false)) else "missing_optional"
	elif not id_ok:
		status = "installed_wrong_id"
	elif not version_ok:
		status = "installed_unapproved_version"
	elif pending_validation:
		status = "installed_enabled_pending_validation" if enabled else "installed_disabled_pending_validation"
	elif enabled:
		status = "enabled_verified"
	else:
		status = "installed_disabled"

	var error_zh := ""
	if blocking:
		if not lock_version_valid:
			error_zh = "插件锁的精确版本字段无效：%s；来源、commit、兼容性和安装方式必须放在独立元数据字段" % locked_version
		elif path_conflict:
			error_zh = "插件锁路径与实际安装事实矛盾：锁定路径%s；发现同ID安装%s；请更新锁路径" % [configured_path, observed_path]
		elif not installed_present:
			error_zh = "必需插件缺失或plugin.cfg无法读取：%s；请恢复插件并重新验证" % configured_path
		elif not id_ok:
			error_zh = "插件%s的逻辑ID不符合锁定值：实际%s，锁定%s；请修复plugin.cfg后重试" % [entry.get("display_name", entry.get("id", "")), actual_name, entry.get("id", "")]
		elif not version_ok:
			error_zh = "插件%s的精确版本不符合锁定值：实际%s，锁定%s；请修复plugin.cfg或锁定后重试" % [entry.get("display_name", entry.get("id", "")), actual_version, locked_version]

	var warning_zh := ""
	if not blocking and not installed_present and not bool(entry.get("required", false)):
		warning_zh = "可选插件未安装；平台仍可用，但不能视为已验证接入：%s" % configured_path
	elif not blocking and installed_present and pending_validation:
		warning_zh = "插件已安装但%s；当前默认%s，尚待完整接入验证，不能视为B级正式可选接入" % ["尚待完整接入验证" if validation_state == "pending_validation" else "处于候选验证状态", "启用" if enabled else "禁用"]

	var fact_conflict := not lock_version_valid or path_conflict or (installed_present and (not path_matches or not id_ok or not version_ok))
	var verified := fact_ok and not pending_validation and validation_state == "verified"
	return {
		"id": entry.get("id", ""),
		"display_name": entry.get("display_name", ""),
		"name": actual_name,
		"path": configured_path,
		"configured_path": configured_path,
		"observed_path": observed_path if installed_present else "",
		"path_state": path_state,
		"path_matches": path_matches,
		"configured_path_present": configured_present,
		"present": installed_present,
		"installed_present": installed_present,
		"decision": decision,
		"required": bool(entry.get("required", false)),
		"default_enabled": default_enabled,
		"enabled": enabled,
		"activation_state": "enabled" if enabled else ("disabled" if installed_present else "not_observed"),
		"version_locked": locked_version,
		"version_actual": actual_version,
		"version_lock_valid": lock_version_valid,
		"version_actual_valid": actual_version_valid,
		"id_ok": id_ok,
		"version_ok": version_ok,
		"fact_ok": fact_ok,
		"fact_conflict": fact_conflict,
		"validation_state": validation_state,
		"pending_validation": pending_validation,
		"validation_complete": verified,
		"verified": verified,
		"adapter_id": adapter_id,
		"integration_level": integration_level,
		"integration_ok": verified and not adapter_id.is_empty(),
		"status": status,
		"ok": not blocking,
		"blocking": blocking,
		"error_zh": error_zh,
		"warning_zh": warning_zh,
	}


static func _duplicate_keys(values: Array) -> Array:
	var seen: Dictionary = {}
	var duplicates: Array = []
	for value in values:
		var key := _normalise_id(value)
		if key.is_empty():
			continue
		if seen.has(key) and not duplicates.has(key):
			duplicates.append(key)
		seen[key] = true
	return duplicates


static func plugin_report_for_entries(entries: Array) -> Dictionary:
	var discovered := _discover_plugin_cfgs()
	var observations: Array = []
	var entry_ids: Array = []
	for item in entries:
		if not item is Dictionary:
			continue
		var entry: Dictionary = item
		entry_ids.append(entry.get("id", ""))
		observations.append(_plugin_observation(entry, discovered))

	var duplicate_ids := _duplicate_keys(entry_ids)
	var duplicate_installed_ids: Array = []
	var installed_paths_by_id: Dictionary = {}
	var expected_ids: Dictionary = {}
	for value in entry_ids:
		expected_ids[_normalise_id(value)] = true
	for candidate in discovered:
		var candidate_id := str(candidate.get("id_key", ""))
		if candidate_id.is_empty() or not expected_ids.has(candidate_id):
			continue
		if not installed_paths_by_id.has(candidate_id):
			installed_paths_by_id[candidate_id] = []
		installed_paths_by_id[candidate_id].append(candidate.get("path", ""))
	for candidate_id in installed_paths_by_id:
		if installed_paths_by_id[candidate_id].size() > 1:
			duplicate_installed_ids.append(candidate_id)

	var required_failures: Array = []
	var blocking_failures: Array = []
	var optional_failures: Array = []
	var fact_conflicts: Array = []
	var invalid_lock_entries: Array = []
	var optional_missing: Array = []
	var pending_validation: Array = []
	var warnings: Array = []
	for observation in observations:
		var id := str(observation.get("id", ""))
		if bool(observation.get("blocking", false)):
			blocking_failures.append(id)
			if bool(observation.get("required", false)):
				required_failures.append(id)
			else:
				optional_failures.append(id)
		if bool(observation.get("fact_conflict", false)):
			fact_conflicts.append(id)
		if not bool(observation.get("version_lock_valid", true)):
			invalid_lock_entries.append(id)
		if not bool(observation.get("present", false)) and not bool(observation.get("required", false)):
			optional_missing.append(id)
		if bool(observation.get("pending_validation", false)) and bool(observation.get("present", false)):
			pending_validation.append(id)
		var warning := str(observation.get("warning_zh", ""))
		if not warning.is_empty():
			warnings.append(warning)

	var ok := blocking_failures.is_empty() and duplicate_ids.is_empty() and duplicate_installed_ids.is_empty()
	var validation_complete := ok and optional_missing.is_empty() and pending_validation.is_empty()
	var status := "verified"
	if not ok:
		status = "plugin_fact_conflict"
	elif not pending_validation.is_empty():
		status = "candidate_validation_pending"
	elif not optional_missing.is_empty():
		status = "optional_dependency_missing"
	return {
		"plugins": observations,
		"duplicate_ids": duplicate_ids,
		"duplicate_installed_ids": duplicate_installed_ids,
		"required_failures": required_failures,
		"blocking_failures": blocking_failures,
		"optional_failures": optional_failures,
		"fact_conflicts": fact_conflicts,
		"invalid_lock_entries": invalid_lock_entries,
		"optional_missing": optional_missing,
		"pending_validation": pending_validation,
		"validation_complete": validation_complete,
		"status": status,
		"warning_zh": "；".join(warnings),
		"error_zh": "插件锁或实际安装事实存在矛盾：%s" % "、".join(blocking_failures + duplicate_ids + duplicate_installed_ids) if not ok else "",
		"ok": ok,
	}


static func plugin_report() -> Dictionary:
	var entries: Array = []
	for item in LOCK_RESOURCE.plugins:
		if item is Dictionary:
			entries.append(item)
	return plugin_report_for_entries(entries)


static func environment() -> Dictionary:
	var actual: String = str(Engine.get_version_info().string)
	var main_ok: bool = actual == str(VERSION_RESOURCE.godot_baseline)
	var trial: bool = actual.begins_with("4.7.2-stable")
	var report: Dictionary = plugin_report()
	var ok: bool = main_ok and bool(report.get("ok", false))
	var validation_complete: bool = ok and bool(report.get("validation_complete", false))
	var status := "main_baseline_verified"
	if not main_ok:
		status = "compatibility_trial" if trial else "unsupported_version"
	elif not bool(report.get("ok", false)):
		status = "plugin_fact_conflict"
	elif not validation_complete:
		status = str(report.get("status", "candidate_validation_pending"))
	return {
		"platform_version": VERSION_RESOURCE.platform_version,
		"godot_actual": actual,
		"godot_baseline": VERSION_RESOURCE.godot_baseline,
		"status": status,
		"environment_schema": ENVIRONMENT_RESOURCE.get_script().get_global_name(),
		"plugin_observation_schema": "gm.plugin-observation.v2",
		"plugins": report,
		"ok": ok,
		"platform_ok": ok,
		"validation_complete": validation_complete,
		"warning_zh": report.get("warning_zh", "") if ok else "",
		"error_zh": "主基线或插件事实验证失败；请查看plugins字段" if not ok else "",
	}


static func validate() -> Dictionary:
	var required := ["addons/gm_editor", "addons/gm_agent_planner", "addons/gm_feedback", "addons/gm_p26_vertical_sample", "gm_runtime", "gm_adapters", "interaction_recipes", "samples", "DOCS/gm/platform_manual"]
	var missing: Array = []
	for path in required:
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://" + path)):
			missing.append(path)
	var required_files := [
		"project.godot",
		"gm_runtime/gm_minimal_entry.tscn",
		"gm_runtime/vertical_sample/gm_ext_3d_11_entry.tscn",
		"gm_runtime/vertical_sample/gm_ext_3d_11_2d_entry.tscn",
		"gm_runtime/manifests/manifest_index.tres",
		"gm_runtime/gm_module_profile.tres",
		"addons/gm_editor/plugin.cfg",
		"addons/gm_agent_planner/plugin.cfg",
		"addons/gm_feedback/plugin.cfg",
		"addons/gm_p26_vertical_sample/plugin.cfg",
	]
	var missing_files: Array = []
	for path in required_files:
		if not FileAccess.file_exists(ProjectSettings.globalize_path("res://" + path)):
			missing_files.append(path)
	var ok: bool = missing.is_empty() and missing_files.is_empty()
	var validation_complete := ok
	var status := "release_tree_verified" if ok else "missing_release_resources"
	if not missing.is_empty():
		status = "missing_required_directories"
	return {
		"ok": ok,
		"platform_ok": ok,
		"validation_complete": validation_complete,
		"status": status,
		"missing": missing,
		"missing_files": missing_files,
		"enabled_production_plugins": required_files.slice(6),
		"warning_zh": "",
		"error_zh": "发布树缺少生产目录或资源；请查看 missing 与 missing_files" if not ok else "",
	}


static func compatibility() -> Dictionary:
	var actual: String = str(Engine.get_version_info().string)
	var ok: bool = actual.begins_with("4.6.2-stable")
	return {
		"ok": ok,
		"command": "compatibility",
		"status": "baseline_verified" if ok else "unsupported_version",
		"godot_actual": actual,
		"target": GODOT_BUILD,
		"validation_complete": ok,
		"future_unverified_target": COMPATIBILITY_BUILD,
		"error_zh": "当前版本不是已验证的 Godot 4.6.2 基线：%s" % actual if not ok else "",
	}


static func fixture_validation(kind: String) -> Dictionary:
	return {
		"ok": false,
		"fixture": kind,
		"code": "diagnostic.not_available_in_release",
		"observations": [],
		"duplicate_plugin_ids": [],
		"required_failures": [],
		"fact_conflicts": [],
		"error_zh": "此隔离错误配置诊断仅属于内部测试包，发布包不含：%s" % kind,
	}
