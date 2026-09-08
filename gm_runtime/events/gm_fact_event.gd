class_name GMFactEvent
extends RefCounted

## 已由领域 Resolver 成功提交的事实事件。
## GameplayEvent 是请求/通知；只有 GMFactEvent 才能进入事实账本。

const SCHEMA_VERSION := GMFactEventSchema.SCHEMA_ID
static var _commit_capability: RefCounted = RefCounted.new()

var schema_version: String = SCHEMA_VERSION
var event_id: String = ""
var sequence: int = 0
var time: String = ""
var timestamp_usec: int = 0
var type: String = ""
var actor: String = ""
var targets: Array = []
var inputs: Array = []
var outputs: Array = []
var tags: Array = []
var causes: Array = []
var visibility: Dictionary = {"public": false, "witnesses": []}
var source_system: String = ""
var ability_id: String = ""
var ability_instance_id: String = ""
var resolver_id: String = ""
var transaction_id: String = ""
var idempotency_key: String = ""
var causal_chain_id: String = ""
var payload: Dictionary = {}
## 仅由 GMDomainTransactionCoordinator 在 Resolver commit 成功后设置；不进入公共 Schema。
var commit_proof: String = ""
var _commit_authority: Object = null

func _init(p_type: String = "", p_actor: String = "", p_targets: Array = [], p_payload: Dictionary = {}) -> void:
	type = p_type
	actor = p_actor
	targets = p_targets.duplicate(true)
	payload = p_payload.duplicate(true)
	time = Time.get_datetime_string_from_system(true)
	timestamp_usec = Time.get_ticks_usec()

func configure(p_sequence: int, p_type: String, p_actor: String, p_source_system: String, p_ability_id: String, p_ability_instance_id: String, p_resolver_id: String, p_transaction_id: String, p_idempotency_key: String, p_options: Dictionary = {}) -> GMFactEvent:
	schema_version = SCHEMA_VERSION
	sequence = p_sequence
	type = p_type
	actor = p_actor
	source_system = p_source_system
	ability_id = p_ability_id
	ability_instance_id = p_ability_instance_id
	resolver_id = p_resolver_id
	transaction_id = p_transaction_id
	idempotency_key = p_idempotency_key
	time = str(p_options.get("time", Time.get_datetime_string_from_system(true)))
	timestamp_usec = int(p_options.get("timestamp_usec", Time.get_ticks_usec()))
	event_id = str(p_options.get("event_id", make_event_id(sequence, type, idempotency_key)))
	targets = _array_copy(p_options.get("targets", targets))
	inputs = _array_copy(p_options.get("inputs", []))
	outputs = _array_copy(p_options.get("outputs", []))
	tags = _unique_strings(_array_copy(p_options.get("tags", [])))
	causes = _unique_strings(_array_copy(p_options.get("causes", [])))
	visibility = _visibility_copy(p_options.get("visibility", visibility))
	causal_chain_id = str(p_options.get("causal_chain_id", ""))
	payload = p_options.get("payload", payload).duplicate(true) if p_options.get("payload", payload) is Dictionary else {}
	return self

func mark_committed(p_transaction_id: String, p_authority: Object = null) -> GMFactEvent:
	if p_authority != _commit_capability or p_transaction_id.strip_edges().is_empty(): return self
	commit_proof = p_transaction_id
	_commit_authority = p_authority
	return self

func has_commit_proof() -> bool:
	return not commit_proof.is_empty() and _commit_authority == _commit_capability

static func _get_commit_capability() -> Object:
	return _commit_capability

static func from_dict(value: Dictionary) -> GMFactEvent:
	var result := GMFactEvent.new()
	result.schema_version = str(value.get("schema_version", SCHEMA_VERSION))
	result.event_id = str(value.get("event_id", ""))
	result.sequence = int(value.get("sequence", 0))
	result.time = str(value.get("time", ""))
	result.timestamp_usec = int(value.get("timestamp_usec", 0))
	result.type = str(value.get("type", ""))
	result.actor = str(value.get("actor", ""))
	result.targets = _array_copy(value.get("targets", []))
	result.inputs = _array_copy(value.get("inputs", []))
	result.outputs = _array_copy(value.get("outputs", []))
	result.tags = _array_copy(value.get("tags", []))
	result.causes = _array_copy(value.get("causes", []))
	result.visibility = _visibility_copy(value.get("visibility", {}))
	result.source_system = str(value.get("source_system", ""))
	result.ability_id = str(value.get("ability_id", ""))
	result.ability_instance_id = str(value.get("ability_instance_id", ""))
	result.resolver_id = str(value.get("resolver_id", ""))
	result.transaction_id = str(value.get("transaction_id", ""))
	result.idempotency_key = str(value.get("idempotency_key", ""))
	result.causal_chain_id = str(value.get("causal_chain_id", ""))
	result.payload = value.get("payload", {}).duplicate(true) if value.get("payload", {}) is Dictionary else {}
	return result

func validate() -> Dictionary:
	return GMFactEventSchema.validate_record(to_dict())

func is_valid() -> bool:
	return bool(validate().get("ok", false))

func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"event_id": event_id,
		"sequence": sequence,
		"time": time,
		"timestamp_usec": timestamp_usec,
		"type": type,
		"actor": actor,
		"targets": targets.duplicate(true),
		"inputs": inputs.duplicate(true),
		"outputs": outputs.duplicate(true),
		"tags": tags.duplicate(true),
		"causes": causes.duplicate(true),
		"visibility": visibility.duplicate(true),
		"source_system": source_system,
		"ability_id": ability_id,
		"ability_instance_id": ability_instance_id,
		"resolver_id": resolver_id,
		"transaction_id": transaction_id,
		"idempotency_key": idempotency_key,
		"causal_chain_id": causal_chain_id,
		"payload": payload.duplicate(true)
	}

static func make_event_id(p_sequence: int, p_type: String, p_idempotency_key: String = "") -> String:
	var identity_material := "%s|%s|%d" % [p_type, p_idempotency_key, maxi(p_sequence, 1)]
	return "gm.fact.v2.%06d.%s" % [maxi(p_sequence, 1), identity_material.sha256_text()]

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in range(raw.length()):
		var code := raw.unicode_at(index)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45:
			result += raw.substr(index, 1)
		else:
			result += "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_") if not result.is_empty() else "fact"

static func _array_copy(value: Variant) -> Array:
	return value.duplicate(true) if value is Array else []

static func _unique_strings(value: Array) -> Array:
	var seen: Dictionary = {}
	var result: Array = []
	for item in value:
		var text := str(item)
		if not seen.has(text):
			seen[text] = true
			result.append(text)
	return result

static func _visibility_copy(value: Variant) -> Dictionary:
	var source: Dictionary = value if value is Dictionary else {}
	return {"public": bool(source.get("public", false)), "witnesses": _unique_strings(_array_copy(source.get("witnesses", [])))}
