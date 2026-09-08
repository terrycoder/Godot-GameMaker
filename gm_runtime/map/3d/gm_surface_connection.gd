@tool
class_name GMSurfaceConnection
extends Resource

const SCHEMA := "gm.surface_connection.v1"
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const STABLE_DATA := preload("res://gm_runtime/simulation/gm_stable_data.gd")
const CONNECTION_KINDS := ["stairs", "ramp", "bridge", "portal", "door", "lift_reserved"]
const NATIVE_FIELDS := ["schema", "schema_version", "connection_id", "source_map_id", "source_surface_id", "target_map_id", "target_surface_id", "connection_kind", "direction", "bidirectional", "source_exit", "target_entry", "agent_profiles", "traversal_cost", "required_ability_id", "enabled"]
const POINT_FIELDS := ["x", "y"]

@export var connection_id: StringName = &""
@export var source_map_id: StringName = &""
@export var source_surface_id: StringName = &""
@export var target_map_id: StringName = &""
@export var target_surface_id: StringName = &""
@export_enum("stairs", "ramp", "bridge", "portal", "door", "lift_reserved") var connection_kind: String = "stairs"
@export_enum("source_to_target", "target_to_source") var direction: String = "source_to_target"
@export var bidirectional: bool = true
@export var source_exit: Vector2 = Vector2.ZERO
@export var target_entry: Vector2 = Vector2.ZERO
@export var agent_profiles: PackedStringArray = PackedStringArray(["default"])
@export_range(0.01, 100000.0, 0.01) var traversal_cost: float = 1.0
@export var required_ability_id: StringName = &""
@export var enabled: bool = true

func validate() -> Dictionary:
	var errors: Array[Dictionary] = []
	for pair in [["connection_id", connection_id], ["source_map_id", source_map_id], ["source_surface_id", source_surface_id], ["target_map_id", target_map_id], ["target_surface_id", target_surface_id]]:
		var value := str(pair[1])
		if value.is_empty() or not PLANAR_POSITION.is_valid_stable_id(value): errors.append(_error("connection.field_invalid", "连接字段必须是非空稳定ID：%s" % pair[0], str(pair[0])))
	if connection_kind not in CONNECTION_KINDS: errors.append(_error("connection.kind_invalid", "连接类型不受支持。", "connection_kind"))
	if direction not in ["source_to_target", "target_to_source"]: errors.append(_error("connection.direction_invalid", "连接方向无效。", "direction"))
	if not _finite(source_exit.x) or not _finite(source_exit.y) or not _finite(target_entry.x) or not _finite(target_entry.y): errors.append(_error("connection.endpoint_nonfinite", "连接出口坐标必须是有限数值。", "endpoint"))
	if not _finite(traversal_cost) or traversal_cost <= 0.0: errors.append(_error("connection.cost_invalid", "连接代价必须是正的有限数值。", "traversal_cost"))
	var profiles: Dictionary = {}
	for raw_profile in agent_profiles:
		var profile := str(raw_profile).strip_edges()
		if profile.is_empty() or not PLANAR_POSITION.is_valid_stable_id(profile): errors.append(_error("connection.agent_profile_invalid", "连接Agent Profile必须是稳定ID。", "agent_profiles"))
		elif profiles.has(profile): errors.append(_error("connection.agent_profile_duplicate", "连接Agent Profile不能重复：%s" % profile, "agent_profiles"))
		else: profiles[profile] = true
	if profiles.is_empty(): errors.append(_error("connection.agent_profile_missing", "连接至少需要一个Agent Profile。", "agent_profiles"))
	if not str(required_ability_id).is_empty() and not PLANAR_POSITION.is_valid_stable_id(str(required_ability_id)):
		errors.append(_error("connection.ability_invalid", "连接所需能力ID无效。", "required_ability_id"))
	return {"ok": errors.is_empty(), "code": "connection.valid" if errors.is_empty() else "connection.invalid", "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh), "connection_id": str(connection_id)}

func supports_agent(agent_profile: String = "default") -> bool:
	return enabled and agent_profiles.has(agent_profile.strip_edges())

func matches_forward(from_map: String, from_surface: String, to_map: String, to_surface: String) -> bool:
	return from_map == str(source_map_id) and from_surface == str(source_surface_id) and to_map == str(target_map_id) and to_surface == str(target_surface_id)

func allows(from_map: String, from_surface: String, to_map: String, to_surface: String, agent_profile: String = "default") -> bool:
	if not supports_agent(agent_profile): return false
	var forward := matches_forward(from_map, from_surface, to_map, to_surface)
	var reverse := matches_forward(to_map, to_surface, from_map, from_surface)
	if direction == "target_to_source":
		return reverse or (bidirectional and forward)
	return forward or (bidirectional and reverse)

func endpoint_for(from_map: String, from_surface: String, to_map: String, to_surface: String) -> Dictionary:
	if matches_forward(from_map, from_surface, to_map, to_surface):
		return {"ok": true, "source": source_exit, "target": target_entry, "direction": "source_to_target"}
	if bidirectional and matches_forward(to_map, to_surface, from_map, from_surface):
		return {"ok": true, "source": target_entry, "target": source_exit, "direction": "target_to_source"}
	return {"ok": false, "code": "connection.direction_blocked", "error_zh": "连接方向不允许当前行程。"}

func to_native() -> Dictionary:
	return {
		"schema": SCHEMA,
		"schema_version": 1,
		"connection_id": str(connection_id),
		"source_map_id": str(source_map_id),
		"source_surface_id": str(source_surface_id),
		"target_map_id": str(target_map_id),
		"target_surface_id": str(target_surface_id),
		"connection_kind": connection_kind,
		"direction": direction,
		"bidirectional": bidirectional,
		"source_exit": {"x": source_exit.x, "y": source_exit.y},
		"target_entry": {"x": target_entry.x, "y": target_entry.y},
		"agent_profiles": Array(agent_profiles),
		"traversal_cost": traversal_cost,
		"required_ability_id": str(required_ability_id),
		"enabled": enabled,
	}

static func from_native(value: Variant) -> Dictionary:
	if not value is Dictionary: return _failure("connection.native_type_invalid", "连接纯值必须是Dictionary。")
	var source: Dictionary = value
	var shape := _validate_native_fields(source, NATIVE_FIELDS, "connection")
	if not shape.ok: return shape
	if str(source.get("schema", "")) != SCHEMA:
		return _failure("connection.schema_invalid", "连接 Schema标识无效。")
	var schema_version := STABLE_DATA.normalize_schema_version(source.get("schema_version"))
	if not schema_version.ok:
		return _failure("connection.schema_version_invalid", "连接 Schema版本必须是整数1。")
	var connection := GMSurfaceConnection.new()
	connection.connection_id = str(source.get("connection_id", ""))
	connection.source_map_id = str(source.get("source_map_id", ""))
	connection.source_surface_id = str(source.get("source_surface_id", ""))
	connection.target_map_id = str(source.get("target_map_id", ""))
	connection.target_surface_id = str(source.get("target_surface_id", ""))
	connection.connection_kind = str(source.get("connection_kind", "stairs"))
	connection.direction = str(source.get("direction", "source_to_target"))
	connection.bidirectional = bool(source.get("bidirectional", true))
	if not source.get("source_exit") is Dictionary or not source.get("target_entry") is Dictionary:
		return _failure("connection.endpoint_invalid", "连接出口必须是包含x/y的Dictionary。")
	var source_shape := _validate_native_fields(source.get("source_exit"), POINT_FIELDS, "connection.source_exit")
	if not source_shape.ok: return source_shape
	var target_shape := _validate_native_fields(source.get("target_entry"), POINT_FIELDS, "connection.target_entry")
	if not target_shape.ok: return target_shape
	connection.source_exit = _vector2(source.get("source_exit"))
	connection.target_entry = _vector2(source.get("target_entry"))
	if not source.get("agent_profiles") is Array and not source.get("agent_profiles") is PackedStringArray:
		return _failure("connection.agent_profiles_invalid", "连接 agent_profiles必须是数组。")
	connection.agent_profiles = PackedStringArray(source.get("agent_profiles", ["default"]))
	connection.traversal_cost = float(source.get("traversal_cost", 1.0))
	connection.required_ability_id = str(source.get("required_ability_id", ""))
	connection.enabled = bool(source.get("enabled", true))
	var validation := connection.validate()
	if not validation.ok: return validation
	return {"ok": true, "connection": connection, "value": connection.to_native()}

func copy_connection() -> GMSurfaceConnection:
	return duplicate(true) as GMSurfaceConnection

func _error(code: String, message: String, field: String) -> Dictionary:
	return {"code": code, "error_zh": message, "field": field, "connection_id": str(connection_id)}

static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": message}

static func _validate_native_fields(source: Dictionary, expected: Array, label: String) -> Dictionary:
	for field in expected:
		if not source.has(field):
			return _failure("%s.schema_field_missing" % label, "%s缺少必需字段：%s。" % [label, field])
	for raw_key in source.keys():
		if not expected.has(str(raw_key)):
			return _failure("%s.schema_field_unknown" % label, "%s包含未知字段：%s。" % [label, raw_key])
	return {"ok": true}

static func _vector2(value: Variant) -> Vector2:
	if value is Dictionary: return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	if value is Vector2: return value
	return Vector2(INF, INF)

static func _finite(value: float) -> bool:
	return is_finite(value)
