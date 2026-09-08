class_name GMProcessFeedbackAdapter
extends RefCounted

## P20 is intentionally not implemented here.  This adapter is a typed
## boundary that reports Unsupported Domain instead of accepting Process state
## or writing any domain fact.

const SUPPORTED := false
const DOMAIN := "process"

func request_for_unsupported(operation_id: String = "") -> Dictionary:
	var reason := GMFeedbackBlockedReason.new("feedback.unsupported_domain", "P20 Process领域尚未进入P18反馈范围。", "等待P20公开适配器合同后再接入。", DOMAIN, false, operation_id, {"supported": false, "future_contract": "P20 ProcessFeedbackAdapter"})
	return {"ok": false, "code": reason.code, "reason_zh": reason.reason_zh, "blocked_reason": reason.to_dict(), "domain_facts_written": false, "logic_unchanged": true}

