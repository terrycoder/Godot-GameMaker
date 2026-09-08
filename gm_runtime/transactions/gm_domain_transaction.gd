class_name GMDomainTransaction
extends RefCounted

## 一次领域事务的单一状态机：预检 → 预留 → 提交 → 事实/变更写入，失败统一回滚。

const NEW := "NEW"
const PREFLIGHTED := "PREFLIGHTED"
const RESERVED := "RESERVED"
const COMMITTING := "COMMITTING"
const COMMITTED := "COMMITTED"
const ROLLING_BACK := "ROLLING_BACK"
const ROLLED_BACK := "ROLLED_BACK"
const RECOVERED := "RECOVERED"
const FAILED := "FAILED"
const ROLLBACK_FAILED := "ROLLBACK_FAILED"

var transaction_id: String = ""
var idempotency_key: String = ""
var request_id: String = ""
var ability_id: String = ""
var ability_instance_id: String = ""
var resolver_id: String = ""
var fact_type: String = ""
var source_system: String = ""
var chain: GMCausalChain
var request: GMAbilityActivationRequest
var state: String = NEW
var expected_versions: Dictionary = {}
var observed_versions: Dictionary = {}
var reserved_handles: Array = []
var changeset: Array = []
var commit_payload: Dictionary = {}
var commit_outputs: Array = []
var commit_inputs: Array = []
var commit_tags: Array = []
var commit_visibility: Dictionary = {"public": false, "witnesses": []}
var failure: Dictionary = {}
var rollback_report: Dictionary = {}
var recovery_snapshot: Variant = null
var recovery_prepared: bool = false
var recovery_report: Dictionary = {}
var timeline: Array[Dictionary] = []

func _init(p_request: GMAbilityActivationRequest = null, p_chain: GMCausalChain = null, p_resolver_id: String = "", p_fact_type: String = "", p_source_system: String = "") -> void:
	request = p_request
	chain = p_chain
	request_id = p_request.request_id if p_request != null else ""
	idempotency_key = p_request.idempotency_key if p_request != null and not p_request.idempotency_key.is_empty() else request_id
	ability_id = p_request.ability_id if p_request != null else ""
	resolver_id = p_resolver_id
	fact_type = p_fact_type
	source_system = p_source_system
	ability_instance_id = str(p_request.event_data.get("ability_instance_id", "")) if p_request != null else ""
	var identity_material := "%s|%s|%s|%s" % [resolver_id, idempotency_key, ability_instance_id, request_id]
	transaction_id = "gm.transaction.v2.%s" % identity_material.sha256_text()
	if p_request != null and p_request.event_data.get("expected_versions", {}) is Dictionary:
		expected_versions = p_request.event_data.get("expected_versions", {}).duplicate(true)
	_record(NEW, "事务已创建。", {})

func prepare_recovery(resolver: Object) -> Dictionary:
	if state != NEW: return _stage_rejected("transaction.recovery_prepare_order", "恢复点只能在领域事务开始前创建。")
	if resolver == null or not is_instance_valid(resolver) or not resolver.has_method("capture_transaction_state"):
		return _fail_stage({"ok": false, "code": "transaction.recovery_contract_missing", "reason_zh": "领域 Resolver 缺少提交前恢复合同，已在变更前拒绝。"})
	var result: Variant = resolver.call("capture_transaction_state", self)
	if not result is Dictionary or not bool(result.get("ok", false)) or not result.has("snapshot"):
		var failure_result: Dictionary = result.duplicate(true) if result is Dictionary else {}
		failure_result["ok"] = false
		failure_result["code"] = str(failure_result.get("code", "transaction.recovery_snapshot_failed"))
		failure_result["reason_zh"] = str(failure_result.get("reason_zh", "领域 Resolver 无法建立提交前恢复点，已在变更前拒绝。"))
		return _fail_stage(failure_result)
	recovery_snapshot = result.get("snapshot")
	recovery_prepared = true
	_record(NEW, "领域事务恢复点已建立。", {"recovery_contract": str(result.get("contract", "snapshot"))})
	return {"ok": true, "stage": "RECOVERY_PREPARED", "contract": str(result.get("contract", "snapshot"))}

func recover_after_rollback_failure(resolver: Object, rollback_failure: Dictionary) -> Dictionary:
	if not recovery_prepared:
		return {"ok": false, "code": "transaction.recovery_snapshot_missing", "reason_zh": "事务缺少提交前恢复点。", "rollback_failure": rollback_failure.duplicate(true)}
	if resolver == null or not is_instance_valid(resolver) or not resolver.has_method("restore_transaction_state") or not resolver.has_method("release_transaction_reservations"):
		return {"ok": false, "code": "transaction.recovery_contract_missing", "reason_zh": "领域 Resolver 缺少恢复或预留释放接口。", "rollback_failure": rollback_failure.duplicate(true)}
	var restored_value: Variant = resolver.call("restore_transaction_state", self, recovery_snapshot)
	var restored: Dictionary = restored_value.duplicate(true) if restored_value is Dictionary else {"ok": false, "code": "transaction.recovery_result_invalid"}
	var released_value: Variant = resolver.call("release_transaction_reservations", self)
	var released: Dictionary = released_value.duplicate(true) if released_value is Dictionary else {"ok": false, "code": "transaction.release_result_invalid"}
	var ok := bool(restored.get("ok", false)) and bool(released.get("ok", false))
	recovery_report = {"ok": ok, "restored": restored, "released": released, "rollback_failure": rollback_failure.duplicate(true)}
	if ok:
		state = RECOVERED
		reserved_handles.clear()
		_record(RECOVERED, "普通回滚失败后已从提交前恢复点还原并释放预留。", recovery_report)
	else:
		state = ROLLBACK_FAILED
		_record(ROLLBACK_FAILED, "普通回滚与强制恢复均失败，Resolver必须隔离。", recovery_report)
	return recovery_report.duplicate(true)

func ensure_reservations_released(resolver: Object) -> Dictionary:
	if resolver == null or not is_instance_valid(resolver) or not resolver.has_method("release_transaction_reservations"):
		return {"ok": false, "code": "transaction.reservation_release_contract_missing", "reason_zh": "领域 Resolver 缺少预留释放接口。"}
	var value: Variant = resolver.call("release_transaction_reservations", self)
	var result: Dictionary = value.duplicate(true) if value is Dictionary else {"ok": false, "code": "transaction.release_result_invalid"}
	if bool(result.get("ok", false)): reserved_handles.clear()
	return result

func preflight(resolver: Object) -> Dictionary:
	if state != NEW: return _stage_rejected("transaction.preflight_order", "事务只能从 NEW 进入预检。")
	state = PREFLIGHTED
	_record(PREFLIGHTED, "开始事务预检。", {})
	var conflict := _check_conflicts(resolver)
	if not conflict.ok: return _fail_stage(conflict)
	var result := _call_stage(resolver, "preflight_transaction")
	if not result.ok: return _fail_stage(result)
	_record(PREFLIGHTED, "事务预检通过。", result)
	return result

func reserve(resolver: Object) -> Dictionary:
	if state != PREFLIGHTED: return _stage_rejected("transaction.reserve_order", "事务必须先通过预检才能预留。")
	state = RESERVED
	_record(RESERVED, "开始事务预留。", {})
	var result := _call_stage(resolver, "reserve_transaction")
	if not result.ok: return _fail_stage(result)
	var handles: Variant = result.get("reservations", result.get("reserved_handles", []))
	reserved_handles = handles.duplicate(true) if handles is Array else []
	_record(RESERVED, "事务预留完成。", result)
	return result

func commit(resolver: Object) -> Dictionary:
	if state != RESERVED: return _stage_rejected("transaction.commit_order", "事务必须先完成预留才能提交。")
	state = COMMITTING
	_record(COMMITTING, "开始事务提交。", {})
	var result := _call_stage(resolver, "commit_transaction")
	if not result.ok: return _fail_stage(result)
	var changes: Variant = result.get("changeset", result.get("changes", []))
	changeset = changes.duplicate(true) if changes is Array else []
	commit_payload = result.get("payload", {}).duplicate(true) if result.get("payload", {}) is Dictionary else {}
	commit_outputs = result.get("outputs", []).duplicate(true) if result.get("outputs", []) is Array else []
	commit_inputs = result.get("inputs", []).duplicate(true) if result.get("inputs", []) is Array else []
	commit_tags = result.get("tags", []).duplicate(true) if result.get("tags", []) is Array else []
	commit_visibility = result.get("visibility", commit_visibility).duplicate(true) if result.get("visibility", commit_visibility) is Dictionary else commit_visibility
	return result

func mark_committed(details: Dictionary = {}) -> Dictionary:
	if state != COMMITTING: return _stage_rejected("transaction.commit_state_invalid", "只有提交阶段可以完成事实写入。")
	state = COMMITTED
	_record(COMMITTED, "FactEvent 与 ChangeRecord 已原子写入。", details)
	return {"ok": true, "state": state}

func rollback(resolver: Object, reason_zh: String) -> Dictionary:
	if state == ROLLED_BACK: return {"ok": true, "state": state, "duplicate": true, "rollback": rollback_report.duplicate(true)}
	if state == COMMITTED: return {"ok": false, "code": "transaction.rollback_after_commit", "reason_zh": "已提交事务不可回滚。", "state": state}
	state = ROLLING_BACK
	_record(ROLLING_BACK, reason_zh, {})
	var result := _call_stage(resolver, "rollback_transaction", [reason_zh])
	rollback_report = result.duplicate(true)
	if not result.ok:
		state = ROLLBACK_FAILED
		failure = {"code": "transaction.rollback_failed", "reason_zh": "事务回滚失败，领域状态需要人工诊断。", "original_reason_zh": reason_zh, "rollback": result}
		_record(ROLLBACK_FAILED, str(failure.reason_zh), failure)
		return {"ok": false, "code": "transaction.rollback_failed", "reason_zh": str(failure.reason_zh), "rollback": result, "state": state}
	state = ROLLED_BACK
	_record(ROLLED_BACK, "事务回滚完成，未产生 FactEvent。", result)
	return {"ok": true, "state": state, "rollback": result}

func add_change(draft: Dictionary) -> void:
	changeset.append(draft.duplicate(true))

func is_terminal() -> bool:
	return state in [COMMITTED, ROLLED_BACK, RECOVERED, FAILED, ROLLBACK_FAILED]

func to_dict() -> Dictionary:
	return {
		"transaction_id": transaction_id,
		"idempotency_key": idempotency_key,
		"request_id": request_id,
		"ability_id": ability_id,
		"ability_instance_id": ability_instance_id,
		"resolver_id": resolver_id,
		"fact_type": fact_type,
		"source_system": source_system,
		"state": state,
		"expected_versions": expected_versions.duplicate(true),
		"observed_versions": observed_versions.duplicate(true),
		"reserved_handles": reserved_handles.duplicate(true),
		"changeset": changeset.duplicate(true),
		"payload": commit_payload.duplicate(true),
		"inputs": commit_inputs.duplicate(true),
		"outputs": commit_outputs.duplicate(true),
		"tags": commit_tags.duplicate(true),
		"visibility": commit_visibility.duplicate(true),
		"failure": failure.duplicate(true),
		"rollback_report": rollback_report.duplicate(true),
		"recovery_prepared": recovery_prepared,
		"recovery_report": recovery_report.duplicate(true),
		"timeline": timeline.duplicate(true),
		"causal_chain": chain.to_dict() if chain != null else {}
	}

func _call_stage(resolver: Object, method_name: String, extra_args: Array = []) -> Dictionary:
	if resolver == null or not is_instance_valid(resolver): return {"ok": false, "code": "transaction.resolver_missing", "reason_zh": "领域 Resolver 不存在。"}
	if not resolver.has_method(method_name): return {"ok": false, "code": "transaction.resolver_interface_missing", "reason_zh": "领域 Resolver 缺少接口：%s" % method_name, "resolver_id": resolver_id}
	var args: Array = [self]
	args.append_array(extra_args)
	var value: Variant = resolver.callv(method_name, args)
	if value is Dictionary:
		var result: Dictionary = value.duplicate(true)
		if not result.has("ok"): result["ok"] = true
		return result
	if value is bool: return {"ok": value}
	return {"ok": true, "value": value}

func _check_conflicts(resolver: Object) -> Dictionary:
	if expected_versions.is_empty(): return {"ok": true, "checked": []}
	if resolver == null or not resolver.has_method("version_for"):
		return {"ok": false, "code": "transaction.version_source_missing", "reason_zh": "事务声明了版本冲突检测，但 Resolver 没有 version_for 接口。"}
	var conflicts: Array = []
	for key in expected_versions:
		var actual := int(resolver.call("version_for", str(key)))
		observed_versions[str(key)] = actual
		if actual != int(expected_versions[key]): conflicts.append({"key": str(key), "expected": int(expected_versions[key]), "actual": actual})
	if not conflicts.is_empty():
		return {"ok": false, "code": "transaction.conflict", "reason_zh": "事务检测到状态版本冲突，未进入预留。", "conflicts": conflicts}
	return {"ok": true, "checked": expected_versions.keys()}

func _fail_stage(result: Dictionary) -> Dictionary:
	state = FAILED
	failure = result.duplicate(true)
	_record(FAILED, str(result.get("reason_zh", "事务阶段失败。")), result)
	return result

func _stage_rejected(code: String, reason_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "state": state}

func _record(p_state: String, reason_zh: String, details: Dictionary) -> void:
	timeline.append({"sequence": timeline.size() + 1, "state": p_state, "reason_zh": reason_zh, "details": details.duplicate(true)})

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in range(raw.length()):
		var code := raw.unicode_at(index)
		result += raw.substr(index, 1) if ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45) else "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_") if not result.is_empty() else "transaction"
