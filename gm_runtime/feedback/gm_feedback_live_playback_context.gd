class_name GMFeedbackLivePlaybackContext
extends RefCounted

## Ephemeral P18 context built only from a pure presentation plan.  It carries
## no mapper artifact, reader, store, authority package, descriptor, catalog,
## or journal reference.

const SCHEMA_VERSION := "gm.feedback.live_playback_context.v2"

var presentation_plan: GMFeedbackPresentationPlan
var request: GMFeedbackPresentationRequest
var definition: GMFeedbackSequenceDefinition

static func from_plan(value: Variant) -> Dictionary:
	if not value is GMFeedbackPresentationPlan:
		return _failure("feedback.presentation_plan_required", "P18只接受纯值PresentationPlan，不接受reader-bound mapper artifact。", {"required_api": "GMSemanticFeedbackMapper.build_presentation_plan_from_fact/build_presentation_plan_from_result -> GMFeedbackPlaybackService.play_plan"})
	var plan: GMFeedbackPresentationPlan = value
	var plan_check := plan.validate()
	if not plan_check.ok:
		return plan_check
	# Re-decode the already-validated value so the accepted context owns its
	# plan object and every nested attention/definition/metadata value.  Keeping
	# the caller's RefCounted plan here would let post-acceptance mutations alter
	# context.presentation_plan while request/definition stayed stale.
	var copied := GMFeedbackPresentationPlan.from_dict(plan.to_dict())
	if not copied.ok or not copied.plan is GMFeedbackPresentationPlan:
		return _failure("feedback.presentation_plan_copy_invalid", "PresentationPlan无法复制到P18自有的live上下文。", copied)
	var owned_plan: GMFeedbackPresentationPlan = copied.plan
	var owned_check := owned_plan.validate()
	if not owned_check.ok:
		return _failure("feedback.presentation_plan_copy_invalid", "P18自有PresentationPlan未通过一致性校验。", owned_check)
	var request := owned_plan.build_request()
	var definition := owned_plan.build_definition()
	if request == null or definition == null:
		return _failure("feedback.presentation_plan_invalid", "PresentationPlan无法形成严格的live表现值。")
	var context := GMFeedbackLivePlaybackContext.new()
	context.presentation_plan = owned_plan
	context.request = request
	context.definition = definition
	return {"ok": true, "code": "feedback.live_context_built", "context": context}

## Historical mapper artifacts are deliberately rejected at the P18 boundary;
## callers must ask the upstream mapper for a new pure-value plan.
static func from_mapped(_mapped: Variant, _p_attention_runtime: GMAgentPlannerRuntime = null) -> Dictionary:
	return _failure("feedback.presentation_plan_required", "旧reader-bound mapper artifact已退役；P18必须接收纯值PresentationPlan。", {"required_api": "GMSemanticFeedbackMapper.build_presentation_plan_from_fact/build_presentation_plan_from_result -> GMFeedbackPlaybackService.play_plan"})

func validate_registered_definition(registry: Dictionary) -> Dictionary:
	if definition == null or not registry.has(definition.sequence_id):
		return _failure("feedback.sequence_unregistered", "live反馈序列未注册。")
	var registered: GMFeedbackSequenceDefinition = registry[definition.sequence_id]
	if registered.digest() != definition.digest():
		return _failure("feedback.live_definition_stale", "PresentationPlan使用的反馈定义不是当前注册版本。")
	return {"ok": true, "code": "feedback.live_definition_valid"}

func request_fingerprint() -> String:
	return request.fingerprint() if request != null else ""

static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
