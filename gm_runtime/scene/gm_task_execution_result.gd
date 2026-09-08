class_name GMTaskExecutionResult
extends RefCounted

## 场景结束时交给 P16/调用者的结果值；不会自行完成任务或写入世界。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const RETURN_CONTEXT := preload("res://gm_runtime/scene/gm_scene_return_context.gd")

const SCHEMA_VERSION := "gm.task.execution_result.v1"
const SETTLEMENT_FIELDS: Array[String] = ["request_id", "idempotency_key", "fact_event_id", "transaction_id", "idempotent"]
const FIELDS: Array[String] = [
	"schema_version", "result_id", "session_id", "task_id", "status", "reason_code", "reason_zh",
	"completed_objective_ids", "pending_objective_ids", "fact_ids", "request_ids", "settlement_refs",
	"return_context", "idempotent"
]
const STATUSES: Array[String] = ["pending", "success", "partial_success", "failed", "extracted", "returned", "cancelled"]

var result_id: String
var session_id: String
var task_id: String
var status: String
var reason_code: String
var reason_zh: String
var completed_objective_ids: Array
var pending_objective_ids: Array
var fact_ids: Array
var request_ids: Array
var settlement_refs: Array
var return_context: Dictionary
var idempotent: bool

func _init(
	p_result_id: String = "",
	p_session_id: String = "",
	p_task_id: String = "",
	p_status: String = "pending",
	p_reason_code: String = "",
	p_reason_zh: String = "",
	p_completed_objective_ids: Array = [],
	p_pending_objective_ids: Array = [],
	p_fact_ids: Array = [],
	p_request_ids: Array = [],
	p_settlement_refs: Array = [],
	p_return_context: Dictionary = {},
	p_idempotent: bool = false
) -> void:
	result_id = p_result_id
	session_id = p_session_id
	task_id = p_task_id
	status = p_status
	reason_code = p_reason_code
	reason_zh = p_reason_zh
	completed_objective_ids = VALUE.duplicate_value(p_completed_objective_ids)
	pending_objective_ids = VALUE.duplicate_value(p_pending_objective_ids)
	fact_ids = VALUE.duplicate_value(p_fact_ids)
	request_ids = VALUE.duplicate_value(p_request_ids)
	settlement_refs = VALUE.duplicate_value(p_settlement_refs)
	return_context = VALUE.duplicate_value(p_return_context)
	idempotent = p_idempotent

static func from_dict(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var stable := VALUE.persistence(value)
	if not stable.ok:
		return stable
	if value.schema_version != SCHEMA_VERSION:
		return {"ok": false, "code": "scene.result.schema", "error_zh": "TaskExecutionResult Schema版本不匹配。"}
	for identity in ["result_id", "session_id", "task_id"]:
		if not VALUE.stable_id(value.get(identity)):
			return {"ok": false, "code": "scene.result.identity", "error_zh": "执行结果标识无效。"}
	if not STATUSES.has(str(value.status)) or not VALUE.stable_id(value.reason_code, true) or typeof(value.reason_zh) != TYPE_STRING:
		return {"ok": false, "code": "scene.result.status", "error_zh": "执行结果状态或原因无效。"}
	for ids_name in ["completed_objective_ids", "pending_objective_ids", "fact_ids", "request_ids"]:
		var ids := VALUE.string_array(value.get(ids_name), false)
		if not ids.ok:
			return {"ok": false, "code": "scene.result.%s" % ids_name, "error_zh": "执行结果ID列表无效。"}
		var seen_ids := {}
		for item in ids.value:
			if seen_ids.has(item):
				return {"ok": false, "code": "scene.result.%s_duplicate" % ids_name, "error_zh": "执行结果ID列表不得包含重复值。"}
			seen_ids[item] = true
	if typeof(value.settlement_refs) != TYPE_ARRAY:
		return {"ok": false, "code": "scene.result.settlements", "error_zh": "结算回执引用必须是数组。"}
	var settlement_request_ids := {}
	var settlement_keys := {}
	var settlement_fact_ids := {}
	var settlement_transaction_ids := {}
	for settlement in value.settlement_refs:
		var settlement_fields := VALUE.exact_fields(settlement, SETTLEMENT_FIELDS)
		if not settlement_fields.ok:
			return {"ok": false, "code": "scene.result.settlement_shape", "error_zh": "结算回执引用字段集合必须精确匹配。"}
		if not VALUE.persistence(settlement).ok:
			return {"ok": false, "code": "scene.result.settlement_persistence", "error_zh": "结算回执引用不可持久化。"}
		if typeof(settlement.idempotent) != TYPE_BOOL:
			return {"ok": false, "code": "scene.result.settlement_type", "error_zh": "结算回执idempotent必须是布尔值。"}
		for field in ["request_id", "idempotency_key", "fact_event_id", "transaction_id"]:
			if not VALUE.stable_id(settlement.get(field), false):
				return {"ok": false, "code": "scene.result.settlement_identity", "error_zh": "结算回执包含非法稳定ID。", "field": field}
		for pair in [[settlement_request_ids, settlement.request_id], [settlement_keys, settlement.idempotency_key], [settlement_fact_ids, settlement.fact_event_id], [settlement_transaction_ids, settlement.transaction_id]]:
			var seen: Dictionary = pair[0]
			var key := str(pair[1])
			if seen.has(key):
				return {"ok": false, "code": "scene.result.settlement_duplicate", "error_zh": "结算回执请求、事实或事务ID不得重复。"}
			seen[key] = true
	if typeof(value.return_context) != TYPE_DICTIONARY:
		return {"ok": false, "code": "scene.result.return_type", "error_zh": "执行结果返回上下文必须是字典。"}
	if not value.return_context.is_empty():
		var return_check := RETURN_CONTEXT.from_dict(value.return_context)
		if not return_check.ok:
			return {"ok": false, "code": "scene.result.return", "error_zh": "执行结果返回上下文无效。"}
	if typeof(value.idempotent) != TYPE_BOOL:
		return {"ok": false, "code": "scene.result.idempotent", "error_zh": "执行结果idempotent必须是布尔值。"}
	var result := GMTaskExecutionResult.new(
		str(value.result_id), str(value.session_id), str(value.task_id), str(value.status), str(value.reason_code), str(value.reason_zh),
		_value_array(value.completed_objective_ids), _value_array(value.pending_objective_ids), _value_array(value.fact_ids),
		_value_array(value.request_ids), _value_array(value.settlement_refs), value.return_context, bool(value.idempotent)
	)
	return {"ok": true, "value": result}

static func _value_array(value: Variant) -> Array:
	return VALUE.duplicate_value(value)

static func from_json(text: String) -> Dictionary:
	var parsed := VALUE.parse_json(text)
	if not parsed.ok:
		return parsed
	return from_dict(parsed.value)

func validate() -> Dictionary:
	return GMTaskExecutionResult.from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"result_id": result_id,
		"session_id": session_id,
		"task_id": task_id,
		"status": status,
		"reason_code": reason_code,
		"reason_zh": reason_zh,
		"completed_objective_ids": VALUE.duplicate_value(completed_objective_ids),
		"pending_objective_ids": VALUE.duplicate_value(pending_objective_ids),
		"fact_ids": VALUE.duplicate_value(fact_ids),
		"request_ids": VALUE.duplicate_value(request_ids),
		"settlement_refs": VALUE.duplicate_value(settlement_refs),
		"return_context": VALUE.duplicate_value(return_context),
		"idempotent": idempotent
	}

func to_json() -> String:
	return VALUE.json_string(to_dict())

func fingerprint() -> String:
	return VALUE.digest(to_dict())
