class_name GMCausalRef
extends RefCounted

## 因果链中的稳定引用。只保存业务身份，不保存 NodePath、Node 或 Resource 引用。

const ALLOWED_KINDS := [
	"activation_request",
	"ability_instance",
	"domain_transaction",
	"domain_resolver",
	"fact_event",
	"change_record",
	"cue",
	"gameplay_event"
]

var kind: String = ""
var ref_type: String = ""
var stable_id: String = ""
var ref_id: String = ""
var label: String = ""
var metadata: Dictionary = {}

func _init(p_kind: String = "", p_stable_id: String = "", p_label: String = "", p_metadata: Dictionary = {}) -> void:
	kind = p_kind
	ref_type = p_kind
	stable_id = p_stable_id
	ref_id = p_stable_id
	label = p_label
	metadata = p_metadata.duplicate(true)

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not ALLOWED_KINDS.has(kind): errors.append("未知因果引用类型：%s" % kind)
	if stable_id.strip_edges().is_empty(): errors.append("因果引用缺少稳定 ID。")
	if stable_id != ref_id or kind != ref_type: errors.append("因果引用别名字段不一致。")
	if stable_id.contains("NodePath") or stable_id.begins_with("/") or stable_id.contains("res://") or stable_id.contains("user://"):
		errors.append("因果引用不得使用 NodePath 或文件路径。")
	return {"ok": errors.is_empty(), "code": "causal_ref.valid" if errors.is_empty() else "causal_ref.invalid", "errors": errors}

func to_dict() -> Dictionary:
	return {
		"kind": kind,
		"ref_type": ref_type,
		"stable_id": stable_id,
		"ref_id": ref_id,
		"label": label,
		"metadata": metadata.duplicate(true)
	}

static func from_dict(value: Dictionary) -> GMCausalRef:
	return GMCausalRef.new(str(value.get("kind", value.get("ref_type", ""))), str(value.get("stable_id", value.get("ref_id", ""))), str(value.get("label", "")), value.get("metadata", {}) if value.get("metadata", {}) is Dictionary else {})

static func request(request_id: String, source: String = "") -> GMCausalRef:
	return GMCausalRef.new("activation_request", request_id, "ActivationRequest", {"source": source})

static func ability_instance(instance_id: String, ability_id: String = "") -> GMCausalRef:
	return GMCausalRef.new("ability_instance", instance_id, "AbilityInstance", {"ability_id": ability_id})

static func resolver(resolver_id: String) -> GMCausalRef:
	return GMCausalRef.new("domain_resolver", resolver_id, "DomainResolver")

static func transaction(transaction_id: String, resolver_id: String = "") -> GMCausalRef:
	return GMCausalRef.new("domain_transaction", transaction_id, "DomainTransaction", {"resolver_id": resolver_id})

static func fact(event_id: String, fact_type: String = "") -> GMCausalRef:
	return GMCausalRef.new("fact_event", event_id, "FactEvent", {"type": fact_type})

static func change(change_id: String, fact_event_id: String = "") -> GMCausalRef:
	return GMCausalRef.new("change_record", change_id, "ChangeRecord", {"fact_event_id": fact_event_id})

static func cue(cue_id: String, instance_id: String = "") -> GMCausalRef:
	return GMCausalRef.new("cue", cue_id, "Cue", {"instance_id": instance_id})
