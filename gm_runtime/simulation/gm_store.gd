class_name GMStore
extends RefCounted

signal mutation_committed(change: Dictionary)

## 通用Store合同：版本、脏标记、稳定键、索引与存档快照。

const SNAPSHOT_SCHEMA := "gm.store_snapshot.v3"

var store_id: String = ""
var schema_version: String = "gm.store.v1"
var version: int = 0
var persistence_revision: int = 0
var dirty: bool = false
var records: Dictionary = {}
var indexes: Dictionary = {}

func _init(p_store_id: String = "", p_schema_version: String = "gm.store.v1") -> void:
	store_id = p_store_id.strip_edges()
	schema_version = p_schema_version

func put(key: String, value: Dictionary, expected_version: int = -1) -> Dictionary:
	var key_check := _validate_key(key)
	if not key_check.ok: return key_check
	if expected_version >= 0 and expected_version != version:
		return {"ok": false, "code": "store.version_conflict", "reason_zh": "Store 版本已变化，拒绝覆盖。", "expected": expected_version, "actual": version}
	var stable := GMStableData.validate_persistence(value)
	if not stable.ok: return {"ok": false, "code": "store.value_invalid", "reason_zh": "Store 记录必须是纯数据。", "errors": stable.errors}
	var before := snapshot()
	records[key] = GMStableData.clone(value)
	version += 1
	persistence_revision += 1
	dirty = true
	_rebuild_indexes()
	_emit_mutation("put", before)
	return {"ok": true, "store_id": store_id, "key": key, "version": version, "dirty": dirty}

func erase(key: String, expected_version: int = -1) -> Dictionary:
	if not records.has(key): return {"ok": false, "code": "store.key_missing", "reason_zh": "Store 记录不存在。", "key": key}
	if expected_version >= 0 and expected_version != version:
		return {"ok": false, "code": "store.version_conflict", "reason_zh": "Store 版本已变化，拒绝删除。", "expected": expected_version, "actual": version}
	var before := snapshot()
	records.erase(key)
	version += 1
	persistence_revision += 1
	dirty = true
	_rebuild_indexes()
	_emit_mutation("erase", before)
	return {"ok": true, "key": key, "version": version, "dirty": dirty}

func has(key: String) -> bool:
	return records.has(key)

func read(key: String) -> Dictionary:
	var value: Variant = records.get(key, null)
	return GMStableData.clone(value) if value is Dictionary else {}

func keys() -> Array[String]:
	var result: Array[String] = []
	for key in records.keys(): result.append(str(key))
	result.sort()
	return result

func create_index(index_id: String, field: String) -> Dictionary:
	if index_id.strip_edges().is_empty() or field.strip_edges().is_empty(): return {"ok": false, "code": "store.index_invalid", "reason_zh": "索引需要 index_id 和 field。"}
	var existing: Variant = indexes.get(index_id, null)
	if existing is Dictionary and str(existing.get("field", "")) == field:
		return {"ok": true, "index_id": index_id, "field": field, "unchanged": true, "persistence_revision": persistence_revision}
	var before := snapshot()
	indexes[index_id] = {"field": field, "values": {}}
	_rebuild_indexes()
	persistence_revision += 1
	_emit_mutation("create_index", before)
	return {"ok": true, "index_id": index_id, "field": field, "persistence_revision": persistence_revision}

func query_index(index_id: String, value: Variant) -> Array:
	var index: Dictionary = indexes.get(index_id, {})
	var values: Dictionary = index.get("values", {}) if index.get("values", {}) is Dictionary else {}
	var result: Array = values.get(GMStableData.persistence_canonical_json(value), []).duplicate(true)
	result.sort()
	return result

func mark_clean() -> void:
	if not dirty: return
	var before := snapshot()
	dirty = false
	persistence_revision += 1
	_emit_mutation("mark_clean", before)

func snapshot() -> Dictionary:
	return {"snapshot_schema": SNAPSHOT_SCHEMA, "schema_version": schema_version, "store_id": store_id, "version": version, "persistence_revision": persistence_revision, "dirty": dirty, "records": GMStableData.clone(records), "indexes": GMStableData.clone(indexes)}

func restore_snapshot(value: Dictionary) -> Dictionary:
	var shape := _exact_fields(value, ["snapshot_schema", "schema_version", "store_id", "version", "persistence_revision", "dirty", "records", "indexes"])
	if not shape.ok: return {"ok": false, "code": "store.snapshot_shape_invalid", "reason_zh": "Store 存档字段缺失或附加。", "details": shape}
	if typeof(value.get("snapshot_schema")) != TYPE_STRING or value.snapshot_schema != SNAPSHOT_SCHEMA: return {"ok": false, "code": "store.snapshot_schema_invalid", "reason_zh": "Store存档Schema不受支持；旧快照必须由原兼容版本重导。", "expected": SNAPSHOT_SCHEMA}
	if typeof(value.get("schema_version")) != TYPE_STRING or value.schema_version != schema_version: return {"ok": false, "code": "store.schema_invalid", "reason_zh": "Store 数据Schema不匹配。", "expected": schema_version}
	if typeof(value.get("store_id")) != TYPE_STRING or value.store_id != store_id: return {"ok": false, "code": "store.id_invalid", "reason_zh": "Store 存档身份不匹配。", "expected": store_id}
	var version_result := _exact_nonnegative_integer(value.get("version"), "version")
	if not version_result.ok: return version_result
	var revision_result := _exact_nonnegative_integer(value.get("persistence_revision"), "persistence_revision")
	if not revision_result.ok: return revision_result
	if typeof(value.get("dirty")) != TYPE_BOOL: return {"ok": false, "code": "store.dirty_type_invalid", "reason_zh": "Store dirty必须是精确布尔值。"}
	var saved: Variant = value.get("records")
	if not saved is Dictionary: return {"ok": false, "code": "store.records_invalid", "reason_zh": "Store 存档缺少 records 对象。"}
	var stable := GMStableData.validate_persistence(saved, "$.records")
	if not stable.ok: return {"ok": false, "code": "store.records_invalid", "reason_zh": "Store 存档包含运行时对象。", "errors": stable.errors}
	for record_key in saved.keys():
		if typeof(record_key) != TYPE_STRING or not saved[record_key] is Dictionary:
			return {"ok": false, "code": "store.record_shape_invalid", "reason_zh": "Store记录必须使用字符串键和对象值。"}
		var key_check := _validate_key(record_key)
		if not key_check.ok: return key_check
	var saved_indexes: Variant = value.get("indexes")
	if not saved_indexes is Dictionary: return {"ok": false, "code": "store.indexes_invalid", "reason_zh": "Store 存档缺少 indexes 对象。"}
	var index_stable := GMStableData.validate_persistence(saved_indexes, "$.indexes")
	if not index_stable.ok: return {"ok": false, "code": "store.indexes_invalid", "reason_zh": "Store 索引存档包含运行时对象。", "errors": index_stable.errors}
	var saved_index_check := _validate_indexes(saved_indexes, saved)
	if not saved_index_check.ok: return saved_index_check
	var configured_definitions := _index_definitions(indexes)
	if not configured_definitions.ok: return configured_definitions
	if configured_definitions.definitions != saved_index_check.definitions:
		return {"ok": false, "code": "store.index_configuration_mismatch", "reason_zh": "Store 存档索引定义与当前配置不一致。"}
	var expected_indexes := _build_index_projection(saved, saved_index_check.definitions)
	if GMStableData.canonical_json(saved_indexes) != GMStableData.canonical_json(expected_indexes):
		return {"ok": false, "code": "store.index_projection_mismatch", "reason_zh": "Store索引投影与records不一致，拒绝静默重建。"}
	# Atomic Store boundary: every field and the complete derived projection has
	# been validated. The remaining assignments cannot fail.
	records = GMStableData.clone(saved)
	version = version_result.value
	persistence_revision = revision_result.value
	dirty = value.dirty
	indexes = GMStableData.clone(saved_indexes)
	return {"ok": true, "store_id": store_id, "version": version, "persistence_revision": persistence_revision, "dirty": dirty, "record_count": records.size()}

func _exact_fields(value: Dictionary, expected_fields: Array) -> Dictionary:
	var actual: Array[String] = []
	for key in value.keys(): actual.append(str(key))
	actual.sort()
	var expected: Array[String] = []
	for key in expected_fields: expected.append(str(key))
	expected.sort()
	return {"ok": actual == expected, "actual": actual, "expected": expected}

func _index_definitions(value: Dictionary) -> Dictionary:
	var definitions := {}
	for index_id in value.keys():
		var index: Variant = value[index_id]
		if typeof(index_id) != TYPE_STRING or index_id.strip_edges().is_empty() or not index is Dictionary:
			return {"ok": false, "code": "store.index_definition_invalid", "reason_zh": "Store索引定义必须使用非空字符串身份和对象值。"}
		if typeof(index.get("field")) != TYPE_STRING or index.field.strip_edges().is_empty():
			return {"ok": false, "code": "store.index_field_invalid", "reason_zh": "Store索引field必须是非空字符串。"}
		definitions[index_id] = index.field
	return {"ok": true, "definitions": definitions}

func _validate_indexes(value: Dictionary, saved_records: Dictionary) -> Dictionary:
	var definitions_result := _index_definitions(value)
	if not definitions_result.ok: return definitions_result
	for index_id in value.keys():
		var index: Dictionary = value[index_id]
		var shape := _exact_fields(index, ["field", "values"])
		if not shape.ok: return {"ok": false, "code": "store.index_shape_invalid", "reason_zh": "Store索引字段缺失或附加。", "details": shape}
		if not index.values is Dictionary: return {"ok": false, "code": "store.index_values_shape_invalid", "reason_zh": "Store索引values必须是对象。"}
		for value_key in index.values.keys():
			if typeof(value_key) != TYPE_STRING or not index.values[value_key] is Array:
				return {"ok": false, "code": "store.index_bucket_shape_invalid", "reason_zh": "Store索引桶必须使用字符串键和数组值。"}
			var rows: Array = index.values[value_key]
			var seen := {}
			var sorted_rows: Array[String] = []
			for row_key in rows:
				if typeof(row_key) != TYPE_STRING or not saved_records.has(row_key) or seen.has(row_key):
					return {"ok": false, "code": "store.index_record_reference_invalid", "reason_zh": "Store索引含非字符串、未知或重复记录引用。"}
				seen[row_key] = true
				sorted_rows.append(row_key)
			var original_rows: Array[String] = []
			for row_key in rows: original_rows.append(row_key)
			sorted_rows.sort()
			if original_rows != sorted_rows: return {"ok": false, "code": "store.index_order_invalid", "reason_zh": "Store索引记录引用必须使用规范顺序。"}
	return definitions_result

func _build_index_projection(source_records: Dictionary, definitions: Dictionary) -> Dictionary:
	var projected := {}
	var record_keys: Array[String] = []
	for key in source_records.keys(): record_keys.append(key)
	record_keys.sort()
	var index_ids: Array[String] = []
	for index_id in definitions.keys(): index_ids.append(index_id)
	index_ids.sort()
	for index_id in index_ids:
		var field: String = definitions[index_id]
		var values := {}
		for key in record_keys:
			var record: Dictionary = source_records[key]
			if not record.has(field): continue
			var value_key := GMStableData.persistence_canonical_json(record[field])
			if not values.has(value_key): values[value_key] = []
			values[value_key].append(key)
		projected[index_id] = {"field": field, "values": values}
	return projected

func _exact_nonnegative_integer(value: Variant, field_name: String) -> Dictionary:
	if typeof(value) == TYPE_INT:
		if value >= 0 and value <= GMStableData.JSON_SAFE_INTEGER_MAX: return {"ok": true, "value": value}
	elif typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value) and value >= 0.0 and value <= GMStableData.JSON_SAFE_INTEGER_MAX:
		return {"ok": true, "value": int(value)}
	return {"ok": false, "code": "store.%s_invalid" % field_name, "reason_zh": "Store %s必须是JSON边界可精确表示的非负整数。" % field_name}

func _validate_key(key: String) -> Dictionary:
	if key.strip_edges().is_empty() or key.contains("res://") or key.contains("user://") or key.contains("NodePath") or key.begins_with("/"):
		return {"ok": false, "code": "store.key_invalid", "reason_zh": "Store 键必须是稳定业务身份，不能是路径。", "key": key}
	return {"ok": true}

func _rebuild_indexes() -> void:
	for index_id in indexes.keys():
		var index: Dictionary = indexes[index_id]
		var values := {}
		var field := str(index.get("field", ""))
		for key in keys():
			var record: Dictionary = records[key]
			if not record.has(field): continue
			var value_key := GMStableData.persistence_canonical_json(record[field])
			if not values.has(value_key): values[value_key] = []
			values[value_key].append(key)
		index["values"] = values
		indexes[index_id] = index


func _emit_mutation(operation: String, before_component: Dictionary) -> void:
	if mutation_committed.get_connections().is_empty(): return
	mutation_committed.emit({"component_kind": "store", "component_id": store_id, "operation": operation, "before_component": GMStableData.clone(before_component), "after_component": snapshot()})
