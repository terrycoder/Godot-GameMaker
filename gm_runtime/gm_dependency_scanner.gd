class_name GMDependencyScanner
extends RefCounted

const MODULE_MANIFEST_SCRIPT := preload("res://gm_runtime/gm_module_manifest.gd")
const FORBIDDEN_RUNTIME_ROOTS := ["res://addons/gm_editor", "res://DOCS"]
const MAX_STATIC_EXPRESSION_LENGTH := 4096
const MAX_STATIC_EXPRESSION_DEPTH := 24
const MAX_STATIC_EXPRESSION_TERMS := 64

static func scan(root: String = "res://") -> Dictionary:
	var violations: Array[Dictionary] = []
	var unresolved: Array[Dictionary] = []
	var visited_files: Dictionary = {}
	_scan_path(root, violations, visited_files, unresolved)
	return _result(violations, unresolved)

static func scan_project() -> Dictionary:
	var violations: Array[Dictionary] = []
	var unresolved: Array[Dictionary] = []
	var visited_files: Dictionary = {}
	for root in ["res://gm_runtime", "res://gm_adapters", "res://project.godot"]:
		_scan_path(root, violations, visited_files, unresolved)
	return _result(violations, unresolved)

static func _result(violations: Array[Dictionary], unresolved: Array[Dictionary] = []) -> Dictionary:
	return {"ok":violations.is_empty(),"violations":violations,"unresolved_expressions":unresolved,"error_zh":"发现非法依赖：%s" % violations[0].source if not violations.is_empty() else ""}

static func _scan_path(path: String, violations: Array[Dictionary], visited_files: Dictionary, unresolved: Array[Dictionary]) -> void:
	var normalized := path.replace("\\", "/")
	if FileAccess.file_exists(ProjectSettings.globalize_path(normalized)):
		_scan_file(normalized, violations, visited_files, unresolved)
		return
	var dir := DirAccess.open(normalized)
	if dir == null: return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty(): break
		if name in [".", "..", ".godot"]: continue
		var child := normalized.path_join(name)
		if dir.current_is_dir():
			_scan_path(child, violations, visited_files, unresolved)
		else:
			_scan_file(child, violations, visited_files, unresolved)
	dir.list_dir_end()

static func _scan_file(path: String, violations: Array[Dictionary], visited_files: Dictionary, unresolved: Array[Dictionary]) -> void:
	var normalized := path.replace("\\", "/")
	if visited_files.has(normalized): return
	visited_files[normalized] = true
	var name := normalized.get_file().to_lower()
	var file := FileAccess.open(normalized, FileAccess.READ)
	if file == null: return
	var source_text := file.get_as_text()
	var semantic_source_text := source_text
	if name.ends_with(".tscn") or name.ends_with(".tres"):
		var resource: Resource = _load_resource(normalized) if _declares_module_manifest(source_text) else null
		var semantic_export_exclusions: Array[String] = _manifest_field_paths(resource, "export_excluded_paths")
		_scan_resource_dependency_graph(normalized, normalized, [], semantic_export_exclusions, violations, {})
		semantic_source_text = _strip_manifest_field(source_text, resource, "export_excluded_paths")
		# editor_root is manifest metadata, not a runtime Resource/PackedScene
		# dependency.  Keep it out of the literal-path pass while retaining the
		# actual dependency graph and export-exclusion checks above.
		semantic_source_text = _strip_manifest_field(semantic_source_text, resource, "editor_root")
	_scan_text_references(normalized, semantic_source_text, violations, unresolved)
	if name.ends_with(".tres") or name.ends_with(".tscn"):
		for value in _quoted_strings(semantic_source_text):
			if value.begins_with("res://") or value.begins_with("*res://"):
				_report_path_reference(normalized, value, [normalized, _normalize_path(value)], "移除Resource/PackedScene对被排除内容的依赖", violations)
	if name.ends_with(".godot"):
		for value in _quoted_strings(semantic_source_text):
			if value.begins_with("res://") or value.begins_with("*res://"):
				_report_path_reference(normalized, value, [normalized, _normalize_path(value)], "配置项引用了被排除路径", violations)
	for forbidden in ["EditorInterface", "EditorPlugin", "EditorUndoRedoManager"]:
		if source_text.contains(forbidden) and not normalized.contains("addons/gm_editor") and not GMDependencyPolicy.allows_editor_literals(normalized):
			_add_unique(violations, normalized, forbidden, [normalized, forbidden], "运行时移除Editor API引用，改用显式运行时接口")

static func _scan_text_references(source: String, text: String, violations: Array[Dictionary], unresolved: Array[Dictionary]) -> void:
	var constants: Dictionary = {}
	var assignments: Array[Dictionary] = []
	for line in text.split("\n"):
		var assignment := _assignment_expression(line)
		if not assignment.is_empty(): assignments.append(assignment)
	var reported_assignments: Dictionary = {}
	for pass_index in range(assignments.size() + 1):
		var changed := false
		for assignment in assignments:
			var name := str(assignment.get("name", ""))
			var evaluated := _evaluate_string_expression_result(str(assignment.get("expression", "")), constants)
			if not bool(evaluated.get("ok", false)): continue
			var value := str(evaluated.get("value", ""))
			if not constants.has(name) or str(constants[name]) != value:
				constants[name] = value
				changed = true
			var assignment_key := "%s|%s" % [name, str(assignment.get("expression", ""))]
			if not reported_assignments.has(assignment_key) and (value.begins_with("res://") or value.begins_with("*res://")):
				reported_assignments[assignment_key] = true
				_report_path_reference(source, value, [source, _normalize_path(value)], "字符串常量引用了被排除路径", violations)
		if not changed: break
	for assignment in assignments:
		var pending_expression := str(assignment.get("expression", ""))
		if not constants.has(str(assignment.get("name", ""))) and _expression_may_be_path(pending_expression, constants) and not _contains_static_loader(pending_expression, constants):
			_add_unresolved(unresolved, source, pending_expression, "静态表达式无法在受限常量范围内确认")
	for call in _load_preload_calls(text):
		var expression := str(call.get("argument", ""))
		var evaluated := _evaluate_string_expression_result(expression, constants)
		if bool(evaluated.get("ok", false)):
			var value := str(evaluated.get("value", ""))
			if value.begins_with("res://") or value.begins_with("*res://"):
				_report_path_reference(source, value, [source, _normalize_path(value)], "load/preload引用了被排除路径", violations)
		elif _expression_may_be_path(expression, constants):
			_add_unresolved(unresolved, source, expression, "load/preload参数无法静态确认，需改为明确的运行时边界")

static func _assignment_expression(line: String) -> Dictionary:
	var stripped := line.strip_edges()
	if stripped.is_empty() or stripped.begins_with("#"): return {}
	var regex := RegEx.new()
	if regex.compile("^(?:(?:static)\\s+)?(?:const|var)\\s+([A-Za-z_][A-Za-z0-9_]*)[^=]*=\\s*(.+)$") != OK: return {}
	var match := regex.search(stripped)
	if match == null: return {}
	return {"name":match.get_string(1),"expression":_strip_inline_comment(match.get_string(2))}

static func _evaluate_string_expression(expression: String, constants: Dictionary) -> String:
	var evaluated := _evaluate_string_expression_result(expression, constants)
	return str(evaluated.get("value", "")) if bool(evaluated.get("ok", false)) else ""

static func _evaluate_string_expression_result(expression: String, constants: Dictionary) -> Dictionary:
	var value := _strip_inline_comment(expression).strip_edges()
	if value.is_empty() or value.length() > MAX_STATIC_EXPRESSION_LENGTH:
		return {"ok":false,"value":""}
	var state := {"text":value,"position":0,"ok":true,"depth":0,"terms":0,"constants":constants}
	var result := _parse_static_expression(state)
	_skip_static_space(state)
	if not bool(state.ok) or int(state.position) != value.length(): return {"ok":false,"value":""}
	return {"ok":true,"value":result}

static func _parse_static_expression(state: Dictionary) -> String:
	var result := _parse_static_term(state)
	while bool(state.ok):
		_skip_static_space(state)
		var position := int(state.position)
		var text := str(state.text)
		if position >= text.length() or text[position] == ")": break
		if text[position] != "+":
			state.ok = false
			break
		state.position = position + 1
		state.terms = int(state.terms) + 1
		if int(state.terms) > MAX_STATIC_EXPRESSION_TERMS:
			state.ok = false
			break
		result += _parse_static_term(state)
	return result

static func _parse_static_term(state: Dictionary) -> String:
	_skip_static_space(state)
	var text := str(state.text)
	var position := int(state.position)
	if position >= text.length():
		state.ok = false
		return ""
	var character := text[position]
	if character == "\"" or character == "'":
		var quote := character
		state.position = position + 1
		var result := ""
		var closed := false
		while int(state.position) < text.length():
			var current := text[int(state.position)]
			if current == "\\":
				if int(state.position) + 1 >= text.length():
					state.ok = false
					return ""
				state.position = int(state.position) + 1
				var escaped := text[int(state.position)]
				match escaped:
					"n": result += "\n"
					"r": result += "\r"
					"t": result += "\t"
					_: result += escaped
				state.position = int(state.position) + 1
			elif current == quote:
				state.position = int(state.position) + 1
				closed = true
				break
			else:
				result += current
				state.position = int(state.position) + 1
		if not closed: state.ok = false
		return result
	if character == "(":
		var depth := int(state.depth) + 1
		if depth > MAX_STATIC_EXPRESSION_DEPTH:
			state.ok = false
			return ""
		state.depth = depth
		state.position = position + 1
		var grouped := _parse_static_expression(state)
		_skip_static_space(state)
		if int(state.position) >= text.length() or text[int(state.position)] != ")":
			state.ok = false
			return ""
		state.position = int(state.position) + 1
		state.depth = depth - 1
		return grouped
	if not _is_identifier_start(character):
		state.ok = false
		return ""
	var start := position
	state.position = position + 1
	while int(state.position) < text.length() and _is_identifier_character(text[int(state.position)]):
		state.position = int(state.position) + 1
	var name := text.substr(start, int(state.position) - start)
	var constants: Dictionary = state.constants
	if not constants.has(name): state.ok = false
	return str(constants.get(name, ""))

static func _skip_static_space(state: Dictionary) -> void:
	var text := str(state.text)
	while int(state.position) < text.length() and text[int(state.position)] in [" ", "\t", "\r", "\n"]:
		state.position = int(state.position) + 1

static func _is_identifier_start(character: String) -> bool:
	return (character >= "A" and character <= "Z") or (character >= "a" and character <= "z") or character == "_"

static func _is_identifier_character(character: String) -> bool:
	return _is_identifier_start(character) or (character >= "0" and character <= "9")

static func _load_preload_calls(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cursor := 0
	while cursor < text.length():
		var character := text[cursor]
		if character == "#":
			var newline := text.find("\n", cursor)
			cursor = text.length() if newline < 0 else newline + 1
			continue
		if character == "\"" or character == "'":
			cursor = _quoted_end(text, cursor)
			continue
		if not _is_identifier_start(character):
			cursor += 1
			continue
		var start := cursor
		cursor += 1
		while cursor < text.length() and _is_identifier_character(text[cursor]): cursor += 1
		var name := text.substr(start, cursor - start)
		if name != "load" and name != "preload": continue
		while cursor < text.length() and text[cursor] in [" ", "\t", "\r", "\n"]: cursor += 1
		if cursor >= text.length() or text[cursor] != "(": continue
		var close := _matching_parenthesis(text, cursor)
		if close < 0:
			cursor += 1
			continue
		result.append({"name":name,"argument":text.substr(cursor + 1, close - cursor - 1)})
		cursor = close + 1
	return result

static func _matching_parenthesis(text: String, opening: int) -> int:
	var depth := 0
	var cursor := opening
	while cursor < text.length():
		var character := text[cursor]
		if character == "#":
			var newline := text.find("\n", cursor)
			cursor = text.length() if newline < 0 else newline + 1
			continue
		if character == "\"" or character == "'":
			cursor = _quoted_end(text, cursor)
			continue
		if character == "(": depth += 1
		elif character == ")":
			depth -= 1
			if depth == 0: return cursor
		cursor += 1
	return -1

static func _quoted_end(text: String, opening: int) -> int:
	var quote := text[opening]
	var cursor := opening + 1
	while cursor < text.length():
		if text[cursor] == "\\":
			cursor += 2
			continue
		if text[cursor] == quote: return cursor + 1
		cursor += 1
	return text.length()

static func _expression_may_be_path(expression: String, constants: Dictionary) -> bool:
	var value := expression.strip_edges()
	while value.begins_with("("):
		value = value.trim_prefix("(").strip_edges()
	if value.begins_with("\"res://") or value.begins_with("'res://") or value.begins_with("\"*res://") or value.begins_with("'*res://"): return true
	for name in constants:
		var constant_value := str(constants[name]).to_lower()
		if (constant_value.begins_with("res://") or constant_value.begins_with("*res://")) and expression.contains(str(name)):
			return true
	return false

static func _contains_static_loader(expression: String, constants: Dictionary) -> bool:
	for call in _load_preload_calls(expression):
		var evaluated := _evaluate_string_expression_result(str(call.get("argument", "")), constants)
		if bool(evaluated.get("ok", false)): return true
	return false

static func _add_unresolved(unresolved: Array[Dictionary], source: String, expression: String, reason: String) -> void:
	var normalized := expression.strip_edges()
	for item in unresolved:
		if str(item.get("source", "")) == source and str(item.get("expression", "")) == normalized: return
	unresolved.append({"source":source,"expression":normalized,"chain":[source,"static-expression"],"status":"not_statically_confirmable","fix_zh":reason})

static func _quoted_strings(text: String) -> Array[String]:
	var result: Array[String] = []
	var cursor := 0
	while cursor < text.length():
		if text[cursor] == "#":
			var newline := text.find("\n", cursor)
			cursor = text.length() if newline < 0 else newline + 1
			continue
		var quote := text[cursor]
		if quote != "\"" and quote != "'":
			cursor += 1
			continue
		cursor += 1
		var value := ""
		var closed := false
		while cursor < text.length():
			var character := text[cursor]
			if character == "\\" and cursor + 1 < text.length():
				cursor += 1
				value += text[cursor]
				cursor += 1
			elif character == quote:
				cursor += 1
				closed = true
				break
			else:
				value += character
				cursor += 1
		if closed: result.append(value)
	return result

static func _strip_inline_comment(value: String) -> String:
	var quote := ""
	var escaped := false
	for index in value.length():
		var character := value[index]
		if escaped:
			escaped = false
			continue
		if character == "\\" and not quote.is_empty():
			escaped = true
			continue
		if (character == "\"" or character == "'"):
			if quote.is_empty(): quote = character
			elif quote == character: quote = ""
		elif character == "#" and quote.is_empty(): return value.substr(0, index)
	return value

static func _scan_resource_dependency_graph(source: String, path: String, chain: Array, declared_exclusions: Array[String], violations: Array[Dictionary], stack: Dictionary) -> void:
	var normalized := _normalize_path(path)
	if stack.has(normalized): return
	stack[normalized] = true
	var dependencies: PackedStringArray = ResourceLoader.get_dependencies(normalized)
	for dependency in dependencies:
		var target := _normalize_path(dependency)
		if target.is_empty(): continue
		var next_chain: Array = chain.duplicate()
		if next_chain.is_empty(): next_chain.append(source)
		next_chain.append(target)
		if _is_forbidden_path(target) and not _path_matches_any(target, declared_exclusions) and not GMDependencyPolicy.allows(source, target):
			_add_unique(violations, source, target, next_chain, "移除Resource/PackedScene/Autoload对被排除内容的依赖")
		if target.begins_with("res://") and FileAccess.file_exists(ProjectSettings.globalize_path(target)) and (target.ends_with(".tres") or target.ends_with(".tscn")):
			_scan_resource_dependency_graph(source, target, next_chain, declared_exclusions, violations, stack)
	stack.erase(normalized)

static func _report_path_reference(source: String, raw_target: String, chain: Array, fix: String, violations: Array[Dictionary]) -> void:
	var target := _normalize_path(raw_target)
	if not _is_forbidden_path(target): return
	if GMDependencyPolicy.allows(source, target): return
	_add_unique(violations, source, target, chain, fix)

static func _add_unique(violations: Array[Dictionary], source: String, target: String, chain: Array, fix: String) -> void:
	var normalized_target := _normalize_path(target)
	for item in violations:
		if str(item.get("source", "")) == source and str(item.get("target", "")) == normalized_target and item.get("chain", []) == chain: return
	violations.append({"source":source,"target":normalized_target,"chain":chain,"fix_zh":fix})

static func _normalize_path(value: Variant) -> String:
	var path := str(value).strip_edges().replace("\\", "/")
	while path.begins_with("*"): path = path.trim_prefix("*")
	return path

static func _is_forbidden_path(path: String) -> bool:
	var normalized := path.to_lower().trim_suffix("/")
	for root in FORBIDDEN_RUNTIME_ROOTS:
		var lower_root := str(root).to_lower().trim_suffix("/")
		if normalized == lower_root or normalized.begins_with(lower_root + "/"): return true
	return false

static func _load_resource(path: String) -> Resource:
	var resource := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	return resource if resource is Resource else null

static func _declares_module_manifest(source_text: String) -> bool:
	return source_text.contains("script_class=\"GMModuleManifest\"") or source_text.contains("script_class='GMModuleManifest'")

static func _manifest_field_paths(resource: Resource, field_name: String) -> Array[String]:
	if resource == null or resource.get_script() != MODULE_MANIFEST_SCRIPT: return []
	var value: Variant = resource.get(field_name)
	var paths: Array[String] = []
	if value is PackedStringArray:
		for item in value:
			var path := str(item).replace("\\", "/").strip_edges()
			if not path.is_empty(): paths.append(path)
	elif value is Array:
		for item in value:
			var path := str(item).replace("\\", "/").strip_edges()
			if not path.is_empty(): paths.append(path)
	return paths

static func _path_matches_any(path: String, declared_paths: Array[String]) -> bool:
	var normalized := path.replace("\\", "/").strip_edges().trim_suffix("/")
	for declared in declared_paths:
		var prefix := str(declared).replace("\\", "/").strip_edges().trim_suffix("/")
		if normalized == prefix or normalized.begins_with(prefix + "/"): return true
	return false

static func _strip_manifest_field(source_text: String, resource: Resource, field_name: String) -> String:
	if resource == null or resource.get_script() != MODULE_MANIFEST_SCRIPT: return source_text
	var lines := source_text.split("\n")
	var result: Array[String] = []
	var skipping := false
	var delimiter_depth := 0
	var assignment_prefix := field_name + " ="
	for line in lines:
		if not skipping:
			if line.strip_edges().begins_with(assignment_prefix):
				delimiter_depth = _delimiter_delta(line)
				result.append("")
				if delimiter_depth > 0: skipping = true
			else:
				result.append(line)
		else:
			result.append("")
			delimiter_depth += _delimiter_delta(line)
			if delimiter_depth <= 0: skipping = false
	return "\n".join(result)

static func _delimiter_delta(line: String) -> int:
	return line.count("(") + line.count("[") + line.count("{") - line.count(")") - line.count("]") - line.count("}")
