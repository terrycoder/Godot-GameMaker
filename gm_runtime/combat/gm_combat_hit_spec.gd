class_name GMCombatHitSpec
extends RefCounted

const SCHEMA_VERSION := "gm.combat.hit_spec.v1"
const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")
const FIELDS := ["schema_version", "hit_id", "query_kind", "source_id", "target_id", "direction", "distance", "max_distance", "shape_radius", "metadata"]
const QUERY_KINDS := ["direct", "projectile"]

var schema_version := SCHEMA_VERSION
var hit_id := ""
var query_kind := "direct"
var source_id := ""
var target_id := ""
var direction: Dictionary = {"x": 1.0, "y": 0.0}
var distance := 0.0
var max_distance := 0.0
var shape_radius := 0.0
var metadata: Dictionary = {}

func configure(p_hit_id: String, p_query_kind: String, p_source_id: String, p_target_id: String, p_direction: Variant = {"x": 1.0, "y": 0.0}, p_distance: float = 0.0, p_max_distance: float = 0.0, p_shape_radius: float = 0.0, p_metadata: Dictionary = {}):
        hit_id = p_hit_id
        query_kind = p_query_kind
        source_id = p_source_id
        target_id = p_target_id
        direction = CONTRACT.vector2_native(p_direction)
        distance = p_distance
        max_distance = p_max_distance
        shape_radius = p_shape_radius
        metadata = p_metadata.duplicate(true)
        return self

func to_native() -> Dictionary:
        return {"schema_version": schema_version, "hit_id": hit_id, "query_kind": query_kind, "source_id": source_id, "target_id": target_id, "direction": direction.duplicate(true), "distance": distance, "max_distance": max_distance, "shape_radius": shape_radius, "metadata": metadata.duplicate(true)}

func validate() -> Dictionary:
        var errors: Array[String] = []
        errors.append_array(CONTRACT.unknown_fields(to_native(), FIELDS, "HitSpec"))
        if schema_version != SCHEMA_VERSION: errors.append("HitSpec schema_version 无效。")
        if not CONTRACT.stable_id(hit_id) or not hit_id.begins_with("gm.hit."): errors.append("HitSpec hit_id 必须使用 gm.hit.* 稳定身份。")
        if not QUERY_KINDS.has(query_kind): errors.append("HitSpec query_kind 不是后端无关类型。")
        if not CONTRACT.stable_id(source_id) or not CONTRACT.stable_id(target_id): errors.append("HitSpec source_id/target_id 必须是稳定 ID。")
        if not CONTRACT.finite_vector2(direction, false): errors.append("HitSpec direction 必须是非零 Planar 纯向量。")
        if not CONTRACT.finite_nonnegative(distance): errors.append("HitSpec distance 必须为有限非负数。")
        if not CONTRACT.finite_nonnegative(max_distance): errors.append("HitSpec max_distance 必须为有限非负数。")
        if max_distance > 0.0 and distance > max_distance: errors.append("HitSpec distance 不能超过 max_distance。")
        if not CONTRACT.finite_nonnegative(shape_radius): errors.append("HitSpec shape_radius 必须为有限非负数。")
        var pure_check := CONTRACT.pure(to_native())
        if not pure_check.ok: errors.append_array(pure_check.errors)
        return {"ok": errors.is_empty(), "code": "combat.hit_spec.valid" if errors.is_empty() else "combat.hit_spec.invalid", "errors": errors}

static func from_native(value: Variant) -> Dictionary:
        if not value is Dictionary: return {"ok": false, "code": "combat.hit_spec.type_invalid", "reason_zh": "HitSpec 必须是字典纯值。"}
        var unknown := CONTRACT.unknown_fields(value, FIELDS, "HitSpec")
        if not unknown.is_empty(): return {"ok": false, "code": "combat.hit_spec.unknown_field", "reason_zh": unknown[0], "errors": unknown}
        if not CONTRACT.exact(value, FIELDS): return {"ok": false, "code": "combat.hit_spec.fields_incomplete", "reason_zh": "HitSpec 字段集合必须完整。"}
        if not CONTRACT.exact_field_types(value, ["schema_version", "hit_id", "query_kind", "source_id", "target_id"], ["distance", "max_distance", "shape_radius"], [], [], ["direction", "metadata"]):
                return {"ok": false, "code": "combat.hit_spec.field_type_invalid", "reason_zh": "HitSpec 字段类型无效。"}
        var result = load("res://gm_runtime/combat/gm_combat_hit_spec.gd").new()
        result.schema_version = str(value.get("schema_version", ""))
        result.hit_id = str(value.get("hit_id", ""))
        result.query_kind = str(value.get("query_kind", ""))
        result.source_id = str(value.get("source_id", ""))
        result.target_id = str(value.get("target_id", ""))
        result.direction = value.get("direction", {}).duplicate(true) if value.get("direction", {}) is Dictionary else {}
        result.distance = float(value.get("distance", 0.0))
        result.max_distance = float(value.get("max_distance", 0.0))
        result.shape_radius = float(value.get("shape_radius", 0.0))
        result.metadata = value.get("metadata", {}).duplicate(true) if value.get("metadata", {}) is Dictionary else {}
        var checked: Dictionary = result.validate()
        if not checked.ok: return {"ok": false, "code": checked.code, "reason_zh": checked.errors[0] if not checked.errors.is_empty() else "HitSpec 无效。", "errors": checked.errors}
        return {"ok": true, "value": result}
