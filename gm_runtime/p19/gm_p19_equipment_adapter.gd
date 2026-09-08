class_name GMP19EquipmentAdapter
extends RefCounted

## Equipment is an inventory transfer with semantic slot metadata. The
## existing InventoryResolver remains the only owner of item/ownership state.

func build_equip_request(host: GMAbilitySystemHost, item_id: String, source_container_id: String, equipment_container_id: String, equipment_slot: String, source_id: String, idempotency_key: String, ability_source_request: Dictionary = {}) -> GMAbilityActivationRequest:
		return GMP19RequestAdapter.build(host, "equip", {
				"inventory_operation": "transfer",
				"item_kind": str(ability_source_request.get("item_kind", "lot")),
				"item_id": item_id,
				"source_container_id": source_container_id,
				"target_container_id": equipment_container_id,
				"target_holder_id": source_id,
				"target_id": source_id,
				"equipment_slot": equipment_slot,
				"ability_source_request": ability_source_request.duplicate(true),
		}, source_id, idempotency_key)

func build_unequip_request(host: GMAbilitySystemHost, item_id: String, equipment_container_id: String, target_container_id: String, equipment_slot: String, source_id: String, idempotency_key: String, ability_source_request: Dictionary = {}) -> GMAbilityActivationRequest:
		return GMP19RequestAdapter.build(host, "unequip", {
				"inventory_operation": "transfer",
				"item_kind": str(ability_source_request.get("item_kind", "lot")),
				"item_id": item_id,
				"source_container_id": equipment_container_id,
				"target_container_id": target_container_id,
				"target_holder_id": source_id,
				"target_id": source_id,
				"equipment_slot": equipment_slot,
				"ability_source_request": ability_source_request.duplicate(true),
		}, source_id, idempotency_key)

func execute(host: GMAbilitySystemHost, request: GMAbilityActivationRequest) -> RefCounted:
		return GMP19RequestAdapter.execute(host, request)
