class_name GMP19DropAdapter
extends RefCounted

## A drop records only stable semantic facts. A semantic generation target is
## data, not a Node, transform, world coordinate, or backend object reference.

func build_request(host: GMAbilitySystemHost, item_kind: String, item_id: String, source_container_id: String, world_container_id: String, quantity: int, source_id: String, idempotency_key: String, semantic_generation_target: Dictionary = {}) -> GMAbilityActivationRequest:
		return GMP19RequestAdapter.build(host, "drop", {
				"inventory_operation": "drop",
				"item_kind": item_kind,
				"item_id": item_id,
				"source_container_id": source_container_id,
				"target_container_id": world_container_id,
				"target_holder_id": "gm.actor.world",
				"target_id": world_container_id,
				"quantity": quantity,
				"semantic_generation_target": semantic_generation_target.duplicate(true),
				"drop_generation_target": semantic_generation_target.duplicate(true),
		}, source_id, idempotency_key)

func execute(host: GMAbilitySystemHost, request: GMAbilityActivationRequest) -> RefCounted:
		return GMP19RequestAdapter.execute(host, request)
