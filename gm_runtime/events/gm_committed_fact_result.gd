class_name GMCommittedFactResult
extends RefCounted

## 只有成功提交的领域事务才能产生此结果。

const RESULT_KIND := "committed_fact"

var fact_event: GMFactEvent
var change_records: Array[GMChangeRecord] = []
var chain: GMCausalChain
var transaction_id: String = ""
var idempotent: bool = false
var cues: Array = []
## 仅Coordinator设置；指向产生此返回副本的既有权威FactEventStore。
## Task消费端仍会逐值比对Store中的不可变提交包，不能把此引用当作自证字段。
var authority_store: GMFactEventStore

func _init(p_fact_event: GMFactEvent = null, p_change_records: Array = [], p_chain: GMCausalChain = null, p_transaction_id: String = "", p_idempotent: bool = false) -> void:
	fact_event = p_fact_event
	for record in p_change_records:
		if record is GMChangeRecord: change_records.append(record)
	chain = p_chain
	transaction_id = p_transaction_id
	idempotent = p_idempotent

func is_candidate() -> bool:
	return false

func is_blocked() -> bool:
	return false

func is_committed() -> bool:
	return true

func to_dict() -> Dictionary:
	return {
		"result_kind": RESULT_KIND,
		"committed": true,
		"idempotent": idempotent,
		"transaction_id": transaction_id,
		"fact_event": fact_event.to_dict() if fact_event != null else {},
		"change_records": change_records.map(func(value: GMChangeRecord): return value.to_dict()),
		"chain": chain.to_dict() if chain != null else {},
		"cues": cues.duplicate(true)
	}

func validate() -> Dictionary:
	var errors: Array[String] = []
	if fact_event == null or not fact_event.is_valid(): errors.append("CommittedFactResult 缺少有效 FactEvent。")
	if change_records.is_empty(): errors.append("CommittedFactResult 至少需要一个 ChangeRecord。")
	if chain == null or not chain.validate().ok: errors.append("CommittedFactResult 缺少有效因果链。")
	return {"ok": errors.is_empty(), "code": "committed_fact.valid" if errors.is_empty() else "committed_fact.invalid", "errors": errors}

static func from_dict(value: Dictionary) -> GMCommittedFactResult:
	var fact_value: Variant = value.get("fact_event", {})
	var fact := GMFactEvent.from_dict(fact_value) if fact_value is Dictionary else null
	var records: Array = []
	for record_value in value.get("change_records", []):
		if record_value is Dictionary: records.append(GMChangeRecord.from_dict(record_value))
	var result := GMCommittedFactResult.new(fact, records, null, str(value.get("transaction_id", "")), bool(value.get("idempotent", false)))
	result.cues = value.get("cues", []).duplicate(true) if value.get("cues", []) is Array else []
	return result
