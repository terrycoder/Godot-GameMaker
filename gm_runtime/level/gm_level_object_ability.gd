extends RefCounted

## P24 统一对象能力请求。
##
## 门、箱子、机制、传送、检查点、复活、撤离与生成都经过这一种请求值；
## 它只描述请求，不自行执行、不写 Task/World/Inventory/Store。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")

const SCHEMA_VERSION := "gm.level.object_ability.v1"
const OPERATIONS: Array[String] = [
	"open", "close", "unlock", "activate", "deactivate", "teleport", "scene_switch",
	"save_checkpoint", "checkpoint", "revive", "extract", "fail_return", "generate"
]
const FIELDS: Array[String] = [
	"schema_version", "request_id", "ability_id", "actor_ref", "object_ref", "operation", "payload", "idempotency_key"
]

var request_id: String
var ability_id: String
var actor_ref: Dictionary
var object_ref: Dictionary
var operation: String
var payload: Dictionary
var idempotency_key: String

func _init(
	p_request_id: String = "",
	p_ability_id: String = "",
	p_actor_ref: Dictionary = {},
	p_object_ref: Dictionary = {},
	p_operation: String = "",
	p_payload: Dictionary = {},
	p_idempotency_key: String = ""
) -> void:
	request_id = p_request_id
	ability_id = p_ability_id
	actor_ref = VALUE.duplicate_value(p_actor_ref)
	object_ref = VALUE.duplicate_value(p_object_ref)
	operation = p_operation
	payload = VALUE.duplicate_value(p_payload)
	idempotency_key = p_idempotency_key if not p_idempotency_key.is_empty() else p_request_id

static func make(
	p_request_id: String,
	p_ability_id: String,
	p_actor_ref: Dictionary,
	p_object_ref: Dictionary,
	p_operation: String,
	p_payload: Dictionary = {},
	p_idempotency_key: String = ""
)-> RefCounted:
	return load("res://gm_runtime/level/gm_level_object_ability.gd").new(p_request_id, p_ability_id, p_actor_ref, p_object_ref, p_operation, p_payload, p_idempotency_key)

static func from_dict(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var stable := VALUE.persistence(value)
	if not stable.ok:
		return {"ok": false, "code": "level_object.ability.persistence", "error_zh": "对象能力请求必须是可持久化纯值。", "detail": stable}
	if _contains_direct_write_marker(value):
		return {"ok": false, "code": "level_object.ability.direct_write", "error_zh": "对象能力请求不得声明直接写入领域状态。"}
	if str(value.get("schema_version", "")) != SCHEMA_VERSION:
		return {"ok": false, "code": "level_object.ability.schema", "error_zh": "对象能力请求Schema版本不匹配。"}
	for identity in ["request_id", "ability_id", "operation", "idempotency_key"]:
		if not VALUE.stable_id(value.get(identity, ""), false):
			return {"ok": false, "code": "level_object.ability.identity", "error_zh": "对象能力请求包含非法稳定标识。", "field": identity}
	if not OPERATIONS.has(str(value.operation)):
		return {"ok": false, "code": "level_object.ability.operation", "error_zh": "对象能力操作不在P24通用合同内。", "operation": str(value.operation)}
	var actor_check := VALUE.semantic_ref(value.actor_ref, false)
	if not actor_check.ok:
		return {"ok": false, "code": "level_object.ability.actor", "error_zh": "对象能力请求actor引用无效。", "detail": actor_check}
	var object_check := VALUE.semantic_ref(value.object_ref, false)
	if not object_check.ok:
		return {"ok": false, "code": "level_object.ability.object", "error_zh": "对象能力请求object引用无效。", "detail": object_check}
	if str(object_check.value.get("type", "")) != "level_object":
		return {"ok": false, "code": "level_object.ability.object_type", "error_zh": "对象能力请求必须指向level_object语义引用。"}
	if typeof(value.payload) != TYPE_DICTIONARY or not VALUE.persistence(value.payload).ok:
		return {"ok": false, "code": "level_object.ability.payload", "error_zh": "对象能力载荷必须是可持久化纯字典。"}
	if str(value.idempotency_key) != str(value.get("idempotency_key", "")):
		return {"ok": false, "code": "level_object.ability.key", "error_zh": "对象能力幂等键无效。"}
	var ability = load("res://gm_runtime/level/gm_level_object_ability.gd").new(
		str(value.request_id), str(value.ability_id), actor_check.value, object_check.value,
		str(value.operation), value.payload, str(value.idempotency_key)
	)
	return {"ok": true, "value": ability}

static func from_json(text: String) -> Dictionary:
	var parsed := VALUE.parse_json(text)
	if not parsed.ok:
		return parsed
	return from_dict(parsed.value)

static func _contains_direct_write_marker(value: Variant) -> bool:
	if value is Array:
		for item in value:
			if _contains_direct_write_marker(item):
				return true
		return false
	if value is Dictionary:
		for key in value.keys():
			var name := str(key).to_lower()
			if name in ["direct_world_write", "direct_task_write", "direct_store_write", "direct_transaction_write", "scene_tree_mutation"] and bool(value[key]):
				return true
			if _contains_direct_write_marker(value[key]):
				return true
	return false

func validate() -> Dictionary:
	return load("res://gm_runtime/level/gm_level_object_ability.gd").from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"request_id": request_id,
		"ability_id": ability_id,
		"actor_ref": VALUE.duplicate_value(actor_ref),
		"object_ref": VALUE.duplicate_value(object_ref),
		"operation": operation,
		"payload": VALUE.duplicate_value(payload),
		"idempotency_key": idempotency_key
	}

func to_json() -> String:
	return VALUE.json_string(to_dict())

func fingerprint() -> String:
	return VALUE.digest(to_dict())
