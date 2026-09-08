class_name GMCombatResult
extends RefCounted

const SCHEMA_VERSION := "gm.combat.result.v1"
const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")
const REQUEST := preload("res://gm_runtime/combat/gm_combat_request.gd")
const FIELDS := ["schema_version", "result_id", "request_id", "idempotency_key", "status", "code", "reason_zh", "mode", "source_id", "target_id", "attack_id", "operation", "amount", "hit_confirmed", "commit_scope", "fact_id", "change_ids", "cue_ids", "transaction_id", "idempotent", "metadata"]
const STATUSES := ["committed", "blocked", "rejected"]
const OPERATIONS := ["damage", "heal"]

var schema_version := SCHEMA_VERSION
var result_id := ""
var request_id := ""
var idempotency_key := ""
var status := "rejected"
var code := "combat.result_invalid"
var reason_zh := "战斗结果无效。"
var mode := "realtime"
var source_id := ""
var target_id := ""
var attack_id := ""
var operation := "damage"
var amount := 0.0
var hit_confirmed := false
var commit_scope := "combat_rule"
var fact_id := ""
var change_ids: Array[String] = []
var cue_ids: Array[String] = []
var transaction_id := ""
var idempotent := false
var metadata: Dictionary = {}

static func for_request(request, p_status: String, p_code: String, p_reason_zh: String, p_amount: float = 0.0, p_hit_confirmed: bool = false):
        var result = load("res://gm_runtime/combat/gm_combat_result.gd").new()
        if request != null:
                result.request_id = request.request_id
                result.idempotency_key = request.idempotency_key
                result.mode = request.mode
                result.source_id = request.source_id
                result.target_id = request.target_id
                result.attack_id = request.attack_id
        result.result_id = "gm.combat.result.%s" % CONTRACT.digest({"request_id": result.request_id, "idempotency_key": result.idempotency_key, "code": p_code})
        result.status = p_status
        result.code = p_code
        result.reason_zh = p_reason_zh
        result.amount = p_amount
        result.hit_confirmed = p_hit_confirmed
        return result

func to_native() -> Dictionary:
        return {"schema_version": schema_version, "result_id": result_id, "request_id": request_id, "idempotency_key": idempotency_key, "status": status, "code": code, "reason_zh": reason_zh, "mode": mode, "source_id": source_id, "target_id": target_id, "attack_id": attack_id, "operation": operation, "amount": amount, "hit_confirmed": hit_confirmed, "commit_scope": commit_scope, "fact_id": fact_id, "change_ids": change_ids.duplicate(), "cue_ids": cue_ids.duplicate(), "transaction_id": transaction_id, "idempotent": idempotent, "metadata": metadata.duplicate(true)}

func validate() -> Dictionary:
        var errors: Array[String] = []
        errors.append_array(CONTRACT.unknown_fields(to_native(), FIELDS, "CombatResult"))
        if schema_version != SCHEMA_VERSION: errors.append("CombatResult schema_version 无效。")
        if not CONTRACT.stable_id(result_id) or not result_id.begins_with("gm.combat.result."): errors.append("CombatResult result_id 必须使用 gm.combat.result.* 稳定身份。")
        if not CONTRACT.stable_id(request_id) or not request_id.begins_with("gm.combat.request."): errors.append("CombatResult request_id 身份无效。")
        if not CONTRACT.text(idempotency_key) or idempotency_key != idempotency_key.strip_edges(): errors.append("CombatResult idempotency_key 不能为空。")
        if not STATUSES.has(status): errors.append("CombatResult status 只能是 committed/blocked/rejected。")
        if not CONTRACT.stable_id(code): errors.append("CombatResult code 必须是稳定 ID。")
        if not CONTRACT.text(reason_zh): errors.append("CombatResult reason_zh 必须是有限文本。")
        if not REQUEST.MODES.has(mode): errors.append("CombatResult mode 无效。")
        for field in ["source_id", "target_id", "attack_id"]:
                if not CONTRACT.stable_id(get(field)): errors.append("CombatResult %s 身份无效。" % field)
        if not OPERATIONS.has(operation): errors.append("CombatResult operation 无效。")
        if not CONTRACT.finite_nonnegative(amount): errors.append("CombatResult amount 必须为有限非负数。")
        if not CONTRACT.stable_id(fact_id, true) or not CONTRACT.stable_id(transaction_id, true): errors.append("CombatResult 事实/事务引用必须是稳定 ID 或空值。")
        if not CONTRACT.string_array(change_ids) or not CONTRACT.string_array(cue_ids): errors.append("CombatResult change_ids/cue_ids 必须是稳定 ID 数组。")
        if not CONTRACT.stable_id(commit_scope): errors.append("CombatResult commit_scope 必须是稳定 ID。")
        if typeof(hit_confirmed) != TYPE_BOOL or typeof(idempotent) != TYPE_BOOL: errors.append("CombatResult hit_confirmed/idempotent 必须是布尔值。")
        var pure_check := CONTRACT.pure(to_native())
        if not pure_check.ok: errors.append_array(pure_check.errors)
        return {"ok": errors.is_empty(), "code": "combat.result.valid" if errors.is_empty() else "combat.result.invalid", "errors": errors}

func duplicate_result():
        var parsed = load("res://gm_runtime/combat/gm_combat_result.gd").from_native(to_native())
        return parsed.value if parsed.ok else load("res://gm_runtime/combat/gm_combat_result.gd").new()

static func from_native(value: Variant) -> Dictionary:
        if not value is Dictionary: return {"ok": false, "code": "combat.result.type_invalid", "reason_zh": "CombatResult 必须是字典纯值。"}
        var unknown := CONTRACT.unknown_fields(value, FIELDS, "CombatResult")
        if not unknown.is_empty(): return {"ok": false, "code": "combat.result.unknown_field", "reason_zh": unknown[0], "errors": unknown}
        if not CONTRACT.exact(value, FIELDS): return {"ok": false, "code": "combat.result.fields_incomplete", "reason_zh": "CombatResult 字段集合必须完整。"}
        if not CONTRACT.exact_field_types(value, ["schema_version", "result_id", "request_id", "idempotency_key", "status", "code", "reason_zh", "mode", "source_id", "target_id", "attack_id", "operation", "commit_scope", "fact_id", "transaction_id"], ["amount"], ["hit_confirmed", "idempotent"], ["change_ids", "cue_ids"], ["metadata"]):
                return {"ok": false, "code": "combat.result.field_type_invalid", "reason_zh": "CombatResult 字段类型无效。"}
        var result = load("res://gm_runtime/combat/gm_combat_result.gd").new()
        result.schema_version = str(value.get("schema_version", ""))
        result.result_id = str(value.get("result_id", ""))
        result.request_id = str(value.get("request_id", ""))
        result.idempotency_key = str(value.get("idempotency_key", ""))
        result.status = str(value.get("status", ""))
        result.code = str(value.get("code", ""))
        result.reason_zh = str(value.get("reason_zh", ""))
        result.mode = str(value.get("mode", ""))
        result.source_id = str(value.get("source_id", ""))
        result.target_id = str(value.get("target_id", ""))
        result.attack_id = str(value.get("attack_id", ""))
        result.operation = str(value.get("operation", ""))
        result.amount = float(value.get("amount", 0.0))
        result.hit_confirmed = bool(value.get("hit_confirmed", false))
        result.commit_scope = str(value.get("commit_scope", ""))
        result.fact_id = str(value.get("fact_id", ""))
        result.change_ids.clear()
        if value.get("change_ids", []) is Array: for item in value.change_ids: result.change_ids.append(str(item))
        result.cue_ids.clear()
        if value.get("cue_ids", []) is Array: for item in value.cue_ids: result.cue_ids.append(str(item))
        result.transaction_id = str(value.get("transaction_id", ""))
        result.idempotent = bool(value.get("idempotent", false))
        result.metadata = value.get("metadata", {}).duplicate(true) if value.get("metadata", {}) is Dictionary else {}
        var checked: Dictionary = result.validate()
        if not checked.ok: return {"ok": false, "code": checked.code, "reason_zh": checked.errors[0] if not checked.errors.is_empty() else "CombatResult 无效。", "errors": checked.errors}
        return {"ok": true, "value": result}
