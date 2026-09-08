@tool
class_name GMEntityReference
extends GMSceneReference

## 场景内实体语义引用。entity_business_id 是唯一业务身份。

@export var entity_business_id: String = ""
@export var expected_entity_class: String = ""

func validate_definition() -> Dictionary:
	var result := super.validate_definition()
	var errors: Array = result.get("errors", []).duplicate(true) if result.get("errors", []) is Array else []
	if entity_business_id.strip_edges().is_empty(): errors.append({"code": "entity.reference_identity_missing", "reason_zh": "实体引用缺少稳定 entity_business_id。", "field": "entity_business_id"})
	result["ok"] = errors.is_empty()
	result["code"] = "entity.reference_valid" if result.ok else "entity.reference_invalid"
	result["errors"] = errors
	result["errors_zh"] = _messages(errors)
	return result

func resolve_entity(root: Node) -> Dictionary:
	var result := resolve(root, entity_business_id)
	if not result.ok: return result
	var entity: Node = result.get("resolved", null)
	if entity == null: return {"ok": false, "code": "entity.missing", "reason_zh": "实体引用解析没有返回实体：%s。" % entity_business_id, "cause_chain": [scene_business_id, entity_business_id]}
	if not expected_entity_class.is_empty() and not entity.is_class(expected_entity_class):
		return {"ok": false, "code": "entity.class_mismatch", "reason_zh": "实体引用类型不匹配：期望 %s，实际 %s。" % [expected_entity_class, entity.get_class()], "cause_chain": [scene_business_id, entity_business_id]}
	result["entity"] = entity
	result["entity_business_id"] = entity_business_id
	return result

func to_dict() -> Dictionary:
	var result := super.to_dict()
	result["entity_business_id"] = entity_business_id
	result["expected_entity_class"] = expected_entity_class
	result["reference_kind"] = "GMEntityReference"
	return result

static func _messages(errors: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for row in errors: result.append(str(row.get("reason_zh", "实体引用无效。")))
	return result
