class_name GMStableData
extends RefCounted

## 后台模拟只允许 JSON 等价的值：不可携带运行时对象、资源或节点引用。

const JSON_SAFE_INTEGER_MAX := 9007199254740991

## Schema versions cross the Native/JSON boundary as either integer or float
## values.  Keep their normalization in one shared rule so every spatial
## parser accepts exactly the same supported value and rejects coercion.
static func normalize_schema_version(value: Variant) -> Dictionary:
	var valid := false
	match typeof(value):
		TYPE_INT:
			valid = int(value) == 1
		TYPE_FLOAT:
			var numeric := float(value)
			valid = is_finite(numeric) and numeric == floor(numeric) and numeric == 1.0
		_:
			valid = false
	if valid:
		return {"ok": true, "value": 1}
	return {"ok": false, "code": "schema_version.invalid", "error_zh": "Schema版本必须是有限、精确等于1的整数数值。"}

static func validate(value: Variant, path: String = "$", allow_empty: bool = true) -> Dictionary:
	var errors: Array[String] = []
	_validate(value, path, errors, allow_empty)
	return {"ok": errors.is_empty(), "errors": errors, "code": "stable_data.valid" if errors.is_empty() else "stable_data.invalid"}

static func validate_persistence(value: Variant, path: String = "$") -> Dictionary:
	var errors: Array[String] = []
	_validate(value, path, errors, true)
	_validate_persistence(value, path, errors)
	return {"ok": errors.is_empty(), "errors": errors, "code": "stable_data.persistence_valid" if errors.is_empty() else "stable_data.persistence_invalid"}

static func canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		var keys: Array[String] = []
		for key in value.keys(): keys.append(str(key))
		keys.sort()
		for key in keys: result[key] = canonical(value.get(key))
		return result
	if value is Array:
		var array_result: Array = []
		for item in value: array_result.append(canonical(item))
		return array_result
	if value is PackedStringArray:
		return canonical(Array(value))
	if value is PackedInt32Array:
		return canonical(Array(value))
	if value is PackedFloat32Array:
		return canonical(Array(value))
	if value is PackedByteArray:
		return canonical(Array(value))
	return value

static func canonical_json(value: Variant) -> String:
	return JSON.stringify(canonical(value), "", false)

static func persistence_canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		var keys: Array[String] = []
		for key in value.keys(): keys.append(str(key))
		keys.sort()
		for key in keys: result[key] = persistence_canonical(value.get(key))
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(persistence_canonical(item))
		return result
	if value is PackedStringArray or value is PackedInt32Array or value is PackedFloat32Array or value is PackedByteArray:
		return persistence_canonical(Array(value))
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value) and abs(value) <= JSON_SAFE_INTEGER_MAX:
		return int(value)
	return value

static func persistence_canonical_json(value: Variant) -> String:
	return JSON.stringify(persistence_canonical(value), "", false)

static func digest(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(canonical_json(value).to_utf8_buffer())
	return context.finish().hex_encode()

static func clone(value: Variant) -> Variant:
	return canonical(value)

static func _validate(value: Variant, path: String, errors: Array[String], allow_empty: bool) -> void:
	if value is Object:
		errors.append("%s 不得保存运行时对象引用。" % path)
		return
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return
		TYPE_STRING:
			if not allow_empty and str(value).is_empty(): errors.append("%s 不得为空。" % path)
			return
		TYPE_ARRAY:
			for index in value.size(): _validate(value[index], "%s[%d]" % [path, index], errors, allow_empty)
			return
		TYPE_DICTIONARY:
			for key in value.keys():
				if key is Object: errors.append("%s 的键不得是对象。" % path); continue
				_validate(value[key], "%s.%s" % [path, str(key)], errors, allow_empty)
			return
		_:
			errors.append("%s 包含不可序列化值类型：%s。" % [path, type_string(typeof(value))])

static func _validate_persistence(value: Variant, path: String, errors: Array[String]) -> void:
	match typeof(value):
		TYPE_INT:
			if value < -JSON_SAFE_INTEGER_MAX or value > JSON_SAFE_INTEGER_MAX:
				errors.append("%s 超出JSON安全整数范围。" % path)
		TYPE_FLOAT:
			if not is_finite(value): errors.append("%s 必须是有限数值。" % path)
			elif value == floor(value) and abs(value) > JSON_SAFE_INTEGER_MAX: errors.append("%s 超出JSON安全整数范围。" % path)
		TYPE_ARRAY:
			for index in value.size(): _validate_persistence(value[index], "%s[%d]" % [path, index], errors)
		TYPE_DICTIONARY:
			for key in value.keys():
				if typeof(key) != TYPE_STRING:
					errors.append("%s 的持久化键必须是字符串。" % path)
					continue
				_validate_persistence(value[key], "%s.%s" % [path, key], errors)

static func type_string(value_type: int) -> String:
	return str(value_type)
