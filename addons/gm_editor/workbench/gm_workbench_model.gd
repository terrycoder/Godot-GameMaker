@tool
class_name GMWorkbenchModel
extends RefCounted

const TEMPLATES := preload("res://addons/gm_editor/templates/gm_template_catalog.gd")
const RESULT_SCHEMA := "gm.profile-operation.v2"

static func guard_template_switch(profile: Variant, subject: Variant, target_template_id: Variant, next_modules: Variant = null, terminology_override: Variant = {}, content_would_be_deleted: Variant = false) -> Dictionary:
	var modules: Variant = next_modules
	if modules == null and profile is Resource:
		modules = profile.get("enabled_modules")
	var validation := TEMPLATES.validate_template(target_template_id, modules, terminology_override)
	var errors: Array[String] = _typed_errors(validation.get("errors_zh", []))
	var before := _snapshot(subject)
	var after := before.duplicate(true)
	if bool(content_would_be_deleted):
		errors.append("模板切换会删除已有内容，已中文阻断且不会写入 Profile")
	var error_code := "" if errors.is_empty() else "template.switch_blocked"
	return {
		"schema_version": RESULT_SCHEMA,
		"ok": errors.is_empty(),
		"error_code": error_code,
		"error_zh": "" if errors.is_empty() else errors[0],
		"errors_zh": errors,
		"validation": validation,
		"content_before": before,
		"content_after": after,
		"content_preserved": before == after,
		"profile_before": _profile_snapshot(profile),
		"profile_after": _profile_snapshot(profile),
		"committed": false,
		"rolled_back": true,
	}

static func apply_profile_state(profile: Variant, template_id: Variant, modules: Variant, save: bool = true) -> Dictionary:
	var target_id := str(template_id) if template_id is String else ""
	var before := _profile_snapshot(profile)
	if profile == null:
		return _profile_result(false, "profile.missing", target_id, [], ["项目配置资源不存在"], before, before, FAILED, {}, "", false, true)
	if not profile is Resource:
		return _profile_result(false, "profile.invalid_type", target_id, [], ["项目配置资源类型无效：仅支持 Resource"], before, before, FAILED, {}, "", false, true)
	var module_errors: Array[String] = []
	var candidate_modules := _coerce_modules(modules, module_errors)
	var validation := TEMPLATES.validate_template(template_id, candidate_modules)
	var validation_errors := _typed_errors(validation.get("errors_zh", []))
	for error in module_errors: validation_errors.append(error)
	if not validation_errors.is_empty():
		return _profile_result(false, "profile.validation_failed", target_id, candidate_modules, validation_errors, before, before, FAILED, validation, "", false, true)
	var save_path := ""
	if save:
		save_path = str(profile.resource_path)
		var path_result := _save_target_details(save_path)
		if not bool(path_result.get("ok", false)):
			var path_errors: Array[String] = [str(path_result.get("error_zh", "项目配置保存目标无效"))]
			return _profile_result(false, str(path_result.get("error_code", "profile.save_target_invalid")), target_id, candidate_modules, path_errors, before, before, FAILED, validation, save_path, false, true)
		var candidate = profile.duplicate(true)
		if not candidate is Resource:
			return _profile_result(false, "profile.candidate_invalid", target_id, candidate_modules, ["项目配置候选资源无效，未提交任何状态"], before, before, FAILED, validation, save_path, false, true)
		var candidate_resource: Resource = candidate
		candidate_resource.set("template_id", target_id)
		candidate_resource.set("enabled_modules", candidate_modules.duplicate())
		var save_error := ResourceSaver.save(candidate_resource, save_path)
		if save_error != OK:
			return _profile_result(false, "profile.save_failed", target_id, candidate_modules, ["项目配置保存未完成，原有 Profile 状态已保留"], before, before, save_error, validation, save_path, false, true)
	# Only the validated candidate is committed after persistence succeeds.
	profile.set("template_id", target_id)
	profile.set("enabled_modules", candidate_modules.duplicate())
	var after := _profile_snapshot(profile)
	if str(after.get("template_id", "")) != target_id or after.get("enabled_modules", PackedStringArray()) != candidate_modules:
		profile.set("template_id", before.get("template_id", ""))
		profile.set("enabled_modules", before.get("enabled_modules", PackedStringArray()).duplicate())
		return _profile_result(false, "profile.commit_failed", target_id, candidate_modules, ["项目配置提交未完成，原有 Profile 状态已恢复"], before, _profile_snapshot(profile), FAILED, validation, save_path, false, true)
	return _profile_result(true, "", target_id, candidate_modules, [], before, after, OK, validation, save_path, true, false)

static func subject_field(subject: Resource, field: String) -> Variant:
	return subject.get(field) if subject != null else null

static func snapshot_equal(before: Dictionary, after: Dictionary) -> bool:
	return before == after

static func _snapshot(subject: Variant) -> Dictionary:
	if not subject is Resource: return {}
	if subject.has_method("content_snapshot"): return subject.content_snapshot()
	return {"resource_path": subject.resource_path, "resource_name": subject.resource_name}

static func _profile_snapshot(profile: Variant) -> Dictionary:
	if not profile is Resource:
		return {"template_id": "", "enabled_modules": PackedStringArray()}
	var raw_modules = profile.get("enabled_modules")
	var modules: PackedStringArray = _coerce_modules(raw_modules, [])
	return {"template_id": str(profile.get("template_id")), "enabled_modules": modules}

static func _profile_result(ok: bool, error_code: String, template_id: String, modules: PackedStringArray, errors: Array[String], before: Dictionary, after: Dictionary, save_error: int, validation: Dictionary, save_path: String, committed: bool, rolled_back: bool) -> Dictionary:
	var typed_errors: Array[String] = []
	for error in errors: typed_errors.append(str(error))
	return {
		"schema_version": RESULT_SCHEMA,
		"ok": ok,
		"error_code": "" if ok else error_code,
		"error_zh": "" if typed_errors.is_empty() else typed_errors[0],
		"errors_zh": typed_errors,
		"save_error": save_error,
		"save_path": save_path,
		"template_id": template_id,
		"enabled_modules": modules.duplicate(),
		"validation": validation.duplicate(true),
		"profile_before": before.duplicate(true),
		"profile_after": after.duplicate(true),
		"committed": committed,
		"rolled_back": rolled_back,
	}

static func _typed_errors(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value: result.append(str(item))
	return result

static func _coerce_modules(value: Variant, errors: Array[String]) -> PackedStringArray:
	var result: PackedStringArray = []
	if value is PackedStringArray:
		return value.duplicate()
	if value is Array:
		for item in value:
			if not item is String:
				errors.append("启用模块类型无效：模块ID必须是字符串")
				return []
			result.append(str(item))
		return result
	if value != null: errors.append("启用模块类型无效：仅支持 PackedStringArray 或字符串数组")
	return result

static func _save_target_details(path: String) -> Dictionary:
	var raw := path
	if raw.is_empty(): return {"ok":false,"error_code":"profile.path_missing","error_zh":"项目配置没有可用的保存路径"}
	if raw != raw.strip_edges(): return {"ok":false,"error_code":"profile.path_invalid","error_zh":"项目配置保存目标包含首尾空白"}
	var normalized := raw.replace("\\", "/")
	if normalized.ends_with("/"):
		return {"ok":false,"error_code":"profile.path_invalid","error_zh":"项目配置保存目标必须是文件路径"}
	var virtual_path := normalized.begins_with("res://") or normalized.begins_with("user://")
	if not virtual_path and not normalized.is_absolute_path():
		return {"ok":false,"error_code":"profile.path_invalid","error_zh":"项目配置保存目标不是受支持的本地路径"}
	if virtual_path:
		var stack: Array[String] = []
		for part in normalized.trim_prefix("res://").trim_prefix("user://").split("/", false):
			if part.is_empty() or part == ".": continue
			if part == "..":
				if stack.is_empty(): return {"ok":false,"error_code":"profile.path_invalid","error_zh":"项目配置保存目标越出受支持目录"}
				stack.pop_back()
			else: stack.append(part)
		if stack.is_empty(): return {"ok":false,"error_code":"profile.path_invalid","error_zh":"项目配置保存目标必须是文件路径"}
	var absolute := ProjectSettings.globalize_path(normalized)
	if absolute.is_empty(): return {"ok":false,"error_code":"profile.path_invalid","error_zh":"项目配置保存目标无法解析"}
	if DirAccess.dir_exists_absolute(absolute): return {"ok":false,"error_code":"profile.path_invalid","error_zh":"项目配置保存目标是目录"}
	var parent := absolute.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent):
		return {"ok":false,"error_code":"profile.path_parent_missing","error_zh":"项目配置保存目标的父目录不存在"}
	return {"ok":true,"path":normalized,"absolute":absolute}
