class_name GMProcessAbilityAdapter
extends RefCounted

## Ability-facing request builders. They do not mutate Process state.

static func start(host: GMAbilitySystemHost, definition_id: String, source_id: String, idempotency_key: String) -> GMAbilityActivationRequest:
	return GMAbilityActivationRequest.new(host, "gm.ability.process.start", "", null, {"process_action": "start", "process_definition_id": definition_id}, source_id, {}, idempotency_key)

static func action(host: GMAbilitySystemHost, action_id: String, instance_id: String, source_id: String, idempotency_key: String, participant_id: String = "") -> GMAbilityActivationRequest:
	var data := {"process_action": action_id, "process_instance_id": instance_id}
	if not participant_id.is_empty(): data["participant_id"] = participant_id
	return GMAbilityActivationRequest.new(host, "gm.ability.process.%s" % action_id, "", null, data, source_id, {}, idempotency_key)

static func instant_ability(host: GMAbilitySystemHost, ability_id: String, source_id: String, event_data: Dictionary, idempotency_key: String) -> GMAbilityActivationRequest:
	# Instant abilities intentionally have no process_action and never enter GMProcessService.
	return GMAbilityActivationRequest.new(host, ability_id, "", null, event_data, source_id, {}, idempotency_key)
