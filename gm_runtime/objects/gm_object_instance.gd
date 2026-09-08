@tool
class_name GMObjectInstance
extends Node2D

const ID_DOMAIN := "gm.object.instance.v1"
static var _sequence := 0

@export var definition: GMObjectDefinition
@export var stable_instance_id: String = ""
@export var map_id: StringName
@export var object_state: Dictionary = {}
@export var persistent: bool = true

func ensure_identity(p_map_id: String, allocation_hint: String = "") -> Dictionary:
	if p_map_id.strip_edges().is_empty(): return _failure("object.map_id_missing", "对象实例缺少任务08/09地图稳定ID。")
	if stable_instance_id.is_empty():
		_sequence += 1
		var material := "%s|%s|%s|%d|%d" % [ID_DOMAIN, p_map_id, allocation_hint, Time.get_ticks_usec(), _sequence]
		stable_instance_id = "%s.%s" % [ID_DOMAIN, material.sha256_text()]
	map_id = StringName(p_map_id)
	return {"ok": true, "stable_instance_id": stable_instance_id, "map_id": str(map_id)}

func regenerate_identity_for_copy(target_map_id: String = "") -> Dictionary:
	stable_instance_id = ""
	return ensure_identity(target_map_id if not target_map_id.is_empty() else str(map_id), "copy")

func move_to_map(target_map_id: String) -> Dictionary:
	if target_map_id.strip_edges().is_empty(): return _failure("object.map_id_missing", "跨地图移动目标缺少稳定地图ID。")
	var before := stable_instance_id
	map_id = StringName(target_map_id)
	return {"ok": true, "stable_instance_id": stable_instance_id, "identity_preserved": before == stable_instance_id, "map_id": str(map_id)}

func state_snapshot() -> Dictionary:
	return {"stable_instance_id": stable_instance_id, "map_id": str(map_id), "definition_id": definition.content_id if definition != null else "", "persistent": persistent, "object_state": object_state.duplicate(true), "position": {"x": position.x, "y": position.y}}

func prepare_state(snapshot: Dictionary) -> Dictionary:
	var stable_check := _required_text_field(snapshot, "stable_instance_id", "object.save_identity_missing")
	if not stable_check.ok: return stable_check
	var map_check := _required_text_field(snapshot, "map_id", "object.save_map_id_missing")
	if not map_check.ok: return map_check
	var definition_check := _required_text_field(snapshot, "definition_id", "object.save_definition_id_missing")
	if not definition_check.ok: return definition_check
	if definition != null and str(definition.content_id) != str(definition_check.value):
		return _failure("object.save_definition_mismatch", "保存数据的对象定义ID与活动实例不一致。", {"field": "definition_id", "expected": definition.content_id, "actual": definition_check.value})
	if not snapshot.has("persistent") or typeof(snapshot.get("persistent")) != TYPE_BOOL:
		return _field_type_failure("persistent", "bool", snapshot.get("persistent", null))
	if not snapshot.has("object_state") or not snapshot.get("object_state") is Dictionary:
		return _field_type_failure("object_state", "Dictionary", snapshot.get("object_state", null))
	if not snapshot.has("position") or not snapshot.get("position") is Dictionary:
		return _field_type_failure("position", "Dictionary", snapshot.get("position", null))
	var saved_position: Dictionary = snapshot.get("position")
	for axis in ["x", "y"]:
		if not saved_position.has(axis) or typeof(saved_position.get(axis)) not in [TYPE_INT, TYPE_FLOAT]:
			return _field_type_failure("position.%s" % axis, "number", saved_position.get(axis, null))
		if not is_finite(float(saved_position.get(axis))):
			return _failure("object.save_position_non_finite", "保存数据的位置字段不是有限数值。", {"field": "position.%s" % axis})
	var restored_position := Vector2(float(saved_position.x), float(saved_position.y))
	var restored_state: Dictionary = snapshot.get("object_state").duplicate(true)
	return {"ok": true, "prepared": {"stable_instance_id": str(stable_check.value), "map_id": str(map_check.value), "persistent": snapshot.get("persistent"), "object_state": restored_state, "position": restored_position}}

func commit_prepared_state(prepared: Dictionary) -> Dictionary:
	# No live value is written until every required persisted field is valid.
	stable_instance_id = str(prepared.get("stable_instance_id", ""))
	map_id = StringName(str(prepared.get("map_id", "")))
	persistent = bool(prepared.get("persistent", false))
	object_state = prepared.get("object_state", {}).duplicate(true)
	position = prepared.get("position", Vector2.ZERO)
	return {"ok": true, "stable_instance_id": stable_instance_id}

func restore_state(snapshot: Dictionary) -> Dictionary:
	var prepared := prepare_state(snapshot)
	if not prepared.ok: return prepared
	return commit_prepared_state(prepared.prepared)

func _required_text_field(snapshot: Dictionary, field: String, missing_code: String) -> Dictionary:
	if not snapshot.has(field): return _failure(missing_code, "保存数据缺少必需稳定身份字段：%s。" % field, {"field": field, "issue": "missing"})
	var value: Variant = snapshot.get(field)
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]: return _field_type_failure(field, "String", value)
	var raw := str(value)
	var normalized := raw.strip_edges()
	if normalized.is_empty(): return _failure(missing_code, "保存数据的必需稳定身份字段为空：%s。" % field, {"field": field, "issue": "empty"})
	if normalized != raw: return _failure("object.save_field_format_invalid", "保存数据的稳定身份字段含首尾空白：%s。" % field, {"field": field, "issue": "surrounding_whitespace"})
	return {"ok": true, "value": raw}

func _field_type_failure(field: String, expected: String, actual: Variant) -> Dictionary:
	return _failure("object.save_field_type_invalid", "保存数据字段类型无效：%s。" % field, {"field": field, "expected": expected, "actual_type": type_string(typeof(actual))})

func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "error_zh": message}
	result.merge(details, true)
	return result
