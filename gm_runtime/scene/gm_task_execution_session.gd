class_name GMTaskExecutionSession
extends RefCounted

## P23 唯一场景执行编排权威。
##
## Session 只在内存中持有注入的 Builder/空间后端/既有事务协调器；其
## snapshot 只保存 GMSceneSessionState。场景逻辑通过 ExecutionFacts 与
## 既有领域请求交付事实，永远不直接写 Task、World、Store 或节点树。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const CONTEXT := preload("res://gm_runtime/scene/gm_task_execution_context.gd")
const DEFINITION := preload("res://gm_runtime/scene/gm_scene_session_definition.gd")
const STATE := preload("res://gm_runtime/scene/gm_scene_session_state.gd")
const FACTS := preload("res://gm_runtime/scene/gm_execution_facts.gd")
const RESULT := preload("res://gm_runtime/scene/gm_task_execution_result.gd")
const BUILDER := preload("res://gm_runtime/scene/gm_scene_recipe_builder.gd")
const RETURN_CONTEXT := preload("res://gm_runtime/scene/gm_scene_return_context.gd")
const ABILITY_REQUEST := preload("res://gm_runtime/gas/gm_ability_activation_request.gd")
const INTERACTION_REQUEST := preload("res://gm_runtime/p21/gm_interaction_request.gd")
const COMMITTED_RESULT := preload("res://gm_runtime/events/gm_committed_fact_result.gd")
const BLOCKED_RESULT := preload("res://gm_runtime/events/gm_blocked_result.gd")

const SNAPSHOT_SCHEMA := "gm.scene.session_snapshot.v1"
const SNAPSHOT_FIELDS: Array[String] = ["schema_version", "definition_id", "definition_fingerprint", "state"]

var definition: GMSceneSessionDefinition
var state: GMSceneSessionState
var _builder: GMSceneRecipeBuilder
var _backend: Object

func _init(
	p_definition: GMSceneSessionDefinition = null,
	p_builder: GMSceneRecipeBuilder = null,
	p_backend: Object = null
) -> void:
	definition = p_definition
	_builder = p_builder
	_backend = p_backend
	if definition != null:
		var definition_hash := definition.fingerprint()
		var session_id := "gm.scene.session.%s" % VALUE.digest({"definition": definition.definition_id, "definition_fingerprint": definition_hash, "seed": definition.context.get("seed", 0)})
		state = GMSceneSessionState.new(session_id, definition.definition_id, definition.task_id, "created", int(definition.context.get("seed", 0)))
	else:
		state = GMSceneSessionState.new()

static func open(definition_value: Variant, builder: GMSceneRecipeBuilder = null, backend: Object = null) -> Dictionary:
	var parsed := _as_definition(definition_value)
	if not parsed.ok:
		return parsed
	var definition_object: GMSceneSessionDefinition = parsed.value
	var session := GMTaskExecutionSession.new(definition_object, builder, backend)
	return {"ok": true, "session": session, "state": session.state.to_dict()}

static func from_travel_handoff(handoff: Variant, definition_value: Variant, builder: GMSceneRecipeBuilder = null, backend: Object = null) -> Dictionary:
	var parsed := _as_definition(definition_value)
	if not parsed.ok:
		return parsed
	var session := GMTaskExecutionSession.new(parsed.value, builder, backend)
	var entered := session.enter_from_travel_handoff(handoff)
	if not entered.ok:
		return entered
	return {
		"ok": true,
		"session": session,
		"handoff": entered.get("handoff", {}),
		"entry": entered.get("entry", {}),
		"return_context": entered.get("return_context", {}),
		"state": entered.get("state", {})
	}

static func open_from_travel_handoff(
	handoff: Variant,
	context_value: Variant,
	skeleton_value: Variant,
	recipe_value: Variant,
	builder: GMSceneRecipeBuilder = null,
	backend: Object = null,
	p_definition_id: String = ""
) -> Dictionary:
	var context_check := _as_context(context_value)
	if not context_check.ok:
		return context_check
	var skeleton_check := preload("res://gm_runtime/scene/gm_scene_skeleton_definition.gd").from_dict(skeleton_value) if not skeleton_value is GMSceneSkeletonDefinition else {"ok": true, "value": skeleton_value}
	if not skeleton_check.ok:
		return skeleton_check
	var recipe_check := preload("res://gm_runtime/scene/gm_scene_recipe.gd").from_dict(recipe_value) if not recipe_value is GMSceneRecipe else {"ok": true, "value": recipe_value}
	if not recipe_check.ok:
		return recipe_check
	var context_object: GMTaskExecutionContext = context_check.value
	var skeleton_object: GMSceneSkeletonDefinition = skeleton_check.value
	var recipe_object: GMSceneRecipe = recipe_check.value
	var definition_id := p_definition_id if not p_definition_id.is_empty() else "gm.scene.definition.%s" % VALUE.digest({"task_id": context_object.task_id, "recipe_id": recipe_object.recipe_id, "seed": context_object.seed})
	var return_context := context_object.return_context
	var definition_object := GMSceneSessionDefinition.new(
		definition_id, context_object.task_id, context_object.assignment_id, context_object.to_dict(),
		skeleton_object.to_dict(), recipe_object.to_dict(), return_context
	)
	var definition_check := definition_object.validate()
	if not definition_check.ok:
		return definition_check
	return from_travel_handoff(handoff, definition_object, builder, backend)

func start() -> Dictionary:
	if definition == null:
		return _blocked("scene.session.definition_missing", "TaskExecutionSession缺少SessionDefinition。")
	if state.phase == "active" or state.phase == "paused" or STATE.TERMINAL_PHASES.has(state.phase):
		return {"ok": true, "idempotent": true, "state": state.to_dict(), "build": VALUE.duplicate_value(state.build)}
	if state.phase != "created":
		return _blocked("scene.session.phase_invalid", "TaskExecutionSession当前阶段不能启动。")
	if _builder == null or _backend == null or not is_instance_valid(_backend):
		return _blocked("scene.session.builder_missing", "TaskExecutionSession缺少注入的语义场景Builder或空间后端。")
	var definition_check := definition.validate()
	if not definition_check.ok:
		return _blocked("scene.session.definition_invalid", "TaskExecutionSession定义验证失败。", definition_check)
	var built := _builder.build(definition.recipe, definition.skeleton, definition.context, _backend)
	if not built.ok:
		return built
	var build_value: Dictionary = built.value
	var build_check := BUILDER.parse_build(build_value, definition.recipe, definition.skeleton, definition.context)
	if not build_check.ok:
		return _blocked("scene.session.build_invalid", "语义装配结果未通过严格SceneRecipeBuild解析。", build_check)
	build_value = build_check.value
	var progress := {}
	for objective in definition.recipe.get("objectives", []):
		progress[str(objective.get("objective_id", ""))] = 0
	var return_value: Dictionary = definition.return_context if not definition.return_context.is_empty() else definition.context.get("return_context", {})
	var next_state := GMSceneSessionState.new(
		state.session_id, definition.definition_id, definition.task_id, "active", int(definition.context.get("seed", 0)),
		state.sequence, build_value, state.facts, state.request_refs, state.settlement_refs, progress, {}, return_value, state.handoff_identity
	)
	var next_check := next_state.validate()
	if not next_check.ok:
		return _blocked("scene.session.state_invalid", "TaskExecutionSession启动状态无效。", next_check)
	var semantic_check := _validate_state_against_definition(next_state)
	if not semantic_check.ok:
		return semantic_check
	state = next_state
	return {"ok": true, "state": state.to_dict(), "build": VALUE.duplicate_value(state.build)}

func enter_from_travel_handoff(handoff: Variant) -> Dictionary:
	var handoff_check := _validate_travel_handoff(handoff)
	if not handoff_check.ok:
		return handoff_check
	if definition == null:
		return _blocked("scene.travel.definition_missing", "旅行进入缺少场景定义。")
	var row: Dictionary = handoff_check.value
	var binding := _validate_handoff_binding(row)
	if not binding.ok:
		return binding
	var identity := {"fingerprint": VALUE.digest(row), "handoff": VALUE.duplicate_value(row)}
	if state.phase != "created":
		if state.handoff_identity.is_empty():
			return _blocked("scene.travel.first_handoff_missing", "当前会话不是由已保存的首次P15 handoff进入，拒绝绕过旅行身份绑定。")
		if str(state.handoff_identity.get("fingerprint", "")) != str(identity.fingerprint):
			return _blocked("scene.travel.handoff_conflict", "重复旅行进入与首次handoff身份不一致。")
		return {"ok": true, "idempotent": true, "state": state.to_dict(), "handoff": VALUE.duplicate_value(row), "entry": VALUE.duplicate_value(definition.recipe.get("entry", {})), "return_context": VALUE.duplicate_value(state.return_context)}
	var recipe_entry: Dictionary = definition.recipe.get("entry", {})
	var context_return: Dictionary = definition.return_context if not definition.return_context.is_empty() else definition.context.get("return_context", {})
	var before_start_state := state
	var started := start()
	if not started.ok:
		return started
	state.handoff_identity = identity
	if state.return_context.is_empty():
		var derived_return := RETURN_CONTEXT.new(str(row.source_map_id), str(row.return_anchor_id), {}).to_dict()
		var derived_check := RETURN_CONTEXT.from_dict(derived_return)
		if not derived_check.ok:
			state = before_start_state
			return _blocked("scene.travel.return_context_invalid", "旅行返回上下文生成失败。", derived_check)
		state.return_context = derived_check.value.to_dict()
	var state_check := state.validate()
	if not state_check.ok:
		state = before_start_state
		return _blocked("scene.travel.return_state_invalid", "旅行进入后身份或返回上下文使会话状态无效。", state_check)
	return {
		"ok": true,
		"code": "scene.travel.entered",
		"handoff": VALUE.duplicate_value(row),
		"entry": VALUE.duplicate_value(recipe_entry),
		"return_context": VALUE.duplicate_value(state.return_context if not state.return_context.is_empty() else context_return),
		"state": state.to_dict()
	}

func record_fact(fact_value: Variant) -> Dictionary:
	var fact_check := _as_facts(fact_value)
	if not fact_check.ok:
		return fact_check
	var fact: GMExecutionFacts = fact_check.value
	if fact.session_id != state.session_id:
		return _blocked("scene.session.fact_session_mismatch", "ExecutionFacts不属于当前会话。")
	var existing := _fact_by_id(fact.fact_id)
	if not existing.is_empty():
		if VALUE.digest(VALUE.persistence_canonical(existing)) == VALUE.digest(VALUE.persistence_canonical(fact.to_dict())):
			return {"ok": true, "idempotent": true, "fact_id": fact.fact_id, "state": state.to_dict(), "result": state.result}
		return _blocked("scene.session.fact_conflict", "同一fact_id对应不同事实，拒绝覆盖。")
	if state.phase != "active" and state.phase != "paused":
		return _blocked("scene.session.fact_phase", "当前会话阶段不接受新的ExecutionFacts。")
	if fact.sequence != state.sequence + 1:
		return _blocked("scene.session.fact_sequence", "ExecutionFacts sequence必须严格接续当前会话序号。", {"expected": state.sequence + 1, "actual": fact.sequence})
	var next_requests := state.request_refs.duplicate(true)
	for request_ref in fact.domain_requests:
		var existing_request := _request_ref_by_id(next_requests, str(request_ref.request_id))
		var existing_key := _request_ref_by_key(next_requests, str(request_ref.idempotency_key))
		if not existing_request.is_empty() and VALUE.digest(existing_request) != VALUE.digest(request_ref):
			return _blocked("scene.session.request_conflict", "同一领域请求ID对应不同请求包。")
		if not existing_key.is_empty() and VALUE.digest(existing_key) != VALUE.digest(request_ref):
			return _blocked("scene.session.request_conflict", "同一领域幂等键对应不同请求包。")
		if existing_request.is_empty() and existing_key.is_empty(): next_requests.append(VALUE.duplicate_value(request_ref))
	var next_progress := state.objective_progress.duplicate(true)
	for objective in definition.recipe.get("objectives", []):
		var objective_id := str(objective.get("objective_id", ""))
		var contribution_field := str(objective.get("contribution_field", ""))
		if not fact.contributions.has(contribution_field): continue
		if not _fact_matches_objective(fact, objective): continue
		var amount := int(fact.contributions.get(contribution_field, 0))
		var target_value := int(objective.get("target_value", 1))
		next_progress[objective_id] = mini(target_value, int(next_progress.get(objective_id, 0)) + amount)
	var next_facts := state.facts.duplicate(true)
	next_facts.append(fact.to_dict())
	var next_sequence := fact.sequence
	var next_phase := state.phase
	var next_result: Dictionary = {}
	var progress_status := _status_for_progress(next_progress)
	if not progress_status.ok:
		return progress_status
	if str(progress_status.status) == "success":
		var finished := _make_result("success", "scene.objectives.completed", "所有场景目标已完成。", next_facts, next_requests, state.settlement_refs, state.return_context, next_progress)
		if not finished.ok: return finished
		next_result = finished.value.to_dict()
		next_phase = "succeeded"
	var next_state := GMSceneSessionState.new(
		state.session_id, state.definition_id, state.task_id, next_phase, state.seed, next_sequence,
		state.build, next_facts, next_requests, state.settlement_refs, next_progress, next_result, state.return_context, state.handoff_identity
	)
	var next_check := next_state.validate()
	if not next_check.ok:
		return _blocked("scene.session.fact_state_invalid", "记录事实后会话状态无效。", next_check)
	var semantic_check := _validate_state_against_definition(next_state)
	if not semantic_check.ok:
		return semantic_check
	state = next_state
	return {"ok": true, "fact_id": fact.fact_id, "state": state.to_dict(), "result": state.result}

func record_domain_request(request: Object, fact_kind: String = "domain_request") -> Dictionary:
	if request == null or not is_instance_valid(request) or not request.has_method("validate") or not request.has_method("to_dict"):
		return _blocked("scene.session.request_type", "P23只能接收既有领域请求，不接受手写世界写入。")
	var request_check: Dictionary = request.validate()
	if not bool(request_check.get("ok", false)):
		return _blocked("scene.session.request_invalid", "既有领域请求验证失败。", request_check)
	var descriptor := _request_descriptor(request)
	if not descriptor.ok:
		return descriptor
	var previous_request := _request_ref_by_id(state.request_refs, str(descriptor.value.request_id))
	if not previous_request.is_empty():
		if VALUE.digest(previous_request) == VALUE.digest(descriptor.value):
			return {"ok": true, "idempotent": true, "request_id": descriptor.value.request_id, "state": state.to_dict()}
		return _blocked("scene.session.request_conflict", "同一领域请求ID对应不同请求包。")
	var previous_key := _request_ref_by_key(state.request_refs, str(descriptor.value.idempotency_key))
	if not previous_key.is_empty():
		if VALUE.digest(previous_key) == VALUE.digest(descriptor.value):
			return {"ok": true, "idempotent": true, "request_id": descriptor.value.request_id, "state": state.to_dict()}
		return _blocked("scene.session.request_conflict", "同一领域幂等键对应不同请求包。")
	var fact_id := "gm.scene.fact.request.%s" % VALUE.digest({"session_id": state.session_id, "idempotency_key": descriptor.value.idempotency_key})
	var fact := GMExecutionFacts.new(
		fact_id, state.session_id, state.sequence + 1, fact_kind, {}, {}, {}, {}, [descriptor.value], [], {}
	)
	return record_fact(fact)

func settle_domain_request(
	request: Object,
	resolver: Object,
	coordinator: Object,
	fact_store: Object,
	change_store: Object,
	metadata: Dictionary = {}
) -> Dictionary:
	if request == null or not is_instance_valid(request) or not request is ABILITY_REQUEST:
		return _blocked("scene.session.settlement_request", "领域结算必须使用既有GMAbilityActivationRequest。")
	if resolver == null or coordinator == null or fact_store == null or change_store == null:
		return _blocked("scene.session.settlement_dependency", "领域结算缺少既有Resolver、Coordinator或Fact/Change Store。")
	if state.phase != "active" and state.phase != "paused":
		return _blocked("scene.session.settlement_phase", "当前会话阶段不接受领域请求结算。")
	var request_check: Dictionary = request.validate()
	if not request_check.ok:
		return _blocked("scene.session.settlement_request_invalid", "既有领域请求验证失败。", request_check)
	var descriptor := _request_descriptor(request)
	if not descriptor.ok:
		return descriptor
	var existing_request := _request_ref_by_id(state.request_refs, str(descriptor.value.request_id))
	var existing_key := _request_ref_by_key(state.request_refs, str(descriptor.value.idempotency_key))
	if (not existing_request.is_empty() and VALUE.digest(existing_request) != VALUE.digest(descriptor.value)) or (not existing_key.is_empty() and VALUE.digest(existing_key) != VALUE.digest(descriptor.value)):
		return _blocked("scene.session.request_conflict", "结算前发现同一请求ID或幂等键对应不同请求包。")
	var result = coordinator.resolve(request, resolver, fact_store, change_store, metadata, request.causal_chain)
	if result is COMMITTED_RESULT:
		var committed: GMCommittedFactResult = result
		if committed.fact_event == null:
			return _blocked("scene.session.settlement_proof_missing", "既有事务协调器返回的提交结果缺少FactEvent。")
		var ref := {
			"request_id": request.request_id,
			"idempotency_key": request.idempotency_key if not request.idempotency_key.is_empty() else request.request_id,
			"fact_event_id": committed.fact_event.event_id,
			"transaction_id": committed.transaction_id,
			"idempotent": committed.idempotent
		}
		var ref_check := VALUE.persistence(ref)
		if not ref_check.ok:
			return _blocked("scene.session.settlement_ref_invalid", "事务提交回执引用不可持久化。", ref_check)
		var recorded := record_domain_request(request)
		if not bool(recorded.get("ok", false)) and not bool(recorded.get("idempotent", false)):
			return recorded
		var next_settlements := state.settlement_refs.duplicate(true)
		var already := false
		for existing in next_settlements:
			if typeof(existing) == TYPE_DICTIONARY and str(existing.get("idempotency_key", "")) == str(ref.idempotency_key):
				already = true
				var existing_identity: Dictionary = existing.duplicate(true)
				var ref_identity: Dictionary = ref.duplicate(true)
				existing_identity.erase("idempotent")
				ref_identity.erase("idempotent")
				if VALUE.digest(existing_identity) != VALUE.digest(ref_identity): return _blocked("scene.session.settlement_conflict", "同一幂等键对应不同结算回执。")
		if not already: next_settlements.append(ref)
		var next_state := GMSceneSessionState.new(
			state.session_id, state.definition_id, state.task_id, state.phase, state.seed, state.sequence,
			state.build, state.facts, state.request_refs, next_settlements, state.objective_progress, state.result,
			state.return_context, state.handoff_identity
		)
		var next_check := next_state.validate()
		if not next_check.ok:
			return _blocked("scene.session.settlement_state_invalid", "记录领域结算回执后会话状态无效。", next_check)
		var semantic_check := _validate_state_against_definition(next_state)
		if not semantic_check.ok:
			return semantic_check
		state = next_state
		return {"ok": true, "committed": committed, "idempotent": committed.idempotent, "receipt": ref, "state": state.to_dict()}
	if result is BLOCKED_RESULT:
		return {"ok": false, "committed": false, "result": result, "error_code": result.error_code, "error_zh": result.reason_zh}
	return _blocked("scene.session.settlement_result_invalid", "既有事务协调器返回未知结果，未接受为场景结算。")

func request_extraction(reason_code: String = "scene.extraction.voluntary", reason_zh: String = "执行者主动撤离。") -> Dictionary:
	if STATE.TERMINAL_PHASES.has(state.phase):
		return {"ok": true, "idempotent": true, "result": state.result, "state": state.to_dict()}
	if state.phase != "active" and state.phase != "paused":
		return _blocked("scene.session.extraction_phase", "当前会话阶段不能撤离。")
	var status_check := _status_for_progress(state.objective_progress)
	if not status_check.ok:
		return status_check
	return _finish(str(status_check.status), reason_code, reason_zh, "extracted")

func request_return(reason_code: String = "scene.return.completed", reason_zh: String = "场景执行返回既有世界。") -> Dictionary:
	if state.phase == "returned":
		return {"ok": true, "idempotent": true, "result": state.result, "return_context": state.return_context, "state": state.to_dict()}
	if state.phase == "succeeded" or state.phase == "partially_succeeded" or state.phase == "extracted" or state.phase == "failed":
		var next_state := GMSceneSessionState.new(
			state.session_id, state.definition_id, state.task_id, "returned", state.seed, state.sequence,
			state.build, state.facts, state.request_refs, state.settlement_refs, state.objective_progress, state.result,
			state.return_context, state.handoff_identity
		)
		var checked_terminal := next_state.validate()
		if not checked_terminal.ok: return _blocked("scene.session.return_state_invalid", "成功/失败会话返回时状态无效。", checked_terminal)
		var semantic_check := _validate_state_against_definition(next_state)
		if not semantic_check.ok: return semantic_check
		state = next_state
		return {"ok": true, "result": state.result, "return_context": state.return_context, "state": state.to_dict()}
	if state.phase != "active" and state.phase != "paused":
		return _blocked("scene.session.return_phase", "当前会话阶段不能返回。")
	var status_check := _status_for_progress(state.objective_progress)
	if not status_check.ok:
		return status_check
	return _finish(str(status_check.status), reason_code, reason_zh, "returned")

func fail(reason_code: String = "scene.execution.failed", reason_zh: String = "场景执行失败。") -> Dictionary:
	if state.phase == "failed":
		return {"ok": true, "idempotent": true, "result": state.result, "state": state.to_dict()}
	if state.phase != "active" and state.phase != "paused":
		return _blocked("scene.session.failure_phase", "当前会话阶段不能标记失败。")
	return _finish("failed", reason_code, reason_zh, "failed")

func pause() -> Dictionary:
	if state.phase != "active": return _blocked("scene.session.pause_phase", "只有active会话可以暂停。")
	state.phase = "paused"
	return {"ok": true, "state": state.to_dict()}

func resume() -> Dictionary:
	if state.phase != "paused": return _blocked("scene.session.resume_phase", "只有paused会话可以恢复。")
	state.phase = "active"
	return {"ok": true, "state": state.to_dict()}

func close() -> Dictionary:
	if state.phase == "closed": return {"ok": true, "idempotent": true, "state": state.to_dict()}
	if not STATE.TERMINAL_PHASES.has(state.phase): return _blocked("scene.session.close_phase", "只有终止会话可以关闭。")
	state.phase = "closed"
	return {"ok": true, "state": state.to_dict()}

func snapshot() -> Dictionary:
	var value := {
		"schema_version": SNAPSHOT_SCHEMA,
		"definition_id": definition.definition_id if definition != null else state.definition_id,
		"definition_fingerprint": definition.fingerprint() if definition != null else "",
		"state": state.to_dict()
	}
	return value

func save_snapshot() -> Dictionary:
	return snapshot()

func snapshot_json() -> String:
	return VALUE.json_string(snapshot())

func prepare_snapshot(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, SNAPSHOT_FIELDS)
	if not fields.ok: return fields
	var stable := VALUE.persistence(value)
	if not stable.ok: return stable
	if value.schema_version != SNAPSHOT_SCHEMA: return _blocked("scene.session.snapshot_schema", "Session snapshot Schema版本不匹配。")
	if definition == null or str(value.definition_id) != definition.definition_id or str(value.definition_fingerprint) != definition.fingerprint():
		return _blocked("scene.session.snapshot_definition", "Session snapshot不属于当前场景定义。")
	var state_check := STATE.from_dict(value.state)
	if not state_check.ok: return state_check
	var candidate: GMSceneSessionState = state_check.value
	if candidate.session_id != state.session_id or candidate.definition_id != definition.definition_id or candidate.task_id != definition.task_id:
		return _blocked("scene.session.snapshot_identity", "Session snapshot身份与当前会话不一致。")
	if candidate.seed != int(definition.context.get("seed", 0)):
		return _blocked("scene.session.snapshot_seed", "Session snapshot种子与定义不一致。")
	var semantic_check := _validate_state_against_definition(candidate)
	if not semantic_check.ok:
		return semantic_check
	if not candidate.build.is_empty():
		if _builder == null or _backend == null or not is_instance_valid(_backend): return _blocked("scene.session.snapshot_builder", "恢复非空会话需要同一语义Builder与空间后端。")
		var rebuilt := _builder.build(definition.recipe, definition.skeleton, definition.context, _backend)
		if not rebuilt.ok: return rebuilt
		var rebuilt_check := BUILDER.parse_build(rebuilt.value, definition.recipe, definition.skeleton, definition.context)
		if not rebuilt_check.ok: return rebuilt_check
		if VALUE.digest(VALUE.persistence_canonical(rebuilt_check.value)) != VALUE.digest(VALUE.persistence_canonical(candidate.build)):
			return _blocked("scene.session.snapshot_build_drift", "恢复时后端语义装配结果与存档完整内容不一致。")
	return {"ok": true, "prepared": {"state": candidate}}

func commit_prepared_snapshot(prepared: Dictionary) -> Dictionary:
	# The candidate was fully parsed, replay-checked and semantically rebuilt in prepare_snapshot.
	state = prepared.get("state")
	return {"ok": true, "restored": true, "state": state.to_dict()}

func restore_snapshot(value: Variant) -> Dictionary:
	var prepared := prepare_snapshot(value)
	if not prepared.ok: return prepared
	return commit_prepared_snapshot(prepared.prepared)

func restore_snapshot_json(text: String) -> Dictionary:
	var parsed := VALUE.parse_json(text)
	if not parsed.ok: return parsed
	return restore_snapshot(parsed.value)

func state_value() -> Dictionary:
	return state.to_dict()

func _finish(status: String, reason_code: String, reason_zh: String, phase: String) -> Dictionary:
	var made := _make_result(status, reason_code, reason_zh, state.facts, state.request_refs, state.settlement_refs, state.return_context, state.objective_progress)
	if not made.ok: return made
	var result_value: GMTaskExecutionResult = made.value
	var next_state := GMSceneSessionState.new(
		state.session_id, state.definition_id, state.task_id, phase, state.seed, state.sequence,
		state.build, state.facts, state.request_refs, state.settlement_refs, state.objective_progress, result_value.to_dict(), state.return_context, state.handoff_identity
	)
	var checked := next_state.validate()
	if not checked.ok: return _blocked("scene.session.finish_state_invalid", "场景结束状态无效。", checked)
	var semantic_check := _validate_state_against_definition(next_state)
	if not semantic_check.ok:
		return semantic_check
	state = next_state
	return {"ok": true, "result": result_value.to_dict(), "return_context": VALUE.duplicate_value(state.return_context), "state": state.to_dict()}

func _make_result(status: String, reason_code: String, reason_zh: String, fact_values: Array, request_values: Array, settlement_values: Array, return_value: Dictionary, progress: Dictionary) -> Dictionary:
	var completed: Array = []
	var pending: Array = []
	for objective in definition.recipe.get("objectives", []):
		var objective_id := str(objective.get("objective_id", ""))
		if int(progress.get(objective_id, 0)) >= int(objective.get("target_value", 1)): completed.append(objective_id)
		else: pending.append(objective_id)
	var rule_check := _find_result_rule(status, completed)
	if not rule_check.ok:
		return rule_check
	var rule: Dictionary = rule_check.rule
	var fact_ids: Array = []
	for fact_value in fact_values:
		if typeof(fact_value) == TYPE_DICTIONARY: fact_ids.append(str(fact_value.get("fact_id", "")))
	var request_ids: Array = []
	for request_value in request_values:
		if typeof(request_value) == TYPE_DICTIONARY: request_ids.append(str(request_value.get("request_id", "")))
	var authoritative_reason_code := str(rule.get("reason_code", reason_code))
	var result_id := "gm.scene.result.%s" % VALUE.digest({"session_id": state.session_id, "status": status, "rule_id": str(rule.get("result_id", "")), "facts": fact_ids, "reason_code": authoritative_reason_code})
	var result := GMTaskExecutionResult.new(result_id, state.session_id, definition.task_id, status, authoritative_reason_code, reason_zh, completed, pending, fact_ids, request_ids, settlement_values, return_value, false)
	var checked := result.validate()
	if not checked.ok: return _blocked("scene.session.result_invalid", "生成场景结果失败。", checked)
	return {"ok": true, "value": result}

func _status_for_progress(progress: Dictionary) -> Dictionary:
	var completed := _completed_objective_ids(progress)
	var success_rule := _find_result_rule("success", completed)
	if success_rule.ok:
		return {"ok": true, "status": "success", "rule": success_rule.rule}
	if _has_objective_progress_in(progress):
		var partial_rule := _find_result_rule("partial_success", completed)
		if partial_rule.ok:
			return {"ok": true, "status": "partial_success", "rule": partial_rule.rule}
	var extracted_rule := _find_result_rule("extracted", completed)
	if extracted_rule.ok:
		return {"ok": true, "status": "extracted", "rule": extracted_rule.rule}
	return _blocked("scene.session.result_rule_missing", "当前目标进度没有可适用的Recipe结果规则。")

func _find_result_rule(status: String, completed: Array) -> Dictionary:
	var matches: Array[Dictionary] = []
	for raw_rule in definition.recipe.get("results", []):
		if typeof(raw_rule) != TYPE_DICTIONARY or str(raw_rule.get("status", "")) != status:
			continue
		var required: Variant = raw_rule.get("required_objective_ids", [])
		if not required is Array:
			continue
		var satisfied := true
		for objective_id in required:
			if str(objective_id) not in completed:
				satisfied = false
				break
		if satisfied:
			matches.append(raw_rule)
	matches.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left.get("result_id", "")) < str(right.get("result_id", "")))
	if matches.is_empty():
		return _blocked("scene.session.result_rule_missing", "Recipe没有满足当前状态的结果规则。", {"status": status, "completed_objective_ids": completed})
	return {"ok": true, "rule": VALUE.duplicate_value(matches[0])}

func _completed_objective_ids(progress: Dictionary) -> Array:
	var completed: Array = []
	for objective in definition.recipe.get("objectives", []):
		var objective_id := str(objective.get("objective_id", ""))
		if int(progress.get(objective_id, 0)) >= int(objective.get("target_value", 1)):
			completed.append(objective_id)
	return completed

func _has_objective_progress_in(progress: Dictionary) -> bool:
	for value in progress.values():
		if int(value) > 0:
			return true
	return false

func _rebuild_progress(facts_value: Array) -> Dictionary:
	var progress := {}
	for objective in definition.recipe.get("objectives", []):
		progress[str(objective.get("objective_id", ""))] = 0
	var previous_sequence := 0
	for raw_fact in facts_value:
		var fact_check := FACTS.from_dict(raw_fact)
		if not fact_check.ok:
			return _blocked("scene.session.replay_fact_invalid", "恢复时ExecutionFacts无法重新解析。", fact_check)
		var fact: GMExecutionFacts = fact_check.value
		if fact.session_id != state.session_id:
			return _blocked("scene.session.replay_fact_session", "恢复时事实不属于当前会话。")
		if fact.sequence != previous_sequence + 1:
			return _blocked("scene.session.replay_fact_sequence", "恢复时事实序列无法连续重放。")
		previous_sequence = fact.sequence
		for objective in definition.recipe.get("objectives", []):
			var objective_id := str(objective.get("objective_id", ""))
			var contribution_field := str(objective.get("contribution_field", ""))
			if not fact.contributions.has(contribution_field) or not _fact_matches_objective(fact, objective):
				continue
			var amount := int(fact.contributions.get(contribution_field, 0))
			var target_value := int(objective.get("target_value", 1))
			progress[objective_id] = mini(target_value, int(progress.get(objective_id, 0)) + amount)
	return {"ok": true, "value": progress}

func _request_refs_from_facts(facts_value: Array) -> Dictionary:
	var refs: Array = []
	var request_ids := {}
	var idempotency_keys := {}
	for raw_fact in facts_value:
		var fact_check := FACTS.from_dict(raw_fact)
		if not fact_check.ok:
			return _blocked("scene.session.replay_fact_invalid", "恢复时事实无法解析为类型化ExecutionFacts。", fact_check)
		var fact: GMExecutionFacts = fact_check.value
		for raw_request in fact.domain_requests:
			var request_check := FACTS.validate_request_descriptor(raw_request)
			if not request_check.ok:
				return _blocked("scene.session.replay_request_invalid", "恢复时领域请求未通过既有严格解析器。", request_check)
			var request_ref: Dictionary = request_check.value
			if request_ids.has(str(request_ref.request_id)) or idempotency_keys.has(str(request_ref.idempotency_key)):
				return _blocked("scene.session.replay_request_duplicate", "恢复时领域请求ID或幂等键重复。")
			request_ids[str(request_ref.request_id)] = true
			idempotency_keys[str(request_ref.idempotency_key)] = true
			refs.append(request_ref)
	return {"ok": true, "value": refs}

func _validate_state_against_definition(candidate: GMSceneSessionState) -> Dictionary:
	if definition == null:
		return _blocked("scene.session.definition_missing", "当前会话缺少定义。")
	if candidate.definition_id != definition.definition_id or candidate.task_id != definition.task_id:
		return _blocked("scene.session.state_identity", "会话状态身份与当前定义不一致。")
	if candidate.phase == "created":
		if not candidate.build.is_empty() or not candidate.facts.is_empty() or not candidate.request_refs.is_empty() or not candidate.settlement_refs.is_empty() or not candidate.objective_progress.is_empty() or not candidate.result.is_empty() or not candidate.handoff_identity.is_empty():
			return _blocked("scene.session.created_state_nonempty", "created会话不得携带已执行状态。")
		return {"ok": true}
	if candidate.build.is_empty():
		return _blocked("scene.session.build_missing", "非created会话必须携带严格SceneRecipeBuild。")
	var build_check := BUILDER.parse_build(candidate.build, definition.recipe, definition.skeleton, definition.context)
	if not build_check.ok:
		return _blocked("scene.session.build_invalid", "会话状态build未通过严格解析。", build_check)
	var progress_check := _rebuild_progress(candidate.facts)
	if not progress_check.ok:
		return progress_check
	if VALUE.digest(progress_check.value) != VALUE.digest(candidate.objective_progress):
		return _blocked("scene.session.progress_facts_mismatch", "objective_progress必须与已验证facts重建结果完全一致。")
	var request_check := _request_refs_from_facts(candidate.facts)
	if not request_check.ok:
		return request_check
	if VALUE.digest(request_check.value) != VALUE.digest(candidate.request_refs):
		return _blocked("scene.session.request_refs_facts_mismatch", "request_refs必须与facts中的类型化领域请求完全一致。")
	var request_ids := {}
	for request_ref in candidate.request_refs:
		request_ids[str(request_ref.get("request_id", ""))] = true
	for settlement in candidate.settlement_refs:
		if not request_ids.has(str(settlement.get("request_id", ""))):
			return _blocked("scene.session.settlement_request_missing", "结算回执必须引用已记录的领域请求。")
	if not candidate.result.is_empty():
		var result_check := RESULT.from_dict(candidate.result)
		if not result_check.ok:
			return _blocked("scene.session.result_invalid", "会话状态结果未通过严格解析。", result_check)
		var result: GMTaskExecutionResult = result_check.value
		var expected_completed := _completed_objective_ids(candidate.objective_progress)
		var expected_pending: Array = []
		for objective in definition.recipe.get("objectives", []):
			var objective_id := str(objective.get("objective_id", ""))
			if objective_id not in expected_completed: expected_pending.append(objective_id)
		var expected_fact_ids: Array = []
		for fact_value in candidate.facts: expected_fact_ids.append(str(fact_value.get("fact_id", "")))
		var expected_request_ids: Array = []
		for request_value in candidate.request_refs: expected_request_ids.append(str(request_value.get("request_id", "")))
		if result.completed_objective_ids != expected_completed or result.pending_objective_ids != expected_pending or result.fact_ids != expected_fact_ids or result.request_ids != expected_request_ids or VALUE.digest(result.settlement_refs) != VALUE.digest(candidate.settlement_refs):
			return _blocked("scene.session.result_state_mismatch", "结果中的目标、事实、请求或结算引用与会话状态不一致。")
		var rule_check := _find_result_rule(result.status, expected_completed)
		if not rule_check.ok:
			return rule_check
	if not candidate.handoff_identity.is_empty():
		var handoff_check := _validate_handoff_binding(candidate.handoff_identity.get("handoff", {}))
		if not handoff_check.ok:
			return handoff_check
	return {"ok": true}

func _all_objectives_complete(progress: Dictionary) -> bool:
	for objective in definition.recipe.get("objectives", []):
		var objective_id := str(objective.get("objective_id", ""))
		if int(progress.get(objective_id, 0)) < int(objective.get("target_value", 1)): return false
	return true

func _has_objective_progress() -> bool:
	for value in state.objective_progress.values():
		if int(value) > 0: return true
	return false

func _fact_matches_objective(fact: GMExecutionFacts, objective: Dictionary) -> bool:
	var objective_target: Dictionary = objective.get("target_ref", {})
	if objective_target.is_empty() or fact.target_ref.is_empty(): return true
	return VALUE.digest(objective_target) == VALUE.digest(fact.target_ref)

func _fact_by_id(fact_id: String) -> Dictionary:
	for value in state.facts:
		if typeof(value) == TYPE_DICTIONARY and str(value.get("fact_id", "")) == fact_id: return value
	return {}

func _request_ref_by_id(values: Array, request_id: String) -> Dictionary:
	for value in values:
		if typeof(value) == TYPE_DICTIONARY and str(value.get("request_id", "")) == request_id: return value
	return {}

func _request_ref_by_key(values: Array, idempotency_key: String) -> Dictionary:
	for value in values:
		if typeof(value) == TYPE_DICTIONARY and str(value.get("idempotency_key", "")) == idempotency_key: return value
	return {}

func _request_descriptor(request: Object) -> Dictionary:
	var request_id := str(request.get("request_id"))
	var key := str(request.get("idempotency_key"))
	if key.is_empty(): key = request_id
	if not VALUE.stable_id(request_id) or not VALUE.stable_id(key):
		return _blocked("scene.session.request_identity", "既有领域请求缺少稳定request_id或幂等键。")
	var request_value: Dictionary = request.to_dict()
	# GMAbilityActivationRequest.to_dict() intentionally exposes runtime diagnostics
	# (host instance id, local timestamp and causal-chain copy). P23 stores only the
	# stable request payload as a reference; the live request itself still goes to
	# the existing Coordinator for settlement.
	request_value.erase("host_id")
	request_value.erase("created_at_usec")
	request_value.erase("causal_chain_id")
	var stable := VALUE.persistence(request_value)
	if not stable.ok: return _blocked("scene.session.request_not_persistable", "既有领域请求不能转为P23纯值请求引用。", stable)
	var request_kind := ""
	if request is ABILITY_REQUEST:
		request_kind = "ability_activation"
	elif request is INTERACTION_REQUEST:
		request_kind = "interaction_request"
	else:
		return _blocked("scene.session.request_unregistered", "P23只能接收已注册的GMAbilityActivationRequest或P21 InteractionRequest。")
	var descriptor := {"request_kind": request_kind, "request_id": request_id, "idempotency_key": key, "request": request_value}
	var descriptor_check := FACTS.validate_request_descriptor(descriptor)
	if not descriptor_check.ok:
		return _blocked("scene.session.request_contract_invalid", "既有领域请求序列化未通过ExecutionFacts严格合同。", descriptor_check)
	return descriptor_check

static func _validate_travel_handoff(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _blocked("scene.travel.envelope_required", "P23旅行进入只能接收完整P15 envelope。")
	var envelope_fields := VALUE.exact_fields(value, ["ok", "completed", "handoff", "scene_session_created", "deferred_to"])
	if not envelope_fields.ok:
		return envelope_fields
	var envelope_stable := VALUE.persistence(value)
	if not envelope_stable.ok:
		return envelope_stable
	if typeof(value.ok) != TYPE_BOOL or typeof(value.completed) != TYPE_BOOL or typeof(value.scene_session_created) != TYPE_BOOL or typeof(value.deferred_to) != TYPE_STRING:
		return _blocked("scene.travel.envelope_type", "旅行握手外层字段类型无效。")
	if not bool(value.ok) or not bool(value.completed) or str(value.deferred_to) != "P23" or bool(value.scene_session_created):
		return _blocked("scene.travel.not_deferred", "旅行握手不是completed且延迟至P23的合法结果。")
	var row: Variant = value.get("handoff", {})
	if typeof(row) != TYPE_DICTIONARY:
		return _blocked("scene.travel.shape", "旅行握手内层必须是纯字典。")
	var fields := VALUE.exact_fields(row, ["schema", "actor_id", "source_map_id", "target_map_id", "entry_anchor_id", "exit_anchor_id", "return_anchor_id", "request_source", "owner_id"])
	if not fields.ok: return fields
	if str(row.schema) != "gm.movement.travel_handoff.v1": return _blocked("scene.travel.schema", "旅行握手Schema不匹配。")
	for identity in ["actor_id", "source_map_id", "target_map_id", "entry_anchor_id", "exit_anchor_id", "return_anchor_id", "request_source", "owner_id"]:
		if not VALUE.stable_id(row.get(identity), false): return _blocked("scene.travel.identity", "旅行握手包含非法稳定标识。", {"field": identity})
	if str(row.source_map_id).is_empty() or str(row.target_map_id).is_empty() or str(row.return_anchor_id).is_empty():
		return _blocked("scene.travel.reference_missing", "旅行握手缺少地图或返回锚点。")
	if str(row.owner_id) != str(row.actor_id):
		return _blocked("scene.travel.owner_mismatch", "旅行握手owner必须与actor绑定。")
	return {"ok": true, "value": VALUE.duplicate_value(row), "envelope": VALUE.duplicate_value(value)}

func _validate_handoff_binding(row: Dictionary) -> Dictionary:
	if definition == null:
		return _blocked("scene.travel.definition_missing", "旅行进入缺少场景定义。")
	if str(row.owner_id) != str(row.actor_id):
		return _blocked("scene.travel.owner_mismatch", "旅行握手owner必须与actor绑定。")
	var participant_bound := false
	for participant in definition.context.get("participants", []):
		if typeof(participant) == TYPE_DICTIONARY and str(participant.get("type", "")) == "actor" and str(participant.get("id", "")) == str(row.actor_id):
			participant_bound = true
			break
	if not participant_bound:
		return _blocked("scene.travel.actor_not_participant", "旅行握手actor必须属于TaskExecutionContext participants。")
	var recipe_entry: Dictionary = definition.recipe.get("entry", {})
	var recipe_exit: Dictionary = definition.recipe.get("exit", {})
	var entry_binding := _validate_recipe_anchor_binding(recipe_entry, str(row.target_map_id), str(row.entry_anchor_id), "entry")
	if not entry_binding.ok:
		return entry_binding
	var exit_binding := _validate_recipe_anchor_binding(recipe_exit, str(row.target_map_id), str(row.exit_anchor_id), "exit")
	if not exit_binding.ok:
		return exit_binding
	var extraction := _find_recipe_slot("extraction")
	if extraction.is_empty():
		return _blocked("scene.travel.extraction_missing", "Recipe缺少可绑定的extraction插槽。")
	var extraction_binding := _validate_recipe_anchor_binding(extraction.get("target_ref", {}), str(row.target_map_id), str(row.exit_anchor_id), "extraction")
	if not extraction_binding.ok:
		return extraction_binding
	var context_return: Dictionary = definition.return_context if not definition.return_context.is_empty() else definition.context.get("return_context", {})
	if context_return.is_empty():
		return _blocked("scene.travel.return_context_missing", "旅行进入必须在Context或Definition中声明ReturnContext。")
	if str(context_return.get("map_id", "")) != str(row.source_map_id) or str(context_return.get("anchor_id", "")) != str(row.return_anchor_id):
		return _blocked("scene.travel.return_mismatch", "旅行来源与场景返回锚点不一致。")
	return {"ok": true}

func _validate_recipe_anchor_binding(reference: Variant, map_id: String, anchor_id: String, label: String) -> Dictionary:
	if not reference is Dictionary or reference.is_empty():
		return _blocked("scene.travel.%s_missing" % label, "Recipe%s缺少可绑定的地图锚点引用。" % label)
	var recipe_map_id := str(reference.get("map_id", ""))
	var recipe_anchor_id := str(reference.get("semantic_id", reference.get("id", "")))
	if recipe_map_id.is_empty() or recipe_anchor_id.is_empty():
		return _blocked("scene.travel.%s_unbound" % label, "Recipe%s必须提供地图与锚点稳定身份。" % label)
	if recipe_map_id != map_id or recipe_anchor_id != anchor_id:
		return _blocked("scene.travel.%s_mismatch" % label, "旅行%s锚点与Recipe绑定不一致。" % label)
	return {"ok": true}

func _find_recipe_slot(kind: String) -> Dictionary:
	for slot in definition.recipe.get("slots", []):
		if typeof(slot) == TYPE_DICTIONARY and str(slot.get("slot_kind", "")) == kind:
			return slot
	return {}

static func _as_definition(value: Variant) -> Dictionary:
	if value is GMSceneSessionDefinition: return {"ok": true, "value": value}
	return DEFINITION.from_dict(value)

static func _as_context(value: Variant) -> Dictionary:
	if value is GMTaskExecutionContext: return {"ok": true, "value": value}
	return CONTEXT.from_dict(value)

static func _as_facts(value: Variant) -> Dictionary:
	if value is GMExecutionFacts: return {"ok": true, "value": value}
	return FACTS.from_dict(value)

static func _blocked(code: String, error_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error_zh": error_zh}
	if not details.is_empty(): result["details"] = VALUE.duplicate_value(details)
	return result
