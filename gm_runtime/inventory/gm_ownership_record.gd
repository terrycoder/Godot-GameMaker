class_name GMOwnershipRecord
extends RefCounted

## Owner, current holder and physical container are three independent facts.

const SCHEMA_VERSION := "gm.ownership_record.v2"
const ID_DOMAIN := "gm.inventory.ownership.identity.v2"
const CUSTODY_TYPES := ["owned", "stored", "borrowed", "dropped", "entrusted", "consigned", "world"]

var ownership_id: String = ""
var item_kind: String = ""
var item_id: String = ""
var owner_id: String = ""
var holder_id: String = ""
var container_id: String = ""
var custody_type: String = "owned"
var history_fact_ids: Array[String] = []
var created_fact_id: String = ""
var updated_fact_id: String = ""

func configure(p_ownership_id: String, p_item_kind: String, p_item_id: String, p_owner_id: String, p_holder_id: String, p_container_id: String, p_custody_type: String, p_created_fact_id: String, p_history_fact_ids: Array = [], p_updated_fact_id: String = "") -> GMOwnershipRecord:
	ownership_id = p_ownership_id.strip_edges()
	item_kind = p_item_kind.strip_edges()
	# item_id is identity material. Preserve its exact Unicode/code-point and
	# whitespace spelling; validation decides whether the referenced item exists.
	item_id = p_item_id
	owner_id = p_owner_id.strip_edges()
	holder_id = p_holder_id.strip_edges()
	container_id = p_container_id.strip_edges()
	custody_type = p_custody_type.strip_edges()
	created_fact_id = p_created_fact_id.strip_edges()
	history_fact_ids = _unique_strings(p_history_fact_ids)
	updated_fact_id = p_updated_fact_id.strip_edges() if not p_updated_fact_id.is_empty() else created_fact_id
	return self

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not ownership_id.begins_with("gm.ownership."): errors.append("Ownership ID 必须使用 gm.ownership.*。")
	if not ["lot", "instance"].has(item_kind): errors.append("Ownership item_kind 必须是 lot 或 instance。")
	if item_id.is_empty(): errors.append("Ownership 缺少物品身份。")
	if not _stable_id(owner_id): errors.append("Ownership owner_id 必须是稳定身份。")
	if not _stable_id(holder_id): errors.append("Ownership holder_id 必须是稳定身份。")
	if not container_id.begins_with("gm.container."): errors.append("Ownership container_id 必须引用 InventoryContainer。")
	if not CUSTODY_TYPES.has(custody_type): errors.append("未知 custody_type：%s" % custody_type)
	if not created_fact_id.begins_with("gm.fact."): errors.append("Ownership 必须记录创建 FactEvent。")
	if not updated_fact_id.begins_with("gm.fact."): errors.append("Ownership 必须记录最近更新 FactEvent。")
	if history_fact_ids.is_empty(): errors.append("Ownership 必须保留转移 Fact 历史。")
	for fact_id in history_fact_ids:
		if not str(fact_id).begins_with("gm.fact."): errors.append("Ownership 历史包含无效 Fact：%s" % str(fact_id))
	return {"ok": errors.is_empty(), "code": "ownership.valid" if errors.is_empty() else "ownership.invalid", "errors": errors}

func transfer(p_new_owner_id: String, p_new_holder_id: String, p_new_container_id: String, p_new_custody_type: String, p_fact_id: String) -> Dictionary:
	var next := GMOwnershipRecord.new().configure(ownership_id, item_kind, item_id, p_new_owner_id, p_new_holder_id, p_new_container_id, p_new_custody_type, created_fact_id, history_fact_ids + [p_fact_id], p_fact_id)
	var check := next.validate()
	return {"ok": check.ok, "record": next.to_dict(), "validation": check}

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"ownership_id": ownership_id,
		"item_kind": item_kind,
		"item_id": item_id,
		"owner_id": owner_id,
		"holder_id": holder_id,
		"container_id": container_id,
		"custody_type": custody_type,
		"history_fact_ids": history_fact_ids.duplicate(),
		"created_fact_id": created_fact_id,
		"updated_fact_id": updated_fact_id
	}

static func from_dict(value: Dictionary) -> GMOwnershipRecord:
	var result := GMOwnershipRecord.new()
	result.ownership_id = str(value.get("ownership_id", value.get("id", "")))
	result.item_kind = str(value.get("item_kind", value.get("item_ref", {}).get("kind", "") if value.get("item_ref", {}) is Dictionary else ""))
	result.item_id = str(value.get("item_id", value.get("item_ref", {}).get("id", "") if value.get("item_ref", {}) is Dictionary else ""))
	result.owner_id = str(value.get("owner_id", value.get("legal_owner", "")))
	result.holder_id = str(value.get("holder_id", value.get("holder", "")))
	result.container_id = str(value.get("container_id", value.get("container", "")))
	result.custody_type = str(value.get("custody_type", "owned"))
	result.history_fact_ids = _unique_strings(value.get("history_fact_ids", value.get("transfer_history", [])))
	result.created_fact_id = str(value.get("created_fact_id", value.get("created_by_event", "")))
	result.updated_fact_id = str(value.get("updated_fact_id", value.get("updated_by_event", result.created_fact_id)))
	return result

static func make_id(item_kind: String, item_id: String) -> String:
	var kind := item_kind.strip_edges()
	var kind_bytes := kind.to_utf8_buffer()
	var item_bytes := item_id.to_utf8_buffer()
	var material := "%s|%d:%s|%d:%s" % [ID_DOMAIN, kind_bytes.size(), kind, item_bytes.size(), item_id]
	return "gm.ownership.v2.%s" % material.sha256_text()

static func legacy_id(item_kind: String, item_id: String) -> String:
	return "gm.ownership.%s.%s" % [item_kind.strip_edges(), _slug(item_id)]

static func identity_contract_matches(value: Dictionary, expected_kind: String, expected_item_id: String) -> bool:
	return str(value.get("item_kind", "")) == expected_kind and str(value.get("item_id", "")) == expected_item_id

static func _stable_id(value: String) -> bool:
	return not value.strip_edges().is_empty() and not value.contains(" ") and not value.contains("NodePath") and not value.contains("res://") and not value.contains("user://")

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in raw.length():
		var code := raw.unicode_at(index)
		result += raw.substr(index, 1) if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45 else "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_") if not result.is_empty() else "item"

static func _unique_strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	var values: Array = value if value is Array else []
	var seen: Dictionary = {}
	for item in values:
		var text := str(item)
		if text.is_empty() or seen.has(text): continue
		seen[text] = true
		result.append(text)
	return result
