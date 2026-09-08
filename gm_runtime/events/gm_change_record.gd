class_name GMChangeRecord
extends RefCounted

## 一条与已提交 FactEvent 一一关联的变更记录。

const SCHEMA_VERSION := "gm.change_record.v1"

var schema_version: String = SCHEMA_VERSION
var change_id: String = ""
var sequence: int = 0
var time: String = ""
var fact_event_id: String = ""
var causal_chain_id: String = ""
var transaction_id: String = ""
var idempotency_key: String = ""
var entity_id: String = ""
var operation: String = ""
var field: String = ""
var before: Variant = null
var after: Variant = null
var metadata: Dictionary = {}

func configure(p_sequence: int, p_fact_event_id: String, p_transaction_id: String, p_idempotency_key: String, p_entity_id: String, p_operation: String, p_field: String, p_before: Variant, p_after: Variant, p_options: Dictionary = {}) -> GMChangeRecord:
	schema_version = SCHEMA_VERSION
	sequence = p_sequence
	fact_event_id = p_fact_event_id
	transaction_id = p_transaction_id
	idempotency_key = p_idempotency_key
	entity_id = p_entity_id
	operation = p_operation
	field = p_field
	before = p_before
	after = p_after
	time = str(p_options.get("time", Time.get_datetime_string_from_system(true)))
	causal_chain_id = str(p_options.get("causal_chain_id", ""))
	var configured_change_id := str(p_options.get("change_id", ""))
	change_id = configured_change_id if not configured_change_id.is_empty() else make_change_id(p_fact_event_id, p_idempotency_key, p_sequence)
	metadata = p_options.get("metadata", {}).duplicate(true) if p_options.get("metadata", {}) is Dictionary else {}
	return self

static func from_draft(draft: Dictionary, p_sequence: int, p_fact_event_id: String, p_transaction_id: String, p_idempotency_key: String, p_chain_id: String) -> GMChangeRecord:
	var result := GMChangeRecord.new()
	var options := {"causal_chain_id": p_chain_id, "change_id": str(draft.get("change_id", "")), "metadata": draft.get("metadata", {})}
	var draft_time := str(draft.get("time", ""))
	if not draft_time.is_empty(): options["time"] = draft_time
	result.configure(
		p_sequence,
		p_fact_event_id,
		p_transaction_id,
		p_idempotency_key,
		str(draft.get("entity_id", draft.get("target_id", "domain"))),
		str(draft.get("operation", "transaction.commit")),
		str(draft.get("field", "state")),
		draft.get("before", null),
		draft.get("after", draft.get("value", null)),
		options
	)
	return result

static func from_dict(value: Dictionary) -> GMChangeRecord:
	var result := GMChangeRecord.new()
	result.schema_version = str(value.get("schema_version", SCHEMA_VERSION))
	result.change_id = str(value.get("change_id", ""))
	result.sequence = int(value.get("sequence", 0))
	result.time = str(value.get("time", ""))
	result.fact_event_id = str(value.get("fact_event_id", ""))
	result.causal_chain_id = str(value.get("causal_chain_id", ""))
	result.transaction_id = str(value.get("transaction_id", ""))
	result.idempotency_key = str(value.get("idempotency_key", ""))
	result.entity_id = str(value.get("entity_id", ""))
	result.operation = str(value.get("operation", ""))
	result.field = str(value.get("field", ""))
	result.before = value.get("before", null)
	result.after = value.get("after", null)
	result.metadata = value.get("metadata", {}).duplicate(true) if value.get("metadata", {}) is Dictionary else {}
	return result

func validate() -> Dictionary:
	var errors: Array[String] = []
	for field_name in ["change_id", "fact_event_id", "causal_chain_id", "transaction_id", "idempotency_key", "entity_id", "operation", "field", "time"]:
		if str(get(field_name)).strip_edges().is_empty(): errors.append("ChangeRecord %s 不能为空。" % field_name)
	if sequence < 1: errors.append("ChangeRecord sequence 必须大于0。")
	if schema_version != SCHEMA_VERSION: errors.append("ChangeRecord schema_version 不匹配。")
	for identity in [change_id, fact_event_id, causal_chain_id, transaction_id, idempotency_key, entity_id]:
		if identity.contains("NodePath") or identity.begins_with("/") or identity.contains("res://") or identity.contains("user://"):
			errors.append("ChangeRecord 不得使用 NodePath 或文件路径身份。")
	return {"ok": errors.is_empty(), "code": "change.valid" if errors.is_empty() else "change.invalid", "errors": errors}

func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"change_id": change_id,
		"sequence": sequence,
		"time": time,
		"fact_event_id": fact_event_id,
		"causal_chain_id": causal_chain_id,
		"transaction_id": transaction_id,
		"idempotency_key": idempotency_key,
		"entity_id": entity_id,
		"operation": operation,
		"field": field,
		"before": before,
		"after": after,
		"metadata": metadata.duplicate(true)
	}

static func make_change_id(p_fact_event_id: String, p_idempotency_key: String, p_sequence: int) -> String:
	var seed := p_idempotency_key if not p_idempotency_key.is_empty() else p_fact_event_id
	var identity_material := "%s|%s|%d" % [p_fact_event_id, seed, maxi(p_sequence, 1)]
	return "gm.change.v2.%s.%02d" % [identity_material.sha256_text(), maxi(p_sequence, 1)]

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in range(raw.length()):
		var code := raw.unicode_at(index)
		result += raw.substr(index, 1) if ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45) else "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_") if not result.is_empty() else "change"
