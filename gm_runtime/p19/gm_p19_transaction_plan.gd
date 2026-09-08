class_name GMP19TransactionPlan
extends RefCounted

## Value plan carried by one existing GMDomainTransaction.

const SCHEMA_VERSION := "gm.p19.transaction_plan.v1"

var transaction_id: String = ""
var idempotency_key: String = ""
var operation: String = ""
var fact_id: String = ""
var participants: Array[String] = []
var inventory_plan: Dictionary = {}
var numeric_plan: Dictionary = {}
var reservation_handles: Array = []
var inputs: Array = []
var outputs: Array = []
var changeset: Array = []
var payload: Dictionary = {}

func configure(p_transaction_id: String, p_idempotency_key: String, p_operation: String, p_fact_id: String) -> GMP19TransactionPlan:
	transaction_id = p_transaction_id
	idempotency_key = p_idempotency_key
	operation = p_operation
	fact_id = p_fact_id
	return self

func add_participant(name: String, participant_plan: Dictionary) -> void:
	if not participants.has(name): participants.append(name)
	if name == "inventory": inventory_plan = participant_plan.duplicate(true)
	if name == "numeric_resource": numeric_plan = participant_plan.duplicate(true)

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"transaction_id": transaction_id,
		"idempotency_key": idempotency_key,
		"operation": operation,
		"fact_id": fact_id,
		"participants": participants.duplicate(),
		"inventory_plan": inventory_plan.duplicate(true),
		"numeric_plan": numeric_plan.duplicate(true),
		"reservation_handles": reservation_handles.duplicate(true),
		"inputs": inputs.duplicate(true),
		"outputs": outputs.duplicate(true),
		"changeset": changeset.duplicate(true),
		"payload": payload.duplicate(true),
	}

func summary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"transaction_id": transaction_id,
		"idempotency_key": idempotency_key,
		"operation": operation,
		"fact_id": fact_id,
		"participants": participants.duplicate(),
		"input_count": inputs.size(),
		"output_count": outputs.size(),
		"change_count": changeset.size(),
	}

func validate() -> Dictionary:
	var errors: Array[String] = []
	if transaction_id.is_empty(): errors.append("P19 TransactionPlan 缺少 transaction_id。")
	if idempotency_key.is_empty(): errors.append("P19 TransactionPlan 缺少 idempotency_key。")
	if operation.is_empty(): errors.append("P19 TransactionPlan 缺少 operation。")
	if not fact_id.begins_with("gm.fact."): errors.append("P19 TransactionPlan fact_id 必须使用 gm.fact.*。")
	if participants.is_empty(): errors.append("P19 TransactionPlan 至少需要一个领域参与者。")
	if not participants.has("inventory") and not participants.has("numeric_resource"):
		errors.append("P19 TransactionPlan 参与者必须来自现有库存或数值资源 Resolver。")
	var stable := GMStableData.validate(to_dict())
	if not stable.ok: errors.append_array(stable.errors)
	return {"ok": errors.is_empty(), "code": "p19.transaction_plan.valid" if errors.is_empty() else "p19.transaction_plan.invalid", "errors": errors}

static func from_dict(value: Dictionary) -> GMP19TransactionPlan:
	var result := GMP19TransactionPlan.new()
	result.transaction_id = str(value.get("transaction_id", ""))
	result.idempotency_key = str(value.get("idempotency_key", ""))
	result.operation = str(value.get("operation", ""))
	result.fact_id = str(value.get("fact_id", ""))
	var participants_value: Variant = value.get("participants", [])
	if participants_value is Array:
		for item in participants_value: result.participants.append(str(item))
	result.inventory_plan = value.get("inventory_plan", {}).duplicate(true) if value.get("inventory_plan", {}) is Dictionary else {}
	result.numeric_plan = value.get("numeric_plan", {}).duplicate(true) if value.get("numeric_plan", {}) is Dictionary else {}
	result.reservation_handles = value.get("reservation_handles", []).duplicate(true) if value.get("reservation_handles", []) is Array else []
	result.inputs = value.get("inputs", []).duplicate(true) if value.get("inputs", []) is Array else []
	result.outputs = value.get("outputs", []).duplicate(true) if value.get("outputs", []) is Array else []
	result.changeset = value.get("changeset", []).duplicate(true) if value.get("changeset", []) is Array else []
	result.payload = value.get("payload", {}).duplicate(true) if value.get("payload", {}) is Dictionary else {}
	return result
