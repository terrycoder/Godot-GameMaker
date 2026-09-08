class_name GMFactEventSchema
extends RefCounted

## FactEvent 的机器可读公共 Schema。
##
## Schema 只校验通用身份和因果字段，不理解具体领域 payload。领域 Resolver
## 仍然负责 payload 的业务正确性；这里负责阻止请求、表现或伪造结果被当成事实。

const SCHEMA_ID := "gm.fact_event.v1"
const REQUIRED_FIELDS := [
	"schema_version",
	"event_id",
	"sequence",
	"time",
	"type",
	"actor",
	"targets",
	"inputs",
	"outputs",
	"tags",
	"causes",
	"visibility",
	"source_system",
	"ability_id",
	"ability_instance_id",
	"resolver_id",
	"transaction_id",
	"idempotency_key",
	"payload"
]

static func describe() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"required": REQUIRED_FIELDS.duplicate(),
		"field_types": {
			"schema_version": "string",
			"event_id": "string",
			"sequence": "integer",
			"time": "string_or_integer",
			"type": "string",
			"actor": "string",
			"targets": "array",
			"inputs": "array",
			"outputs": "array",
			"tags": "array",
			"causes": "array",
			"visibility": "object",
			"source_system": "string",
			"ability_id": "string",
			"ability_instance_id": "string",
			"resolver_id": "string",
			"transaction_id": "string",
			"idempotency_key": "string",
			"payload": "object"
		},
		"semantics": {
			"type_prefix": "gm.fact.",
			"append_only": true,
			"gameplay_event_is_not_fact": true
		}
	}

static func validate_record(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		errors.append("FactEvent 必须是 Dictionary 或 GMFactEvent 的序列化结果。")
		return {"ok": false, "code": "fact.schema_not_object", "errors": errors}
	var record: Dictionary = value
	for field in REQUIRED_FIELDS:
		if not record.has(field): errors.append("FactEvent 缺少字段：%s" % field)
	if not errors.is_empty():
		return {"ok": false, "code": "fact.schema_required_missing", "errors": errors}
	if str(record.get("schema_version", "")) != SCHEMA_ID:
		errors.append("FactEvent schema_version 必须为 %s。" % SCHEMA_ID)
	if typeof(record.get("event_id")) != TYPE_STRING or str(record.get("event_id", "")).strip_edges().is_empty():
		errors.append("FactEvent event_id 必须是非空稳定字符串。")
	var sequence_value: Variant = record.get("sequence")
	if typeof(sequence_value) != TYPE_INT or int(sequence_value) < 1:
		errors.append("FactEvent sequence 必须是大于0的整数。")
	var time_value: Variant = record.get("time")
	if typeof(time_value) != TYPE_STRING and typeof(time_value) != TYPE_INT:
		errors.append("FactEvent time 必须是时间字符串或整数时间戳。")
	var type_value := str(record.get("type", ""))
	if type_value.is_empty() or not type_value.begins_with("gm.fact."):
		errors.append("FactEvent type 必须使用 gm.fact.* 命名空间。")
	for field in ["actor", "source_system", "ability_id", "ability_instance_id", "resolver_id", "transaction_id", "idempotency_key"]:
		if typeof(record.get(field)) != TYPE_STRING or str(record.get(field, "")).strip_edges().is_empty():
			errors.append("FactEvent %s 必须是非空稳定字符串。" % field)
	for field in ["targets", "inputs", "outputs", "tags", "causes"]:
		if typeof(record.get(field)) != TYPE_ARRAY:
			errors.append("FactEvent %s 必须是数组。" % field)
			continue
		var seen: Dictionary = {}
		for item in record[field]:
			if item is Object:
				errors.append("FactEvent %s 不得保存 Godot 对象引用。" % field)
			var item_key := str(item)
			if typeof(item) != TYPE_STRING:
				errors.append("FactEvent %s 只能保存稳定字符串 ID。" % field)
			if item_key.is_empty():
				errors.append("FactEvent %s 不得包含空身份。" % field)
			if field == "causes" and seen.has(item_key):
				errors.append("FactEvent causes 不得重复：%s" % item_key)
			if field == "causes" and item_key == str(record.get("event_id", "")):
				errors.append("FactEvent causes 不得包含自身 event_id：%s" % item_key)
			seen[item_key] = true
	var visibility: Variant = record.get("visibility")
	if not visibility is Dictionary:
		errors.append("FactEvent visibility 必须是对象。")
	else:
		if typeof(visibility.get("public", false)) != TYPE_BOOL:
			errors.append("FactEvent visibility.public 必须是 bool。")
		if not visibility.get("witnesses", []) is Array:
			errors.append("FactEvent visibility.witnesses 必须是数组。")
		else:
			for witness in visibility.get("witnesses", []):
				if witness is Object or typeof(witness) != TYPE_STRING or str(witness).strip_edges().is_empty():
					errors.append("FactEvent visibility.witnesses 必须是稳定字符串。")
	var payload: Variant = record.get("payload")
	if not payload is Dictionary:
		errors.append("FactEvent payload 必须是对象。")
	for field in ["event_id", "actor", "source_system", "ability_id", "targets", "inputs", "outputs", "tags", "causes", "ability_instance_id", "resolver_id", "transaction_id", "idempotency_key"]:
		var stable_result := validate_stable_value(record.get(field), "FactEvent.%s" % field)
		if not stable_result.ok: errors.append_array(stable_result.errors)
	return {
		"ok": errors.is_empty(),
		"code": "fact.schema_valid" if errors.is_empty() else "fact.schema_invalid",
		"errors": errors,
		"schema": describe()
	}

static func validate_stable_value(value: Variant, field_name: String) -> Dictionary:
	var errors: Array[String] = []
	var values: Array = value if value is Array else [value]
	for item in values:
		if item is Object:
			errors.append("%s 不得保存对象引用。" % field_name)
			continue
		if typeof(item) != TYPE_STRING:
			errors.append("%s 必须是稳定字符串 ID。" % field_name)
			continue
		var text := str(item)
		if text.is_empty(): continue
		if text.contains("NodePath") or text.begins_with("/") or text.contains("res://") or text.contains("user://"):
			errors.append("%s 不得使用 NodePath 或文件路径作为业务身份：%s" % [field_name, text])
	return {"ok": errors.is_empty(), "errors": errors}
