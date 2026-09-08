@tool
class_name GMSurfaceDefinition3D
extends Resource

## Authored planar surface.  The resource stores only stable semantic values;
## scene nodes, meshes and Navigation objects are adapter-owned projections.

const SCHEMA := "gm.surface_definition_3d.v1"
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const STABLE_DATA := preload("res://gm_runtime/simulation/gm_stable_data.gd")

const SURFACE_KINDS := ["courtyard", "floor", "bridge"]
const DEFAULT_PROFILE := "default"
const EPSILON := 0.0001
const NATIVE_FIELDS := ["schema", "schema_version", "surface_id", "map_id", "surface_kind", "display_name_zh", "boundary", "world_origin", "height_slope", "walkable", "agent_profiles", "semantic_region_id", "max_slope_degrees"]
const ORIGIN_FIELDS := ["x", "y", "z"]
const SLOPE_FIELDS := ["x", "y"]
const POINT_FIELDS := ["x", "y"]

@export var surface_id: StringName = &""
@export var map_id: StringName = &""
@export_enum("courtyard", "floor", "bridge") var surface_kind: String = "floor"
@export var display_name_zh: String = ""
@export var boundary: PackedVector2Array = PackedVector2Array()
@export var world_origin_x: float = 0.0
@export var world_origin_y: float = 0.0
@export var world_origin_z: float = 0.0
@export var height_slope_x: float = 0.0
@export var height_slope_y: float = 0.0
@export var walkable: bool = true
@export var agent_profiles: PackedStringArray = PackedStringArray([DEFAULT_PROFILE])
@export var semantic_region_id: StringName = &""
@export_range(0.0, 89.0, 0.1) var max_slope_degrees: float = 45.0

func validate() -> Dictionary:
	var errors: Array[Dictionary] = []
	if not PLANAR_POSITION.is_valid_stable_id(str(surface_id)) or str(surface_id).is_empty():
		errors.append(_error("surface.id_invalid", "Surface必须是非空稳定ID。", "surface_id"))
	if not PLANAR_POSITION.is_valid_stable_id(str(map_id)) or str(map_id).is_empty():
		errors.append(_error("surface.map_id_invalid", "Surface必须引用非空稳定地图ID。", "map_id"))
	if surface_kind not in SURFACE_KINDS:
		errors.append(_error("surface.kind_invalid", "Surface类型必须是院子、一层/楼层或桥面。", "surface_kind"))
	if boundary.size() < 3:
		errors.append(_error("surface.boundary_too_small", "Surface边界至少需要三个点。", "boundary"))
	elif absf(_signed_area(boundary)) <= EPSILON:
		errors.append(_error("surface.boundary_degenerate", "Surface边界面积不能为零。", "boundary"))
	elif _has_self_intersection():
		errors.append(_error("surface.boundary_self_intersection", "Surface边界不能自交。", "boundary"))
	for index in boundary.size():
		var point := boundary[index]
		if not is_finite(point.x) or not is_finite(point.y):
			errors.append(_error("surface.boundary_nonfinite", "Surface边界坐标必须是有限数值。", "boundary[%d]" % index))
	if not _finite(world_origin_x) or not _finite(world_origin_y) or not _finite(world_origin_z):
		errors.append(_error("surface.origin_nonfinite", "Surface世界原点必须是有限数值。", "world_origin"))
	if not _finite(height_slope_x) or not _finite(height_slope_y):
		errors.append(_error("surface.slope_nonfinite", "Surface高度斜率必须是有限数值。", "height_slope"))
	if not _finite(max_slope_degrees) or max_slope_degrees < 0.0 or max_slope_degrees >= 90.0:
		errors.append(_error("surface.slope_limit_invalid", "Surface最大坡度必须在0到89度之间。", "max_slope_degrees"))
	var profiles: Dictionary = {}
	for raw_profile in agent_profiles:
		var profile := str(raw_profile).strip_edges()
		if profile.is_empty() or not PLANAR_POSITION.is_valid_stable_id(profile):
			errors.append(_error("surface.agent_profile_invalid", "Surface Agent Profile必须是稳定ID。", "agent_profiles"))
		elif profiles.has(profile):
			errors.append(_error("surface.agent_profile_duplicate", "Surface Agent Profile不能重复：%s" % profile, "agent_profiles"))
		else:
			profiles[profile] = true
	if profiles.is_empty():
		errors.append(_error("surface.agent_profile_missing", "Surface至少需要一个Agent Profile。", "agent_profiles"))
	if not str(semantic_region_id).is_empty() and not PLANAR_POSITION.is_valid_stable_id(str(semantic_region_id)):
		errors.append(_error("surface.region_id_invalid", "Surface语义区域ID无效。", "semantic_region_id"))
	return {"ok": errors.is_empty(), "code": "surface.valid" if errors.is_empty() else "surface.invalid", "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh), "surface_id": str(surface_id), "map_id": str(map_id)}

func contains_logical(point: Vector2) -> bool:
	return boundary.size() >= 3 and Geometry2D.is_point_in_polygon(point, boundary)

func world_height_at(point: Vector2) -> float:
	return world_origin_y + height_slope_x * point.x + height_slope_y * point.y

func logical_to_world(point: Vector2) -> Vector3:
	return Vector3(world_origin_x + point.x, world_height_at(point), world_origin_z + point.y)

func world_to_logical(point: Vector3) -> Vector2:
	return Vector2(point.x - world_origin_x, point.z - world_origin_z)

func slope_degrees() -> float:
	return rad_to_deg(atan(sqrt(height_slope_x * height_slope_x + height_slope_y * height_slope_y)))

func supports_agent(agent_profile: String = DEFAULT_PROFILE) -> bool:
	var normalized := agent_profile.strip_edges()
	return walkable and (agent_profiles.has(normalized) or (normalized.is_empty() and agent_profiles.has(DEFAULT_PROFILE)))

func to_native() -> Dictionary:
	var points: Array = []
	for point in boundary: points.append({"x": point.x, "y": point.y})
	return {
		"schema": SCHEMA,
		"schema_version": 1,
		"surface_id": str(surface_id),
		"map_id": str(map_id),
		"surface_kind": surface_kind,
		"display_name_zh": display_name_zh,
		"boundary": points,
		"world_origin": {"x": world_origin_x, "y": world_origin_y, "z": world_origin_z},
		"height_slope": {"x": height_slope_x, "y": height_slope_y},
		"walkable": walkable,
		"agent_profiles": Array(agent_profiles),
		"semantic_region_id": str(semantic_region_id),
		"max_slope_degrees": max_slope_degrees,
	}

static func from_native(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("surface.native_type_invalid", "Surface纯值必须是Dictionary。")
	var source: Dictionary = value
	var shape := _validate_native_fields(source, NATIVE_FIELDS, "surface")
	if not shape.ok: return shape
	if str(source.get("schema", "")) != SCHEMA:
		return _failure("surface.schema_invalid", "Surface Schema标识无效。")
	var schema_version := STABLE_DATA.normalize_schema_version(source.get("schema_version"))
	if not schema_version.ok:
		return _failure("surface.schema_version_invalid", "Surface Schema版本必须是整数1。")
	var surface := GMSurfaceDefinition3D.new()
	surface.surface_id = str(source.get("surface_id", ""))
	surface.map_id = str(source.get("map_id", ""))
	surface.surface_kind = str(source.get("surface_kind", "floor"))
	surface.display_name_zh = str(source.get("display_name_zh", ""))
	var raw_boundary: Variant = source.get("boundary", [])
	if not raw_boundary is Array:
		return _failure("surface.boundary_invalid", "Surface边界必须是数组。")
	for raw_point in raw_boundary:
		if not raw_point is Dictionary:
			return _failure("surface.boundary_invalid", "Surface边界点必须是Dictionary。")
		var point_shape := _validate_native_fields(raw_point, POINT_FIELDS, "surface.boundary")
		if not point_shape.ok: return point_shape
		surface.boundary.append(Vector2(float(raw_point.get("x")), float(raw_point.get("y"))))
	if not source.get("world_origin") is Dictionary:
		return _failure("surface.world_origin_invalid", "Surface world_origin必须是包含x/y/z的Dictionary。")
	var origin: Dictionary = source.get("world_origin")
	var origin_shape := _validate_native_fields(origin, ORIGIN_FIELDS, "surface.world_origin")
	if not origin_shape.ok: return origin_shape
	surface.world_origin_x = float(origin.get("x", 0.0))
	surface.world_origin_y = float(origin.get("y", 0.0))
	surface.world_origin_z = float(origin.get("z", 0.0))
	if not source.get("height_slope") is Dictionary:
		return _failure("surface.height_slope_invalid", "Surface height_slope必须是包含x/y的Dictionary。")
	var slope: Dictionary = source.get("height_slope")
	var slope_shape := _validate_native_fields(slope, SLOPE_FIELDS, "surface.height_slope")
	if not slope_shape.ok: return slope_shape
	surface.height_slope_x = float(slope.get("x", 0.0))
	surface.height_slope_y = float(slope.get("y", 0.0))
	surface.walkable = bool(source.get("walkable", true))
	if not source.get("agent_profiles") is Array and not source.get("agent_profiles") is PackedStringArray:
		return _failure("surface.agent_profiles_invalid", "Surface agent_profiles必须是数组。")
	surface.agent_profiles = PackedStringArray(source.get("agent_profiles", [DEFAULT_PROFILE]))
	surface.semantic_region_id = str(source.get("semantic_region_id", ""))
	surface.max_slope_degrees = float(source.get("max_slope_degrees", 45.0))
	var validation := surface.validate()
	if not validation.ok: return validation
	return {"ok": true, "surface": surface, "value": surface.to_native()}

func copy_surface() -> GMSurfaceDefinition3D:
	return duplicate(true) as GMSurfaceDefinition3D

static func rectangle(p_surface_id: String, p_map_id: String, p_kind: String, p_origin: Vector3, p_size: Vector2, p_profiles: PackedStringArray = PackedStringArray([DEFAULT_PROFILE])) -> GMSurfaceDefinition3D:
	var surface := GMSurfaceDefinition3D.new()
	surface.surface_id = p_surface_id
	surface.map_id = p_map_id
	surface.surface_kind = p_kind
	surface.display_name_zh = p_surface_id
	surface.boundary = PackedVector2Array([Vector2.ZERO, Vector2(p_size.x, 0.0), p_size, Vector2(0.0, p_size.y)])
	surface.world_origin_x = p_origin.x
	surface.world_origin_y = p_origin.y
	surface.world_origin_z = p_origin.z
	surface.agent_profiles = p_profiles
	return surface

func _error(code: String, message: String, field: String) -> Dictionary:
	return {"code": code, "error_zh": message, "field": field, "surface_id": str(surface_id), "map_id": str(map_id)}

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

static func _finite(value: float) -> bool:
	return is_finite(value)

func _signed_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5

func _has_self_intersection() -> bool:
	for index in boundary.size():
		var next := (index + 1) % boundary.size()
		for other in range(index + 1, boundary.size()):
			var other_next := (other + 1) % boundary.size()
			if index == other or next == other or index == other_next: continue
			if _segments_intersect(boundary[index], boundary[next], boundary[other], boundary[other_next]): return true
	return false

static func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab := b - a
	var cd := d - c
	var denominator := ab.cross(cd)
	if is_zero_approx(denominator): return false
	var ac := c - a
	var t := ac.cross(cd) / denominator
	var u := ac.cross(ab) / denominator
	return t > 0.00001 and t < 0.99999 and u > 0.00001 and u < 0.99999
