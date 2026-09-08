@tool
class_name GMEventScriptValidator
extends RefCounted

## 任务07 的 GDScript 扩展验证器。
##
## 脚本是策划可替换的规则扩展，但加载失败、基类错误、方法签名错误和
## 返回类型错误都必须成为可定位的结构化错误；不能因为 ResourceLoader
## 返回 null 就把条件静默当成 false。

static func validate_file(path: String, expected_base: String, required_method: String, expected_argument_count: int, expected_return_type: String = "Dictionary") -> Dictionary:
	var errors: Array[Dictionary] = []
	var normalized_path := path.strip_edges()
	if normalized_path.is_empty():
		errors.append(_error("script.path_missing", "GDScript 扩展缺少脚本路径。", 0))
		return _result(normalized_path, expected_base, required_method, errors)
	if not FileAccess.file_exists(normalized_path):
		errors.append(_error("script.file_missing", "GDScript 扩展文件不存在：%s。" % normalized_path, 0))
		return _result(normalized_path, expected_base, required_method, errors)
	var source := FileAccess.get_file_as_string(normalized_path)
	if source.strip_edges().is_empty():
		errors.append(_error("script.source_empty", "GDScript 扩展文件为空：%s。" % normalized_path, 1))
		return _result(normalized_path, expected_base, required_method, errors)
	var script_value: Variant = ResourceLoader.load(normalized_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if script_value == null or not script_value is Script:
		errors.append(_error("script.parse_error", "GDScript 解析失败，无法加载：%s。请检查脚本语法。" % normalized_path, _line_for(source, "extends")))
		return _result(normalized_path, expected_base, required_method, errors)
	var script: Script = script_value
	var script_can_instantiate: bool = script.can_instantiate()
	if not script_can_instantiate:
		errors.append(_error("script.parse_error", "GDScript 解析失败，脚本不可实例化：%s。请检查基类、方法签名和语法。" % normalized_path, _line_for(source, "func")))
	var extends_name := _extends_name(source)
	if not _inherits_expected(script, source, expected_base):
		errors.append(_error("script.base_invalid", "脚本基类错误：期望继承 %s，实际声明为 %s。" % [expected_base, extends_name if not extends_name.is_empty() else "未知"], _line_for(source, "extends")))
	var method_info := _find_method(script, required_method)
	if method_info.is_empty(): method_info = _find_method_in_source(source, required_method)
	if method_info.is_empty():
		errors.append(_error("script.method_missing", "脚本缺少规定方法 %s。" % required_method, _line_for(source, "func %s" % required_method)))
	else:
		var args: Array = method_info.get("args", []) if method_info.get("args", []) is Array else []
		if args.size() != expected_argument_count:
			errors.append(_error("script.signature_invalid", "方法 %s 参数数量错误：期望 %d，实际 %d。" % [required_method, expected_argument_count, args.size()], _line_for(source, "func %s" % required_method)))
		var declared_return := _declared_return_type(source, required_method)
		if declared_return.is_empty():
			errors.append(_error("script.return_type_missing", "方法 %s 必须显式声明返回类型 -> %s。" % [required_method, expected_return_type], _line_for(source, "func %s" % required_method)))
		elif declared_return != expected_return_type:
			errors.append(_error("script.return_type_invalid", "方法 %s 返回类型错误：期望 %s，实际 %s。" % [required_method, expected_return_type, declared_return], _line_for(source, "func %s" % required_method)))
	var instance: Variant = null
	if errors.is_empty():
		instance = script.new()
		if instance == null or not _instance_matches_base(instance, expected_base):
			errors.append(_error("script.base_runtime_invalid", "脚本运行时实例不是 %s，已阻断使用。" % expected_base, _line_for(source, "extends")))
	return _result(normalized_path, expected_base, required_method, errors, script, instance)

static func validate_condition_script(path: String) -> Dictionary:
	return validate_file(path, "GMEventCondition", "_evaluate_custom", 1, "Dictionary")

static func validate_handler_script(path: String) -> Dictionary:
	return validate_file(path, "GMEventHandler", "_handle_event", 2, "Dictionary")

static func validate_selector_script(path: String) -> Dictionary:
	return validate_file(path, "GMTargetSelector", "_select", 2, "Dictionary")

static func validate_instance(instance: Object, expected_base: String, required_method: String, expected_argument_count: int, expected_return_type: String = "Dictionary") -> Dictionary:
	if instance == null or not is_instance_valid(instance):
		return _result("", expected_base, required_method, [_error("script.instance_missing", "GDScript 扩展实例不存在，无法验证。", 0)])
	var script_value: Variant = instance.get_script()
	if script_value == null or not script_value is Script:
		return _result("", expected_base, required_method, [_error("script.attached_script_missing", "对象没有可验证的附加 GDScript。", 0)])
	var script: Script = script_value
	var path := str(script.resource_path)
	if path.is_empty():
		return _result(path, expected_base, required_method, [_error("script.resource_path_missing", "附加 GDScript 没有稳定资源路径，无法提供错误定位。", 0)])
	return validate_file(path, expected_base, required_method, expected_argument_count, expected_return_type)

static func _result(path: String, expected_base: String, required_method: String, errors: Array[Dictionary], script: Script = null, instance: Variant = null) -> Dictionary:
	var messages: Array[String] = []
	for item in errors: messages.append(str(item.get("reason_zh", "脚本验证失败。")))
	return {
		"ok": errors.is_empty(),
		"code": "script.valid" if errors.is_empty() else "script.invalid",
		"path": path,
		"expected_base": expected_base,
		"required_method": required_method,
		"errors": errors,
		"errors_zh": messages,
		"script": script,
		"instance": instance,
		"usage_location": {"path": path, "line": int(errors[0].get("line", 0)) if not errors.is_empty() else 1}
	}

static func _error(code: String, reason_zh: String, line: int) -> Dictionary:
	return {"code": code, "reason_zh": reason_zh, "line": line}

static func _extends_name(source: String) -> String:
	var regex := RegEx.new()
	regex.compile("(?m)^\\s*extends\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var found := regex.search(source)
	return found.get_string(1) if found != null else ""

static func _inherits_expected(script: Script, source: String, expected_base: String) -> bool:
	var declared := _extends_name(source)
	if declared == expected_base: return true
	var current: Script = script
	var guard := 0
	while current != null and guard < 16:
		var global_name := str(current.get_global_name())
		if global_name == expected_base: return true
		current = current.get_base_script()
		guard += 1
	return declared == expected_base

static func _instance_matches_base(instance: Variant, expected_base: String) -> bool:
	match expected_base:
		"GMEventCondition": return instance is GMEventCondition
		"GMEventHandler": return instance is GMEventHandler
		"GMTargetSelector": return instance is GMTargetSelector
		_: return instance != null

static func _find_method(script: Script, method_name: String) -> Dictionary:
	for method in script.get_method_list():
		if str(method.get("name", "")) == method_name: return method
	return {}

static func _find_method_in_source(source: String, method_name: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("(?m)^\\s*func\\s+" + method_name.replace(".", "\\\\.") + "\\s*\\(([^\\)]*)\\)")
	var found := regex.search(source)
	if found == null: return {}
	var raw_args := found.get_string(1).strip_edges()
	var args: Array[Dictionary] = []
	if not raw_args.is_empty():
		for raw_arg in raw_args.split(","):
			args.append({"name": raw_arg.strip_edges()})
	return {"name": method_name, "args": args, "source_fallback": true}

static func _declared_return_type(source: String, method_name: String) -> String:
	var regex := RegEx.new()
	regex.compile("(?m)^\\s*func\\s+" + method_name.replace(".", "\\.") + "\\s*\\([^\\)]*\\)\\s*->\\s*([A-Za-z_][A-Za-z0-9_\\[\\]]*)")
	var found := regex.search(source)
	return found.get_string(1) if found != null else ""

static func _line_for(source: String, needle: String) -> int:
	var lines := source.split("\n")
	for index in lines.size():
		if str(lines[index]).contains(needle): return index + 1
	return 0
