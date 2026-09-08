class_name GMDialogueChoice
extends RefCounted

const SCHEMA_VERSION := GMP21Contract.DIALOGUE_CHOICE_SCHEMA_VERSION
const FIELDS := ["schema_version", "choice_id", "display_name_zh", "text_zh", "next_node_id", "order", "condition", "request"]
const CONDITION_FIELDS := ["field", "operator", "value"]
const REQUEST_FIELDS := ["kind", "interaction_id", "payload"]
const CONDITION_OPERATORS := ["equals", "not_equals", "exists", "gte", "lte", "in"]

var schema_version := SCHEMA_VERSION
var choice_id := ""
var display_name_zh := ""
var text_zh := ""
var next_node_id := ""
var order := 0
var condition: Dictionary = {}
var request: Dictionary = {}

func _init(p_choice_id: String = "", p_text_zh: String = "", p_next_node_id: String = "") -> void:
	choice_id = p_choice_id
	display_name_zh = p_text_zh
	text_zh = p_text_zh
	next_node_id = p_next_node_id

func validate() -> Dictionary:
	var value := to_dict()
	if not GMP21Contract.exact(value, FIELDS):
		return GMP21Contract.failure("dialogue.choice_shape_invalid", "DialogueChoice字段集合必须精确匹配。")
	if schema_version != SCHEMA_VERSION or not GMP21Contract.stable_id(choice_id) or display_name_zh.strip_edges().is_empty() or text_zh.strip_edges().is_empty() or not GMP21Contract.stable_id(next_node_id, true) or not GMP21Contract.nonnegative_integer(order):
		return GMP21Contract.failure("dialogue.choice_identity_invalid", "DialogueChoice的版本、稳定ID、中文文案、目标节点或顺序无效。")
	var condition_check := _validate_condition(condition)
	if not condition_check.ok:
		return condition_check
	var request_check := _validate_request(request)
	if not request_check.ok:
		return request_check
	return {"ok": true, "code": "dialogue.choice_valid", "value": value}

func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"choice_id": choice_id,
		"display_name_zh": display_name_zh,
		"text_zh": text_zh,
		"next_node_id": next_node_id,
		"order": order,
		"condition": condition.duplicate(true),
		"request": request.duplicate(true),
	}

func available(context: Dictionary) -> bool:
	var checked := _validate_condition(condition)
	if not checked.ok:
		return false
	if condition.is_empty():
		return true
	var field := str(condition.get("field", ""))
	var present := context.has(field)
	var actual: Variant = context.get(field, null)
	var expected: Variant = condition.get("value", null)
	match str(condition.get("operator", "")):
		"exists": return present == bool(expected)
		"equals": return present and GMP21Contract.same_value(actual, expected)
		"not_equals": return not present or not GMP21Contract.same_value(actual, expected)
		"gte": return present and _number(actual) >= _number(expected)
		"lte": return present and _number(actual) <= _number(expected)
		"in":
			if not expected is Array:
				return false
			for candidate in expected:
				if present and GMP21Contract.same_value(actual, candidate):
					return true
			return false
	return false

func build_interaction_request(source_ref: Variant, target_ref: Variant, idempotency_key: String) -> GMInteractionRequest:
	if request.is_empty():
		return null
	var checked := validate()
	if not checked.ok or not GMP21Contract.stable_id(idempotency_key):
		return null
	var data: Dictionary = request.get("payload", {}).duplicate(true)
	data["choice_id"] = choice_id
	data["dialogue_choice_schema"] = SCHEMA_VERSION
	return GMInteractionRequest.new(str(request.interaction_id), str(request.kind), source_ref, target_ref, data, idempotency_key)

static func from_dict(value: Variant, json_boundary: bool = false) -> GMDialogueChoice:
	if not value is Dictionary or not GMP21Contract.exact(value, FIELDS):
		return null
	if typeof(value.get("schema_version")) != TYPE_STRING or typeof(value.get("choice_id")) != TYPE_STRING or typeof(value.get("display_name_zh")) != TYPE_STRING or typeof(value.get("text_zh")) != TYPE_STRING or typeof(value.get("next_node_id")) != TYPE_STRING or not _integer_value(value.get("order"), json_boundary) or not value.get("condition") is Dictionary or not value.get("request") is Dictionary:
		return null
	var result := GMDialogueChoice.new()
	result.schema_version = str(value.schema_version)
	result.choice_id = str(value.choice_id)
	result.display_name_zh = str(value.display_name_zh)
	result.text_zh = str(value.text_zh)
	result.next_node_id = str(value.next_node_id)
	result.order = int(value.order)
	result.condition = value.condition.duplicate(true)
	result.request = value.request.duplicate(true)
	return result if result.validate().ok else null

static func _integer_value(value: Variant, json_boundary: bool) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= 0 and int(value) <= GMStableData.JSON_SAFE_INTEGER_MAX
	return json_boundary and typeof(value) == TYPE_FLOAT and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= 0.0 and float(value) <= float(GMStableData.JSON_SAFE_INTEGER_MAX)

static func _validate_condition(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return GMP21Contract.failure("dialogue.choice_condition_invalid", "DialogueChoice condition必须是纯Dictionary。")
	if value.is_empty():
		return {"ok": true}
	if not GMP21Contract.exact(value, CONDITION_FIELDS) or typeof(value.field) != TYPE_STRING or not GMP21Contract.stable_id(value.field) or typeof(value.operator) != TYPE_STRING or value.operator not in CONDITION_OPERATORS:
		return GMP21Contract.failure("dialogue.choice_condition_invalid", "DialogueChoice condition必须使用精确的field/operator/value合同。")
	if value.operator == "exists" and typeof(value.value) != TYPE_BOOL:
		return GMP21Contract.failure("dialogue.choice_condition_invalid", "exists条件的value必须是布尔值。")
	var pure_check := GMP21Contract.pure(value, "$.condition")
	return pure_check

static func _validate_request(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return GMP21Contract.failure("dialogue.choice_request_invalid", "DialogueChoice request必须是纯Dictionary。")
	if value.is_empty():
		return {"ok": true}
	if not GMP21Contract.exact(value, REQUEST_FIELDS) or typeof(value.kind) != TYPE_STRING or value.kind not in GMP21Contract.INTERACTION_KINDS or typeof(value.interaction_id) != TYPE_STRING or not GMP21Contract.stable_id(value.interaction_id) or not value.payload is Dictionary:
		return GMP21Contract.failure("dialogue.choice_request_invalid", "DialogueChoice request必须声明稳定kind、interaction_id和payload。")
	return GMP21Contract.pure(value, "$.request")

static func _number(value: Variant) -> float:
	return float(value) if value is int or value is float else 0.0

