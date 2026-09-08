class_name GMChangeRecordStore
extends RefCounted

## 只追加 ChangeRecord 写入器。没有删除或覆盖 API；测试故障注入只模拟写入失败。

var records: Array[GMChangeRecord] = []
var by_id: Dictionary = {}
var by_idempotency: Dictionary = {}
var fail_next_append: bool = false

func append_record_once(record: GMChangeRecord) -> Dictionary:
	return append_batch_once([record])

func append_batch_once(values: Array) -> Dictionary:
	var validation := validate_batch(values)
	if not validation.ok: return validation
	if fail_next_append:
		fail_next_append = false
		return {"ok": false, "code": "change.append_injected_failure", "reason_zh": "ChangeRecord 写入器故障注入，批次未写入。", "appended": false}
	var duplicates: Array = []
	for record in values:
		if by_id.has(record.change_id):
			var existing: GMChangeRecord = by_id[record.change_id]
			if existing.to_dict() != record.to_dict():
				return {"ok": false, "code": "change.id_conflict", "reason_zh": "ChangeRecord ID 已存在但内容不同。", "change_id": record.change_id, "appended": false}
			duplicates.append(record.change_id)
		if by_idempotency.has(record.idempotency_key):
			var existing_by_key: GMChangeRecord = by_idempotency[record.idempotency_key]
			if existing_by_key.to_dict() != record.to_dict():
				return {"ok": false, "code": "change.idempotency_conflict", "reason_zh": "幂等键已对应不同 ChangeRecord。", "idempotency_key": record.idempotency_key, "appended": false}
	for record in values:
		if by_id.has(record.change_id): continue
		var copy := GMChangeRecord.from_dict(record.to_dict())
		records.append(copy)
		by_id[copy.change_id] = copy
		by_idempotency[copy.idempotency_key] = copy
	return {"ok": true, "appended": values.size() - duplicates.size(), "duplicate_skipped": duplicates.size(), "duplicates": duplicates, "record_count": records.size()}

func validate_batch(values: Array) -> Dictionary:
	var errors: Array[String] = []
	var local_ids: Dictionary = {}
	var local_keys: Dictionary = {}
	for value in values:
		if not value is GMChangeRecord:
			errors.append("ChangeRecord store 只接受 GMChangeRecord。")
			continue
		var record: GMChangeRecord = value
		var validation := record.validate()
		if not validation.ok: errors.append_array(validation.errors)
		if local_ids.has(record.change_id): errors.append("ChangeRecord 批次内 ID 重复：%s" % record.change_id)
		local_ids[record.change_id] = true
		if local_keys.has(record.idempotency_key): errors.append("ChangeRecord 批次内幂等键重复：%s" % record.idempotency_key)
		local_keys[record.idempotency_key] = true
	return {"ok": errors.is_empty(), "code": "change.batch_valid" if errors.is_empty() else "change.batch_invalid", "errors": errors}

func contains_id(change_id: String) -> bool:
	return by_id.has(change_id)

func get_by_id(change_id: String) -> GMChangeRecord:
	return by_id.get(change_id, null)

func get_by_idempotency(key: String) -> GMChangeRecord:
	return by_idempotency.get(key, null)

func get_records() -> Array:
	var result: Array = []
	for record in records: result.append(record.to_dict())
	return result

func get_record_count() -> int:
	return records.size()

func snapshot() -> Dictionary:
	return {"schema": GMChangeRecord.SCHEMA_VERSION, "record_count": records.size(), "records": get_records()}
