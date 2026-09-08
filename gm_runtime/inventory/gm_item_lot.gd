class_name GMItemLot
extends RefCounted

## A stackable batch. Dynamic ownership/custody remains in GMOwnershipRecord.

const SCHEMA_VERSION := "gm.item_lot.v1"

var lot_id: String = ""
var definition_id: String = ""
var quantity: int = 0
var quality: int = 100
var variant: Dictionary = {}
var tags: PackedStringArray = PackedStringArray()
var provenance_id: String = ""
var source_fact_id: String = ""

func configure(p_lot_id: String, p_definition_id: String, p_quantity: int, p_quality: int, p_variant: Dictionary, p_tags: PackedStringArray, p_provenance_id: String, p_source_fact_id: String) -> GMItemLot:
	lot_id = p_lot_id.strip_edges()
	definition_id = p_definition_id.strip_edges()
	quantity = p_quantity
	quality = p_quality
	variant = p_variant.duplicate(true)
	tags = _unique_strings(p_tags)
	provenance_id = p_provenance_id.strip_edges()
	source_fact_id = p_source_fact_id.strip_edges()
	return self

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not _stable_id(lot_id): errors.append("ItemLot 缺少稳定 lot ID。")
	if definition_id.is_empty(): errors.append("ItemLot 缺少 Definition ID。")
	if quantity <= 0: errors.append("ItemLot 数量必须大于0。")
	if quality < 0 or quality > 100: errors.append("ItemLot 质量必须在0到100之间。")
	if provenance_id.is_empty(): errors.append("ItemLot 必须引用 Provenance。")
	if source_fact_id.is_empty() or not source_fact_id.begins_with("gm.fact."): errors.append("ItemLot 必须记录创建 FactEvent。")
	var variant_check := GMStableData.validate(variant)
	if not variant_check.ok: errors.append_array(variant_check.errors)
	if not _unique(Array(tags)): errors.append("ItemLot 标签不能重复。")
	return {"ok": errors.is_empty(), "code": "item_lot.valid" if errors.is_empty() else "item_lot.invalid", "errors": errors}

func is_valid() -> bool:
	return bool(validate().get("ok", false))

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"lot_id": lot_id,
		"definition_id": definition_id,
		"quantity": quantity,
		"quality": quality,
		"variant": variant.duplicate(true),
		"tags": Array(tags),
		"provenance_id": provenance_id,
		"source_fact_id": source_fact_id
	}

static func from_dict(value: Dictionary) -> GMItemLot:
	var result := GMItemLot.new()
	result.lot_id = str(value.get("lot_id", value.get("id", "")))
	result.definition_id = str(value.get("definition_id", value.get("item_def", "")))
	result.quantity = int(value.get("quantity", 0))
	result.quality = int(value.get("quality", 100))
	result.variant = value.get("variant", {}).duplicate(true) if value.get("variant", {}) is Dictionary else {}
	result.tags = _unique_strings(value.get("tags", []))
	result.provenance_id = str(value.get("provenance_id", ""))
	result.source_fact_id = str(value.get("source_fact_id", value.get("created_fact_id", "")))
	return result

func can_split(split_quantity: int) -> Dictionary:
	var errors: Array[String] = []
	if split_quantity <= 0: errors.append("拆分数量必须大于0。")
	if split_quantity >= quantity: errors.append("拆分必须保留源Lot，不能取走全部数量。")
	return {"ok": errors.is_empty(), "code": "item_lot.split_valid" if errors.is_empty() else "item_lot.split_invalid", "errors": errors, "remaining_quantity": quantity - split_quantity}

func can_merge_with(other: GMItemLot, source_policy: String) -> Dictionary:
	var errors: Array[String] = []
	if other == null: errors.append("合并目标Lot不存在。")
	if other != null:
		if definition_id != other.definition_id: errors.append("不同Definition不能合并。")
		if quality != other.quality: errors.append("质量不同，不能直接合并。")
		if GMStableData.canonical_json(variant) != GMStableData.canonical_json(other.variant): errors.append("变体不同，不能直接合并。")
		if GMStableData.canonical_json(Array(tags)) != GMStableData.canonical_json(Array(other.tags)): errors.append("标签不同，不能直接合并。")
		if source_policy == "same_provenance_only" and provenance_id != other.provenance_id: errors.append("来源策略禁止合并不同Provenance。")
		if not ["same_provenance_only", "allow_different_preserve"].has(source_policy): errors.append("未知来源合并策略：%s" % source_policy)
	return {"ok": errors.is_empty(), "code": "item_lot.merge_valid" if errors.is_empty() else "item_lot.merge_invalid", "errors": errors}

static func _stable_id(value: String) -> bool:
	return not value.strip_edges().is_empty() and not value.contains(" ") and not value.contains("NodePath") and not value.contains("res://") and not value.contains("user://")

static func _unique(value: Array) -> bool:
	var seen: Dictionary = {}
	for item in value:
		var text := str(item)
		if seen.has(text): return false
		seen[text] = true
	return true

static func _unique_strings(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	var values: Array = Array(value) if value is PackedStringArray else value if value is Array else []
	var seen: Dictionary = {}
	for item in values:
		var text := str(item)
		if text.is_empty() or seen.has(text): continue
		seen[text] = true
		result.append(text)
	return result
