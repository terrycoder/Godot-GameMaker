class_name GMDomainTransactionCoordinator
extends RefCounted

## 统一驱动领域事务，并在提交成功后创建 FactEvent、ChangeRecord 与 Cue。

var active_transactions: Dictionary = {}
var completed_by_key: Dictionary = {}
var transaction_log: Array[Dictionary] = []
var quarantined_resolvers: Dictionary = {}

func candidate(request: GMAbilityActivationRequest, resolver: Object, chain: GMCausalChain = null, score: float = 0.0, reasons: Array = []) -> GMCandidateResult:
	var candidate_chain := chain if chain != null else GMCausalChain.from_activation_request(request)
	if resolver != null and resolver.has_method("build_candidate"):
		var value: Variant = resolver.call("build_candidate", request, candidate_chain)
		if value is GMCandidateResult: return value
	var result := GMCandidateResult.from_request(request, candidate_chain, score, reasons if not reasons.is_empty() else ["候选尚未进入领域提交。"])
	return result

func resolve(request: GMAbilityActivationRequest, resolver: Object, fact_store: GMFactEventStore, change_store: GMChangeRecordStore, metadata: Dictionary = {}, chain: GMCausalChain = null) -> Variant:
	var causal_chain := chain if chain != null else GMCausalChain.from_activation_request(request)
	var basic := _validate_inputs(request, resolver, fact_store, change_store, causal_chain, metadata)
	if not basic.ok: return GMBlockedResult.from_failure(basic, request, causal_chain)
	var resolver_id := str(metadata.get("resolver_id", resolver.get("resolver_id") if resolver.get("resolver_id") != null else ""))
	if quarantined_resolvers.has(resolver_id):
		return _blocked("transaction.resolver_quarantined", "领域 Resolver 因恢复失败已隔离，拒绝继续读取或提交正常世界事务。", request, causal_chain, quarantined_resolvers[resolver_id])
	var idempotency_key := request.idempotency_key if request != null and not request.idempotency_key.is_empty() else request.request_id
	var existing: GMFactEvent = fact_store.get_by_idempotency(idempotency_key)
	if existing != null:
		if _same_identity(existing, request, metadata):
			var idempotent_result:=fact_store.make_committed_result(existing.event_id,true)
			if idempotent_result==null:return _blocked("transaction.authority_package_missing","既有Fact缺少权威提交包，不能作为幂等提交结果返回。",request,causal_chain,{"fact_event_id":existing.event_id})
			transaction_log.append({"result_kind": "committed_fact", "idempotent": true, "fact_event_id": existing.event_id, "idempotency_key": idempotency_key})
			return idempotent_result
		var conflict := GMBlockedResult.new("transaction.idempotency_conflict", "幂等键已用于不同领域事实，拒绝覆盖既有提交。", _source_id(request), _target_id(request), causal_chain, {"action": "使用新的幂等键或读取既有事实。"})
		conflict.details = {"existing_fact": existing.to_dict(), "idempotency_key": idempotency_key}
		return conflict
	var reward_receipt_id := str(request.event_data.get("reward_receipt_id", "")).strip_edges()
	if not reward_receipt_id.is_empty():
		var existing_receipt: GMFactEvent = _find_reward_receipt_fact(fact_store, reward_receipt_id)
		if existing_receipt != null:
			if not _same_reward_receipt_identity(existing_receipt, request, metadata, reward_receipt_id):
				return _blocked("transaction.reward_receipt_conflict", "奖励收据身份已对应不同奖励请求，拒绝重复发奖。", request, causal_chain, {"reward_receipt_id": reward_receipt_id, "existing_fact_id": existing_receipt.event_id})
			var receipt_result: GMCommittedFactResult = fact_store.make_committed_result(existing_receipt.event_id, true)
			if receipt_result == null:
				return _blocked("transaction.authority_package_missing", "既有奖励收据缺少权威提交包，不能作为幂等结果返回。", request, causal_chain, {"reward_receipt_id": reward_receipt_id, "fact_event_id": existing_receipt.event_id})
			transaction_log.append({"result_kind": "committed_fact", "idempotent": true, "reward_receipt_id": reward_receipt_id, "fact_event_id": existing_receipt.event_id})
			return receipt_result
	var fact_type := str(metadata.get("fact_type", ""))
	var source_system := str(metadata.get("source_system", "gm.domain"))
	var transaction := GMDomainTransaction.new(request, causal_chain, resolver_id, fact_type, source_system)
	transaction.ability_instance_id = str(metadata.get("ability_instance_id", transaction.ability_instance_id))
	active_transactions[transaction.transaction_id] = transaction
	var request_ref := request.request_id
	var ability_instance_id := str(metadata.get("ability_instance_id", ""))
	var prefix_check := causal_chain.validate_activation_prefix(request_ref, ability_instance_id)
	if not prefix_check.ok:
		active_transactions.erase(transaction.transaction_id)
		return _blocked("causal.activation_prefix_invalid", "领域事务因果链不属于当前 Request/AbilityInstance，已在变更前拒绝。", request, causal_chain, prefix_check)
	var resolver_ref := GMCausalRef.resolver(resolver_id)
	var resolver_link := causal_chain.add_ref(resolver_ref, [ability_instance_id])
	if not resolver_link.ok:
		active_transactions.erase(transaction.transaction_id)
		return _blocked("causal.resolver_link_failed", "无法把 DomainResolver 接入 ActivationRequest 因果链。", request, causal_chain, resolver_link)
	var transaction_ref := GMCausalRef.transaction(transaction.transaction_id, resolver_id)
	var transaction_link := causal_chain.add_ref(transaction_ref, [resolver_id])
	if not transaction_link.ok:
		active_transactions.erase(transaction.transaction_id)
		return _blocked("causal.transaction_link_failed", "无法把 DomainTransaction 接入因果链。", request, causal_chain, transaction_link)
	var ownership_check := _validate_linked_prefix(causal_chain, request_ref, ability_instance_id, resolver_id, transaction.transaction_id)
	if not ownership_check.ok:
		active_transactions.erase(transaction.transaction_id)
		return _blocked("causal.transaction_ownership_invalid", "因果链阶段归属不一致，已在领域变更前拒绝。", request, causal_chain, ownership_check)
	var downstream_link_check := _preflight_downstream_links(causal_chain, transaction)
	if not downstream_link_check.ok:
		active_transactions.erase(transaction.transaction_id)
		return _blocked("causal.downstream_link_preflight_failed", "Fact/Change/Cue因果链接能力预检失败，已在领域变更前拒绝。", request, causal_chain, downstream_link_check)
	var recovery_prepared := transaction.prepare_recovery(resolver)
	if not recovery_prepared.ok:
		active_transactions.erase(transaction.transaction_id)
		return _blocked(str(recovery_prepared.get("code", "transaction.recovery_snapshot_failed")), str(recovery_prepared.get("reason_zh", "领域事务恢复点建立失败。")), request, causal_chain, recovery_prepared)
	var preflight := transaction.preflight(resolver)
	if not preflight.ok: return _finish_failure(transaction, resolver, request, causal_chain, preflight)
	var reserved := transaction.reserve(resolver)
	if not reserved.ok: return _finish_failure(transaction, resolver, request, causal_chain, reserved)
	var committed := transaction.commit(resolver)
	if not committed.ok: return _finish_failure(transaction, resolver, request, causal_chain, committed)
	var fact := _build_fact(transaction, request, metadata)
	if fact == null:
		return _finish_failure(transaction, resolver, request, causal_chain, {"ok": false, "code": "transaction.fact_build_failed", "reason_zh": "提交成功但无法建立 FactEvent，事务将回滚。"})
	fact.causes = _chain_ids(causal_chain)
	var fact_link := causal_chain.add_ref(GMCausalRef.fact(fact.event_id, fact.type), [transaction.transaction_id])
	if not fact_link.ok:
		return _finish_failure(transaction, resolver, request, causal_chain, {"ok": false, "code": "causal.fact_link_failed", "reason_zh": "无法把 FactEvent 接入当前事务因果链。", "details": fact_link})
	fact.causal_chain_id = causal_chain.chain_id
	var change_records := _build_changes(transaction, fact)
	for record in change_records:
		var change_link := causal_chain.add_ref(GMCausalRef.change(record.change_id, fact.event_id), [fact.event_id])
		if not change_link.ok:
			return _finish_failure(transaction, resolver, request, causal_chain, {"ok": false, "code": "causal.change_link_failed", "reason_zh": "无法把 ChangeRecord 接入当前 FactEvent 因果链。", "details": change_link})
	var normalized_cues := _normalize_cues(committed.get("cues", metadata.get("cues", [])), transaction.ability_instance_id)
	for cue_value in normalized_cues:
		var cue_id := str(cue_value.get("cue_id", ""))
		if cue_id.is_empty(): continue
		var cue_ref:=GMCausalRef.cue(cue_id,transaction.ability_instance_id)
		cue_ref.metadata["payload_hash"]=JSON.stringify(GMStableData.persistence_canonical(cue_value.get("parameters",{})),"",true,true).sha256_text()
		var cue_link := causal_chain.add_ref(cue_ref, [fact.event_id])
		if not cue_link.ok:
			return _finish_failure(transaction, resolver, request, causal_chain, {"ok": false, "code": "causal.cue_link_failed", "reason_zh": "无法把 Cue 接入当前 FactEvent 因果链。", "details": cue_link})
	var append_result := fact_store.append_committed(fact,change_records,{"chain":causal_chain.to_dict(),"cues":normalized_cues})
	if not append_result.ok:
		return _finish_failure(transaction, resolver, request, causal_chain, {"ok": false, "code": "transaction.fact_append_failed", "reason_zh": "FactEvent/ChangeRecord 原子写入失败，事务将回滚。", "append_result": append_result})
	var mark := transaction.mark_committed({"fact_event_id": fact.event_id, "change_count": change_records.size()})
	if not mark.ok: return _finish_failure(transaction, resolver, request, causal_chain, mark)
	if resolver.has_method("finalize_transaction"):
		var finalized_value: Variant = resolver.call("finalize_transaction", transaction)
		if finalized_value is Dictionary and not bool(finalized_value.get("ok", true)):
			transaction_log.append({"result_kind": "finalize_warning", "transaction_id": transaction.transaction_id, "details": finalized_value.duplicate(true)})
	active_transactions.erase(transaction.transaction_id)
	completed_by_key[idempotency_key] = transaction.transaction_id
	# 返回与Store内部对象隔离的副本；权威内容只从同一FactEventStore提交包读取。
	var result:=fact_store.make_committed_result(fact.event_id,false)
	if result==null:return _finish_failure(transaction,resolver,request,causal_chain,{"ok":false,"code":"transaction.authority_package_missing","reason_zh":"提交完成但权威提交包不可读取。"})
	transaction_log.append({"result_kind": "committed_fact", "transaction": transaction.to_dict(), "result": result.to_dict()})
	return result

func _finish_failure(transaction: GMDomainTransaction, resolver: Object, request: GMAbilityActivationRequest, chain: GMCausalChain, failure: Dictionary) -> GMBlockedResult:
	var rollback := transaction.rollback(resolver, str(failure.get("reason_zh", "事务阶段失败，执行回滚。")))
	var release: Dictionary = {}
	var recovery: Dictionary = {}
	if rollback.ok:
		release = transaction.ensure_reservations_released(resolver)
		if not release.ok:
			recovery = transaction.recover_after_rollback_failure(resolver, {"ok": false, "code": "transaction.reservation_release_failed", "release": release})
	else:
		recovery = transaction.recover_after_rollback_failure(resolver, rollback)
	active_transactions.erase(transaction.transaction_id)
	var blocked: GMBlockedResult
	if not rollback.ok or not release.is_empty() and not release.ok:
		if bool(recovery.get("ok", false)):
			blocked = GMBlockedResult.new("transaction.rollback_failed", "普通回滚失败；已从提交前恢复点还原领域状态并释放预留。", _source_id(request), _target_id(request), chain, {"action": "修复普通回滚实现后可重试。"})
		else:
			var resolver_id := transaction.resolver_id
			var isolation: Dictionary = {"ok": false, "code": "transaction.isolation_contract_missing"}
			if resolver != null and is_instance_valid(resolver) and resolver.has_method("isolate_transaction_state"):
				var isolation_value: Variant = resolver.call("isolate_transaction_state", transaction, {"failure": failure, "rollback": rollback, "recovery": recovery})
				if isolation_value is Dictionary: isolation = isolation_value.duplicate(true)
			var quarantine := {"transaction_id": transaction.transaction_id, "failure": failure.duplicate(true), "rollback": rollback.duplicate(true), "recovery": recovery.duplicate(true), "isolation": isolation}
			quarantined_resolvers[resolver_id] = quarantine
			blocked = GMBlockedResult.new("transaction.recovery_failed_quarantined", "普通回滚与强制恢复均失败；Resolver已隔离，禁止继续正常事务。", _source_id(request), _target_id(request), chain, {"action": "替换或修复 Resolver 并显式解除隔离。"})
	else:
		blocked = GMBlockedResult.new(str(failure.get("code", "transaction.blocked")), str(failure.get("reason_zh", "领域事务未提交。")), _source_id(request), _target_id(request), chain, _fix_for(failure))
	blocked.rollback_report = {"ok": bool(rollback.get("ok", false)), "state": transaction.state, "ordinary_rollback": rollback.duplicate(true), "reservation_release": release.duplicate(true), "recovery": recovery.duplicate(true), "recovered": bool(recovery.get("ok", false))}
	blocked.transaction_id = transaction.transaction_id
	blocked.details = {"failure": failure.duplicate(true), "transaction": transaction.to_dict(), "rollback": rollback.duplicate(true), "reservation_release": release.duplicate(true), "recovery": recovery.duplicate(true)}
	transaction_log.append({"result_kind": "blocked", "transaction": transaction.to_dict(), "result": blocked.to_dict()})
	return blocked

func _validate_inputs(request: GMAbilityActivationRequest, resolver: Object, fact_store: GMFactEventStore, change_store: GMChangeRecordStore, chain: GMCausalChain, metadata: Dictionary) -> Dictionary:
	if request == null: return {"ok": false, "code": "transaction.request_missing", "reason_zh": "领域事务缺少 ActivationRequest。", "fix": {"action": "从统一能力入口创建请求。"}}
	if resolver == null or not is_instance_valid(resolver): return {"ok": false, "code": "transaction.resolver_missing", "reason_zh": "领域事务缺少 DomainResolver。", "fix": {"action": "注册可用的领域 Resolver。"}}
	if fact_store == null or change_store == null: return {"ok": false, "code": "transaction.store_missing", "reason_zh": "领域事务缺少 Fact/Change 只追加写入器。", "fix": {"action": "安装事实账本和变更账本。"}}
	if chain == null or not chain.validate().ok: return {"ok": false, "code": "transaction.chain_invalid", "reason_zh": "领域事务缺少有效因果链。", "fix": {"action": "从 ActivationRequest 创建 GMCausalChain。"}}
	var ability_instance_id := str(metadata.get("ability_instance_id", ""))
	if ability_instance_id.is_empty() or not ability_instance_id.begins_with("gm.ability.instance.v2."):
		return {"ok": false, "code": "transaction.ability_instance_identity_invalid", "reason_zh": "领域事务必须使用 Host 分配的 v2 AbilityInstance 身份。"}
	var fact_type := str(metadata.get("fact_type", ""))
	if fact_type.is_empty() or not fact_type.begins_with("gm.fact."): return {"ok": false, "code": "transaction.fact_type_invalid", "reason_zh": "领域事务必须声明 gm.fact.* 类型。", "fix": {"action": "在能力定义中配置稳定 Fact 类型。"}}
	if not resolver.has_method("preflight_transaction") or not resolver.has_method("reserve_transaction") or not resolver.has_method("commit_transaction") or not resolver.has_method("rollback_transaction") or not resolver.has_method("capture_transaction_state") or not resolver.has_method("restore_transaction_state") or not resolver.has_method("release_transaction_reservations") or not resolver.has_method("isolate_transaction_state"):
		return {"ok": false, "code": "transaction.resolver_interface_missing", "reason_zh": "领域 Resolver 必须实现预检、预留、提交、回滚、恢复快照与预留释放接口。", "fix": {"action": "继承 GMDomainResolver 并实现完整事务恢复合同。"}}
	return {"ok": true}

func _validate_linked_prefix(chain: GMCausalChain, request_id: String, instance_id: String, resolver_id: String, transaction_id: String) -> Dictionary:
	if chain == null: return {"ok": false, "code": "causal.chain_missing"}
	var structural := chain.validate()
	if not structural.ok: return structural
	var expected := [
		{"id": request_id, "kind": "activation_request"},
		{"id": instance_id, "kind": "ability_instance"},
		{"id": resolver_id, "kind": "domain_resolver"},
		{"id": transaction_id, "kind": "domain_transaction"},
	]
	if chain.refs_by_id.size() != expected.size() or chain.links.size() != expected.size() - 1:
		return {"ok": false, "code": "causal.stage_shape_invalid", "ref_count": chain.refs_by_id.size(), "link_count": chain.links.size()}
	for row in expected:
		var ref: GMCausalRef = chain.get_ref(str(row.id))
		if ref == null or ref.kind != str(row.kind): return {"ok": false, "code": "causal.stage_identity_mismatch", "expected": row}
	if not chain.has_direct_link(request_id, instance_id) or not chain.has_direct_link(instance_id, resolver_id) or not chain.has_direct_link(resolver_id, transaction_id):
		return {"ok": false, "code": "causal.stage_order_invalid"}
	return {"ok": true}

func _preflight_downstream_links(chain: GMCausalChain, transaction: GMDomainTransaction) -> Dictionary:
	var preview := chain.clone()
	var fact_id := "gm.fact.preview.%s" % transaction.transaction_id.sha256_text()
	var change_id := "gm.change.preview.%s" % transaction.transaction_id.sha256_text()
	var cue_id := "gm.cue.preview.%s" % transaction.transaction_id.sha256_text()
	var stages := [
		{"stage": "fact", "ref": GMCausalRef.fact(fact_id, transaction.fact_type), "parents": [transaction.transaction_id]},
		{"stage": "change", "ref": GMCausalRef.change(change_id, fact_id), "parents": [fact_id]},
		{"stage": "cue", "ref": GMCausalRef.cue(cue_id, transaction.ability_instance_id), "parents": [fact_id]},
	]
	for row in stages:
		var result: Dictionary = preview.add_ref(row.ref, row.parents)
		if not result.ok: return {"ok": false, "code": "causal.%s_link_preflight_failed" % str(row.stage), "stage": row.stage, "details": result}
	return {"ok": true}

func _build_fact(transaction: GMDomainTransaction, request: GMAbilityActivationRequest, metadata: Dictionary) -> GMFactEvent:
	var fact := GMFactEvent.new()
	var fact_options := {
		"targets": transaction.commit_payload.get("targets", [_target_id(request)]) if transaction.commit_payload is Dictionary else [_target_id(request)],
		"inputs": transaction.commit_inputs,
		"outputs": transaction.commit_outputs,
		"tags": transaction.commit_tags,
		"visibility": transaction.commit_visibility,
		"payload": transaction.commit_payload,
		"causal_chain_id": transaction.chain.chain_id if transaction.chain != null else ""
	}
	if transaction.commit_payload.has("timestamp_usec"): fact_options["timestamp_usec"] = int(transaction.commit_payload.get("timestamp_usec", 0))
	fact.configure(1, transaction.fact_type, _source_id(request), transaction.source_system, transaction.ability_id, transaction.ability_instance_id, transaction.resolver_id, transaction.transaction_id, transaction.idempotency_key, fact_options)
	if transaction.commit_payload.has("timestamp_usec"): fact.timestamp_usec = int(transaction.commit_payload.get("timestamp_usec", 0))
	fact.mark_committed(transaction.transaction_id, GMFactEvent._get_commit_capability())
	if transaction.commit_payload.get("event_id", "") is String and not str(transaction.commit_payload.get("event_id", "")).is_empty(): fact.event_id = str(transaction.commit_payload.get("event_id"))
	if transaction.commit_payload.has("time"): fact.time = str(transaction.commit_payload.get("time"))
	return fact

func _build_changes(transaction: GMDomainTransaction, fact: GMFactEvent) -> Array:
	var result: Array = []
	var drafts := transaction.changeset.duplicate(true)
	if drafts.is_empty():
		drafts.append({"entity_id": _source_id(transaction.request), "operation": "transaction.commit", "field": "state", "before": null, "after": transaction.commit_outputs.duplicate(true)})
	var index := 1
	for draft in drafts:
		if draft is GMChangeRecord:
			var record: GMChangeRecord = draft
			if record.fact_event_id.is_empty(): record.fact_event_id = fact.event_id
			if record.transaction_id.is_empty(): record.transaction_id = transaction.transaction_id
			if record.idempotency_key.is_empty() or record.idempotency_key == transaction.idempotency_key: record.idempotency_key = "%s.change.%d" % [transaction.idempotency_key, index]
			if record.causal_chain_id.is_empty(): record.causal_chain_id = transaction.chain.chain_id
			if record.sequence < 1: record.sequence = index
			if record.change_id.is_empty(): record.change_id = GMChangeRecord.make_change_id(fact.event_id, record.idempotency_key, index)
			result.append(record)
		else:
			result.append(GMChangeRecord.from_draft(draft if draft is Dictionary else {}, index, fact.event_id, transaction.transaction_id, "%s.change.%d" % [transaction.idempotency_key, index], transaction.chain.chain_id))
		index += 1
	return result

func _same_identity(existing: GMFactEvent, request: GMAbilityActivationRequest, metadata: Dictionary) -> bool:
	if existing.ability_id != str(request.ability_id) or existing.resolver_id != str(metadata.get("resolver_id", existing.resolver_id)) or existing.type != str(metadata.get("fact_type", existing.type)):
		return false
	if existing.actor != _source_id(request) or not existing.targets.has(_target_id(request)):
		return false
	var request_data: Dictionary = request.event_data if request != null else {}
	# Resolver-owned pure requests are part of the idempotency identity. This
	# keeps the coordinator generic while allowing P22 (and future resolvers)
	# to reject same-key requests whose domain payload differs.
	var existing_domain_request: Variant = existing.payload.get("combat_request", null) if existing.payload is Dictionary else null
	var request_domain_request: Variant = request_data.get("combat_request", null)
	if existing_domain_request != null or request_domain_request != null:
		if not existing_domain_request is Dictionary or not request_domain_request is Dictionary:
			return false
		if GMStableData.persistence_canonical_json(existing_domain_request) != GMStableData.persistence_canonical_json(request_domain_request):
			return false
	for key in ["source_id", "target_id", "amount", "quantity", "operation"]:
		if request_data.has(key):
			if not existing.payload.has(key) or not _same_value(request_data[key], existing.payload[key]): return false
	return true

func _find_reward_receipt_fact(fact_store: GMFactEventStore, reward_receipt_id: String) -> GMFactEvent:
	if fact_store == null or reward_receipt_id.is_empty(): return null
	for fact in fact_store.records:
		if fact == null or not fact.payload is Dictionary: continue
		if str(fact.payload.get("reward_receipt_id", "")) == reward_receipt_id:
			return fact_store.get_by_id(fact.event_id)
	return null

func _same_reward_receipt_identity(existing: GMFactEvent, request: GMAbilityActivationRequest, metadata: Dictionary, reward_receipt_id: String) -> bool:
	if existing == null or request == null or not existing.payload is Dictionary: return false
	if str(existing.payload.get("reward_receipt_id", "")) != reward_receipt_id: return false
	if str(existing.payload.get("reward_id", "")) != str(request.event_data.get("reward_id", "")): return false
	return _same_identity(existing, request, metadata)

func _same_value(left: Variant, right: Variant) -> bool:
	if left is float or right is float:
		return is_equal_approx(float(left), float(right))
	return left == right

func _blocked(code: String, reason_zh: String, request: GMAbilityActivationRequest, chain: GMCausalChain, details: Dictionary) -> GMBlockedResult:
	var result := GMBlockedResult.new(code, reason_zh, _source_id(request), _target_id(request), chain, {"action": "修复因果链后重试。"})
	result.details = details.duplicate(true)
	return result

func _fix_for(failure: Dictionary) -> Dictionary:
	var value: Variant = failure.get("fix", {"action": "检查领域前置条件、冲突和预留状态。"})
	return value if value is Dictionary else {"action": str(value)}

func _source_id(request: GMAbilityActivationRequest) -> String:
	if request == null: return ""
	return str(request.event_data.get("source_id", request.source))

func _target_id(request: GMAbilityActivationRequest) -> String:
	if request == null: return ""
	if request.target_data != null and not request.target_data.target_business_id.is_empty(): return request.target_data.target_business_id
	return str(request.event_data.get("target_id", ""))

func _chain_ids(chain: GMCausalChain) -> Array:
	var ids: Array = []
	for ref_value in chain.to_dict().get("refs", []): ids.append(str(ref_value.get("stable_id", "")))
	return ids

func _normalize_cues(value: Variant, instance_id: String) -> Array:
	var result: Array = []
	if not value is Array: return result
	for cue_value in value:
		if cue_value is String: result.append({"cue_id": cue_value, "instance_id": instance_id, "parameters": {}})
		elif cue_value is Dictionary:
			var parameters:Variant=cue_value.get("parameters",{})
			if parameters is Dictionary:result.append({"cue_id":str(cue_value.get("cue_id","")),"instance_id":instance_id,"parameters":parameters.duplicate(true)})
	return result
