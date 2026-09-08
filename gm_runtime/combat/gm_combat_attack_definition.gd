class_name GMCombatAttackDefinition
extends RefCounted

const SCHEMA_VERSION := "gm.combat.attack.v1"
const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")
const FIELDS := ["schema_version", "attack_id", "display_name_zh", "attack_kind", "operation", "magnitude", "range", "cooldown_seconds", "weapon_ref", "projectile_ref", "effect_ref", "tags", "metadata"]
const ATTACK_KINDS := ["melee", "weapon", "projectile"]
const OPERATIONS := ["damage", "heal"]

var schema_version := SCHEMA_VERSION
var attack_id := ""
var display_name_zh := ""
var attack_kind := "melee"
var operation := "damage"
var magnitude := 0.0
var range := 0.0
var cooldown_seconds := 0.0
var weapon_ref := ""
var projectile_ref := ""
var effect_ref := ""
var tags: Array[String] = []
var metadata: Dictionary = {}

func configure(p_attack_id: String, p_display_name_zh: String, p_attack_kind: String, p_operation: String, p_magnitude: float, p_range: float = 0.0, p_cooldown_seconds: float = 0.0, p_weapon_ref: String = "", p_projectile_ref: String = "", p_effect_ref: String = "", p_tags: Array = [], p_metadata: Dictionary = {}):
        attack_id = p_attack_id
        display_name_zh = p_display_name_zh
        attack_kind = p_attack_kind
        operation = p_operation
        magnitude = p_magnitude
        range = p_range
        cooldown_seconds = p_cooldown_seconds
        weapon_ref = p_weapon_ref
        projectile_ref = p_projectile_ref
        effect_ref = p_effect_ref
        tags.clear()
        for value in p_tags:
                tags.append(str(value))
        metadata = p_metadata.duplicate(true)
        return self

func to_native() -> Dictionary:
        return {
                "schema_version": schema_version,
                "attack_id": attack_id,
                "display_name_zh": display_name_zh,
                "attack_kind": attack_kind,
                "operation": operation,
                "magnitude": magnitude,
                "range": range,
                "cooldown_seconds": cooldown_seconds,
                "weapon_ref": weapon_ref,
                "projectile_ref": projectile_ref,
                "effect_ref": effect_ref,
                "tags": tags.duplicate(),
                "metadata": metadata.duplicate(true),
        }

func validate() -> Dictionary:
        var errors: Array[String] = []
        errors.append_array(CONTRACT.unknown_fields(to_native(), FIELDS, "AttackDefinition"))
        if schema_version != SCHEMA_VERSION: errors.append("AttackDefinition schema_version 无效。")
        if not CONTRACT.stable_id(attack_id) or not attack_id.begins_with("gm.attack."): errors.append("AttackDefinition attack_id 必须使用 gm.attack.* 稳定身份。")
        if not CONTRACT.text(display_name_zh): errors.append("AttackDefinition 必须有中文名称。")
        if not ATTACK_KINDS.has(attack_kind): errors.append("AttackDefinition attack_kind 不是统一三类之一。")
        if not OPERATIONS.has(operation): errors.append("AttackDefinition operation 不是 damage/heal。")
        if not CONTRACT.finite_positive(magnitude): errors.append("AttackDefinition magnitude 必须为有限正数。")
        if not CONTRACT.finite_nonnegative(range): errors.append("AttackDefinition range 必须为有限非负数。")
        if not CONTRACT.finite_nonnegative(cooldown_seconds): errors.append("AttackDefinition cooldown_seconds 必须为有限非负数。")
        if not CONTRACT.stable_id(weapon_ref, true): errors.append("AttackDefinition weapon_ref 必须是稳定 ID 或空值。")
        if not CONTRACT.stable_id(projectile_ref, true): errors.append("AttackDefinition projectile_ref 必须是稳定 ID 或空值。")
        if not CONTRACT.stable_id(effect_ref, true): errors.append("AttackDefinition effect_ref 必须是稳定 ID 或空值。")
        if not CONTRACT.string_array(tags): errors.append("AttackDefinition tags 必须是稳定 ID 数组。")
        var pure_check := CONTRACT.pure(to_native())
        if not pure_check.ok: errors.append_array(pure_check.errors)
        return {"ok": errors.is_empty(), "code": "combat.attack.valid" if errors.is_empty() else "combat.attack.invalid", "errors": errors}

static func from_native(value: Variant) -> Dictionary:
        if not value is Dictionary:
                return {"ok": false, "code": "combat.attack.type_invalid", "reason_zh": "AttackDefinition 必须是字典纯值。"}
        var unknown := CONTRACT.unknown_fields(value, FIELDS, "AttackDefinition")
        if not unknown.is_empty(): return {"ok": false, "code": "combat.attack.unknown_field", "reason_zh": unknown[0], "errors": unknown}
        if not CONTRACT.exact(value, FIELDS): return {"ok": false, "code": "combat.attack.fields_incomplete", "reason_zh": "AttackDefinition 字段集合必须完整。"}
        if not CONTRACT.exact_field_types(value, ["schema_version", "attack_id", "display_name_zh", "attack_kind", "operation", "weapon_ref", "projectile_ref", "effect_ref"], ["magnitude", "range", "cooldown_seconds"], [], ["tags"], ["metadata"]):
                return {"ok": false, "code": "combat.attack.field_type_invalid", "reason_zh": "AttackDefinition 字段类型无效。"}
        var result = load("res://gm_runtime/combat/gm_combat_attack_definition.gd").new()
        result.schema_version = str(value.get("schema_version", ""))
        result.attack_id = str(value.get("attack_id", ""))
        result.display_name_zh = str(value.get("display_name_zh", ""))
        result.attack_kind = str(value.get("attack_kind", ""))
        result.operation = str(value.get("operation", ""))
        result.magnitude = float(value.get("magnitude", 0.0))
        result.range = float(value.get("range", 0.0))
        result.cooldown_seconds = float(value.get("cooldown_seconds", 0.0))
        result.weapon_ref = str(value.get("weapon_ref", ""))
        result.projectile_ref = str(value.get("projectile_ref", ""))
        result.effect_ref = str(value.get("effect_ref", ""))
        result.tags.clear()
        if value.get("tags", []) is Array:
                for tag in value.tags: result.tags.append(str(tag))
        result.metadata = value.get("metadata", {}).duplicate(true) if value.get("metadata", {}) is Dictionary else {}
        var checked: Dictionary = result.validate()
        if not checked.ok:
                return {"ok": false, "code": checked.code, "reason_zh": checked.errors[0] if not checked.errors.is_empty() else "AttackDefinition 无效。", "errors": checked.errors}
        return {"ok": true, "value": result}
