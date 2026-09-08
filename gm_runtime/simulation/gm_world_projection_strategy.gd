class_name GMWorldProjectionStrategy
extends RefCounted


const JOURNAL_SCHEMA := "gm.simulation.post_receipt_mutation_journal.v3"
const ENTRY_SCHEMA := "gm.simulation.post_receipt_mutation.v3"
const PROJECTION_FIELDS := ["registry_digest", "registry_versions", "registry_record_digests", "store_revisions", "store_digests", "event_archive_digest", "event_history_id", "event_count", "change_count", "abstract_count", "cue_count", "cue_digest"]


static func project(registry: GMEntityRegistry, event_store: GMEventStore, stores: Dictionary, abstract_commits: Array, cue_projection: Dictionary) -> Dictionary:
	var registry_versions := {}
	var registry_record_digests := {}
	for entity_id in registry.all_entity_ids():
		registry_versions[entity_id] = registry.version_for(entity_id)
		registry_record_digests[entity_id] = GMReceiptEnvelopeAdapter.persistence_digest(registry.get_record(entity_id))
	var store_revisions := {}
	var store_digests := {}
	var store_ids: Array[String] = []
	for store_id in stores.keys(): store_ids.append(str(store_id))
	store_ids.sort()
	for store_id in store_ids:
		var store: GMStore = stores[store_id]
		store_revisions[store_id] = store.persistence_revision
		store_digests[store_id] = GMReceiptEnvelopeAdapter.persistence_digest(store.snapshot())
	var event_snapshot: Dictionary = event_store.snapshot()
	return {
		"registry_digest": GMReceiptEnvelopeAdapter.persistence_digest(registry.snapshot()),
		"registry_versions": registry_versions,
		"registry_record_digests": registry_record_digests,
		"store_revisions": store_revisions,
		"store_digests": store_digests,
		"event_archive_digest": str(event_snapshot.get("archive_digest", "")),
		"event_history_id": str(event_snapshot.get("history_id", "")),
		"event_count": event_store.get_record_count(),
		"change_count": event_store.get_change_record_count(),
		"abstract_count": abstract_commits.size(),
		"cue_count": int(cue_projection.get("cue_count", 0)),
		"cue_digest": str(cue_projection.get("cue_digest", cue_digest([]))),
	}


static func cue_projection(receipt_rows: Array, extra_identity: Dictionary = {}) -> Dictionary:
	var digests: Array = []
	for row_value in receipt_rows:
		if not row_value is Dictionary: continue
		var identity: Variant = row_value.get("identity_projection", {})
		if identity is Dictionary and identity.get("cue_digests", null) is Array:
			for digest_value in identity.cue_digests: digests.append(str(digest_value))
	if not extra_identity.is_empty() and extra_identity.get("cue_digests", null) is Array:
		for digest_value in extra_identity.cue_digests: digests.append(str(digest_value))
	return {"cue_count": digests.size(), "cue_digest": cue_digest(digests), "cue_digests": digests}


static func cue_digest(digests: Array) -> String:
	return GMReceiptEnvelopeAdapter.persistence_digest({"domain": "gm.simulation.cue_projection.v1", "cue_digests": digests})


static func empty_journal(world_id: String, epoch: int) -> Dictionary:
	var journal := {"schema": JOURNAL_SCHEMA, "world_id": world_id, "epoch": epoch, "entry_count": 0, "tail_digest": journal_genesis(world_id, epoch), "entries": []}
	journal["journal_digest"] = journal_digest(journal)
	return journal


static func build_journal(world_id: String, epoch: int, entries: Array) -> Dictionary:
	var journal := {"schema": JOURNAL_SCHEMA, "world_id": world_id, "epoch": epoch, "entry_count": entries.size(), "tail_digest": journal_genesis(world_id, epoch) if entries.is_empty() else str(entries.back().get("record_digest", "")), "entries": GMStableData.clone(entries)}
	journal["journal_digest"] = journal_digest(journal)
	return journal


static func make_journal_entry(world_id: String, epoch: int, journal_sequence: int, base_receipt_sequence: int, base_receipt_id: String, previous_digest: String, component_kind: String, component_id: String, operation: String, before_component: Dictionary, after_component: Dictionary, before_projection: Dictionary, after_projection: Dictionary) -> Dictionary:
	var entry := {
		"schema": ENTRY_SCHEMA,
		"world_id": world_id,
		"epoch": epoch,
		"journal_sequence": journal_sequence,
		"base_receipt_sequence": base_receipt_sequence,
		"base_receipt_id": base_receipt_id,
		"previous_digest": previous_digest,
		"component_kind": component_kind,
		"component_id": component_id,
		"operation": operation,
		"from_revision": _component_revision(component_kind, before_component),
		"to_revision": _component_revision(component_kind, after_component),
		"before_component": GMStableData.clone(before_component),
		"after_component": GMStableData.clone(after_component),
		"before_projection": GMStableData.clone(before_projection),
		"after_projection": GMStableData.clone(after_projection),
	}
	entry["record_digest"] = entry_digest(entry)
	return entry


static func validate(receipt_rows: Array, journal_value: Dictionary, expected_world_id: String, expected_epoch: int, registry: GMEntityRegistry, event_store: GMEventStore, stores: Dictionary, abstract_commits: Array) -> Dictionary:
	var journal_result := _decode_journal(journal_value, receipt_rows, expected_world_id, expected_epoch)
	if not journal_result.ok: return journal_result
	var journal_entries: Array = journal_result.entries
	var entries_by_base: Dictionary = {}
	for entry in journal_entries:
		var base := int(entry.base_receipt_sequence)
		if not entries_by_base.has(base): entries_by_base[base] = []
		entries_by_base[base].append(entry)
	var cumulative_identity_rows: Array = []
	for index in receipt_rows.size():
		var row: Dictionary = receipt_rows[index]
		var before_check := _validate_projection_shape(row.before_state)
		if not before_check.ok: return before_check
		var after_check := _validate_projection_shape(row.after_state)
		if not after_check.ok: return after_check
		if index == 0:
			var empty_cues := cue_projection([])
			if int(row.before_state.cue_count) != 0 or str(row.before_state.cue_digest) != str(empty_cues.cue_digest):
				return _failure("commit.receipt_initial_cue_projection_mismatch", "首条收据前置Cue投影必须为空。")
		else:
			var previous: Dictionary = receipt_rows[index - 1].after_state
			var transitioned := _apply_projection_entries(previous, entries_by_base.get(index, []))
			if not transitioned.ok: return transitioned
			if GMReceiptEnvelopeAdapter.persistence_digest(transitioned.projection) != GMReceiptEnvelopeAdapter.persistence_digest(row.before_state):
				return _failure("commit.receipt_state_chain_mismatch", "收据之间的世界投影没有连续journal证明。", {"receipt_sequence": index + 1})
		var result_check := _validate_receipt_projection(row, cumulative_identity_rows, event_store)
		if not result_check.ok: return result_check
		cumulative_identity_rows.append(row)
	for base_value in entries_by_base.keys():
		var base := int(base_value)
		if base < 1 or base > receipt_rows.size():
			return _failure("commit.journal_base_receipt_invalid", "变更journal引用了不存在的收据。", {"base_receipt_sequence": base})
	var final_cues := cue_projection(receipt_rows)
	var final_projection := project(registry, event_store, stores, abstract_commits, final_cues)
	if receipt_rows.is_empty():
		if not journal_entries.is_empty():
			return _failure("commit.journal_without_receipt", "无收据世界不能携带收据后变更journal。")
	else:
		var last_row: Dictionary = receipt_rows.back()
		var transitioned := _apply_projection_entries(last_row.after_state, entries_by_base.get(receipt_rows.size(), []))
		if not transitioned.ok: return transitioned
		if GMReceiptEnvelopeAdapter.persistence_digest(transitioned.projection) != GMReceiptEnvelopeAdapter.persistence_digest(final_projection):
			return _failure("commit.receipt_final_world_projection_mismatch", "最终Registry/Store/Event/Change/Cue投影与收据及连续journal不一致。")
	return {"ok": true, "entries": journal_entries, "next_sequence": journal_entries.size() + 1, "cursor_projection": final_projection}


static func entry_digest(entry: Dictionary) -> String:
	var material: Dictionary = GMStableData.clone(entry)
	material.erase("record_digest")
	return GMReceiptEnvelopeAdapter.persistence_digest({"domain": ENTRY_SCHEMA, "entry": material})


static func journal_digest(journal: Dictionary) -> String:
	var material: Dictionary = GMStableData.clone(journal)
	material.erase("journal_digest")
	return GMReceiptEnvelopeAdapter.persistence_digest({"domain": JOURNAL_SCHEMA, "journal": material})


static func journal_genesis(world_id: String, epoch: int) -> String:
	return GMReceiptEnvelopeAdapter.persistence_digest({"domain": "gm.simulation.post_receipt_mutation_genesis.v3", "world_id": world_id, "epoch": epoch})


static func _decode_journal(value: Dictionary, receipt_rows: Array, expected_world_id: String, expected_epoch: int) -> Dictionary:
	var shape := _exact_fields(value, ["schema", "world_id", "epoch", "entry_count", "tail_digest", "entries", "journal_digest"])
	if not shape.ok: return _failure("commit.journal_shape_invalid", "收据后变更journal字段缺失或附加。", shape)
	if str(value.get("schema", "")) != JOURNAL_SCHEMA or str(value.get("world_id", "")) != expected_world_id or int(value.get("epoch", 0)) != expected_epoch:
		return _failure("commit.journal_scope_mismatch", "收据后变更journal的world、epoch或schema不匹配。")
	var entries_value: Variant = value.get("entries", null)
	if not entries_value is Array: return _failure("commit.journal_entries_invalid", "收据后变更journal不是数组。")
	var entries: Array = entries_value
	if int(value.get("entry_count", -1)) != entries.size(): return _failure("commit.journal_count_mismatch", "收据后变更journal计数不一致。")
	if str(value.get("journal_digest", "")) != journal_digest(value): return _failure("commit.journal_digest_mismatch", "收据后变更journal封套摘要不匹配。")
	var previous := journal_genesis(expected_world_id, expected_epoch)
	var previous_base := 0
	for index in entries.size():
		var entry_value: Variant = entries[index]
		if not entry_value is Dictionary: return _failure("commit.journal_entry_invalid", "收据后变更journal含非对象记录。")
		var entry: Dictionary = entry_value
		var entry_shape := _exact_fields(entry, ["schema", "world_id", "epoch", "journal_sequence", "base_receipt_sequence", "base_receipt_id", "previous_digest", "component_kind", "component_id", "operation", "from_revision", "to_revision", "before_component", "after_component", "before_projection", "after_projection", "record_digest"])
		if not entry_shape.ok: return _failure("commit.journal_entry_shape_invalid", "收据后变更记录字段缺失或附加。", entry_shape)
		if str(entry.get("schema", "")) != ENTRY_SCHEMA or str(entry.get("world_id", "")) != expected_world_id or int(entry.get("epoch", 0)) != expected_epoch:
			return _failure("commit.journal_entry_scope_mismatch", "收据后变更记录跨world、epoch或schema。")
		if int(entry.get("journal_sequence", 0)) != index + 1 or str(entry.get("previous_digest", "")) != previous or str(entry.get("record_digest", "")) != entry_digest(entry):
			return _failure("commit.journal_chain_invalid", "收据后变更journal顺序、前序链或摘要无效。")
		var base := int(entry.get("base_receipt_sequence", 0))
		if base < 1 or base > receipt_rows.size() or base < previous_base:
			return _failure("commit.journal_base_receipt_invalid", "收据后变更记录引用无效或倒序的基础收据。")
		var base_row: Dictionary = receipt_rows[base - 1]
		if str(entry.get("base_receipt_id", "")) != str(base_row.receipt_id):
			return _failure("commit.journal_base_receipt_mismatch", "收据后变更记录的基础收据身份不匹配。")
		var transition := _validate_entry_transition(entry)
		if not transition.ok: return transition
		previous = str(entry.record_digest)
		previous_base = base
	var expected_tail := journal_genesis(expected_world_id, expected_epoch) if entries.is_empty() else str(entries.back().get("record_digest", ""))
	if str(value.get("tail_digest", "")) != expected_tail: return _failure("commit.journal_tail_mismatch", "收据后变更journal尾摘要不匹配。")
	return {"ok": true, "entries": GMStableData.clone(entries)}


static func _validate_entry_transition(entry: Dictionary) -> Dictionary:
	var before_component: Variant = entry.get("before_component", null)
	var after_component: Variant = entry.get("after_component", null)
	if not before_component is Dictionary or not after_component is Dictionary:
		return _failure("commit.journal_component_shape_invalid", "变更journal组件快照必须是对象。")
	var before_projection: Variant = entry.get("before_projection", null)
	var after_projection: Variant = entry.get("after_projection", null)
	if not before_projection is Dictionary or not after_projection is Dictionary:
		return _failure("commit.journal_projection_shape_invalid", "变更journal世界投影必须是对象。")
	var before_shape := _validate_projection_shape(before_projection)
	if not before_shape.ok: return before_shape
	var after_shape := _validate_projection_shape(after_projection)
	if not after_shape.ok: return after_shape
	var kind := str(entry.get("component_kind", ""))
	var identity := str(entry.get("component_id", ""))
	var from_revision := int(entry.get("from_revision", -1))
	var to_revision := int(entry.get("to_revision", -1))
	if identity.is_empty() or not kind in ["registry", "store"] or to_revision != from_revision + 1:
		return _failure("commit.journal_revision_transition_invalid", "变更journal必须描述单一组件的连续持久化修订。")
	if from_revision != _component_revision(kind, before_component) or to_revision != _component_revision(kind, after_component):
		return _failure("commit.journal_component_revision_mismatch", "变更journal修订与组件快照不一致。")
	if GMReceiptEnvelopeAdapter.persistence_digest(before_component) == GMReceiptEnvelopeAdapter.persistence_digest(after_component):
		return _failure("commit.journal_noop_invalid", "变更journal不能记录无内容变化操作。")
	for invariant in ["event_archive_digest", "event_history_id", "event_count", "change_count", "abstract_count", "cue_count", "cue_digest"]:
		if GMReceiptEnvelopeAdapter.persistence_digest(before_projection.get(invariant)) != GMReceiptEnvelopeAdapter.persistence_digest(after_projection.get(invariant)):
			return _failure("commit.journal_non_component_projection_changed", "Registry/Store journal不得改变Event/Change/Cue或abstract投影。", {"field": invariant})
	if kind == "registry":
		if GMReceiptEnvelopeAdapter.persistence_digest(before_projection.store_revisions) != GMReceiptEnvelopeAdapter.persistence_digest(after_projection.store_revisions) or GMReceiptEnvelopeAdapter.persistence_digest(before_projection.store_digests) != GMReceiptEnvelopeAdapter.persistence_digest(after_projection.store_digests):
			return _failure("commit.journal_cross_component_changed", "Registry journal同时改变了Store投影。")
		if int(before_projection.registry_versions.get(identity, 0)) != from_revision or int(after_projection.registry_versions.get(identity, 0)) != to_revision:
			return _failure("commit.journal_registry_version_mismatch", "Registry journal身份版本投影不一致。")
		if str(before_projection.registry_record_digests.get(identity, GMReceiptEnvelopeAdapter.persistence_digest({}))) != GMReceiptEnvelopeAdapter.persistence_digest(before_component) or str(after_projection.registry_record_digests.get(identity, "")) != GMReceiptEnvelopeAdapter.persistence_digest(after_component):
			return _failure("commit.journal_registry_digest_mismatch", "Registry journal实体内容摘要与世界投影不一致。")
		var before_other: Dictionary = GMStableData.clone(before_projection.registry_record_digests)
		var after_other: Dictionary = GMStableData.clone(after_projection.registry_record_digests)
		before_other.erase(identity)
		after_other.erase(identity)
		if GMReceiptEnvelopeAdapter.persistence_digest(before_other) != GMReceiptEnvelopeAdapter.persistence_digest(after_other):
			return _failure("commit.journal_multi_entity_transition_invalid", "单条Registry journal改变了多个实体。")
	else:
		if GMReceiptEnvelopeAdapter.persistence_digest(before_projection.registry_versions) != GMReceiptEnvelopeAdapter.persistence_digest(after_projection.registry_versions) or GMReceiptEnvelopeAdapter.persistence_digest(before_projection.registry_record_digests) != GMReceiptEnvelopeAdapter.persistence_digest(after_projection.registry_record_digests) or str(before_projection.registry_digest) != str(after_projection.registry_digest):
			return _failure("commit.journal_cross_component_changed", "Store journal同时改变了Registry投影。")
		if int(before_projection.store_revisions.get(identity, -1)) != from_revision or int(after_projection.store_revisions.get(identity, -1)) != to_revision:
			return _failure("commit.journal_store_revision_mismatch", "Store journal持久化修订投影不一致。")
		if str(before_projection.store_digests.get(identity, "")) != GMReceiptEnvelopeAdapter.persistence_digest(before_component) or str(after_projection.store_digests.get(identity, "")) != GMReceiptEnvelopeAdapter.persistence_digest(after_component):
			return _failure("commit.journal_store_digest_mismatch", "Store journal内容摘要与世界投影不一致。")
		var before_other_revisions: Dictionary = GMStableData.clone(before_projection.store_revisions)
		var after_other_revisions: Dictionary = GMStableData.clone(after_projection.store_revisions)
		var before_other_digests: Dictionary = GMStableData.clone(before_projection.store_digests)
		var after_other_digests: Dictionary = GMStableData.clone(after_projection.store_digests)
		for mapping in [before_other_revisions, after_other_revisions, before_other_digests, after_other_digests]: mapping.erase(identity)
		if GMReceiptEnvelopeAdapter.persistence_digest(before_other_revisions) != GMReceiptEnvelopeAdapter.persistence_digest(after_other_revisions) or GMReceiptEnvelopeAdapter.persistence_digest(before_other_digests) != GMReceiptEnvelopeAdapter.persistence_digest(after_other_digests):
			return _failure("commit.journal_multi_store_transition_invalid", "单条Store journal改变了多个Store。")
	return {"ok": true}


static func _apply_projection_entries(initial: Dictionary, entries: Array) -> Dictionary:
	var cursor: Dictionary = GMStableData.clone(initial)
	for entry_value in entries:
		var entry: Dictionary = entry_value
		if GMReceiptEnvelopeAdapter.persistence_digest(cursor) != GMReceiptEnvelopeAdapter.persistence_digest(entry.before_projection):
			return _failure("commit.journal_projection_gap", "变更journal存在缺口、重排或重放。", {"journal_sequence": entry.journal_sequence})
		cursor = GMStableData.clone(entry.after_projection)
	return {"ok": true, "projection": cursor}


static func _validate_receipt_projection(row: Dictionary, previous_rows: Array, event_store: GMEventStore) -> Dictionary:
	var result: Dictionary = row.result
	var identity: Dictionary = row.identity_projection
	var expected_before_cues := cue_projection(previous_rows)
	var with_current := previous_rows.duplicate()
	with_current.append(row)
	var expected_after_cues := cue_projection(with_current)
	if int(row.before_state.cue_count) != int(expected_before_cues.cue_count) or str(row.before_state.cue_digest) != str(expected_before_cues.cue_digest):
		return _failure("commit.receipt_before_cue_projection_mismatch", "收据前置Cue投影与历史收据不一致。")
	if int(row.after_state.cue_count) != int(expected_after_cues.cue_count) or str(row.after_state.cue_digest) != str(expected_after_cues.cue_digest):
		return _failure("commit.receipt_after_cue_projection_mismatch", "收据后置Cue投影与结果不一致。")
	if int(result.event_count) != int(row.after_state.event_count) or int(result.change_count) != int(row.after_state.change_count) or int(result.abstract_count) != int(row.after_state.abstract_count) or int(result.cue_count) != int(identity.get("cue_count", -1)):
		return _failure("commit.receipt_result_projection_mismatch", "提交结果计数与Event/Change/Cue状态投影不一致。")
	var facts_by_id := {}
	for fact in event_store.get_records(): facts_by_id[str(fact.get("event_id", ""))] = fact
	for item_value in result.results:
		var item: Dictionary = item_value
		var fact_id := str(item.get("fact_event_id", ""))
		if fact_id.is_empty(): continue
		if not facts_by_id.has(fact_id): return _failure("commit.receipt_fact_projection_mismatch", "收据结果引用了EventStore中不存在的Fact。")
		var fact: Dictionary = facts_by_id[fact_id]
		if str(item.get("transaction_id", "")) != str(fact.get("transaction_id", "")) or str(item.get("ability_instance_id", "")) != str(fact.get("ability_instance_id", "")):
			return _failure("commit.receipt_fact_identity_mismatch", "收据Transaction/AbilityInstance身份与Fact不一致。")
	return {"ok": true}


static func _validate_projection_shape(value: Dictionary) -> Dictionary:
	var shape := _exact_fields(value, PROJECTION_FIELDS)
	if not shape.ok: return _failure("commit.receipt_projection_shape_invalid", "世界投影字段缺失或附加。", shape)
	for digest_field in ["registry_digest", "event_archive_digest", "event_history_id", "cue_digest"]:
		if str(value.get(digest_field, "")).is_empty(): return _failure("commit.receipt_projection_digest_missing", "世界投影缺少稳定摘要。", {"field": digest_field})
	if not value.get("registry_versions", null) is Dictionary or not value.get("registry_record_digests", null) is Dictionary or not value.get("store_revisions", null) is Dictionary or not value.get("store_digests", null) is Dictionary:
		return _failure("commit.receipt_projection_mapping_invalid", "世界投影版本或内容摘要映射无效。")
	return {"ok": true}


static func _component_revision(kind: String, component: Dictionary) -> int:
	if component.is_empty(): return 0
	if kind == "store": return int(component.get("persistence_revision", -1))
	return int(component.get("version", -1))


static func _exact_fields(value: Dictionary, expected_fields: Array) -> Dictionary:
	var actual: Array[String] = []
	for key in value.keys(): actual.append(str(key))
	actual.sort()
	var expected: Array[String] = []
	for key in expected_fields: expected.append(str(key))
	expected.sort()
	return {"ok": actual == expected, "actual": actual, "expected": expected}


static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty(): result["details"] = details
	return result
