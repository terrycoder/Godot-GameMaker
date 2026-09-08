class_name GMCombatProjectileDefinition
extends RefCounted

const SCHEMA_VERSION := "gm.combat.projectile.v1"
const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")
const FIELDS := ["schema_version", "projectile_id", "display_name_zh", "speed", "lifetime_seconds", "hit_radius", "max_hits", "tags", "metadata"]

var schema_version := SCHEMA_VERSION
var projectile_id := ""
var display_name_zh := ""
var speed := 0.0
var lifetime_seconds := 0.0
var hit_radius := 0.0
var max_hits := 1
var tags: Array[String] = []
var metadata: Dictionary = {}

func configure(p_projectile_id: String, p_display_name_zh: String, p_speed: float, p_lifetime_seconds: float, p_hit_radius: float, p_max_hits: int = 1, p_tags: Array = [], p_metadata: Dictionary = {}):
        projectile_id = p_projectile_id
        display_name_zh = p_display_name_zh
        speed = p_speed
        lifetime_seconds = p_lifetime_seconds
        hit_radius = p_hit_radius
        max_hits = p_max_hits
        tags.clear()
        for value in p_tags: tags.append(str(value))
        metadata = p_metadata.duplicate(true)
        return self

func to_native() -> Dictionary:
        return {"schema_version": schema_version, "projectile_id": projectile_id, "display_name_zh": display_name_zh, "speed": speed, "lifetime_seconds": lifetime_seconds, "hit_radius": hit_radius, "max_hits": max_hits, "tags": tags.duplicate(), "metadata": metadata.duplicate(true)}

func validate() -> Dictionary:
        var errors: Array[String] = []
        errors.append_array(CONTRACT.unknown_fields(to_native(), FIELDS, "ProjectileDefinition"))
        if schema_version != SCHEMA_VERSION: errors.append("ProjectileDefinition schema_version 无效。")
        if not CONTRACT.stable_id(projectile_id) or not projectile_id.begins_with("gm.projectile."): errors.append("ProjectileDefinition projectile_id 必须使用 gm.projectile.* 稳定身份。")
        if not CONTRACT.text(display_name_zh): errors.append("ProjectileDefinition 必须有中文名称。")
        if not CONTRACT.finite_positive(speed): errors.append("ProjectileDefinition speed 必须为有限正数。")
        if not CONTRACT.finite_positive(lifetime_seconds): errors.append("ProjectileDefinition lifetime_seconds 必须为有限正数。")
        if not CONTRACT.finite_nonnegative(hit_radius): errors.append("ProjectileDefinition hit_radius 必须为有限非负数。")
        if typeof(max_hits) != TYPE_INT or max_hits <= 0: errors.append("ProjectileDefinition max_hits 必须为正整数。")
        if not CONTRACT.string_array(tags): errors.append("ProjectileDefinition tags 必须是稳定 ID 数组。")
        var pure_check := CONTRACT.pure(to_native())
        if not pure_check.ok: errors.append_array(pure_check.errors)
        return {"ok": errors.is_empty(), "code": "combat.projectile.valid" if errors.is_empty() else "combat.projectile.invalid", "errors": errors}

static func from_native(value: Variant) -> Dictionary:
        if not value is Dictionary: return {"ok": false, "code": "combat.projectile.type_invalid", "reason_zh": "ProjectileDefinition 必须是字典纯值。"}
        var unknown := CONTRACT.unknown_fields(value, FIELDS, "ProjectileDefinition")
        if not unknown.is_empty(): return {"ok": false, "code": "combat.projectile.unknown_field", "reason_zh": unknown[0], "errors": unknown}
        if not CONTRACT.exact(value, FIELDS): return {"ok": false, "code": "combat.projectile.fields_incomplete", "reason_zh": "ProjectileDefinition 字段集合必须完整。"}
        if not CONTRACT.exact_field_types(value, ["schema_version", "projectile_id", "display_name_zh"], ["speed", "lifetime_seconds", "hit_radius", "max_hits"], [], ["tags"], ["metadata"]):
                return {"ok": false, "code": "combat.projectile.field_type_invalid", "reason_zh": "ProjectileDefinition 字段类型无效。"}
        var result = load("res://gm_runtime/combat/gm_combat_projectile_definition.gd").new()
        result.schema_version = str(value.get("schema_version", ""))
        result.projectile_id = str(value.get("projectile_id", ""))
        result.display_name_zh = str(value.get("display_name_zh", ""))
        result.speed = float(value.get("speed", 0.0))
        result.lifetime_seconds = float(value.get("lifetime_seconds", 0.0))
        result.hit_radius = float(value.get("hit_radius", 0.0))
        result.max_hits = int(value.get("max_hits", 0))
        result.tags.clear()
        if value.get("tags", []) is Array:
                for tag in value.tags: result.tags.append(str(tag))
        result.metadata = value.get("metadata", {}).duplicate(true) if value.get("metadata", {}) is Dictionary else {}
        var checked: Dictionary = result.validate()
        if not checked.ok: return {"ok": false, "code": checked.code, "reason_zh": checked.errors[0] if not checked.errors.is_empty() else "ProjectileDefinition 无效。", "errors": checked.errors}
        return {"ok": true, "value": result}
