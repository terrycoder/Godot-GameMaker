class_name GMSemanticSlot2D
extends RefCounted

## 历史任务包使用 GMSemanticSlot2D 这个名字；其值本身不含二维坐标，
## 只保存维度无关的语义引用。Planar3D 与 2D 共用同一字典契约。

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")

const SCHEMA_VERSION := "gm.scene.semantic_slot.v1"
const FIELDS: Array[String] = ["schema_version", "slot_id", "slot_kind", "target_ref", "required", "capacity", "tags"]
const KINDS: Array[String] = [
	"entry", "exit", "objective", "resource", "hostile", "facility", "extraction",
	"participant", "object", "region"
]

var slot_id: String
var slot_kind: String
var target_ref: Dictionary
var required: bool
var capacity: int
var tags: Array

func _init(
	p_slot_id: String = "",
	p_slot_kind: String = "object",
	p_target_ref: Dictionary = {},
	p_required: bool = true,
	p_capacity: int = 1,
	p_tags: Array = []
) -> void:
	slot_id = p_slot_id
	slot_kind = p_slot_kind
	target_ref = VALUE.duplicate_value(p_target_ref)
	required = p_required
	capacity = p_capacity
	tags = VALUE.duplicate_value(p_tags)

static func from_dict(value: Variant) -> Dictionary:
	var fields := VALUE.exact_fields(value, FIELDS)
	if not fields.ok:
		return fields
	var stable := VALUE.persistence(value)
	if not stable.ok:
		return stable
	if value.schema_version != SCHEMA_VERSION:
		return {"ok": false, "code": "scene.slot.schema", "error_zh": "SemanticSlot Schema版本不匹配。"}
	if not VALUE.stable_id(value.slot_id) or not KINDS.has(str(value.slot_kind)):
		return {"ok": false, "code": "scene.slot.identity", "error_zh": "语义插槽标识或类型无效。"}
	if typeof(value.required) != TYPE_BOOL:
		return {"ok": false, "code": "scene.slot.required_type", "error_zh": "语义插槽required必须是布尔值。"}
	var capacity_check := VALUE.integer_field(value.capacity, false)
	if not capacity_check.ok or capacity_check.value < 1:
		return {"ok": false, "code": "scene.slot.capacity", "error_zh": "语义插槽capacity必须是正整数。"}
	var ref_check := VALUE.semantic_ref(value.target_ref, true)
	if not ref_check.ok:
		return {"ok": false, "code": "scene.slot.target", "error_zh": "语义插槽目标无效。", "detail": ref_check}
	var tag_check := VALUE.string_array(value.tags, true)
	if not tag_check.ok:
		return {"ok": false, "code": "scene.slot.tags", "error_zh": "语义插槽tags必须是稳定字符串数组。", "detail": tag_check}
	var slot := GMSemanticSlot2D.new(
		str(value.slot_id), str(value.slot_kind), ref_check.get("value", VALUE.duplicate_value(value.target_ref)), bool(value.required), int(capacity_check.value), tag_check.value
	)
	return {"ok": true, "value": slot}

static func from_json(text: String) -> Dictionary:
	var parsed := VALUE.parse_json(text)
	if not parsed.ok:
		return parsed
	return from_dict(parsed.value)

func validate() -> Dictionary:
	return GMSemanticSlot2D.from_dict(to_dict())

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"slot_id": slot_id,
		"slot_kind": slot_kind,
		"target_ref": VALUE.duplicate_value(target_ref),
		"required": required,
		"capacity": capacity,
		"tags": VALUE.duplicate_value(tags)
	}

func to_json() -> String:
	return VALUE.json_string(to_dict())

func fingerprint() -> String:
	return VALUE.digest(to_dict())
