class_name GMSpatialBackendCapabilities
extends RefCounted

const SCHEMA_VERSION := 1
const RESOLVE_TARGET := "gm.spatial.capability.resolve_target"
const LOGICAL_TO_WORLD := "gm.spatial.capability.logical_to_world"
const WORLD_TO_LOGICAL := "gm.spatial.capability.world_to_logical"
const PLANAR_DISTANCE := "gm.spatial.capability.planar_distance"
const PLANAR_DIRECTION := "gm.spatial.capability.planar_direction"
const TRAVEL_COST := "gm.spatial.capability.travel_cost"
const FIND_SURFACE := "gm.spatial.capability.find_surface"
const GROUND_HEIGHT := "gm.spatial.capability.ground_height"
const VALIDATE_WALKABLE_POSITION := "gm.spatial.capability.validate_walkable_position"
const IS_REACHABLE := "gm.spatial.capability.is_reachable"
const REQUEST_PATH := "gm.spatial.capability.request_path"
const SCREEN_TO_WORLD := "gm.spatial.capability.screen_to_world"
const WORLD_TO_SCREEN := "gm.spatial.capability.world_to_screen"
const SNAP_TO_SURFACE := "gm.spatial.capability.snap_to_surface"
const FIND_NEAREST_SURFACE := "gm.spatial.capability.find_nearest_surface"

const ALL_KNOWN := [
	RESOLVE_TARGET,
	LOGICAL_TO_WORLD,
	WORLD_TO_LOGICAL,
	PLANAR_DISTANCE,
	PLANAR_DIRECTION,
	TRAVEL_COST,
	FIND_SURFACE,
	GROUND_HEIGHT,
	VALIDATE_WALKABLE_POSITION,
	IS_REACHABLE,
	REQUEST_PATH,
	SCREEN_TO_WORLD,
	WORLD_TO_SCREEN,
	SNAP_TO_SURFACE,
	FIND_NEAREST_SURFACE,
]

var _domain_id := ""
var _supported := PackedStringArray()

func _init(domain_id: String = "", supported: PackedStringArray = PackedStringArray()) -> void:
	_domain_id = domain_id
	_supported = PackedStringArray()
	for capability_id in supported:
		if not _supported.has(str(capability_id)): _supported.append(str(capability_id))
	_supported.sort()

func query(capability_id: String) -> Dictionary:
	var domain := GMSpatialDomain.validate_id(_domain_id)
	if not domain.ok:
		return GMSpatialQueryResult.blocked("spatial.capability.domain_invalid", "后端空间域声明无效。", _domain_id, capability_id)
	if not domain.get("execution_available", false):
		return GMSpatialQueryResult.blocked("spatial.capability.domain_unavailable", "该空间域当前只有稳定ID，尚无可用执行后端：%s" % _domain_id, _domain_id, capability_id)
	if not _supported.has(capability_id):
		return GMSpatialQueryResult.blocked("spatial.capability.unsupported", "当前后端不支持请求的空间能力：%s" % capability_id, _domain_id, capability_id)
	return {"ok": true, "schema_version": SCHEMA_VERSION, "domain_id": _domain_id, "capability_id": capability_id, "supported": true}

func supports(capability_id: String) -> bool:
	return _supported.has(capability_id) and GMSpatialDomain.is_execution_available(_domain_id)

func domain_id() -> String:
	return _domain_id

func supported() -> PackedStringArray:
	return _supported.duplicate()

func validate() -> Dictionary:
	var errors: Array[String] = []
	var domain := GMSpatialDomain.validate_id(_domain_id)
	if not domain.ok: errors.append("空间能力域无效：%s" % _domain_id)
	var seen: Dictionary = {}
	for capability_id in _supported:
		var text := str(capability_id)
		if text.strip_edges().is_empty() or text != text.strip_edges() or not text.begins_with("gm.spatial.capability."):
			errors.append("空间能力ID无效：%s" % text)
		elif seen.has(text):
			errors.append("空间能力ID重复：%s" % text)
		else: seen[text] = true
	return {"ok": errors.is_empty(), "code": "spatial.capabilities_valid" if errors.is_empty() else "spatial.capabilities_invalid", "errors_zh": errors}

static func from_native(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "code": "spatial.capabilities_type_invalid", "error_zh": "空间能力声明必须是Dictionary。"}
	var domain_id := str(value.get("domain_id", ""))
	var raw_supported = value.get("supported", value.get("capabilities", []))
	if not raw_supported is Array and not raw_supported is PackedStringArray:
		return {"ok": false, "code": "spatial.capabilities_list_invalid", "error_zh": "空间能力列表必须是字符串数组。"}
	var supported_ids := PackedStringArray()
	for capability_id in raw_supported: supported_ids.append(str(capability_id))
	var capabilities := GMSpatialBackendCapabilities.new(domain_id, supported_ids)
	var validation := capabilities.validate()
	if not validation.ok: return validation
	return {"ok": true, "capabilities": capabilities, "value": capabilities.to_native()}

func to_native() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "domain_id": _domain_id, "supported": Array(_supported)}
