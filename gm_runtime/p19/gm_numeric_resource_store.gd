class_name GMNumericResourceStore
extends "res://gm_runtime/simulation/gm_store.gd"

## The sole numeric-resource fact store. Reservations are runtime-only and are
## always cleared on a successful restore.

const STORE_SCHEMA_VERSION := "gm.numeric_resource_store.v1"
const KINDS := ["definition", "account", "change"]
const RESERVATION_SCHEMA := "gm.numeric.reservation.v1"

var reservations: Dictionary = {}

func _init(p_store_id: String = "gm.store.numeric_resource") -> void:
        store_id = p_store_id
        schema_version = STORE_SCHEMA_VERSION

func register_definition(value: Variant, expected_version: int = -1) -> Dictionary:
        if value is Dictionary:
                var integer_check := _validate_integer_fields("definition", value)
                if not integer_check.ok: return integer_check
        var definition: GMNumericResourceDefinition = value if value is GMNumericResourceDefinition else GMNumericResourceDefinition.from_dict(value if value is Dictionary else {})
        return _write_typed("definition", definition.resource_id, definition.to_dict(), expected_version)

func register_account(value: Variant, expected_version: int = -1) -> Dictionary:
        if value is Dictionary:
                var integer_check := _validate_integer_fields("account", value)
                if not integer_check.ok: return integer_check
        var account: GMNumericResourceAccount = value if value is GMNumericResourceAccount else GMNumericResourceAccount.from_dict(value if value is Dictionary else {})
        return _write_typed("account", account.account_id, account.to_dict(), expected_version)

func register_change(value: Variant, expected_version: int = -1) -> Dictionary:
        if value is Dictionary:
                var integer_check := _validate_integer_fields("change", value)
                if not integer_check.ok: return integer_check
        var change: GMNumericResourceChange = value if value is GMNumericResourceChange else GMNumericResourceChange.from_dict(value if value is Dictionary else {})
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
        var keys_sorted: Array[String] = []
        for key in records.keys():
                if str(key).begins_with("%s:" % kind): keys_sorted.append(str(key))
        keys_sorted.sort()
        for key in keys_sorted:
                var wrapped: Variant = records.get(key, {})
                if wrapped is Dictionary and wrapped.get("record", {}) is Dictionary: result.append(wrapped.record.duplicate(true))
        return result

func get_definition(resource_id: String) -> GMNumericResourceDefinition:
        var value := get_typed("definition", resource_id)
        return GMNumericResourceDefinition.from_dict(value) if not value.is_empty() else null

func get_account(account_id: String) -> GMNumericResourceAccount:
        var value := get_typed("account", account_id)
        return GMNumericResourceAccount.from_dict(value) if not value.is_empty() else null

func get_change(change_id: String) -> GMNumericResourceChange:
        var value := get_typed("change", change_id)
        return GMNumericResourceChange.from_dict(value) if not value.is_empty() else null

func accounts_for_resource(resource_id: String) -> Array:
        var result: Array = []
        for value in all_typed("account"):
                if str(value.get("resource_id", "")) == resource_id: result.append(value)
        return result

func apply_atomic(upserts: Array, deletes: Array = [], expected_version: int = -1) -> Dictionary:
        if expected_version >= 0 and expected_version != version:
                return {"ok": false, "code": "numeric.store_version_conflict", "reason_zh": "数值资源Store版本已变化，拒绝提交过期事务。", "expected": expected_version, "actual": version}
        var next_records: Dictionary = records.duplicate(true)
        var delete_keys: Dictionary = {}
        for raw_key in deletes:
                var key := str(raw_key)
                if not _valid_storage_key(key): return {"ok": false, "code": "numeric.store_key_invalid", "reason_zh": "数值资源Store删除键无效。", "key": key}
                delete_keys[key] = true
        for key in delete_keys: next_records.erase(key)
        var seen_upserts: Dictionary = {}
        for row in upserts:
                if not row is Dictionary: return {"ok": false, "code": "numeric.store_upsert_invalid", "reason_zh": "数值资源Store upsert 必须是对象。"}
                var kind := str(row.get("kind", ""))
                var record_id := str(row.get("id", ""))
                var value: Variant = row.get("value", null)
                var key := _key(kind, record_id)
                if not KINDS.has(kind) or record_id.is_empty() or not value is Dictionary:
                        return {"ok": false, "code": "numeric.store_upsert_invalid", "reason_zh": "数值资源Store upsert 的类型、ID或记录无效。", "row": row}
                if seen_upserts.has(key): return {"ok": false, "code": "numeric.store_duplicate_upsert", "reason_zh": "同一数值资源记录在一个事务中重复写入。", "key": key}
                var canonical := _canonicalize_typed(kind, value)
                if not canonical.ok: return {"ok": false, "code": "numeric.store_record_invalid", "reason_zh": "数值资源记录校验失败。", "key": key, "details": canonical}
                if canonical.id != record_id: return {"ok": false, "code": "numeric.store_record_identity_mismatch", "reason_zh": "数值资源记录键与类型化身份不一致。", "key": key, "record_id": canonical.id}
                seen_upserts[key] = true
                next_records[key] = {"record_kind": kind, "record": canonical.value}
        var relation := _validate_relations(next_records)
        if not relation.ok: return relation
        if next_records == records and upserts.is_empty() and deletes.is_empty(): return {"ok": true, "version": version, "changed": false}
        records = next_records
        version += 1
        persistence_revision += 1
        dirty = true
        _rebuild_indexes()
        return {"ok": true, "version": version, "changed": true, "upsert_count": upserts.size(), "delete_count": deletes.size()}

func reserve(transaction_id: String, input_claims: Array, output_claims: Array, expected_version: int) -> Dictionary:
        if transaction_id.is_empty(): return {"ok": false, "code": "numeric.reservation_id_missing", "reason_zh": "数值资源预留缺少事务身份。"}
        var candidate := _reservation_candidate(transaction_id, input_claims, output_claims, expected_version)
        if not candidate.ok: return candidate
        if reservations.has(transaction_id):
                var existing: Dictionary = reservations[transaction_id]
                if GMStableData.canonical_json(existing) == GMStableData.canonical_json(candidate.reservation):
                        return {"ok": true, "duplicate": true, "reservation": existing.duplicate(true), "reservations": [existing.duplicate(true)]}
                return {"ok": false, "code": "numeric.reservation_identity_conflict", "reason_zh": "同一事务身份已经绑定不同数值资源预留。"}
        if expected_version >= 0 and expected_version != version:
                return {"ok": false, "code": "numeric.reservation_version_conflict", "reason_zh": "预留时数值资源Store版本已变化。", "expected": expected_version, "actual": version}
        var input_totals := _claim_totals(input_claims)
        var output_totals := _claim_totals(output_claims)
        var errors: Array[String] = []
        for account_id in input_totals:
                var account := get_account(str(account_id))
                if account == null: errors.append("数值资源账户不存在：%s" % account_id); continue
                var available := account.balance - _reserved_input(str(account_id), transaction_id)
                if available < int(input_totals[account_id]): errors.append("数值资源余额不足：%s 可用%s 请求%s" % [account_id, available, input_totals[account_id]])
        for account_id in output_totals:
                var account := get_account(str(account_id))
                if account == null: errors.append("数值资源目标账户不存在：%s" % account_id); continue
                if account.capacity >= 0:
                        var free := account.capacity - account.balance - _reserved_output(str(account_id), transaction_id)
                        if free < int(output_totals[account_id]): errors.append("数值资源容量不足：%s 可用%s 请求%s" % [account_id, free, output_totals[account_id]])
        if not errors.is_empty(): return {"ok": false, "code": "numeric.reservation_conflict", "reason_zh": "数值资源余额或容量已被并发事务预留。", "errors": errors}
        reservations[transaction_id] = candidate.reservation.duplicate(true)
        return {"ok": true, "reservation": candidate.reservation.duplicate(true), "reservations": [candidate.reservation.duplicate(true)]}

func release_reservation(transaction_id: String) -> Dictionary:
        var existed := reservations.has(transaction_id)
        reservations.erase(transaction_id)
        return {"ok": true, "released": existed, "transaction_id": transaction_id}

func reservation_for(transaction_id: String) -> Dictionary:
        return reservations.get(transaction_id, {}).duplicate(true)

func snapshot() -> Dictionary:
        return super.snapshot()

func restore_snapshot(value: Dictionary) -> Dictionary:
        var boundary := GMStore.new(store_id, schema_version)
        boundary.indexes = GMStableData.clone(indexes)
        var boundary_result := boundary.restore_snapshot(value)
        if not boundary_result.ok: return {"ok": false, "code": "numeric.store_v3_boundary_invalid", "reason_zh": "数值资源快照未通过GMStore v3严格边界。", "details": boundary_result}
        var canonical_records: Dictionary = {}
        for raw_key in boundary.records.keys():
                var key := str(raw_key)
                var wrapped: Variant = boundary.records[key]
                if not wrapped is Dictionary or wrapped.size() != 2 or not wrapped.has("record_kind") or not wrapped.has("record") or not wrapped.record is Dictionary:
                        return {"ok": false, "code": "numeric.snapshot_record_invalid", "reason_zh": "数值资源快照记录缺少精确类型封套。", "key": key}
                var kind := str(wrapped.record_kind)
                var parts := key.split(":", false, 1)
                if parts.size() != 2 or parts[0] != kind: return {"ok": false, "code": "numeric.snapshot_key_kind_mismatch", "reason_zh": "数值资源快照键与类型不一致。", "key": key}
                var canonical := _canonicalize_typed(kind, wrapped.record)
                if not canonical.ok: return {"ok": false, "code": "numeric.snapshot_record_invalid", "reason_zh": "数值资源快照记录校验失败。", "key": key, "details": canonical}
                if parts[1] != str(canonical.id): return {"ok": false, "code": "numeric.snapshot_identity_mismatch", "reason_zh": "数值资源快照记录身份与键不一致。", "key": key}
                canonical_records[_key(kind, str(canonical.id))] = {"record_kind": kind, "record": canonical.value}
        var relation := _validate_relations(canonical_records)
        if not relation.ok: return relation
        boundary.records = canonical_records
        boundary._rebuild_indexes()
        records = GMStableData.clone(boundary.records)
        version = boundary.version
        persistence_revision = boundary.persistence_revision
        dirty = boundary.dirty
        indexes = GMStableData.clone(boundary.indexes)
        reservations.clear()
        return {"ok": true, "store_id": store_id, "version": version, "persistence_revision": persistence_revision, "dirty": dirty, "record_count": records.size()}

func _reservation_candidate(transaction_id: String, input_claims: Array, output_claims: Array, expected_version: int) -> Dictionary:
        var normalized_inputs := _normalize_claims(input_claims, "input")
        if not normalized_inputs.ok: return normalized_inputs
        var normalized_outputs := _normalize_claims(output_claims, "output")
        if not normalized_outputs.ok: return normalized_outputs
        var reservation := {
                "schema": RESERVATION_SCHEMA,
                "reservation_id": "gm.reservation.numeric.%s" % ("%s|numeric" % transaction_id).sha256_text(),
                "participant": "numeric_resource",
                "transaction_id": transaction_id,
                "store_version": version,
                "expected_version": expected_version,
                "input_claims": normalized_inputs.claims,
                "output_claims": normalized_outputs.claims,
        }
        return {"ok": true, "reservation": reservation}

func _normalize_claims(value: Variant, side: String) -> Dictionary:
        if not value is Array: return {"ok": false, "code": "numeric.claims_invalid", "reason_zh": "数值资源预留声明必须是数组。"}
        var result: Array = []
        var seen: Dictionary = {}
        for raw in value:
                if not raw is Dictionary: return {"ok": false, "code": "numeric.claim_invalid", "reason_zh": "数值资源预留声明必须是对象。"}
                var account_id := str(raw.get("account_id", "")).strip_edges()
                var resource_id := str(raw.get("resource_id", "")).strip_edges()
                var raw_amount: Variant = raw.get("amount", raw.get("quantity", 0))
                if typeof(raw_amount) != TYPE_INT: return {"ok": false, "code": "numeric.claim_integer_required", "reason_zh": "数值资源预留数量必须是整数，不接受浮点或字符串。", "claim": raw}
                var amount := int(raw_amount)
                var key := "%s|%s" % [account_id, resource_id]
                if not account_id.begins_with("gm.resource.account.") or not resource_id.begins_with("gm.resource.") or amount <= 0:
                        return {"ok": false, "code": "numeric.claim_invalid", "reason_zh": "数值资源预留账户、资源或数量无效。", "claim": raw}
                var account := get_account(account_id)
                if account == null: return {"ok": false, "code": "numeric.account_missing", "reason_zh": "数值资源预留引用了不存在的账户。", "account_id": account_id}
                if account.resource_id != resource_id: return {"ok": false, "code": "numeric.resource_mismatch", "reason_zh": "数值资源预留账户与资源身份不一致。", "account_id": account_id, "expected": account.resource_id, "actual": resource_id}
                if seen.has(key): return {"ok": false, "code": "numeric.claim_duplicate", "reason_zh": "同一数值资源账户在预留中重复声明。", "claim": raw}
                seen[key] = true
                result.append({"account_id": account_id, "resource_id": resource_id, "amount": amount, "side": side})
        result.sort_custom(func(left: Dictionary, right: Dictionary): return "%s|%s" % [left.account_id, left.resource_id] < "%s|%s" % [right.account_id, right.resource_id])
        return {"ok": true, "claims": result}

func _claim_totals(claims: Array) -> Dictionary:
        var result: Dictionary = {}
        for claim in claims:
                var account_id := str(claim.get("account_id", ""))
                result[account_id] = int(result.get(account_id, 0)) + int(claim.get("amount", 0))
        return result

func _reserved_input(account_id: String, exclude_transaction_id: String) -> int:
        var total := 0
        for tx_id in reservations:
                if str(tx_id) == exclude_transaction_id: continue
                for claim in reservations[tx_id].get("input_claims", []):
                        if str(claim.get("account_id", "")) == account_id: total += int(claim.get("amount", 0))
        return total

func _reserved_output(account_id: String, exclude_transaction_id: String) -> int:
        var total := 0
        for tx_id in reservations:
                if str(tx_id) == exclude_transaction_id: continue
                for claim in reservations[tx_id].get("output_claims", []):
                        if str(claim.get("account_id", "")) == account_id: total += int(claim.get("amount", 0))
        return total

func _validate_relations(candidate_records: Dictionary) -> Dictionary:
        var definitions: Dictionary = {}
        for key in candidate_records:
                var wrapped: Dictionary = candidate_records[key]
                if str(wrapped.get("record_kind", "")) == "definition": definitions[str(wrapped.record.resource_id)] = wrapped.record
        for key in candidate_records:
                var wrapped: Dictionary = candidate_records[key]
                if str(wrapped.get("record_kind", "")) != "account": continue
                var account: Dictionary = wrapped.record
                if not definitions.has(str(account.get("resource_id", ""))): return {"ok": false, "code": "numeric.account_definition_missing", "reason_zh": "Numeric Resource Account 引用了不存在的 Definition。", "account_id": key}
                var definition: Dictionary = definitions[account.resource_id]
                var maximum := int(definition.get("maximum_capacity", -1))
                if maximum >= 0 and int(account.capacity) > maximum: return {"ok": false, "code": "numeric.account_capacity_invalid", "reason_zh": "账户容量超过 Resource Definition 上限。", "account_id": key}
        return {"ok": true}

func _write_typed(kind: String, record_id: String, value: Dictionary, expected_version: int) -> Dictionary:
        return apply_atomic([{"kind": kind, "id": record_id, "value": value}], [], expected_version)

func _canonicalize_typed(kind: String, value: Dictionary) -> Dictionary:
        if not value is Dictionary: return {"ok": false, "code": "numeric.record_type_invalid"}
        var integer_check := _validate_integer_fields(kind, value)
        if not integer_check.ok: return integer_check
        var canonical: Dictionary = {}
        var record_id := ""
        var check: Dictionary = {}
        match kind:
                "definition":
                        var definition := GMNumericResourceDefinition.from_dict(value); check = definition.validate(); canonical = definition.to_dict(); record_id = definition.resource_id
                "account":
                        var account := GMNumericResourceAccount.from_dict(value); check = account.validate(); canonical = account.to_dict(); record_id = account.account_id
                "change":
                        var change := GMNumericResourceChange.from_dict(value); check = change.validate(); canonical = change.to_dict(); record_id = change.change_id
                _:
                        return {"ok": false, "code": "numeric.record_kind_invalid", "kind": kind}
        if not check.ok: return {"ok": false, "code": "numeric.typed_validation_failed", "errors": check.errors}
        var stable := GMStableData.validate_persistence(canonical)
        if not stable.ok: return {"ok": false, "code": "numeric.record_not_persistable", "errors": stable.errors}
        return {"ok": true, "id": record_id, "value": canonical}

func _validate_integer_fields(kind: String, value: Dictionary) -> Dictionary:
        var fields: Array = []
        match kind:
                "definition": fields = ["minimum_value", "maximum_capacity"]
                "account": fields = ["balance", "capacity", "account_version"]
                "change": fields = ["delta", "balance_before", "balance_after"]
                _:
                        return {"ok": false, "code": "numeric.record_kind_invalid", "kind": kind}
        for field in fields:
                if value.has(field) and not _exact_integer(value[field]):
                        return {"ok": false, "code": "numeric.integer_field_required", "reason_zh": "数值资源持久化字段必须是整数，不接受浮点或字符串。", "kind": kind, "field": field}
        return {"ok": true}

static func _exact_integer(value: Variant) -> bool:
        if typeof(value) == TYPE_INT: return abs(value) <= GMStableData.JSON_SAFE_INTEGER_MAX
        if typeof(value) == TYPE_FLOAT:
                return is_finite(value) and value == floor(value) and abs(value) <= float(GMStableData.JSON_SAFE_INTEGER_MAX)
        return false

func _valid_storage_key(key: String) -> bool:
        var parts := key.split(":", false, 1)
        return parts.size() == 2 and KINDS.has(parts[0]) and not parts[1].is_empty() and not parts[1].contains("res://") and not parts[1].contains("user://")

static func _key(kind: String, record_id: String) -> String:
        return "%s:%s" % [kind, record_id]
