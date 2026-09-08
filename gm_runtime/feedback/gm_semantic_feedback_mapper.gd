class_name GMSemanticFeedbackMapper
extends RefCounted

## Upstream-only mapper: converts an authoritative committed package into
## presentation values.  P18 receives only the pure-value plan produced by the
## build_presentation_plan_* methods; no reader/store capability crosses that
## boundary and domain payload is never copied into the plan.

var authority_reader: GMFeedbackAuthorityReader
var attention_runtime: GMAgentPlannerRuntime

func _init(p_authority_reader: GMFeedbackAuthorityReader = null, p_attention_runtime: GMAgentPlannerRuntime = null) -> void:
	authority_reader = p_authority_reader
	attention_runtime = p_attention_runtime

## Derive every persisted presentation identity from the current authoritative
## package, Fact, semantic action, and current sequence definition.  Snapshot
## restore calls this same helper instead of trusting format-valid caller data.
static func canonical_identity(authority: Dictionary, definition: GMFeedbackSequenceDefinition, target: String, direction: String, anchor: String, semantic_action_id: String) -> Dictionary:
	var fact_value: Variant = authority.get("fact", null)
	var package_value: Variant = authority.get("package", null)
	if not fact_value is GMFactEvent or not package_value is Dictionary or package_value.is_empty() or definition == null:
		return {"ok": false, "code": "feedback.canonical_identity_authority_missing", "reason_zh": "反馈身份派生需要当前权威Fact、提交包和序列定义。"}
	if not GMFeedbackValidation.stable_id(target, true) or direction not in GMSemanticFeedbackRequest.DIRECTIONS or not GMFeedbackValidation.stable_id(anchor, true) or not GMFeedbackValidation.stable_id(semantic_action_id):
		return {"ok": false, "code": "feedback.canonical_identity_input_invalid", "reason_zh": "反馈身份派生输入不是受支持的稳定值。"}
	var fact: GMFactEvent = fact_value
	var package: Dictionary = package_value
	var identity_material := {
		"authority_package_digest": GMStableData.digest(package),
		"source_fact_id": str(fact.event_id),
		"commit_package_id": str(authority.get("commit_package_id", "")),
		"transaction_id": str(fact.transaction_id),
		"causal_chain_id": str(fact.causal_chain_id),
		"global_sequence": int(fact.sequence),
		"source_type": str(authority.get("source_type", "")),
		"source_payload_digest": str(authority.get("source_payload_digest", "")),
		"sequence_id": str(definition.sequence_id),
		"sequence_digest": definition.digest(),
		"target_ref": target,
		"direction": direction,
		"anchor_id": anchor,
		"semantic_action_id": semantic_action_id
	}
	var digest := GMStableData.digest(identity_material)
	var sequence_key_digest := GMStableData.digest({"identity_digest": digest, "kind": "sequence_key"})
	return {
		"ok": true,
		"feedback_id": "gm.feedback.%s" % digest,
		"idempotency_key": "gm.feedback.play.%s" % digest,
		"sequence_key": "gm.feedback.sequence-key.%s" % sequence_key_digest,
		"receipt_id": "gm.presentation.receipt.gm.feedback.%s" % digest,
                "digest": digest
        }

## Rebuild the complete request projection used by restore.  The caller may
## supply only the public semantic inputs (target, direction, anchor and the
## already validated current Attention projection); every persisted request
## field is derived again from the current authority or sequence definition.
static func canonical_live_projection(authority: Dictionary, definition: GMFeedbackSequenceDefinition, target: String, direction: String, anchor: String, attention_projection: Dictionary = {}) -> Dictionary:
	var fact_value: Variant = authority.get("fact", null)
	if not fact_value is GMFactEvent or definition == null:
		return {"ok": false, "code": "feedback.canonical_restore_authority_missing", "reason_zh": "恢复投影需要当前权威Fact和序列定义。"}
	var fact: GMFactEvent = fact_value
	var semantic_action := semantic_action_for_fact(fact)
	var identity := canonical_identity(authority, definition, target, direction, anchor, semantic_action)
	if not identity.ok:
		return identity
	var request_fields := {
		"schema_version": GMSemanticFeedbackRequest.SCHEMA_VERSION,
		"feedback_id": identity.feedback_id,
		"idempotency_key": identity.idempotency_key,
		"source_fact_id": fact.event_id,
		"commit_package_id": str(authority.get("commit_package_id", "")),
		"transaction_id": fact.transaction_id,
		"causal_chain_id": fact.causal_chain_id,
		"global_sequence": fact.sequence,
		"source_type": str(authority.get("source_type", "")),
		"source_payload_digest": str(authority.get("source_payload_digest", "")),
		"sequence_id": definition.sequence_id,
		"semantic_action_id": semantic_action,
		"target_ref": target,
		"direction": direction,
		"anchor_id": anchor,
		"requested_logical_tick": requested_tick_for_fact(fact),
		"sequence_key": identity.sequence_key,
		"attention_projection": attention_projection.duplicate(true),
		"logic_unchanged": true,
		"domain_facts_written": false
	}
	return {"ok": true, "request_fields": request_fields, "receipt_id": identity.receipt_id, "identity": identity, "sequence_digest": definition.digest()}

## Compatibility name retained only for historical fixtures.  It is a live
## mapper projection helper; it never restores or accepts persisted state.
static func canonical_restore_projection(authority: Dictionary, definition: GMFeedbackSequenceDefinition, target: String, direction: String, anchor: String, attention_projection: Dictionary = {}) -> Dictionary:
	return canonical_live_projection(authority, definition, target, direction, anchor, attention_projection)

func build_from_fact(event_id: String, target_override: String = "", direction_override: String = "down", anchor_override: String = "", attention_override: Dictionary = {}) -> Dictionary:
	if authority_reader == null:
		return _failure("feedback.mapper_authority_missing", "反馈映射器未连接权威读取器。")
	var authority := authority_reader.read_fact(event_id)
	if not authority.ok:
		return authority
	return _build(authority, target_override, direction_override, anchor_override, attention_override)

func build_from_result(result: Variant, target_override: String = "", direction_override: String = "down", anchor_override: String = "", attention_override: Dictionary = {}) -> Dictionary:
	if authority_reader == null:
		return _failure("feedback.mapper_authority_missing", "反馈映射器未连接权威读取器。")
	var authority := authority_reader.read_result(result)
	if not authority.ok:
		return authority
	return _build(authority, target_override, direction_override, anchor_override, attention_override)

## Upstream-only handoff: the mapper verifies current authority, then drops
## every reader/store/authority reference while creating the pure P18 plan.
func build_presentation_plan_from_fact(event_id: String, target_override: String = "", direction_override: String = "down", anchor_override: String = "", attention_override: Dictionary = {}) -> Dictionary:
	var mapped := build_from_fact(event_id, target_override, direction_override, anchor_override, attention_override)
	if not mapped.ok:
		return mapped
	return GMFeedbackPresentationPlan.from_mapped(mapped)

func build_presentation_plan_from_result(result: Variant, target_override: String = "", direction_override: String = "down", anchor_override: String = "", attention_override: Dictionary = {}) -> Dictionary:
	var mapped := build_from_result(result, target_override, direction_override, anchor_override, attention_override)
	if not mapped.ok:
		return mapped
	return GMFeedbackPresentationPlan.from_mapped(mapped)

func build_presentation_plan_with_definition_from_fact(event_id: String, definition: GMFeedbackSequenceDefinition, target_override: String = "", direction_override: String = "down", anchor_override: String = "", attention_override: Dictionary = {}) -> Dictionary:
	var mapped := build_with_definition_from_fact(event_id, definition, target_override, direction_override, anchor_override, attention_override)
	if not mapped.ok:
		return mapped
	return GMFeedbackPresentationPlan.from_mapped(mapped)

func build_presentation_plan_with_definition_from_result(result: Variant, definition: GMFeedbackSequenceDefinition, target_override: String = "", direction_override: String = "down", anchor_override: String = "", attention_override: Dictionary = {}) -> Dictionary:
	var mapped := build_with_definition_from_result(result, definition, target_override, direction_override, anchor_override, attention_override)
	if not mapped.ok:
		return mapped
	return GMFeedbackPresentationPlan.from_mapped(mapped)

## Build a trusted request for a caller-supplied, already registered definition.
## This is still the formal mapper path; the definition is never read from a
## snapshot and the returned mapper artifact is runtime-only.
func build_with_definition_from_result(result: Variant, definition: GMFeedbackSequenceDefinition, target_override: String = "", direction_override: String = "down", anchor_override: String = "", attention_override: Dictionary = {}) -> Dictionary:
	if authority_reader == null:
		return _failure("feedback.mapper_authority_missing", "反馈映射器未连接权威读取器。")
	var authority := authority_reader.read_result(result)
	if not authority.ok:
		return authority
	return _build(authority, target_override, direction_override, anchor_override, attention_override, definition)

func build_with_definition_from_fact(event_id: String, definition: GMFeedbackSequenceDefinition, target_override: String = "", direction_override: String = "down", anchor_override: String = "", attention_override: Dictionary = {}) -> Dictionary:
	if authority_reader == null:
		return _failure("feedback.mapper_authority_missing", "反馈映射器未连接权威读取器。")
	var authority := authority_reader.read_fact(event_id)
	if not authority.ok:
		return authority
	return _build(authority, target_override, direction_override, anchor_override, attention_override, definition)

func _build(authority: Dictionary, target_override: String, direction_override: String, anchor_override: String, attention_override: Dictionary, definition_override: GMFeedbackSequenceDefinition = null) -> Dictionary:
	var fact: GMFactEvent = authority.fact
	var target := _target_ref(fact, target_override)
	if not GMFeedbackValidation.stable_id(target, true):
		return _failure("feedback.mapper_target_invalid", "反馈目标必须是稳定业务ID。")
	var direction := direction_override if direction_override in GMSemanticFeedbackRequest.DIRECTIONS else ""
	if direction.is_empty():
		return _failure("feedback.mapper_direction_invalid", "反馈方向不在支持集合内。")
	var anchor := anchor_override
	if not GMFeedbackValidation.stable_id(anchor, true):
		return _failure("feedback.mapper_anchor_invalid", "反馈锚点必须是稳定ID或空值。")
	var attention := attention_override.duplicate(true)
	var attention_version := ""
	if not attention.is_empty():
		var current_attention: Dictionary = {}
		if attention_runtime != null:
			current_attention = attention_runtime.attention_projection.duplicate(true)
		var attention_check := authority_reader.validate_attention_projection(fact.event_id, target, attention, current_attention)
		if not attention_check.ok:
			return _failure("feedback.mapper_attention_invalid", "Attention必须与当前P16 Fact和P17投影版本逐值互证。", attention_check)
		attention = attention_check.value
		attention_version = str(attention_check.get("projection_version", ""))
	var definition := definition_override if definition_override != null else _sequence_for(fact, authority.package, target, attention)
	var sequence_check := definition.validate()
	if not sequence_check.ok:
		return sequence_check
	var canonical := canonical_live_projection(authority, definition, target, direction, anchor, attention)
	if not canonical.ok:
		return canonical
	var request := GMSemanticFeedbackRequest.from_dict(canonical.request_fields)
	if request == null:
		return _failure("feedback.mapper_canonical_request_invalid", "规范化反馈投影无法重建严格语义反馈请求。")
	var request_check := request.validate()
	if not request_check.ok:
		return request_check
	var artifact := GMFeedbackMapperBuildArtifact.new(self, authority_reader, authority, request, definition, attention_runtime, str(canonical.identity.digest))
	return {"ok": true, "request": request, "definition": definition, "authority": authority, "sequence_digest": canonical.sequence_digest, "attention_projection_version": attention_version, "mapper_build_artifact": artifact}

func build_rejection_notice(blocked: Variant, source_id: String = "") -> Dictionary:
	## Reservation conflicts and other blocked results have no FactEvent.  This
	## returns a clearly non-domain presentation notice and never disguises it as
	## a committed event.
	if not blocked is GMBlockedResult:
		return _failure("feedback.rejection_result_required", "拒绝提示只接受 GMBlockedResult。")
	var value: GMBlockedResult = blocked
	var blocked_check := value.validate()
	if not blocked_check.ok:
		return _failure("feedback.rejection_invalid", "拒绝结果缺少可验证的结构化原因，未生成表现提示。", blocked_check)
	var source: String = source_id if not source_id.is_empty() else value.source
	var details := value.details.duplicate(true)
	details["target_id"] = value.target
	details["transaction_id"] = value.transaction_id
	var reason := GMFeedbackBlockedReason.from_failure({"code": value.error_code, "reason_zh": value.reason_zh, "fix": value.fix, "details": details}, source)
	reason.domain = _blocked_domain(value.error_code)
	var reason_check := reason.validate()
	if not reason_check.ok:
		return reason_check
	var receipt := GMPresentationReceipt.new()
	var digest := GMStableData.digest({"code": value.error_code, "source": source, "transaction": value.transaction_id, "reason": value.reason_zh})
	receipt.presentation_receipt_id = "gm.presentation.rejection.%s" % digest
	receipt.feedback_id = "gm.feedback.rejection.%s" % digest
	receipt.idempotency_key = "gm.feedback.rejection.%s" % digest
	receipt.source_fact_id = ""
	receipt.commit_package_id = ""
	receipt.sequence_id = "gm.feedback.sequence.rejection_notice"
	receipt.status = "blocked"
	receipt.blocked_reason = reason.to_dict()
	receipt.idempotent = false
	receipt.logic_unchanged = true
	receipt.domain_facts_written = false
	return {"ok": true, "receipt": receipt, "domain_event": false, "source_fact_id": "", "reason": reason}

func _blocked_domain(code: String) -> String:
	if code.begins_with("task.reservation"):
		return "reservation"
	if code.begins_with("task."):
		return "task"
	if code.begins_with("process."):
		return "process"
	if code.begins_with("presentation.") or code.begins_with("feedback."):
		return "presentation"
	return "feedback"

func _sequence_for(fact: GMFactEvent, package: Dictionary, target: String, attention: Dictionary) -> GMFeedbackSequenceDefinition:
	var operation := str(fact.payload.get("operation", fact.type.trim_prefix("gm.fact."))) if fact.payload is Dictionary else fact.type.trim_prefix("gm.fact.")
	var outcome := _outcome(fact)
	var sequence_suffix := _sequence_suffix(operation, outcome)
	var definition := GMFeedbackSequenceDefinition.new("gm.feedback.sequence.%s" % sequence_suffix, "语义反馈：%s" % _outcome_name(outcome))
	definition.max_steps = GMFeedbackSequenceDefinition.MAX_STEPS
	definition.max_duration_ticks = 600
	var action := semantic_action_for_fact(fact)
	var action_step := GMFeedbackStep.new("gm.feedback.step.action", "semantic_action")
	action_step.semantic_action_id = action
	action_step.target_ref = target
	action_step.logical_order = 0
	action_step.parallel_group = "gm.feedback.parallel.primary"
	action_step.duration_ticks = 1 if outcome in ["completed", "failed", "cancelled"] else 0
	action_step.optional = false
	action_step.metadata = {"outcome": outcome}
	definition.steps.append(action_step)
	var cues: Array = package.get("cues", []) if package is Dictionary else []
	if not cues.is_empty() and cues[0] is Dictionary:
		var cue_id := str(cues[0].get("cue_id", ""))
		if GMFeedbackValidation.stable_id(cue_id):
			var cue_step := GMFeedbackStep.new("gm.feedback.step.cue", "cue")
			cue_step.cue_id = cue_id
			cue_step.target_ref = target
			cue_step.logical_order = 0
			cue_step.parallel_group = "gm.feedback.parallel.primary"
			cue_step.duration_ticks = 0
			cue_step.optional = false
			cue_step.metadata = {"source_fact_id": fact.event_id}
			definition.steps.append(cue_step)
	var text_step := GMFeedbackStep.new("gm.feedback.step.text", "text")
	text_step.content_id = "gm.content.feedback.%s" % outcome
	text_step.text_zh = _outcome_name(outcome)
	text_step.target_ref = target
	text_step.logical_order = 1
	text_step.parallel_group = ""
	text_step.after_step_ids = ["gm.feedback.step.action"]
	if definition.steps.size() > 1:
		text_step.after_step_ids.append("gm.feedback.step.cue")
	text_step.metadata = {"outcome": outcome}
	definition.steps.append(text_step)
	if not attention.is_empty() and attention.selected.size() > 0:
		var attention_step := GMFeedbackStep.new("gm.feedback.step.attention", "attention")
		attention_step.content_id = "gm.content.feedback.attention"
		attention_step.target_ref = target
		attention_step.logical_order = 1
		attention_step.parallel_group = ""
		attention_step.after_step_ids = ["gm.feedback.step.action"]
		if definition.steps.size() > 2 and definition.steps[1].step_kind == "cue":
			attention_step.after_step_ids.append("gm.feedback.step.cue")
		attention_step.optional = true
		attention_step.metadata = {"selected_count": attention.selected.size()}
		definition.steps.append(attention_step)
	return definition

func _target_ref(fact: GMFactEvent, override: String) -> String:
	if not override.is_empty():
		return override
	if fact.targets.size() > 0 and GMFeedbackValidation.stable_id(str(fact.targets[0])):
		return str(fact.targets[0])
	if fact.payload is Dictionary:
		for key in ["task_id", "assignment_id", "reservation_id", "target_id", "resource_id"]:
			var value := str(fact.payload.get(key, ""))
			if GMFeedbackValidation.stable_id(value):
				return value
	return fact.actor if GMFeedbackValidation.stable_id(fact.actor) else ""

static func requested_tick_for_fact(fact: GMFactEvent) -> int:
	if fact != null and fact.payload is Dictionary and typeof(fact.payload.get("logical_tick", 0)) == TYPE_INT:
		return clamp(int(fact.payload.get("logical_tick", 0)), 0, 600)
	return 0

static func semantic_action_for_fact(fact: GMFactEvent) -> String:
	var operation := str(fact.payload.get("operation", "")) if fact.payload is Dictionary else ""
	var outcome := _outcome(fact)
	if outcome == "cancelled":
		return "death"
	if outcome in ["failed", "blocked"]:
		return "hurt"
	if operation.contains("assign") or operation.contains("reservation") and operation.contains("acquire") or operation.contains("reservation") and operation.contains("renew"):
		return "move"
	if operation.contains("execute") or operation.contains("ability"):
		return "attack"
	return "idle"

static func _outcome(fact: GMFactEvent) -> String:
	var operation := str(fact.payload.get("operation", "")) if fact.payload is Dictionary else ""
	var result: Variant = fact.payload.get("result", {}) if fact.payload is Dictionary else {}
	var state := str(result.get("state", "")) if result is Dictionary else ""
	if state in ["completed", "failed", "cancelled", "blocked", "in_progress"]:
		return state
	if operation.contains("reject") or operation.contains("revoke"):
		return "cancelled"
	if operation.contains("release") or operation.contains("consume"):
		return "completed"
	return "accepted"

func _outcome_name(outcome: String) -> String:
	return {"accepted": "反馈已接收", "completed": "反馈已完成", "failed": "反馈已失败", "cancelled": "反馈已取消", "blocked": "反馈已阻断", "in_progress": "反馈进行中"}.get(outcome, "反馈已接收")

func _sequence_suffix(operation: String, outcome: String) -> String:
	var raw := operation.to_lower()
	var safe := ""
	for character in raw:
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			safe += character
		else:
			safe += "_"
	if safe.is_empty():
		safe = "event"
	return "%s.%s" % [safe.trim_prefix("_").trim_suffix("_"), outcome]

static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
