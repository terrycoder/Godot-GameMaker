class_name GMCombatResolver
extends "res://gm_runtime/transactions/gm_domain_resolver.gd"

## The single P22 combat rule layer. It evaluates pure CombatRequest values,
## then participates in the existing DomainTransaction lifecycle. It never
## owns HP, actor, inventory, world or cue state.

const RESOLVER_ID := "gm.resolver.combat"
const FACT_TYPE := "gm.fact.combat.resolution.v1"
const COMBAT_REQUEST_KEY := "combat_request"
const COMBAT_PLAN_KEY := "combat_plan"
const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")
const ATTACK := preload("res://gm_runtime/combat/gm_combat_attack_definition.gd")
const WEAPON := preload("res://gm_runtime/combat/gm_combat_weapon_definition.gd")
const PROJECTILE := preload("res://gm_runtime/combat/gm_combat_projectile_definition.gd")
const REQUEST := preload("res://gm_runtime/combat/gm_combat_request.gd")
const RESULT := preload("res://gm_runtime/combat/gm_combat_result.gd")
const CATALOG := preload("res://gm_runtime/combat/gm_combat_catalog.gd")
const P19_OVERLAY_FIELDS := ["operation", "item_kind", "item_id", "quantity", "source_container_id", "target_container_id", "source_account_id", "target_account_id", "resource_id", "amount"]
const DEFAULT_HIT_QUERY := preload("res://gm_runtime/combat/gm_combat_planar_hit_query_adapter.gd")

var p19_resolver: Object
var hit_query: Object
var attacks: Dictionary = {}
var weapons: Dictionary = {}
var projectiles: Dictionary = {}
var plans: Dictionary = {}
var preview_results: Dictionary = {}
var isolated := false
var isolation_report: Dictionary = {}

func _init(p_p19_resolver: Object = null, p_hit_query: Object = null) -> void:
        resolver_id = RESOLVER_ID
        p19_resolver = p_p19_resolver
        hit_query = p_hit_query if p_hit_query != null else DEFAULT_HIT_QUERY.new()

func register_attack(definition) -> Dictionary:
        if definition == null:
                return CONTRACT.failure("combat.attack_missing", "不能注册空的 AttackDefinition。")
        var checked: Dictionary = definition.validate()
        if not checked.ok:
                return CONTRACT.failure("combat.attack_invalid", "AttackDefinition 未通过严格校验。", {"errors": checked.errors})
        return _register(attacks, definition.attack_id, definition)

func register_weapon(definition) -> Dictionary:
        if definition == null:
                return CONTRACT.failure("combat.weapon_missing", "不能注册空的 WeaponDefinition。")
        var checked: Dictionary = definition.validate()
        if not checked.ok:
                return CONTRACT.failure("combat.weapon_invalid", "WeaponDefinition 未通过严格校验。", {"errors": checked.errors})
        return _register(weapons, definition.weapon_id, definition)

func register_projectile(definition) -> Dictionary:
        if definition == null:
                return CONTRACT.failure("combat.projectile_missing", "不能注册空的 ProjectileDefinition。")
        var checked: Dictionary = definition.validate()
        if not checked.ok:
                return CONTRACT.failure("combat.projectile_invalid", "ProjectileDefinition 未通过严格校验。", {"errors": checked.errors})
        return _register(projectiles, definition.projectile_id, definition)

func register_catalog(catalog) -> Dictionary:
        if catalog == null:
                return CONTRACT.failure("combat.catalog_missing", "不能注册空的 P22 定义目录。")
        var checked: Dictionary = catalog.validate()
        if not checked.ok:
                return CONTRACT.failure("combat.catalog_invalid", "P22 定义目录未通过严格校验。", {"errors": checked.errors})
        attacks.clear()
        weapons.clear()
        projectiles.clear()
        for raw in catalog.attacks:
                var attack_result: Dictionary = ATTACK.from_native(raw)
                if not attack_result.ok: return CONTRACT.failure("combat.catalog_attack_invalid", "P22 目录中的 AttackDefinition 无效。", attack_result)
                attacks[str(attack_result.value.attack_id)] = attack_result.value
        for raw in catalog.weapons:
                var weapon_result: Dictionary = WEAPON.from_native(raw)
                if not weapon_result.ok: return CONTRACT.failure("combat.catalog_weapon_invalid", "P22 目录中的 WeaponDefinition 无效。", weapon_result)
                weapons[str(weapon_result.value.weapon_id)] = weapon_result.value
        for raw in catalog.projectiles:
                var projectile_result: Dictionary = PROJECTILE.from_native(raw)
                if not projectile_result.ok: return CONTRACT.failure("combat.catalog_projectile_invalid", "P22 目录中的 ProjectileDefinition 无效。", projectile_result)
                projectiles[str(projectile_result.value.projectile_id)] = projectile_result.value
        return {"ok": true, "code": "combat.catalog_registered", "attack_count": attacks.size(), "weapon_count": weapons.size(), "projectile_count": projectiles.size()}

## Pure deterministic resolution. The returned status describes the combat
## rule result; persistent world effects are only committed by the transaction
## methods below, which feed the existing Fact/Change pipeline.
func resolve(combat_request, query_context: Dictionary = {}):
        if combat_request == null:
                return _result(null, "rejected", "combat.request_missing", "CombatRequest 不能为空。")
        var key: String = combat_request.idempotency_key
        var digest: String = combat_request.identity_digest()
        if preview_results.has(key):
                var prior: Dictionary = preview_results[key]
                if str(prior.get("digest", "")) != digest:
                        return _result(combat_request, "rejected", "combat.idempotency_conflict", "同一幂等键对应不同战斗请求，已拒绝覆盖。")
                var replayed = prior.get("result")
                var replay = replayed.duplicate_result()
                replay.idempotent = true
                return replay
        var computed := _compute(combat_request, query_context)
        var result = computed.get("result")
        if result == null:
                return _result(combat_request, "rejected", "combat.result_missing", "CombatResolver 没有产生有效结果。")
        preview_results[key] = {"digest": digest, "result": result.duplicate_result()}
        return result

func preview_native(value: Variant, query_context: Dictionary = {}) -> Dictionary:
        var parsed: Dictionary = REQUEST.from_native(value)
        if not parsed.ok:
                return {"ok": false, "code": "combat.request_invalid", "reason_zh": parsed.get("reason_zh", "CombatRequest 无效。"), "errors": parsed.get("errors", [])}
        var result = resolve(parsed.value, query_context)
        return {"ok": result.status == "committed", "result": result.to_native(), "code": result.code, "reason_zh": result.reason_zh}

func preflight_transaction(transaction: GMDomainTransaction) -> Dictionary:
        if isolated:
                return _blocked("combat.resolver_isolated", "CombatResolver 处于恢复失败隔离状态，拒绝新的战斗事务。", isolation_report)
        if transaction == null or transaction.request == null:
                return _blocked("combat.transaction_request_missing", "战斗事务缺少 ActivationRequest。")
        var parsed := _request_from_transaction(transaction)
        if not parsed.ok:
                return _blocked("combat.request_invalid", str(parsed.get("reason_zh", "CombatRequest 无效。")), parsed)
        var computed := _compute(parsed.value, _query_context(transaction))
        var result = computed.get("result")
        if result == null or result.status == "rejected":
                return _blocked("combat.request_rejected", result.reason_zh if result != null else "CombatRequest 被拒绝。", {"result": result.to_native() if result != null else {}})
        if not result.status == "committed":
                return _blocked("combat.rule_blocked", result.reason_zh, {"result": result.to_native()})
        var intent_check: Dictionary = CONTRACT.p19_intent(parsed.value.p19_intent)
        if not intent_check.ok:
                return _blocked("combat.p19_intent_invalid", str(intent_check.get("reason_zh", "P19 交易意图无效。")), intent_check)
        var has_p19: bool = not parsed.value.p19_intent.is_empty()
        if has_p19:
                if p19_resolver == null or not is_instance_valid(p19_resolver):
                        return _blocked("combat.p19_resolver_missing", "武器弹药或资源成本必须通过现有 P19 Resolver。")
                _install_p19_overlay(transaction, parsed.value)
                var p19_check: Dictionary = p19_resolver.preflight_transaction(transaction)
                if not p19_check.ok:
                        return p19_check
        var plan := {"request": parsed.value.to_native(), "result": result.to_native(), "has_p19": has_p19, "p19_intent": parsed.value.p19_intent.duplicate(true), "p19_preflight": {}, "p19_commit": {}}
        if has_p19:
                plan["p19_preflight"] = p19_resolver.planned_transaction_plan(transaction.transaction_id) if p19_resolver.has_method("planned_transaction_plan") else {}
        plans[transaction.transaction_id] = plan
        return {"ok": true, "stage": "PREFLIGHT", "combat_result": result.to_native(), "p19": has_p19, "inputs": [], "outputs": [], "changeset": []}

func reserve_transaction(transaction: GMDomainTransaction) -> Dictionary:
        var plan: Dictionary = plans.get(transaction.transaction_id, {})
        if plan.is_empty(): return _blocked("combat.plan_missing", "战斗事务没有预检计划。")
        var reservations: Array = []
        if bool(plan.get("has_p19", false)):
                if p19_resolver == null: return _blocked("combat.p19_resolver_missing", "P19 Resolver 不可用，未进入预留。")
                _install_p19_overlay_from_plan(transaction, plan)
                var p19_result: Dictionary = p19_resolver.reserve_transaction(transaction)
                if not p19_result.ok: return p19_result
                reservations.append_array(p19_result.get("reservations", []))
        plan["reservations"] = reservations.duplicate(true)
        plans[transaction.transaction_id] = plan
        return {"ok": true, "stage": "RESERVE", "reservations": reservations}

func commit_transaction(transaction: GMDomainTransaction) -> Dictionary:
        var plan: Dictionary = plans.get(transaction.transaction_id, {})
        if plan.is_empty(): return _blocked("combat.plan_missing", "战斗事务没有预检计划。")
        var p19_commit: Dictionary = {"ok": true}
        if bool(plan.get("has_p19", false)):
                if p19_resolver == null: return _blocked("combat.p19_resolver_missing", "P19 Resolver 不可用，未提交任何消耗。")
                _install_p19_overlay_from_plan(transaction, plan)
                p19_commit = p19_resolver.commit_transaction(transaction)
                if not p19_commit.ok: return p19_commit
        var result_data: Dictionary = plan.get("result", {}).duplicate(true)
        var request_data: Dictionary = plan.get("request", {}).duplicate(true)
        var request = REQUEST.from_native(request_data).value
        var result = RESULT.from_native(result_data).value
        var payload := {
                "event_id": "gm.fact.combat.%s" % transaction.idempotency_key.sha256_text(),
                "combat_request": request.to_native(),
                "combat_result": result.to_native(),
                "operation": result.operation,
                "amount": result.amount,
                "source_id": request.source_id,
                "target_id": request.target_id,
                "targets": [request.target_id],
                "p19_intent": request.p19_intent.duplicate(true),
                "p19_commit": p19_commit.duplicate(true),
                "resolver_id": RESOLVER_ID,
                "commit_scope": "combat_rule_then_domain_transaction",
        }
        var change_draft := {
                "entity_id": request.target_id,
                "operation": "combat.%s" % result.operation,
                "field": "combat_resolution",
                "before": null,
                "after": {"amount": result.amount, "hit_confirmed": result.hit_confirmed, "attack_id": request.attack_id},
                "metadata": {"authority": "gm.fact.combat.resolution.v1", "source_id": request.source_id, "target_id": request.target_id},
        }
        var cue_id := "gm.cue.combat.hit" if result.hit_confirmed else "gm.cue.combat.miss"
        var cue := {"cue_id": cue_id, "instance_id": transaction.ability_instance_id, "parameters": {"operation": result.operation, "amount": result.amount, "target_id": request.target_id, "attack_id": request.attack_id}}
        plan["p19_commit"] = p19_commit.duplicate(true)
        plans[transaction.transaction_id] = plan
        return {"ok": true, "stage": "COMMIT", "payload": payload, "inputs": p19_commit.get("inputs", []) if p19_commit is Dictionary else [], "outputs": p19_commit.get("outputs", []) if p19_commit is Dictionary else [], "tags": ["gm.combat", "gm.combat.%s" % result.operation, "gm.combat.%s" % request.mode], "visibility": {"public": false, "witnesses": []}, "changeset": [change_draft] + (p19_commit.get("changeset", []) if p19_commit is Dictionary else []), "cues": [cue]}

func rollback_transaction(transaction: GMDomainTransaction, reason_zh: String) -> Dictionary:
        var plan: Dictionary = plans.get(transaction.transaction_id, {})
        var p19_result: Dictionary = {"ok": true, "skipped": true}
        if not plan.is_empty() and bool(plan.get("has_p19", false)) and p19_resolver != null:
                _install_p19_overlay_from_plan(transaction, plan)
                p19_result = p19_resolver.rollback_transaction(transaction, reason_zh)
        plans.erase(transaction.transaction_id)
        return {"ok": bool(p19_result.get("ok", false)), "stage": "ROLLBACK", "rolled_back": bool(p19_result.get("ok", false)), "p19": p19_result}

func capture_transaction_state(_transaction: GMDomainTransaction) -> Dictionary:
        if isolated: return _blocked("combat.resolver_isolated", "CombatResolver 已隔离，不能建立新的恢复点。", isolation_report)
        var p19_snapshot: Variant = null
        if p19_resolver != null and p19_resolver.has_method("capture_transaction_state"):
                var value: Variant = p19_resolver.capture_transaction_state(_transaction)
                if value is Dictionary and not bool(value.get("ok", false)): return value
                if value is Dictionary: p19_snapshot = value.get("snapshot", null)
        return {"ok": true, "contract": "gm.combat.recovery.v1", "snapshot": {"p19": p19_snapshot}}

func restore_transaction_state(transaction: GMDomainTransaction, snapshot: Variant) -> Dictionary:
        if not snapshot is Dictionary or not snapshot.has("p19") or snapshot.size() != 1:
                return _blocked("combat.recovery_snapshot_invalid", "CombatResolver 恢复点字段集合无效。")
        var p19_value: Variant = snapshot.get("p19", null)
        var restored: Dictionary = {"ok": true, "skipped": true}
        if p19_value != null:
                if p19_resolver == null or not p19_resolver.has_method("restore_transaction_state"):
                        return _blocked("combat.p19_recovery_missing", "P19 恢复接口不可用，不能安全恢复战斗事务。")
                restored = p19_resolver.restore_transaction_state(transaction, p19_value)
        plans.erase(transaction.transaction_id)
        return restored

func release_transaction_reservations(transaction: GMDomainTransaction) -> Dictionary:
        var released: Dictionary = {"ok": true, "skipped": true}
        if p19_resolver != null and p19_resolver.has_method("release_transaction_reservations"):
                released = p19_resolver.release_transaction_reservations(transaction)
        return released

func isolate_transaction_state(transaction: GMDomainTransaction, failure: Dictionary) -> Dictionary:
        isolated = true
        isolation_report = {"transaction_id": transaction.transaction_id if transaction != null else "", "failure": failure.duplicate(true)}
        if p19_resolver != null and p19_resolver.has_method("isolate_transaction_state"):
                p19_resolver.isolate_transaction_state(transaction, failure)
        return {"ok": true, "isolated": true, "resolver_id": RESOLVER_ID, "transaction_id": isolation_report.transaction_id}

func finalize_transaction(transaction: GMDomainTransaction) -> Dictionary:
        var finalized: Dictionary = {"ok": true, "skipped": true}
        if p19_resolver != null and p19_resolver.has_method("finalize_transaction"):
                finalized = p19_resolver.finalize_transaction(transaction)
        plans.erase(transaction.transaction_id)
        return finalized

func version_for(key: String) -> int:
        if p19_resolver != null and p19_resolver.has_method("version_for"):
                return int(p19_resolver.version_for(key))
        return 0

func build_candidate(request: GMAbilityActivationRequest, chain: GMCausalChain) -> GMCandidateResult:
        return GMCandidateResult.from_request(request, chain, 1.0, ["P22 CombatResolver 将同一份纯 CombatRequest 交给实时或回合调度器。"])

func _compute(request, query_context: Dictionary) -> Dictionary:
        var validation: Dictionary = request.validate()
        if not validation.ok:
                return {"result": _result(request, "rejected", "combat.request_invalid", validation.errors[0] if not validation.errors.is_empty() else "CombatRequest 无效。")}
        var context_check := CONTRACT.pure(query_context)
        if not context_check.ok:
                return {"result": _result(request, "blocked", "combat.hit_query_context_invalid", "命中查询上下文不是可传递的纯数据。")}
        var attack = attacks.get(request.attack_id, null)
        if attack == null:
                return {"result": _result(request, "rejected", "combat.attack_missing", "AttackDefinition 未注册：%s。" % request.attack_id)}
        var attack_check: Dictionary = attack.validate()
        if not attack_check.ok:
                return {"result": _result(request, "rejected", "combat.attack_invalid", "AttackDefinition 未通过运行时校验。")}
        if not request.weapon_id.is_empty():
                var weapon = weapons.get(request.weapon_id, null)
                if weapon == null: return {"result": _result(request, "rejected", "combat.weapon_missing", "WeaponDefinition 未注册：%s。" % request.weapon_id)}
                if weapon.attack_ref != attack.attack_id: return {"result": _result(request, "rejected", "combat.weapon_attack_mismatch", "WeaponDefinition 与 AttackDefinition 引用不一致。")}
                if not attack.weapon_ref.is_empty() and attack.weapon_ref != weapon.weapon_id: return {"result": _result(request, "rejected", "combat.weapon_ref_mismatch", "AttackDefinition 与 WeaponDefinition 引用不一致。")}
        if not request.projectile_id.is_empty():
                var projectile = projectiles.get(request.projectile_id, null)
                if projectile == null: return {"result": _result(request, "rejected", "combat.projectile_missing", "ProjectileDefinition 未注册：%s。" % request.projectile_id)}
                if not attack.projectile_ref.is_empty() and attack.projectile_ref != projectile.projectile_id: return {"result": _result(request, "rejected", "combat.projectile_ref_mismatch", "AttackDefinition 与 ProjectileDefinition 引用不一致。")}
        var query_result: Dictionary = hit_query.query(request.hit_spec, query_context) if hit_query != null and hit_query.has_method("query") else {"ok": false, "code": "combat.hit_query_missing", "reason_zh": "HitQuery 适配器未安装。"}
        var query_check := CONTRACT.pure(query_result)
        if not query_check.ok:
                return {"result": _result(request, "blocked", "combat.hit_query_result_invalid", "命中查询结果不是可保存的纯数据。")}
        if not bool(query_result.get("ok", false)):
                return {"result": _result(request, "blocked", str(query_result.get("code", "combat.hit_query_blocked")), str(query_result.get("reason_zh", "命中查询被阻断。")))}
        var hit := bool(query_result.get("hit", false))
        var amount: float = attack.magnitude if hit else 0.0
        var result = _result(request, "committed", "combat.hit" if hit else "combat.miss", "命中并形成战斗结果。" if hit else "未命中；形成零效果战斗结果。", amount, hit)
        result.operation = attack.operation
        result.metadata = {"attack_kind": attack.attack_kind, "effect_ref": attack.effect_ref, "query": query_result.duplicate(true), "rule_version": "gm.combat.rules.v1"}
        return {"result": result}

func _request_from_transaction(transaction: GMDomainTransaction) -> Dictionary:
        var raw: Variant = transaction.request.event_data.get(COMBAT_REQUEST_KEY, null)
        return REQUEST.from_native(raw)

func _query_context(transaction: GMDomainTransaction) -> Dictionary:
        var context: Variant = transaction.request.event_data.get("combat_query_context", {})
        return context.duplicate(true) if context is Dictionary else {}

func _install_p19_overlay(transaction: GMDomainTransaction, request) -> void:
        for field in P19_OVERLAY_FIELDS:
                if request.p19_intent.has(field): transaction.request.event_data[field] = request.p19_intent[field]
        transaction.request.event_data["p19_operation"] = str(request.p19_intent.get("operation", ""))
        if not transaction.request.event_data.has("source_id"): transaction.request.event_data["source_id"] = request.source_id
        if not transaction.request.event_data.has("target_id"): transaction.request.event_data["target_id"] = request.target_id

func _install_p19_overlay_from_plan(transaction: GMDomainTransaction, plan: Dictionary) -> void:
        var intent: Dictionary = plan.get("p19_intent", {}) if plan.get("p19_intent", {}) is Dictionary else {}
        for field in P19_OVERLAY_FIELDS:
                if intent.has(field): transaction.request.event_data[field] = intent[field]
        transaction.request.event_data["p19_operation"] = str(intent.get("operation", ""))
        var request: Dictionary = plan.get("request", {}) if plan.get("request", {}) is Dictionary else {}
        if not transaction.request.event_data.has("source_id"): transaction.request.event_data["source_id"] = str(request.get("source_id", ""))
        if not transaction.request.event_data.has("target_id"): transaction.request.event_data["target_id"] = str(request.get("target_id", ""))

func _register(registry: Dictionary, identifier: String, definition: RefCounted) -> Dictionary:
        if registry.has(identifier) and registry[identifier].to_native() != definition.to_native():
                return CONTRACT.failure("combat.definition_duplicate", "P22 定义 ID 已注册为不同内容：%s。" % identifier)
        registry[identifier] = definition
        return {"ok": true, "code": "combat.definition_registered", "id": identifier}

func _result(request, p_status: String, p_code: String, p_reason_zh: String, p_amount: float = 0.0, p_hit: bool = false):
        var result = RESULT.for_request(request, p_status, p_code, p_reason_zh, p_amount, p_hit)
        result.result_id = "gm.combat.result.%s" % CONTRACT.digest({"request_id": result.request_id, "idempotency_key": result.idempotency_key, "code": p_code, "mode": result.mode})
        return result

func _blocked(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
        var result := {"ok": false, "code": code, "reason_zh": reason_zh}
        if not details.is_empty(): result.merge(details, true)
        return result
