class_name GMP19UseAdapter
extends RefCounted

## Use/consume carries effect confirmation as transaction payload. The
## confirmation is observed by the domain executor in the same commit; this
## adapter does not mutate inventory or effects directly.

func build_request(host: GMAbilitySystemHost, item_kind: String, item_id: String, source_container_id: String, quantity: int, source_id: String, idempotency_key: String, effect_request: Dictionary = {}, use_confirmation: Dictionary = {}) -> GMAbilityActivationRequest:
		return GMP19RequestAdapter.build(host, "use", {
				"inventory_operation": "consume",
				"numeric_operation": str(effect_request.get("numeric_operation", "")) if not effect_request.is_empty() else "",
				"item_kind": item_kind,
				"item_id": item_id,
				"source_container_id": source_container_id,
				"quantity": quantity,
				"target_id": source_id,
				"effect_request": effect_request.duplicate(true),
				"use_confirmation": use_confirmation.duplicate(true),
		}, source_id, idempotency_key)

func execute(host: GMAbilitySystemHost, request: GMAbilityActivationRequest) -> RefCounted:
		return GMP19RequestAdapter.execute(host, request)
