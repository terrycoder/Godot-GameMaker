@tool
class_name GMHitVolume3D
extends Area3D

## Area3D/Shape3D is a candidate generator only.  The result emitted by this
## component is the same pure GMCombatHitSpec consumed by P22 Resolver.

const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")
const HIT_SPEC := preload("res://gm_runtime/combat/gm_combat_hit_spec.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

const SCHEMA := "gm.combat.hit_volume_3d.v1"
const QUERY_KINDS := ["direct", "projectile"]

@export var volume_id := ""
@export var source_id := ""
@export var query_kind := "direct"
@export var planar_radius := 0.5
@export var height_tolerance := 0.75

var _collision_shape: CollisionShape3D

func _init() -> void:
	name = "GMHitVolume3D"
	monitoring = true
	monitorable = true
	_ensure_collision_shape()

func _ready() -> void:
	_ensure_collision_shape()

func configure(p_volume_id: String, p_source_id: String, p_query_kind: String = "direct", p_planar_radius: float = 0.5, p_height_tolerance: float = 0.75) -> GMHitVolume3D:
	volume_id = p_volume_id
	source_id = p_source_id
	query_kind = p_query_kind
	planar_radius = p_planar_radius
	height_tolerance = p_height_tolerance
	_ensure_collision_shape()
	return self

func to_native() -> Dictionary:
	return {
		"schema": SCHEMA,
		"volume_id": volume_id,
		"source_id": source_id,
		"query_kind": query_kind,
		"planar_radius": planar_radius,
		"height_tolerance": height_tolerance,
		"collision_shape": "SphereShape3D",
		"collision_radius": maxf(planar_radius, 0.001),
		"collision_mask": collision_mask,
		"candidate_only": true,
		"domain_facts_written": false,
	}

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not CONTRACT.stable_id(volume_id) or not volume_id.begins_with("gm.hit_volume."):
		errors.append("HitVolume3D volume_id必须使用gm.hit_volume.*稳定身份。")
	if not CONTRACT.stable_id(source_id):
		errors.append("HitVolume3D source_id必须是稳定ID。")
	if not QUERY_KINDS.has(query_kind):
		errors.append("HitVolume3D query_kind不是direct/projectile。")
	if not CONTRACT.finite_nonnegative(planar_radius) or planar_radius > 100.0:
		errors.append("HitVolume3D planar_radius必须是0至100的有限数值。")
	if not CONTRACT.finite_nonnegative(height_tolerance) or height_tolerance > 100.0:
		errors.append("HitVolume3D height_tolerance必须是0至100的有限数值。")
	return {"ok": errors.is_empty(), "code": "combat.hit_volume_3d.valid" if errors.is_empty() else "combat.hit_volume_3d.invalid", "errors": errors}

## Build one pure candidate from an authored/assembled TargetPoint3D.
## `map_backend` is used only to resolve the point into pure logical values.
func candidate_for(source_position: Variant, target_point: Variant, map_backend: Object, metadata: Dictionary = {}) -> Dictionary:
	var checked := validate()
	if not checked.ok:
		return _failure("combat.3d.hit_volume_invalid", "HitVolume3D未通过稳定值校验。", {"errors": checked.errors})
	if not target_point is GMTargetPoint3D:
		return _failure("combat.3d.target_point_missing", "HitVolume3D缺少正式TargetPoint3D，不能产生命中候选。")
	var source_parsed := PLANAR_POSITION.from_native(source_position)
	if not source_parsed.ok:
		return _failure("combat.3d.source_position_invalid", "HitVolume3D的源逻辑位置无效。", source_parsed)
	var captured: Dictionary = target_point.capture_context(map_backend)
	if not captured.ok:
		return captured
	var target_parsed := PLANAR_POSITION.from_native(captured.get("target_position", {}))
	if not target_parsed.ok:
		return _failure("combat.3d.target_position_invalid", "HitVolume3D的TargetPoint逻辑位置无效。", target_parsed)
	var source: GMPlanarPosition = source_parsed.position
	var target: GMPlanarPosition = target_parsed.position
	var source_point := Vector2(source.x, source.y)
	var target_point_2d := Vector2(target.x, target.y)
	var planar_delta := target_point_2d - source_point
	var distance := planar_delta.length()
	if is_zero_approx(distance):
		return _failure("combat.3d.planar_direction_missing", "HitVolume3D源与目标不能使用零Planar方向。")
	var p_metadata := metadata.duplicate(true)
	p_metadata["volume_id"] = volume_id
	p_metadata["representation"] = "area3d_shape"
	p_metadata["planar_distance_source"] = "Vector2_XZ"
	var pure_metadata := CONTRACT.pure(p_metadata)
	if not pure_metadata.ok:
		return _failure("combat.3d.metadata_invalid", "HitVolume3D metadata必须是纯数据。", pure_metadata)
	var hit_id := "gm.hit.%s" % CONTRACT.digest({"volume_id": volume_id, "source_id": source_id, "target_id": target_point.target_ref, "distance": distance, "query_kind": query_kind})
	var spec: GMCombatHitSpec = HIT_SPEC.new().configure(hit_id, query_kind, source_id, target_point.target_ref, planar_delta, distance, 0.0, planar_radius, p_metadata)
	var spec_check: Dictionary = spec.validate()
	if not spec_check.ok:
		return _failure("combat.3d.hit_spec_invalid", "HitVolume3D产生的HitSpec无效。", {"errors": spec_check.errors})
	var context: Dictionary = captured.duplicate(true)
	context["source_position"] = source.to_native()
	context["source_id"] = source_id
	context["target_id"] = target_point.target_ref
	context["query_kind"] = query_kind
	context["height_tolerance"] = minf(height_tolerance, float(captured.get("height_tolerance", height_tolerance)))
	context["force_hit"] = true
	var context_check := CONTRACT.pure(context)
	if not context_check.ok:
		return _failure("combat.3d.query_context_invalid", "HitVolume3D查询上下文不是纯数据。", context_check)
	return {"ok": true, "code": "combat.3d.hit_candidate_built", "hit_spec": spec, "hit_spec_native": spec.to_native(), "query_context": context, "distance": distance, "target_id": target_point.target_ref, "representation": "Area3D/Shape3D->HitSpec"}

func _ensure_collision_shape() -> void:
	if _collision_shape == null or not is_instance_valid(_collision_shape):
		_collision_shape = get_node_or_null("GMHitVolumeShape3D") as CollisionShape3D
	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "GMHitVolumeShape3D"
		add_child(_collision_shape)
	var sphere := _collision_shape.shape as SphereShape3D
	if sphere == null:
		sphere = SphereShape3D.new()
		_collision_shape.shape = sphere
	sphere.radius = maxf(planar_radius, 0.001)

func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
