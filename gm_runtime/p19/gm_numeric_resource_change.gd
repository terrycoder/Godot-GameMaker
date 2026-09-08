class_name GMNumericResourceChange
extends RefCounted

## Persisted numeric account delta paired with the Coordinator's FactEvent.

const SCHEMA_VERSION := "gm.numeric_resource_change.v1"

var change_id: String = ""
var fact_event_id: String = ""
var transaction_id: String = ""
var causal_chain_id: String = ""
var idempotency_key: String = ""
var operation: String = ""
var account_id: String = ""
var resource_id: String = ""
var unit_id: String = ""
var delta: int = 0
var balance_before: int = 0
var balance_after: int = 0
var owner_id: String = ""
var holder_id: String = ""
var reason_zh: String = ""
var metadata: Dictionary = {}

func configure(p_change_id: String, p_fact_event_id: String, p_transaction_id: String, p_chain_id: String, p_idempotency_key: String, p_operation: String, p_account_id: String, p_resource_id: String, p_unit_id: String, p_delta: int, p_before: int, p_after: int, p_owner_id: String, p_holder_id: String, p_reason_zh: String, p_metadata: Dictionary = {}) -> GMNumericResourceChange:
	change_id = p_change_id.strip_edges()
	fact_event_id = p_fact_event_id.strip_edges()
	transaction_id = p_transaction_id.strip_edges()
	causal_chain_id = p_chain_id.strip_edges()
	idempotency_key = p_idempotency_key
	operation = p_operation.strip_edges()
	account_id = p_account_id.strip_edges()
	resource_id = p_resource_id.strip_edges()
	unit_id = p_unit_id.strip_edges()
	delta = p_delta
	balance_before = p_before
	balance_after = p_after
	owner_id = p_owner_id.strip_edges()
	holder_id = p_holder_id.strip_edges()
	reason_zh = p_reason_zh
	metadata = p_metadata.duplicate(true)
	return self

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not change_id.begins_with("gm.numeric.change."): errors.append("NumericResourceChange ID 无效。")
	if not fact_event_id.begins_with("gm.fact."): errors.append("NumericResourceChange 必须回指 FactEvent。")
	if transaction_id.is_empty() or not causal_chain_id.begins_with("gm.causal.chain."): errors.append("NumericResourceChange 缺少事务或因果链。")
	if idempotency_key.is_empty() or operation.is_empty(): errors.append("NumericResourceChange 缺少幂等键或操作。")
	if not account_id.begins_with("gm.resource.account."): errors.append("NumericResourceChange account_id 无效。")
	if not resource_id.begins_with("gm.resource.") or not unit_id.begins_with("gm.unit."): errors.append("NumericResourceChange Resource 或单位引用无效。")
	if delta == 0 or balance_after - balance_before != delta: errors.append("NumericResourceChange delta 必须等于余额前后差。")
	if balance_before < 0 or balance_after < 0: errors.append("NumericResourceChange 余额不能为负数。")
	if owner_id.is_empty() or holder_id.is_empty(): errors.append("NumericResourceChange 必须保留 Owner 与 Holder。")
	if reason_zh.is_empty(): errors.append("NumericResourceChange 必须说明变化原因。")
	var stable := GMStableData.validate(metadata)
	if not stable.ok: errors.append_array(stable.errors)
	return {"ok": errors.is_empty(), "code": "numeric_resource_change.valid" if errors.is_empty() else "numeric_resource_change.invalid", "errors": errors}

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"change_id": change_id,
		"fact_event_id": fact_event_id,
		"transaction_id": transaction_id,
		"causal_chain_id": causal_chain_id,
		"idempotency_key": idempotency_key,
		"operation": operation,
		"account_id": account_id,
		"resource_id": resource_id,
		"unit_id": unit_id,
		"delta": delta,
		"balance_before": balance_before,
		"balance_after": balance_after,
		"owner_id": owner_id,
		"holder_id": holder_id,
		"reason_zh": reason_zh,
		"metadata": metadata.duplicate(true),
	}

static func from_dict(value: Dictionary) -> GMNumericResourceChange:
	var result := GMNumericResourceChange.new()
	for field in ["change_id", "fact_event_id", "transaction_id", "causal_chain_id", "operation", "account_id", "resource_id", "unit_id", "owner_id", "holder_id", "reason_zh"]:
		result.set(field, str(value.get(field, "")))
	result.idempotency_key = str(value.get("idempotency_key", ""))
	for field in ["delta", "balance_before", "balance_after"]:
		result.set(field, int(value.get(field, 0)))
	result.metadata = value.get("metadata", {}).duplicate(true) if value.get("metadata", {}) is Dictionary else {}
	return result

static func make_id(fact_event_id: String, account_id: String, sequence: int) -> String:
		var material := "%s|%s|%d" % [fact_event_id, account_id, maxi(sequence, 1)]
		return "gm.numeric.change.%s.%02d" % [material.sha256_text(), maxi(sequence, 1)]
