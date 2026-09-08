class_name GMProcessService
extends RefCounted

## Generic Process lifecycle service. Every mutation still originates as a
## GMAbilityActivationRequest; this service never selects an actor or writes a
## domain fact directly.

const SERVICE_SCHEMA := "gm.process.service.v1"

var process_store: GMProcessStore
var clock: GMProcessClock
var settlement_gateway: GMProcessSettlementGateway

func _init(p_store: GMProcessStore = null, p_clock: GMProcessClock = null, p_gateway: GMProcessSettlementGateway = null) -> void:
	process_store = p_store if p_store != null else GMProcessStore.new()
	clock = p_clock if p_clock != null else process_store.get_clock()
	if clock == null: clock = GMProcessClock.new()
	settlement_gateway = p_gateway
	if not process_store.backend_rebound.is_connected(_on_store_rebound): process_store.backend_rebound.connect(_on_store_rebound)
	if process_store.get_clock() == null: process_store.put_clock(clock)

func register_definition(definition: GMProcessDefinition) -> Dictionary:
	return process_store.put_definition(definition)

func request(request_value: GMAbilityActivationRequest) -> Dictionary:
	if request_value == null: return _failure("process.ability_request_missing", "Process 操作必须由 Ability 请求发起。")
	var validation := request_value.validate()
	if not validation.ok: return validation
	if not request_value.ability_id.begins_with("gm.ability.process."):
		return _failure("process.ability_boundary_invalid", "Process 只能由 Process Ability 请求入口调用。")
	var action := str(request_value.event_data.get("process_action", "")).strip_edges().to_lower()
	if action.is_empty(): return _failure("process.action_missing", "Process Ability 请求缺少 process_action。")
	if request_value.idempotency_key.is_empty(): return _failure("process.idempotency_key_required", "Process 操作必须携带显式幂等键，以保持逻辑时钟和存档确定性。")
	_sync_clock_from_store()
	match action:
		"start": return _start(request_value)
		"participate": return _participate(request_value)
		"pause": return _transition_request(request_value, GMProcessState.PAUSED, "Process 已由 Ability 请求暂停。")
		"resume": return _resume(request_value)
		"cancel": return _transition_request(request_value, GMProcessState.CANCELLED, "Process 已由 Ability 请求取消。")
		_: return _failure("process.action_invalid", "未知 Process Ability 操作。", {"action": action})

func advance(instance_id: String, units: int) -> Dictionary:
	_sync_clock_from_store()
	if typeof(units) != TYPE_INT or units <= 0: return _failure("process.clock_units_invalid", "Process 推进单位必须是正整数。")
	var instance := process_store.get_instance(instance_id)
	if instance == null: return _failure("process.instance_missing", "ProcessInstance 不存在。")
	if not [GMProcessState.READY, GMProcessState.RUNNING].has(instance.state):
		return _failure("process.advance_state_invalid", "只有 ready/running Process 可以推进。", {"state": instance.state})
	var old_clock := clock.to_native()
	if instance.state == GMProcessState.READY:
		var started := instance.transition(GMProcessState.RUNNING, clock.now(), "逻辑时钟开始推进 Process。")
		if not started.ok: return started
	var clock_result := clock.advance(units)
	if not clock_result.ok: return clock_result
	var progress_result := instance.progress.advance(units, clock.now())
	if not progress_result.ok:
		clock.restore_native(old_clock)
		return progress_result
	var checkpoint := instance.record_progress_checkpoint(clock.now(), units)
	if not checkpoint.ok:
		clock.restore_native(old_clock)
		return checkpoint
	if progress_result.completed:
		return _settle_and_persist(instance, old_clock)
	return _persist_runtime(instance, old_clock)

func complete(instance_id: String) -> Dictionary:
	_sync_clock_from_store()
	var instance := process_store.get_instance(instance_id)
	if instance == null: return _failure("process.instance_missing", "ProcessInstance 不存在。")
	if instance.state == GMProcessState.COMPLETED:
		return {"ok": true, "duplicate": true, "idempotent": true, "state": instance.state, "instance": instance.to_native(), "result": instance.result.duplicate(true)}
	if not [GMProcessState.RUNNING, GMProcessState.BLOCKED].has(instance.state) or instance.progress.elapsed_units < instance.progress.required_units:
		return _failure("process.complete_not_ready", "Process 尚未达到完成进度或当前状态不允许结算。", {"state": instance.state, "progress": instance.progress.to_native()})
	if instance.state == GMProcessState.BLOCKED: return retry_blocked(instance_id)
	return _settle_and_persist(instance, clock.to_native())

func fail(instance_id: String, code: String, reason_zh: String) -> Dictionary:
	_sync_clock_from_store()
	if code.strip_edges().is_empty() or reason_zh.strip_edges().is_empty(): return _failure("process.failure_reason_missing", "Process 失败必须提供稳定代码和原因。")
	var instance := process_store.get_instance(instance_id)
	if instance == null: return _failure("process.instance_missing", "ProcessInstance 不存在。")
	if instance.state == GMProcessState.FAILED:
		return {"ok": true, "duplicate": true, "state": instance.state, "instance": instance.to_native()}
	if GMProcessState.is_terminal(instance.state): return _failure("process.fail_terminal", "终态 Process 不能再次失败。", {"state": instance.state})
	var old_clock := clock.to_native()
	instance.failure = {"code": code, "reason_zh": reason_zh}
	var transitioned := instance.transition(GMProcessState.FAILED, clock.now(), reason_zh, {"code": code})
	if not transitioned.ok: return transitioned
	return _persist_runtime(instance, old_clock)

func recover(instance_id: String) -> Dictionary:
	_sync_clock_from_store()
	var instance := process_store.get_instance(instance_id)
	if instance == null: return _failure("process.instance_missing", "ProcessInstance 不存在。")
	if instance.state != GMProcessState.FAILED: return _failure("process.recover_state_invalid", "只有 failed Process 可显式恢复。")
	var old_clock := clock.to_native()
	instance.failure.clear()
	var transitioned := instance.transition(GMProcessState.READY, clock.now(), "Process 已显式恢复，等待继续推进。")
	if not transitioned.ok: return transitioned
	return _persist_runtime(instance, old_clock)

func retry_blocked(instance_id: String) -> Dictionary:
	_sync_clock_from_store()
	var instance := process_store.get_instance(instance_id)
	if instance == null: return _failure("process.instance_missing", "ProcessInstance 不存在。")
	if instance.state != GMProcessState.BLOCKED: return _failure("process.retry_state_invalid", "只有 blocked Process 可重试结算。")
	var old_clock := clock.to_native()
	var transitioned := instance.transition(GMProcessState.RUNNING, clock.now(), "阻断条件已由外部权威处理，重试完成结算。")
	if not transitioned.ok: return transitioned
	return _settle_and_persist(instance, old_clock)

func snapshot() -> Dictionary:
	return {"schema_version": SERVICE_SCHEMA, "process_store": process_store.snapshot(), "clock": clock.to_native()}

func restore_snapshot(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() != 3 or not value.has("schema_version") or not value.has("process_store") or not value.has("clock"):
		return _failure("process.service_snapshot_shape_invalid", "Process Service 快照字段缺失或附加。")
	if value.schema_version != SERVICE_SCHEMA or not value.process_store is Dictionary or not value.clock is Dictionary:
		return _failure("process.service_snapshot_shape_invalid", "Process Service 快照字段类型或Schema无效。")
	var stable := GMStableData.validate_persistence(value)
	if not stable.ok: return _failure("process.service_snapshot_data_invalid", "Process Service 快照不是持久化纯数据。")
	var staged_store := GMProcessStore.new()
	var store_result := staged_store.restore_snapshot(value.process_store)
	if not store_result.ok: return store_result
	var clock_result := GMProcessClock.from_native(value.clock, true)
	if not clock_result.ok: return clock_result
	var stored_clock := staged_store.get_clock()
	if stored_clock != null and GMStableData.canonical_json(stored_clock.to_native()) != GMStableData.canonical_json(clock_result.clock.to_native()):
		return _failure("process.service_clock_mismatch", "Process Service 快照中的逻辑时钟与Process Store不一致。")
	var old_store := process_store
	process_store = staged_store
	clock = clock_result.clock
	if not process_store.backend_rebound.is_connected(_on_store_rebound): process_store.backend_rebound.connect(_on_store_rebound)
	return {"ok": true, "store_result": store_result, "clock": clock.to_native(), "store_changed": old_store != process_store}

func _start(request_value: GMAbilityActivationRequest) -> Dictionary:
	var definition_id := str(request_value.event_data.get("process_definition_id", "")).strip_edges()
	var definition := process_store.get_definition(definition_id)
	if definition == null: return _failure("process.definition_missing", "ProcessDefinition 不存在。")
	var key_material := request_value.idempotency_key
	var instance_id := "gm.process.instance.%s" % ("%s|%s|%s" % [definition_id, definition.revision, key_material]).sha256_text()
	var existing := process_store.get_instance(instance_id)
	if existing != null:
		return {"ok": true, "duplicate": true, "idempotent": true, "state": existing.state, "instance": existing.to_native()}
	var stable_request_id := "gm.process.request.%s" % key_material.sha256_text()
	var instance := GMProcessInstance.new().configure(instance_id, definition, stable_request_id, clock.now())
	var ready := instance.transition(GMProcessState.READY, clock.now(), "ProcessDefinition 已验证，等待参与或逻辑时钟推进。")
	if not ready.ok: return ready
	return _persist_runtime(instance, clock.to_native())

func _participate(request_value: GMAbilityActivationRequest) -> Dictionary:
	var instance := _instance_from_request(request_value)
	if instance == null: return _failure("process.instance_missing", "ProcessInstance 不存在。")
	if GMProcessState.is_terminal(instance.state): return _failure("process.participate_terminal", "终态 Process 不接受参与请求。")
	var participant_id := str(request_value.event_data.get("participant_id", "")).strip_edges()
	if not GMProcessDefinition._stable_id(participant_id): return _failure("process.participant_invalid", "参与者必须由调用方显式提供稳定 ID。")
	var old_clock := clock.to_native()
	var participant_result := instance.add_participant(participant_id)
	if not participant_result.ok: return participant_result
	var saved := _persist_runtime(instance, old_clock)
	saved["duplicate"] = bool(participant_result.get("duplicate", false))
	return saved

func _transition_request(request_value: GMAbilityActivationRequest, next_state: String, reason_zh: String) -> Dictionary:
	var instance := _instance_from_request(request_value)
	if instance == null: return _failure("process.instance_missing", "ProcessInstance 不存在。")
	if instance.state == next_state:
		return {"ok": true, "duplicate": true, "state": instance.state, "instance": instance.to_native()}
	var old_clock := clock.to_native()
	var transitioned := instance.transition(next_state, clock.now(), reason_zh)
	if not transitioned.ok: return transitioned
	if next_state == GMProcessState.CANCELLED: instance.failure.clear()
	return _persist_runtime(instance, old_clock)

func _resume(request_value: GMAbilityActivationRequest) -> Dictionary:
	var instance := _instance_from_request(request_value)
	if instance == null: return _failure("process.instance_missing", "ProcessInstance 不存在。")
	var target := GMProcessState.RUNNING if instance.progress.elapsed_units > 0 else GMProcessState.READY
	return _transition_loaded(instance, target, "Process 已由 Ability 请求恢复。")

func _transition_loaded(instance: GMProcessInstance, next_state: String, reason_zh: String) -> Dictionary:
	if instance.state == next_state: return {"ok": true, "duplicate": true, "state": instance.state, "instance": instance.to_native()}
	var old_clock := clock.to_native()
	var transitioned := instance.transition(next_state, clock.now(), reason_zh)
	if not transitioned.ok: return transitioned
	return _persist_runtime(instance, old_clock)

func _settle_and_persist(instance: GMProcessInstance, old_clock: Dictionary) -> Dictionary:
	var definition := process_store.get_definition(instance.definition_id, instance.definition_revision)
	if definition == null: return _block_instance(instance, old_clock, _failure("process.definition_missing", "完成时 ProcessDefinition 不存在。"))
	var settlement := _settlement_for(instance, definition)
	if not settlement.ok: return _block_instance(instance, old_clock, settlement)
	var stable := GMStableData.validate_persistence(settlement)
	if not stable.ok: return _block_instance(instance, old_clock, _failure("process.settlement_data_invalid", "完成适配器返回了不可持久化结果。"))
	instance.result = settlement.duplicate(true)
	instance.failure.clear()
	var completed := instance.transition(GMProcessState.COMPLETED, clock.now(), "Process 已通过权威结算完成。", {"kind": settlement.get("kind", "")})
	if not completed.ok: return completed
	var saved := _persist_runtime(instance, old_clock)
	if not saved.ok: return saved
	saved["result"] = settlement.duplicate(true)
	return saved

func _block_instance(instance: GMProcessInstance, old_clock: Dictionary, settlement: Dictionary) -> Dictionary:
	instance.failure = settlement.duplicate(true)
	var blocked := instance.transition(GMProcessState.BLOCKED, clock.now(), "权威领域结算阻断，Process 未完成。", settlement)
	if not blocked.ok: return blocked
	var saved := _persist_runtime(instance, old_clock)
	return {"ok": false, "code": str(settlement.get("code", "process.settlement_blocked")), "reason_zh": str(settlement.get("reason_zh", "权威领域结算阻断。")), "state": instance.state, "instance": instance.to_native(), "store": saved}

func _settlement_for(instance: GMProcessInstance, definition: GMProcessDefinition) -> Dictionary:
	var key := "gm.process.completion.%s" % instance.instance_id
	match definition.completion_kind:
		"none": return {"ok": true, "kind": "none", "process_instance_id": instance.instance_id, "idempotency_key": key}
		"typed_domain_request": return {"ok": true, "kind": "typed_domain_request", "process_instance_id": instance.instance_id, "request": definition.completion_payload.duplicate(true), "idempotency_key": key}
		"p19_transaction":
			if settlement_gateway == null: return _failure("process.settlement_not_configured", "P19 结算网关未配置。")
			return settlement_gateway.settle_p19(instance, definition)
		_: return _failure("process.completion_kind_invalid", "未知完成适配器。")

func _persist_runtime(instance: GMProcessInstance, old_clock: Dictionary) -> Dictionary:
	var saved := process_store.put_runtime_state(instance, clock)
	if not saved.ok:
		clock.restore_native(old_clock)
		return {"ok": false, "code": "process.persist_failed", "reason_zh": "Process 状态和逻辑时钟未能原子写入。", "details": saved, "state": instance.state, "instance": instance.to_native()}
	return {"ok": true, "state": instance.state, "instance": instance.to_native(), "clock": clock.to_native(), "store": saved}

func _instance_from_request(request_value: GMAbilityActivationRequest) -> GMProcessInstance:
	return process_store.get_instance(str(request_value.event_data.get("process_instance_id", "")))

func _sync_clock_from_store() -> void:
	var stored := process_store.get_clock()
	if stored != null: clock = stored

func _on_store_rebound(_old_backend: GMStore, new_backend: GMStore) -> void:
	if new_backend == null: return
	_sync_clock_from_store()

static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty(): result["details"] = details
	return result
