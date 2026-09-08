class_name GMFeedbackBlockedReason
extends RefCounted

const SCHEMA_VERSION := "gm.feedback.blocked_reason.v1"
const FIELDS := ["schema_version", "code", "domain", "reason_zh", "action_zh", "retryable", "source_id", "details"]
const DOMAINS := ["feedback", "task", "reservation", "process", "presentation"]

var schema_version := SCHEMA_VERSION
var code := ""
var domain := "feedback"
var reason_zh := ""
var action_zh := ""
var retryable := false
var source_id := ""
var details: Dictionary = {}

func _init(p_code: String = "", p_reason_zh: String = "", p_action_zh: String = "", p_domain: String = "feedback", p_retryable: bool = false, p_source_id: String = "", p_details: Dictionary = {}) -> void:
	code = p_code
	reason_zh = p_reason_zh
	action_zh = p_action_zh
	domain = p_domain
	retryable = p_retryable
	source_id = p_source_id
	details = p_details.duplicate(true)

func to_dict() -> Dictionary:
	return {"schema_version": schema_version, "code": code, "domain": domain, "reason_zh": reason_zh, "action_zh": action_zh, "retryable": retryable, "source_id": source_id, "details": details.duplicate(true)}

func validate() -> Dictionary:
	var row := to_dict()
	if not GMFeedbackValidation.exact(row, FIELDS):
		return GMFeedbackValidation.failure("feedback.blocked_reason_shape_invalid", "阻断原因字段集合必须精确匹配。")
	if typeof(schema_version) != TYPE_STRING or typeof(code) != TYPE_STRING or typeof(domain) != TYPE_STRING or typeof(reason_zh) != TYPE_STRING or typeof(action_zh) != TYPE_STRING or typeof(source_id) != TYPE_STRING or typeof(details) != TYPE_DICTIONARY:
		return GMFeedbackValidation.failure("feedback.blocked_reason_variant_invalid", "阻断原因原始Variant类型无效。")
	if schema_version != SCHEMA_VERSION or not GMFeedbackValidation.stable_id(code) or domain not in DOMAINS:
		return GMFeedbackValidation.failure("feedback.blocked_reason_identity_invalid", "阻断原因的Schema、代码或领域无效。")
	if reason_zh.strip_edges().is_empty() or action_zh.strip_edges().is_empty() or typeof(retryable) != TYPE_BOOL or not GMFeedbackValidation.stable_id(source_id, true):
		return GMFeedbackValidation.failure("feedback.blocked_reason_value_invalid", "阻断原因必须包含中文原因、可执行建议和稳定来源。")
	var stable := GMFeedbackValidation.stable_value(details, "$.details")
	if not stable.ok:
		return stable
	return {"ok": true, "code": "feedback.blocked_reason_valid", "value": row.duplicate(true)}

static func from_dict(value: Variant) -> GMFeedbackBlockedReason:
	if not value is Dictionary:
		return null
	var row: Dictionary = value
	if not GMFeedbackValidation.exact(row, FIELDS):
		return null
	if not GMFeedbackValidation.exact_field_types(row, ["schema_version", "code", "domain", "reason_zh", "action_zh", "source_id"], [], ["retryable"], [], ["details"]):
		return null
	var result := GMFeedbackBlockedReason.new(row.code, row.reason_zh, row.action_zh, row.domain, row.retryable, row.source_id, row.details)
	result.schema_version = row.schema_version
	return result if result.validate().ok else null

static func from_failure(failure: Dictionary, p_source_id: String = "") -> GMFeedbackBlockedReason:
	var code := str(failure.get("code", "feedback.blocked"))
	if not GMFeedbackValidation.stable_id(code):
		code = "feedback.blocked"
	var reason := str(failure.get("reason_zh", "语义反馈未能进入表现层。"))
	var fix: Variant = failure.get("fix", {"action": "检查当前反馈契约后重试。"})
	var action := str(fix.get("action", "检查当前反馈契约后重试。")) if fix is Dictionary else str(fix)
	if action.strip_edges().is_empty():
		action = "检查当前反馈契约后重试。"
	var retryable_value: bool = false
	var retryable: Variant = failure.get("retryable", false)
	if typeof(retryable) == TYPE_BOOL:
		retryable_value = retryable
	return GMFeedbackBlockedReason.new(code, reason, action, "feedback", retryable_value, p_source_id, failure.get("details", {}).duplicate(true) if failure.get("details", {}) is Dictionary else {})
