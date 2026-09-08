@tool
class_name GMCombatCatalog
extends Resource

## One authoring Resource for P22. It contains definition data only; runtime
## actor state, inventory state and fact/change stores remain elsewhere.

const SCHEMA_VERSION := "gm.combat.catalog.v1"
const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")
const ATTACK := preload("res://gm_runtime/combat/gm_combat_attack_definition.gd")
const WEAPON := preload("res://gm_runtime/combat/gm_combat_weapon_definition.gd")
const PROJECTILE := preload("res://gm_runtime/combat/gm_combat_projectile_definition.gd")
const FIELDS := ["schema_version", "catalog_id", "display_name_zh", "revision", "attacks", "weapons", "projectiles"]

var schema_version := SCHEMA_VERSION
@export var catalog_id := "gm.combat.catalog.default"
@export var display_name_zh := "P22 战斗定义目录"
@export var revision := 0
@export var attacks: Array[Dictionary] = []
@export var weapons: Array[Dictionary] = []
@export var projectiles: Array[Dictionary] = []

func configure(p_catalog_id: String, p_display_name_zh: String = "P22 战斗定义目录", p_attacks: Array = [], p_weapons: Array = [], p_projectiles: Array = []):
        catalog_id = p_catalog_id
        display_name_zh = p_display_name_zh
        attacks.clear()
        weapons.clear()
        projectiles.clear()
        for value in p_attacks:
                if value is Dictionary: attacks.append(value.duplicate(true))
        for value in p_weapons:
                if value is Dictionary: weapons.append(value.duplicate(true))
        for value in p_projectiles:
                if value is Dictionary: projectiles.append(value.duplicate(true))
        revision = 0
        return self

func to_native() -> Dictionary:
        return {"schema_version": schema_version, "catalog_id": catalog_id, "display_name_zh": display_name_zh, "revision": revision, "attacks": attacks.duplicate(true), "weapons": weapons.duplicate(true), "projectiles": projectiles.duplicate(true)}

func validate() -> Dictionary:
        var errors: Array[String] = []
        errors.append_array(CONTRACT.unknown_fields(to_native(), FIELDS, "CombatCatalog"))
        if schema_version != SCHEMA_VERSION: errors.append("P22 目录 schema_version 无效。")
        if not CONTRACT.stable_id(catalog_id) or not catalog_id.begins_with("gm.combat.catalog."): errors.append("P22 目录 ID 必须使用 gm.combat.catalog.* 稳定身份。")
        if not CONTRACT.text(display_name_zh): errors.append("P22 目录必须有中文名称。")
        if revision < 0: errors.append("P22 目录 revision 不能为负数。")
        if typeof(revision) != TYPE_INT: errors.append("P22 目录 revision 必须是整数。")
        _validate_rows(attacks, "attacks", errors, ATTACK)
        _validate_rows(weapons, "weapons", errors, WEAPON)
        _validate_rows(projectiles, "projectiles", errors, PROJECTILE)
        var pure_check := CONTRACT.pure(to_native())
        if not pure_check.ok: errors.append_array(pure_check.errors)
        return {"ok": errors.is_empty(), "code": "combat.catalog.valid" if errors.is_empty() else "combat.catalog.invalid", "errors": errors}

func add_or_replace_attack(value: Dictionary) -> Dictionary:
        return _add_or_replace(attacks, value, "attack_id", ATTACK)

func add_or_replace_weapon(value: Dictionary) -> Dictionary:
        return _add_or_replace(weapons, value, "weapon_id", WEAPON)

func add_or_replace_projectile(value: Dictionary) -> Dictionary:
        return _add_or_replace(projectiles, value, "projectile_id", PROJECTILE)

static func from_native(value: Variant) -> Dictionary:
        if not value is Dictionary: return {"ok": false, "code": "combat.catalog.type_invalid", "reason_zh": "P22 目录必须是字典纯值。"}
        var unknown := CONTRACT.unknown_fields(value, FIELDS, "CombatCatalog")
        if not unknown.is_empty(): return {"ok": false, "code": "combat.catalog.unknown_field", "reason_zh": unknown[0], "errors": unknown}
        if not CONTRACT.exact(value, FIELDS): return {"ok": false, "code": "combat.catalog.fields_incomplete", "reason_zh": "CombatCatalog 字段集合必须完整。"}
        if not CONTRACT.exact_field_types(value, ["schema_version", "catalog_id", "display_name_zh"], ["revision"], [], ["attacks", "weapons", "projectiles"]):
                return {"ok": false, "code": "combat.catalog.field_type_invalid", "reason_zh": "CombatCatalog 字段类型无效。"}
        var result = load("res://gm_runtime/combat/gm_combat_catalog.gd").new()
        result.schema_version = str(value.get("schema_version", ""))
        result.catalog_id = str(value.get("catalog_id", ""))
        result.display_name_zh = str(value.get("display_name_zh", ""))
        result.revision = int(value.get("revision", 0))
        for key in ["attacks", "weapons", "projectiles"]:
                var rows: Variant = value.get(key, [])
                for row in rows:
                        if key == "attacks": result.attacks.append(row.duplicate(true))
                        elif key == "weapons": result.weapons.append(row.duplicate(true))
                        else: result.projectiles.append(row.duplicate(true))
        var checked: Dictionary = result.validate()
        if not checked.ok: return {"ok": false, "code": checked.code, "reason_zh": checked.errors[0] if not checked.errors.is_empty() else "P22 目录无效。", "errors": checked.errors}
        return {"ok": true, "value": result}

func _add_or_replace(rows: Array[Dictionary], value: Dictionary, id_field: String, script: Script) -> Dictionary:
        var parsed: Variant = script.from_native(value)
        if not parsed.ok: return parsed
        var identifier := str(value.get(id_field, ""))
        for index in rows.size():
                if str(rows[index].get(id_field, "")) == identifier:
                        rows[index] = value.duplicate(true)
                        revision += 1
                        return {"ok": true, "code": "combat.catalog.replaced", "id": identifier, "revision": revision}
        rows.append(value.duplicate(true))
        revision += 1
        return {"ok": true, "code": "combat.catalog.added", "id": identifier, "revision": revision}

static func _validate_rows(rows: Variant, field: String, errors: Array[String], script: Script) -> void:
        if not rows is Array:
                errors.append("P22 目录 %s 必须是数组。" % field)
                return
        var seen := {}
        for row in rows:
                if not row is Dictionary:
                        errors.append("P22 目录 %s 只能包含字典纯值。" % field)
                        continue
                var checked: Dictionary = script.from_native(row)
                if not bool(checked.get("ok", false)): errors.append_array(checked.get("errors", [str(checked.get("reason_zh", "定义无效。"))]))
                var id_field := "attack_id" if field == "attacks" else ("weapon_id" if field == "weapons" else "projectile_id")
                var identifier := str(row.get(id_field, ""))
                if seen.has(identifier): errors.append("P22 目录 %s ID 重复：%s。" % [field, identifier])
                seen[identifier] = true
