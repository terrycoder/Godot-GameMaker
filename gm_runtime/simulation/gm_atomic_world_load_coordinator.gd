class_name GMAtomicWorldLoadCoordinator
extends RefCounted

const SPATIAL_CONTRIBUTOR := preload("res://gm_runtime/spatial_core/gm_spatial_snapshot_contributor.gd")

func load(world: RefCounted, value: Dictionary) -> Dictionary:
	if str(value.get("schema_version", "")) != GMReceiptEnvelopeAdapter.WORLD_SCHEMA:
		return _failure("world.save_schema_invalid", "世界存档Schema不匹配；旧world v2/v3/v4不在当前恢复边界内，必须由原兼容版本重导。")
	var top_shape := _fields_with_optional(value, ["schema_version", "world_id", "seed", "tick", "phase", "world_budget_units", "registry", "event_store", "stores", "abstract_commits", "commit_receipts", "post_receipt_journal", "pending_merge", "scheduler_debt", "tick_history"], ["spatial_state"])
	if not top_shape.ok: return _failure("world.save_shape_invalid", "世界存档字段缺失或附加，恢复已拒绝。", top_shape)
	var saved_world_value: Variant = value.get("world_id", null)
	if not saved_world_value is String or str(saved_world_value).is_empty(): return _failure("world.save_identity_invalid", "世界存档world_id无效。")
	var saved_world_id := str(saved_world_value)
	if saved_world_id != str(world.world_id): return _failure("world.save_identity_mismatch", "不能把其他world的存档或收据装入当前世界。", {"expected": world.world_id, "actual": saved_world_id})
	for field_name in ["abstract_commits", "tick_history"]:
		if not value.get(field_name, null) is Array: return _failure("world.save_collection_invalid", "世界存档数组字段形状无效。", {"field": field_name})
	for field_name in ["pending_merge", "scheduler_debt", "stores", "registry", "event_store", "commit_receipts", "post_receipt_journal"]:
		if not value.get(field_name, null) is Dictionary: return _failure("world.save_mapping_invalid", "世界存档映射字段形状无效。", {"field": field_name})
	var stable_world := GMStableData.validate(value)
	if not stable_world.ok: return {"ok": false, "code": "world.save_data_invalid", "reason_zh": "世界存档包含非纯数据。", "errors": stable_world.errors}

	# All components below are detached. No live reference is mutated during validation.
	var staged_registry := GMEntityRegistry.new()
	var registry_result := staged_registry.load_snapshot(value.registry)
	if not registry_result.ok: return registry_result
	var saved_spatial_state: Dictionary = {}
	if value.has("spatial_state"):
		if not value.get("spatial_state", null) is Dictionary: return _failure("spatial.snapshot.invalid", "世界存档spatial_state必须是Dictionary。")
		saved_spatial_state = value.get("spatial_state", {}).duplicate(true)
	var staged_spatial: Dictionary = {}
	if saved_spatial_state.has("map_state") and world.spatial_runtime_context != null and world.spatial_runtime_context.has_method("validate_spatial_registry_against_map_state"):
		staged_spatial = world.spatial_runtime_context.call("validate_spatial_registry_against_map_state", staged_registry, saved_spatial_state.get("map_state"))
	else:
		staged_spatial = SPATIAL_CONTRIBUTOR.validate_registry(staged_registry, world.spatial_runtime_context)
	if not staged_spatial.ok: return _failure("spatial.snapshot.invalid", "空间实体贡献无法暂存，世界保持不变。", staged_spatial)
	if not staged_spatial.positions.is_empty() and not world.has_active_spatial_backend():
		return _failure("spatial.backend.missing", "空间实体存档缺少当前可用的空间执行后端。")
	if not saved_spatial_state.is_empty():
		if not world.has_active_spatial_backend(): return _failure("spatial.backend.missing", "空间存档包含后端状态，但当前世界没有激活对应后端。")
		var context = world.spatial_runtime_context
		if context == null or not context.has_method("validate_spatial_snapshot_state"):
			return _failure("spatial.context_invalid", "空间存档无法通过现有GMRuntimeContext校验。")
		var spatial_state_result = context.call("validate_spatial_snapshot_state", saved_spatial_state)
		if not spatial_state_result.ok: return _failure("spatial.snapshot.invalid", "空间存档状态与当前后端不一致。", spatial_state_result)
	var staged_change_store := GMChangeRecordStore.new()
	var staged_event_store := GMEventStore.new(staged_change_store)
	var configured_archive := staged_event_store.configure_archive_identity(saved_world_id, int(value.event_store.get("archive_epoch", 0)))
	if not configured_archive.ok: return configured_archive
	var event_result := staged_event_store.restore_snapshot(value.event_store)
	if not event_result.ok: return event_result

	var saved_stores: Dictionary = value.stores
	var configured_ids: Array[String] = []
	for store_id in world.stores.keys(): configured_ids.append(str(store_id))
	configured_ids.sort()
	var saved_ids: Array[String] = []
	for store_id in saved_stores.keys(): saved_ids.append(str(store_id))
	saved_ids.sort()
	if saved_ids != configured_ids: return _failure("world.store_set_mismatch", "Store集合与当前世界配置不一致。", {"expected": configured_ids, "actual": saved_ids})
	var staged_stores: Dictionary = {}
	var store_results: Array = []
	for store_id in configured_ids:
		var existing: GMStore = world.stores[store_id]
		var staged_store := GMStore.new(existing.store_id, existing.schema_version)
		for index_id in existing.indexes.keys():
			var index: Dictionary = existing.indexes[index_id]
			var index_result := staged_store.create_index(str(index_id), str(index.get("field", "")))
			if not index_result.ok: return _failure("world.store_index_restore_failed", "Store索引配置无法暂存。", index_result)
		var staged_result := staged_store.restore_snapshot(saved_stores[store_id])
		if not staged_result.ok: return _failure("world.store_restore_failed", "Store存档验证失败，世界保持不变。", staged_result)
		staged_stores[store_id] = staged_store
		store_results.append(staged_result)
	var staged_abstract: Array = GMStableData.clone(value.abstract_commits)

	var receipt_result := GMReceiptEnvelopeAdapter.decode_ledger(value.commit_receipts, saved_world_id, int(world.max_commit_receipts))
	if not receipt_result.ok: return receipt_result
	if int(value.post_receipt_journal.get("epoch", 0)) != int(receipt_result.epoch):
		return _failure("commit.journal_epoch_mismatch", "收据后变更journal与收据账本epoch不一致。")
	var projection_result := GMWorldProjectionStrategy.validate(receipt_result.rows, value.post_receipt_journal, saved_world_id, int(receipt_result.epoch), staged_registry, staged_event_store, staged_stores, staged_abstract)
	if not projection_result.ok: return projection_result

	# Give registered runtime contributors the same detached candidate before
	# the world or any runtime object is committed. A failed participant keeps
	# the existing world, stores and contributor objects untouched.
	var contributor_prepare: Dictionary = world._prepare_atomic_restore_participants(value, staged_stores)
	if not contributor_prepare.ok:
		return contributor_prepare

        # The detached validation above has succeeded. Restore the authored Graph
        # only now, immediately before the existing world atomic swap.
	if saved_spatial_state.has("map_state"):
		var context = world.spatial_runtime_context
		if context == null or not context.has_method("restore_spatial_map_snapshot_state"):
			return _failure("spatial.snapshot.invalid", "空间存档Graph无法通过既有GMRuntimeContext恢复。")
		var map_restore = context.call("restore_spatial_map_snapshot_state", saved_spatial_state.get("map_state"))
		if not map_restore is Dictionary or not bool(map_restore.get("ok", false)):
			return _failure("spatial.snapshot.invalid", "空间存档Graph恢复失败，世界保持不变。", map_restore if map_restore is Dictionary else {})

	# Atomic boundary: all schema, archive lineage, lock projection, receipt envelope,
	# mutation journal and final content cross-references have succeeded. Remaining
	# assignments are no-fail reference/value swaps.
	world._suppress_mutation_journal = true
	world.registry = staged_registry
	world.change_store = staged_change_store
	world.event_store = staged_event_store
	world.stores = staged_stores
	world._commit_receipts = receipt_result.receipts
	world._command_contracts_by_key = receipt_result.command_contracts
	world.commit_receipt_epoch = receipt_result.epoch
	world._next_receipt_sequence = receipt_result.next_sequence
	world._post_receipt_mutations = projection_result.entries
	world._next_mutation_sequence = projection_result.next_sequence
	world._journal_projection_cursor = projection_result.cursor_projection
	world.world_id = saved_world_id
	world.seed = int(value.get("seed", world.seed))
	world.tick = int(value.get("tick", 0))
	world.phase = "reopened"
	world.world_budget_units = int(value.get("world_budget_units", world.world_budget_units))
	world.abstract_commits = staged_abstract
	world.last_merge = GMStableData.clone(value.pending_merge)
	world.scheduler_debt = GMStableData.clone(value.scheduler_debt)
	world.tick_history = GMStableData.clone(value.tick_history)
	if world.domain_resolver != null and is_instance_valid(world.domain_resolver) and world._object_has_property(world.domain_resolver, "registry"):
		world.domain_resolver.set("registry", world.registry)
	world.domain_host.configure_fact_pipeline(world.event_store, world.change_store, world.transaction_coordinator)
	world._bind_mutation_observers()
	world._commit_atomic_restore_participants(contributor_prepare)
	world._notify_store_replaced()
	world._suppress_mutation_journal = false
	return {"ok": true, "registry": registry_result, "event_store": event_result, "stores": store_results, "contributors": {"count": int(contributor_prepare.get("participant_count", 0))}, "tick": world.tick, "event_count": world.event_store.get_record_count()}


static func _exact_fields(value: Dictionary, expected_fields: Array) -> Dictionary:
	var actual: Array[String] = []
	for key in value.keys(): actual.append(str(key))
	actual.sort()
	var expected: Array[String] = []
	for key in expected_fields: expected.append(str(key))
	expected.sort()
	return {"ok": actual == expected, "actual": actual, "expected": expected}

static func _fields_with_optional(value: Dictionary, expected_fields: Array, optional_fields: Array) -> Dictionary:
	var allowed: Array = expected_fields.duplicate()
	allowed.append_array(optional_fields)
	var actual: Array[String] = []
	for key in value.keys(): actual.append(str(key))
	actual.sort()
	var expected: Array[String] = []
	for key in expected_fields:
		expected.append(str(key))
	expected.sort()
	var allowed_sorted: Array[String] = []
	for key in allowed:
		allowed_sorted.append(str(key))
	allowed_sorted.sort()
	var has_all_required := true
	for key in expected:
		if not actual.has(key): has_all_required = false
	var has_only_allowed := true
	for key in actual:
		if not allowed_sorted.has(key): has_only_allowed = false
	return {"ok": has_all_required and has_only_allowed, "actual": actual, "expected": expected, "allowed": allowed_sorted}


static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty(): result["details"] = details
	return result
