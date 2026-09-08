class_name GMSemanticFeedbackRequest
extends RefCounted

const SCHEMA_VERSION := "gm.semantic_feedback_request.v1"
const FIELDS := ["schema_version", "feedback_id", "idempotency_key", "source_fact_id", "commit_package_id", "transaction_id", "causal_chain_id", "global_sequence", "source_type", "source_payload_digest", "sequence_id", "semantic_action_id", "target_ref", "direction", "anchor_id", "requested_logical_tick", "sequence_key", "attention_projection", "logic_unchanged", "domain_facts_written"]
const DIRECTIONS := ["down", "left", "right", "up", "down_left", "down_right", "up_left", "up_right"]
const SOURCE_TYPES := ["player", "ai", "organization", "world_event", "script", "duty_provider", "system"]

var schema_version := SCHEMA_VERSION
var feedback_id := ""
var idempotency_key := ""
var source_fact_id := ""
var commit_package_id := ""
var transaction_id := ""
var causal_chain_id := ""
var global_sequence := 0
var source_type := "system"
var source_payload_digest := ""
var sequence_id := ""
var semantic_action_id := "idle"
var target_ref := ""
var direction := "down"
var anchor_id := ""
var requested_logical_tick := 0
var sequence_key := ""
var attention_projection: Dictionary = {}
var logic_unchanged := true
var domain_facts_written := false

func to_dict() -> Dictionary:
	return {"schema_version": schema_version, "feedback_id": feedback_id, "idempotency_key": idempotency_key, "source_fact_id": source_fact_id, "commit_package_id": commit_package_id, "transaction_id": transaction_id, "causal_chain_id": causal_chain_id, "global_sequence": global_sequence, "source_type": source_type, "source_payload_digest": source_payload_digest, "sequence_id": sequence_id, "semantic_action_id": semantic_action_id, "target_ref": target_ref, "direction": direction, "anchor_id": anchor_id, "requested_logical_tick": requested_logical_tick, "sequence_key": sequence_key, "attention_projection": attention_projection.duplicate(true), "logic_unchanged": logic_unchanged, "domain_facts_written": domain_facts_written}

func fingerprint() -> String:
	return GMStableData.digest(to_dict())

func validate(json_boundary: bool = false) -> Dictionary:
	var row := to_dict()
	if not GMFeedbackValidation.exact(row, FIELDS):
		return GMFeedbackValidation.failure("feedback.request_shape_invalid", "SemanticFeedbackRequest字段集合必须精确匹配。")
	if typeof(schema_version) != TYPE_STRING or typeof(feedback_id) != TYPE_STRING or typeof(idempotency_key) != TYPE_STRING or typeof(source_fact_id) != TYPE_STRING or typeof(commit_package_id) != TYPE_STRING or typeof(transaction_id) != TYPE_STRING or typeof(causal_chain_id) != TYPE_STRING or typeof(global_sequence) != TYPE_INT or typeof(source_type) != TYPE_STRING or typeof(source_payload_digest) != TYPE_STRING or typeof(sequence_id) != TYPE_STRING or typeof(semantic_action_id) != TYPE_STRING or typeof(target_ref) != TYPE_STRING or typeof(direction) != TYPE_STRING or typeof(anchor_id) != TYPE_STRING or typeof(requested_logical_tick) != TYPE_INT or typeof(sequence_key) != TYPE_STRING or typeof(attention_projection) != TYPE_DICTIONARY or typeof(logic_unchanged) != TYPE_BOOL or typeof(domain_facts_written) != TYPE_BOOL:
		return GMFeedbackValidation.failure("feedback.request_variant_invalid", "SemanticFeedbackRequest原始Variant类型无效。")
	if schema_version != SCHEMA_VERSION or not GMFeedbackValidation.stable_id(feedback_id) or not GMFeedbackValidation.stable_id(idempotency_key) or not GMFeedbackValidation.stable_id(source_fact_id) or not GMFeedbackValidation.stable_id(commit_package_id) or not GMFeedbackValidation.stable_id(transaction_id) or not GMFeedbackValidation.stable_id(causal_chain_id) or not GMFeedbackValidation.stable_id(sequence_id) or not GMFeedbackValidation.stable_id(semantic_action_id) or not GMFeedbackValidation.stable_id(target_ref, true) or not GMFeedbackValidation.stable_id(anchor_id, true) or not GMFeedbackValidation.stable_id(sequence_key):
		return GMFeedbackValidation.failure("feedback.request_identity_invalid", "反馈请求包含空白、路径或不稳定身份。")
	if source_type not in SOURCE_TYPES or direction not in DIRECTIONS or not GMFeedbackValidation.is_digest(source_payload_digest) or not GMFeedbackValidation.bounded_integer(global_sequence, 1, GMFeedbackValidation.MAX_SAFE_INT, json_boundary) or not GMFeedbackValidation.bounded_integer(requested_logical_tick, 0, 600, json_boundary):
		return GMFeedbackValidation.failure("feedback.request_value_invalid", "反馈请求来源、方向、摘要或有界整数无效。")
	if typeof(logic_unchanged) != TYPE_BOOL or not logic_unchanged or typeof(domain_facts_written) != TYPE_BOOL or domain_facts_written:
		return GMFeedbackValidation.failure("feedback.request_write_flag_invalid", "P18请求必须明确保持逻辑不变且不写入领域事实。")
	if attention_projection.is_empty():
		return {"ok": true, "code": "feedback.request_valid", "value": row.duplicate(true)}
	var attention := GMAttentionBudget.validate_projection(attention_projection, json_boundary)
	if not attention.ok:
		return GMFeedbackValidation.failure("feedback.request_attention_invalid", "P17 Attention投影未通过只读校验。", attention)
	return {"ok": true, "code": "feedback.request_valid", "value": row.duplicate(true)}

static func from_dict(value: Variant, json_boundary: bool = false) -> GMSemanticFeedbackRequest:
	if not value is Dictionary:
		return null
	var row: Dictionary = value
	if not GMFeedbackValidation.exact(row, FIELDS):
		return null
	var raw_check := _validate_raw_row(row, json_boundary)
	if not raw_check.ok:
		return null
	var result := GMSemanticFeedbackRequest.new()
	result.schema_version = row.schema_version
	result.feedback_id = row.feedback_id
	result.idempotency_key = row.idempotency_key
	result.source_fact_id = row.source_fact_id
	result.commit_package_id = row.commit_package_id
	result.transaction_id = row.transaction_id
	result.causal_chain_id = row.causal_chain_id
	result.global_sequence = int(row.global_sequence) if json_boundary else row.global_sequence
	result.source_type = row.source_type
	result.source_payload_digest = row.source_payload_digest
	result.sequence_id = row.sequence_id
	result.semantic_action_id = row.semantic_action_id
	result.target_ref = row.target_ref
	result.direction = row.direction
	result.anchor_id = row.anchor_id
	result.requested_logical_tick = int(row.requested_logical_tick) if json_boundary else row.requested_logical_tick
	result.sequence_key = row.sequence_key
	result.attention_projection = row.attention_projection.duplicate(true)
	result.logic_unchanged = row.logic_unchanged
	result.domain_facts_written = row.domain_facts_written
	return result if result.validate().ok else null

static func _validate_raw_row(row: Dictionary, json_boundary: bool) -> Dictionary:
	var string_fields := ["schema_version", "feedback_id", "idempotency_key", "source_fact_id", "commit_package_id", "transaction_id", "causal_chain_id", "source_type", "source_payload_digest", "sequence_id", "semantic_action_id", "target_ref", "direction", "anchor_id", "sequence_key"]
	if not GMFeedbackValidation.exact_field_types(row, string_fields, ["global_sequence", "requested_logical_tick"], ["logic_unchanged", "domain_facts_written"], [], ["attention_projection"], json_boundary):
		return GMFeedbackValidation.failure("feedback.request_variant_invalid", "SemanticFeedbackRequest原始Variant类型不符合精确契约。")
	if row.schema_version != SCHEMA_VERSION or not GMFeedbackValidation.stable_id(row.feedback_id) or not GMFeedbackValidation.stable_id(row.idempotency_key) or not GMFeedbackValidation.stable_id(row.source_fact_id) or not GMFeedbackValidation.stable_id(row.commit_package_id) or not GMFeedbackValidation.stable_id(row.transaction_id) or not GMFeedbackValidation.stable_id(row.causal_chain_id) or not GMFeedbackValidation.stable_id(row.sequence_id) or not GMFeedbackValidation.stable_id(row.semantic_action_id) or not GMFeedbackValidation.stable_id(row.target_ref, true) or not GMFeedbackValidation.stable_id(row.anchor_id, true) or not GMFeedbackValidation.stable_id(row.sequence_key):
		return GMFeedbackValidation.failure("feedback.request_identity_invalid", "反馈请求包含空白、路径或不稳定身份。")
	if row.source_type not in SOURCE_TYPES or row.direction not in DIRECTIONS or not GMFeedbackValidation.is_digest(row.source_payload_digest) or not GMFeedbackValidation.bounded_integer(row.global_sequence, 1, GMFeedbackValidation.MAX_SAFE_INT, json_boundary) or not GMFeedbackValidation.bounded_integer(row.requested_logical_tick, 0, 600, json_boundary):
		return GMFeedbackValidation.failure("feedback.request_value_invalid", "反馈请求来源、方向、摘要或有界整数无效。")
	if not row.logic_unchanged or row.domain_facts_written:
		return GMFeedbackValidation.failure("feedback.request_write_flag_invalid", "P18请求必须明确保持逻辑不变且不写入领域事实。")
	if not row.attention_projection.is_empty() and not GMAttentionBudget.validate_projection(row.attention_projection, json_boundary).ok:
		return GMFeedbackValidation.failure("feedback.request_attention_invalid", "P17 Attention投影未通过只读校验。")
	return {"ok": true}
