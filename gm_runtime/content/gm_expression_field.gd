@tool
class_name GMExpressionField
extends Resource

## 只保存 Godot Expression 的短规则，不保存任意 GDScript 文本。
@export var expression: String = ""
@export var input_names: PackedStringArray = PackedStringArray()
@export_enum("bool", "int", "float", "String", "Variant") var expected_type: String = "bool"
@export_multiline var help_zh: String = ""

func validate(input_values: Dictionary = {}) -> Dictionary:
	var errors: Array[Dictionary] = []
	if expression.strip_edges().is_empty():
		errors.append({"code":"expression.empty","reason_zh":"Expression 不能为空。","suggestion_zh":"填写一个返回条件或数值的 Expression。"})
		return _result(errors)
	var parser := Expression.new()
	var parse_error := parser.parse(expression, input_names)
	if parse_error != OK:
		errors.append({"code":"expression.syntax","reason_zh":"Expression 语法错误：%s" % parser.get_error_text(),"suggestion_zh":"检查括号、运算符和输入变量名。"})
		return _result(errors)
	for unknown_name in _unknown_identifiers(expression):
		errors.append({"code":"expression.unknown_variable","reason_zh":"Expression 使用了未声明变量：%s" % unknown_name,"suggestion_zh":"把变量加入输入列表或修正变量名。"})
	if not errors.is_empty(): return _result(errors)
	for input_name in input_names:
		if not input_values.has(input_name):
			errors.append({"code":"expression.unknown_variable","reason_zh":"Expression 输入变量未提供：%s" % input_name,"suggestion_zh":"在运行时输入字典中提供该变量，或从输入列表移除它。"})
	if not errors.is_empty(): return _result(errors)
	var values: Array = []
	for input_name in input_names: values.append(input_values[input_name])
	var value = parser.execute(values, self)
	if parser.has_execute_failed():
		errors.append({"code":"expression.execute","reason_zh":"Expression 执行失败：%s" % parser.get_error_text(),"suggestion_zh":"检查运行时输入类型与表达式运算。"})
		return _result(errors)
	if not _matches_expected_type(value):
		errors.append({"code":"expression.return_type","reason_zh":"Expression 返回类型不符：期望 %s，实际 %s。" % [expected_type, typeof(value)],"suggestion_zh":"修改表达式或字段的返回类型设置。"})
	return {"ok":errors.is_empty(),"errors":errors,"errors_zh":_messages(errors),"value":value}

func evaluate(input_values: Dictionary = {}) -> Dictionary:
	return validate(input_values)

func _matches_expected_type(value: Variant) -> bool:
	match expected_type:
		"bool": return value is bool
		"int": return value is int and not value is bool
		"float": return value is float or (value is int and not value is bool)
		"String": return value is String
		_: return true

func _result(errors: Array[Dictionary]) -> Dictionary:
	return {"ok":errors.is_empty(),"errors":errors,"errors_zh":_messages(errors)}

func _messages(errors: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for error in errors: result.append(str(error.reason_zh))
	return result

func _unknown_identifiers(source: String) -> Array[String]:
	var cleaned := source
	var string_regex := RegEx.new()
	string_regex.compile("\\\"(?:\\\\.|[^\\\"\\\\])*\\\"|'(?:\\\\.|[^'\\\\])*'")
	cleaned = string_regex.sub(cleaned, "", true)
	var identifier_regex := RegEx.new()
	identifier_regex.compile("\\b[A-Za-z_][A-Za-z0-9_]*\\b")
	var allowed := {"true":true,"false":true,"null":true,"and":true,"or":true,"not":true,"in":true,"if":true,"else":true,"abs":true,"sign":true,"floor":true,"ceil":true,"round":true,"sqrt":true,"pow":true,"sin":true,"cos":true,"tan":true,"asin":true,"acos":true,"atan":true,"atan2":true,"lerp":true,"clamp":true,"min":true,"max":true,"PI":true,"TAU":true}
	for input_name in input_names: allowed[str(input_name)] = true
	var result: Array[String] = []
	for match in identifier_regex.search_all(cleaned):
		var value := match.get_string(0)
		if not allowed.has(value) and not result.has(value): result.append(value)
	return result
