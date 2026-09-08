class_name GMInventoryStore
extends "res://gm_runtime/simulation/gm_store.gd"

## Canonical item/lot/instance/provenance/ownership/container/change Store.
## It is a normal 05B GMStore with typed accessors, not a second fact source.

const STORE_SCHEMA_VERSION := "gm.inventory_store.v3"
const KINDS := ["definition", "lot", "instance", "provenance", "ownership", "container", "change"]

var reservations: Dictionary = {}

func _init(p_store_id: String = "gm.store.inventory") -> void:
	store_id = p_store_id
	schema_version = STORE_SCHEMA_VERSION

func register_definition(value: Variant, expected_version: int = -1) -> Dictionary:
	var definition: GMItemDefinition = value if value is GMItemDefinition else GMItemDefinition.from_dict(value if value is Dictionary else {})
	return _write_typed("definition", definition.definition_id, definition.to_dict(), expected_version)

func register_lot(value: Variant, expected_version: int = -1) -> Dictionary:
	var lot: GMItemLot = value if value is GMItemLot else GMItemLot.from_dict(value if value is Dictionary else {})
	return _write_typed("lot", lot.lot_id, lot.to_dict(), expected_version)

func register_instance(value: Variant, expected_version: int = -1) -> Dictionary:
	var instance: GMItemInstance = value if value is GMItemInstance else GMItemInstance.from_dict(value if value is Dictionary else {})
	return _write_typed("instance", instance.instance_id, instance.to_dict(), expected_version)

func register_provenance(value: Variant, expected_version: int = -1) -> Dictionary:
	var provenance: GMProvenanceRecord = value if value is GMProvenanceRecord else GMProvenanceRecord.from_dict(value if value is Dictionary else {})
	return _write_typed("provenance", provenance.provenance_id, provenance.to_dict(), expected_version)

func register_ownership(value: Variant, expected_version: int = -1) -> Dictionary:
	var ownership: GMOwnershipRecord = value if value is GMOwnershipRecord else GMOwnershipRecord.from_dict(value if value is Dictionary else {})
	var result := _write_typed("ownership", ownership.ownership_id, ownership.to_dict(), expected_version)
	if result.ok: result["ownership_id"] = ownership.ownership_id
	return result

func register_container(value: Variant, expected_version: int = -1) -> Dictionary:
	var container: GMInventoryContainer = value if value is GMInventoryContainer else GMInventoryContainer.from_dict(value if value is Dictionary else {})
	return _write_typed("container", container.container_id, container.to_dict(), expected_version)

func register_change(value: Variant, expected_version: int = -1) -> Dictionary:
	var change: GMInventoryChange = value if value is GMInventoryChange else GMInventoryChange.from_dict(value if value is Dictionary else {})
	return _write_typed("change", change.change_id, change.to_dict(), expected_version)

func get_typed(kind: String, record_id: String) -> Dictionary:
	var wrapped: Variant = records.get(_key(kind, record_id), null)
	if not wrapped is Dictionary: return {}
	var value: Variant = wrapped.get("record", {})
	return value.duplicate(true) if value is Dictionary else {}

func has_typed(kind: String, record_id: String) -> bool:
	return records.has(_key(kind, record_id))

func all_typed(kind: String) -> Array:
	var result: Array = []
	var prefix := "%s:" % kind
	var keys_sorted: Array[String] = []
	for key in records.keys():
		if str(key).begins_with(prefix): keys_sorted.append(str(key))
	keys_sorted.sort()
	for key in keys_sorted:
		var wrapped: Dictionary = records[key]
		result.append(wrapped.get("record", {}).duplicate(true))
	return result

func get_definition(definition_id: String) -> GMItemDefinition:
	var value := get_typed("definition", definition_id)
	return GMItemDefinition.from_dict(value) if not value.is_empty() else null

func get_lot(lot_id: String) -> GMItemLot:
	var value := get_typed("lot", lot_id)
	return GMItemLot.from_dict(value) if not value.is_empty() else null

func get_instance(instance_id: String) -> GMItemInstance:
	var value := get_typed("instance", instance_id)
	return GMItemInstance.from_dict(value) if not value.is_empty() else null

func get_provenance(provenance_id: String) -> GMProvenanceRecord:
	var value := get_typed("provenance", provenance_id)
	return GMProvenanceRecord.from_dict(value) if not value.is_empty() else null

func get_ownership(ownership_id: String) -> GMOwnershipRecord:
	var value := get_typed("ownership", ownership_id)
	return GMOwnershipRecord.from_dict(value) if not value.is_empty() else null

func get_container(container_id: String) -> GMInventoryContainer:
	var value := get_typed("container", container_id)
	return GMInventoryContainer.from_dict(value) if not value.is_empty() else null

func get_change(change_id: String) -> GMInventoryChange:
	var value := get_typed("change", change_id)
	return GMInventoryChange.from_dict(value) if not value.is_empty() else null

func find_ownership(item_kind: String, item_id: String) -> GMOwnershipRecord:
	for value in all_typed("ownership"):
		var ownership := GMOwnershipRecord.from_dict(value)
		if ownership.item_kind == item_kind and ownership.item_id == item_id: return ownership
	return null

func apply_atomic(upserts: Array, deletes: Array = [], expected_version: int = -1) -> Dictionary:
	if expected_version >= 0 and expected_version != version:
		return {"ok": false, "code": "inventory.store_version_conflict", "reason_zh": "库存Store版本已变化，拒绝提交过期事务。", "expected": expected_version, "actual": version}
	var next_records: Dictionary = records.duplicate(true)
	var delete_keys: Dictionary = {}
	for raw_key in deletes:
		var key := str(raw_key)
		if not _valid_storage_key(key): return {"ok": false, "code": "inventory.store_key_invalid", "reason_zh": "库存Store删除键无效。", "key": key}
		delete_keys[key] = true
	for key in delete_keys: next_records.erase(key)
	var seen_upserts: Dictionary = {}
	for row in upserts:
		if not row is Dictionary: return {"ok": false, "code": "inventory.store_upsert_invalid", "reason_zh": "库存Store upsert 必须是对象。"}
		var kind := str(row.get("kind", ""))
		var record_id := str(row.get("id", ""))
		var value: Variant = row.get("value", null)
		var key := _key(kind, record_id)
		if not KINDS.has(kind) or record_id.is_empty() or not value is Dictionary: return {"ok": false, "code": "inventory.store_upsert_invalid", "reason_zh": "库存Store upsert 的类型、ID或记录无效。", "row": row}
		if seen_upserts.has(key): return {"ok": false, "code": "inventory.store_duplicate_upsert", "reason_zh": "同一库存记录在一个事务中重复写入。", "key": key}
		var canonical := _canonicalize_typed(kind, value, false)
		if not canonical.ok: return {"ok": false, "code": "inventory.store_record_invalid", "reason_zh": "库存记录校验或规范化失败。", "key": key, "details": canonical}
		if canonical.id != record_id: return {"ok": false, "code": "inventory.store_record_identity_mismatch", "reason_zh": "库存记录键与类型化身份不一致。", "key": key, "record_id": canonical.id}
		if kind == "ownership":
			var existing_contract := _ownership_contract(next_records.get(key, {}))
			var incoming_contract := "%s\u001f%s" % [str(canonical.value.get("item_kind", "")), str(canonical.value.get("item_id", ""))]
			if not existing_contract.is_empty() and existing_contract != incoming_contract:
				return {"ok": false, "code": "inventory.ownership_identity_conflict", "reason_zh": "同一Ownership ID对应不同精确物品合同，拒绝覆盖。", "ownership_id": record_id}
		seen_upserts[key] = true
		next_records[key] = {"record_kind": kind, "record": canonical.value}
	if next_records == records and upserts.is_empty() and deletes.is_empty(): return {"ok": true, "version": version, "changed": false}
	records = next_records
	version += 1
	persistence_revision += 1
	dirty = true
	_rebuild_indexes()
	return {"ok": true, "version": version, "changed": true, "upsert_count": upserts.size(), "delete_count": deletes.size()}

func reserve(transaction_id: String, source_claims: Array, target_claims: Array, expected_version: int) -> Dictionary:
	if transaction_id.is_empty(): return {"ok": false, "code": "inventory.reservation_id_missing", "reason_zh": "库存预留缺少事务身份。"}
	if reservations.has(transaction_id):
		var existing: Dictionary = reservations[transaction_id]
		if GMStableData.canonical_json(existing.get("source_claims", [])) == GMStableData.canonical_json(source_claims) and GMStableData.canonical_json(existing.get("target_claims", [])) == GMStableData.canonical_json(target_claims) and int(existing.get("store_version", -1)) == version:
			return {"ok": true, "duplicate": true, "reservation": existing.duplicate(true), "reservations": [existing.duplicate(true)]}
		return {"ok": false, "code": "inventory.reservation_identity_conflict", "reason_zh": "同一事务身份已经绑定不同库存预留。"}
	if expected_version >= 0 and expected_version != version: return {"ok": false, "code": "inventory.reservation_version_conflict", "reason_zh": "预留时库存Store版本已变化。", "expected": expected_version, "actual": version}
	var errors: Array[String] = []
	for claim in source_claims:
		var container_id := str(claim.get("container_id", ""))
		var item_kind := str(claim.get("item_kind", ""))
		var item_id := str(claim.get("item_id", ""))
		var quantity := int(claim.get("quantity", 0))
		var container := get_container(container_id)
		if container == null: errors.append("预留源容器不存在：%s" % container_id); continue
		var available := container.quantity_for(item_kind, item_id) - _reserved_quantity(container_id, item_kind, item_id, transaction_id)
		if available < quantity: errors.append("源物品已被其他事务预留：%s 可用%s 请求%s" % [item_id, available, quantity])
	for claim in target_claims:
		var container_id := str(claim.get("container_id", ""))
		var required_slots := int(claim.get("slots", 0))
		var container := get_container(container_id)
		if container == null: errors.append("预留目标容器不存在：%s" % container_id); continue
		var free_slots := container.slot_limit - container.slot_count() if container.slot_limit >= 0 else 2147483647
		free_slots -= _reserved_slots(container_id, transaction_id)
		if free_slots < required_slots: errors.append("目标容器槽位预留不足：%s 可用%s 请求%s" % [container_id, free_slots, required_slots])
	if not errors.is_empty(): return {"ok": false, "code": "inventory.reservation_conflict", "reason_zh": "库存资源或容器容量已经被并发事务预留。", "errors": errors}
	var reservation := {
		"schema": "gm.inventory.reservation.v1",
		"reservation_id": "gm.reservation.inventory.%s" % ("%s|inventory" % transaction_id).sha256_text(),
		"participant": "inventory",
		"transaction_id": transaction_id,
		"store_version": version,
		"source_claims": source_claims.duplicate(true),
		"target_claims": target_claims.duplicate(true),
	}
	reservations[transaction_id] = reservation
	return {"ok": true, "reservation": reservation.duplicate(true), "reservations": [reservation.duplicate(true)]}

func release_reservation(transaction_id: String) -> Dictionary:
	var existed := reservations.has(transaction_id)
	reservations.erase(transaction_id)
	return {"ok": true, "released": existed, "transaction_id": transaction_id}

func reservation_for(transaction_id: String) -> Dictionary:
	return reservations.get(transaction_id, {}).duplicate(true)

func snapshot() -> Dictionary:
	return super.snapshot()

func restore_snapshot(value: Dictionary) -> Dictionary:
	var migrated := migrate_snapshot(value)
	if not migrated.ok: return migrated
	var saved: Dictionary = migrated.snapshot
	# Validate the complete 05B Store v3 shape, numeric boundary and exact index
	# projection on an isolated Store before touching this authoritative Store.
	var boundary := GMStore.new(store_id, schema_version)
	boundary.indexes = GMStableData.clone(indexes)
	var boundary_result := boundary.restore_snapshot(saved)
	if not boundary_result.ok: return {"ok": false, "code": "inventory.store_v3_boundary_invalid", "reason_zh": "库存快照未通过05B Store v3精确边界。", "details": boundary_result}
	var canonical_records: Dictionary = {}
	var ownership_contracts: Dictionary = {}
	var identity_migrations: Array = []
	var keys_sorted: Array[String] = []
	for raw_key in boundary.records.keys(): keys_sorted.append(str(raw_key))
	keys_sorted.sort()
	for key in keys_sorted:
		var wrapped: Variant = boundary.records[key]
		if not wrapped is Dictionary or wrapped.size() != 2 or not wrapped.has("record_kind") or not wrapped.has("record") or not wrapped.record is Dictionary:
			return {"ok": false, "code": "inventory.snapshot_record_invalid", "reason_zh": "库存Store存档记录缺少精确类型封套。", "key": key}
		var kind := str(wrapped.record_kind)
		var parts := key.split(":", false, 1)
		if parts.size() != 2 or parts[0] != kind: return {"ok": false, "code": "inventory.snapshot_key_kind_mismatch", "key": key, "record_kind": kind}
		var canonical := _canonicalize_typed(kind, wrapped.record, true)
		if not canonical.ok: return {"ok": false, "code": "inventory.snapshot_record_invalid", "reason_zh": "库存Store类型化记录无法规范化。", "key": key, "details": canonical}
		var saved_id := str(parts[1])
		var canonical_id := str(canonical.id)
		if kind != "ownership" and saved_id != canonical_id:
			return {"ok": false, "code": "inventory.snapshot_record_identity_mismatch", "key": key, "record_id": canonical_id}
		if kind == "ownership" and saved_id != canonical_id:
			var legacy_expected := GMOwnershipRecord.legacy_id(str(canonical.value.item_kind), str(canonical.value.item_id))
			if saved_id != legacy_expected: return {"ok": false, "code": "inventory.ownership_legacy_id_untrusted", "saved_id": saved_id, "expected_legacy_id": legacy_expected}
			identity_migrations.append({"from": saved_id, "to": canonical_id, "item_kind": canonical.value.item_kind, "item_id": canonical.value.item_id})
		var canonical_key := _key(kind, canonical_id)
		if canonical_records.has(canonical_key): return {"ok": false, "code": "inventory.snapshot_identity_collision", "key": canonical_key}
		if kind == "ownership":
			var contract := "%s\u001f%s" % [str(canonical.value.item_kind), str(canonical.value.item_id)]
			if ownership_contracts.has(canonical_id) and ownership_contracts[canonical_id] != contract:
				return {"ok": false, "code": "inventory.ownership_identity_conflict", "ownership_id": canonical_id}
			ownership_contracts[canonical_id] = contract
		canonical_records[canonical_key] = {"record_kind": kind, "record": canonical.value}
	boundary.records = canonical_records
	boundary._rebuild_indexes()
	# All validation and canonicalization completed; assignments below are atomic.
	records = GMStableData.clone(boundary.records)
	version = boundary.version
	persistence_revision = boundary.persistence_revision
	dirty = boundary.dirty
	indexes = GMStableData.clone(boundary.indexes)
	reservations.clear()
	return {"ok": true, "store_id": store_id, "version": version, "persistence_revision": persistence_revision, "dirty": dirty, "record_count": records.size(), "migration": migrated.migration, "ownership_identity_migrations": identity_migrations}

static func migrate_snapshot(value: Dictionary) -> Dictionary:
	var schema := str(value.get("schema_version", ""))
	if value.get("snapshot_schema", "") == GMStore.SNAPSHOT_SCHEMA and schema == STORE_SCHEMA_VERSION:
		return {"ok": true, "snapshot": value.duplicate(true), "migration": {"from": schema, "to": STORE_SCHEMA_VERSION, "applied": false}}
	if schema == "gm.inventory_store.v2":
		var version_check := _legacy_nonnegative_integer(value.get("version", null), "version")
		if not version_check.ok or typeof(value.get("dirty")) != TYPE_BOOL or not value.get("records", null) is Dictionary or not value.get("indexes", null) is Dictionary:
			return {"ok": false, "code": "inventory.snapshot_v2_invalid", "details": version_check}
		var migrated_v2 := {"snapshot_schema": GMStore.SNAPSHOT_SCHEMA, "schema_version": STORE_SCHEMA_VERSION, "store_id": value.get("store_id", ""), "version": version_check.value, "persistence_revision": version_check.value, "dirty": value.dirty, "records": value.records.duplicate(true), "indexes": value.indexes.duplicate(true)}
		return {"ok": true, "snapshot": migrated_v2, "migration": {"from": schema, "to": STORE_SCHEMA_VERSION, "applied": true, "boundary": "inventory_v2_to_store_v3"}}
	if schema == "gm.inventory_store.v1":
		var version_check_v1 := _legacy_nonnegative_integer(value.get("version", null), "version")
		if not version_check_v1.ok or typeof(value.get("dirty")) != TYPE_BOOL: return {"ok": false, "code": "inventory.snapshot_v1_invalid", "details": version_check_v1}
		var migrated := {"snapshot_schema": GMStore.SNAPSHOT_SCHEMA, "schema_version": STORE_SCHEMA_VERSION, "store_id": value.get("store_id", ""), "version": version_check_v1.value, "persistence_revision": version_check_v1.value, "dirty": value.dirty, "records": {}, "indexes": {}}
		for kind in KINDS:
			var rows: Variant = value.get("%ss" % kind, {})
			if rows is Dictionary:
				for id in rows:
					migrated.records[_key(kind, str(id))] = {"record_kind": kind, "record": rows[id]}
		return {"ok": true, "snapshot": migrated, "migration": {"from": schema, "to": STORE_SCHEMA_VERSION, "applied": true}}
	if schema == "gm.store.v1":
		return {"ok": false, "code": "inventory.snapshot_migration_ambiguous", "reason_zh": "旧通用Store存档缺少库存记录类型，拒绝猜测迁移。"}
	return {"ok": false, "code": "inventory.snapshot_schema_invalid", "reason_zh": "库存Store存档版本不受支持。", "schema_version": schema}

static func _legacy_nonnegative_integer(value: Variant, field_name: String) -> Dictionary:
	if typeof(value) == TYPE_INT and value >= 0 and value <= GMStableData.JSON_SAFE_INTEGER_MAX: return {"ok": true, "value": value}
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value) and value >= 0.0 and value <= GMStableData.JSON_SAFE_INTEGER_MAX: return {"ok": true, "value": int(value)}
	return {"ok": false, "code": "inventory.snapshot_%s_invalid" % field_name}

func _write_typed(kind: String, record_id: String, value: Dictionary, expected_version: int) -> Dictionary:
	return apply_atomic([{"kind": kind, "id": record_id, "value": value}], [], expected_version)

func _validate_typed(kind: String, value: Dictionary) -> Dictionary:
	if kind == "definition": return GMItemDefinition.from_dict(value).validate()
	if kind == "lot": return GMItemLot.from_dict(value).validate()
	if kind == "instance": return GMItemInstance.from_dict(value).validate()
	if kind == "provenance": return GMProvenanceRecord.from_dict(value).validate()
	if kind == "ownership": return GMOwnershipRecord.from_dict(value).validate()
	if kind == "container": return GMInventoryContainer.from_dict(value).validate()
	if kind == "change": return GMInventoryChange.from_dict(value).validate()
	return {"ok": false, "errors": ["未知库存记录类型：%s" % kind]}

func _canonicalize_typed(kind: String, value: Dictionary, allow_legacy_ownership_id: bool) -> Dictionary:
	var numeric := _validate_numeric_contract(kind, value)
	if not numeric.ok: return numeric
	var canonical_value: Dictionary = {}
	var record_id := ""
	var check: Dictionary = {}
	match kind:
		"definition":
			var row := GMItemDefinition.from_dict(value); check = row.validate(); canonical_value = row.to_dict(); record_id = row.definition_id
		"lot":
			var row := GMItemLot.from_dict(value); check = row.validate(); canonical_value = row.to_dict(); record_id = row.lot_id
		"instance":
			var row := GMItemInstance.from_dict(value); check = row.validate(); canonical_value = row.to_dict(); record_id = row.instance_id
		"provenance":
			var row := GMProvenanceRecord.from_dict(value); check = row.validate(); canonical_value = row.to_dict(); record_id = row.provenance_id
		"ownership":
			var row := GMOwnershipRecord.from_dict(value)
			var expected := GMOwnershipRecord.make_id(row.item_kind, row.item_id)
			var legacy := GMOwnershipRecord.legacy_id(row.item_kind, row.item_id)
			if row.ownership_id != expected and (not allow_legacy_ownership_id or row.ownership_id != legacy):
				return {"ok": false, "code": "inventory.ownership_id_contract_invalid", "ownership_id": row.ownership_id, "expected": expected}
			row.ownership_id = expected; check = row.validate(); canonical_value = row.to_dict(); record_id = expected
		"container":
			var row := GMInventoryContainer.from_dict(value); check = row.validate(); canonical_value = row.to_dict(); record_id = row.container_id
		"change":
			var row := GMInventoryChange.from_dict(value); check = row.validate(); canonical_value = row.to_dict(); record_id = row.change_id
		_:
			return {"ok": false, "code": "inventory.record_kind_invalid", "kind": kind}
	if not check.ok: return {"ok": false, "code": "inventory.typed_validation_failed", "errors": check.errors}
	return {"ok": true, "id": record_id, "value": canonical_value}

func _validate_numeric_contract(kind: String, value: Dictionary) -> Dictionary:
	var integer_fields: Array[String] = []
	var float_fields: Array[String] = []
	match kind:
		"definition": integer_fields = ["max_stack"]; float_fields = ["unit_weight"]
		"lot": integer_fields = ["quantity", "quality"]
		"instance": integer_fields = ["quality", "upgrade_level"]
		"container": integer_fields = ["slot_limit"]; float_fields = ["weight_limit"]
		"change": integer_fields = ["quantity_delta", "quantity_before", "quantity_after"]
	for field in integer_fields:
		if not value.has(field): return {"ok": false, "code": "inventory.numeric_field_missing", "field": field}
		var raw: Variant = value[field]
		if typeof(raw) == TYPE_INT:
			if abs(raw) > GMStableData.JSON_SAFE_INTEGER_MAX: return {"ok": false, "code": "inventory.integer_out_of_range", "field": field}
		elif typeof(raw) == TYPE_FLOAT and is_finite(raw) and raw == floor(raw) and abs(raw) <= GMStableData.JSON_SAFE_INTEGER_MAX:
			pass
		else: return {"ok": false, "code": "inventory.integer_type_invalid", "field": field, "value_type": typeof(raw)}
	for field in float_fields:
		if not value.has(field): return {"ok": false, "code": "inventory.numeric_field_missing", "field": field}
		var raw: Variant = value[field]
		if not [TYPE_INT, TYPE_FLOAT].has(typeof(raw)) or not is_finite(float(raw)):
			return {"ok": false, "code": "inventory.float_type_invalid", "field": field, "value_type": typeof(raw)}
	if kind == "definition" and (not value.has("stackable") or typeof(value.stackable) != TYPE_BOOL): return {"ok": false, "code": "inventory.bool_type_invalid", "field": "stackable"}
	if kind == "container":
		if not value.get("entries", null) is Array: return {"ok": false, "code": "inventory.container_entries_invalid"}
		for entry in value.entries:
			if not entry is Dictionary or not entry.has("quantity"): return {"ok": false, "code": "inventory.container_entry_invalid"}
			var raw: Variant = entry.quantity
			if not (typeof(raw) == TYPE_INT and abs(raw) <= GMStableData.JSON_SAFE_INTEGER_MAX) and not (typeof(raw) == TYPE_FLOAT and is_finite(raw) and raw == floor(raw) and abs(raw) <= GMStableData.JSON_SAFE_INTEGER_MAX):
				return {"ok": false, "code": "inventory.container_quantity_invalid", "value_type": typeof(raw)}
	return {"ok": true}

func _ownership_contract(wrapped: Variant) -> String:
	if not wrapped is Dictionary or not wrapped.get("record", null) is Dictionary: return ""
	var row: Dictionary = wrapped.record
	return "%s\u001f%s" % [str(row.get("item_kind", "")), str(row.get("item_id", ""))]

static func _key(kind: String, record_id: String) -> String:
	return "%s:%s" % [kind, record_id]

func _valid_storage_key(key: String) -> bool:
	var parts := key.split(":", false, 1)
	return parts.size() == 2 and KINDS.has(parts[0]) and not parts[1].is_empty() and not parts[1].contains("res://") and not parts[1].contains("user://")

func _reserved_quantity(container_id: String, item_kind: String, item_id: String, exclude_transaction_id: String) -> int:
	var result := 0
	for tx_id in reservations:
		if str(tx_id) == exclude_transaction_id: continue
		for claim in reservations[tx_id].get("source_claims", []):
			if str(claim.get("container_id", "")) == container_id and str(claim.get("item_kind", "")) == item_kind and str(claim.get("item_id", "")) == item_id: result += int(claim.get("quantity", 0))
	return result

func _reserved_slots(container_id: String, exclude_transaction_id: String) -> int:
	var result := 0
	for tx_id in reservations:
		if str(tx_id) == exclude_transaction_id: continue
		for claim in reservations[tx_id].get("target_claims", []):
			if str(claim.get("container_id", "")) == container_id: result += int(claim.get("slots", 0))
	return result
