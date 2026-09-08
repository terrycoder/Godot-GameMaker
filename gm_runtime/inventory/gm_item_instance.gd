class_name GMItemInstance
extends RefCounted

## A unique upgrade of a Lot. It keeps a stable history of source references.

const SCHEMA_VERSION := "gm.item_instance.v1"

var instance_id: String = ""
var definition_id: String = ""
var quality: int = 100
var variant: Dictionary = {}
var provenance_id: String = ""
var source_lot_id: String = ""
var history_refs: Array[String] = []
var upgrade_rule_id: String = ""
var upgrade_level: int = 1

func configure(p_instance_id: String, p_definition_id: String, p_quality: int, p_variant: Dictionary, p_provenance_id: String, p_source_lot_id: String, p_history_refs: Array, p_upgrade_rule_id: String = "", p_upgrade_level: int = 1) -> GMItemInstance:
	instance_id = p_instance_id.strip_edges()
	definition_id = p_definition_id.strip_edges()
	quality = p_quality
	variant = p_variant.duplicate(true)
	provenance_id = p_provenance_id.strip_edges()
	source_lot_id = p_source_lot_id.strip_edges()
	history_refs = _unique_strings(p_history_refs)
	upgrade_rule_id = p_upgrade_rule_id.strip_edges()
	upgrade_level = p_upgrade_level
	return self

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not instance_id.begins_with("gm.item.instance."): errors.append("ItemInstance ID 必须使用 gm.item.instance.*。")
	if definition_id.is_empty(): errors.append("ItemInstance 缺少 Definition ID。")
	if quality < 0 or quality > 100: errors.append("ItemInstance 质量必须在0到100之间。")
	if provenance_id.is_empty(): errors.append("ItemInstance 必须引用 Provenance。")
	if history_refs.is_empty(): errors.append("ItemInstance 必须保留历史引用。")
	if source_lot_id.is_empty(): errors.append("ItemInstance 必须记录来源Lot。")
	if upgrade_level < 1: errors.append("ItemInstance 升级等级必须大于0。")
	var stable := GMStableData.validate(variant)
	if not stable.ok: errors.append_array(stable.errors)
	return {"ok": errors.is_empty(), "code": "item_instance.valid" if errors.is_empty() else "item_instance.invalid", "errors": errors}

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"instance_id": instance_id,
		"definition_id": definition_id,
		"quality": quality,
		"variant": variant.duplicate(true),
		"provenance_id": provenance_id,
		"source_lot_id": source_lot_id,
		"history_refs": history_refs.duplicate(),
		"upgrade_rule_id": upgrade_rule_id,
		"upgrade_level": upgrade_level
	}

static func from_dict(value: Dictionary) -> GMItemInstance:
	var result := GMItemInstance.new()
	result.instance_id = str(value.get("instance_id", value.get("id", "")))
	result.definition_id = str(value.get("definition_id", value.get("item_def", "")))
	result.quality = int(value.get("quality", 100))
	result.variant = value.get("variant", {}).duplicate(true) if value.get("variant", {}) is Dictionary else {}
	result.provenance_id = str(value.get("provenance_id", ""))
	result.source_lot_id = str(value.get("source_lot_id", ""))
	result.history_refs = _unique_strings(value.get("history_refs", value.get("event_history", [])))
	result.upgrade_rule_id = str(value.get("upgrade_rule_id", value.get("instance_reason", "")))
	result.upgrade_level = int(value.get("upgrade_level", 1))
	return result

static func from_lot(lot: GMItemLot, p_instance_id: String, p_fact_id: String, p_rule_id: String = "gm.item.upgrade") -> GMItemInstance:
	var history: Array = [lot.lot_id, lot.provenance_id, lot.source_fact_id, p_fact_id]
	return GMItemInstance.new().configure(p_instance_id, lot.definition_id, lot.quality, lot.variant, lot.provenance_id, lot.lot_id, history, p_rule_id, 1)

func can_upgrade() -> Dictionary:
	if upgrade_level >= 1: return {"ok": false, "code": "item_instance.already_upgraded", "reason_zh": "唯一实例不能重复升级。"}
	return {"ok": true}

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
