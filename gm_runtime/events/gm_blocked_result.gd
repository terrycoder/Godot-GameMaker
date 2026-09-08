class_name GMBlockedResult
extends RefCounted

## 阻断表示一次尝试没有提交。它必须携带可定位的结构化原因和修复建议。

const RESULT_KIND := "blocked"

var error_code: String = ""
var reason_zh: String = ""
var source: String = ""
var target: String = ""
var chain: GMCausalChain
var fix: Dictionary = {}
var details: Dictionary = {}
var transaction_id: String = ""
var rollback_report: Dictionary = {}

func _init(p_error_code: String = "", p_reason_zh: String = "", p_source: String = "", p_target: String = "", p_chain: GMCausalChain = null, p_fix: Dictionary = {}) -> void:
	error_code = p_error_code
	reason_zh = p_reason_zh
	source = p_source
	target = p_target
	chain = p_chain
	fix = p_fix.duplicate(true)

func is_candidate() -> bool:
	return false

func is_blocked() -> bool:
	return true

func is_committed() -> bool:
	return false

func to_dict() -> Dictionary:
	return {
		"result_kind": RESULT_KIND,
		"error_code": error_code,
		"reason_zh": reason_zh,
		"source": source,
		"target": target,
		"chain": chain.to_dict() if chain != null else {},
		"fix": fix.duplicate(true),
		"details": details.duplicate(true),
		"transaction_id": transaction_id,
		"rollback_report": rollback_report.duplicate(true)
	}

func validate() -> Dictionary:
	var errors: Array[String] = []
	if error_code.strip_edges().is_empty(): errors.append("BlockedResult 缺少结构化错误码。")
	if reason_zh.strip_edges().is_empty(): errors.append("BlockedResult 缺少中文原因。")
	if source.strip_edges().is_empty(): errors.append("BlockedResult 缺少 source。")
	if chain == null or not chain.validate().ok: errors.append("BlockedResult 缺少有效因果链。")
	if fix.is_empty(): errors.append("BlockedResult 缺少 fix 修复建议。")
	return {"ok": errors.is_empty(), "code": "blocked.valid" if errors.is_empty() else "blocked.invalid", "errors": errors}

static func from_failure(failure: Dictionary, request: GMAbilityActivationRequest, p_chain: GMCausalChain = null) -> GMBlockedResult:
	var chain := p_chain if p_chain != null else GMCausalChain.from_activation_request(request)
	var source_id := str(failure.get("source", request.event_data.get("source_id", request.source) if request != null else ""))
	var target_id := str(failure.get("target", request.target_data.target_business_id if request != null and request.target_data != null else request.event_data.get("target_id", "") if request != null else ""))
	var fix_value: Variant = failure.get("fix", {"action": "检查请求、目标和领域前置条件。"})
	var result := GMBlockedResult.new(str(failure.get("code", failure.get("failure_code", "activation.blocked"))), str(failure.get("reason_zh", failure.get("failure_reason_zh", "能力尝试未提交。"))), source_id, target_id, chain, fix_value if fix_value is Dictionary else {"action": str(fix_value)})
	result.details = failure.duplicate(true)
	result.transaction_id = str(failure.get("transaction_id", ""))
	return result
