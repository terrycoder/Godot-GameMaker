class_name GMFeedbackPresentationRequest
extends RefCounted

## P18's runtime request is a presentation value, not an authority proof.
## Upstream mapper metadata such as commit packages, transactions, causal
## chains and payload digests is intentionally absent from this contract.

const SCHEMA_VERSION := "gm.feedback.presentation_request.v1"
const FIELDS := ["schema_version", "feedback_id", "idempotency_key", "source_fact_id", "sequence_id", "semantic_action_id", "target_ref", "direction", "anchor_id", "requested_logical_tick", "sequence_key", "attention_projection", "logic_unchanged", "domain_facts_written"]
const DIRECTIONS := ["down", "left", "right", "up", "down_left", "down_right", "up_left", "up_right"]

var schema_version := SCHEMA_VERSION
var feedback_id := ""
var idempotency_key := ""
## Diagnostic correlation only.  P18 never verifies or treats this as proof.
var source_fact_id := ""
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
	return {"schema_version": schema_version, "feedback_id": feedback_id, "idempotency_key": idempotency_key, "source_fact_id": source_fact_id, "sequence_id": sequence_id, "semantic_action_id": semantic_action_id, "target_ref": target_ref, "direction": direction, "anchor_id": anchor_id, "requested_logical_tick": requested_logical_tick, "sequence_key": sequence_key, "attention_projection": attention_projection.duplicate(true), "logic_unchanged": logic_unchanged, "domain_facts_written": domain_facts_written}

func fingerprint() -> String:
	return GMStableData.digest(to_dict())

func validate() -> Dictionary:
	var row := to_dict()
	if not GMFeedbackValidation.exact(row, FIELDS):
		return GMFeedbackValidation.failure("feedback.presentation_request_shape_invalid", "PresentationRequest字段集合必须精确匹配。")
	if typeof(schema_version) != TYPE_STRING or typeof(feedback_id) != TYPE_STRING or typeof(idempotency_key) != TYPE_STRING or typeof(source_fact_id) != TYPE_STRING or typeof(sequence_id) != TYPE_STRING or typeof(semantic_action_id) != TYPE_STRING or typeof(target_ref) != TYPE_STRING or typeof(direction) != TYPE_STRING or typeof(anchor_id) != TYPE_STRING or typeof(requested_logical_tick) != TYPE_INT or typeof(sequence_key) != TYPE_STRING or typeof(attention_projection) != TYPE_DICTIONARY or typeof(logic_unchanged) != TYPE_BOOL or typeof(domain_facts_written) != TYPE_BOOL:
		return GMFeedbackValidation.failure("feedback.presentation_request_variant_invalid", "PresentationRequest原始Variant类型无效。")
	if schema_version != SCHEMA_VERSION or not GMFeedbackValidation.stable_id(feedback_id) or not GMFeedbackValidation.stable_id(idempotency_key) or not GMFeedbackValidation.stable_id(source_fact_id, true) or not GMFeedbackValidation.stable_id(sequence_id) or not GMFeedbackValidation.stable_id(semantic_action_id) or not GMFeedbackValidation.stable_id(target_ref, true) or direction not in DIRECTIONS or not GMFeedbackValidation.stable_id(anchor_id, true) or not GMFeedbackValidation.stable_id(sequence_key):
		return GMFeedbackValidation.failure("feedback.presentation_request_identity_invalid", "PresentationRequest包含空白、路径或不稳定身份。")
	if not GMFeedbackValidation.bounded_integer(requested_logical_tick, 0, 600) or not logic_unchanged or domain_facts_written:
		return GMFeedbackValidation.failure("feedback.presentation_request_value_invalid", "PresentationRequest的方向、时钟或只读标志无效。")
	if not attention_projection.is_empty():
		var attention := GMAttentionBudget.validate_projection(attention_projection)
		if not attention.ok:
			return GMFeedbackValidation.failure("feedback.presentation_request_attention_invalid", "PresentationRequest的Attention投影未通过只读校验。", attention)
	return {"ok": true, "code": "feedback.presentation_request_valid", "value": row.duplicate(true)}

static func from_dict(value: Variant) -> GMFeedbackPresentationRequest:
	if not value is Dictionary:
		return null
	var row: Dictionary = value
	if not GMFeedbackValidation.exact(row, FIELDS):
		return null
	var result := GMFeedbackPresentationRequest.new()
	result.schema_version = row.schema_version
	result.feedback_id = row.feedback_id
	result.idempotency_key = row.idempotency_key
	result.source_fact_id = row.source_fact_id
	result.sequence_id = row.sequence_id
	result.semantic_action_id = row.semantic_action_id
	result.target_ref = row.target_ref
	result.direction = row.direction
	result.anchor_id = row.anchor_id
	result.requested_logical_tick = row.requested_logical_tick
	result.sequence_key = row.sequence_key
	result.attention_projection = row.attention_projection.duplicate(true)
	result.logic_unchanged = row.logic_unchanged
	result.domain_facts_written = row.domain_facts_written
	return result if result.validate().ok else null
