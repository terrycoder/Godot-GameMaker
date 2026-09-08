class_name GMInteractionRequest
extends RefCounted

## A request is an immutable value handoff. It never contains an authority
## object, runtime handle, world coordinate or backend instance.

const SCHEMA_VERSION := GMP21Contract.INTERACTION_REQUEST_SCHEMA_VERSION
const FIELDS := ["schema_version", "request_id", "interaction_id", "kind", "source_ref", "target_ref", "payload", "idempotency_key"]

var schema_version := SCHEMA_VERSION
var request_id := ""
var interaction_id := ""
var kind := ""
var source_ref: Variant = ""
var target_ref: Variant = ""
var payload: Dictionary = {}
var idempotency_key := ""

func _init(p_interaction_id: String = "", p_kind: String = "", p_source_ref: Variant = "", p_target_ref: Variant = "", p_payload: Dictionary = {}, p_idempotency_key: String = "") -> void:
	interaction_id = p_interaction_id
	kind = p_kind
	var source := GMP21Contract.target_ref(p_source_ref, true)
	var target := GMP21Contract.target_ref(p_target_ref, true)
	source_ref = source.value if source.ok else p_source_ref
	target_ref = target.value if target.ok else p_target_ref
	payload = p_payload.duplicate(true)
	idempotency_key = p_idempotency_key
	request_id = derive_request_id()

func derive_request_id() -> String:
	var identity := {
		"schema_version": SCHEMA_VERSION,
		"interaction_id": interaction_id,
		"kind": kind,
		"source_ref": source_ref,
		"target_ref": target_ref,
		"payload": payload,
		"idempotency_key": idempotency_key,
	}
	return "gm.interaction.request.%s" % GMP21Contract.digest(identity)

func validate() -> Dictionary:
	var value := to_dict()
	if not GMP21Contract.exact(value, FIELDS):
		return GMP21Contract.failure("interaction.request_shape_invalid", "InteractionRequest字段集合必须精确匹配。")
	if schema_version != SCHEMA_VERSION or not GMP21Contract.stable_id(interaction_id) or kind not in GMP21Contract.INTERACTION_KINDS:
		return GMP21Contract.failure("interaction.request_identity_invalid", "InteractionRequest版本、交互ID或类型无效。")
	if not GMP21Contract.stable_id(idempotency_key):
		return GMP21Contract.failure("interaction.request_idempotency_invalid", "InteractionRequest必须携带稳定幂等键。")
	var source := GMP21Contract.target_ref(source_ref, true)
	if not source.ok:
		return source
	var target := GMP21Contract.target_ref(target_ref, true)
	if not target.ok:
		return target
	var payload_check := GMP21Contract.pure(payload, "$.payload")
	if not payload_check.ok:
		return payload_check
	if request_id != derive_request_id():
		return GMP21Contract.failure("interaction.request_identity_mismatch", "InteractionRequest的request_id不是由合同内容确定性派生。")
	return {"ok": true, "code": "interaction.request_valid", "value": value}

func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"request_id": request_id,
		"interaction_id": interaction_id,
		"kind": kind,
		"source_ref": GMStableData.clone(source_ref),
		"target_ref": GMStableData.clone(target_ref),
		"payload": payload.duplicate(true),
		"idempotency_key": idempotency_key,
	}

func to_json() -> String:
	return JSON.stringify(GMStableData.persistence_canonical(to_dict()), "", false, true)

static func from_dict(value: Variant, json_boundary: bool = false) -> Dictionary:
	if not value is Dictionary or not GMP21Contract.exact(value, FIELDS):
		return GMP21Contract.failure("interaction.request_shape_invalid", "InteractionRequest字段缺失或包含未知字段。")
	for field in ["schema_version", "request_id", "interaction_id", "kind", "idempotency_key"]:
		if typeof(value.get(field)) != TYPE_STRING:
			return GMP21Contract.failure("interaction.request_type_invalid", "InteractionRequest字符串字段类型无效。", {"field": field})
	if not value.get("source_ref") is String and not value.get("source_ref") is Dictionary:
		return GMP21Contract.failure("interaction.request_type_invalid", "InteractionRequest source_ref必须是稳定字符串或纯对象。")
	if not value.get("target_ref") is String and not value.get("target_ref") is Dictionary:
		return GMP21Contract.failure("interaction.request_type_invalid", "InteractionRequest target_ref必须是稳定字符串或纯对象。")
	if not value.get("payload") is Dictionary:
		return GMP21Contract.failure("interaction.request_type_invalid", "InteractionRequest payload必须是纯对象。")
	var result := GMInteractionRequest.new()
	result.schema_version = str(value.get("schema_version", ""))
	result.request_id = str(value.get("request_id", ""))
	result.interaction_id = str(value.get("interaction_id", ""))
	result.kind = str(value.get("kind", ""))
	result.source_ref = GMStableData.clone(value.get("source_ref", ""))
	result.target_ref = GMStableData.clone(value.get("target_ref", ""))
	result.payload = value.get("payload", {}).duplicate(true) if value.get("payload", {}) is Dictionary else {}
	result.idempotency_key = str(value.get("idempotency_key", ""))
	var checked := result.validate()
	if not checked.ok:
		return checked
	return {"ok": true, "code": "interaction.request_decoded", "request": result}

static func from_json(text: String) -> Dictionary:
	var parsed := GMP21Contract.normalize_json(text, "interaction.request_json_invalid")
	if not parsed.ok:
		return parsed
	return from_dict(parsed.value, true)

static func ability(interaction_id: String, source_ref: Variant, target_ref: Variant, payload: Dictionary, idempotency_key: String) -> GMInteractionRequest:
	return GMInteractionRequest.new(interaction_id, "ability", source_ref, target_ref, payload, idempotency_key)

static func task(interaction_id: String, source_ref: Variant, target_ref: Variant, payload: Dictionary, idempotency_key: String) -> GMInteractionRequest:
	return GMInteractionRequest.new(interaction_id, "task", source_ref, target_ref, payload, idempotency_key)

static func transaction(interaction_id: String, source_ref: Variant, target_ref: Variant, payload: Dictionary, idempotency_key: String) -> GMInteractionRequest:
	return GMInteractionRequest.new(interaction_id, "transaction", source_ref, target_ref, payload, idempotency_key)

static func process(interaction_id: String, source_ref: Variant, target_ref: Variant, payload: Dictionary, idempotency_key: String) -> GMInteractionRequest:
	return GMInteractionRequest.new(interaction_id, "process", source_ref, target_ref, payload, idempotency_key)
