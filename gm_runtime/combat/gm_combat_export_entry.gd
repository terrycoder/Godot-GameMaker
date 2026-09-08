extends Node

## Minimal P22 export smoke entry. It exercises the public pure-value contract
## and the single resolver without creating actor, HP, inventory or UI state.

const ATTACK := preload("res://gm_runtime/combat/gm_combat_attack_definition.gd")
const HIT_SPEC := preload("res://gm_runtime/combat/gm_combat_hit_spec.gd")
const REQUEST := preload("res://gm_runtime/combat/gm_combat_request.gd")
const RESOLVER := preload("res://gm_runtime/combat/gm_combat_resolver.gd")
const RESULT := preload("res://gm_runtime/combat/gm_combat_result.gd")

func _ready() -> void:
        var resolver = RESOLVER.new()
        var attack = ATTACK.new().configure("gm.attack.export.smoke", "导出检查攻击", "melee", "damage", 3.0, 1.0)
        var hit_spec = HIT_SPEC.new().configure("gm.hit.export.smoke", "direct", "gm.actor.export", "gm.actor.target", {"x": 1.0, "y": 0.0}, 0.5, 2.0)
        var request = REQUEST.new().configure("gm.combat.request.export.smoke", "gm.p22.export.smoke", "realtime", "gm.actor.export", "gm.actor.target", "gm.ability.export.combat", attack.attack_id, hit_spec)
        var registered: Dictionary = resolver.register_attack(attack)
        var resolved = resolver.resolve(request)
        var decoded: Dictionary = REQUEST.from_native(JSON.parse_string(JSON.stringify(request.to_native())))
        var result_native: Dictionary = resolved.to_native() if resolved != null and resolved.has_method("to_native") else {}
        var result_check: Dictionary = RESULT.from_native(result_native) if not result_native.is_empty() else {"ok": false}
        var smoke := {
                "event": "P22_EXPORT_SENTINEL",
                "ok": registered.get("ok", false) and resolved.status == "committed" and decoded.get("ok", false) and result_check.get("ok", false),
                "resolver_id": resolver.resolver_id,
                "result_status": resolved.status,
                "result_code": resolved.code,
                "request_schema": REQUEST.SCHEMA_VERSION,
                "result_schema": RESULT.SCHEMA_VERSION,
                "direct_store_write": false,
                "runtime_state_owner": "existing_domain_transaction_pipeline",
        }
        print(JSON.stringify(smoke))
        get_tree().quit(0 if smoke.ok else 172)
