@tool
class_name GMSemanticAnchor
extends Resource

@export var anchor_id: StringName
@export var anchor_type_id: StringName = &"gm.anchor_type.interaction"
@export var position: Vector2
## Optional explicit Surface selector used by Planar 3D.  Legacy 2D anchors
## leave this empty; 3D resolution fails closed when a Surface is ambiguous.
@export var surface_id: String = ""
@export var facing_degrees: float = 0.0
@export_range(1, 1024, 1) var capacity: int = 1
@export var occupants: Array[String] = []
@export var tags: PackedStringArray = PackedStringArray()
@export var editor_label: String = ""

func validate_definition() -> Dictionary:
	var errors: Array[Dictionary] = []
	if str(anchor_id).strip_edges().is_empty(): errors.append(_error("semantic.anchor_id_missing", "锚点稳定ID不能为空", "anchor_id"))
	if str(anchor_type_id).strip_edges().is_empty(): errors.append(_error("semantic.anchor_type_missing", "锚点类型ID不能为空", "anchor_type_id"))
	if capacity < 1: errors.append(_error("semantic.anchor_capacity_invalid", "锚点容量必须至少为1", "capacity"))
	var seen := {}
	for occupant in occupants:
		if seen.has(occupant): errors.append(_error("semantic.anchor_duplicate_occupancy", "锚点存在重复占用：%s" % occupant, "occupants"))
		seen[occupant] = true
	if occupants.size() > capacity: errors.append(_error("semantic.anchor_capacity_insufficient", "锚点容量不足：%d/%d" % [occupants.size(), capacity], "occupants"))
	return {"ok": errors.is_empty(), "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh), "anchor_id": str(anchor_id)}

func try_occupy(entity_id: String) -> Dictionary:
	if entity_id.strip_edges().is_empty(): return _error_result("semantic.anchor_occupant_missing", "占用实体ID不能为空")
	if occupants.has(entity_id): return _error_result("semantic.anchor_duplicate_occupancy", "实体已占用该锚点：%s" % entity_id)
	if occupants.size() >= capacity: return {"ok": false, "code": "semantic.anchor_capacity_insufficient", "error_zh": "锚点容量不足：%s" % anchor_id, "anchor_id": str(anchor_id), "capacity": capacity, "occupied": occupants.size()}
	occupants.append(entity_id)
	return {"ok": true, "anchor_id": str(anchor_id), "occupant_id": entity_id, "remaining": capacity - occupants.size()}

func release(entity_id: String) -> Dictionary:
	if not occupants.has(entity_id): return _error_result("semantic.anchor_occupant_missing", "实体未占用该锚点：%s" % entity_id)
	occupants.erase(entity_id)
	return {"ok": true, "anchor_id": str(anchor_id), "occupant_id": entity_id}

func _error(code: String, message: String, field: String) -> Dictionary:
	return {"code": code, "error_zh": message, "field": field, "object_id": str(anchor_id)}

func _error_result(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": message, "anchor_id": str(anchor_id)}
