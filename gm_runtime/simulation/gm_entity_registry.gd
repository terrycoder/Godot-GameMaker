class_name GMEntityRegistry
extends RefCounted

signal mutation_committed(change: Dictionary)

## 稳定业务身份与后台数据的唯一注册表。存储内容必须是可序列化纯数据。

const SPATIAL_CONTRIBUTOR := preload("res://gm_runtime/spatial_core/gm_spatial_snapshot_contributor.gd")

var _records: Dictionary = {}

func register_entity(entity_id: String, kind: String = "generic", data: Dictionary = {}, resolution: String = GMResolutionState.ACTIVE, flags: Dictionary = {}) -> Dictionary:
	var identity := GMEntityId.validate_value(entity_id)
	if not identity.ok: return _failure("entity.register_invalid", "实体注册失败：实体身份无效。", identity.errors)
	if _records.has(entity_id): return _failure("entity.duplicate", "实体身份已经注册，禁止覆盖既有实体。", [entity_id])
	var resolution_check := GMResolutionState.validate(resolution)
	if not resolution_check.ok: return resolution_check
	var stable_check := GMStableData.validate(data)
	if not stable_check.ok: return _failure("entity.data_invalid", "实体数据包含不可序列化值。", stable_check.errors)
	var flags_check := GMStableData.validate(flags)
	if not flags_check.ok: return _failure("entity.flags_invalid", "实体标记包含不可序列化值。", flags_check.errors)
	var lock_check := GMActiveLockContract.project(flags)
	if not lock_check.ok: return _failure(str(lock_check.get("code", "entity.active_lock_invalid")), str(lock_check.get("reason_zh", "实体Active锁无效。")), [])
	_records[entity_id] = {
		"entity_id": entity_id,
		"kind": kind.strip_edges(),
		"resolution": resolution,
		"version": 1,
		"data": GMStableData.clone(data),
		"flags": GMStableData.clone(flags),
		"abstract_count": 0
	}
	_emit_mutation("register_entity", entity_id, {}, get_record(entity_id))
	return {"ok": true, "entity_id": entity_id, "version": 1, "resolution": resolution}

func contains(entity_id: String) -> bool:
	return _records.has(entity_id)

func get_record(entity_id: String) -> Dictionary:
	var record: Variant = _records.get(entity_id, null)
	return GMStableData.clone(record) if record is Dictionary else {}

func all_entity_ids() -> Array[String]:
	var result: Array[String] = []
	for entity_id in _records.keys(): result.append(str(entity_id))
	result.sort()
	return result

func version_for(entity_id: String) -> int:
	var record: Variant = _records.get(entity_id, null)
	return int(record.get("version", -1)) if record is Dictionary else -1

func resolution_for(entity_id: String) -> String:
	var record: Variant = _records.get(entity_id, null)
	return str(record.get("resolution", "")) if record is Dictionary else ""

func update_flags(entity_id: String, flags: Dictionary, expected_version: int = -1) -> Dictionary:
	var record: Dictionary = _records.get(entity_id, {})
	if record.is_empty(): return _failure("entity.missing", "实体不存在。", [entity_id])
	var version_check := _check_version(record, expected_version)
	if not version_check.ok: return version_check
	var stable_check := GMStableData.validate(flags)
	if not stable_check.ok: return _failure("entity.flags_invalid", "实体标记包含不可序列化值。", stable_check.errors)
	var lock_check := GMActiveLockContract.project(flags)
	if not lock_check.ok: return _failure(str(lock_check.get("code", "entity.active_lock_invalid")), str(lock_check.get("reason_zh", "实体Active锁无效。")), [])
	var before: Dictionary = GMStableData.clone(record)
	record["flags"] = GMStableData.clone(flags)
	record["version"] = int(record.get("version", 0)) + 1
	_records[entity_id] = record
	_emit_mutation("update_flags", entity_id, before, record)
	return {"ok": true, "entity_id": entity_id, "version": record["version"], "flags": GMStableData.clone(flags)}

func set_resolution(entity_id: String, target: String, expected_version: int = -1) -> Dictionary:
	var record: Dictionary = _records.get(entity_id, {})
	if record.is_empty(): return _failure("entity.missing", "实体不存在。", [entity_id])
	var allowed := GMResolutionState.can_enter(record, target)
	if not allowed.ok: return allowed
	var version_check := _check_version(record, expected_version)
	if not version_check.ok: return version_check
	var before: Dictionary = GMStableData.clone(record)
	record["resolution"] = target
	record["version"] = int(record.get("version", 0)) + 1
	_records[entity_id] = record
	_emit_mutation("set_resolution", entity_id, before, record)
	return {"ok": true, "entity_id": entity_id, "resolution": target, "version": record["version"]}

func apply_patch(entity_id: String, patch: Dictionary, expected_version: int = -1, _origin: String = "") -> Dictionary:
	var record: Dictionary = _records.get(entity_id, {})
	if record.is_empty(): return _failure("entity.missing", "实体不存在。", [entity_id])
	var version_check := _check_version(record, expected_version)
	if not version_check.ok: return version_check
	var stable_check := GMStableData.validate(patch)
	if not stable_check.ok: return _failure("entity.patch_invalid", "实体状态变更包含不可序列化值。", stable_check.errors)
	var before: Dictionary = GMStableData.clone(record)
	var data: Dictionary = record.get("data", {}).duplicate(true)
	for key in patch.keys(): data[str(key)] = GMStableData.clone(patch[key])
	record["data"] = data
	record["version"] = int(record.get("version", 0)) + 1
	_records[entity_id] = record
	_emit_mutation("apply_patch", entity_id, before, record)
	return {"ok": true, "entity_id": entity_id, "version": record["version"], "data": data.duplicate(true)}

func restore_record(record_value: Dictionary) -> Dictionary:
	var validation := _validated_record(record_value)
	if not validation.ok: return validation
	var record: Dictionary = validation.record
	var entity_id := str(record.entity_id)
	var before := get_record(entity_id)
	_records[entity_id] = record
	_emit_mutation("restore_record", entity_id, before, record)
	return {"ok": true, "entity_id": entity_id, "version": record.version}

func _validated_record(record_value: Dictionary) -> Dictionary:
	var entity_id := str(record_value.get("entity_id", ""))
	var identity := GMEntityId.validate_value(entity_id)
	if not identity.ok: return identity
	var stable_check := GMStableData.validate(record_value)
	if not stable_check.ok: return _failure("entity.restore_invalid", "存档实体包含不可序列化值。", stable_check.errors)
	var data_value: Variant = record_value.get("data", null)
	var flags_value: Variant = record_value.get("flags", null)
	if not data_value is Dictionary: return _failure("entity.restore_data_shape_invalid", "存档实体data必须是对象。", [entity_id])
	if not flags_value is Dictionary: return _failure("entity.restore_flags_shape_invalid", "存档实体flags必须是对象；Active锁投影失败关闭。", [entity_id])
	var normalized_data := SPATIAL_CONTRIBUTOR.normalize_entity_data(data_value)
	if not normalized_data.ok:
		return _failure("entity.restore_spatial_data_invalid", "存档实体空间数据无法规范化。", normalized_data.get("errors", [normalized_data.get("reason_zh", "空间数据无效。")]))
	var lock_check := GMActiveLockContract.project(flags_value)
	if not lock_check.ok: return _failure(str(lock_check.get("code", "entity.restore_active_lock_invalid")), str(lock_check.get("reason_zh", "存档实体Active锁投影失败。")), [entity_id])
	var record := {
		"entity_id": entity_id,
		"kind": str(record_value.get("kind", "generic")),
		"resolution": str(record_value.get("resolution", GMResolutionState.ACTIVE)),
		"version": maxi(int(record_value.get("version", 1)), 1),
		"data": GMStableData.clone(normalized_data.data),
		"flags": GMStableData.clone(flags_value),
		"abstract_count": maxi(int(record_value.get("abstract_count", 0)), 0)
	}
	if not GMResolutionState.validate(record.resolution).ok: return _failure("entity.restore_resolution_invalid", "存档实体的分辨率无效。", [record.resolution])
	return {"ok": true, "record": record}

func snapshot() -> Dictionary:
	var entities: Array = []
	for entity_id in all_entity_ids(): entities.append(get_record(entity_id))
	return {"schema_version": "gm.entity_registry.v1", "entity_count": entities.size(), "entities": entities}

func load_snapshot(value: Dictionary) -> Dictionary:
	if str(value.get("schema_version", "")) != "gm.entity_registry.v1": return _failure("entity.snapshot_schema_invalid", "实体注册表存档版本不受支持。", [])
	var rows: Variant = value.get("entities", [])
	if not rows is Array: return _failure("entity.snapshot_invalid", "实体注册表存档缺少 entities 数组。", [])
	var staged_records: Dictionary = {}
	for row in rows:
		if not row is Dictionary: return _failure("entity.snapshot_row_invalid", "实体注册表存档包含无效行。", [])
		var restored := _validated_record(row)
		if not restored.ok: return restored
		var entity_id := str(restored.record.entity_id)
		if staged_records.has(entity_id): return _failure("entity.snapshot_duplicate", "实体注册表存档包含重复身份。", [entity_id])
		staged_records[entity_id] = restored.record
	if int(value.get("entity_count", -1)) != staged_records.size(): return _failure("entity.snapshot_count_mismatch", "实体注册表存档计数不一致。", [])
	var before := snapshot()
	_records = staged_records
	_emit_mutation("load_snapshot", "*", before, snapshot())
	return {"ok": true, "entity_count": _records.size()}

func increment_abstract_count(entity_id: String) -> Dictionary:
	var record: Dictionary = _records.get(entity_id, {})
	if record.is_empty(): return _failure("entity.missing", "实体不存在。", [entity_id])
	var before: Dictionary = GMStableData.clone(record)
	record["abstract_count"] = int(record.get("abstract_count", 0)) + 1
	record["version"] = int(record.get("version", 0)) + 1
	_records[entity_id] = record
	_emit_mutation("increment_abstract_count", entity_id, before, record)
	return {"ok": true, "entity_id": entity_id, "version": record["version"], "abstract_count": record["abstract_count"]}

func _check_version(record: Dictionary, expected_version: int) -> Dictionary:
	if expected_version < 0: return {"ok": true}
	var actual := int(record.get("version", -1))
	if actual != expected_version:
		return {"ok": false, "code": "entity.version_conflict", "reason_zh": "实体状态版本已变化，命令使用了过期快照。", "expected": expected_version, "actual": actual}
	return {"ok": true}

func _failure(code: String, reason_zh: String, errors: Array) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "errors": errors.duplicate(true)}


func _emit_mutation(operation: String, entity_id: String, before_component: Dictionary, after_component: Dictionary) -> void:
	if mutation_committed.get_connections().is_empty(): return
	mutation_committed.emit({"component_kind": "registry", "component_id": entity_id, "operation": operation, "before_component": GMStableData.clone(before_component), "after_component": GMStableData.clone(after_component)})
