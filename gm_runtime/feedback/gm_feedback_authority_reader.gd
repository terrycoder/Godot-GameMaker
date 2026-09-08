class_name GMFeedbackAuthorityReader
extends RefCounted

## Upstream P16/P17 authority reader.  The mapper host uses it to verify a Fact
## ID or committed result; this reader never crosses the P18 presentation-only
## boundary, and P18 never treats it as a playback capability.

const PACKAGE_SCHEMA := "gm.fact.commit_package.v1"

## The public property is retained for compatibility, but it is only a
## construction-time binding surface.  All authority reads use the private
## retained capability, never a caller-provided store alias.
var _fact_store_bound := false
var _bound_fact_store: GMFactEventStore
var _bound_fact_store_identity: int = 0
var fact_store: GMFactEventStore:
	get:
		return _bound_fact_store
	set(value):
		if _fact_store_bound:
			return
		_fact_store_bound = true
		if value is GMFactEventStore:
			_bound_fact_store = value
			_bound_fact_store_identity = value.get_instance_id()

func _init(p_fact_store: GMFactEventStore = null) -> void:
	fact_store = p_fact_store

## Verify that the retained FactEventStore capability is still the identity
## captured at initialization.  This is deliberately checked at every
## authority boundary so a stale or externally mutated backing alias cannot
## become effective.
func validate_capability() -> Dictionary:
	if not _fact_store_bound or _bound_fact_store == null:
		return _failure("feedback.authority_store_missing", "反馈权威读取器未连接 FactEventStore。")
	if not is_instance_valid(_bound_fact_store) or _bound_fact_store.get_instance_id() != _bound_fact_store_identity:
		return _failure("feedback.authority_store_identity_changed", "反馈权威读取器绑定的FactEventStore身份已失配。", {"bound_store_identity": _bound_fact_store_identity})
	return {"ok": true, "reader": self, "store": _bound_fact_store, "store_identity": _bound_fact_store_identity}

func read_fact(event_id: String) -> Dictionary:
	var capability := validate_capability()
	if not capability.ok:
		return capability
	if not GMFeedbackValidation.stable_id(event_id):
		return _failure("feedback.authority_fact_id_invalid", "反馈来源必须是稳定 FactEvent ID。")
	var store: GMFactEventStore = capability.store
	var package := store.get_committed_package(event_id)
	if package.is_empty():
		return _failure("feedback.authority_package_missing", "指定 Fact 没有可验证的权威提交包。", {"fact_event_id": event_id})
	return _verify_package(event_id, package, store)

func read_result(result: Variant) -> Dictionary:
	if not result is GMCommittedFactResult:
		return _failure("feedback.authority_result_required", "语义反馈只接受 GMCommittedFactResult，不接受候选或手写Dictionary。")
	var capability := validate_capability()
	if not capability.ok:
		return capability
	var store: GMFactEventStore = capability.store
	var committed: GMCommittedFactResult = result
	if committed.authority_store == null or committed.authority_store != store:
		return _failure("feedback.authority_store_mismatch", "CommittedFactResult必须来自当前唯一权威 FactEventStore。")
	if committed.fact_event == null or not GMFeedbackValidation.stable_id(committed.fact_event.event_id):
		return _failure("feedback.authority_result_fact_missing", "CommittedFactResult缺少可验证 FactEvent。")
	var read := read_fact(committed.fact_event.event_id)
	if not read.ok:
		return read
	var package: Dictionary = read.package
	if package.fact != committed.fact_event.to_dict() or package.changes != _change_dicts(committed.change_records) or package.chain != committed.chain.to_dict() or package.transaction_id != committed.transaction_id or package.cues != committed.cues:
		return _failure("feedback.authority_result_stale", "CommittedFactResult与权威提交包逐值不一致，拒绝使用陈旧副本。", {"fact_event_id": committed.fact_event.event_id})
	return read

## Attention is accepted only when the supplied projection is the exact current
## P17 projection and every selected row is rooted in the current P16 Fact.
## The digest is the projection version at this read-only boundary; no second
## Attention or domain store is created here.
func validate_attention_projection(event_id: String, target_ref: String, requested: Variant, current: Variant) -> Dictionary:
	if requested is Dictionary and requested.is_empty():
		return {"ok": true, "value": {}, "projection_version": ""}
	var capability := validate_capability()
	if not capability.ok:
		return _failure("feedback.attention_authority_missing", "Attention互证未连接P16 FactEventStore。", capability)
	if not GMFeedbackValidation.stable_id(event_id) or not GMFeedbackValidation.stable_id(target_ref):
		return _failure("feedback.attention_identity_invalid", "Attention互证的Fact或目标身份无效。")
	if not requested is Dictionary:
		return _failure("feedback.attention_projection_invalid", "Attention请求必须是Dictionary投影。")
	var requested_check := GMAttentionBudget.validate_projection(requested)
	if not requested_check.ok:
		return _failure("feedback.attention_projection_invalid", "Attention请求未通过P17结构校验。", requested_check)
	if not current is Dictionary or current.is_empty():
		return _failure("feedback.attention_projection_missing", "当前P17 Attention投影缺失，拒绝使用调用者提供的投影。")
	var current_check := GMAttentionBudget.validate_projection(current)
	if not current_check.ok:
		return _failure("feedback.attention_projection_current_invalid", "当前P17 Attention投影本身无效，拒绝继续。", current_check)
	var requested_projection: Dictionary = requested_check.value
	var current_projection: Dictionary = current_check.value
	var requested_version := GMStableData.digest(requested_projection)
	var current_version := GMStableData.digest(current_projection)
	if requested_version != current_version or requested_projection != current_projection:
		return _failure("feedback.attention_projection_stale", "Attention投影不是当前P17投影版本，拒绝陈旧或跨实例副本。", {"requested_version": requested_version, "current_version": current_version})
	var authority := read_fact(event_id)
	if not authority.ok:
		return authority
	var fact: GMFactEvent = authority.fact
	var target_ids := _fact_target_ids(fact)
	if not target_ids.has(target_ref):
		return _failure("feedback.attention_cross_object", "Attention目标不在当前P16 Fact权威目标集合中。", {"fact_event_id": event_id, "target_id": target_ref})
	var initiator_ids := _fact_initiator_ids(fact)
	for raw in current_projection.selected:
		if not raw is Dictionary:
			return _failure("feedback.attention_projection_invalid", "当前P17 Attention选中项不是Dictionary。")
		var row: Dictionary = raw
		var source_ids := _fact_source_ids(fact, row.source_kind)
		if not source_ids.has(row.source_id):
			return _failure("feedback.attention_source_stale", "Attention来源未与当前P16 Fact逐值互证，拒绝缺失、陈旧或跨来源引用。", {"fact_event_id": event_id, "source_kind": row.source_kind, "source_id": row.source_id})
		if not initiator_ids.has(row.initiator_id) or row.target_id != target_ref:
			return _failure("feedback.attention_cross_object", "Attention发起者或目标与当前P16 Fact对象不一致。", {"fact_event_id": event_id, "initiator_id": row.initiator_id, "target_id": row.target_id})
	return {"ok": true, "value": current_projection.duplicate(true), "projection_version": current_version, "source_fact_id": fact.event_id}

func _fact_target_ids(fact: GMFactEvent) -> Dictionary:
	var result := {}
	for target in fact.targets:
		if GMFeedbackValidation.stable_id(target):
			result[str(target)] = true
	if fact.payload is Dictionary:
		for key in ["target_id", "target_ref"]:
			var value: Variant = fact.payload.get(key, "")
			if GMFeedbackValidation.stable_id(value):
				result[str(value)] = true
	return result

func _fact_initiator_ids(fact: GMFactEvent) -> Dictionary:
	var result := {}
	if GMFeedbackValidation.stable_id(fact.actor):
		result[fact.actor] = true
	for input in fact.inputs:
		if GMFeedbackValidation.stable_id(input):
			result[str(input)] = true
	if fact.payload is Dictionary:
		for key in ["source_id", "initiator_id"]:
			var value: Variant = fact.payload.get(key, "")
			if GMFeedbackValidation.stable_id(value):
				result[str(value)] = true
	return result

func _fact_source_ids(fact: GMFactEvent, source_kind: String) -> Dictionary:
	var result := {}
	if source_kind == "fact":
		result[fact.event_id] = true
		return result
	var keys: Array = []
	if source_kind == "task":
		keys = ["task_id", "assignment_id", "reservation_id", "source_task_id"]
	elif source_kind == "plan":
		keys = ["plan_id", "execution_plan_id", "source_plan_id"]
	else:
		return result
	# Do not treat generic Fact targets (usually actor/object IDs) as typed
	# Task/Plan authority.  Each kind is intentionally limited to its own
	# namespaced payload fields; cross-kind IDs fail closed.
	if fact.payload is Dictionary:
		for key in keys:
			var value: Variant = fact.payload.get(key, "")
			if GMFeedbackValidation.stable_id(value):
				result[str(value)] = true
	return result

func _verify_package(event_id: String, package: Dictionary, store: GMFactEventStore) -> Dictionary:
	var capability := validate_capability()
	if not capability.ok:
		return capability
	if store != capability.store or store.get_instance_id() != capability.store_identity:
		return _failure("feedback.authority_store_identity_changed", "反馈权威读取器使用的FactEventStore身份已失配。", {"bound_store_identity": capability.store_identity})
	if str(package.get("schema", "")) != PACKAGE_SCHEMA or str(package.get("fact_event_id", "")) != event_id:
		return _failure("feedback.authority_package_shape_invalid", "权威提交包Schema或Fact身份无效。")
	var fact: GMFactEvent = store.get_by_id(event_id)
	if fact == null or not fact.has_commit_proof():
		return _failure("feedback.authority_fact_uncommitted", "指定 Fact 缺少 Coordinator 提交证明。")
	if package.get("fact", {}) != fact.to_dict() or str(package.get("transaction_id", "")) != fact.transaction_id or str(package.get("causal_chain_id", "")) != fact.causal_chain_id or int(package.get("global_sequence", 0)) != fact.sequence or str(package.get("commit_proof", "")) != fact.commit_proof:
		return _failure("feedback.authority_package_stale", "权威提交包不能与 FactEvent 账本逐值互证。", {"fact_event_id": event_id})
	var changes: Array = store.get_change_records_for_fact(event_id)
	var change_rows: Array = []
	for change in changes:
		change_rows.append(change.to_dict())
	if package.get("changes", []) != change_rows:
		return _failure("feedback.authority_changes_stale", "权威提交包的 ChangeRecord 顺序或内容已失配。", {"fact_event_id": event_id})
	var chain := GMCausalChain.from_dict(package.get("chain", {}))
	if chain == null or chain.chain_id != fact.causal_chain_id:
		return _failure("feedback.authority_chain_invalid", "权威提交包因果链不能被解析。", {"fact_event_id": event_id})
	var chain_fact := chain.get_ref(event_id)
	var transaction_ref := chain.get_ref(fact.transaction_id)
	if chain_fact == null or chain_fact.kind != "fact_event" or transaction_ref == null or transaction_ref.kind != "domain_transaction" or not chain.has_direct_link(fact.transaction_id, event_id):
		return _failure("feedback.authority_chain_link_invalid", "权威提交包缺少 Transaction 到 Fact 的直接因果链接。", {"fact_event_id": event_id})
	var package_id := "gm.commit_package.v1.%s" % GMStableData.digest(package)
	return {"ok": true, "package": package.duplicate(true), "fact": fact, "commit_package_id": package_id, "source_payload_digest": GMStableData.digest(fact.payload), "global_sequence": fact.sequence, "transaction_id": fact.transaction_id, "causal_chain_id": fact.causal_chain_id, "source_type": _source_type(fact), "source_fact_id": fact.event_id}

func _source_type(fact: GMFactEvent) -> String:
	var candidate: Variant = fact.payload.get("source_type", "") if fact.payload is Dictionary else ""
	if typeof(candidate) == TYPE_STRING and candidate in GMSemanticFeedbackRequest.SOURCE_TYPES:
		return str(candidate)
	if fact.source_system.begins_with("gm.source.player") or fact.source_system == "player":
		return "player"
	if fact.source_system.begins_with("gm.source.ai") or fact.source_system == "ai":
		return "ai"
	if fact.source_system.begins_with("gm.source.organization") or fact.source_system == "organization":
		return "organization"
	if fact.source_system.begins_with("gm.source.world") or fact.source_system == "world_event":
		return "world_event"
	if fact.source_system.begins_with("gm.source.script") or fact.source_system == "script":
		return "script"
	if fact.source_system.begins_with("gm.source.duty") or fact.source_system == "duty_provider":
		return "duty_provider"
	return "system"

func _change_dicts(records: Array) -> Array:
	var result: Array = []
	for record in records:
		if record is GMChangeRecord:
			result.append(record.to_dict())
	return result

func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
