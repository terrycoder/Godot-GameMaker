class_name GMFeedbackRestoreCatalog
extends RefCounted

## RETIRED P18 EXIT catalog.  It remains as a compatibility type only; no
## descriptor can be registered, resolved, or consumed by the live service.

const REFERENCE_SCHEMA := "gm.feedback.restore_descriptor.v2"
const REFERENCE_FIELDS := ["schema", "binding_id", "descriptor_digest"]

var owner: Object
var descriptors_by_binding: Dictionary = {}
var bindings_by_feedback: Dictionary = {}

func _init(p_owner: Object = null) -> void:
	owner = p_owner

func register_from_mapper_result(mapped: Dictionary, presenter: Object, cue_router: GMCueRouter, backends: Dictionary, attention_runtime: GMAgentPlannerRuntime = null) -> Dictionary:
	return _retired()
	# Historical catalog registration is intentionally unreachable after EXIT.
	var built := GMFeedbackRestoreDescriptor.from_mapper_result(mapped, presenter, cue_router, backends, attention_runtime)
	if not built.ok:
		return built
	var descriptor: GMFeedbackRestoreDescriptor = built.descriptor
	var binding: Variant = descriptors_by_binding.get(descriptor.binding_id, null)
	if binding != null:
		var existing: GMFeedbackRestoreDescriptor = binding
		if existing.descriptor_digest != descriptor.descriptor_digest:
			return _failure("feedback.restore_binding_conflict", "同一恢复binding不能对应不同的当前描述符。")
		return {"ok": true, "code": "feedback.restore_descriptor_idempotent", "descriptor": existing, "binding_id": existing.binding_id}
	var previous_binding_id: String = str(bindings_by_feedback.get(descriptor.feedback_id(), ""))
	if not previous_binding_id.is_empty() and previous_binding_id != descriptor.binding_id:
		return _failure("feedback.restore_feedback_binding_conflict", "同一反馈身份不能在当前catalog中绑定多个语义根。")
	descriptors_by_binding[descriptor.binding_id] = descriptor
	bindings_by_feedback[descriptor.feedback_id()] = descriptor.binding_id
	return {"ok": true, "code": "feedback.restore_descriptor_registered", "descriptor": descriptor, "binding_id": descriptor.binding_id}

func resolve(reference_or_binding: Variant, descriptor_digest: String = "") -> Dictionary:
	return _retired()
	# Historical catalog lookup is intentionally unreachable after EXIT.
	var binding_id := ""
	var digest := descriptor_digest
	if reference_or_binding is Dictionary:
		var reference: Dictionary = reference_or_binding
		if not GMFeedbackValidation.exact(reference, REFERENCE_FIELDS):
			return _failure("feedback.restore_reference_shape_invalid", "恢复引用必须精确包含schema、binding和descriptor摘要。")
		if str(reference.get("schema", "")) != REFERENCE_SCHEMA:
			return _failure("feedback.restore_reference_schema_invalid", "恢复引用Schema不属于当前运行时catalog。")
		binding_id = str(reference.get("binding_id", ""))
		digest = str(reference.get("descriptor_digest", ""))
	else:
		binding_id = str(reference_or_binding)
	if not GMFeedbackValidation.stable_id(binding_id) or not GMFeedbackValidation.is_digest(digest):
		return _failure("feedback.restore_reference_invalid", "恢复引用的binding或descriptor摘要无效。")
	var value: Variant = descriptors_by_binding.get(binding_id, null)
	if not value is GMFeedbackRestoreDescriptor:
		return _failure("feedback.restore_binding_missing", "当前trusted restore catalog中不存在该binding。", {"binding_id": binding_id})
	var descriptor: GMFeedbackRestoreDescriptor = value
	if descriptor.descriptor_digest != digest:
		return _failure("feedback.restore_binding_stale", "恢复binding对应的descriptor摘要已过期。", {"binding_id": binding_id})
	var authority_check := descriptor.validate_authority()
	if not authority_check.ok:
		return authority_check
	return {"ok": true, "code": "feedback.restore_descriptor_resolved", "descriptor": descriptor}

func resolve_request(request: GMSemanticFeedbackRequest, definition: GMFeedbackSequenceDefinition) -> Dictionary:
	return _retired()
	# Historical live/restore catalog lookup is intentionally unreachable after EXIT.
	if request == null or definition == null:
		return _failure("feedback.restore_request_missing", "live播放需要已注册的trusted restore descriptor。")
	for value in descriptors_by_binding.values():
		var descriptor: GMFeedbackRestoreDescriptor = value
		if descriptor.request != null and descriptor.request.to_dict() == request.to_dict() and descriptor.definition.digest() == definition.digest():
			var authority_check := descriptor.validate_authority()
			if not authority_check.ok:
				return authority_check
			return {"ok": true, "code": "feedback.restore_request_resolved", "descriptor": descriptor}
	return _failure("feedback.restore_descriptor_missing", "当前catalog没有由正式mapper build路径产生的对应恢复描述符。")

func reference_for_feedback(feedback_id: String) -> Dictionary:
	return {}

func count() -> int:
	return 0

func _retired() -> Dictionary:
	return {"ok": false, "code": "feedback.restore_api_retired", "reason_zh": "P18 restore catalog API已退役，不能注册、替换或解析表现状态。", "details": {"migration": "discard_presentation_only_state_and_rebuild_from_current_authority", "replayed": false, "logic_unchanged": true, "domain_facts_written": false}}

static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
