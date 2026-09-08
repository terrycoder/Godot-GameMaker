class_name GMCombatWeaponDefinition
extends RefCounted

const SCHEMA_VERSION := "gm.combat.weapon.v1"
const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")
const FIELDS := ["schema_version", "weapon_id", "display_name_zh", "item_ref", "attack_ref", "projectile_ref", "ammo_item_ref", "resource_costs", "tags", "metadata"]

var schema_version := SCHEMA_VERSION
var weapon_id := ""
var display_name_zh := ""
var item_ref := ""
var attack_ref := ""
var projectile_ref := ""
var ammo_item_ref := ""
var resource_costs: Array[Dictionary] = []
var tags: Array[String] = []
var metadata: Dictionary = {}

func configure(p_weapon_id: String, p_display_name_zh: String, p_item_ref: String, p_attack_ref: String, p_projectile_ref: String = "", p_ammo_item_ref: String = "", p_resource_costs: Array = [], p_tags: Array = [], p_metadata: Dictionary = {}):
        weapon_id = p_weapon_id
        display_name_zh = p_display_name_zh
        item_ref = p_item_ref
        attack_ref = p_attack_ref
        projectile_ref = p_projectile_ref
        ammo_item_ref = p_ammo_item_ref
        resource_costs.clear()
        for row in p_resource_costs:
                if row is Dictionary: resource_costs.append(row.duplicate(true))
        tags.clear()
        for value in p_tags: tags.append(str(value))
        metadata = p_metadata.duplicate(true)
        return self

func to_native() -> Dictionary:
        return {
                "schema_version": schema_version,
                "weapon_id": weapon_id,
                "display_name_zh": display_name_zh,
                "item_ref": item_ref,
                "attack_ref": attack_ref,
                "projectile_ref": projectile_ref,
                "ammo_item_ref": ammo_item_ref,
                "resource_costs": resource_costs.duplicate(true),
                "tags": tags.duplicate(),
                "metadata": metadata.duplicate(true),
        }

func validate() -> Dictionary:
        var errors: Array[String] = []
        errors.append_array(CONTRACT.unknown_fields(to_native(), FIELDS, "WeaponDefinition"))
        if schema_version != SCHEMA_VERSION: errors.append("WeaponDefinition schema_version 无效。")
        if not CONTRACT.stable_id(weapon_id) or not weapon_id.begins_with("gm.weapon."): errors.append("WeaponDefinition weapon_id 必须使用 gm.weapon.* 稳定身份。")
        if not CONTRACT.text(display_name_zh): errors.append("WeaponDefinition 必须有中文名称。")
        if not (CONTRACT.stable_id(item_ref) and (item_ref.begins_with("gm.item.") or item_ref.begins_with("gm.equipment."))): errors.append("WeaponDefinition item_ref 必须是 P19 Item/Equipment 稳定引用。")
        if not CONTRACT.stable_id(attack_ref): errors.append("WeaponDefinition attack_ref 必须是稳定攻击引用。")
        if not CONTRACT.stable_id(projectile_ref, true): errors.append("WeaponDefinition projectile_ref 必须是稳定 ID 或空值。")
        if not CONTRACT.stable_id(ammo_item_ref, true): errors.append("WeaponDefinition ammo_item_ref 必须是稳定 ID 或空值。")
        for row in resource_costs:
                if not row is Dictionary or row.size() < 2 or not row.has("resource_id") or not row.has("amount"):
                        errors.append("WeaponDefinition resource_costs 只能声明 resource_id/amount。")
                        continue
                for key in row.keys():
                        if str(key) not in ["resource_id", "amount", "account_id"]: errors.append("WeaponDefinition resource_costs 包含未知字段：%s。" % str(key))
                if not CONTRACT.stable_id(row.get("resource_id")) or not CONTRACT.finite_positive(row.get("amount")):
                        errors.append("WeaponDefinition resource_costs 的资源 ID 或数量无效。")
                if row.has("account_id") and not CONTRACT.stable_id(row.get("account_id")): errors.append("WeaponDefinition resource_costs account_id 无效。")
        if not CONTRACT.string_array(tags): errors.append("WeaponDefinition tags 必须是稳定 ID 数组。")
        var pure_check := CONTRACT.pure(to_native())
        if not pure_check.ok: errors.append_array(pure_check.errors)
        return {"ok": errors.is_empty(), "code": "combat.weapon.valid" if errors.is_empty() else "combat.weapon.invalid", "errors": errors}

static func from_native(value: Variant) -> Dictionary:
        if not value is Dictionary: return {"ok": false, "code": "combat.weapon.type_invalid", "reason_zh": "WeaponDefinition 必须是字典纯值。"}
        var unknown := CONTRACT.unknown_fields(value, FIELDS, "WeaponDefinition")
        if not unknown.is_empty(): return {"ok": false, "code": "combat.weapon.unknown_field", "reason_zh": unknown[0], "errors": unknown}
        if not CONTRACT.exact(value, FIELDS): return {"ok": false, "code": "combat.weapon.fields_incomplete", "reason_zh": "WeaponDefinition 字段集合必须完整。"}
        if not CONTRACT.exact_field_types(value, ["schema_version", "weapon_id", "display_name_zh", "item_ref", "attack_ref", "projectile_ref", "ammo_item_ref"], [], [], ["resource_costs", "tags"], ["metadata"]):
                return {"ok": false, "code": "combat.weapon.field_type_invalid", "reason_zh": "WeaponDefinition 字段类型无效。"}
        var result = load("res://gm_runtime/combat/gm_combat_weapon_definition.gd").new()
        result.schema_version = str(value.get("schema_version", ""))
        result.weapon_id = str(value.get("weapon_id", ""))
        result.display_name_zh = str(value.get("display_name_zh", ""))
        result.item_ref = str(value.get("item_ref", ""))
        result.attack_ref = str(value.get("attack_ref", ""))
        result.projectile_ref = str(value.get("projectile_ref", ""))
        result.ammo_item_ref = str(value.get("ammo_item_ref", ""))
        result.resource_costs = []
        if value.get("resource_costs", []) is Array:
                for row in value.resource_costs:
                        if row is Dictionary: result.resource_costs.append(row.duplicate(true))
        result.tags.clear()
        if value.get("tags", []) is Array:
                for tag in value.tags: result.tags.append(str(tag))
        result.metadata = value.get("metadata", {}).duplicate(true) if value.get("metadata", {}) is Dictionary else {}
        var checked: Dictionary = result.validate()
        if not checked.ok: return {"ok": false, "code": checked.code, "reason_zh": checked.errors[0] if not checked.errors.is_empty() else "WeaponDefinition 无效。", "errors": checked.errors}
        return {"ok": true, "value": result}
