@tool
class_name GMAnchorReference
extends GMSceneReference

## 地图/场景锚点语义引用。anchor_id 可跨重命名和实例化保持稳定。

@export var anchor_id: String = ""
@export var anchor_kind: String = ""

func validate_definition() -> Dictionary:
	var result := super.validate_definition()
	var errors: Array = result.get("errors", []).duplicate(true) if result.get("errors", []) is Array else []
	if anchor_id.strip_edges().is_empty(): errors.append({"code": "anchor.reference_identity_missing", "reason_zh": "锚点引用缺少稳定 anchor_id。", "field": "anchor_id"})
	result["ok"] = errors.is_empty()
	result["code"] = "anchor.reference_valid" if result.ok else "anchor.reference_invalid"
	result["errors"] = errors
	result["errors_zh"] = _messages(errors)
	return result

func resolve_anchor(root: Node) -> Dictionary:
	var result := resolve(root, anchor_id)
	if not result.ok: return result
	var anchor: Node = result.get("resolved", null)
	if anchor == null: return {"ok": false, "code": "anchor.missing", "reason_zh": "锚点引用解析没有返回节点：%s。" % anchor_id, "cause_chain": [scene_business_id, anchor_id]}
	result["anchor"] = anchor
	result["anchor_id"] = anchor_id
	result["anchor_kind"] = anchor_kind
	return result

func to_dict() -> Dictionary:
	var result := super.to_dict()
	result["anchor_id"] = anchor_id
	result["anchor_kind"] = anchor_kind
	result["reference_kind"] = "GMAnchorReference"
	return result

static func _messages(errors: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for row in errors: result.append(str(row.get("reason_zh", "锚点引用无效。")))
	return result
