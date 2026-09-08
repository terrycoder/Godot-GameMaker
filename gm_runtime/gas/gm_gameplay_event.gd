class_name GMGameplayEvent
extends RefCounted

## GameplayEvent 是统一事件数据，不把 Godot signal 当成全局事件事实源。

var event_tag: String = ""
var event_id: String = ""
var instigator: Object
var target: Object
var payload: Dictionary = {}
var payload_schema: Dictionary = {}
var context: Dictionary = {}
var source: String = ""
var timestamp_usec: int = 0
var dispatch_depth: int = 0
var dispatch_id: String = ""

func _init(tag_value: String = "", p_instigator: Object = null, p_target: Object = null, p_payload: Dictionary = {}, p_source: String = "", p_context: Dictionary = {}, p_schema: Dictionary = {}) -> void:
	event_tag = GMGameplayTag.normalize(tag_value)
	event_id = event_tag
	instigator = p_instigator
	target = p_target
	payload = p_payload.duplicate(true)
	source = p_source
	if p_schema.is_empty() and p_context.has("payload_schema"):
		payload_schema = p_context.get("payload_schema", {}).duplicate(true)
		context = p_context.duplicate(true)
		context.erase("payload_schema")
	else:
		context = p_context.duplicate(true)
		payload_schema = p_schema.duplicate(true)
	timestamp_usec = Time.get_ticks_usec()
	dispatch_id = "gm.event.dispatch.%d" % timestamp_usec

func validate() -> Dictionary:
	if event_tag.is_empty():
		return {"ok": false, "code": "event.id_missing", "reason_zh": "Gameplay Event 缺少稳定事件 ID。"}
	if not (event_tag.begins_with("gm.event.") or event_tag.contains(".event.")):
		return {"ok": false, "code": "event.id_invalid", "reason_zh": "Gameplay Event ID 必须使用事件命名空间：%s" % event_tag}
	var schema_result := validate_payload(payload_schema)
	return schema_result

func validate_payload(schema: Dictionary) -> Dictionary:
	if schema.is_empty(): return {"ok": true}
	var required: Dictionary = schema.get("required", schema)
	var optional: Dictionary = schema.get("optional", {})
	for key in required:
		if not payload.has(key):
			return {"ok": false, "code": "event.payload_missing", "reason_zh": "事件载荷缺少字段：%s" % key, "field": key}
		var type_check := _matches_type(payload[key], required[key])
		if not type_check:
			return {"ok": false, "code": "event.payload_type_invalid", "reason_zh": "事件载荷字段类型错误：%s" % key, "field": key, "expected": required[key], "actual": type_string(typeof(payload[key]))}
	for key in optional:
		if payload.has(key) and not _matches_type(payload[key], optional[key]):
			return {"ok": false, "code": "event.payload_type_invalid", "reason_zh": "事件可选载荷字段类型错误：%s" % key, "field": key, "expected": optional[key], "actual": type_string(typeof(payload[key]))}
	return {"ok": true, "schema": schema.duplicate(true)}

func matches_tag(query: String, include_children: bool = true) -> bool:
	var normalized := GMGameplayTag.normalize(query)
	return event_tag == normalized or (include_children and event_tag.begins_with(normalized + "."))

func to_dict() -> Dictionary:
	return {
		"event_id": event_id,
		"event_tag": event_tag,
		"source": source,
		"payload": payload.duplicate(true),
		"payload_schema": payload_schema.duplicate(true),
		"context": context.duplicate(true),
		"instigator_id": instigator.get_instance_id() if is_instance_valid(instigator) else 0,
		"target_id": target.get_instance_id() if is_instance_valid(target) else 0,
		"timestamp_usec": timestamp_usec,
		"dispatch_depth": dispatch_depth,
		"dispatch_id": dispatch_id,
	}

func set_dispatch_depth(value: int) -> GMGameplayEvent:
	dispatch_depth = value
	return self

func type_string(kind: int) -> String:
	match kind:
		TYPE_NIL: return "nil"
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_VECTOR2: return "Vector2"
		TYPE_DICTIONARY: return "Dictionary"
		TYPE_ARRAY: return "Array"
		_: return str(kind)

func _matches_type(value: Variant, expected: Variant) -> bool:
	if expected is int:
		return typeof(value) == int(expected)
	var expected_name := str(expected).to_lower()
	match expected_name:
		"any", "variant": return true
		"nil", "null": return value == null
		"bool", "boolean": return typeof(value) == TYPE_BOOL
		"int", "integer": return typeof(value) == TYPE_INT
		"float", "number": return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT
		"string": return typeof(value) == TYPE_STRING
		"vector2": return typeof(value) == TYPE_VECTOR2
		"dictionary", "map": return typeof(value) == TYPE_DICTIONARY
		"array", "list": return typeof(value) == TYPE_ARRAY
		_: return true

