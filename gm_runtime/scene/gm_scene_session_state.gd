class_name GMSceneSessionState
extends RefCounted

## 可保存的会话进度。它只保存场景事实、请求/回执引用与派生目标进度，
## 不复制 P16 Task、GMWorld、GMStore 或 P19 Transaction 的权威状态。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const FACTS := preload("res://gm_runtime/scene/gm_execution_facts.gd")
const RESULT := preload("res://gm_runtime/scene/gm_task_execution_result.gd")
const RETURN_CONTEXT := preload("res://gm_runtime/scene/gm_scene_return_context.gd")

const SCHEMA_VERSION := "gm.scene.session_state.v1"
const FIELDS: Array[String] = [
	"schema_version", "session_id", "definition_id", "task_id", "phase", "seed", "sequence", "build",
	"facts", "request_refs", "settlement_refs", "objective_progress", "result", "return_context", "handoff_identity"
]
const HANDOFF_IDENTITY_FIELDS: Array[String] = ["fingerprint", "handoff"]
const HANDOFF_FIELDS: Array[String] = ["schema", "actor_id", "source_map_id", "target_map_id", "entry_anchor_id", "exit_anchor_id", "return_anchor_id", "request_source", "owner_id"]
const SETTLEMENT_FIELDS: Array[String] = ["request_id", "idempotency_key", "fact_event_id", "transaction_id", "idempotent"]
const PHASES: Array[String] = ["created", "entered", "active", "paused", "extracted", "succeeded", "partially_succeeded", "failed", "returned", "closed"]
const TERMINAL_PHASES: Array[String] = ["extracted", "succeeded", "partially_succeeded", "failed", "returned", "closed"]

var session_id: String
var definition_id: String
var task_id: String
var phase: String
var seed: int
var sequence: int
var build: Dictionary
var facts: Array
var request_refs: Array
var settlement_refs: Array
var objective_progress: Dictionary
var result: Dictionary
var return_context: Dictionary
var handoff_identity: Dictionary

func _init(
	p_session_id: String = "",
	p_definition_id: String = "",
	p_task_id: String = "",
	p_phase: String = "created",
	p_seed: int = 0,
	p_sequence: int = 0,
	p_build: Dictionary = {},
	p_facts: Array = [],
	p_request_refs: Array = [],
	p_settlement_refs: Array = [],
	p_objective_progress: Dictionary = {},
	p_result: Dictionary = {},
	p_return_context: Dictionary = {},
	p_handoff_identity: Dictionary = {}
) -> void:
	session_id = p_session_id
	definition_id = p_definition_id
	task_id = p_task_id
	phase = p_phase
	seed = p_seed
	sequence = p_sequence
	build = VALUE.duplicate_value(p_build)
	facts = VALUE.duplicate_value(p_facts)
	request_refs = VALUE.duplicate_value(p_request_refs)
	settlement_refs = VALUE.duplicate_value(p_settlement_refs)
	objective_progress = VALUE.duplicate_value(p_objective_progress)
	result = VALUE.duplicate_value(p_result)
	return_context = VALUE.duplicate_value(p_return_context)
	handoff_identity = VALUE.duplicate_value(p_handoff_identity)

static func from_dict(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var stable := VALUE.persistence(value)
	if not stable.ok:
		return stable
	if value.schema_version != SCHEMA_VERSION:
		return {"ok": false, "code": "scene.state.schema", "error_zh": "SceneSessionState Schema版本不匹配。"}
	for identity in ["session_id", "definition_id", "task_id"]:
		if not VALUE.stable_id(value.get(identity)):
			return {"ok": false, "code": "scene.state.identity", "error_zh": "会话状态标识无效。"}
	if not PHASES.has(str(value.phase)):
		return {"ok": false, "code": "scene.state.phase", "error_zh": "会话阶段无效。"}
	var seed_check := VALUE.integer_field(value.seed, true)
	var sequence_check := VALUE.integer_field(value.sequence, false)
	if not seed_check.ok or not sequence_check.ok:
		return {"ok": false, "code": "scene.state.counters", "error_zh": "会话种子或序号无效。"}
	if typeof(value.build) != TYPE_DICTIONARY or typeof(value.facts) != TYPE_ARRAY:
		return {"ok": false, "code": "scene.state.build_facts", "error_zh": "会话构建结果与事实必须是纯字典/数组。"}
	var facts_value: Array = []
	var previous_sequence := 0
	var fact_ids := {}
	for raw_fact in value.facts:
		var fact_check := FACTS.from_dict(raw_fact)
		if not fact_check.ok:
			return {"ok": false, "code": "scene.state.fact_invalid", "error_zh": "会话状态包含非法ExecutionFacts。", "detail": fact_check}
		var fact: GMExecutionFacts = fact_check.value
		if fact.session_id != str(value.session_id):
			return {"ok": false, "code": "scene.state.fact_session", "error_zh": "事实不属于当前会话。"}
		if fact.sequence != previous_sequence + 1:
			return {"ok": false, "code": "scene.state.fact_sequence", "error_zh": "会话状态事实序号必须连续且从1开始。"}
		if fact_ids.has(fact.fact_id):
			return {"ok": false, "code": "scene.state.fact_duplicate", "error_zh": "会话状态不得包含重复fact_id。"}
		fact_ids[fact.fact_id] = true
		previous_sequence = fact.sequence
		facts_value.append(fact.to_dict())
	var request_check := _validate_request_refs(value.request_refs)
	if not request_check.ok:
		return request_check
	var settlement_check := _validate_settlement_refs(value.settlement_refs)
	if not settlement_check.ok:
		return settlement_check
	var progress_check := _validate_progress(value.objective_progress)
	if not progress_check.ok:
		return progress_check
	if typeof(value.result) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.state.result_type", "error_zh": "会话结果必须是字典。"}
	var result_value: Dictionary = {}
	if not value.result.is_empty():
		var result_check := RESULT.from_dict(value.result)
		if not result_check.ok:
			return {"ok": false, "code": "scene.state.result_invalid", "error_zh": "会话状态结果无效。", "detail": result_check}
		var parsed_result: GMTaskExecutionResult = result_check.value
		if parsed_result.session_id != str(value.session_id) or parsed_result.task_id != str(value.task_id):
			return {"ok": false, "code": "scene.state.result_identity", "error_zh": "会话结果身份不一致。"}
		result_value = parsed_result.to_dict()
	if TERMINAL_PHASES.has(str(value.phase)) and result_value.is_empty():
		return {"ok": false, "code": "scene.state.terminal_result_missing", "error_zh": "终止阶段必须保存执行结果。"}
	if not TERMINAL_PHASES.has(str(value.phase)) and not result_value.is_empty():
		return {"ok": false, "code": "scene.state.nonterminal_result", "error_zh": "非终止阶段不得提前保存终止结果。"}
	if previous_sequence != int(sequence_check.value):
		return {"ok": false, "code": "scene.state.counter_mismatch", "error_zh": "会话序号必须等于事实序号尾部。"}
	if typeof(value.return_context) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.state.return_type", "error_zh": "会话返回上下文必须是字典。"}
	if not value.return_context.is_empty():
		var return_check := RETURN_CONTEXT.from_dict(value.return_context)
		if not return_check.ok:
			return {"ok": false, "code": "scene.state.return_invalid", "error_zh": "会话返回上下文无效。"}
	var handoff_check := _validate_handoff_identity(value.handoff_identity)
	if not handoff_check.ok:
		return handoff_check
	var state := GMSceneSessionState.new(
		str(value.session_id), str(value.definition_id), str(value.task_id), str(value.phase), int(seed_check.value), int(sequence_check.value),
		VALUE.duplicate_value(value.build), facts_value, request_check.value, settlement_check.value, progress_check.value,
		result_value, value.return_context, handoff_check.value
	)
	return {"ok": true, "value": state}

static func _validate_request_refs(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {"ok": false, "code": "scene.state.request_refs_type", "error_zh": "请求引用必须是数组。"}
	var result: Array = []
	var request_ids := {}
	var idempotency_keys := {}
	for request in value:
		var checked := FACTS.validate_request_descriptor(request)
		if not checked.ok:
			return {"ok": false, "code": "scene.state.request_ref_invalid", "error_zh": "请求引用不是既有类型化领域请求。", "detail": checked}
		var normalized: Dictionary = checked.value
		if request_ids.has(str(normalized.request_id)) or idempotency_keys.has(str(normalized.idempotency_key)):
			return {"ok": false, "code": "scene.state.request_ref_duplicate", "error_zh": "请求引用的request_id或幂等键不得重复。"}
		request_ids[str(normalized.request_id)] = true
		idempotency_keys[str(normalized.idempotency_key)] = true
		result.append(normalized)
	return {"ok": true, "value": result}

static func _validate_settlement_refs(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {"ok": false, "code": "scene.state.settlements_type", "error_zh": "结算引用必须是数组。"}
	var result: Array = []
	var request_ids := {}
	var idempotency_keys := {}
	var fact_event_ids := {}
	var transaction_ids := {}
	for settlement in value:
		var fields := VALUE.exact_fields(settlement, SETTLEMENT_FIELDS)
		if not fields.ok:
			return {"ok": false, "code": "scene.state.settlement_shape", "error_zh": "结算引用字段集合必须精确匹配。", "detail": fields}
		if not VALUE.persistence(settlement).ok:
			return {"ok": false, "code": "scene.state.settlement_persistence", "error_zh": "结算引用必须是可持久化纯值。"}
		for field in ["request_id", "idempotency_key", "fact_event_id", "transaction_id"]:
			if not VALUE.stable_id(settlement.get(field), false):
				return {"ok": false, "code": "scene.state.settlement_identity", "error_zh": "结算引用包含非法稳定ID。", "field": field}
		if typeof(settlement.idempotent) != TYPE_BOOL:
			return {"ok": false, "code": "scene.state.settlement_type", "error_zh": "结算引用idempotent必须是布尔值。"}
		for pair in [[request_ids, settlement.request_id], [idempotency_keys, settlement.idempotency_key], [fact_event_ids, settlement.fact_event_id], [transaction_ids, settlement.transaction_id]]:
			var seen: Dictionary = pair[0]
			var key := str(pair[1])
			if seen.has(key):
				return {"ok": false, "code": "scene.state.settlement_duplicate", "error_zh": "结算引用的请求、事实或事务ID不得重复。"}
			seen[key] = true
		result.append({
			"request_id": str(settlement.request_id), "idempotency_key": str(settlement.idempotency_key),
			"fact_event_id": str(settlement.fact_event_id), "transaction_id": str(settlement.transaction_id),
			"idempotent": bool(settlement.idempotent)
		})
	return {"ok": true, "value": result}

static func _validate_handoff_identity(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.state.handoff_identity_type", "error_zh": "首次旅行交接身份必须是字典。"}
	if value.is_empty():
		return {"ok": true, "value": {}}
	var fields := VALUE.exact_fields(value, HANDOFF_IDENTITY_FIELDS)
	if not fields.ok:
		return {"ok": false, "code": "scene.state.handoff_identity_shape", "error_zh": "首次旅行交接身份字段集合无效。", "detail": fields}
	if not VALUE.stable_id(value.fingerprint, false) or typeof(value.handoff) != TYPE_DICTIONARY or not VALUE.persistence(value).ok:
		return {"ok": false, "code": "scene.state.handoff_identity_invalid", "error_zh": "首次旅行交接身份不是稳定纯值。"}
	var handoff_fields := VALUE.exact_fields(value.handoff, HANDOFF_FIELDS)
	if not handoff_fields.ok or str(value.handoff.schema) != "gm.movement.travel_handoff.v1":
		return {"ok": false, "code": "scene.state.handoff_identity_handoff", "error_zh": "首次旅行交接身份缺少完整P15 handoff。"}
	for field in HANDOFF_FIELDS.slice(1):
		if not VALUE.stable_id(value.handoff.get(field), false):
			return {"ok": false, "code": "scene.state.handoff_identity_field", "error_zh": "首次旅行交接身份包含非法字段。", "field": field}
	if str(value.handoff.owner_id) != str(value.handoff.actor_id):
		return {"ok": false, "code": "scene.state.handoff_identity_owner", "error_zh": "首次旅行交接身份的owner必须绑定actor。"}
	if str(value.fingerprint) != VALUE.digest(value.handoff):
		return {"ok": false, "code": "scene.state.handoff_identity_fingerprint", "error_zh": "首次旅行交接身份fingerprint不匹配。"}
	return {"ok": true, "value": {"fingerprint": str(value.fingerprint), "handoff": VALUE.duplicate_value(value.handoff)}}

static func _validate_pure_array(value: Variant, code_prefix: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {"ok": false, "code": code_prefix + ".type", "error_zh": "引用集合必须是数组。"}
	var result: Array = []
	for item in value:
		if typeof(item) != TYPE_DICTIONARY or not VALUE.persistence(item).ok:
			return {"ok": false, "code": code_prefix + ".item", "error_zh": "引用集合必须只包含可持久化字典。"}
		result.append(VALUE.duplicate_value(item))
	return {"ok": true, "value": result}

static func _validate_progress(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.state.progress_type", "error_zh": "目标进度必须是字典。"}
	var result := {}
	for key in value.keys():
		if not VALUE.stable_id(key):
			return {"ok": false, "code": "scene.state.progress_key", "error_zh": "目标进度键必须是稳定标识。"}
		var amount := VALUE.integer_field(value[key], false)
		if not amount.ok:
			return {"ok": false, "code": "scene.state.progress_value", "error_zh": "目标进度必须是非负整数。"}
		result[str(key)] = int(amount.value)
	return {"ok": true, "value": result}

static func from_json(text: String) -> Dictionary:
	var parsed := VALUE.parse_json(text)
	if not parsed.ok:
		return parsed
	return from_dict(parsed.value)

func validate() -> Dictionary:
	return GMSceneSessionState.from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"session_id": session_id,
		"definition_id": definition_id,
		"task_id": task_id,
		"phase": phase,
		"seed": seed,
		"sequence": sequence,
		"build": VALUE.duplicate_value(build),
		"facts": VALUE.duplicate_value(facts),
		"request_refs": VALUE.duplicate_value(request_refs),
		"settlement_refs": VALUE.duplicate_value(settlement_refs),
		"objective_progress": VALUE.duplicate_value(objective_progress),
		"result": VALUE.duplicate_value(result),
		"return_context": VALUE.duplicate_value(return_context),
		"handoff_identity": VALUE.duplicate_value(handoff_identity)
	}

func to_json() -> String:
	return VALUE.json_string(to_dict())

func fingerprint() -> String:
	return VALUE.digest(to_dict())
