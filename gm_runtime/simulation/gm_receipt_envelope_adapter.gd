class_name GMReceiptEnvelopeAdapter
extends RefCounted


const WORLD_SCHEMA := "gm.simulation_world.v6"
const LEDGER_SCHEMA := "gm.simulation.commit_receipts.v5"
const ENVELOPE_SCHEMA := "gm.simulation.commit_receipt_envelope.v5"


static func decode_ledger(value: Dictionary, expected_world_id: String, maximum_entries: int) -> Dictionary:
	if str(value.get("schema", "")) != LEDGER_SCHEMA:
		return _failure("commit.receipt_archive_missing", "世界存档缺少当前版本的提交收据账本。")
	var ledger_shape := _exact_fields(value, ["schema", "epoch", "entry_count", "limit", "receipts", "command_contracts"])
	if not ledger_shape.ok:
		return _failure("commit.receipt_archive_shape_invalid", "提交收据账本字段缺失或附加。", ledger_shape)
	var rows_value: Variant = value.get("receipts", null)
	var contracts_value: Variant = value.get("command_contracts", null)
	if not rows_value is Array or not contracts_value is Dictionary:
		return _failure("commit.receipt_archive_invalid", "提交收据账本结构无效。")
	var rows: Array = rows_value
	var ledger_limit := int(value.get("limit", 0))
	if ledger_limit < 1 or ledger_limit > maxi(maximum_entries, 1) or rows.size() > ledger_limit:
		return _failure("commit.receipt_archive_overflow", "提交收据账本超出有界容量。")
	var ledger_epoch := int(value.get("epoch", 0))
	if ledger_epoch < 1:
		return _failure("commit.receipt_epoch_invalid", "提交收据epoch无效。")
	var staged_receipts: Dictionary = {}
	var derived_contracts: Dictionary = {}
	var decoded_rows: Array = []
	var expected_sequence := 1
	for row_value in rows:
		if not row_value is Dictionary:
			return _failure("commit.receipt_invalid", "提交收据不是对象。")
		var row: Dictionary = row_value
		var row_shape := _exact_fields(row, ["schema", "receipt_id", "receipt_sequence", "world_id", "epoch", "contract_digest", "contract", "result", "before_state", "after_state", "identity_projection", "envelope_digest"])
		if not row_shape.ok:
			return _failure("commit.receipt_shape_invalid", "提交收据封套字段缺失或附加。", row_shape)
		if str(row.get("schema", "")) != ENVELOPE_SCHEMA or str(row.get("world_id", "")) != expected_world_id or int(row.get("epoch", 0)) != ledger_epoch:
			return _failure("commit.receipt_scope_mismatch", "提交收据来自不同world、epoch或封套版本。")
		if int(row.get("receipt_sequence", 0)) != expected_sequence:
			return _failure("commit.receipt_sequence_invalid", "提交收据顺序不连续或发生漂移。")
		var contract_value: Variant = row.get("contract", null)
		if not contract_value is Dictionary:
			return _failure("commit.receipt_contract_missing", "提交收据缺少完整合同。")
		var contract: Dictionary = contract_value
		var contract_shape := _exact_fields(contract, ["schema", "epoch", "world_id", "snapshot", "merge", "commands"])
		if not contract_shape.ok or str(contract.get("schema", "")) != LEDGER_SCHEMA or str(contract.get("world_id", "")) != expected_world_id or int(contract.get("epoch", 0)) != ledger_epoch:
			return _failure("commit.receipt_contract_scope_invalid", "提交合同字段或world/epoch绑定无效。")
		var digest := persistence_digest(contract)
		var expected_receipt_id := receipt_id_for_contract(contract)
		if str(row.get("contract_digest", "")) != digest or str(row.get("receipt_id", "")) != expected_receipt_id:
			return _failure("commit.receipt_digest_mismatch", "提交收据身份或摘要不匹配。")
		if str(row.get("envelope_digest", "")) != envelope_digest(row):
			return _failure("commit.receipt_envelope_digest_mismatch", "提交收据完整封套摘要不匹配。")
		if staged_receipts.has(expected_receipt_id):
			return _failure("commit.receipt_duplicate", "提交收据存档包含重复身份。")
		var result_check := _decode_result(row)
		if not result_check.ok:
			return result_check
		var commands_value: Variant = contract.get("commands", null)
		if not commands_value is Array:
			return _failure("commit.receipt_commands_invalid", "提交收据命令合同不是数组。")
		for command_value in commands_value:
			if not command_value is Dictionary:
				return _failure("commit.receipt_command_invalid", "提交收据含无效命令合同。")
			var exact_key := str(command_value.get("idempotency_key", ""))
			var command_digest := command_contract_digest(command_value)
			if exact_key.is_empty() or (derived_contracts.has(exact_key) and str(derived_contracts[exact_key]) != command_digest):
				return _failure("commit.receipt_command_conflict", "提交收据命令合同键缺失或冲突。")
			derived_contracts[exact_key] = command_digest
		var cloned: Dictionary = GMStableData.clone(row)
		staged_receipts[expected_receipt_id] = cloned
		decoded_rows.append(cloned)
		expected_sequence += 1
	if int(value.get("entry_count", -1)) != staged_receipts.size():
		return _failure("commit.receipt_count_mismatch", "提交收据计数不一致。")
	if persistence_digest(contracts_value) != persistence_digest(derived_contracts):
		return _failure("commit.command_contract_projection_mismatch", "命令合同账本与收据封套不一致。")
	if decoded_rows.is_empty() and not contracts_value.is_empty():
		return _failure("commit.command_contract_orphaned", "无收据账本不能携带命令合同。")
	return {"ok": true, "rows": decoded_rows, "receipts": staged_receipts, "command_contracts": GMStableData.clone(contracts_value), "epoch": ledger_epoch, "next_sequence": expected_sequence}


static func create_envelope(receipt_id: String, receipt_sequence: int, world_id: String, epoch: int, contract: Dictionary, result: Dictionary, before_state: Dictionary, after_state: Dictionary, identity_projection: Dictionary) -> Dictionary:
	var envelope := {
		"schema": ENVELOPE_SCHEMA,
		"receipt_id": receipt_id,
		"receipt_sequence": receipt_sequence,
		"world_id": world_id,
		"epoch": epoch,
		"contract_digest": persistence_digest(contract),
		"contract": GMStableData.clone(contract),
		"result": GMStableData.clone(result),
		"before_state": GMStableData.clone(before_state),
		"after_state": GMStableData.clone(after_state),
		"identity_projection": GMStableData.clone(identity_projection),
	}
	envelope["envelope_digest"] = envelope_digest(envelope)
	return envelope


static func receipt_id_for_contract(contract: Dictionary) -> String:
	return "gm.simulation.commit_receipt.v2.%s" % persistence_digest(contract)


static func envelope_digest(envelope: Dictionary) -> String:
	var material: Dictionary = GMStableData.clone(envelope)
	material.erase("envelope_digest")
	return persistence_digest({"domain": ENVELOPE_SCHEMA, "envelope": material})


static func command_contract_digest(command: Dictionary) -> String:
	var material: Dictionary = GMStableData.clone(command)
	for field_name in ["command_id", "sequence"]:
		material.erase(field_name)
	return persistence_digest({"domain": "gm.simulation.command_contract.v1", "command": material})


static func persistence_digest(value: Variant) -> String:
	return GMStableData.digest(_persistence_canonical(value))


static func _decode_result(row: Dictionary) -> Dictionary:
	var result_value: Variant = row.get("result", null)
	if not result_value is Dictionary:
		return _failure("commit.receipt_result_missing", "提交收据缺少结果对象。")
	var result: Dictionary = result_value
	var result_shape := _exact_fields(result, ["ok", "accepted_count", "results", "event_count", "change_count", "cue_count", "abstract_count", "receipt_id", "idempotent_replay"])
	if not result_shape.ok:
		return _failure("commit.receipt_result_shape_invalid", "提交结果字段缺失或附加。", result_shape)
	var contract: Dictionary = row.contract
	var commands: Variant = contract.get("commands", null)
	var results: Variant = result.get("results", null)
	if not commands is Array or not results is Array or int(result.get("accepted_count", -1)) != commands.size() or results.size() != commands.size():
		return _failure("commit.receipt_result_count_mismatch", "提交结果数量与完整命令合同不一致。")
	if str(result.get("receipt_id", "")) != str(row.receipt_id) or bool(result.get("idempotent_replay", true)):
		return _failure("commit.receipt_result_identity_mismatch", "持久化提交结果身份或重放状态无效。")
	var all_ok := true
	for item in results:
		if not item is Dictionary:
			return _failure("commit.receipt_result_row_invalid", "提交结果行不是对象。")
		if not bool(item.get("ok", false)):
			all_ok = false
	if bool(result.get("ok", false)) != all_ok:
		return _failure("commit.receipt_ok_projection_mismatch", "提交结果ok与逐命令结果不一致。")
	var identity := result_identity_projection(results)
	if persistence_digest(row.get("identity_projection", {})) != persistence_digest(identity):
		return _failure("commit.receipt_identity_projection_mismatch", "提交结果稳定身份/Cue投影不一致。")
	if not row.get("before_state", null) is Dictionary or not row.get("after_state", null) is Dictionary:
		return _failure("commit.receipt_state_projection_invalid", "提交收据缺少前后状态投影。")
	return {"ok": true}


static func result_identity_projection(results: Array) -> Dictionary:
	var fact_ids: Array[String] = []
	var transaction_ids: Array[String] = []
	var instance_ids: Array[String] = []
	var cue_digests: Array[String] = []
	var cue_count := 0
	for item_value in results:
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var fact_id := str(item.get("fact_event_id", ""))
		var transaction_id := str(item.get("transaction_id", ""))
		var instance_id := str(item.get("ability_instance_id", ""))
		if not fact_id.is_empty(): fact_ids.append(fact_id)
		if not transaction_id.is_empty(): transaction_ids.append(transaction_id)
		if not instance_id.is_empty(): instance_ids.append(instance_id)
		var cues: Variant = item.get("cues", [])
		if cues is Array:
			for cue in cues:
				cue_digests.append(persistence_digest(cue))
				cue_count += 1
	return {"fact_event_ids": fact_ids, "transaction_ids": transaction_ids, "ability_instance_ids": instance_ids, "cue_digests": cue_digests, "cue_count": cue_count}


static func _exact_fields(value: Dictionary, expected_fields: Array) -> Dictionary:
	var actual: Array[String] = []
	for key in value.keys(): actual.append(str(key))
	actual.sort()
	var expected: Array[String] = []
	for key in expected_fields: expected.append(str(key))
	expected.sort()
	return {"ok": actual == expected, "actual": actual, "expected": expected}


static func _persistence_canonical(value: Variant) -> Variant:
	return GMStableData.persistence_canonical(value)


static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty(): result["details"] = details
	return result
