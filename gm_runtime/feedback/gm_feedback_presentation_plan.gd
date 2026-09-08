class_name GMFeedbackPresentationPlan
extends RefCounted

## Pure-value handoff from the upstream mapper to P18.  The plan intentionally
## contains no GMFeedbackAuthorityReader, FactEventStore, descriptor, catalog,
## journal, backend capability or other authority object reference.

const SCHEMA_VERSION := "gm.feedback.presentation_plan.v1"
const FIELDS := ["schema_version", "authoritative", "persistence", "domain_facts_written", "feedback_id", "idempotency_key", "source_fact_id", "sequence_id", "semantic_action_id", "target_ref", "direction", "anchor_id", "requested_logical_tick", "sequence_key", "attention_projection", "sequence_digest", "definition"]

var _value: Dictionary = {}

static func from_mapped(mapped: Variant) -> Dictionary:
	if not mapped is Dictionary:
		return _failure("feedback.presentation_plan_required", "P18只接受由当前mapper转换出的纯值PresentationPlan。")
	var artifact_value: Variant = mapped.get("mapper_build_artifact", null)
	if not artifact_value is GMFeedbackMapperBuildArtifact:
		return _failure("feedback.presentation_plan_required", "P18只接受由当前mapper转换出的纯值PresentationPlan。", {"required_api": "GMSemanticFeedbackMapper.build_presentation_plan_from_fact/build_presentation_plan_from_result -> GMFeedbackPlaybackService.play_plan"})
	var artifact: GMFeedbackMapperBuildArtifact = artifact_value
	var artifact_check := artifact.validate_for(mapped, artifact.source_mapper)
	if not artifact_check.ok:
		return artifact_check
	var request_value: Variant = mapped.get("request", null)
	var definition_value: Variant = mapped.get("definition", null)
	if not request_value is GMSemanticFeedbackRequest or not definition_value is GMFeedbackSequenceDefinition:
		return _failure("feedback.presentation_plan_source_invalid", "当前mapper产物缺少可复制的Presentation值。")
	var request: GMSemanticFeedbackRequest = request_value
	var definition: GMFeedbackSequenceDefinition = definition_value
	var plan := GMFeedbackPresentationPlan.new()
	plan._value = {
		"schema_version": SCHEMA_VERSION,
		"authoritative": false,
		"persistence": "none",
		"domain_facts_written": false,
		"feedback_id": request.feedback_id,
		"idempotency_key": request.idempotency_key,
		"source_fact_id": request.source_fact_id,
		"sequence_id": request.sequence_id,
		"semantic_action_id": request.semantic_action_id,
		"target_ref": request.target_ref,
		"direction": request.direction,
		"anchor_id": request.anchor_id,
		"requested_logical_tick": request.requested_logical_tick,
		"sequence_key": request.sequence_key,
		"attention_projection": request.attention_projection.duplicate(true),
		"sequence_digest": definition.digest(),
		"definition": definition.to_dict().duplicate(true)
	}
	var plan_check := plan.validate()
	if not plan_check.ok:
		return plan_check
	return {"ok": true, "code": "feedback.presentation_plan_built", "plan": plan}

func to_dict() -> Dictionary:
	return _value.duplicate(true)

## Decode only a pure-value envelope.  This never rehydrates an authority
## reader, store, descriptor, catalog, journal or backend capability.
static func from_dict(value: Variant, json_boundary: bool = false) -> Dictionary:
	if not value is Dictionary:
		return _failure("feedback.presentation_plan_shape_invalid", "PresentationPlan必须是纯值Dictionary。")
	var plan := GMFeedbackPresentationPlan.new()
	plan._value = value.duplicate(true)
	var checked := plan.validate(json_boundary)
	if not checked.ok:
		return checked
	if json_boundary:
		plan._value.requested_logical_tick = int(plan._value.requested_logical_tick)
		if not plan._value.attention_projection.is_empty():
			plan._value.attention_projection.capacity = int(plan._value.attention_projection.capacity)
			plan._value.attention_projection.candidate_count = int(plan._value.attention_projection.candidate_count)
		var normalized_definition := GMFeedbackSequenceDefinition.from_dict(plan._value.definition, true)
		if normalized_definition == null:
			return _failure("feedback.presentation_plan_definition_invalid", "PresentationPlan的JSON序列定义无法规范化。")
		plan._value.definition = normalized_definition.to_dict()
	var native_checked := plan.validate()
	return {"ok": true, "code": "feedback.presentation_plan_decoded", "plan": plan} if native_checked.ok else native_checked

func validate(json_boundary: bool = false) -> Dictionary:
	if not GMFeedbackValidation.exact(_value, FIELDS):
		return _failure("feedback.presentation_plan_shape_invalid", "PresentationPlan字段集合必须精确匹配。")
	var tick_type_valid := typeof(_value.requested_logical_tick) == TYPE_INT or (json_boundary and typeof(_value.requested_logical_tick) == TYPE_FLOAT)
	if typeof(_value.schema_version) != TYPE_STRING or typeof(_value.authoritative) != TYPE_BOOL or typeof(_value.persistence) != TYPE_STRING or typeof(_value.domain_facts_written) != TYPE_BOOL or typeof(_value.feedback_id) != TYPE_STRING or typeof(_value.idempotency_key) != TYPE_STRING or typeof(_value.source_fact_id) != TYPE_STRING or typeof(_value.sequence_id) != TYPE_STRING or typeof(_value.semantic_action_id) != TYPE_STRING or typeof(_value.target_ref) != TYPE_STRING or typeof(_value.direction) != TYPE_STRING or typeof(_value.anchor_id) != TYPE_STRING or not tick_type_valid or typeof(_value.sequence_key) != TYPE_STRING or typeof(_value.attention_projection) != TYPE_DICTIONARY or typeof(_value.sequence_digest) != TYPE_STRING or typeof(_value.definition) != TYPE_DICTIONARY:
		return _failure("feedback.presentation_plan_variant_invalid", "PresentationPlan原始Variant类型无效。")
	if _value.schema_version != SCHEMA_VERSION or _value.authoritative != false or _value.persistence != "none" or _value.domain_facts_written != false:
		return _failure("feedback.presentation_plan_flags_invalid", "PresentationPlan必须明确标记为非权威、非持久化且不写入领域事实。")
	if not GMFeedbackValidation.stable_id(_value.feedback_id) or not GMFeedbackValidation.stable_id(_value.idempotency_key) or not GMFeedbackValidation.stable_id(_value.source_fact_id, true) or not GMFeedbackValidation.stable_id(_value.sequence_id) or not GMFeedbackValidation.stable_id(_value.semantic_action_id) or not GMFeedbackValidation.stable_id(_value.target_ref, true) or _value.direction not in GMFeedbackPresentationRequest.DIRECTIONS or not GMFeedbackValidation.stable_id(_value.anchor_id, true) or not GMFeedbackValidation.bounded_integer(_value.requested_logical_tick, 0, 600, json_boundary) or not GMFeedbackValidation.stable_id(_value.sequence_key) or not GMFeedbackValidation.is_digest(_value.sequence_digest):
		return _failure("feedback.presentation_plan_identity_invalid", "PresentationPlan包含空白、路径或不稳定展示身份。")
	if not _value.attention_projection.is_empty():
		var attention := GMAttentionBudget.validate_projection(_value.attention_projection, json_boundary)
		if not attention.ok:
			return _failure("feedback.presentation_plan_attention_invalid", "PresentationPlan的Attention投影未通过只读校验。", attention)
	var definition := GMFeedbackSequenceDefinition.from_dict(_value.definition, json_boundary)
	if definition == null or definition.sequence_id != _value.sequence_id or definition.digest() != _value.sequence_digest:
		return _failure("feedback.presentation_plan_definition_invalid", "PresentationPlan的展示序列定义或摘要无效。")
	return {"ok": true, "code": "feedback.presentation_plan_valid", "value": to_dict()}

func build_request() -> GMFeedbackPresentationRequest:
	if not validate().ok:
		return null
	var request := GMFeedbackPresentationRequest.new()
	request.feedback_id = _value.feedback_id
	request.idempotency_key = _value.idempotency_key
	request.source_fact_id = _value.source_fact_id
	request.sequence_id = _value.sequence_id
	request.semantic_action_id = _value.semantic_action_id
	request.target_ref = _value.target_ref
	request.direction = _value.direction
	request.anchor_id = _value.anchor_id
	request.requested_logical_tick = int(_value.requested_logical_tick)
	request.sequence_key = _value.sequence_key
	request.attention_projection = _value.attention_projection.duplicate(true)
	request.logic_unchanged = true
	request.domain_facts_written = false
	return request if request.validate().ok else null

func build_definition() -> GMFeedbackSequenceDefinition:
	if not validate().ok:
		return null
	return GMFeedbackSequenceDefinition.from_dict(_value.definition)

static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
