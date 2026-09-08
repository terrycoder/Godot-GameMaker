extends Node

## Minimal exported smoke entry. It exercises the P19 numeric Store contract
## without adding a second runtime, fact ledger, or spatial backend.

func _ready() -> void:
        var store := GMNumericResourceStore.new()
        var definition := GMNumericResourceDefinition.new().configure("gm.resource.export.gold", "gm.unit.whole", {"display_name_zh": "导出金币", "minimum_value": 0, "maximum_capacity": 1000})
        var account_id := GMNumericResourceAccount.make_id(definition.resource_id, "gm.actor.export", "gm.actor.export")
        var account := GMNumericResourceAccount.new().configure(account_id, definition.resource_id, "gm.actor.export", "gm.actor.export", 42, 1000)
        var definition_result := store.register_definition(definition)
        var account_result := store.register_account(account)
        var snapshot := store.snapshot()
        var restored := GMNumericResourceStore.new()
        var restore_result := restored.restore_snapshot(JSON.parse_string(JSON.stringify(snapshot)))
        var restored_account := restored.get_account(account_id)
        var result := {
                "event": "P19_EXPORT_SENTINEL",
                "ok": definition_result.ok and account_result.ok and restore_result.ok and restored_account != null and restored_account.balance == 42,
                "schema": GMNumericResourceStore.STORE_SCHEMA_VERSION,
                "resource_id": definition.resource_id,
                "account_id": account_id,
                "balance": restored_account.balance if restored_account != null else -1,
                "json_roundtrip": restore_result.ok,
                "spatial_backend": false,
        }
        print(JSON.stringify(result))
        get_tree().quit(0 if result.ok else 164)
