class_name GMCombatRequest
extends RefCounted

const SCHEMA_VERSION := "gm.combat.request.v1"
const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")
const HIT_SPEC := preload("res://gm_runtime/combat/gm_combat_hit_spec.gd")
const FIELDS := ["schema_version", "request_id", "idempotency_key", "mode", "source_id", "target_id", "ability_id", "attack_id", "weapon_id", "projectile_id", "hit_spec", "p19_intent", "metadata"]
const MODES := ["realtime", "turn"]

var schema_version := SCHEMA_VERSION
var request_id := ""
var idempotency_key := ""
var mode := "realtime"
var source_id := ""
var target_id := ""
var ability_id := ""
var attack_id := ""
var weapon_id := ""
var projectile_id := ""
var hit_spec
var p19_intent: Dictionary = {}
var metadata: Dictionary = {}

func configure(p_request_id: String, p_idempotency_key: String, p_mode: String, p_source_id: String, p_target_id: String, p_ability_id: String, p_attack_id: String, p_hit_spec, p_weapon_id: String = "", p_projectile_id: String = "", p_p19_intent: Dictionary = {}, p_metadata: Dictionary = {}):
        request_id = p_request_id
        idempotency_key = p_idempotency_key
        mode = p_mode
        source_id = p_source_id
        target_id = p_target_id
        ability_id = p_ability_id
        attack_id = p_attack_id
        hit_spec = p_hit_spec
        weapon_id = p_weapon_id
        projectile_id = p_projectile_id
        p19_intent = p_p19_intent.duplicate(true)
        metadata = p_metadata.duplicate(true)
        return self

func to_native() -> Dictionary:
        return {"schema_version": schema_version, "request_id": request_id, "idempotency_key": idempotency_key, "mode": mode, "source_id": source_id, "target_id": target_id, "ability_id": ability_id, "attack_id": attack_id, "weapon_id": weapon_id, "projectile_id": projectile_id, "hit_spec": hit_spec.to_native() if hit_spec != null else {}, "p19_intent": p19_intent.duplicate(true), "metadata": metadata.duplicate(true)}

func validate() -> Dictionary:
        var errors: Array[String] = []
        errors.append_array(CONTRACT.unknown_fields(to_native(), FIELDS, "CombatRequest"))
        if schema_version != SCHEMA_VERSION: errors.append("CombatRequest schema_version 无效。")
        if not CONTRACT.stable_id(request_id) or not request_id.begins_with("gm.combat.request."): errors.append("CombatRequest request_id 必须使用 gm.combat.request.* 稳定身份。")
        if not CONTRACT.text(idempotency_key) or idempotency_key != idempotency_key.strip_edges(): errors.append("CombatRequest idempotency_key 必须是非空稳定运行时键。")
        if not MODES.has(mode): errors.append("CombatRequest mode 只能是 realtime 或 turn。")
        for field in ["source_id", "target_id", "ability_id", "attack_id"]:
                if not CONTRACT.stable_id(get(field)): errors.append("CombatRequest %s 必须是稳定 ID。" % field)
        if not CONTRACT.stable_id(weapon_id, true): errors.append("CombatRequest weapon_id 必须是稳定 ID 或空值。")
        if not CONTRACT.stable_id(projectile_id, true): errors.append("CombatRequest projectile_id 必须是稳定 ID 或空值。")
        if hit_spec == null: errors.append("CombatRequest 缺少 HitSpec。")
        else:
                var hit_check: Dictionary = hit_spec.validate()
                if not hit_check.ok: errors.append_array(hit_check.errors)
                elif hit_spec.source_id != source_id or hit_spec.target_id != target_id: errors.append("CombatRequest 与 HitSpec 的 source/target 身份不一致。")
        var p19_check := CONTRACT.p19_intent(p19_intent)
        if not p19_check.ok: errors.append_array(p19_check.errors)
        var pure_check := CONTRACT.pure(to_native())
        if not pure_check.ok: errors.append_array(pure_check.errors)
        return {"ok": errors.is_empty(), "code": "combat.request.valid" if errors.is_empty() else "combat.request.invalid", "errors": errors}

static func from_native(value: Variant) -> Dictionary:
        if not value is Dictionary: return {"ok": false, "code": "combat.request.type_invalid", "reason_zh": "CombatRequest 必须是字典纯值。"}
        var unknown := CONTRACT.unknown_fields(value, FIELDS, "CombatRequest")
        if not unknown.is_empty(): return {"ok": false, "code": "combat.request.unknown_field", "reason_zh": unknown[0], "errors": unknown}
        if not CONTRACT.exact(value, FIELDS): return {"ok": false, "code": "combat.request.fields_incomplete", "reason_zh": "CombatRequest 字段集合必须完整。"}
        if not CONTRACT.exact_field_types(value, ["schema_version", "request_id", "idempotency_key", "mode", "source_id", "target_id", "ability_id", "attack_id", "weapon_id", "projectile_id"], [], [], [], ["hit_spec", "p19_intent", "metadata"]):
                return {"ok": false, "code": "combat.request.field_type_invalid", "reason_zh": "CombatRequest 字段类型无效。"}
        var hit_parsed := HIT_SPEC.from_native(value.get("hit_spec", {}))
        var result = load("res://gm_runtime/combat/gm_combat_request.gd").new()
        result.schema_version = str(value.get("schema_version", ""))
        result.request_id = str(value.get("request_id", ""))
        result.idempotency_key = str(value.get("idempotency_key", ""))
        result.mode = str(value.get("mode", ""))
        result.source_id = str(value.get("source_id", ""))
        result.target_id = str(value.get("target_id", ""))
        result.ability_id = str(value.get("ability_id", ""))
        result.attack_id = str(value.get("attack_id", ""))
        result.weapon_id = str(value.get("weapon_id", ""))
        result.projectile_id = str(value.get("projectile_id", ""))
        result.hit_spec = hit_parsed.value if hit_parsed.ok else null
        result.p19_intent = value.get("p19_intent", {}).duplicate(true) if value.get("p19_intent", {}) is Dictionary else {}
        result.metadata = value.get("metadata", {}).duplicate(true) if value.get("metadata", {}) is Dictionary else {}
        var checked: Dictionary = result.validate()
        if not checked.ok: return {"ok": false, "code": checked.code, "reason_zh": checked.errors[0] if not checked.errors.is_empty() else "CombatRequest 无效。", "errors": checked.errors, "hit_error": hit_parsed}
        return {"ok": true, "value": result}

func identity_digest() -> String:
        return CONTRACT.digest(to_native())
