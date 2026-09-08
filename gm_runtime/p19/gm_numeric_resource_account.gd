class_name GMNumericResourceAccount
extends RefCounted

## Mutable numeric balance owned by one holder. Balance and capacity are exact integers.

const SCHEMA_VERSION := "gm.numeric_resource_account.v1"

var account_id: String = ""
var resource_id: String = ""
var owner_id: String = ""
var holder_id: String = ""
var balance: int = 0
var capacity: int = -1
var account_version: int = 0
var last_fact_id: String = ""

func configure(p_account_id: String, p_resource_id: String, p_owner_id: String, p_holder_id: String, p_balance: int = 0, p_capacity: int = -1, p_account_version: int = 0, p_last_fact_id: String = "") -> GMNumericResourceAccount:
	account_id = p_account_id.strip_edges()
	resource_id = p_resource_id.strip_edges()
	owner_id = p_owner_id.strip_edges()
	holder_id = p_holder_id.strip_edges()
	balance = p_balance
	capacity = p_capacity
	account_version = p_account_version
	last_fact_id = p_last_fact_id.strip_edges()
	return self

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not _stable_id(account_id) or not account_id.begins_with("gm.resource.account."):
		errors.append("Numeric Resource Account ID 必须使用 gm.resource.account.*。")
	if not _stable_id(resource_id) or not resource_id.begins_with("gm.resource."):
		errors.append("Numeric Resource Account 缺少有效 Resource ID。")
	if not _stable_id(owner_id): errors.append("Numeric Resource Account 必须明确 owner_id。")
	if not _stable_id(holder_id): errors.append("Numeric Resource Account 必须明确 holder_id。")
	if balance < 0: errors.append("Numeric Resource Account balance 不能为负数。")
	if capacity == 0 or capacity < -1: errors.append("Numeric Resource Account capacity 必须是-1或正整数。")
	if capacity >= 0 and balance > capacity: errors.append("Numeric Resource Account balance 不能超过 capacity。")
	if account_version < 0 or account_version > GMStableData.JSON_SAFE_INTEGER_MAX:
		errors.append("Numeric Resource Account account_version 超出安全范围。")
	if not last_fact_id.is_empty() and not last_fact_id.begins_with("gm.fact."):
		errors.append("Numeric Resource Account last_fact_id 必须引用 gm.fact.*。")
	return {"ok": errors.is_empty(), "code": "numeric_resource_account.valid" if errors.is_empty() else "numeric_resource_account.invalid", "errors": errors}

func can_apply_delta(delta: int, minimum_value: int = 0) -> Dictionary:
	if delta == 0: return {"ok": false, "code": "numeric_resource.delta_zero", "reason_zh": "数值资源变化不能为零。"}
	var next_balance := balance + delta
	if next_balance < minimum_value:
		return {"ok": false, "code": "numeric_resource.balance_insufficient", "reason_zh": "数值资源余额不足。", "balance": balance, "required": -delta, "minimum": minimum_value}
	if capacity >= 0 and next_balance > capacity:
		return {"ok": false, "code": "numeric_resource.capacity_exceeded", "reason_zh": "数值资源账户容量不足。", "balance": balance, "delta": delta, "capacity": capacity}
	return {"ok": true, "balance_before": balance, "balance_after": next_balance}

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"account_id": account_id,
		"resource_id": resource_id,
		"owner_id": owner_id,
		"holder_id": holder_id,
		"balance": balance,
		"capacity": capacity,
		"account_version": account_version,
		"last_fact_id": last_fact_id,
	}

static func from_dict(value: Dictionary) -> GMNumericResourceAccount:
	var result := GMNumericResourceAccount.new()
	result.account_id = str(value.get("account_id", value.get("id", "")))
	result.resource_id = str(value.get("resource_id", value.get("resource", "")))
	result.owner_id = str(value.get("owner_id", value.get("owner", "")))
	result.holder_id = str(value.get("holder_id", value.get("holder", "")))
	result.balance = int(value.get("balance", value.get("amount", value.get("value", 0))))
	result.capacity = int(value.get("capacity", -1))
	result.account_version = int(value.get("account_version", value.get("version", 0)))
	result.last_fact_id = str(value.get("last_fact_id", ""))
	return result

static func make_id(resource_id: String, owner_id: String, holder_id: String) -> String:
	var material := "gm.numeric_resource.account|%s|%s|%s" % [resource_id, owner_id, holder_id]
	return "gm.resource.account.%s" % material.sha256_text()

static func _stable_id(value: String) -> bool:
	return not value.strip_edges().is_empty() and not value.contains(" ") and not value.contains("\t") and not value.contains("res://") and not value.contains("user://") and not value.begins_with("/")
