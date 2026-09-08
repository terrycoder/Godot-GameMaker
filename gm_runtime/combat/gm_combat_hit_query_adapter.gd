class_name GMCombatHitQueryAdapter
extends RefCounted

const HIT_SPEC := preload("res://gm_runtime/combat/gm_combat_hit_spec.gd")

## Adapter seam only. It returns a pure query outcome and never receives a
## Scene objects, engine handles or world coordinates.
func query(_spec, _context: Dictionary = {}) -> Dictionary:
        return {"ok": false, "code": "combat.hit_query.not_implemented", "reason_zh": "HitQuery 适配器尚未安装。"}
