class_name GMObjectAbilityHostNode
extends Node

var ability_host: GMAbilitySystemHost
var runtime_context: GMRuntimeContext
var interaction_service: GMObjectInteractionService

func _enter_tree() -> void:
	_ensure_initialized_from_parent()

func _ready() -> void:
	_ensure_initialized_from_parent()

func _ensure_initialized_from_parent() -> void:
	if ability_host != null: return
	var target := get_parent() as GMObjectInstance
	if target == null or target.definition == null: return
	var resolved := target.definition.resolve_effective()
	if resolved.ok: initialize(target, resolved.effective.ability_definitions)

func initialize(target: GMObjectInstance, definitions: Array) -> Dictionary:
	if ability_host != null and ability_host.mounted: return {"ok": true, "already_initialized": true, "ability_count": definitions.size(), "mounted": true}
	if target == null: return {"ok": false, "code": "object.host_target_missing", "error_zh": "对象能力宿主缺少目标实例。"}
	runtime_context = GMRuntimeContext.new()
	var mounted := GMAbilitySystemHost.attach_to(target, runtime_context)
	if not mounted.ok: return mounted
	ability_host = mounted.host
	interaction_service = GMObjectInteractionService.new(target)
	var service_result := ability_host.set_domain_service(GMObjectInteractionService.SERVICE_ID, interaction_service)
	if not service_result.ok: return service_result
	for definition in definitions:
		var grant := ability_host.grant_ability(definition, "object_definition:%s" % target.definition.content_id)
		if not grant.ok: return grant
	return {"ok": true, "ability_count": definitions.size(), "mounted": true}

func interact(context: Dictionary = {}) -> Dictionary:
	if ability_host == null or not is_instance_valid(ability_host): return {"ok": false, "code": "object.host_missing", "error_zh": "对象能力宿主未初始化。"}
	var target := get_parent() as GMObjectInstance
	if target == null or target.definition == null: return {"ok": false, "code": "object.definition_missing", "error_zh": "对象实例缺少定义。"}
	var resolved := target.definition.resolve_effective()
	if not resolved.ok: return resolved
	var recipe: GMInteractionRecipe = resolved.effective.interaction_recipe
	var preflight := recipe.preflight(target.object_state, context)
	if not preflight.ok: return preflight
	var event_data := context.duplicate(true)
	event_data["recipe_id"] = recipe.recipe_id
	event_data["stable_instance_id"] = target.stable_instance_id
	event_data["state_patch"] = recipe.success_state_patch.duplicate(true)
	event_data["event_tag"] = recipe.event_tag
	event_data["cue_id"] = recipe.cue_id
	var key := "object:%s:recipe:%s:state:%s" % [target.stable_instance_id, recipe.recipe_id, JSON.stringify(target.object_state, "", true, true).sha256_text()]
	var request := GMAbilityActivationRequest.new(ability_host, recipe.ability_id, "", GMTargetData.from_entity(target, target.stable_instance_id), event_data, "gm.object.interaction", {}, key)
	var result := ability_host.activate(request)
	if not bool(result.get("ok", false)) and not result.has("code"):
		result["code"] = str(result.get("failure_code", "ability.failed"))
	# Report the committed ledger counts by reading the Host-owned stores after
	# the synchronous lifecycle has finished; these are not synthetic counters.
	result["fact_count"] = ability_host.fact_event_store.get_record_count() if ability_host.fact_event_store != null else 0
	result["change_record_count"] = ability_host.change_record_store.get_record_count() if ability_host.change_record_store != null else 0
	result["gas_path"] = GMAbilitySystemHost.ACTIVATION_PATH
	result["recipe_id"] = recipe.recipe_id
	return result

func reset_runtime_host() -> void:
	if ability_host != null: ability_host.dispose()
	ability_host = null
	interaction_service = null
	if runtime_context != null and is_instance_valid(runtime_context): runtime_context.free()
	runtime_context = null

func _exit_tree() -> void:
	if ability_host != null: ability_host.dispose()
	ability_host = null
	if runtime_context != null and is_instance_valid(runtime_context): runtime_context.free()
	runtime_context = null
