class_name GMAbilityActivationRequest
extends RefCounted

## 所有输入、AI、日程、调试器与事件触发都必须构造这个请求。

const IDENTITY_VERSION := "v2"
const INSTANCE_ID_DOMAIN := "gm.ability.instance"
const MAX_IDEMPOTENCY_KEY_LENGTH := 4096

static var _request_sequence: int = 0

var host: GMAbilitySystemHost
var ability_id: String = ""
var ability_tag: String = ""
var target_data: GMTargetData
var event_data: Dictionary = {}
var source: String = ""
var schedule_context: Dictionary = {}
var request_id: String = ""
var idempotency_key: String = ""
var causal_chain: GMCausalChain
var created_at_usec: int = 0

func _init(p_host: GMAbilitySystemHost = null, p_ability_id: String = "", p_ability_tag: String = "", p_target_data: GMTargetData = null, p_event_data: Dictionary = {}, p_source: String = "", p_schedule_context: Dictionary = {}, p_idempotency_key: String = "") -> void:
	host = p_host
	ability_id = p_ability_id
	ability_tag = p_ability_tag
	target_data = p_target_data
	event_data = p_event_data.duplicate(true)
	source = p_source
	schedule_context = p_schedule_context.duplicate(true)
	created_at_usec = Time.get_ticks_usec()
	_request_sequence += 1
	request_id = "gmreq-%s-%d-%d" % [IDENTITY_VERSION, created_at_usec, _request_sequence]
	# Only the zero-length string means "no explicit idempotency". Case,
	# whitespace, Unicode composition and separators are exact key material.
	idempotency_key = p_idempotency_key if not p_idempotency_key.is_empty() else str(event_data.get("idempotency_key", ""))
	causal_chain = GMCausalChain.from_activation_request(self)

func validate() -> Dictionary:
	if host == null:
		return {"ok": false, "code": "request.host_missing", "reason_zh": "激活请求缺少能力宿主。"}
	if ability_id.strip_edges().is_empty() and ability_tag.strip_edges().is_empty():
		return {"ok": false, "code": "request.ability_missing", "reason_zh": "激活请求必须包含能力 ID 或能力标签。"}
	if source.strip_edges().is_empty():
		return {"ok": false, "code": "request.source_missing", "reason_zh": "激活请求缺少触发来源。"}
	if idempotency_key.length() > MAX_IDEMPOTENCY_KEY_LENGTH:
		return {"ok": false, "code": "request.idempotency_key_too_long", "reason_zh": "显式幂等键超过支持上限。", "length": idempotency_key.length(), "max_length": MAX_IDEMPOTENCY_KEY_LENGTH}
	if not idempotency_key.is_empty() and (idempotency_key.contains("NodePath") or idempotency_key.contains("res://") or idempotency_key.contains("user://")):
		return {"ok": false, "code": "request.idempotency_invalid", "reason_zh": "幂等键不得使用 NodePath 或文件路径。"}
	return {"ok": true}

func derive_instance_id(identity_epoch: int = 1, allocation_sequence: int = 0) -> String:
	var kind := "explicit" if not idempotency_key.is_empty() else "request"
	var identity_material := idempotency_key if kind == "explicit" else "%s|%d" % [request_id, allocation_sequence]
	var payload := "%s|%s|epoch:%d|%s|%s" % [INSTANCE_ID_DOMAIN, IDENTITY_VERSION, maxi(identity_epoch, 1), kind, identity_material]
	return "%s.%s.%s.%s" % [INSTANCE_ID_DOMAIN, IDENTITY_VERSION, "exp" if kind == "explicit" else "req", payload.sha256_text()]

func idempotency_contract_hash(resolved_ability_id: String = "") -> String:
	var target_contract: Dictionary = {}
	if target_data != null:
		target_contract = {
			"target_type": target_data.target_type,
			"target_business_id": target_data.target_business_id,
			"target_scene_id": target_data.target_scene_id,
			"area_id": target_data.area_id,
			"route_id": target_data.route_id,
			"location": {"x": target_data.location.x, "y": target_data.location.y},
			"payload": target_data.payload.duplicate(true),
		}
	var event_contract := event_data.duplicate(true)
	event_contract.erase("ability_instance_id")
	var contract := {
		"domain": "%s.idempotency_contract" % INSTANCE_ID_DOMAIN,
		"version": IDENTITY_VERSION,
		"ability_id": resolved_ability_id if not resolved_ability_id.is_empty() else ability_id,
		"ability_tag": ability_tag,
		"source": source,
		"target": target_contract,
		"event_data": event_contract,
		"schedule_context": schedule_context.duplicate(true),
	}
	return JSON.stringify(contract, "", true, true).sha256_text()

func idempotency_key_hash() -> String:
	return ("%s|%s|key|%s" % [INSTANCE_ID_DOMAIN, IDENTITY_VERSION, idempotency_key]).sha256_text()

func to_dict() -> Dictionary:
	return {
		"request_id": request_id,
		"ability_id": ability_id,
		"ability_tag": ability_tag,
		"source": source,
		"event_data": event_data.duplicate(true),
		"schedule_context": schedule_context.duplicate(true),
		"target_data": target_data.to_dict() if target_data != null else {},
		"host_id": host.get_instance_id() if is_instance_valid(host) else 0,
		"idempotency_key": idempotency_key,
		"causal_chain_id": causal_chain.chain_id if causal_chain != null else "",
		"created_at_usec": created_at_usec,
	}
