class_name GMExecutionFacts
extends RefCounted

## 场景侧事实。它是给既有领域请求/结算管线的输入值，不是 GMFactEvent 的替代品。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const INTERACTION_REQUEST := preload("res://gm_runtime/p21/gm_interaction_request.gd")

const SCHEMA_VERSION := "gm.execution.facts.v1"
const REQUEST_KINDS: Array[String] = ["ability_activation", "interaction_request"]
const ABILITY_REQUEST_FIELDS: Array[String] = ["request_id", "ability_id", "ability_tag", "source", "event_data", "schedule_context", "target_data", "idempotency_key"]
const FIELDS: Array[String] = [
	"schema_version", "fact_id", "session_id", "sequence", "kind", "actor_ref", "target_ref",
	"outcome", "contributions", "domain_requests", "tags", "metadata"
]

var fact_id: String
var session_id: String
var sequence: int
var kind: String
var actor_ref: Dictionary
var target_ref: Dictionary
var outcome: Dictionary
var contributions: Dictionary
var domain_requests: Array
var tags: Array
var metadata: Dictionary

func _init(
	p_fact_id: String = "",
	p_session_id: String = "",
	p_sequence: int = 0,
	p_kind: String = "observation",
	p_actor_ref: Dictionary = {},
	p_target_ref: Dictionary = {},
	p_outcome: Dictionary = {},
	p_contributions: Dictionary = {},
	p_domain_requests: Array = [],
	p_tags: Array = [],
	p_metadata: Dictionary = {}
) -> void:
	fact_id = p_fact_id
	session_id = p_session_id
	sequence = p_sequence
	kind = p_kind
	actor_ref = VALUE.duplicate_value(p_actor_ref)
	target_ref = VALUE.duplicate_value(p_target_ref)
	outcome = VALUE.duplicate_value(p_outcome)
	contributions = VALUE.duplicate_value(p_contributions)
	domain_requests = VALUE.duplicate_value(p_domain_requests)
	tags = VALUE.duplicate_value(p_tags)
	metadata = VALUE.duplicate_value(p_metadata)

static func from_dict(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var stable := VALUE.persistence(value)
	if not stable.ok:
		return stable
	if value.schema_version != SCHEMA_VERSION:
		return {"ok": false, "code": "scene.facts.schema", "error_zh": "ExecutionFacts Schema版本不匹配。"}
	if not VALUE.stable_id(value.fact_id) or not VALUE.stable_id(value.session_id) or not VALUE.stable_id(value.kind):
		return {"ok": false, "code": "scene.facts.identity", "error_zh": "ExecutionFacts标识或kind无效。"}
	var sequence_check := VALUE.integer_field(value.sequence, false)
	if not sequence_check.ok:
		return {"ok": false, "code": "scene.facts.sequence", "error_zh": "ExecutionFacts sequence必须是非负整数。"}
	for ref_name in ["actor_ref", "target_ref"]:
		var ref_value = value.get(ref_name)
		var ref_check := VALUE.semantic_ref(ref_value, true)
		if not ref_check.ok:
			return {"ok": false, "code": "scene.facts.ref", "error_zh": "ExecutionFacts引用无效。", "detail": ref_check}
	for dict_name in ["outcome", "contributions", "metadata"]:
		if typeof(value.get(dict_name)) != TYPE_DICTIONARY:
			return {"ok": false, "code": "scene.facts.%s_type" % dict_name, "error_zh": "ExecutionFacts的%s必须是字典。" % dict_name}
	var contribution_check := _validate_contributions(value.contributions)
	if not contribution_check.ok:
		return contribution_check
	var request_check := _validate_domain_requests(value.domain_requests)
	if not request_check.ok:
		return request_check
	var tags_check := VALUE.string_array(value.tags, true)
	if not tags_check.ok:
		return {"ok": false, "code": "scene.facts.tags", "error_zh": "ExecutionFacts tags无效。"}
	if _has_direct_write_marker(value.metadata):
		return {"ok": false, "code": "scene.facts.direct_write", "error_zh": "ExecutionFacts不得声明场景直接写入领域状态。"}
	var facts := GMExecutionFacts.new(
		str(value.fact_id), str(value.session_id), int(sequence_check.value), str(value.kind), value.actor_ref,
		value.target_ref, value.outcome, contribution_check.value, request_check.value, tags_check.value, value.metadata
	)
	return {"ok": true, "value": facts}

static func from_json(text: String) -> Dictionary:
	var parsed := VALUE.parse_json(text)
	if not parsed.ok:
		return parsed
	return from_dict(parsed.value)

static func _validate_contributions(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.facts.contributions_type", "error_zh": "contributions必须是字典。"}
	var result := {}
	for key in value.keys():
		if not VALUE.stable_id(key):
			return {"ok": false, "code": "scene.facts.contribution_key", "error_zh": "贡献字段必须是稳定标识。"}
		var amount := VALUE.integer_field(value[key], false)
		if not amount.ok:
			return {"ok": false, "code": "scene.facts.contribution_value", "error_zh": "贡献值必须是非负整数。"}
		result[str(key)] = int(amount.value)
	return {"ok": true, "value": result}

static func _validate_domain_requests(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {"ok": false, "code": "scene.facts.requests_type", "error_zh": "domain_requests必须是数组。"}
	var result: Array = []
	var request_ids := {}
	var idempotency_keys := {}
	for request in value:
		var checked := validate_request_descriptor(request)
		if not checked.ok:
			return checked
		var normalized: Dictionary = checked.value
		if request_ids.has(str(normalized.request_id)) or idempotency_keys.has(str(normalized.idempotency_key)):
			return {"ok": false, "code": "scene.facts.request_duplicate", "error_zh": "同一ExecutionFacts不得重复声明request_id或幂等键。"}
		request_ids[str(normalized.request_id)] = true
		idempotency_keys[str(normalized.idempotency_key)] = true
		result.append(normalized)
	return {"ok": true, "value": result}

static func validate_request_descriptor(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, ["request_kind", "request_id", "idempotency_key", "request"])
	if not fields.ok:
		return {"ok": false, "code": "scene.facts.request_shape", "error_zh": "领域请求包字段不完整。", "detail": fields}
	if typeof(value.request_kind) != TYPE_STRING or not REQUEST_KINDS.has(str(value.request_kind)):
		return {"ok": false, "code": "scene.facts.request_type_unregistered", "error_zh": "领域请求包必须来自已注册的既有请求类型。"}
	if not VALUE.stable_id(value.request_id, false) or not VALUE.stable_id(value.idempotency_key, false):
		return {"ok": false, "code": "scene.facts.request_identity", "error_zh": "领域请求包标识无效。"}
	if typeof(value.request) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.facts.request_value", "error_zh": "领域请求包必须保存既有请求的纯值序列化。"}
	if str(value.request_kind) == "ability_activation":
		var ability_fields := VALUE.exact_fields(value.request, ABILITY_REQUEST_FIELDS)
		if not ability_fields.ok:
			return {"ok": false, "code": "scene.facts.ability_request_shape", "error_zh": "GMAbilityActivationRequest序列化字段集合无效。", "detail": ability_fields}
		for field in ["request_id", "ability_id", "ability_tag", "source", "idempotency_key"]:
			if typeof(value.request.get(field)) != TYPE_STRING:
				return {"ok": false, "code": "scene.facts.ability_request_type", "error_zh": "GMAbilityActivationRequest字符串字段类型无效。", "field": field}
		for field in ["event_data", "schedule_context", "target_data"]:
			if typeof(value.request.get(field)) != TYPE_DICTIONARY or not VALUE.persistence(value.request.get(field)).ok:
				return {"ok": false, "code": "scene.facts.ability_request_payload", "error_zh": "GMAbilityActivationRequest载荷必须是可持久化纯字典。", "field": field}
		if str(value.request.request_id) != str(value.request_id):
			return {"ok": false, "code": "scene.facts.request_identity_mismatch", "error_zh": "领域请求包request_id与既有请求不一致。"}
		var nested_key := str(value.request.idempotency_key)
		var effective_key := nested_key if not nested_key.is_empty() else str(value.request_id)
		if effective_key != str(value.idempotency_key):
			return {"ok": false, "code": "scene.facts.request_key_mismatch", "error_zh": "领域请求包幂等键与既有请求不一致。"}
	else:
		var interaction_check := INTERACTION_REQUEST.from_dict(value.request)
		if not interaction_check.ok:
			return {"ok": false, "code": "scene.facts.interaction_request_invalid", "error_zh": "P21 InteractionRequest未通过既有严格解析器。", "detail": interaction_check}
		var interaction = interaction_check.request
		if str(interaction.request_id) != str(value.request_id) or str(interaction.idempotency_key) != str(value.idempotency_key):
			return {"ok": false, "code": "scene.facts.request_identity_mismatch", "error_zh": "领域请求包身份与既有InteractionRequest不一致。"}
	return {
		"ok": true,
		"value": {
			"request_kind": str(value.request_kind), "request_id": str(value.request_id),
			"idempotency_key": str(value.idempotency_key), "request": VALUE.duplicate_value(value.request)
		}
	}

static func _has_direct_write_marker(value: Dictionary) -> bool:
	for key in ["direct_world_write", "direct_task_write", "direct_store_write", "scene_tree_mutation"]:
		if value.has(key) and bool(value[key]):
			return true
	return false

func validate() -> Dictionary:
	return GMExecutionFacts.from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"fact_id": fact_id,
		"session_id": session_id,
		"sequence": sequence,
		"kind": kind,
		"actor_ref": VALUE.duplicate_value(actor_ref),
		"target_ref": VALUE.duplicate_value(target_ref),
		"outcome": VALUE.duplicate_value(outcome),
		"contributions": VALUE.duplicate_value(contributions),
		"domain_requests": VALUE.duplicate_value(domain_requests),
		"tags": VALUE.duplicate_value(tags),
		"metadata": VALUE.duplicate_value(metadata)
	}

func to_json() -> String:
	return VALUE.json_string(to_dict())

func fingerprint() -> String:
	return VALUE.digest(to_dict())
