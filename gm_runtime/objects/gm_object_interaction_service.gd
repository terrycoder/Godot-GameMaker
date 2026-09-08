class_name GMObjectInteractionService
extends GMDomainResolver

const SERVICE_ID := "gm.object.interaction"

var target: GMObjectInstance
var reservations: Dictionary = {}
var isolated: bool = false
var isolated_state: Dictionary = {}

# Bounded fault injection for the sealed Task05A recovery paths.
var fail_preflight: bool = false
var fail_reserve: bool = false
var fail_commit: bool = false
var mutate_before_commit_failure: bool = false
var fail_rollback: bool = false
var fail_recovery_restore: bool = false

func _init(p_target: GMObjectInstance = null) -> void:
	super._init(SERVICE_ID)
	target = p_target

func execute_ability(_definition: GMAbilityDefinition, request: GMAbilityActivationRequest, _spec: GMAbilitySpec) -> Dictionary:
	return {"ok": false, "code": "object.transaction_required", "reason_zh": "对象交互必须由GMAbilitySystemHost进入统一领域事务。", "request_id": request.request_id if request != null else ""}

func execute(_definition: GMAbilityDefinition, request: GMAbilityActivationRequest, _spec: GMAbilitySpec) -> Dictionary:
	return execute_ability(_definition, request, _spec)

func capture_transaction_state(_transaction: GMDomainTransaction) -> Dictionary:
	if not _target_available(): return _blocked("object.target_missing", "对象交互目标不存在或已隔离。")
	return {"ok": true, "contract": "gm.object.interaction.recovery.v1", "snapshot": {"object_state": target.object_state.duplicate(true), "reservations": reservations.duplicate(true)}}

func restore_transaction_state(_transaction: GMDomainTransaction, snapshot: Variant) -> Dictionary:
	if fail_recovery_restore: return _blocked("object.recovery_restore_injected_failure", "对象交互强制恢复故障注入。")
	if not _target_available() or not snapshot is Dictionary: return _blocked("object.recovery_snapshot_invalid", "对象交互恢复快照无效。")
	var value: Dictionary = snapshot
	if not value.get("object_state", null) is Dictionary or not value.get("reservations", null) is Dictionary:
		return _blocked("object.recovery_snapshot_invalid", "对象交互恢复快照缺少状态或预留。")
	target.object_state = value.get("object_state").duplicate(true)
	reservations = value.get("reservations").duplicate(true)
	return {"ok": true, "restored": true, "contract": "gm.object.interaction.recovery.v1"}

func release_transaction_reservations(transaction: GMDomainTransaction) -> Dictionary:
	if transaction == null: return _blocked("object.release_transaction_missing", "对象交互释放预留缺少事务。")
	var existed := reservations.has(transaction.transaction_id)
	reservations.erase(transaction.transaction_id)
	return {"ok": true, "released": true, "reservation_existed": existed}

func isolate_transaction_state(transaction: GMDomainTransaction, failure: Dictionary) -> Dictionary:
	isolated_state = {"transaction_id": transaction.transaction_id if transaction != null else "", "object_state": target.object_state.duplicate(true) if target != null and is_instance_valid(target) else {}, "failure": failure.duplicate(true)}
	# Even when the resolver's advertised recovery operation reports failure,
	# the coordinator-owned immutable recovery point is still used to keep the
	# externally observable object state equal to its pre-transaction value.
	if transaction != null and transaction.recovery_snapshot is Dictionary:
		var snapshot: Dictionary = transaction.recovery_snapshot
		if target != null and is_instance_valid(target) and snapshot.get("object_state", null) is Dictionary:
			target.object_state = snapshot.get("object_state").duplicate(true)
		if snapshot.get("reservations", null) is Dictionary: reservations = snapshot.get("reservations").duplicate(true)
	if transaction != null: reservations.erase(transaction.transaction_id)
	isolated = true
	return {"ok": true, "isolated": true, "normal_reads_disabled": true, "pre_transaction_state_restored": true}

func preflight_transaction(transaction: GMDomainTransaction) -> Dictionary:
	if fail_preflight: return _blocked("object.preflight_injected_failure", "对象交互预检故障注入。")
	if not _target_available(): return _blocked("object.target_missing", "对象交互目标不存在或已隔离。")
	if transaction == null or transaction.request == null: return _blocked("object.request_missing", "对象交互事务缺少能力请求。")
	var request := transaction.request
	if request.target_data == null or request.target_data.target != target or request.target_data.target_business_id != target.stable_instance_id:
		return _blocked("object.target_identity_mismatch", "对象交互请求与稳定目标身份不一致。")
	var patch_value: Variant = request.event_data.get("state_patch", null)
	if not patch_value is Dictionary or patch_value.is_empty(): return _blocked("object.state_patch_missing", "交互配方没有提供状态变化。")
	var before := target.object_state.duplicate(true)
	var after := before.duplicate(true)
	for key in patch_value: after[key] = patch_value[key]
	if after == before: return _blocked("object.state_unchanged", "对象交互不会产生新的领域状态。")
	transaction.commit_payload = {
		"source_id": target.stable_instance_id,
		"target_id": target.stable_instance_id,
		"targets": [target.stable_instance_id],
		"stable_instance_id": target.stable_instance_id,
		"map_id": str(target.map_id),
		"recipe_id": str(request.event_data.get("recipe_id", "")),
		"event_tag": str(request.event_data.get("event_tag", "")),
		"before_state": before,
		"after_state": after,
	}
	return {"ok": true, "stage": "PREFLIGHT", "stable_instance_id": target.stable_instance_id}

func reserve_transaction(transaction: GMDomainTransaction) -> Dictionary:
	if fail_reserve: return _blocked("object.reserve_injected_failure", "对象交互预留故障注入。")
	if reservations.has(transaction.transaction_id): return _blocked("object.reserve_duplicate", "对象交互事务重复预留。")
	var handle := "gm.object.reservation.%s" % transaction.transaction_id
	reservations[transaction.transaction_id] = {"handle": handle, "before_state": transaction.commit_payload.get("before_state", {}).duplicate(true)}
	return {"ok": true, "stage": "RESERVE", "reservations": [handle]}

func commit_transaction(transaction: GMDomainTransaction) -> Dictionary:
	if fail_commit and not mutate_before_commit_failure: return _blocked("object.commit_injected_failure", "对象交互提交故障注入。")
	if not _target_available(): return _blocked("object.target_missing", "对象交互目标不存在或已隔离。")
	if not reservations.has(transaction.transaction_id): return _blocked("object.reservation_missing", "对象交互提交缺少事务预留。")
	var before: Dictionary = transaction.commit_payload.get("before_state", {}).duplicate(true)
	var after: Dictionary = transaction.commit_payload.get("after_state", {}).duplicate(true)
	target.object_state = after
	if fail_commit: return _blocked("object.commit_after_mutation_injected_failure", "对象交互写入后提交故障注入。")
	var cue_id := str(transaction.request.event_data.get("cue_id", ""))
	return {
		"ok": true,
		"stage": "COMMIT",
		"inputs": [target.stable_instance_id],
		"outputs": [target.stable_instance_id],
		"tags": ["gm.fact.object.interaction", str(transaction.request.event_data.get("event_tag", ""))],
		"visibility": {"public": false, "witnesses": [target.stable_instance_id]},
		"payload": transaction.commit_payload.duplicate(true),
		"changeset": [{"entity_id": target.stable_instance_id, "operation": "object.interaction", "field": "object_state", "before": before, "after": after, "metadata": {"recipe_id": str(transaction.request.event_data.get("recipe_id", "")), "map_id": str(target.map_id)}}],
		"cues": [] if cue_id.is_empty() else [{"cue_id": cue_id, "parameters": {"stable_instance_id": target.stable_instance_id, "recipe_id": str(transaction.request.event_data.get("recipe_id", ""))}}],
	}

func rollback_transaction(transaction: GMDomainTransaction, _reason_zh: String) -> Dictionary:
	if fail_rollback: return _blocked("object.rollback_injected_failure", "对象交互普通回滚故障注入。")
	var reservation: Variant = reservations.get(transaction.transaction_id, {})
	if reservation is Dictionary and reservation.get("before_state", null) is Dictionary and _target_available(): target.object_state = reservation.get("before_state").duplicate(true)
	reservations.erase(transaction.transaction_id)
	return {"ok": true, "stage": "ROLLBACK", "rolled_back": true}

func finalize_transaction(transaction: GMDomainTransaction) -> Dictionary:
	reservations.erase(transaction.transaction_id)
	return {"ok": true, "stage": "FINALIZE", "finalized": true}

func pending_reservation_count() -> int:
	return reservations.size()

func _target_available() -> bool:
	return not isolated and target != null and is_instance_valid(target)

func _blocked(code: String, reason_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh}
