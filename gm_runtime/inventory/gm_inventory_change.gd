class_name GMInventoryChange
extends RefCounted

## Domain-visible inventory delta, always paired with one committed FactEvent.

const SCHEMA_VERSION := "gm.inventory_change.v1"

var change_id: String = ""
var fact_event_id: String = ""
var transaction_id: String = ""
var causal_chain_id: String = ""
var idempotency_key: String = ""
var operation: String = ""
var item_kind: String = ""
var item_id: String = ""
var quantity_delta: int = 0
var source_container_id: String = ""
var target_container_id: String = ""
var owner_before: String = ""
var owner_after: String = ""
var holder_before: String = ""
var holder_after: String = ""
var container_before: String = ""
var container_after: String = ""
var provenance_id: String = ""
var quantity_before: int = 0
var quantity_after: int = 0
var reason_zh: String = ""
var metadata: Dictionary = {}

func configure(p_change_id: String, p_fact_event_id: String, p_transaction_id: String, p_chain_id: String, p_idempotency_key: String, p_operation: String, p_item_kind: String, p_item_id: String, p_quantity_delta: int, p_source_container_id: String, p_target_container_id: String, p_owner_before: String, p_owner_after: String, p_holder_before: String, p_holder_after: String, p_container_before: String, p_container_after: String, p_provenance_id: String, p_quantity_before: int, p_quantity_after: int, p_reason_zh: String, p_metadata: Dictionary = {}) -> GMInventoryChange:
	change_id = p_change_id
	fact_event_id = p_fact_event_id
	transaction_id = p_transaction_id
	causal_chain_id = p_chain_id
	idempotency_key = p_idempotency_key
	operation = p_operation
	item_kind = p_item_kind
	item_id = p_item_id
	quantity_delta = p_quantity_delta
	source_container_id = p_source_container_id
	target_container_id = p_target_container_id
	owner_before = p_owner_before
	owner_after = p_owner_after
	holder_before = p_holder_before
	holder_after = p_holder_after
	container_before = p_container_before
	container_after = p_container_after
	provenance_id = p_provenance_id
	quantity_before = p_quantity_before
	quantity_after = p_quantity_after
	reason_zh = p_reason_zh
	metadata = p_metadata.duplicate(true)
	return self

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not change_id.begins_with("gm.inventory.change."): errors.append("InventoryChange ID 无效。")
	if not fact_event_id.begins_with("gm.fact."): errors.append("InventoryChange 必须回指 FactEvent。")
	if transaction_id.is_empty() or not causal_chain_id.begins_with("gm.causal.chain."): errors.append("InventoryChange 缺少事务或因果链。")
	if idempotency_key.is_empty() or operation.is_empty(): errors.append("InventoryChange 缺少幂等键或操作。")
	if not ["lot", "instance"].has(item_kind) or item_id.is_empty(): errors.append("InventoryChange 物品引用无效。")
	if quantity_delta == 0 and owner_before == owner_after and holder_before == holder_after and container_before == container_after:
		errors.append("InventoryChange 必须包含数量、Owner、Holder或Container变化。")
	if target_container_id.is_empty() and source_container_id.is_empty(): errors.append("InventoryChange 至少需要一个容器。")
	if provenance_id.is_empty(): errors.append("InventoryChange 必须保留Provenance引用。")
	if quantity_delta != quantity_after - quantity_before: errors.append("InventoryChange quantity_delta 必须等于 quantity_after - quantity_before。")
	var stable := GMStableData.validate(metadata)
	if not stable.ok: errors.append_array(stable.errors)
	return {"ok": errors.is_empty(), "code": "inventory_change.valid" if errors.is_empty() else "inventory_change.invalid", "errors": errors}

func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "change_id": change_id, "fact_event_id": fact_event_id, "transaction_id": transaction_id, "causal_chain_id": causal_chain_id, "idempotency_key": idempotency_key, "operation": operation, "item_kind": item_kind, "item_id": item_id, "quantity_delta": quantity_delta, "source_container_id": source_container_id, "target_container_id": target_container_id, "owner_before": owner_before, "owner_after": owner_after, "holder_before": holder_before, "holder_after": holder_after, "container_before": container_before, "container_after": container_after, "provenance_id": provenance_id, "quantity_before": quantity_before, "quantity_after": quantity_after, "reason_zh": reason_zh, "metadata": metadata.duplicate(true)}

static func from_dict(value: Dictionary) -> GMInventoryChange:
	var result := GMInventoryChange.new()
	for field in ["change_id", "fact_event_id", "transaction_id", "causal_chain_id", "idempotency_key", "operation", "item_kind", "item_id", "source_container_id", "target_container_id", "owner_before", "owner_after", "holder_before", "holder_after", "container_before", "container_after", "provenance_id", "reason_zh"]:
		result.set(field, str(value.get(field, "")))
	for field in ["quantity_delta", "quantity_before", "quantity_after"]: result.set(field, int(value.get(field, 0)))
	result.metadata = value.get("metadata", {}).duplicate(true) if value.get("metadata", {}) is Dictionary else {}
	return result
