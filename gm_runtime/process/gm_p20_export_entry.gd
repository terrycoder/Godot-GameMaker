extends Node

## Minimal P20 export smoke: one neutral recipe, one Process Store, one typed
## completion result. No scene, movement or domain-specific backend is needed.

const NEUTRAL_RECIPE := preload("res://gm_runtime/process/gm_process_neutral_recipe.tres")

func _ready() -> void:
	var store := GMProcessStore.new()
	var clock := GMProcessClock.new("test", 0)
	var service := GMProcessService.new(store, clock)
	var definition: GMProcessDefinition = NEUTRAL_RECIPE
	var registered := service.register_definition(definition)
	var host := GMAbilitySystemHost.new()
	var request := GMProcessAbilityAdapter.start(host, definition.definition_id, "gm.ability.export", "p20.export.neutral.1")
	var started := service.request(request)
	var instance_id := str(started.get("instance", {}).get("instance_id", ""))
	var first := service.advance(instance_id, 1) if not instance_id.is_empty() else {"ok": false}
	var finished := service.advance(instance_id, 1) if bool(first.get("ok", false)) else {"ok": false}
	var restored_store := GMProcessStore.new()
	var restored := restored_store.restore_snapshot(JSON.parse_string(JSON.stringify(store.snapshot())))
	var restored_instance := restored_store.get_instance(instance_id)
	var result := {
		"event": "P20_EXPORT_SENTINEL",
		"ok": registered.ok and started.ok and first.ok and finished.ok and restored.ok and restored_instance != null and restored_instance.state == GMProcessState.COMPLETED,
		"definition_id": definition.definition_id,
		"instance_id": instance_id,
		"state": restored_instance.state if restored_instance != null else "",
		"progress": restored_instance.progress.to_native() if restored_instance != null else {},
		"typed_result": restored_instance.result if restored_instance != null else {},
		"single_process_store": true,
	}
	print(JSON.stringify(result))
	get_tree().quit(0 if result.ok else 164)
