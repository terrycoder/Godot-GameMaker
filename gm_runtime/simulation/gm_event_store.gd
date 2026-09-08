class_name GMEventStore
extends GMFactEventStore

## 事件账本只接受统一事务管线的 GMCommittedFactResult。
## DomainTransactionCoordinator 内部使用继承的 commit 写入口；外部公共入口严格拒绝裸结果。

var archive_world_id: String = ""
var archive_epoch: int = 1

func configure_archive_identity(p_world_id: String, p_epoch: int = 1) -> Dictionary:
	if p_world_id.is_empty() or p_epoch < 1:
		return {"ok": false, "code": "event_store.archive_identity_invalid", "reason_zh": "EventStore存档身份需要world与正epoch。"}
	archive_world_id = p_world_id
	archive_epoch = p_epoch
	return {"ok": true, "world_id": archive_world_id, "epoch": archive_epoch}

func append_fact(_fact: GMFactEvent) -> Dictionary:
	return _reject_external("GMEventStore 只接受 05A GMCommittedFactResult，不接受裸 FactEvent。")

func append_record_once(value: Variant) -> Dictionary:
	if not value is GMCommittedFactResult:
		return _reject_external("GMEventStore 拒绝 Candidate、BlockedResult 或裸 FactEvent。")
	return super.append_record_once(value)

func append_result(value: Variant) -> Dictionary:
	if not value is GMCommittedFactResult:
		return _reject_external("GMEventStore 只接受 GMCommittedFactResult。")
	return super.append_result(value)

func accept_committed_fact(value: Variant) -> Dictionary:
	return append_result(value)

func restore_snapshot(value: Dictionary) -> Dictionary:
	var top_shape := _require_exact_fields(value, ["schema", "archive_schema", "world_id", "archive_epoch", "history_id", "genesis_digest", "chain_tail_digest", "fact_count", "change_count", "facts", "changes", "archive_records", "archive_digest"])
	if not top_shape.ok: return _restore_failure("event_store.archive_shape_invalid", "事件账本存档字段缺失或附加。")
	if str(value.get("schema", "")) != GMFactEventSchema.SCHEMA_ID:
		return {"ok": false, "code": "event_store.schema_invalid", "reason_zh": "事件账本存档 Schema 不匹配。"}
	if str(value.get("archive_schema", "")) != ARCHIVE_SCHEMA:
		return {"ok": false, "code": "event_store.archive_contract_missing", "reason_zh": "公开Fact字典不是可信内部存档记录，恢复已拒绝。"}
	var archive_records: Variant = value.get("archive_records", null)
	if not archive_records is Array:
		return {"ok": false, "code": "event_store.archive_records_invalid", "reason_zh": "事件账本存档缺少内部提交记录。"}
	var supplied_world_id := str(value.get("world_id", ""))
	var supplied_epoch := int(value.get("archive_epoch", 0))
	var supplied_history_id := str(value.get("history_id", ""))
	var supplied_genesis := str(value.get("genesis_digest", ""))
	if supplied_world_id.is_empty() or supplied_epoch < 1 or supplied_history_id.is_empty() or supplied_genesis.is_empty():
		return _restore_failure("event_store.archive_lineage_missing", "事件账本存档缺少world/epoch/history/genesis谱系。")
	if not archive_world_id.is_empty() and (archive_world_id != supplied_world_id or archive_epoch != supplied_epoch):
		return _restore_failure("event_store.archive_identity_mismatch", "事件账本存档来自不同world或epoch。")
	var raw_records := _raw_archive_records(archive_records)
	var expected_history_id := _history_id(supplied_world_id, supplied_epoch, raw_records)
	var expected_genesis := _genesis_digest(supplied_world_id, supplied_epoch, expected_history_id)
	if supplied_history_id != expected_history_id or supplied_genesis != expected_genesis:
		return _restore_failure("event_store.archive_history_mismatch", "事件账本完整历史身份或genesis不匹配。")
	var supplied_digest := str(value.get("archive_digest", ""))
	var expected_digest := _archive_digest(value)
	if supplied_digest.is_empty() or supplied_digest != expected_digest:
		return {"ok": false, "code": "event_store.archive_digest_mismatch", "reason_zh": "事件账本存档摘要不匹配，原账本保持不变。"}
	var staged_records: Array[GMFactEvent] = []
	var staged_changes: Array[GMChangeRecord] = []
	var staged_by_id: Dictionary = {}
	var staged_by_key: Dictionary = {}
	var staged_transactions: Dictionary = {}
	var staged_change_ids: Dictionary = {}
	var previous_digest := supplied_genesis
	for index in archive_records.size():
		var archive_value: Variant = archive_records[index]
		if not archive_value is Dictionary:
			return _restore_failure("event_store.archive_record_invalid", "事件账本存档包含无效内部记录。")
		var archive: Dictionary = archive_value
		var record_shape := _require_exact_fields(archive, ["fact", "changes", "commit_linkage", "lineage", "record_digest"])
		if not record_shape.ok: return _restore_failure("event_store.archive_record_shape_invalid", "内部提交记录字段缺失或附加。")
		var lineage_value: Variant = archive.get("lineage", null)
		if not lineage_value is Dictionary: return _restore_failure("event_store.record_lineage_missing", "内部提交记录缺少历史谱系绑定。")
		var lineage: Dictionary = lineage_value
		var expected_lineage := {"world_id": supplied_world_id, "archive_epoch": supplied_epoch, "history_id": supplied_history_id, "genesis_digest": supplied_genesis, "record_index": index + 1, "previous_record_digest": previous_digest}
		if GMStableData.canonical_json(_persistence_canonical(lineage)) != GMStableData.canonical_json(_persistence_canonical(expected_lineage)):
			return _restore_failure("event_store.record_lineage_mismatch", "内部提交记录的world/epoch/前序谱系不连续。")
		var fact_value: Variant = archive.get("fact", null)
		var changes_value: Variant = archive.get("changes", null)
		if not fact_value is Dictionary or not changes_value is Array:
			return _restore_failure("event_store.archive_record_invalid", "内部提交记录缺少Fact或Change批次。")
		var fact := GMFactEvent.from_dict(fact_value)
		var check := fact.validate()
		if not check.ok: return _restore_failure("event_store.fact_invalid", "事件账本Fact校验失败。", check.errors)
		if fact.sequence != index + 1:
			return _restore_failure("event_store.fact_sequence_invalid", "Fact序号必须连续且与存档顺序一致。")
		if not fact.ability_instance_id.begins_with("gm.ability.instance.v2.") or not fact.transaction_id.begins_with("gm.transaction.v2."):
			return _restore_failure("event_store.identity_contract_invalid", "Fact缺少当前Host v2或Transaction v2身份。")
		var event_parts := fact.event_id.split(".")
		var identity_sequence := int(event_parts[3]) if event_parts.size() == 5 else 0
		if identity_sequence < 1 or fact.event_id != GMFactEvent.make_event_id(identity_sequence, fact.type, fact.idempotency_key):
			return _restore_failure("event_store.fact_identity_mismatch", "Fact身份与完整精确材料不一致。")
		if staged_by_id.has(fact.event_id) or staged_by_key.has(fact.idempotency_key) or staged_transactions.has(fact.transaction_id):
			return _restore_failure("event_store.archive_duplicate", "存档包含重复Fact、幂等键或Transaction。")
		var linkage: Dictionary = archive.get("commit_linkage", {}) if archive.get("commit_linkage", {}) is Dictionary else {}
		if not _require_exact_fields(linkage, ["transaction_id", "fact_event_id", "causal_chain_id", "ability_instance_id", "request_id"]).ok: return _restore_failure("event_store.commit_linkage_shape_invalid", "内部提交链接字段缺失或附加。")
		if str(linkage.get("transaction_id", "")) != fact.transaction_id or str(linkage.get("fact_event_id", "")) != fact.event_id or str(linkage.get("causal_chain_id", "")) != fact.causal_chain_id or str(linkage.get("ability_instance_id", "")) != fact.ability_instance_id:
			return _restore_failure("event_store.commit_linkage_mismatch", "内部提交记录的Transaction/Fact/因果链接不一致。")
		var request_id := str(linkage.get("request_id", ""))
		var expected_transaction := "gm.transaction.v2.%s" % ("%s|%s|%s|%s" % [fact.resolver_id, fact.idempotency_key, fact.ability_instance_id, request_id]).sha256_text()
		if request_id.is_empty() or fact.transaction_id != expected_transaction:
			return _restore_failure("event_store.transaction_proof_mismatch", "Transaction身份不能由已提交精确材料重新验证。")
		var cause_ids: Array = fact.causes.duplicate(true)
		var required_causes := [request_id, fact.ability_instance_id, fact.resolver_id, fact.transaction_id]
		for cause_id in required_causes:
			if cause_ids.count(cause_id) != 1: return _restore_failure("event_store.causal_chain_mismatch", "Fact因果链缺失、重复或指向错误提交节点。")
		if changes_value.is_empty(): return _restore_failure("event_store.change_missing", "已提交Fact缺少Change记录。")
		var fact_changes: Array[GMChangeRecord] = []
		for change_index in changes_value.size():
			var change_value: Variant = changes_value[change_index]
			if not change_value is Dictionary: return _restore_failure("event_store.change_invalid", "事件账本存档包含无效ChangeRecord。")
			var change := GMChangeRecord.from_dict(change_value)
			var change_check := change.validate()
			if not change_check.ok: return _restore_failure("event_store.change_invalid", "事件账本ChangeRecord校验失败。", change_check.errors)
			if change.fact_event_id != fact.event_id or change.transaction_id != fact.transaction_id or change.causal_chain_id != fact.causal_chain_id:
				return _restore_failure("event_store.change_linkage_mismatch", "Change未指向同一Fact、Transaction和因果链。")
			if staged_change_ids.has(change.change_id): return _restore_failure("event_store.change_duplicate", "存档包含重复Change身份。")
			if change.change_id != GMChangeRecord.make_change_id(fact.event_id, change.idempotency_key, change.sequence):
				return _restore_failure("event_store.change_identity_mismatch", "Change身份与完整精确材料不一致。")
			staged_change_ids[change.change_id] = true
			fact_changes.append(change)
		var record_digest := str(archive.get("record_digest", ""))
		if record_digest != GMStableData.digest(_persistence_canonical({"fact": fact.to_dict(), "changes": _changes_to_dict(fact_changes), "commit_linkage": linkage, "lineage": lineage})):
			return _restore_failure("event_store.record_digest_mismatch", "内部提交记录摘要不匹配。")
		previous_digest = record_digest
		staged_records.append(fact)
		staged_changes.append_array(fact_changes)
		staged_by_id[fact.event_id] = fact
		staged_by_key[fact.idempotency_key] = fact
		staged_transactions[fact.transaction_id] = true
	if int(value.get("fact_count", -1)) != staged_records.size() or int(value.get("change_count", -1)) != staged_changes.size():
		return _restore_failure("event_store.archive_count_mismatch", "事件账本存档计数与内部记录不一致。")
	var top_facts: Variant = value.get("facts", null)
	var top_changes: Variant = value.get("changes", null)
	if not top_facts is Array or not top_changes is Array:
		return _restore_failure("event_store.public_projection_missing", "事件账本存档缺少Fact/Change公共投影。")
	var staged_fact_dicts: Array = []
	for fact in staged_records: staged_fact_dicts.append(fact.to_dict())
	if GMStableData.canonical_json(_persistence_canonical(top_facts)) != GMStableData.canonical_json(_persistence_canonical(staged_fact_dicts)) or GMStableData.canonical_json(_persistence_canonical(top_changes)) != GMStableData.canonical_json(_persistence_canonical(_changes_to_dict(staged_changes))):
		return _restore_failure("event_store.archive_projection_mismatch", "Fact/Change公共投影与可信内部记录不一致。")
	if str(value.get("chain_tail_digest", "")) != previous_digest:
		return _restore_failure("event_store.archive_chain_tail_mismatch", "事件账本存档链尾与逐记录谱系不一致。")
	# Only after every row has validated do we mint in-memory commit authority and
	# atomically replace the live ledger.
	for fact in staged_records: fact.mark_committed(fact.transaction_id, GMFactEvent._get_commit_capability())
	records = staged_records
	by_id = staged_by_id
	by_idempotency = staged_by_key
	if change_store == null: change_store = GMChangeRecordStore.new()
	change_store.records = staged_changes
	_next_sequence = records.size() + 1
	archive_world_id = supplied_world_id
	archive_epoch = supplied_epoch
	return {"ok": true, "fact_count": records.size(), "change_count": change_store.records.size(), "archive_verified": true}

func snapshot() -> Dictionary:
	var raw_records: Array = []
	for fact in records:
		var fact_changes: Array = []
		for change in change_store.records:
			if change.fact_event_id == fact.event_id: fact_changes.append(change.to_dict())
		var request_id := ""
		for cause_id in fact.causes:
			if str(cause_id).begins_with("gmreq-"): request_id = str(cause_id); break
		var linkage := {"transaction_id": fact.transaction_id, "fact_event_id": fact.event_id, "causal_chain_id": fact.causal_chain_id, "ability_instance_id": fact.ability_instance_id, "request_id": request_id}
		raw_records.append({"fact": fact.to_dict(), "changes": fact_changes, "commit_linkage": linkage})
	var effective_world_id := archive_world_id if not archive_world_id.is_empty() else "gm.event_store.standalone"
	var history_id := _history_id(effective_world_id, archive_epoch, raw_records)
	var genesis := _genesis_digest(effective_world_id, archive_epoch, history_id)
	var previous_digest := genesis
	var archive_records: Array = []
	for index in raw_records.size():
		var record: Dictionary = GMStableData.clone(raw_records[index])
		record["lineage"] = {"world_id": effective_world_id, "archive_epoch": archive_epoch, "history_id": history_id, "genesis_digest": genesis, "record_index": index + 1, "previous_record_digest": previous_digest}
		record["record_digest"] = GMStableData.digest(_persistence_canonical(record))
		previous_digest = record.record_digest
		archive_records.append(record)
	var result := {"schema": GMFactEventSchema.SCHEMA_ID, "archive_schema": ARCHIVE_SCHEMA, "world_id": effective_world_id, "archive_epoch": archive_epoch, "history_id": history_id, "genesis_digest": genesis, "chain_tail_digest": previous_digest, "fact_count": records.size(), "change_count": change_store.get_record_count(), "facts": get_records(), "changes": change_store.get_records(), "archive_records": archive_records}
	result["archive_digest"] = _archive_digest(result)
	return result

func _archive_digest(value: Dictionary) -> String:
	return GMStableData.digest(_persistence_canonical({"schema": value.get("schema", ""), "archive_schema": value.get("archive_schema", ""), "world_id": value.get("world_id", ""), "archive_epoch": value.get("archive_epoch", 0), "history_id": value.get("history_id", ""), "genesis_digest": value.get("genesis_digest", ""), "chain_tail_digest": value.get("chain_tail_digest", ""), "fact_count": value.get("fact_count", -1), "change_count": value.get("change_count", -1), "archive_records": value.get("archive_records", [])}))

func _raw_archive_records(values: Array) -> Array:
	var result: Array = []
	for value in values:
		if not value is Dictionary:
			result.append(value)
			continue
		var raw: Dictionary = GMStableData.clone(value)
		raw.erase("record_digest")
		raw.erase("lineage")
		result.append(raw)
	return result

func _history_id(p_world_id: String, p_epoch: int, raw_records: Array) -> String:
	return "gm.event_store.history.v1.%s" % GMStableData.digest(_persistence_canonical({"world_id": p_world_id, "archive_epoch": p_epoch, "records": raw_records}))

func _genesis_digest(p_world_id: String, p_epoch: int, history_id: String) -> String:
	return GMStableData.digest({"domain": "gm.event_store.genesis.v1", "world_id": p_world_id, "archive_epoch": p_epoch, "history_id": history_id})

func _require_exact_fields(value: Dictionary, expected_fields: Array) -> Dictionary:
	var actual: Array[String] = []
	for key in value.keys(): actual.append(str(key))
	actual.sort()
	var expected: Array[String] = []
	for key in expected_fields: expected.append(str(key))
	expected.sort()
	return {"ok": actual == expected, "actual": actual, "expected": expected}

func _restore_failure(code: String, reason_zh: String, errors: Array = []) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "errors": errors.duplicate(true), "atomic": true}

func _changes_to_dict(values: Array[GMChangeRecord]) -> Array:
	var result: Array = []
	for change in values: result.append(change.to_dict())
	return result

func _persistence_canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value.keys(): result[str(key)] = _persistence_canonical(value[key])
		return GMStableData.canonical(result)
	if value is Array:
		var result: Array = []
		for item in value: result.append(_persistence_canonical(item))
		return result
	if value is float and is_equal_approx(value, round(value)):
		return int(round(value))
	return value

func _reject_external(reason_zh: String) -> Dictionary:
	return {"ok": false, "code": "event_store.committed_only", "reason_zh": reason_zh, "appended": false}
const ARCHIVE_SCHEMA := "gm.event_store.archive.v2"
