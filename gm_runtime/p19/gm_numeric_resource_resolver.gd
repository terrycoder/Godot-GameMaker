class_name GMNumericResourceResolver
extends "res://gm_runtime/transactions/gm_domain_resolver.gd"

## Numeric Resource domain adapter. It owns no transaction lifecycle of its own;
## GMDomainTransaction remains the only lifecycle authority.

const OPERATIONS := ["transfer", "cost", "reward", "grant", "consume", "convert"]

var numeric_store: GMNumericResourceStore
var plans: Dictionary = {}
var fail_after_apply_once: bool = false
var fail_commit_code: String = ""
var isolated: bool = false
var isolation_report: Dictionary = {}

func _init(p_store: GMNumericResourceStore = null) -> void:
	resolver_id = "gm.resolver.numeric_resource"
	numeric_store = p_store if p_store != null else GMNumericResourceStore.new()

func preflight_transaction(transaction: GMDomainTransaction) -> Dictionary:
	if isolated: return _blocked("numeric.resolver_isolated", "数值资源Resolver处于恢复失败隔离状态，拒绝正常事务。", isolation_report)
	if transaction == null or transaction.request == null: return _blocked("numeric.request_missing", "数值资源事务缺少请求。")
	var data: Dictionary = transaction.request.event_data.duplicate(true)
	var operation := str(data.get("numeric_operation", data.get("resource_operation", data.get("operation", "")))).strip_edges().to_lower()
	if operation.is_empty() and (data.has("resource_transfers") or data.has("source_account_id")): operation = "transfer"
	if operation.is_empty() or not OPERATIONS.has(operation): return _blocked("numeric.operation_invalid", "数值资源事务操作未注册。", {"operation": operation, "allowed": OPERATIONS})
	var fact_id := str(data.get("planned_fact_event_id", ""))
	if fact_id.is_empty(): fact_id = "gm.fact.numeric.%s" % _slug(transaction.idempotency_key)
	if not fact_id.begins_with("gm.fact."): return _blocked("numeric.fact_id_invalid", "数值资源来源事实必须使用 gm.fact.* 身份。", {"event_id": fact_id})
	var input_rows: Array = _collect_claim_rows(data, ["resource_inputs", "numeric_inputs", "resource_costs"])
	var output_rows: Array = _collect_claim_rows(data, ["resource_outputs", "numeric_outputs", "resource_rewards"])
	for raw_transfer in data.get("resource_transfers", []) if data.get("resource_transfers", []) is Array else []:
		if not raw_transfer is Dictionary: return _blocked("numeric.transfer_invalid", "数值资源转移行必须是对象。")
		input_rows.append({"account_id": raw_transfer.get("source_account_id", ""), "resource_id": raw_transfer.get("resource_id", ""), "amount": raw_transfer.get("amount", raw_transfer.get("quantity", 0))})
		output_rows.append({"account_id": raw_transfer.get("target_account_id", ""), "resource_id": raw_transfer.get("resource_id", ""), "amount": raw_transfer.get("amount", raw_transfer.get("quantity", 0))})
	if input_rows.is_empty() and data.has("source_account_id"):
		input_rows.append({"account_id": data.get("source_account_id", ""), "resource_id": data.get("resource_id", ""), "amount": data.get("amount", data.get("quantity", 0))})
	if output_rows.is_empty() and data.has("target_account_id"):
		output_rows.append({"account_id": data.get("target_account_id", ""), "resource_id": data.get("resource_id", ""), "amount": data.get("amount", data.get("quantity", 0))})
	var inputs := _normalize_rows(input_rows, "input")
	if not inputs.ok: return inputs
	var outputs := _normalize_rows(output_rows, "output")
	if not outputs.ok: return outputs
	if inputs.rows.is_empty() and outputs.rows.is_empty(): return _blocked("numeric.claims_missing", "数值资源事务必须声明输入或输出。")
	var input_totals := _totals(inputs.rows)
	var output_totals := _totals(outputs.rows)
	var account_ids: Array[String] = []
	for account_id in input_totals:
		if not account_ids.has(str(account_id)): account_ids.append(str(account_id))
	for account_id in output_totals:
		if not account_ids.has(str(account_id)): account_ids.append(str(account_id))
	account_ids.sort()
	var plan: Dictionary = {
		"transaction_id": transaction.transaction_id,
		"idempotency_key": transaction.idempotency_key,
		"operation": operation,
		"fact_id": fact_id,
		"base_version": numeric_store.version,
		"snapshot": numeric_store.snapshot(),
		"input_claims": inputs.rows,
		"output_claims": [],
		"resource_inputs": inputs.public_rows,
		"resource_outputs": outputs.public_rows,
		"upserts": [],
		"deletes": [],
		"changeset": [],
		"numeric_changes": [],
				"inputs": _fact_ids(inputs.rows),
				"outputs": _fact_ids(outputs.rows),
		"tags": ["gm.numeric_resource", "gm.numeric_resource.%s" % operation],
		"visibility": {"public": false, "witnesses": []},
		"payload": {"event_id": fact_id, "operation": operation, "numeric_operation": operation, "resource_operation": operation, "resource_inputs": inputs.public_rows, "resource_outputs": outputs.public_rows},
		"mutated": false,
	}
	var expected_versions: Variant = data.get("expected_resource_versions", data.get("expected_account_versions", data.get("expected_versions", {})))
	if expected_versions is Dictionary:
		for account_id in account_ids:
			if not expected_versions.has(account_id): continue
			if typeof(expected_versions[account_id]) != TYPE_INT: return _blocked("numeric.account_version_type_invalid", "数值资源账户版本必须是整数。", {"account_id": account_id})
			var expected_account := numeric_store.get_account(account_id)
			if expected_account == null: return _blocked("numeric.account_missing", "数值资源账户不存在。", {"account_id": account_id})
			if expected_account.account_version != int(expected_versions[account_id]): return _blocked("numeric.account_version_conflict", "数值资源账户版本已变化，拒绝过期请求。", {"account_id": account_id, "expected": int(expected_versions[account_id]), "actual": expected_account.account_version})
	for account_id in account_ids:
		var account := numeric_store.get_account(account_id)
		if account == null: return _blocked("numeric.account_missing", "数值资源账户不存在。", {"account_id": account_id})
		var resource_id := str(account.resource_id)
		var definition := numeric_store.get_definition(resource_id)
		if definition == null: return _blocked("numeric.definition_missing", "数值资源账户引用的Definition不存在。", {"account_id": account_id, "resource_id": resource_id})
		var input_amount := _amount_for(input_totals, account_id)
		var output_amount := _amount_for(output_totals, account_id)
		var delta := output_amount - input_amount
		if delta == 0: continue
		var balance_check := account.can_apply_delta(delta, definition.minimum_value)
		if not balance_check.ok: return _blocked(str(balance_check.get("code", "numeric.balance_invalid")), str(balance_check.get("reason_zh", "数值资源余额或容量不满足事务。")), balance_check)
		var next_account := GMNumericResourceAccount.from_dict(account.to_dict())
		next_account.balance = int(balance_check.balance_after)
		next_account.account_version = account.account_version + 1
		next_account.last_fact_id = fact_id
		_add_upsert(plan, "account", account.account_id, next_account.to_dict())
		var change_id := GMNumericResourceChange.make_id(fact_id, account.account_id, plan.numeric_changes.size() + 1)
		var change := GMNumericResourceChange.new().configure(change_id, fact_id, transaction.transaction_id, _chain_id(transaction), transaction.idempotency_key, operation, account.account_id, account.resource_id, definition.unit_id, delta, account.balance, next_account.balance, account.owner_id, account.holder_id, "数值资源事务已结算。", {"input_amount": input_amount, "output_amount": output_amount})
		var change_check := change.validate()
		if not change_check.ok: return _blocked("numeric.change_invalid", "数值资源变化记录未通过Schema校验。", change_check)
		_add_upsert(plan, "change", change_id, change.to_dict())
		plan.numeric_changes.append(change.to_dict())
		plan.changeset.append({"entity_id": account.account_id, "operation": "numeric.%s" % operation, "field": "balance", "before": account.balance, "after": next_account.balance, "metadata": {"numeric_change_id": change_id, "resource_id": account.resource_id, "unit_id": definition.unit_id}})
	for account_id in output_totals:
		var net_output := _amount_for(output_totals, account_id) - _amount_for(input_totals, account_id)
		if net_output > 0: plan.output_claims.append({"account_id": account_id, "resource_id": _resource_for_claim(outputs.rows, account_id), "amount": net_output})
	plan.payload["numeric_changes"] = plan.numeric_changes.duplicate(true)
	plan.payload["account_count"] = account_ids.size()
	plans[transaction.transaction_id] = plan
	transaction.commit_payload["event_id"] = fact_id
	return {"ok": true, "stage": "PREFLIGHT", "operation": operation, "store_version": numeric_store.version, "inputs": plan.inputs, "outputs": plan.outputs, "changeset": plan.changeset}

func reserve_transaction(transaction: GMDomainTransaction) -> Dictionary:
	var plan: Dictionary = plans.get(transaction.transaction_id, {})
	if plan.is_empty(): return _blocked("numeric.plan_missing", "数值资源事务没有预检计划。")
	var result := numeric_store.reserve(transaction.transaction_id, plan.input_claims, plan.output_claims, int(plan.base_version))
	if not result.ok: return result
	plan["reservation"] = result.get("reservation", {})
	plans[transaction.transaction_id] = plan
	return {"ok": true, "stage": "RESERVE", "reservations": result.get("reservations", [plan.reservation])}

func commit_transaction(transaction: GMDomainTransaction) -> Dictionary:
	var plan: Dictionary = plans.get(transaction.transaction_id, {})
	if plan.is_empty(): return _blocked("numeric.plan_missing", "数值资源事务没有预检计划。")
	if numeric_store.version != int(plan.base_version): return _blocked("numeric.store_version_conflict", "提交前数值资源Store版本已变化，拒绝使用过期计划。", {"expected": plan.base_version, "actual": numeric_store.version})
	if numeric_store.reservation_for(transaction.transaction_id).is_empty(): return _blocked("numeric.reservation_missing", "提交前数值资源预留已丢失。")
	var applied := numeric_store.apply_atomic(plan.upserts, plan.deletes, int(plan.base_version))
	if not applied.ok: return applied
	plan["mutated"] = true
	plans[transaction.transaction_id] = plan
	if not fail_commit_code.is_empty():
		var code := fail_commit_code
		fail_commit_code = ""
		return _blocked(code, "数值资源提交故障注入，事务必须回滚。")
	if fail_after_apply_once:
		fail_after_apply_once = false
		return _blocked("numeric.commit_injected_failure", "数值资源提交后故障注入，事务必须回滚。")
	return {"ok": true, "stage": "COMMIT", "payload": plan.payload, "inputs": plan.inputs, "outputs": plan.outputs, "tags": plan.tags, "visibility": plan.visibility, "changeset": plan.changeset}

func rollback_transaction(transaction: GMDomainTransaction, reason_zh: String) -> Dictionary:
	var plan: Dictionary = plans.get(transaction.transaction_id, {})
	if plan.is_empty():
		numeric_store.release_reservation(transaction.transaction_id)
		return {"ok": true, "stage": "ROLLBACK", "rolled_back": true, "plan_missing": true, "reason_zh": reason_zh}
	var restored := true
	if bool(plan.get("mutated", false)):
		var other_reservations := numeric_store.reservations.duplicate(true)
		var restore_result := numeric_store.restore_snapshot(plan.get("snapshot", {}))
		restored = bool(restore_result.get("ok", false))
		if restored: numeric_store.reservations = other_reservations
	if restored: numeric_store.release_reservation(transaction.transaction_id)
	plans.erase(transaction.transaction_id)
	return {"ok": restored, "stage": "ROLLBACK", "rolled_back": restored, "restored_store": restored, "reason_zh": reason_zh}

func capture_transaction_state(_transaction: GMDomainTransaction) -> Dictionary:
	if isolated: return _blocked("numeric.resolver_isolated", "数值资源Resolver处于隔离状态，不能建立恢复点。", isolation_report)
	return {"ok": true, "contract": "gm.numeric_resource.recovery.v1", "snapshot": {"store": numeric_store.snapshot(), "reservations": GMStableData.clone(numeric_store.reservations)}}

func restore_transaction_state(transaction: GMDomainTransaction, snapshot: Variant) -> Dictionary:
	var shape := _validate_recovery_snapshot(transaction, snapshot)
	if not shape.ok: return shape
	var current := capture_transaction_state(transaction)
	var restored := numeric_store.restore_snapshot(snapshot.store)
	if not restored.ok:
		numeric_store.restore_snapshot(current.snapshot.store)
		numeric_store.reservations = GMStableData.clone(current.snapshot.reservations)
		return _blocked("numeric.recovery_restore_failed", "数值资源Store无法从提交前恢复点还原。", {"restore": restored})
	numeric_store.reservations = GMStableData.clone(snapshot.reservations)
	return {"ok": true, "stage": "RECOVERY", "restored": true, "contract": "gm.numeric_resource.recovery.v1"}

func release_transaction_reservations(transaction: GMDomainTransaction) -> Dictionary:
	if transaction == null: return _blocked("numeric.transaction_missing", "释放数值资源预留需要事务身份。")
	return numeric_store.release_reservation(transaction.transaction_id)

func isolate_transaction_state(transaction: GMDomainTransaction, failure: Dictionary) -> Dictionary:
	isolated = true
	isolation_report = {"transaction_id": transaction.transaction_id if transaction != null else "", "failure": failure.duplicate(true)}
	numeric_store.reservations.clear()
	return {"ok": true, "isolated": true, "resolver_id": resolver_id, "transaction_id": isolation_report.transaction_id}

func finalize_transaction(transaction: GMDomainTransaction) -> Dictionary:
	numeric_store.release_reservation(transaction.transaction_id)
	plans.erase(transaction.transaction_id)
	return {"ok": true, "stage": "FINALIZE", "finalized": true}

func version_for(key: String) -> int:
	if key.is_empty() or key == numeric_store.store_id or key == "numeric" or key == "gm.store.numeric_resource": return numeric_store.version
	var account := numeric_store.get_account(key)
	return account.account_version if account != null else 0

func build_candidate(request: GMAbilityActivationRequest, chain: GMCausalChain) -> GMCandidateResult:
	return GMCandidateResult.from_request(request, chain, 1.0, ["数值资源事务具备统一预检、预留、提交与回滚路径。"])

func planned_transaction_plan(transaction_id: String) -> Dictionary:
	var value: Variant = plans.get(transaction_id, {})
	return value.duplicate(true) if value is Dictionary else {}

func discard_transaction_plan(transaction_id: String) -> void:
	plans.erase(transaction_id)

func _collect_claim_rows(data: Dictionary, keys: Array) -> Array:
	var result: Array = []
	for key in keys:
		var value: Variant = data.get(key, [])
		if value is Array: result.append_array(value)
	return result

func _normalize_rows(rows: Array, side: String) -> Dictionary:
	var totals: Dictionary = {}
	var public_rows: Array = []
	for raw in rows:
		if not raw is Dictionary: return _blocked("numeric.claim_invalid", "数值资源输入/输出行必须是对象。")
		var account_id := str(raw.get("account_id", "")).strip_edges()
		var resource_id := str(raw.get("resource_id", raw.get("resource", ""))).strip_edges()
		var raw_amount: Variant = raw.get("amount", raw.get("quantity", 0))
		if typeof(raw_amount) != TYPE_INT or int(raw_amount) <= 0: return _blocked("numeric.amount_invalid", "数值资源数量必须是正整数。", {"claim": raw})
		if not account_id.begins_with("gm.resource.account.") or not resource_id.begins_with("gm.resource."):
			return _blocked("numeric.claim_identity_invalid", "数值资源输入/输出必须引用稳定账户和资源身份。", {"claim": raw})
		var account := numeric_store.get_account(account_id)
		if account == null: return _blocked("numeric.account_missing", "数值资源账户不存在。", {"account_id": account_id})
		if account.resource_id != resource_id: return _blocked("numeric.resource_mismatch", "数值资源账户与请求资源身份不一致。", {"account_id": account_id, "expected": account.resource_id, "actual": resource_id})
		var key := "%s|%s" % [account_id, resource_id]
		totals[key] = int(totals.get(key, 0)) + int(raw_amount)
		public_rows.append({"account_id": account_id, "resource_id": resource_id, "amount": int(raw_amount), "side": side})
	var collapsed: Array = []
	for key in totals:
		var parts := str(key).split("|", false, 1)
		collapsed.append({"account_id": parts[0], "resource_id": parts[1], "amount": int(totals[key]), "side": side})
	collapsed.sort_custom(func(left: Dictionary, right: Dictionary): return "%s|%s" % [left.account_id, left.resource_id] < "%s|%s" % [right.account_id, right.resource_id])
	return {"ok": true, "rows": collapsed, "public_rows": public_rows}

func _totals(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for row in rows:
		var account_id := str(row.get("account_id", ""))
		result[account_id] = int(result.get(account_id, 0)) + int(row.get("amount", 0))
	return result

func _amount_for(totals: Dictionary, account_id: String) -> int:
	return int(totals.get(account_id, 0))

func _resource_for_claim(rows: Array, account_id: String) -> String:
	for row in rows:
		if str(row.get("account_id", "")) == account_id: return str(row.get("resource_id", ""))
	return ""

func _fact_ids(rows: Array) -> Array:
	var result: Array = []
	for row in rows:
		for value in [str(row.get("account_id", "")), str(row.get("resource_id", ""))]:
			if not value.is_empty() and not result.has(value): result.append(value)
	return result

func _add_upsert(plan: Dictionary, kind: String, record_id: String, value: Dictionary) -> void:
	var row := {"kind": kind, "id": record_id, "value": value.duplicate(true)}
	for index in plan.upserts.size():
		if str(plan.upserts[index].get("kind", "")) == kind and str(plan.upserts[index].get("id", "")) == record_id:
			plan.upserts[index] = row
			return
	plan.upserts.append(row)

func _validate_recovery_snapshot(transaction: GMDomainTransaction, value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() != 2 or not value.has("store") or not value.has("reservations") or not value.store is Dictionary or not value.reservations is Dictionary:
		return _blocked("numeric.recovery_snapshot_invalid", "数值资源恢复点结构无效。")
	if transaction != null:
		var reservations: Dictionary = value.reservations
		var transaction_id := transaction.transaction_id
		for key in reservations:
			if not reservations[key] is Dictionary or str(reservations[key].get("transaction_id", "")) != str(key): return _blocked("numeric.recovery_reservation_invalid", "数值资源恢复点包含未绑定事务的预留。")
		if reservations.has(transaction_id) and str(reservations[transaction_id].get("transaction_id", "")) != transaction_id: return _blocked("numeric.recovery_reservation_invalid", "数值资源恢复点事务身份不一致。")
	var stable := GMStableData.validate_persistence(value.reservations)
	if not stable.ok: return _blocked("numeric.recovery_reservation_invalid", "数值资源恢复点包含不可保存值。", stable)
	return {"ok": true}

func _chain_id(transaction: GMDomainTransaction) -> String:
	return transaction.chain.chain_id if transaction != null and transaction.chain != null else "gm.causal.chain.%s" % transaction.transaction_id.sha256_text()

func _blocked(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	result.merge(details, true)
	return result

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in raw.length():
		var code := raw.unicode_at(index)
		result += raw.substr(index, 1) if ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45) else "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_") if not result.is_empty() else "numeric"
