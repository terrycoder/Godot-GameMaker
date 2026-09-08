class_name GMProvenanceRecord
extends RefCounted

## Source lineage only. Ownership and custody are deliberately separate records.

const SCHEMA_VERSION := "gm.provenance_record.v1"
const SOURCE_KINDS := ["starting", "production", "gathered", "purchased", "converted", "dropped", "split", "merged", "unknown", "simplified"]

var provenance_id: String = ""
var source_fact_id: String = ""
var source_kind: String = "unknown"
var parent_provenance_ids: Array[String] = []
var chain_fact_ids: Array[String] = []
var metadata: Dictionary = {}

func configure(p_id: String, p_source_fact_id: String, p_source_kind: String, p_parents: Array = [], p_chain: Array = [], p_metadata: Dictionary = {}) -> GMProvenanceRecord:
	provenance_id = p_id.strip_edges()
	source_fact_id = p_source_fact_id.strip_edges()
	source_kind = p_source_kind.strip_edges()
	parent_provenance_ids = _unique_strings(p_parents)
	chain_fact_ids = _unique_strings(p_chain)
	metadata = p_metadata.duplicate(true)
	return self

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not _stable_id(provenance_id): errors.append("Provenance 缺少稳定 ID。")
	if not source_fact_id.begins_with("gm.fact."): errors.append("Provenance 必须回指来源 FactEvent。")
	if not SOURCE_KINDS.has(source_kind): errors.append("Provenance 来源类型未注册：%s" % source_kind)
	for parent in parent_provenance_ids:
		if not str(parent).begins_with("gm.provenance."): errors.append("Provenance 父链 ID 无效：%s" % str(parent))
	for fact_id in chain_fact_ids:
		if not str(fact_id).begins_with("gm.fact."): errors.append("Provenance 事实链 ID 无效：%s" % str(fact_id))
	for forbidden in ["owner", "owner_id", "holder", "holder_id", "container", "container_id", "ownership_id"]:
		if metadata.has(forbidden): errors.append("Provenance 不得保存所有权字段：%s" % forbidden)
	var stable := GMStableData.validate(metadata)
	if not stable.ok: errors.append_array(stable.errors)
	return {"ok": errors.is_empty(), "code": "provenance.valid" if errors.is_empty() else "provenance.invalid", "errors": errors}

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"provenance_id": provenance_id,
		"source_fact_id": source_fact_id,
		"source_kind": source_kind,
		"parent_provenance_ids": parent_provenance_ids.duplicate(),
		"chain_fact_ids": chain_fact_ids.duplicate(),
		"metadata": metadata.duplicate(true)
	}

static func from_dict(value: Dictionary) -> GMProvenanceRecord:
	var result := GMProvenanceRecord.new()
	result.provenance_id = str(value.get("provenance_id", value.get("id", "")))
	result.source_fact_id = str(value.get("source_fact_id", value.get("source_event", "")))
	result.source_kind = str(value.get("source_kind", value.get("type", "unknown")))
	result.parent_provenance_ids = _unique_strings(value.get("parent_provenance_ids", []))
	result.chain_fact_ids = _unique_strings(value.get("chain_fact_ids", []))
	result.metadata = value.get("metadata", {}).duplicate(true) if value.get("metadata", {}) is Dictionary else {}
	return result

static func simplified(p_id: String, p_source_fact_id: String, p_source_kind: String) -> GMProvenanceRecord:
	return GMProvenanceRecord.new().configure(p_id, p_source_fact_id, "simplified", [], [], {"source_kind": p_source_kind})

static func _stable_id(value: String) -> bool:
	return not value.strip_edges().is_empty() and not value.contains(" ") and not value.contains("NodePath") and not value.contains("res://") and not value.contains("user://")

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
