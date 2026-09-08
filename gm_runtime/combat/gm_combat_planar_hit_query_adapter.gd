class_name GMCombatPlanarHitQueryAdapter
extends "res://gm_runtime/combat/gm_combat_hit_query_adapter.gd"

const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")

var backend_id := "planar_2d"

func query(spec, context: Dictionary = {}) -> Dictionary:
        if spec == null:
                return {"ok": false, "code": "combat.hit_query.spec_missing", "reason_zh": "HitQuery 缺少 HitSpec。"}
        var context_check := CONTRACT.pure(context)
        if not context_check.ok:
                return {"ok": false, "code": "combat.hit_query_context_invalid", "reason_zh": "命中查询上下文只能是纯数据。"}
        if context.has("blocked_target_ids") and not CONTRACT.string_array(context.get("blocked_target_ids")):
                return {"ok": false, "code": "combat.hit_query_context_invalid", "reason_zh": "blocked_target_ids 必须是稳定 ID 数组。"}
        if context.has("force_hit") and typeof(context.get("force_hit")) != TYPE_BOOL:
                return {"ok": false, "code": "combat.hit_query_context_invalid", "reason_zh": "force_hit 必须是布尔值。"}
        var checked: Dictionary = spec.validate()
        if not checked.ok:
                return {"ok": false, "code": "combat.hit_query.spec_invalid", "reason_zh": checked.errors[0] if not checked.errors.is_empty() else "HitSpec 无效。", "errors": checked.errors}
        var blocked_targets: Array = context.get("blocked_target_ids", []) if context.get("blocked_target_ids", []) is Array else []
        if blocked_targets.has(spec.target_id):
                return {"ok": true, "hit": false, "code": "combat.miss.blocked_target", "reason_zh": "目标被查询规则阻断。", "backend_id": backend_id, "target_id": spec.target_id}
        var forced_hit := bool(context.get("force_hit", true))
        return {"ok": true, "hit": forced_hit, "code": "combat.hit" if forced_hit else "combat.miss", "reason_zh": "命中。" if forced_hit else "未命中。", "backend_id": backend_id, "target_id": spec.target_id, "distance": spec.distance}
