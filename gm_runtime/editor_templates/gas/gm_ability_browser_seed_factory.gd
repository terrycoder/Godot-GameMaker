class_name GMTask04SampleFactory
extends RefCounted

static func make_animal_host(entity: Object = null, context: Object = null) -> Dictionary:
	var actual_entity: Object = entity if entity != null else CharacterBody2D.new()
	var actual_context: Object = context if context != null else Node.new()
	var setup := _setup_host(actual_entity, actual_context, "species.animal")
	if not setup.ok: return setup
	var host: GMAbilitySystemHost = setup.host
	var definitions := _animal_definitions()
	var bundle := GMAbilityBundle.new()
	bundle.bundle_id = "animal.capabilities"
	bundle.display_name_zh = "动物能力组合"
	bundle.description_zh = "移动、进食、死亡掉落三种非战斗能力。"
	for definition in definitions.values(): host.register_definition(definition)
	for id in ["gm.ability.move", "gm.ability.eat", "gm.ability.drop_loot"]:
		bundle.add_ability(id, 1)
	var grant := host.grant_bundle(bundle, "animal.innate")
	setup["definitions"] = definitions
	setup["bundle"] = bundle
	setup["grant"] = grant
	setup["sample_kind"] = "animal"
	return setup

static func make_building_host(entity: Object = null, context: Object = null) -> Dictionary:
	var actual_entity: Object = entity if entity != null else Node2D.new()
	var actual_context: Object = context if context != null else Node.new()
	var setup := _setup_host(actual_entity, actual_context, "structure.building")
	if not setup.ok: return setup
	var host: GMAbilitySystemHost = setup.host
	var definitions := {"gm.ability.produce": _make_definition("gm.ability.produce", "生产（占位）", ["gm.ability.produce"], "GMProductionService", ["action.producing"])}
	var bundle := GMAbilityBundle.new()
	bundle.bundle_id = "building.production"
	bundle.display_name_zh = "建筑生产占位能力包"
	bundle.add_ability("gm.ability.produce", 1, {"recipe_id": "demo.recipe"})
	for definition in definitions.values(): host.register_definition(definition)
	var grant := host.grant_bundle(bundle, "building.recipe")
	setup["definitions"] = definitions
	setup["bundle"] = bundle
	setup["grant"] = grant
	setup["sample_kind"] = "building"
	return setup

static func make_resource_proxy_host(context: Object = null) -> Dictionary:
	var proxy := GMTask04ResourceProxy.new()
	var actual_context: Object = context if context != null else Node.new()
	var setup := _setup_host(proxy, actual_context, "structure.proxy")
	if not setup.ok: return setup
	var definitions := {"gm.ability.produce": _make_definition("gm.ability.produce", "代理生产（占位）", ["gm.ability.produce"], "GMProductionService", [])}
	var bundle := GMAbilityBundle.new()
	bundle.bundle_id = "resource.proxy.production"
	bundle.add_ability("gm.ability.produce", 1)
	var host: GMAbilitySystemHost = setup.host
	for definition in definitions.values(): host.register_definition(definition)
	setup["definitions"] = definitions
	setup["bundle"] = bundle
	setup["grant"] = host.grant_bundle(bundle, "proxy.innate")
	setup["sample_kind"] = "resource_proxy"
	return setup

static func activate_from_source(host: GMAbilitySystemHost, ability_id: String, source: String, target: Object = null, event_data: Dictionary = {}, schedule_context: Dictionary = {}) -> Dictionary:
	var target_data := GMTargetData.new(target) if target != null else null
	var request := GMAbilityActivationRequest.new(host, ability_id, "", target_data, event_data, source, schedule_context)
	return host.request_activation(request)

static func input_move(host: GMAbilitySystemHost) -> Dictionary:
	return activate_from_source(host, "gm.ability.move", "input", null, {}, {"mode": "realtime", "frame": 1})

static func ai_move(host: GMAbilitySystemHost) -> Dictionary:
	return activate_from_source(host, "gm.ability.move", "ai", null, {}, {"mode": "realtime", "decision": "wander"})

static func schedule_move(host: GMAbilitySystemHost) -> Dictionary:
	return activate_from_source(host, "gm.ability.move", "schedule", null, {}, {"mode": "turn", "slot": "morning"})

static func debug_move(host: GMAbilitySystemHost) -> Dictionary:
	return activate_from_source(host, "gm.ability.move", "debugger", null, {}, {"mode": "debug", "reason": "evidence"})

static func run_four_move_sources(host: GMAbilitySystemHost) -> Dictionary:
	var results := [
		input_move(host),
		ai_move(host),
		schedule_move(host),
		debug_move(host),
	]
	var paths: Array[String] = []
	for result in results: paths.append(str(result.get("activation_path", result.get("path", ""))))
	var same_path := paths.size() == 4 and paths.all(func(path): return path == paths[0])
	return {"ok": results.all(func(item): return item.ok) and same_path, "sources": ["input", "ai", "schedule", "debugger"], "results": results, "paths": paths, "same_path": same_path}

static func remove_animal_move(host: GMAbilitySystemHost) -> Dictionary:
	return host.revoke_ability("gm.ability.move", "animal.innate")

static func _setup_host(entity: Object, context: Object, entity_tag: String) -> Dictionary:
	var attached := GMAbilitySystemHost.attach_to(entity, context)
	if not attached.ok: return attached
	attached["entity"] = entity
	attached["context"] = context
	var host: GMAbilitySystemHost = attached.host
	var tag_result := host.register_tag(entity_tag)
	if not tag_result.ok and tag_result.code != "tag.duplicate":
		host.unmount()
		return tag_result
	host.add_host_tag(entity_tag, "entity.identity")
	var services := GMTask04DomainServices.new()
	for service_id in ["GMMovementExecutor2D", "GMInventoryService", "GMLootService", "GMProductionService"]:
		host.set_domain_service(service_id, services)
	attached["services"] = services
	return attached

static func _animal_definitions() -> Dictionary:
	return {
		"gm.ability.move": _make_definition("gm.ability.move", "移动", ["gm.ability.move"], "GMMovementExecutor2D", ["action.moving"], ["state.dead", "state.stunned"]),
		"gm.ability.eat": _make_definition("gm.ability.eat", "进食", ["gm.ability.eat"], "GMInventoryService", ["action.eating"], ["state.dead"]),
		"gm.ability.drop_loot": _make_definition("gm.ability.drop_loot", "死亡掉落", ["gm.ability.drop_loot"], "GMLootService", [], []),
	}

static func _make_definition(ability_id: String, name_zh: String, ability_tags: Array, executor: String, grant_tags: Array = [], blocked_tags: Array = []) -> GMAbilityDefinition:
	var definition := GMAbilityDefinition.new()
	definition.ability_id = ability_id
	definition.display_name_zh = name_zh
	definition.description_zh = "任务包04统一能力样板"
	definition.ability_tags = PackedStringArray(ability_tags)
	definition.executor_service_id = executor
	definition.grant_tags = PackedStringArray(grant_tags)
	definition.blocked_tags = PackedStringArray(blocked_tags)
	definition.concurrency_group = "animal.action" if ability_id != "gm.ability.drop_loot" else ""
	definition.concurrency_policy = "同组拒绝"
	return definition
