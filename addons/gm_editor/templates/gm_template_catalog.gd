@tool
class_name GMTemplateCatalog
extends RefCounted

const TEMPLATE_PATHS := {
	"blank_2d": "res://addons/gm_editor/templates/blank_2d.tres",
	"rpg_arpg": "res://addons/gm_editor/templates/rpg_arpg.tres",
	"management": "res://addons/gm_editor/templates/management.tres",
}
const REGISTRY := preload("res://gm_runtime/gm_module_registry.gd")
const RESULT_SCHEMA := "gm.template-validation.v2"
const UNICODE_WHITE_SPACE_SINGLETONS := {
	0x0020: true,
	0x0085: true,
	0x00A0: true,
	0x1680: true,
	0x2028: true,
	0x2029: true,
	0x202F: true,
	0x205F: true,
	0x3000: true,
}
const UNICODE_ZWNBSP := 0xFEFF

static func all_templates() -> Dictionary:
	var result: Dictionary = {}
	for template_id in TEMPLATE_PATHS:
		var template = load(TEMPLATE_PATHS[template_id])
		if template is Resource:
			result[template_id] = template
	return result

# The public lookup is deliberately Variant-typed. Invalid callers are
# rejected before a path is handed to the resource loader.
static func get_template(template_id: Variant):
	if not template_id is String: return null
	var normalized_id := str(template_id)
	if normalized_id.is_empty() or normalized_id != normalized_id.strip_edges(): return null
	if not TEMPLATE_PATHS.has(normalized_id): return null
	var path := str(TEMPLATE_PATHS.get(normalized_id, ""))
	if path.is_empty(): return null
	var template = load(path)
	return template if template is Resource else null

static func validate_template(template_id: Variant, enabled_modules: Variant, terminology_override: Variant = {}) -> Dictionary:
	var errors: Array[String] = []
	var input_id := "" if not template_id is String else str(template_id)
	if not template_id is String:
		errors.append("模板ID类型无效：仅支持字符串")
		return _validation_result(input_id, null, [], errors, {}, "template.invalid_type")
	if input_id.strip_edges().is_empty():
		errors.append("模板ID不能为空或仅包含空白")
		return _validation_result(input_id, null, [], errors, {}, "template.empty_id")
	if input_id != input_id.strip_edges():
		errors.append("模板ID不得包含首尾空白：%s" % input_id)
		return _validation_result(input_id, null, [], errors, {}, "template.whitespace_id")
	if not TEMPLATE_PATHS.has(input_id):
		errors.append("未知策划模板：%s" % input_id)
		return _validation_result(input_id, null, [], errors, {}, "template.unknown_id")
	var modules := _coerce_modules(enabled_modules, errors)
	if not errors.is_empty():
		return _validation_result(input_id, null, [], errors, {}, "template.invalid_modules")
	var terms: Dictionary = {}
	if terminology_override == null:
		terms = {}
	elif terminology_override is Dictionary:
		terms = terminology_override
		_validate_terminology_values(terms, errors)
	else:
		errors.append("模板术语覆盖类型无效：仅支持字典")
		return _validation_result(input_id, null, [], errors, {}, "template.invalid_terminology")
	if not errors.is_empty():
		return _validation_result(input_id, null, [], errors, {}, "template.invalid_terminology")
	var resolution: Dictionary = _resolve_modules(modules)
	if not bool(resolution.get("ok", false)):
		for error in _string_array(resolution.get("errors_zh", [])): errors.append(error)
		if errors.is_empty(): errors.append("模板模块依赖或冲突解析失败，已安全阻断")
		return _validation_result(input_id, null, _string_array(resolution.get("selected", [])), errors, resolution, "template.module_resolution")
	var template = get_template(input_id)
	if template == null:
		errors.append("策划模板资源无法读取：%s" % input_id)
		return _validation_result(input_id, null, [], errors, {}, "template.resource_invalid")
	var selected: Array[String] = _string_array(resolution.get("selected", []))
	for module_id in template.required_modules:
		if not selected.has(module_id):
			errors.append("模板“%s”需要模块“%s”，当前已禁用或未安装；请启用依赖后重试" % [template.display_name_zh, module_id])
	if terms.is_empty(): terms = template.terminology
	for key in template.required_terminology_keys:
		if not terms.has(key):
			errors.append("模板“%s”缺少术语键“%s”；请补齐中文术语后重试" % [template.display_name_zh, key])
		elif not _is_nonempty_string(terms.get(key)):
			errors.append("模板“%s”的术语键“%s”必须是去除首尾空白后非空的字符串；请修正后重试" % [template.display_name_zh, key])
	return _validation_result(input_id, template, selected, errors, resolution, "template.validation")

static func validate_profile(profile: Variant) -> Dictionary:
	if profile == null:
		return _validation_result("", null, [], ["项目配置资源不存在：res://gm_runtime/gm_module_profile.tres"], {}, "profile.missing")
	if not profile is Resource:
		return _validation_result("", null, [], ["项目配置资源类型无效：仅支持 Resource"], {}, "profile.invalid_type")
	return validate_template(profile.get("template_id"), profile.get("enabled_modules"))

static func template_differences(from_id: Variant, to_id: Variant) -> Dictionary:
	var from_template = get_template(from_id)
	var to_template = get_template(to_id)
	if from_template == null or to_template == null:
		var errors: Array[String] = ["模板不存在，无法计算差异"]
		return {"schema_version": RESULT_SCHEMA, "ok": false, "errors_zh": errors, "from": str(from_id), "to": str(to_id)}
	return {
		"schema_version": RESULT_SCHEMA,
		"ok": true,
		"errors_zh": [],
		"from": from_id,
		"to": to_id,
		"layout_changed": from_template.layout_sections != to_template.layout_sections,
		"terminology_changed": from_template.terminology != to_template.terminology,
		"modules_changed": from_template.required_modules != to_template.required_modules,
		"content_preserved": true,
	}

static func _validation_result(template_id: String, template: Variant, selected: Array[String], errors: Array[String], resolution: Dictionary, error_code: String = "template.validation") -> Dictionary:
	var typed_errors: Array[String] = []
	for error in errors: typed_errors.append(str(error))
	return {
		"schema_version": RESULT_SCHEMA,
		"ok": typed_errors.is_empty(),
		"error_code": "" if typed_errors.is_empty() else error_code,
		"template_id": template_id,
		"template": template,
		"selected_modules": selected.duplicate(),
		"errors_zh": typed_errors,
		"resolution": resolution.duplicate(true),
	}

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
	errors.append("启用模块类型无效：仅支持 PackedStringArray 或字符串数组")
	return result

static func _resolve_modules(modules: PackedStringArray) -> Dictionary:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for module_id in modules:
		var normalized := str(module_id)
		if normalized.strip_edges().is_empty():
			errors.append("启用模块ID不能为空")
		elif normalized != normalized.strip_edges():
			errors.append("启用模块ID不得包含首尾空白：%s" % module_id)
		elif seen.has(normalized):
			errors.append("启用模块不得重复：%s" % normalized)
		else:
			seen[normalized] = true
	var registry_result: Dictionary = REGISTRY.resolve(modules)
	for error in _string_array(registry_result.get("errors_zh", [])):
		if not errors.has(error): errors.append(error)
	var selected := _string_array(registry_result.get("selected", []))
	var registry_ok := bool(registry_result.get("ok", false))
	if not registry_ok and errors.is_empty():
		errors.append("任务01模块 Registry 未通过依赖/冲突合同，模板验证已安全阻断")
	return {
		"ok": errors.is_empty() and registry_ok,
		"selected": selected,
		"errors_zh": errors,
		"manifests": registry_result.get("manifests", {}),
		"registry_result": registry_result.duplicate(true),
	}

static func _validate_terminology_values(values: Dictionary, errors: Array[String]) -> void:
	for raw_key in values.keys():
		if not raw_key is String:
			errors.append("模板术语键类型无效：术语键必须是字符串")
			continue
		var key := str(raw_key)
		var value = values.get(raw_key)
		if not _is_nonempty_string(value):
			errors.append("模板术语键“%s”的值必须是去除首尾空白后非空的字符串" % key)

static func _is_nonempty_string(value: Variant) -> bool:
	if not value is String:
		return false
	var text := str(value)
	if text.is_empty():
		return false
	for index in text.length():
		if not _is_unicode_blank_codepoint(text.unicode_at(index)):
			return true
	return false

static func _is_unicode_blank_codepoint(codepoint: int) -> bool:
	# Unicode White_Space: HT..CR, SPACE, NEL, NBSP, OGHAM,
	# U+2000..U+200A, line/paragraph separators, narrow NBSP,
	# medium mathematical space and ideographic space.
	if codepoint >= 0x0009 and codepoint <= 0x000D:
		return true
	if codepoint >= 0x2000 and codepoint <= 0x200A:
		return true
	if UNICODE_WHITE_SPACE_SINGLETONS.has(codepoint):
		return true
	# U+FEFF/ZWNBSP is not Unicode White_Space. It is blank only when
	# the whole value is made of boundary characters, as enforced by the
	# all-codepoint scan in _is_nonempty_string().
	return codepoint == UNICODE_ZWNBSP

static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array or value is PackedStringArray:
		for item in value:
			if item is String: result.append(str(item))
	return result
