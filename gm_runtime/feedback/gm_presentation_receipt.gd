class_name GMPresentationReceipt
extends RefCounted

const SCHEMA_VERSION := "gm.presentation_receipt.v1"
const FIELDS := ["schema_version", "presentation_receipt_id", "feedback_id", "idempotency_key", "source_fact_id", "commit_package_id", "sequence_id", "status", "current_step_id", "step_receipts", "blocked_reason", "cancel_reason", "backend_kinds", "started_logical_tick", "completed_logical_tick", "idempotent", "optional_missing", "logic_unchanged", "domain_facts_written"]
const STATUSES := ["accepted", "playing", "completed", "cancelled", "blocked"]
const STEP_STATUSES := ["accepted", "completed", "skipped", "optional_missing", "blocked", "cancelled"]

var schema_version := SCHEMA_VERSION
var presentation_receipt_id := ""
var feedback_id := ""
var idempotency_key := ""
var source_fact_id := ""
var commit_package_id := ""
var sequence_id := ""
var status := "accepted"
var current_step_id := ""
var step_receipts: Array[Dictionary] = []
var blocked_reason: Dictionary = {}
var cancel_reason := ""
var backend_kinds: Array[String] = []
var started_logical_tick := 0
var completed_logical_tick := 0
var idempotent := false
var optional_missing: Array[Dictionary] = []
var logic_unchanged := true
var domain_facts_written := false

func to_dict() -> Dictionary:
	var backends := backend_kinds.duplicate()
	backends.sort()
	var missing := optional_missing.duplicate(true)
	return {"schema_version": schema_version, "presentation_receipt_id": presentation_receipt_id, "feedback_id": feedback_id, "idempotency_key": idempotency_key, "source_fact_id": source_fact_id, "commit_package_id": commit_package_id, "sequence_id": sequence_id, "status": status, "current_step_id": current_step_id, "step_receipts": step_receipts.duplicate(true), "blocked_reason": blocked_reason.duplicate(true), "cancel_reason": cancel_reason, "backend_kinds": backends, "started_logical_tick": started_logical_tick, "completed_logical_tick": completed_logical_tick, "idempotent": idempotent, "optional_missing": missing, "logic_unchanged": logic_unchanged, "domain_facts_written": domain_facts_written}

func validate(json_boundary: bool = false) -> Dictionary:
	var row := to_dict()
	if not GMFeedbackValidation.exact(row, FIELDS):
		return GMFeedbackValidation.failure("feedback.receipt_shape_invalid", "PresentationReceipt字段集合必须精确匹配。")
	if typeof(schema_version) != TYPE_STRING or typeof(presentation_receipt_id) != TYPE_STRING or typeof(feedback_id) != TYPE_STRING or typeof(idempotency_key) != TYPE_STRING or typeof(source_fact_id) != TYPE_STRING or typeof(commit_package_id) != TYPE_STRING or typeof(sequence_id) != TYPE_STRING or typeof(status) != TYPE_STRING or typeof(current_step_id) != TYPE_STRING or typeof(cancel_reason) != TYPE_STRING or typeof(step_receipts) != TYPE_ARRAY or typeof(blocked_reason) != TYPE_DICTIONARY or typeof(backend_kinds) != TYPE_ARRAY or typeof(optional_missing) != TYPE_ARRAY:
		return GMFeedbackValidation.failure("feedback.receipt_variant_invalid", "PresentationReceipt原始Variant类型无效。")
	if schema_version != SCHEMA_VERSION or not GMFeedbackValidation.stable_id(presentation_receipt_id) or not GMFeedbackValidation.stable_id(feedback_id) or not GMFeedbackValidation.stable_id(idempotency_key) or not GMFeedbackValidation.stable_id(source_fact_id, true) or not GMFeedbackValidation.stable_id(commit_package_id, true) or not GMFeedbackValidation.stable_id(sequence_id) or not GMFeedbackValidation.stable_id(current_step_id, true) or status not in STATUSES or not GMFeedbackValidation.stable_id(cancel_reason, true):
		return GMFeedbackValidation.failure("feedback.receipt_identity_invalid", "PresentationReceipt的身份、状态或取消原因无效。")
	if not GMFeedbackValidation.bounded_integer(started_logical_tick, 0, GMFeedbackValidation.MAX_SAFE_INT, json_boundary) or not GMFeedbackValidation.bounded_integer(completed_logical_tick, 0, GMFeedbackValidation.MAX_SAFE_INT, json_boundary) or completed_logical_tick < 0:
		return GMFeedbackValidation.failure("feedback.receipt_tick_invalid", "PresentationReceipt逻辑时钟不是有界整数。")
	if typeof(started_logical_tick) != TYPE_INT or typeof(completed_logical_tick) != TYPE_INT or typeof(idempotent) != TYPE_BOOL or typeof(logic_unchanged) != TYPE_BOOL or not logic_unchanged or typeof(domain_facts_written) != TYPE_BOOL or domain_facts_written:
		return GMFeedbackValidation.failure("feedback.receipt_flag_invalid", "PresentationReceipt的只读标志或集合类型无效。")
	var seen_backends := {}
	for backend in backend_kinds:
		if not GMFeedbackValidation.stable_id(backend) or seen_backends.has(backend):
			return GMFeedbackValidation.failure("feedback.receipt_backend_invalid", "PresentationReceipt包含重复或不稳定的表现后端ID。")
		seen_backends[backend] = true
	var seen_steps := {}
	for raw_step in step_receipts:
		if not raw_step is Dictionary or not GMFeedbackValidation.exact(raw_step, ["step_id", "step_kind", "status", "logical_tick", "code", "optional"]):
			return GMFeedbackValidation.failure("feedback.receipt_step_shape_invalid", "步骤回执字段集合必须精确匹配。")
		if typeof(raw_step.step_id) != TYPE_STRING or typeof(raw_step.step_kind) != TYPE_STRING or typeof(raw_step.status) != TYPE_STRING or typeof(raw_step.code) != TYPE_STRING or typeof(raw_step.optional) != TYPE_BOOL or not GMFeedbackValidation.stable_id(raw_step.step_id) or raw_step.step_kind not in GMFeedbackStep.KINDS or raw_step.status not in STEP_STATUSES or not GMFeedbackValidation.bounded_integer(raw_step.logical_tick, 0, GMFeedbackValidation.MAX_SAFE_INT, json_boundary) or not GMFeedbackValidation.stable_id(raw_step.code) or seen_steps.has(raw_step.step_id):
			return GMFeedbackValidation.failure("feedback.receipt_step_invalid", "步骤回执包含无效身份、状态或逻辑时钟。")
		seen_steps[raw_step.step_id] = true
	if blocked_reason.is_empty():
		if status == "blocked":
			return GMFeedbackValidation.failure("feedback.receipt_blocked_reason_missing", "blocked回执必须带结构化阻断原因。")
	else:
		var reason := GMFeedbackBlockedReason.from_dict(blocked_reason)
		if reason == null:
			return GMFeedbackValidation.failure("feedback.receipt_blocked_reason_invalid", "PresentationReceipt阻断原因未通过Schema校验。")
	for missing in optional_missing:
		if not missing is Dictionary or not GMFeedbackValidation.exact(missing, ["step_id", "code", "reason_zh"]):
			return GMFeedbackValidation.failure("feedback.receipt_optional_missing_invalid", "可选内容缺失记录字段集合无效。")
		if typeof(missing.step_id) != TYPE_STRING or typeof(missing.code) != TYPE_STRING or typeof(missing.reason_zh) != TYPE_STRING or not GMFeedbackValidation.stable_id(missing.step_id) or not GMFeedbackValidation.stable_id(missing.code) or missing.reason_zh.strip_edges().is_empty():
			return GMFeedbackValidation.failure("feedback.receipt_optional_missing_invalid", "可选内容缺失记录必须包含稳定步骤和中文原因。")
	return {"ok": true, "code": "feedback.receipt_valid", "value": row.duplicate(true)}

static func from_dict(value: Variant, json_boundary: bool = false) -> GMPresentationReceipt:
	if not value is Dictionary:
		return null
	var row: Dictionary = value
	if not GMFeedbackValidation.exact(row, FIELDS):
		return null
	var raw_check := _validate_raw_row(row, json_boundary)
	if not raw_check.ok:
		return null
	var result := GMPresentationReceipt.new()
	result.schema_version = row.schema_version
	result.presentation_receipt_id = row.presentation_receipt_id
	result.feedback_id = row.feedback_id
	result.idempotency_key = row.idempotency_key
	result.source_fact_id = row.source_fact_id
	result.commit_package_id = row.commit_package_id
	result.sequence_id = row.sequence_id
	result.status = row.status
	result.current_step_id = row.current_step_id
	result.step_receipts.clear()
	if row.step_receipts is Array:
		for step_row in row.step_receipts:
			var step_copy: Dictionary = step_row.duplicate(true)
			if json_boundary:
				step_copy.logical_tick = int(step_copy.logical_tick)
			result.step_receipts.append(step_copy)
	result.blocked_reason = row.blocked_reason.duplicate(true)
	result.cancel_reason = row.cancel_reason
	result.backend_kinds.clear()
	for backend in row.backend_kinds:
		result.backend_kinds.append(backend)
	result.started_logical_tick = int(row.started_logical_tick) if json_boundary else row.started_logical_tick
	result.completed_logical_tick = int(row.completed_logical_tick) if json_boundary else row.completed_logical_tick
	result.idempotent = row.idempotent
	result.optional_missing.clear()
	for missing in row.optional_missing:
		result.optional_missing.append(missing.duplicate(true))
	result.logic_unchanged = row.logic_unchanged
	result.domain_facts_written = row.domain_facts_written
	return result if result.validate().ok else null

static func _validate_raw_row(row: Dictionary, json_boundary: bool) -> Dictionary:
	var strings := ["schema_version", "presentation_receipt_id", "feedback_id", "idempotency_key", "source_fact_id", "commit_package_id", "sequence_id", "status", "current_step_id", "cancel_reason"]
	var integers := ["started_logical_tick", "completed_logical_tick"]
	var booleans := ["idempotent", "logic_unchanged", "domain_facts_written"]
	var arrays := ["step_receipts", "backend_kinds", "optional_missing"]
	if not GMFeedbackValidation.exact_field_types(row, strings, integers, booleans, arrays, ["blocked_reason"], json_boundary):
		return GMFeedbackValidation.failure("feedback.receipt_variant_invalid", "PresentationReceipt原始Variant类型不符合精确契约。")
	if not GMFeedbackValidation.bounded_integer(row.started_logical_tick, 0, GMFeedbackValidation.MAX_SAFE_INT, json_boundary) or not GMFeedbackValidation.bounded_integer(row.completed_logical_tick, 0, GMFeedbackValidation.MAX_SAFE_INT, json_boundary):
		return GMFeedbackValidation.failure("feedback.receipt_tick_invalid", "PresentationReceipt逻辑时钟不是有界整数。")
	if not GMFeedbackValidation.array_members_are(row.backend_kinds, TYPE_STRING):
		return GMFeedbackValidation.failure("feedback.receipt_backend_variant_invalid", "PresentationReceipt后端集合必须是原生字符串数组。")
	for raw_step in row.step_receipts:
		if not raw_step is Dictionary or not GMFeedbackValidation.exact(raw_step, ["step_id", "step_kind", "status", "logical_tick", "code", "optional"]):
			return GMFeedbackValidation.failure("feedback.receipt_step_shape_invalid", "步骤回执字段集合必须精确匹配。")
		if typeof(raw_step.step_id) != TYPE_STRING or typeof(raw_step.step_kind) != TYPE_STRING or typeof(raw_step.status) != TYPE_STRING or typeof(raw_step.code) != TYPE_STRING or typeof(raw_step.optional) != TYPE_BOOL or not GMFeedbackValidation.bounded_integer(raw_step.logical_tick, 0, GMFeedbackValidation.MAX_SAFE_INT, json_boundary):
			return GMFeedbackValidation.failure("feedback.receipt_step_variant_invalid", "步骤回执原始Variant类型或逻辑时钟无效。")
	for missing in row.optional_missing:
		if not missing is Dictionary or not GMFeedbackValidation.exact(missing, ["step_id", "code", "reason_zh"]):
			return GMFeedbackValidation.failure("feedback.receipt_optional_missing_invalid", "可选内容缺失记录字段集合无效。")
		if typeof(missing.step_id) != TYPE_STRING or typeof(missing.code) != TYPE_STRING or typeof(missing.reason_zh) != TYPE_STRING:
			return GMFeedbackValidation.failure("feedback.receipt_optional_missing_variant_invalid", "可选内容缺失记录原始Variant类型无效。")
	if not row.blocked_reason.is_empty() and GMFeedbackBlockedReason.from_dict(row.blocked_reason) == null:
		return GMFeedbackValidation.failure("feedback.receipt_blocked_reason_invalid", "PresentationReceipt阻断原因未通过Schema校验。")
	return {"ok": true}
