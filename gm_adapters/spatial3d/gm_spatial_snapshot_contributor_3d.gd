class_name GMSpatialSnapshotContributor3D
extends RefCounted

## Optional 3D projection contributor over the existing WorldSnapshot chain.
## It owns no registry, Store or save root and emits only stable values.

const BASE := preload("res://gm_runtime/spatial_core/gm_spatial_snapshot_contributor.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

const SCHEMA := "gm.spatial.3d.presentation_snapshot.v1"

static func project_actor(actor: Object) -> Dictionary:
	if actor == null or not is_instance_valid(actor): return _failure("spatial.3d.actor_missing", "3D快照贡献者缺少有效角色。")
	var actor_id := str(actor.get("stable_instance_id")) if "stable_instance_id" in actor else ""
	var data := {
		"entity_id": actor_id,
		"map_id": str(actor.get("map_id")) if "map_id" in actor else "",
		"spatial_position": actor.get("spatial_position") if "spatial_position" in actor else {},
		"facing": _facing_native(actor.get("movement_facing")) if "movement_facing" in actor else {"x": 0.0, "y": -1.0},
		"visual_recipe_id": str(actor.get("visual_recipe_id")) if "visual_recipe_id" in actor else "gm.visual.placeholder_3d",
	}
	return normalize_entity_data(data)

static func normalize_entity_data(data: Dictionary) -> Dictionary:
	var base := BASE.normalize_entity_data(data)
	if not base.ok: return base
	var copy: Dictionary = base.data
	if copy.has("facing"):
		var facing := _parse_facing(copy.facing)
		if not facing.ok: return facing
		copy["facing"] = facing.value
	if copy.has("visual_recipe_id"):
		if typeof(copy.visual_recipe_id) != TYPE_STRING or str(copy.visual_recipe_id).strip_edges().is_empty() or not PLANAR_POSITION.is_valid_stable_id(str(copy.visual_recipe_id)):
			return _failure("spatial.3d.visual_recipe_invalid", "3D视觉配方ID必须是非空稳定ID。")
	return {"ok": true, "schema": SCHEMA, "data": copy, "has_position": base.get("has_position", false), "position": base.get("position", null)}

static func validate_snapshot(snapshot: GMWorldSnapshot) -> Dictionary:
	var base := BASE.validate_snapshot(snapshot)
	if not base.ok: return base
	if snapshot == null: return _failure("spatial.snapshot_missing", "3D快照贡献者缺少WorldSnapshot。")
	for entity_id in snapshot.entity_ids():
		var record := snapshot.get_entity(entity_id)
		var normalized := normalize_entity_data(record.get("data", {}) if record is Dictionary else {})
		if not normalized.ok: return {"ok": false, "code": normalized.get("code", "spatial.3d.entity_invalid"), "reason_zh": normalized.get("reason_zh", normalized.get("error_zh", "3D实体快照无效。")), "entity_id": entity_id}
	return {"ok": true, "schema": SCHEMA, "entities": snapshot.entity_ids(), "base": base}

static func _parse_facing(value: Variant) -> Dictionary:
	if value is Vector2: value = {"x": value.x, "y": value.y}
	if not value is Dictionary or not value.has("x") or not value.has("y"): return _failure("spatial.3d.facing_invalid", "3D实体朝向必须是x/y纯值。")
	var x := float(value.x)
	var y := float(value.y)
	if not is_finite(x) or not is_finite(y): return _failure("spatial.3d.facing_nonfinite", "3D实体朝向不能包含NaN或INF。")
	return {"ok": true, "value": {"x": x, "y": y}}

static func _facing_native(value: Variant) -> Dictionary:
	return {"x": value.x, "y": value.y} if value is Vector2 else {"x": 0.0, "y": -1.0}

static func _failure(code: String, reason_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "error_zh": reason_zh}
