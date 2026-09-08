class_name GMDomainResolver
extends RefCounted

## 领域 Resolver 合同。具体领域只实现业务预检、预留、提交和回滚。

var resolver_id: String = ""

func _init(p_resolver_id: String = "") -> void:
	resolver_id = p_resolver_id

func preflight_transaction(_transaction: GMDomainTransaction) -> Dictionary:
	return {"ok": true, "stage": "PREFLIGHT"}

func reserve_transaction(_transaction: GMDomainTransaction) -> Dictionary:
	return {"ok": true, "stage": "RESERVE", "reservations": []}

func commit_transaction(_transaction: GMDomainTransaction) -> Dictionary:
	return {"ok": false, "code": "resolver.commit_not_implemented", "reason_zh": "领域 Resolver 没有实现提交阶段。"}

func rollback_transaction(_transaction: GMDomainTransaction, _reason_zh: String) -> Dictionary:
	return {"ok": true, "stage": "ROLLBACK", "rolled_back": true}

## Capture a domain-owned recovery point before preflight/reservation/commit can
## mutate state. Resolvers which cannot provide an independently restorable
## snapshot are rejected before mutation by the coordinator.
func capture_transaction_state(_transaction: GMDomainTransaction) -> Dictionary:
	return {"ok": false, "code": "transaction.recovery_contract_unsupported", "reason_zh": "领域 Resolver 未提供提交前可恢复快照。"}

## Restore the exact pre-transaction domain state. This is the coordinator's
## second recovery path when the resolver's ordinary rollback reports failure.
func restore_transaction_state(_transaction: GMDomainTransaction, _snapshot: Variant) -> Dictionary:
	return {"ok": false, "code": "transaction.recovery_restore_unsupported", "reason_zh": "领域 Resolver 未提供快照恢复实现。"}

## Release only reservations owned by this transaction. The coordinator calls
## this on every failure path, including after a successful ordinary rollback.
func release_transaction_reservations(_transaction: GMDomainTransaction) -> Dictionary:
	return {"ok": false, "code": "transaction.reservation_release_unsupported", "reason_zh": "领域 Resolver 未提供事务预留释放实现。"}

## Last-resort isolation contract. If both rollback and snapshot restoration
## fail, the resolver must make the affected state unavailable to normal reads.
func isolate_transaction_state(_transaction: GMDomainTransaction, _failure: Dictionary) -> Dictionary:
	return {"ok": false, "code": "transaction.isolation_unsupported", "reason_zh": "领域 Resolver 未提供失败状态隔离实现。"}

## FactEvent/ChangeRecord 成功写入后释放领域侧提交快照。
## Resolver 可以覆盖该阶段；缺省实现保持兼容，不改变四阶段必选接口。
func finalize_transaction(_transaction: GMDomainTransaction) -> Dictionary:
	return {"ok": true, "stage": "FINALIZE", "finalized": true}

func version_for(_key: String) -> int:
	return 0

func build_candidate(request: GMAbilityActivationRequest, chain: GMCausalChain) -> GMCandidateResult:
	return GMCandidateResult.from_request(request, chain, 0.0, ["领域 Resolver 尚未尝试提交。"])
