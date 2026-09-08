class_name GMCandidateResult
extends RefCounted

## 候选只描述可能性，不代表请求已执行，也不允许写入 Fact ledger。

const RESULT_KIND := "candidate"

var candidate_id: String = ""
var source: String = ""
var target: String = ""
var chain: GMCausalChain
var score: float = 0.0
var reasons: Array = []
var request_snapshot: Dictionary = {}
var suggested_fix: Dictionary = {}

func _init(p_candidate_id: String = "", p_source: String = "", p_target: String = "", p_chain: GMCausalChain = null) -> void:
	candidate_id = p_candidate_id
	source = p_source
	target = p_target
	chain = p_chain

func is_candidate() -> bool:
	return true

func is_blocked() -> bool:
	return false

func is_committed() -> bool:
	return false

func to_dict() -> Dictionary:
	return {
		"result_kind": RESULT_KIND,
		"candidate_id": candidate_id,
		"source": source,
		"target": target,
		"score": score,
		"reasons": reasons.duplicate(true),
		"request": request_snapshot.duplicate(true),
		"chain": chain.to_dict() if chain != null else {},
		"fix": suggested_fix.duplicate(true)
	}

func validate() -> Dictionary:
	var errors: Array[String] = []
	if candidate_id.strip_edges().is_empty(): errors.append("Candidate 缺少 candidate_id。")
	if source.strip_edges().is_empty(): errors.append("Candidate 缺少 source。")
	if chain == null or not chain.validate().ok: errors.append("Candidate 缺少有效因果链。")
	return {"ok": errors.is_empty(), "code": "candidate.valid" if errors.is_empty() else "candidate.invalid", "errors": errors}

static func from_request(request: GMAbilityActivationRequest, p_chain: GMCausalChain = null, p_score: float = 0.0, p_reasons: Array = []) -> GMCandidateResult:
	var chain := p_chain if p_chain != null else GMCausalChain.from_activation_request(request)
	var candidate_key := request.idempotency_key if request != null and not request.idempotency_key.is_empty() else request.request_id if request != null else "candidate"
	var source_id: String = str(request.event_data.get("source_id", request.source)) if request != null else ""
	var target_id: String = str(request.target_data.target_business_id) if request != null and request.target_data != null else str(request.event_data.get("target_id", "")) if request != null else ""
	var result := GMCandidateResult.new("gm.candidate.%s" % _slug(str(candidate_key)), str(source_id), target_id, chain)
	result.score = p_score
	result.reasons = p_reasons.duplicate(true)
	result.request_snapshot = request.to_dict() if request != null else {}
	return result

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in range(raw.length()):
		var code := raw.unicode_at(index)
		result += raw.substr(index, 1) if ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45) else "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_") if not result.is_empty() else "candidate"
