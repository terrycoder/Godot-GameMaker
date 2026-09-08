class_name GMP21Contract
extends RefCounted

## Shared, dependency-light validation for the P21 public contracts.
## Product state lives in P16/P19/P20/GAS; this helper only normalizes values.

const DIALOGUE_SCHEMA_VERSION := "gm.p21.dialogue.v1"
const DIALOGUE_NODE_SCHEMA_VERSION := "gm.p21.dialogue.node.v1"
const DIALOGUE_CHOICE_SCHEMA_VERSION := "gm.p21.dialogue.choice.v1"
const INTERACTION_REQUEST_SCHEMA_VERSION := "gm.p21.interaction.request.v1"
const INTERACTION_RESULT_SCHEMA_VERSION := "gm.p21.interaction.result.v1"
const SHOP_DEFINITION_SCHEMA_VERSION := "gm.p21.shop.definition.v1"
const SHOP_QUOTE_SCHEMA_VERSION := "gm.p21.shop.quote.v1"
const SHOP_ORDER_SCHEMA_VERSION := "gm.p21.shop.order.v1"
const TASK_PROJECTION_SCHEMA_VERSION := "gm.p21.task.projection.v1"
const INTERACTION_KINDS := ["ability", "task", "transaction", "process"]
const INTERACTION_STATUSES := ["accepted", "committed", "blocked", "rejected"]
const SHOP_SIDES := ["buy", "sell"]

static func stable_id(value: Variant, allow_empty: bool = false) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text := str(value)
	if allow_empty and text.is_empty():
		return true
	if text.is_empty() or text != text.strip_edges() or text.length() > 192:
		return false
	for index in text.length():
		var code := text.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code in [46, 95, 45]):
			return false
	return true

static func exact(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field in fields:
		if not value.has(field):
			return false
	return true

static func pure(value: Variant, path: String = "$") -> Dictionary:
	var checked := GMStableData.validate_persistence(value, path)
	if checked.ok:
		return {"ok": true, "value": GMStableData.clone(value)}
	return {"ok": false, "code": "p21.pure_data_invalid", "reason_zh": "P21合同只能携带可持久化纯数据。", "errors": checked.errors}

static func normalize_json(text: String, code: String = "p21.json_invalid") -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return failure(code, "P21 JSON合同无效。", {"line": parser.get_error_line(), "message": parser.get_error_message()})
	var value: Variant = GMStableData.persistence_canonical(parser.data)
	if not value is Dictionary:
		return failure(code, "P21 JSON合同必须是对象。")
	return {"ok": true, "value": value}

static func public_identity(value: Variant) -> Variant:
	var checked := pure(value)
	if checked.ok:
		return GMStableData.persistence_canonical(checked.value)
	return _safe_public_identity(value)

static func _safe_public_identity(value: Variant) -> Variant:
	if value is Dictionary:
		var rows: Array = []
		for key in value.keys():
			var key_data := {"key_type": typeof(key), "key": str(key) if key is String else ""}
			rows.append({"key": key_data, "value": _safe_public_identity(value[key])})
		rows.sort_custom(func(left: Dictionary, right: Dictionary): return JSON.stringify(left.key) < JSON.stringify(right.key))
		return {"type": "dictionary", "entries": rows}
	if value is Array:
		var rows: Array = []
		for item in value:
			rows.append(_safe_public_identity(item))
		return {"type": "array", "items": rows}
	match typeof(value):
		TYPE_NIL: return {"type": "nil"}
		TYPE_BOOL: return {"type": "bool", "value": bool(value)}
		TYPE_INT:
			return {"type": "int", "value": int(value)} if abs(int(value)) <= GMStableData.JSON_SAFE_INTEGER_MAX else {"type": "int_out_of_range"}
		TYPE_FLOAT:
			if not is_finite(float(value)): return {"type": "float_non_finite"}
			return {"type": "float", "value": float(value)}
		TYPE_STRING: return {"type": "string", "value": str(value)}
		_: return {"type": "unsupported", "value_type": typeof(value)}

static func failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh, "error_zh": reason_zh}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result

static func typed_ref(value: Variant, allow_empty: bool = false) -> bool:
	if not value is Dictionary:
		return false
	if value.size() != 2 or not value.has("type") or not value.has("id"):
		return false
	if not stable_id(value.get("type"), allow_empty) or not stable_id(value.get("id"), allow_empty):
		return false
	return not str(value.get("type", "")).to_lower().contains("node")

static func target_ref(value: Variant, allow_empty: bool = false) -> Dictionary:
	if value is String:
		if allow_empty and str(value).is_empty():
			return {"ok": true, "value": ""}
		if not stable_id(value):
			return failure("p21.target_ref_invalid", "目标引用必须是稳定ID。")
		return {"ok": true, "value": str(value)}
	if value is GMSpatialTargetRef:
		var spatial_value: Dictionary = value.to_native()
		var spatial_check := GMSpatialTargetRef.from_native(spatial_value)
		if not spatial_check.ok:
			return failure("p21.target_ref_invalid", "空间目标引用未通过 GMSpatialTargetRef 校验。", spatial_check)
		return {"ok": true, "value": spatial_check.value}
	if typed_ref(value, allow_empty):
		return {"ok": true, "value": value.duplicate(true)}
	if value is Dictionary and value.has("schema_version"):
		var spatial := GMSpatialTargetRef.from_native(value)
		if spatial.ok:
			return {"ok": true, "value": spatial.value}
	return failure("p21.target_ref_invalid", "目标引用只能是稳定ID、稳定类型+ID或 GMSpatialTargetRef。")

static func stable_target_text(value: Variant) -> String:
	var normalized := target_ref(value, true)
	if not normalized.ok:
		return ""
	var target: Variant = normalized.value
	return GMStableData.persistence_canonical_json(target)

static func digest(value: Variant) -> String:
	return GMStableData.digest(value)

static func same_value(left: Variant, right: Variant) -> bool:
	return GMStableData.canonical_json(left) == GMStableData.canonical_json(right)

static func positive_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) > 0 and int(value) <= GMStableData.JSON_SAFE_INTEGER_MAX

static func nonnegative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= GMStableData.JSON_SAFE_INTEGER_MAX
