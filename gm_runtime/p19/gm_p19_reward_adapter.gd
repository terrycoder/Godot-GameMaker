class_name GMP19RewardAdapter
extends RefCounted

## Rewards may combine item production and numeric output in one P19 plan. The
## receipt identity is carried through the same transaction idempotency key.

func build_request(host: GMAbilitySystemHost, reward_id: String, reward_receipt_id: String, source_id: String, target_id: String, idempotency_key: String, item_definition_id: String = "", item_target_container_id: String = "", item_quantity: int = 0, resource_outputs: Array = [], reward_metadata: Dictionary = {}) -> GMAbilityActivationRequest:
		var data: Dictionary = {
				"reward_id": reward_id,
				"reward_receipt_id": reward_receipt_id,
				"target_id": target_id,
				"reward_metadata": reward_metadata.duplicate(true),
				"resource_outputs": resource_outputs.duplicate(true),
			}
		if not item_definition_id.is_empty():
				data["inventory_operation"] = "produce"
				data["definition_id"] = item_definition_id
				data["target_container_id"] = item_target_container_id
				data["quantity"] = item_quantity
		if not resource_outputs.is_empty(): data["numeric_operation"] = "reward"
		return GMP19RequestAdapter.build(host, "reward", data, source_id, idempotency_key)

func execute(host: GMAbilitySystemHost, request: GMAbilityActivationRequest) -> RefCounted:
		return GMP19RequestAdapter.execute(host, request)
