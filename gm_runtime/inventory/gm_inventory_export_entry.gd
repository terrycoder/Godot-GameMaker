extends Node

const INVENTORY_STORE = preload("res://gm_runtime/inventory/gm_inventory_store.gd")

func _ready() -> void:
	var store = INVENTORY_STORE.new()
	if store.store_id != "gm.store.inventory":
		push_error("GM_TASK05C_EXPORT_RUNTIME_FAIL")
		get_tree().quit(1)
		return
	print("GM_TASK05C_EXPORT_RUNTIME_OK ", store.schema_version)
	get_tree().quit(0)
