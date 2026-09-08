class_name GMWorldSnapshot
extends RefCounted

const SPATIAL_CONTRIBUTOR := preload("res://gm_runtime/spatial_core/gm_spatial_snapshot_contributor.gd")

## 只读快照合同。系统只能读取副本并向命令缓冲写入意图。

var schema_version: String = "gm.world_snapshot.v2"
var snapshot_id: String = ""
var tick: int = 0
var seed: int = 0
var phase: String = ""
var _entities: Dictionary = {}
var _world_state: Dictionary = {}
var _content_digest: String = ""

## Compatibility readers deliberately return a fresh deep copy.  Mutating
## snapshot.entities/world_state therefore never mutates this snapshot nor a
## later reader's view.
var entities: Dictionary:
	get:
		return GMStableData.clone(_entities)
var world_state: Dictionary:
	get:
		return GMStableData.clone(_world_state)

func _init(p_tick: int = 0, p_seed: int = 0, p_phase: String = "", p_entities: Dictionary = {}, p_world_state: Dictionary = {}) -> void:
	tick = p_tick
	seed = p_seed
	phase = p_phase
	_entities = GMStableData.clone(p_entities)
	_world_state = GMStableData.clone(p_world_state)
	_content_digest = _calculate_digest()
	snapshot_id = "gm.snapshot.v2.%06d.%s" % [tick, _content_digest]

func has_entity(entity_id: String) -> bool:
	return _entities.has(entity_id)

func get_entity(entity_id: String) -> Dictionary:
	var value: Variant = _entities.get(entity_id, null)
	return GMStableData.clone(value) if value is Dictionary else {}

func version_for(entity_id: String) -> int:
	var value := get_entity(entity_id)
	return int(value.get("version", -1)) if not value.is_empty() else -1

func resolution_for(entity_id: String) -> String:
	var value := get_entity(entity_id)
	return str(value.get("resolution", "")) if not value.is_empty() else ""

func entity_ids() -> Array[String]:
	var result: Array[String] = []
	for key in _entities.keys(): result.append(str(key))
	result.sort()
	return result

func spatial_position_for(entity_id: String):
	return SPATIAL_CONTRIBUTOR.position_for_record(get_entity(entity_id))

func spatial_entity_ids() -> Array[String]:
	var result: Array[String] = []
	for entity_id in entity_ids():
		if spatial_position_for(entity_id) != null: result.append(entity_id)
	return result

func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"snapshot_id": snapshot_id,
		"tick": tick,
		"seed": seed,
		"phase": phase,
		"entities": GMStableData.clone(_entities),
		"world_state": GMStableData.clone(_world_state),
		"content_digest": _content_digest
	}

func get_world_state() -> Dictionary:
	return GMStableData.clone(_world_state)

func verify_integrity() -> Dictionary:
	var actual := _calculate_digest()
	if actual != _content_digest:
		return {"ok": false, "code": "snapshot.integrity_mismatch", "reason_zh": "快照阶段内容完整性校验失败。", "expected": _content_digest, "actual": actual}
	var expected_id := "gm.snapshot.v2.%06d.%s" % [tick, actual]
	if snapshot_id != expected_id:
		return {"ok": false, "code": "snapshot.identity_mismatch", "reason_zh": "快照身份与冻结内容不一致。", "expected": expected_id, "actual": snapshot_id}
	return {"ok": true, "snapshot_id": snapshot_id, "content_digest": actual}

func validate() -> Dictionary:
	var errors: Array[String] = []
	if snapshot_id.is_empty(): errors.append("快照缺少 snapshot_id。")
	if tick < 0: errors.append("快照 tick 不能为负数。")
	var integrity := verify_integrity()
	if not integrity.ok: errors.append(str(integrity.get("reason_zh", "快照完整性失败。")))
	var stable := GMStableData.validate(to_dict())
	if not stable.ok: errors.append_array(stable.errors)
	for entity_id in entity_ids():
		if not GMEntityId.validate_value(entity_id).ok: errors.append("快照包含无效实体身份：%s" % entity_id)
	var spatial := SPATIAL_CONTRIBUTOR.validate_snapshot(self)
	if not spatial.ok: errors.append(str(spatial.get("reason_zh", "空间快照贡献校验失败。")))
	return {"ok": errors.is_empty(), "code": "snapshot.valid" if errors.is_empty() else "snapshot.invalid", "errors": errors}

static func from_registry(registry: GMEntityRegistry, p_tick: int, p_seed: int, p_phase: String = "", p_world_state: Dictionary = {}) -> GMWorldSnapshot:
	var entity_map := {}
	if registry != null:
		for entity_id in registry.all_entity_ids(): entity_map[entity_id] = registry.get_record(entity_id)
	return GMWorldSnapshot.new(p_tick, p_seed, p_phase, entity_map, p_world_state)

static func from_dict(value: Dictionary) -> GMWorldSnapshot:
	var snapshot := GMWorldSnapshot.new(int(value.get("tick", 0)), int(value.get("seed", 0)), str(value.get("phase", "")), value.get("entities", {}) if value.get("entities", {}) is Dictionary else {}, value.get("world_state", {}) if value.get("world_state", {}) is Dictionary else {})
	var supplied_digest := str(value.get("content_digest", ""))
	if not supplied_digest.is_empty(): snapshot._content_digest = supplied_digest
	snapshot.snapshot_id = str(value.get("snapshot_id", snapshot.snapshot_id))
	return snapshot

func _calculate_digest() -> String:
	return GMStableData.digest({"schema_version": schema_version, "tick": tick, "seed": seed, "phase": phase, "entities": _entities, "world_state": _world_state})
