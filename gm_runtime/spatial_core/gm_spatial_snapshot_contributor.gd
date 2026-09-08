class_name GMSpatialSnapshotContributor
extends RefCounted

## Projection/validation helper for the existing GMEntityRegistry and
## GMWorldSnapshot.  It owns no entity map and therefore is not a second
## spatial fact store.

const SCHEMA_VERSION := 1
const POSITION_KEY := "spatial_position"
const LEGACY_POSITION_KEY := "gm.spatial.planar_position"
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const SPATIAL_CAPABILITIES := preload("res://gm_runtime/spatial_core/gm_spatial_backend_capabilities.gd")

static func normalize_entity_data(data: Dictionary) -> Dictionary:
	var copy := data.duplicate(true)
	var has_primary := copy.has(POSITION_KEY)
	var has_legacy := copy.has(LEGACY_POSITION_KEY)
	if not has_primary and not has_legacy:
		return {"ok": true, "data": copy, "has_position": false}
	var candidate = copy.get(POSITION_KEY, copy.get(LEGACY_POSITION_KEY, null))
	var parsed := PLANAR_POSITION.from_native(candidate)
	if not parsed.ok:
		return {"ok": false, "code": "spatial.entity_position_invalid", "reason_zh": "实体空间位置无效：%s" % str(parsed.get("error_zh", "请修正map、surface与有限坐标。")), "details": parsed}
	if has_primary and has_legacy:
		var legacy := PLANAR_POSITION.from_native(copy.get(LEGACY_POSITION_KEY))
		if not legacy.ok or legacy.value != parsed.value:
			return {"ok": false, "code": "spatial.entity_position_duplicate", "reason_zh": "实体同时声明了不一致的空间位置字段。"}
	copy[POSITION_KEY] = parsed.position.to_native()
	copy.erase(LEGACY_POSITION_KEY)
	return {"ok": true, "data": copy, "has_position": true, "position": parsed.position}

static func position_for_record(record: Dictionary):
	if not record is Dictionary: return null
	var data = record.get("data", {})
	if not data is Dictionary: return null
	var parsed := PLANAR_POSITION.from_native(data.get(POSITION_KEY, data.get(LEGACY_POSITION_KEY, null)))
	return parsed.position if parsed.ok else null

static func validate_registry(registry: GMEntityRegistry, spatial_context = null) -> Dictionary:
	if registry == null:
		return {"ok": false, "code": "spatial.snapshot.registry_missing", "reason_zh": "空间快照贡献者缺少实体注册表。"}
	var positions: Dictionary = {}
	for entity_id in registry.all_entity_ids():
		var record := registry.get_record(entity_id)
		var normalized := normalize_entity_data(record.get("data", {}) if record is Dictionary else {})
		if not normalized.ok: return normalized
		if not bool(normalized.get("has_position", false)): continue
		var position = normalized.position
		if spatial_context is Object and is_instance_valid(spatial_context) and spatial_context.has_method("query_spatial"):
			var surface_result = spatial_context.call("query_spatial", SPATIAL_CAPABILITIES.FIND_SURFACE, "find_surface", [position])
			if not surface_result is Dictionary or not bool(surface_result.get("ok", false)):
				return {"ok": false, "code": "spatial.snapshot.position_unresolvable", "reason_zh": "实体空间位置无法由当前SemanticMap解析，空间存档已关闭式拒绝。", "entity_id": entity_id, "details": surface_result.duplicate(true) if surface_result is Dictionary else {}}
		positions[entity_id] = position.to_native()
	return {"ok": true, "schema_version": SCHEMA_VERSION, "positions": positions, "entity_count": positions.size()}

static func validate_snapshot(snapshot: GMWorldSnapshot) -> Dictionary:
	if snapshot == null:
		return {"ok": false, "code": "spatial.snapshot_missing", "reason_zh": "空间快照贡献者缺少WorldSnapshot。"}
	var positions: Dictionary = {}
	for entity_id in snapshot.entity_ids():
		var position = position_for_record(snapshot.get_entity(entity_id))
		var record := snapshot.get_entity(entity_id)
		var data = record.get("data", {})
		if data is Dictionary and (data.has(POSITION_KEY) or data.has(LEGACY_POSITION_KEY)):
			if position == null: return {"ok": false, "code": "spatial.snapshot_position_invalid", "reason_zh": "快照实体空间位置无效：%s" % entity_id}
			positions[entity_id] = position.to_native()
	return {"ok": true, "schema_version": SCHEMA_VERSION, "positions": positions, "entity_count": positions.size()}

static func context_state(context: Object) -> Dictionary:
	if context == null or not is_instance_valid(context) or not context.has_method("spatial_snapshot_state"):
		return {}
	var value = context.call("spatial_snapshot_state")
	return value.duplicate(true) if value is Dictionary else {}
