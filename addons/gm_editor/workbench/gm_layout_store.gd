@tool
class_name GMWorkbenchLayoutStore
extends RefCounted

const DEFAULT_PATH := "user://gm_workbench_layout.json"
const SCHEMA_VERSION := 1
const RESULT_SCHEMA := "gm.layout-operation.v2"
const LAYOUT_FIELDS := ["schema", "active_entry", "mode", "compact", "panel_width", "panel_height", "split_offset", "help_entry"]
const ENTRY_IDS := ["home", "map", "character", "ability", "resource", "task", "equipment", "combat", "building", "production", "p19", "error"]
const MODE_IDS := ["planning", "advanced"]
const MIN_PANEL_WIDTH := 480
const MAX_PANEL_WIDTH := 8192
const MIN_PANEL_HEIGHT := 320
const MAX_PANEL_HEIGHT := 8192
const MIN_SPLIT_OFFSET := 96
const MAX_SPLIT_OFFSET := 640
const MIN_CONTENT_WIDTH := 240
static var _override_path := ""

static func set_storage_path(path: Variant) -> void:
	_override_path = str(path) if path is String else ""

static func storage_path() -> String:
	if not _override_path.is_empty(): return _override_path
	var override_path := OS.get_environment("GM_TASK02_LAYOUT_PATH")
	return override_path if not override_path.is_empty() else DEFAULT_PATH

static func defaults() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"active_entry": "home",
		"mode": "planning",
		"compact": false,
		"panel_width": 980,
		"panel_height": 520,
		"split_offset": 150,
		"help_entry": "home",
	}

static func load_state() -> Dictionary:
	var result := load_state_result()
	return result.get("state", defaults()).duplicate(true)

static func load_state_result() -> Dictionary:
	var fallback := defaults()
	var path := storage_path()
	var path_result := _path_details(path, false)
	if not bool(path_result.get("ok", false)):
		var path_errors: Array[String] = [str(path_result.get("error_zh", "工作台布局路径无效"))]
		return _load_result(false, str(path_result.get("error_code", "layout.path_invalid")), path, fallback, path_errors, true)
	var absolute := str(path_result.get("absolute", ""))
	if not FileAccess.file_exists(absolute):
		return _load_result(true, "", path, fallback, [], false)
	var raw := FileAccess.get_file_as_string(absolute)
	var parser := JSON.new()
	var parse_error := parser.parse(raw)
	var parsed = parser.data
	if parse_error != OK or not parsed is Dictionary:
		var parse_errors: Array[String] = ["工作台布局不是有效的 JSON 对象，已回退到 schema 1 默认值"]
		return _load_result(false, "layout.parse_failed", path, fallback, parse_errors, true)
	var validation := _validate_dictionary(parsed, true)
	if not bool(validation.get("ok", false)):
		return _load_result(false, "layout.validation_failed", path, fallback, _typed_errors(validation.get("errors_zh", [])), true)
	return _load_result(true, "", path, validation.get("state", fallback), [], false)

static func save_state(state: Variant) -> Dictionary:
	var path := storage_path()
	var path_result := _path_details(path, true)
	if not bool(path_result.get("ok", false)):
		var path_errors: Array[String] = [str(path_result.get("error_zh", "无法写入工作台布局"))]
		return _save_result(false, str(path_result.get("error_code", "layout.path_invalid")), path, defaults(), path_errors, FAILED, false, true)
	var validation := _validate_dictionary(state, false)
	if not bool(validation.get("ok", false)):
		return _save_result(false, "layout.validation_failed", path, defaults(), _typed_errors(validation.get("errors_zh", [])), FAILED, false, true)
	var canonical: Dictionary = validation.get("state", defaults())
	var write_result := _atomic_write(str(path_result.get("absolute", "")), JSON.stringify(canonical, "  ") + "\n")
	if not bool(write_result.get("ok", false)):
		var write_errors: Array[String] = [str(write_result.get("error_zh", "工作台布局保存未完成，原有布局已保留"))]
		return _save_result(false, str(write_result.get("error_code", "layout.save_failed")), path, canonical, write_errors, int(write_result.get("save_error", FAILED)), false, true)
	return _save_result(true, "", path, canonical, [], OK, true, false)

static func validate_state(state: Variant) -> Dictionary:
	return _validate_dictionary(state, false)

static func _validate_dictionary(value: Variant, require_schema: bool) -> Dictionary:
	var errors: Array[String] = []
	var candidate := defaults()
	if not value is Dictionary:
		errors.append("工作台布局必须是 JSON 对象")
		return {"ok":false,"errors_zh":errors,"state":candidate}
	var data: Dictionary = value
	for raw_key in data.keys():
		var key := str(raw_key)
		if not LAYOUT_FIELDS.has(key):
			errors.append("工作台布局包含未知字段：%s" % key)
	if require_schema and not data.has("schema"):
		errors.append("工作台布局缺少 schema 字段")
	if data.has("schema"):
		var schema_value := _integer_value(data.get("schema"))
		if schema_value == null or int(schema_value) != SCHEMA_VERSION:
			errors.append("工作台布局 schema 不是受支持的版本：%s" % str(data.get("schema")))
		else: candidate["schema"] = SCHEMA_VERSION
	if data.has("active_entry"):
		var entry = data.get("active_entry")
		if not entry is String or not ENTRY_IDS.has(str(entry)):
			errors.append("工作台布局 active_entry 不是受支持的入口")
		else: candidate["active_entry"] = str(entry)
	if data.has("mode"):
		var mode = data.get("mode")
		if not mode is String or not MODE_IDS.has(str(mode)):
			errors.append("工作台布局 mode 不是受支持的模式")
		else: candidate["mode"] = str(mode)
	if data.has("compact"):
		if not data.get("compact") is bool:
			errors.append("工作台布局 compact 必须是布尔值")
		else: candidate["compact"] = data.get("compact")
	if data.has("panel_width"):
		var width := _bounded_integer(data.get("panel_width"), "panel_width", MIN_PANEL_WIDTH, MAX_PANEL_WIDTH, errors)
		if width != null: candidate["panel_width"] = width
	if data.has("panel_height"):
		var height := _bounded_integer(data.get("panel_height"), "panel_height", MIN_PANEL_HEIGHT, MAX_PANEL_HEIGHT, errors)
		if height != null: candidate["panel_height"] = height
	if data.has("split_offset"):
		var split := _bounded_integer(data.get("split_offset"), "split_offset", MIN_SPLIT_OFFSET, MAX_SPLIT_OFFSET, errors)
		if split != null: candidate["split_offset"] = split
	if data.has("help_entry"):
		var help_entry = data.get("help_entry")
		if not help_entry is String or not ENTRY_IDS.has(str(help_entry)):
			errors.append("工作台布局 help_entry 不是受支持的入口")
		else: candidate["help_entry"] = str(help_entry)
	if int(candidate.get("split_offset", 0)) + MIN_CONTENT_WIDTH > int(candidate.get("panel_width", 0)):
		errors.append("工作台布局分栏超出面板宽度，右侧内容区不足")
	if not errors.is_empty():
		return {"ok":false,"errors_zh":errors,"state":defaults()}
	candidate["schema"] = SCHEMA_VERSION
	return {"ok":true,"errors_zh":[],"state":candidate}

static func _bounded_integer(value: Variant, field: String, minimum: int, maximum: int, errors: Array[String]) -> Variant:
	var integer_value := _integer_value(value)
	if integer_value == null:
		errors.append("工作台布局 %s 必须是有限整数" % field)
		return null
	var number := int(integer_value)
	if number < minimum or number > maximum:
		errors.append("工作台布局 %s 超出范围 [%d, %d]" % [field, minimum, maximum])
		return null
	return number

static func _integer_value(value: Variant) -> Variant:
	if value is bool or (not value is int and not value is float): return null
	var number := float(value)
	if not is_finite(number) or floor(number) != number: return null
	return int(number)

static func _path_details(path: String, require_parent: bool) -> Dictionary:
	var raw := path
	if raw.is_empty(): return {"ok":false,"error_code":"layout.path_missing","error_zh":"工作台布局保存路径为空"}
	if raw != raw.strip_edges(): return {"ok":false,"error_code":"layout.path_invalid","error_zh":"工作台布局路径包含首尾空白"}
	var normalized := raw.replace("\\", "/")
	if normalized.ends_with("/"):
		return {"ok":false,"error_code":"layout.path_invalid","error_zh":"工作台布局路径必须指向文件"}
	var root := ""
	if normalized.begins_with("res://"): root = "res://"
	elif normalized.begins_with("user://"): root = "user://"
	elif not normalized.is_absolute_path():
		return {"ok":false,"error_code":"layout.path_invalid","error_zh":"工作台布局仅支持 res://、user:// 或绝对本地路径"}
	if not root.is_empty():
		var stack: Array[String] = []
		for part in normalized.trim_prefix(root).split("/", false):
			if part.is_empty() or part == ".": continue
			if part == "..":
				if stack.is_empty(): return {"ok":false,"error_code":"layout.path_invalid","error_zh":"工作台布局路径越出受支持目录"}
				stack.pop_back()
			else: stack.append(part)
		if stack.is_empty(): return {"ok":false,"error_code":"layout.path_invalid","error_zh":"工作台布局路径必须指向文件"}
		normalized = root + "/".join(stack)
	var absolute := ProjectSettings.globalize_path(normalized)
	if absolute.is_empty(): return {"ok":false,"error_code":"layout.path_invalid","error_zh":"工作台布局路径无法解析"}
	if DirAccess.dir_exists_absolute(absolute): return {"ok":false,"error_code":"layout.path_invalid","error_zh":"工作台布局路径指向目录"}
	var parent := absolute.get_base_dir()
	if require_parent and not DirAccess.dir_exists_absolute(parent):
		return {"ok":false,"error_code":"layout.path_parent_missing","error_zh":"工作台布局目标父目录不存在"}
	return {"ok":true,"path":normalized,"absolute":absolute}

static func _atomic_write(absolute: String, content: String) -> Dictionary:
	var temporary := absolute + ".gm-layout-tmp"
	var backup := absolute + ".gm-layout-backup"
	_remove_file(temporary)
	_remove_file(backup)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok":false,"error_code":"layout.temp_open_failed","error_zh":"无法建立布局临时文件，原有布局已保留","save_error":FAILED}
	file.store_string(content)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_remove_file(temporary)
		return {"ok":false,"error_code":"layout.temp_write_failed","error_zh":"布局临时文件写入失败，原有布局已保留","save_error":write_error}
	var had_previous := FileAccess.file_exists(absolute)
	if had_previous:
		var old_file := FileAccess.open(absolute, FileAccess.READ)
		var backup_file := FileAccess.open(backup, FileAccess.WRITE)
		if old_file == null or backup_file == null:
			if old_file != null: old_file.close()
			if backup_file != null: backup_file.close()
			_remove_file(temporary)
			_remove_file(backup)
			return {"ok":false,"error_code":"layout.backup_failed","error_zh":"无法保护上次有效布局，未替换原文件","save_error":FAILED}
		backup_file.store_buffer(old_file.get_buffer(old_file.get_length()))
		backup_file.flush()
		var backup_error := backup_file.get_error()
		old_file.close()
		backup_file.close()
		if backup_error != OK:
			_remove_file(temporary)
			_remove_file(backup)
			return {"ok":false,"error_code":"layout.backup_failed","error_zh":"无法保护上次有效布局，未替换原文件","save_error":backup_error}
	var rename_error := DirAccess.rename_absolute(temporary, absolute)
	if rename_error != OK and had_previous:
		var remove_error := DirAccess.remove_absolute(absolute)
		if remove_error == OK: rename_error = DirAccess.rename_absolute(temporary, absolute)
	if rename_error != OK:
		if had_previous and not FileAccess.file_exists(absolute) and FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, absolute)
		_remove_file(temporary)
		_remove_file(backup)
		return {"ok":false,"error_code":"layout.replace_failed","error_zh":"布局替换失败，原有布局已保留","save_error":rename_error}
	_remove_file(backup)
	return {"ok":true,"save_error":OK}

static func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

static func _typed_errors(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value: result.append(str(item))
	return result

static func _load_result(ok: bool, error_code: String, path: String, state: Dictionary, errors: Array[String], fallback: bool) -> Dictionary:
	return {
		"schema_version": RESULT_SCHEMA,
		"ok": ok,
		"error_code": "" if ok else error_code,
		"error_zh": "" if errors.is_empty() else errors[0],
		"errors_zh": errors,
		"path": path,
		"state": state.duplicate(true),
		"fallback": fallback,
	}

static func _save_result(ok: bool, error_code: String, path: String, state: Dictionary, errors: Array[String], save_error: int, committed: bool, preserved_previous: bool) -> Dictionary:
	return {
		"schema_version": RESULT_SCHEMA,
		"ok": ok,
		"error_code": "" if ok else error_code,
		"error_zh": "" if errors.is_empty() else errors[0],
		"errors_zh": errors,
		"path": path,
		"state": state.duplicate(true),
		"save_error": save_error,
		"committed": committed,
		"preserved_previous": preserved_previous,
	}
