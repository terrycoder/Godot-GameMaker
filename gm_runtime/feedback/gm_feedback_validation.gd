class_name GMFeedbackValidation
extends RefCounted

## P18 shared validation helpers.  This layer accepts only stable, JSON-safe
## values and never treats a Dictionary supplied by a caller as authority.

const MAX_SAFE_INT := 9007199254740991

static func exact(value: Variant, fields: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var row: Dictionary = value
	if row.size() != fields.size():
		return false
	for field in fields:
		if not row.has(field):
			return false
	return true

## Validate the raw Variant contract before any typed assignment or coercion.
## JSON numbers are represented as finite integral floats at the JSON boundary;
## native callers must provide actual integer Variants.
static func exact_field_types(value: Variant, string_fields: Array = [], integer_fields: Array = [], boolean_fields: Array = [], array_fields: Array = [], dictionary_fields: Array = [], json_boundary: bool = false) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var row: Dictionary = value
	for field in string_fields:
		if typeof(row[field]) != TYPE_STRING:
			return false
	for field in integer_fields:
		if json_boundary:
			if typeof(row[field]) != TYPE_FLOAT or not is_finite(float(row[field])) or row[field] != floor(row[field]) or abs(float(row[field])) > MAX_SAFE_INT:
				return false
		elif typeof(row[field]) != TYPE_INT:
			return false
	for field in boolean_fields:
		if typeof(row[field]) != TYPE_BOOL:
			return false
	for field in array_fields:
		if typeof(row[field]) != TYPE_ARRAY:
			return false
	for field in dictionary_fields:
		if typeof(row[field]) != TYPE_DICTIONARY:
			return false
	return true

static func array_members_are(value: Variant, expected_type: int) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for member in value:
		if typeof(member) != expected_type:
			return false
	return true

static func stable_id(value: Variant, allow_empty: bool = false) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text := str(value)
	if text.is_empty():
		return allow_empty
	return GMTaskDefinition._stable_id(text)

static func bounded_integer(value: Variant, minimum: int, maximum: int, json_boundary: bool = false) -> bool:
	if json_boundary:
		if typeof(value) != TYPE_FLOAT or not is_finite(float(value)) or value != floor(value):
			return false
		if abs(float(value)) > MAX_SAFE_INT:
			return false
	else:
		if typeof(value) != TYPE_INT:
			return false
	return int(value) >= minimum and int(value) <= maximum

static func finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

static func digest(value: Variant) -> String:
	return GMStableData.digest(value)

static func is_digest(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or str(value).length() != 64:
		return false
	for character in str(value).to_lower():
		if character not in "0123456789abcdef":
			return false
	return true

static func stable_value(value: Variant, path: String = "$") -> Dictionary:
	var checked := GMStableData.validate_persistence(value, path)
	if not checked.ok:
		return {"ok": false, "code": "feedback.stable_value_invalid", "reason_zh": "反馈持久化值包含不可保存的运行时对象或越界数值。", "errors": checked.errors}
	return {"ok": true, "value": GMStableData.persistence_canonical(value)}

static func failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
