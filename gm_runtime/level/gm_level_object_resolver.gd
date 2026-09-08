extends RefCounted

## P24 唯一无状态对象解析器。
##
## Resolver 读取 Definition、Ability、调用方从 ExecutionFacts 重建的对象状态，
## 然后返回新的纯值事实/请求描述。它从不直接写 Task、World、Inventory、
## Store、Transaction 或场景节点；重复 request 由调用方传入的 receipt 做幂等重放。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const DEFINITION := preload("res://gm_runtime/level/gm_level_object_definition.gd")
const ABILITY := preload("res://gm_runtime/level/gm_level_object_ability.gd")
const FACTS := preload("res://gm_runtime/scene/gm_execution_facts.gd")
const CONTEXT := preload("res://gm_runtime/scene/gm_task_execution_context.gd")
const RETURN_CONTEXT := preload("res://gm_runtime/scene/gm_scene_return_context.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const GENERATOR := preload("res://gm_runtime/level/gm_level_object_generator.gd")

const RESOLVER_ID := DEFINITION.RESOLVER_ID

func resolve(
	definition_value: Variant,
	ability_value: Variant,
	state: Dictionary = {},
	context: Dictionary = {},
	receipts: Dictionary = {}
) -> Dictionary:
	var definition_check := _as_definition(definition_value)
	if not definition_check.ok:
		return definition_check
	var ability_check := _as_ability(ability_value)
	if not ability_check.ok:
		return ability_check
	var definition = definition_check.value
	var ability = ability_check.value
	if definition.resolver_id != RESOLVER_ID:
		return _blocked("level_object.resolve.resolver", "P24对象Definition没有使用唯一Resolver。")
	if ability.ability_id != definition.ability_id:
		return _blocked("level_object.resolve.ability_mismatch", "对象Ability与Definition不一致。")
	if typeof(state) != TYPE_DICTIONARY or not VALUE.persistence(state).ok:
		return _blocked("level_object.resolve.state", "对象状态输入必须是可持久化纯字典。")
	if typeof(context) != TYPE_DICTIONARY or not VALUE.persistence(context).ok:
		return _blocked("level_object.resolve.context", "对象解析上下文必须是可持久化纯字典。")
	if _contains_direct_write_marker(context):
		return _blocked("level_object.resolve.direct_write", "对象解析上下文不得声明直接写入领域状态。")
	var replay := _replay_receipt(definition, ability, receipts)
	if bool(replay.get("receipt_found", false)):
		if not bool(replay.get("ok", false)):
			return replay
		return replay.value
	var working_state: Dictionary = definition.state_defaults.duplicate(true)
	for key in state.keys():
		working_state[key] = VALUE.duplicate_value(state[key])
	var operation := _resolve_operation(definition, ability, working_state, context)
	if not operation.ok:
		return operation
	var sequence_check := VALUE.integer_field(context.get("sequence", 1), false)
	if not sequence_check.ok or int(sequence_check.value) < 1:
		return _blocked("level_object.resolve.sequence", "对象解析sequence必须是正整数。")
	var session_id := str(context.get("session_id", "gm.level.object.session"))
	if not VALUE.stable_id(session_id, false):
		return _blocked("level_object.resolve.session", "对象解析session_id必须是稳定标识。")
	var object_id := str(ability.object_ref.get("id", ""))
	var fact_id := "gm.fact.level_object.%s" % VALUE.digest({"object_id": object_id, "request_id": ability.request_id}).substr(0, 32)
	var fact := FACTS.new(
		fact_id,
		session_id,
		int(sequence_check.value),
		"level_object",
		ability.actor_ref,
		ability.object_ref,
		operation.outcome,
		operation.contributions,
		operation.domain_requests,
		["level_object", definition.object_kind, ability.operation],
		{"resolver_id": RESOLVER_ID, "definition_id": definition.definition_id, "object_id": object_id, "request_id": ability.request_id, "state_carrier": "execution_facts_or_domain_request"}
	)
	var fact_check := fact.validate()
	if not fact_check.ok:
		return _blocked("level_object.resolve.fact_invalid", "对象解析结果未通过既有GMExecutionFacts合同。", fact_check)
	var response: Dictionary = {
		"ok": true,
		"idempotent": false,
                "resolver_id": RESOLVER_ID,
                "definition_id": definition.definition_id,
                "ability_id": ability.ability_id,
                "object_id": object_id,
		"request_id": ability.request_id,
		"idempotency_key": ability.idempotency_key,
		"object_kind": definition.object_kind,
		"operation": ability.operation,
		"state_after": VALUE.duplicate_value(operation.state),
		"outcome": VALUE.duplicate_value(operation.outcome),
		"fact": fact.to_dict(),
		"domain_requests": VALUE.duplicate_value(fact.domain_requests),
		"special": VALUE.duplicate_value(operation.special)
	}
	response["receipt"] = {
		"request_id": ability.request_id,
		"idempotency_key": ability.idempotency_key,
		"object_id": object_id,
		"definition_id": definition.definition_id,
		"ability_id": ability.ability_id,
		"operation": ability.operation,
		"ability_fingerprint": ability.fingerprint(),
		"response_fingerprint": VALUE.digest(response)
	}
	var response_persistence := VALUE.persistence(response)
	if not response_persistence.ok:
		return _blocked("level_object.resolve.output", "对象解析输出不是可持久化纯值。", response_persistence)
	return response

func _resolve_operation(definition, ability, state: Dictionary, context: Dictionary) -> Dictionary:
	match definition.object_kind:
		"door":
			return _resolve_door(definition, ability, state)
		"chest":
			return _resolve_chest(definition, ability, state)
		"mechanism":
			return _resolve_mechanism(definition, ability, state, ability.payload)
		"teleport":
			return _resolve_teleport(definition, ability, state, context)
		"checkpoint":
			return _resolve_checkpoint(definition, ability, state)
		"revive":
			return _resolve_revive(definition, ability, state)
		"extraction":
			return _resolve_extraction(definition, ability, state, context)
		"generator":
			return _resolve_generator(definition, ability, state)
	return _blocked("level_object.resolve.kind", "P24对象类别没有解析分支。")

func _resolve_door(definition, ability, state: Dictionary) -> Dictionary:
	if ability.operation not in ["open", "close", "unlock"]:
		return _unsupported(definition.object_kind, ability.operation)
	var next_state := state.duplicate(true)
	match ability.operation:
		"unlock":
			next_state["locked"] = false
		"open":
			if bool(next_state.get("locked", false)):
				return _blocked("level_object.door.locked", "门处于锁定状态，不能打开。")
			next_state["open"] = true
		"close":
			next_state["open"] = false
	return _accepted(next_state, {"state": next_state})

func _resolve_chest(definition, ability, state: Dictionary) -> Dictionary:
	if ability.operation != "open":
		return _unsupported(definition.object_kind, ability.operation)
	if bool(state.get("opened", false)):
		return _blocked("level_object.chest.already_opened", "箱子已经打开，新的请求不会重复产生内容。")
	var next_state := state.duplicate(true)
	next_state["opened"] = true
	var requests := _domain_requests(ability.payload)
	if not requests.ok:
		return requests
	return _accepted(next_state, {"state": next_state, "opened": true}, {}, requests.value)

func _resolve_mechanism(definition, ability, state: Dictionary, payload: Dictionary) -> Dictionary:
	if ability.operation not in ["activate", "deactivate"]:
		return _unsupported(definition.object_kind, ability.operation)
	var next_state := state.duplicate(true)
	var active: bool = ability.operation == "activate"
	next_state["active"] = active
	var contribution := _contribution(payload, "mechanism")
	if not contribution.ok:
		return contribution
	var requests := _domain_requests(payload)
	if not requests.ok:
		return requests
	return _accepted(next_state, {"state": next_state, "mechanism_state": "active" if active else "inactive"}, contribution.value if active else {}, requests.value)

func _resolve_teleport(definition, ability, state: Dictionary, context: Dictionary) -> Dictionary:
	if ability.operation not in ["teleport", "scene_switch"]:
		return _unsupported(definition.object_kind, ability.operation)
	var destination_check := _destination(definition.destination if not definition.destination.is_empty() else ability.payload.get("destination", {}))
	if not destination_check.ok:
		return destination_check
	var task_context_value = ability.payload.get("task_execution_context", context.get("task_execution_context", {}))
	var task_context_check := CONTEXT.from_dict(task_context_value)
	if not task_context_check.ok:
		return _blocked("level_object.teleport.context_missing", "teleport/scene switch必须携带既有TaskExecutionContext。", task_context_check)
	var return_context_check := _resolve_return_context(definition, task_context_check.value, ability.payload, context)
	if not return_context_check.ok:
		return return_context_check
	var next_state := state.duplicate(true)
	next_state["transported"] = true
	var transport := {
		"target": destination_check.value,
		"task_execution_context": task_context_check.value.to_dict(),
		"return_context": return_context_check.value,
		"scene_switch_requested": ability.operation == "scene_switch"
	}
	return _accepted(next_state, {"state": next_state, "transport": transport}, {}, [], {"transport": transport})

func _resolve_checkpoint(definition, ability, state: Dictionary) -> Dictionary:
	if ability.operation not in ["save_checkpoint", "checkpoint"]:
		return _unsupported(definition.object_kind, ability.operation)
	var position_value: Dictionary = definition.logical_position
	if position_value.is_empty():
		position_value = ability.payload.get("logical_position", {})
	var position_check := PLANAR_POSITION.from_native(position_value)
	if not position_check.ok:
		return _blocked("level_object.checkpoint.position_missing", "checkpoint必须保存稳定Logical Position。", position_check)
	var surface_id := str(definition.surface_id)
	if surface_id.is_empty():
		surface_id = str(ability.payload.get("surface_id", ""))
	if not VALUE.stable_id(surface_id, false) or surface_id != str(position_check.value.surface_id):
		return _blocked("level_object.checkpoint.surface_invalid", "checkpoint必须保存与Logical Position一致的稳定Surface。")
	var checkpoint := {"logical_position": position_check.position.to_native(), "surface_id": surface_id}
	var next_state := state.duplicate(true)
	next_state["active"] = true
	next_state["checkpoint"] = checkpoint
	return _accepted(next_state, {"state": next_state, "checkpoint": checkpoint}, {}, [], {"checkpoint": checkpoint})

func _resolve_revive(definition, ability, state: Dictionary) -> Dictionary:
	if ability.operation != "revive":
		return _unsupported(definition.object_kind, ability.operation)
	var charges_check := VALUE.integer_field(state.get("charges", 1), false)
	if not charges_check.ok or int(charges_check.value) < 1:
		return _blocked("level_object.revive.no_charges", "复活对象没有可用次数。")
	var target_value = ability.payload.get("revive_target_ref", ability.actor_ref)
	var target_check := VALUE.semantic_ref(target_value, false)
	if not target_check.ok:
		return _blocked("level_object.revive.target", "复活目标必须是稳定语义引用。", target_check)
	var next_state := state.duplicate(true)
	next_state["charges"] = int(charges_check.value) - 1
	var revive := {"target_ref": target_check.value, "charges_remaining": int(next_state.charges)}
	return _accepted(next_state, {"state": next_state, "revive": revive}, {"revive": 1}, [], {"revive": revive})

func _resolve_extraction(definition, ability, state: Dictionary, context: Dictionary) -> Dictionary:
	if ability.operation not in ["extract", "fail_return"]:
		return _unsupported(definition.object_kind, ability.operation)
	if ability.operation == "extract" and bool(state.get("extracted", false)):
		return _blocked("level_object.extraction.already_done", "撤离点已经完成，重复请求不会再次返回。")
	var return_context_check := _resolve_return_context(definition, null, ability.payload, context)
	if not return_context_check.ok:
		return return_context_check
	var next_state := state.duplicate(true)
	if ability.operation == "extract":
		next_state["extracted"] = true
		var extraction := {"return_context": return_context_check.value, "strategy": "extraction"}
		return _accepted(next_state, {"state": next_state, "extraction": extraction}, {}, [], {"extraction": extraction})
	var failure_return := {"return_context": return_context_check.value, "strategy": "failure_return"}
	return _accepted(next_state, {"state": next_state, "failure_return": failure_return}, {}, [], {"failure_return": failure_return})

func _resolve_generator(definition, ability, state: Dictionary) -> Dictionary:
	if ability.operation != "generate":
		return _unsupported(definition.object_kind, ability.operation)
	var generator_value = ability.payload.get("generator_recipe", definition.generation)
	if typeof(generator_value) != TYPE_DICTIONARY or generator_value.is_empty():
		return _blocked("level_object.generator.recipe_missing", "generator能力必须携带纯值生成配方。")
	var generated := GENERATOR.new().generate(generator_value, definition)
	if not generated.ok:
		return generated
	var next_state := state.duplicate(true)
	next_state["generated_count"] = int(state.get("generated_count", 0)) + int(generated.value.count)
	return _accepted(next_state, {"state": next_state, "generated": generated.value}, {"generated": int(generated.value.count)}, [], {"generation": generated.value})

func _resolve_return_context(definition, task_context, payload: Dictionary, context: Dictionary) -> Dictionary:
	var candidate: Dictionary = {}
	if not definition.return_context.is_empty():
		candidate = definition.return_context
	elif task_context != null and task_context is GMTaskExecutionContext and not task_context.return_context.is_empty():
		candidate = task_context.return_context
	elif typeof(payload.get("return_context", {})) == TYPE_DICTIONARY and not payload.get("return_context", {}).is_empty():
		candidate = payload.get("return_context", {})
	else:
		candidate = context.get("return_context", {})
	if candidate.is_empty():
		return _blocked("level_object.return_context_missing", "传送、撤离与失败返回必须携带既有ReturnContext。")
	var checked := RETURN_CONTEXT.from_dict(candidate)
	if not checked.ok:
		return _blocked("level_object.return_context_invalid", "ReturnContext未通过既有P23纯值合同。", checked)
	return {"ok": true, "value": checked.value.to_dict()}

func _destination(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _blocked("level_object.destination_type", "传送目标必须是纯字典。")
	var fields := VALUE.exact_fields(value, ["map_id", "anchor_id", "scene_id", "transition"])
	if not fields.ok:
		return _blocked("level_object.destination_shape", "传送目标字段集合无效。")
	for identity in ["map_id", "anchor_id"]:
		if not VALUE.stable_id(value.get(identity, ""), false):
			return _blocked("level_object.destination_identity", "传送目标地图与锚点必须是稳定标识。")
	if not VALUE.stable_id(value.get("scene_id", ""), true) or not VALUE.stable_id(value.get("transition", ""), true):
		return _blocked("level_object.destination_optional", "传送目标可选字段无效。")
	return {"ok": true, "value": {"map_id": str(value.map_id), "anchor_id": str(value.anchor_id), "scene_id": str(value.scene_id), "transition": str(value.transition)}}

func _domain_requests(payload: Dictionary) -> Dictionary:
	if not payload.has("domain_request"):
		return {"ok": true, "value": []}
	var values: Array = payload.domain_request if payload.domain_request is Array else [payload.domain_request]
	var normalized: Array = []
	for value in values:
		var check := FACTS.validate_request_descriptor(value)
		if not check.ok:
			return _blocked("level_object.domain_request_invalid", "对象能力只能携带既有已注册领域请求。", check)
		normalized.append(check.value)
	return {"ok": true, "value": normalized}

func _contribution(payload: Dictionary, default_field: String) -> Dictionary:
	var field := str(payload.get("contribution_field", default_field))
	if not VALUE.stable_id(field, false):
		return _blocked("level_object.contribution_field", "对象事实贡献字段必须是稳定标识。")
	var amount := VALUE.integer_field(payload.get("contribution_amount", 1), false)
	if not amount.ok or int(amount.value) < 1:
		return _blocked("level_object.contribution_amount", "对象事实贡献量必须是正整数。")
	return {"ok": true, "value": {field: int(amount.value)}}

func _accepted(state: Dictionary, outcome: Dictionary, contributions: Dictionary = {}, domain_requests: Array = [], special: Dictionary = {}) -> Dictionary:
	return {"ok": true, "state": VALUE.duplicate_value(state), "outcome": VALUE.duplicate_value(outcome), "contributions": VALUE.duplicate_value(contributions), "domain_requests": VALUE.duplicate_value(domain_requests), "special": VALUE.duplicate_value(special)}

func _unsupported(object_kind: String, operation: String) -> Dictionary:
	return _blocked("level_object.operation_unsupported", "对象类别不支持当前Ability操作。", {"object_kind": object_kind, "operation": operation})

func _replay_receipt(definition, ability, receipts: Dictionary) -> Dictionary:
	if typeof(receipts) != TYPE_DICTIONARY:
		return {"ok": false, "receipt_found": false}
	var receipt_key := ""
	if receipts.has(ability.request_id):
		receipt_key = ability.request_id
	elif receipts.has(ability.idempotency_key):
		receipt_key = ability.idempotency_key
	else:
		return {"ok": false, "receipt_found": false}
	var stored = receipts.get(receipt_key, null)
	if stored == null:
		return {"ok": false, "receipt_found": false}
	if typeof(stored) != TYPE_DICTIONARY or not bool(stored.get("ok", false)):
		return {"ok": false, "receipt_found": false}
	var stored_receipt: Dictionary = stored.get("receipt", {}) if typeof(stored.get("receipt", {})) == TYPE_DICTIONARY else {}
	var expected := {
		"object_id": str(ability.object_ref.get("id", "")),
		"definition_id": str(definition.definition_id),
		"ability_id": str(ability.ability_id),
		"operation": str(ability.operation),
		"ability_fingerprint": ability.fingerprint()
	}
	var actual := {}
	var mismatched_fields: Array[String] = []
	for field in expected.keys():
		var actual_value = stored.get(field, null)
		if not stored.has(field):
			actual_value = stored_receipt.get(field, null)
		actual[field] = str(actual_value) if actual_value != null else ""
		if actual_value == null or str(actual_value) != str(expected[field]):
			mismatched_fields.append(str(field))
	if not mismatched_fields.is_empty():
		var conflict := _blocked(
			"level_object.resolve.receipt_identity_conflict",
			"成功回执身份与当前对象请求不一致，拒绝幂等重放。",
			{"receipt_key": receipt_key, "mismatched_fields": mismatched_fields, "expected": expected, "actual": actual}
		)
		conflict["receipt_found"] = true
		return conflict
	var replay: Dictionary = stored.duplicate(true)
	replay["idempotent"] = true
	replay["replayed_request_id"] = ability.request_id
	return {"ok": true, "receipt_found": true, "value": replay}

static func _as_definition(value: Variant) -> Dictionary:
	if value is RefCounted and value.get_script() == DEFINITION:
		return {"ok": true, "value": value}
	return DEFINITION.from_dict(value)

static func _as_ability(value: Variant) -> Dictionary:
	if value is RefCounted and value.get_script() == ABILITY:
		return {"ok": true, "value": value}
	return ABILITY.from_dict(value)

static func _contains_direct_write_marker(value: Variant) -> bool:
	if value is Array:
		for item in value:
			if _contains_direct_write_marker(item):
				return true
		return false
	if value is Dictionary:
		for key in value.keys():
			var name := str(key).to_lower()
			if name in ["direct_world_write", "direct_task_write", "direct_store_write", "direct_transaction_write", "scene_tree_mutation"] and bool(value[key]):
				return true
			if _contains_direct_write_marker(value[key]):
				return true
	return false

static func _blocked(code: String, error_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error_zh": error_zh}
	if not details.is_empty():
		result["details"] = VALUE.duplicate_value(details)
	return result
