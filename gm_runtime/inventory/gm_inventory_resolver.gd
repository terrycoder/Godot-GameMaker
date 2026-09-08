class_name GMInventoryResolver
extends "res://gm_runtime/transactions/gm_domain_resolver.gd"

## The single 05C inventory domain resolver.
## All mutations are planned before reservation and applied once through GMInventoryStore.

const OPERATIONS := ["produce", "gather", "pickup", "trade", "store", "drop", "transfer", "split", "merge", "upgrade_instance", "downgrade_instance", "consume"]

var inventory_store: GMInventoryStore
var feature_flags: GMInventoryFeatureFlags
var plans: Dictionary = {}
var fail_after_apply_once: bool = false
var fail_commit_code: String = ""
var isolated: bool = false
var isolation_report: Dictionary = {}

func _init(p_store: GMInventoryStore = null, p_flags: GMInventoryFeatureFlags = null) -> void:
	resolver_id = "gm.resolver.inventory"
	inventory_store = p_store if p_store != null else GMInventoryStore.new()
	feature_flags = p_flags if p_flags != null else GMInventoryFeatureFlags.new()

func preflight_transaction(transaction: GMDomainTransaction) -> Dictionary:
	if isolated: return _blocked("inventory.resolver_isolated", "库存Resolver处于恢复失败隔离状态，拒绝正常事务。", isolation_report)
	if transaction == null or transaction.request == null:
		return _blocked("inventory.request_missing", "库存事务缺少请求。")
	var flag_check := feature_flags.validate()
	if not flag_check.ok: return _blocked("inventory.feature_flags_invalid", "库存简化开关或来源策略无效。", flag_check)
	var data: Dictionary = transaction.request.event_data.duplicate(true)
	var operation := str(data.get("inventory_operation", data.get("operation", ""))).strip_edges().to_lower()
	if operation.is_empty() or not OPERATIONS.has(operation):
		return _blocked("inventory.operation_invalid", "库存事务操作未注册。", {"operation": operation, "allowed": OPERATIONS})
	var fact_id := str(data.get("planned_fact_event_id", ""))
	if fact_id.is_empty(): fact_id = "gm.fact.inventory.%s" % _slug(transaction.idempotency_key)
	if not fact_id.begins_with("gm.fact."):
		return _blocked("inventory.fact_id_invalid", "库存来源事实必须使用 gm.fact.* 身份。", {"event_id": fact_id})
	var plan: Dictionary = {
		"transaction_id": transaction.transaction_id,
		"idempotency_key": transaction.idempotency_key,
		"operation": operation,
		"fact_id": fact_id,
		"base_version": inventory_store.version,
		"snapshot": inventory_store.snapshot(),
		"upserts": [],
		"deletes": [],
		"source_claims": [],
		"target_claims": [],
		"changeset": [],
		"inventory_changes": [],
		"inputs": [],
		"outputs": [],
		"tags": ["gm.inventory", "gm.inventory.%s" % operation],
		"visibility": {"public": false, "witnesses": []},
		"payload": {"event_id": fact_id, "operation": operation, "inventory_operation": operation, "source_id": str(data.get("source_id", transaction.request.source)), "target_id": str(data.get("target_id", ""))},
		"mutated": false,
		"data": data
	}
	var built: Dictionary = {}
	match operation:
		"produce", "gather": built = _plan_produce(transaction, plan, data)
		"pickup", "trade", "store", "drop", "transfer": built = _plan_move(transaction, plan, data, operation)
		"split": built = _plan_split(transaction, plan, data)
		"merge": built = _plan_merge(transaction, plan, data)
		"upgrade_instance": built = _plan_upgrade(transaction, plan, data)
		"consume": built = _plan_consume(transaction, plan, data)
		"downgrade_instance": built = _blocked("inventory.unique_downgrade_forbidden", "唯一实例不可降级回可堆叠Lot，避免丢失实例身份与历史。")
	if not built.ok: return built
	if plan.has("invalid_change"):
		return _blocked("inventory.change_invalid", "InventoryChange 在预检阶段未通过Schema校验。", plan.invalid_change)
	if plan.inventory_changes.is_empty(): return _blocked("inventory.change_missing", "成功库存事务必须生成 InventoryChange。")
	for identity_key in ["source_id", "target_id", "quantity", "amount", "item_kind", "item_id", "lot_id", "instance_id"]:
		if data.has(identity_key): plan.payload[identity_key] = data[identity_key]
	plan["payload"]["inventory_changes"] = plan.inventory_changes.duplicate(true)
	plan["payload"]["changeset_count"] = plan.changeset.size()
	plans[transaction.transaction_id] = plan
	transaction.commit_payload["event_id"] = fact_id
	return {"ok": true, "stage": "PREFLIGHT", "operation": operation, "store_version": inventory_store.version, "inputs": plan.inputs, "outputs": plan.outputs, "changeset": plan.changeset}

func reserve_transaction(transaction: GMDomainTransaction) -> Dictionary:
	var plan: Dictionary = plans.get(transaction.transaction_id, {})
	if plan.is_empty(): return _blocked("inventory.plan_missing", "库存事务没有预检计划。")
	var result := inventory_store.reserve(transaction.transaction_id, plan.source_claims, plan.target_claims, int(plan.base_version))
	if not result.ok: return result
	plan["reservation"] = result.get("reservation", {})
	plans[transaction.transaction_id] = plan
	return {"ok": true, "stage": "RESERVE", "reservations": result.get("reservations", [plan.reservation])}

func commit_transaction(transaction: GMDomainTransaction) -> Dictionary:
	var plan: Dictionary = plans.get(transaction.transaction_id, {})
	if plan.is_empty(): return _blocked("inventory.plan_missing", "库存事务没有预检计划。")
	if inventory_store.version != int(plan.base_version):
		return _blocked("inventory.store_version_conflict", "提交前库存Store版本已变化，拒绝使用过期计划。", {"expected": plan.base_version, "actual": inventory_store.version})
	if inventory_store.reservation_for(transaction.transaction_id).is_empty():
		return _blocked("inventory.reservation_missing", "提交前库存资源预留已丢失。")
	var applied := inventory_store.apply_atomic(plan.upserts, plan.deletes, int(plan.base_version))
	if not applied.ok: return applied
	plan["mutated"] = true
	plans[transaction.transaction_id] = plan
	if not fail_commit_code.is_empty():
		var code := fail_commit_code
		fail_commit_code = ""
		return _blocked(code, "库存提交故障注入，事务必须回滚。")
	if fail_after_apply_once:
		fail_after_apply_once = false
		return _blocked("inventory.commit_injected_failure", "库存提交后故障注入，事务必须回滚。")
	return {"ok": true, "stage": "COMMIT", "payload": plan.payload, "inputs": plan.inputs, "outputs": plan.outputs, "tags": plan.tags, "visibility": plan.visibility, "changeset": plan.changeset}

func rollback_transaction(transaction: GMDomainTransaction, reason_zh: String) -> Dictionary:
	var plan: Dictionary = plans.get(transaction.transaction_id, {})
	if plan.is_empty():
		inventory_store.release_reservation(transaction.transaction_id)
		return {"ok": true, "stage": "ROLLBACK", "rolled_back": true, "reason_zh": reason_zh, "plan_missing": true}
	var restored := true
	if bool(plan.get("mutated", false)):
		var other_reservations: Dictionary = inventory_store.reservations.duplicate(true)
		var restore_result := inventory_store.restore_snapshot(plan.get("snapshot", {}))
		restored = bool(restore_result.get("ok", false))
		if restored: inventory_store.reservations = other_reservations
	if restored: inventory_store.release_reservation(transaction.transaction_id)
	plans.erase(transaction.transaction_id)
	return {"ok": restored, "stage": "ROLLBACK", "rolled_back": restored, "reason_zh": reason_zh, "restored_store": restored}

func capture_transaction_state(_transaction: GMDomainTransaction) -> Dictionary:
	if isolated: return _blocked("inventory.resolver_isolated", "库存Resolver处于隔离状态，不能建立恢复点。", isolation_report)
	return {
		"ok": true,
		"contract": "gm.inventory.recovery.v2",
		"snapshot": {
			"store": inventory_store.snapshot(),
			"reservations": GMStableData.clone(inventory_store.reservations),
		}
	}

func restore_transaction_state(_transaction: GMDomainTransaction, snapshot: Variant) -> Dictionary:
	if not snapshot is Dictionary or not snapshot.get("store", null) is Dictionary or not snapshot.get("reservations", null) is Dictionary:
		return _blocked("inventory.recovery_snapshot_invalid", "库存恢复点结构无效。")
	var current_store: Dictionary = inventory_store.snapshot()
	var current_reservations: Dictionary = GMStableData.clone(inventory_store.reservations)
	var restored: Dictionary = inventory_store.restore_snapshot(snapshot.store)
	if not restored.ok:
		# restore_snapshot is atomic, nevertheless retain an explicit defensive path.
		inventory_store.restore_snapshot(current_store)
		inventory_store.reservations = current_reservations
		return _blocked("inventory.recovery_restore_failed", "库存Store无法从提交前恢复点还原。", {"restore": restored})
	inventory_store.reservations = GMStableData.clone(snapshot.reservations)
	return {"ok": true, "stage": "RECOVERY", "restored": true, "contract": "gm.inventory.recovery.v2"}

func release_transaction_reservations(transaction: GMDomainTransaction) -> Dictionary:
	if transaction == null: return _blocked("inventory.transaction_missing", "释放库存预留需要事务身份。")
	return inventory_store.release_reservation(transaction.transaction_id)

func isolate_transaction_state(transaction: GMDomainTransaction, failure: Dictionary) -> Dictionary:
	isolated = true
	isolation_report = {"transaction_id": transaction.transaction_id if transaction != null else "", "failure": failure.duplicate(true)}
	inventory_store.reservations.clear()
	return {"ok": true, "isolated": true, "resolver_id": resolver_id, "transaction_id": isolation_report.transaction_id}

func finalize_transaction(transaction: GMDomainTransaction) -> Dictionary:
	inventory_store.release_reservation(transaction.transaction_id)
	plans.erase(transaction.transaction_id)
	return {"ok": true, "stage": "FINALIZE", "finalized": true}

func version_for(key: String) -> int:
	if key.is_empty() or key == inventory_store.store_id or key == "inventory" or key == "gm.store.inventory": return inventory_store.version
	return 0

func planned_transaction_plan(transaction_id: String) -> Dictionary:
	var value: Variant = plans.get(transaction_id, {})
	return value.duplicate(true) if value is Dictionary else {}

func build_candidate(request: GMAbilityActivationRequest, chain: GMCausalChain) -> GMCandidateResult:
	return GMCandidateResult.from_request(request, chain, 1.0, ["库存事务具备统一预检、预留、提交与回滚路径。"])

func _plan_produce(transaction: GMDomainTransaction, plan: Dictionary, data: Dictionary) -> Dictionary:
	var definition_id := str(data.get("definition_id", data.get("item_definition_id", "")))
	var definition := inventory_store.get_definition(definition_id)
	if definition == null: return _blocked("inventory.definition_missing", "生产或采集引用的Definition不存在。", {"definition_id": definition_id})
	var quantity := int(data.get("quantity", data.get("amount", 0)))
	if quantity <= 0 or quantity > definition.max_stack: return _blocked("inventory.quantity_invalid", "生产数量必须在Definition堆叠上限内。", {"quantity": quantity, "max_stack": definition.max_stack})
	if not definition.stackable and quantity != 1: return _blocked("inventory.unique_quantity_invalid", "不可堆叠Definition一次只能生成一个物品。")
	var target_id := str(data.get("target_container_id", data.get("container_id", "")))
	var target := inventory_store.get_container(target_id)
	if target == null: return _blocked("inventory.target_container_missing", "生产目标容器不存在。", {"container_id": target_id})
	var lot_id := str(data.get("lot_id", ""))
	if lot_id.is_empty(): lot_id = "gm.item.lot.%s" % _slug(plan.fact_id + "." + definition_id)
	if inventory_store.has_typed("lot", lot_id): return _blocked("inventory.item_id_conflict", "生产生成的Lot ID已存在。", {"lot_id": lot_id})
	var provenance_id := "gm.provenance.%s" % _slug(plan.fact_id + ".source")
	var source_kind := str(data.get("source_kind", "production" if plan.operation == "produce" else "gathered"))
	if not GMProvenanceRecord.SOURCE_KINDS.has(source_kind): return _blocked("inventory.source_kind_invalid", "生产来源策略未注册。", {"source_kind": source_kind})
	var provenance := GMProvenanceRecord.new().configure(provenance_id, plan.fact_id, source_kind, [], [plan.fact_id], {"definition_id": definition_id})
	var lot := GMItemLot.new().configure(lot_id, definition_id, quantity, int(data.get("quality", 100)), data.get("variant", {}) if data.get("variant", {}) is Dictionary else {}, GMItemLot._unique_strings(data.get("tags", Array(definition.tags))), provenance_id, plan.fact_id)
	var owner_id := str(data.get("owner_id", data.get("source_id", transaction.request.source))).strip_edges()
	var holder_id := str(data.get("holder_id", owner_id)).strip_edges()
	if owner_id.is_empty() or holder_id.is_empty(): return _blocked("inventory.owner_missing", "生成库存物品必须明确Owner和Holder。")
	var ownership := GMOwnershipRecord.new().configure(GMOwnershipRecord.make_id("lot", lot_id), "lot", lot_id, owner_id, holder_id, target_id, "owned", plan.fact_id, [plan.fact_id])
	var target_copy := GMInventoryContainer.from_dict(target.to_dict())
	var add_result := target_copy.add_quantity("lot", lot_id, quantity)
	if not add_result.ok: return add_result
	_add_upsert(plan, "provenance", provenance_id, provenance.to_dict())
	_add_upsert(plan, "lot", lot_id, lot.to_dict())
	_add_upsert(plan, "ownership", ownership.ownership_id, ownership.to_dict())
	_add_upsert(plan, "container", target_id, target_copy.to_dict())
	plan.target_claims.append({"container_id": target_id, "slots": 1 if not target.has_item("lot", lot_id) else 0})
	plan.inputs.append(definition_id)
	plan.outputs.append(lot_id)
	_add_change(plan, transaction, plan.operation, "lot", lot_id, quantity, "", target_id, "", owner_id, "", holder_id, "", target_id, provenance_id, 0, quantity, "生成库存Lot。", {"source_kind": source_kind})
	return {"ok": true}

func _plan_move(transaction: GMDomainTransaction, plan: Dictionary, data: Dictionary, operation: String) -> Dictionary:
	var item_kind := str(data.get("item_kind", "lot"))
	var item_id := str(data.get("item_id", data.get("lot_id", data.get("instance_id", ""))))
	if not ["lot", "instance"].has(item_kind) or item_id.is_empty(): return _blocked("inventory.item_reference_invalid", "库存转移缺少Lot或Instance引用。")
	var ownership := inventory_store.find_ownership(item_kind, item_id)
	if ownership == null: return _blocked("inventory.ownership_missing", "库存转移物品没有OwnershipRecord。", {"item_kind": item_kind, "item_id": item_id})
	var source_id := str(data.get("source_container_id", ownership.container_id))
	var target_id := str(data.get("target_container_id", data.get("container_id", "")))
	if source_id.is_empty() or target_id.is_empty() or source_id == target_id: return _blocked("inventory.container_route_invalid", "库存转移必须有不同的源容器和目标容器。")
	var source := inventory_store.get_container(source_id)
	var target := inventory_store.get_container(target_id)
	if source == null or target == null: return _blocked("inventory.container_missing", "库存转移的源或目标容器不存在。")
	var total := source.quantity_for(item_kind, item_id)
	var quantity := int(data.get("quantity", total))
	if quantity <= 0 or quantity > total: return _blocked("inventory.source_insufficient", "源容器中的物品数量不足。", {"available": total, "requested": quantity})
	if item_kind == "instance" and quantity != 1: return _blocked("inventory.instance_quantity_invalid", "唯一Instance数量固定为1。")
	var target_owner := ownership.owner_id
	var target_holder := ownership.holder_id
	var custody := ownership.custody_type
	match operation:
		"pickup":
			target_holder = str(data.get("target_holder_id", data.get("holder_id", transaction.request.source)))
			custody = "owned"
		"trade":
			target_owner = str(data.get("target_owner_id", data.get("new_owner_id", data.get("target_id", ""))))
			target_holder = str(data.get("target_holder_id", target_owner))
			custody = "owned"
		"store":
			target_holder = str(data.get("target_holder_id", data.get("holder_id", ownership.holder_id)))
			custody = "stored"
		"drop":
			target_holder = str(data.get("target_holder_id", "gm.actor.world"))
			custody = "dropped"
		"transfer":
			target_owner = str(data.get("target_owner_id", data.get("new_owner_id", ownership.owner_id)))
			target_holder = str(data.get("target_holder_id", data.get("holder_id", ownership.holder_id)))
			custody = str(data.get("custody_type", ownership.custody_type))
	if target_owner.is_empty() or target_holder.is_empty(): return _blocked("inventory.owner_missing", "库存转移的Owner或Holder不能为空。")
	var source_copy := GMInventoryContainer.from_dict(source.to_dict())
	var target_copy := GMInventoryContainer.from_dict(target.to_dict())
	var full_move := quantity == total
	var routed_kind := item_kind
	var routed_id := item_id
	var routed_provenance := ""
	var routed_quantity := quantity
	var item_before: Dictionary = {}
	if item_kind == "lot":
		var lot := inventory_store.get_lot(item_id)
		if lot == null: return _blocked("inventory.lot_missing", "库存转移的Lot不存在。")
		item_before = lot.to_dict()
		routed_provenance = lot.provenance_id
		if not full_move:
			var child_id := str(data.get("new_lot_id", ""))
			if child_id.is_empty(): child_id = "gm.item.lot.%s" % _slug(plan.fact_id + ".partial")
			if inventory_store.has_typed("lot", child_id): return _blocked("inventory.item_id_conflict", "部分转移生成的Lot ID已存在。", {"lot_id": child_id})
			var child_provenance_id := "gm.provenance.%s" % _slug(plan.fact_id + ".partial")
			var child_provenance := _child_provenance(lot.provenance_id, lot.source_fact_id, child_provenance_id, plan.fact_id)
			var child_lot := GMItemLot.new().configure(child_id, lot.definition_id, quantity, lot.quality, lot.variant, lot.tags, child_provenance_id, plan.fact_id)
			lot.quantity -= quantity
			routed_id = child_id
			routed_provenance = child_provenance_id
			_add_upsert(plan, "lot", lot.lot_id, lot.to_dict())
			_add_upsert(plan, "provenance", child_provenance_id, child_provenance.to_dict())
			_add_upsert(plan, "lot", child_id, child_lot.to_dict())
			var child_ownership := GMOwnershipRecord.new().configure(GMOwnershipRecord.make_id("lot", child_id), "lot", child_id, target_owner, target_holder, target_id, custody, plan.fact_id, [plan.fact_id])
			_add_upsert(plan, "ownership", child_ownership.ownership_id, child_ownership.to_dict())
			plan.outputs.append(child_id)
		else:
			var moved_ownership := ownership.transfer(target_owner, target_holder, target_id, custody, plan.fact_id)
			if not moved_ownership.ok: return moved_ownership
			_add_upsert(plan, "ownership", ownership.ownership_id, moved_ownership.record)
			plan.outputs.append(lot.lot_id)
	else:
		var instance := inventory_store.get_instance(item_id)
		if instance == null: return _blocked("inventory.instance_missing", "库存转移的Instance不存在。")
		item_before = instance.to_dict()
		routed_provenance = instance.provenance_id
		var moved_instance_ownership := ownership.transfer(target_owner, target_holder, target_id, custody, plan.fact_id)
		if not moved_instance_ownership.ok: return moved_instance_ownership
		_add_upsert(plan, "ownership", ownership.ownership_id, moved_instance_ownership.record)
		plan.outputs.append(item_id)
	var remove_result := source_copy.remove_quantity(item_kind, item_id, quantity)
	if not remove_result.ok: return remove_result
	var add_result := target_copy.add_quantity(routed_kind, routed_id, routed_quantity)
	if not add_result.ok: return add_result
	_add_upsert(plan, "container", source_id, source_copy.to_dict())
	_add_upsert(plan, "container", target_id, target_copy.to_dict())
	plan.source_claims.append({"container_id": source_id, "item_kind": item_kind, "item_id": item_id, "quantity": quantity})
	plan.target_claims.append({"container_id": target_id, "slots": 1 if not target.has_item(routed_kind, routed_id) else 0})
	plan.inputs.append(item_id)
	if not full_move and item_kind == "lot":
		var source_lot := inventory_store.get_lot(item_id)
		_add_change(plan, transaction, operation, "lot", item_id, -quantity, source_id, source_id, ownership.owner_id, ownership.owner_id, ownership.holder_id, ownership.holder_id, source_id, source_id, source_lot.provenance_id, total, total - quantity, "部分转移已减少源Lot。", {"paired_item_id": routed_id, "side": "source", "custody_type": ownership.custody_type})
		_add_change(plan, transaction, operation, "lot", routed_id, quantity, source_id, target_id, "", target_owner, "", target_holder, "", target_id, routed_provenance, 0, quantity, "部分转移已建立目标子Lot。", {"paired_item_id": item_id, "side": "target", "custody_type": custody})
	else:
		# A whole-item move changes location/ownership but not the item's quantity.
		_add_change(plan, transaction, operation, routed_kind, routed_id, 0, source_id, target_id, ownership.owner_id, target_owner, ownership.holder_id, target_holder, source_id, target_id, routed_provenance, total, total, "库存物品已转移。", {"source_item_id": item_id, "full_move": true, "custody_type": custody})
	return {"ok": true}

func _plan_split(transaction: GMDomainTransaction, plan: Dictionary, data: Dictionary) -> Dictionary:
	var lot_id := str(data.get("lot_id", data.get("item_id", "")))
	var lot := inventory_store.get_lot(lot_id)
	if lot == null: return _blocked("inventory.lot_missing", "拆分源Lot不存在。")
	var ownership := inventory_store.find_ownership("lot", lot_id)
	if ownership == null: return _blocked("inventory.ownership_missing", "拆分源Lot没有OwnershipRecord。")
	var split_quantity := int(data.get("split_quantity", data.get("quantity", 0)))
	var split_check := lot.can_split(split_quantity)
	if not split_check.ok: return split_check
	var child_id := str(data.get("new_lot_id", ""))
	if child_id.is_empty(): child_id = "gm.item.lot.%s" % _slug(plan.fact_id + ".split")
	if inventory_store.has_typed("lot", child_id): return _blocked("inventory.item_id_conflict", "拆分生成的Lot ID已存在。")
	var provenance_id := "gm.provenance.%s" % _slug(plan.fact_id + ".split")
	var provenance := _child_provenance(lot.provenance_id, lot.source_fact_id, provenance_id, plan.fact_id)
	var child := GMItemLot.new().configure(child_id, lot.definition_id, split_quantity, lot.quality, lot.variant, lot.tags, provenance_id, plan.fact_id)
	var container := inventory_store.get_container(ownership.container_id)
	if container == null: return _blocked("inventory.container_missing", "拆分源Lot容器不存在。")
	var copy := GMInventoryContainer.from_dict(container.to_dict())
	var remove_result := copy.remove_quantity("lot", lot_id, split_quantity)
	if not remove_result.ok: return remove_result
	var add_result := copy.add_quantity("lot", child_id, split_quantity)
	if not add_result.ok: return add_result
	lot.quantity -= split_quantity
	var child_ownership := GMOwnershipRecord.new().configure(GMOwnershipRecord.make_id("lot", child_id), "lot", child_id, ownership.owner_id, ownership.holder_id, ownership.container_id, ownership.custody_type, plan.fact_id, [plan.fact_id])
	_add_upsert(plan, "lot", lot.lot_id, lot.to_dict())
	_add_upsert(plan, "lot", child_id, child.to_dict())
	_add_upsert(plan, "provenance", provenance_id, provenance.to_dict())
	_add_upsert(plan, "ownership", child_ownership.ownership_id, child_ownership.to_dict())
	_add_upsert(plan, "container", ownership.container_id, copy.to_dict())
	plan.source_claims.append({"container_id": ownership.container_id, "item_kind": "lot", "item_id": lot_id, "quantity": split_quantity})
	plan.target_claims.append({"container_id": ownership.container_id, "slots": 1})
	plan.inputs.append(lot_id)
	plan.outputs.append(child_id)
	_add_change(plan, transaction, "split", "lot", lot_id, -split_quantity, ownership.container_id, ownership.container_id, ownership.owner_id, ownership.owner_id, ownership.holder_id, ownership.holder_id, ownership.container_id, ownership.container_id, lot.provenance_id, lot.quantity + split_quantity, lot.quantity, "拆分已减少源Lot。", {"paired_item_id": child_id, "side": "source"})
	_add_change(plan, transaction, "split", "lot", child_id, split_quantity, ownership.container_id, ownership.container_id, ownership.owner_id, ownership.owner_id, ownership.holder_id, ownership.holder_id, ownership.container_id, ownership.container_id, provenance_id, 0, split_quantity, "拆分已建立子Lot并保留来源链。", {"paired_item_id": lot_id, "side": "target"})
	return {"ok": true}

func _plan_merge(transaction: GMDomainTransaction, plan: Dictionary, data: Dictionary) -> Dictionary:
	var source_id := str(data.get("source_lot_id", data.get("source_id", "")))
	var target_id := str(data.get("target_lot_id", data.get("target_id", "")))
	var source := inventory_store.get_lot(source_id)
	var target := inventory_store.get_lot(target_id)
	if source == null or target == null: return _blocked("inventory.lot_missing", "合并需要两个现存Lot。")
	if source_id == target_id: return _blocked("inventory.merge_same_lot", "不能把Lot合并到自身。")
	var source_ownership := inventory_store.find_ownership("lot", source_id)
	var target_ownership := inventory_store.find_ownership("lot", target_id)
	if source_ownership == null or target_ownership == null: return _blocked("inventory.ownership_missing", "合并Lot必须各自有OwnershipRecord。")
	if source_ownership.owner_id != target_ownership.owner_id or source_ownership.holder_id != target_ownership.holder_id or source_ownership.container_id != target_ownership.container_id:
		return _blocked("inventory.merge_ownership_mismatch", "不同Owner、Holder或Container的Lot不可直接合并。")
	var policy := str(data.get("source_merge_policy", feature_flags.source_merge_policy))
	var merge_check := target.can_merge_with(source, policy)
	if not merge_check.ok: return merge_check
	var container := inventory_store.get_container(target_ownership.container_id)
	if container == null: return _blocked("inventory.container_missing", "合并Lot容器不存在。")
	var copy := GMInventoryContainer.from_dict(container.to_dict())
	var removed := copy.remove_quantity("lot", source_id, source.quantity)
	if not removed.ok: return removed
	var added := copy.add_quantity("lot", target_id, source.quantity)
	if not added.ok: return added
	var merged_provenance_id := target.provenance_id
	if source.provenance_id != target.provenance_id:
		merged_provenance_id = "gm.provenance.%s" % _slug(plan.fact_id + ".merge")
		var merged := GMProvenanceRecord.new().configure(merged_provenance_id, plan.fact_id, "merged", [target.provenance_id, source.provenance_id], [target.source_fact_id, source.source_fact_id, plan.fact_id], {})
		_add_upsert(plan, "provenance", merged_provenance_id, merged.to_dict())
	target.quantity += source.quantity
	target.provenance_id = merged_provenance_id
	_add_upsert(plan, "lot", target.lot_id, target.to_dict())
	_add_delete(plan, "lot", source.lot_id)
	_add_delete(plan, "ownership", source_ownership.ownership_id)
	_add_upsert(plan, "container", target_ownership.container_id, copy.to_dict())
	plan.source_claims.append({"container_id": target_ownership.container_id, "item_kind": "lot", "item_id": source_id, "quantity": source.quantity})
	plan.inputs.append(source_id)
	plan.inputs.append(target_id)
	plan.outputs.append(target_id)
	_add_change(plan, transaction, "merge", "lot", target_id, source.quantity, target_ownership.container_id, target_ownership.container_id, target_ownership.owner_id, target_ownership.owner_id, target_ownership.holder_id, target_ownership.holder_id, target_ownership.container_id, target_ownership.container_id, merged_provenance_id, target.quantity - source.quantity, target.quantity, "库存Lot已合并并保留来源策略结果。", {"source_lot_id": source_id, "source_merge_policy": policy})
	return {"ok": true}

func _plan_upgrade(transaction: GMDomainTransaction, plan: Dictionary, data: Dictionary) -> Dictionary:
	var lot_id := str(data.get("lot_id", data.get("item_id", "")))
	var lot := inventory_store.get_lot(lot_id)
	if lot == null: return _blocked("inventory.lot_missing", "唯一实例升级的源Lot不存在。")
	var ownership := inventory_store.find_ownership("lot", lot_id)
	if ownership == null: return _blocked("inventory.ownership_missing", "唯一实例升级的源Lot没有OwnershipRecord。")
	var quantity := int(data.get("quantity", 1))
	if quantity != 1 or lot.quantity < 1: return _blocked("inventory.unique_quantity_invalid", "唯一实例升级每次只能消耗一个Lot单位。")
	var container := inventory_store.get_container(ownership.container_id)
	if container == null: return _blocked("inventory.container_missing", "唯一实例升级容器不存在。")
	var copy := GMInventoryContainer.from_dict(container.to_dict())
	var remove_result := copy.remove_quantity("lot", lot_id, 1)
	if not remove_result.ok: return remove_result
	lot.quantity -= 1
	if lot.quantity <= 0:
		_add_delete(plan, "lot", lot_id)
		_add_delete(plan, "ownership", ownership.ownership_id)
	else: _add_upsert(plan, "lot", lot_id, lot.to_dict())
	var provenance_id := "gm.provenance.%s" % _slug(plan.fact_id + ".upgrade")
	var provenance: GMProvenanceRecord
	if feature_flags.detailed_provenance:
		provenance = GMProvenanceRecord.new().configure(provenance_id, plan.fact_id, "converted", [lot.provenance_id], [lot.source_fact_id, plan.fact_id], {"upgrade_rule_id": str(data.get("upgrade_rule_id", "gm.item.upgrade"))})
	else:
		provenance = GMProvenanceRecord.simplified(provenance_id, plan.fact_id, "converted")
	_add_upsert(plan, "provenance", provenance_id, provenance.to_dict())
	var destination_kind := "instance"
	var destination_id := ""
	var destination_quantity := 1
	var destination_ownership_kind := "instance"
	if feature_flags.unique_instances_enabled:
		destination_id = str(data.get("instance_id", ""))
		if destination_id.is_empty(): destination_id = "gm.item.instance.%s" % _slug(plan.fact_id)
		if inventory_store.has_typed("instance", destination_id): return _blocked("inventory.item_id_conflict", "唯一Instance ID已存在。")
		var instance := GMItemInstance.new().configure(destination_id, lot.definition_id, lot.quality, lot.variant, provenance_id, lot_id, [lot_id, lot.provenance_id, lot.source_fact_id, plan.fact_id], str(data.get("upgrade_rule_id", "gm.item.upgrade")), 1)
		_add_upsert(plan, "instance", destination_id, instance.to_dict())
	else:
		destination_kind = "lot"
		destination_ownership_kind = "lot"
		destination_id = str(data.get("new_lot_id", ""))
		if destination_id.is_empty(): destination_id = "gm.item.lot.%s" % _slug(plan.fact_id + ".simplified")
		if inventory_store.has_typed("lot", destination_id): return _blocked("inventory.item_id_conflict", "简化升级生成的Lot ID已存在。")
		var simplified_variant := lot.variant.duplicate(true)
		simplified_variant["gm_simplified_upgrade"] = str(data.get("upgrade_rule_id", "gm.item.upgrade"))
		var simplified_lot := GMItemLot.new().configure(destination_id, lot.definition_id, 1, lot.quality, simplified_variant, lot.tags, provenance_id, plan.fact_id)
		_add_upsert(plan, "lot", destination_id, simplified_lot.to_dict())
	var add_result := copy.add_quantity(destination_kind, destination_id, destination_quantity)
	if not add_result.ok: return add_result
	var new_ownership := GMOwnershipRecord.new().configure(GMOwnershipRecord.make_id(destination_ownership_kind, destination_id), destination_ownership_kind, destination_id, ownership.owner_id, ownership.holder_id, ownership.container_id, ownership.custody_type, plan.fact_id, [plan.fact_id])
	_add_upsert(plan, "ownership", new_ownership.ownership_id, new_ownership.to_dict())
	_add_upsert(plan, "container", ownership.container_id, copy.to_dict())
	plan.source_claims.append({"container_id": ownership.container_id, "item_kind": "lot", "item_id": lot_id, "quantity": 1})
	plan.target_claims.append({"container_id": ownership.container_id, "slots": 1})
	plan.inputs.append(lot_id)
	plan.outputs.append(destination_id)
	_add_change(plan, transaction, "upgrade_instance" if feature_flags.unique_instances_enabled else "simplified_upgrade", destination_kind, destination_id, 1, ownership.container_id, ownership.container_id, ownership.owner_id, ownership.owner_id, ownership.holder_id, ownership.holder_id, ownership.container_id, ownership.container_id, provenance_id, 0, 1, "Lot已升级为唯一Instance。" if feature_flags.unique_instances_enabled else "简化模式下Lot已升级为新的可堆叠记录。", {"source_lot_id": lot_id, "unique_instances_enabled": feature_flags.unique_instances_enabled})
	return {"ok": true}

func _plan_consume(transaction: GMDomainTransaction, plan: Dictionary, data: Dictionary) -> Dictionary:
	var item_kind := str(data.get("item_kind", "lot")).strip_edges().to_lower()
	var item_id := str(data.get("item_id", data.get("lot_id", data.get("instance_id", "")))).strip_edges()
	if not ["lot", "instance"].has(item_kind) or item_id.is_empty(): return _blocked("inventory.consume_reference_invalid", "消耗事务缺少稳定Lot或Instance引用。")
	var ownership := inventory_store.find_ownership(item_kind, item_id)
	if ownership == null: return _blocked("inventory.ownership_missing", "消耗物品没有OwnershipRecord。", {"item_kind": item_kind, "item_id": item_id})
	var source_id := str(data.get("source_container_id", ownership.container_id)).strip_edges()
	var source := inventory_store.get_container(source_id)
	if source == null: return _blocked("inventory.source_container_missing", "消耗物品的源容器不存在。", {"container_id": source_id})
	var available := source.quantity_for(item_kind, item_id)
	var quantity := int(data.get("quantity", data.get("amount", 1)))
	if quantity <= 0 or quantity > available: return _blocked("inventory.source_insufficient", "消耗数量超过源容器实际库存。", {"available": available, "requested": quantity, "item_id": item_id})
	if item_kind == "instance" and quantity != 1: return _blocked("inventory.instance_quantity_invalid", "唯一Instance每次只能消耗一个。")
	var source_copy := GMInventoryContainer.from_dict(source.to_dict())
	var removed := source_copy.remove_quantity(item_kind, item_id, quantity)
	if not removed.ok: return removed
	var before_quantity := available
	var after_quantity := available - quantity
	if item_kind == "lot":
		var lot := inventory_store.get_lot(item_id)
		if lot == null: return _blocked("inventory.lot_missing", "消耗引用的Lot不存在。", {"lot_id": item_id})
		if quantity == lot.quantity:
			_add_delete(plan, "lot", item_id)
			_add_delete(plan, "ownership", ownership.ownership_id)
		else:
			lot.quantity -= quantity
			_add_upsert(plan, "lot", lot.lot_id, lot.to_dict())
		plan.inputs.append(item_id)
		_add_change(plan, transaction, "consume", item_kind, item_id, -quantity, source_id, "", ownership.owner_id, ownership.owner_id, ownership.holder_id, ownership.holder_id, source_id, source_id, lot.provenance_id, before_quantity, after_quantity, "库存物品已被消耗。", {"consumed": true, "definition_id": lot.definition_id})
	else:
		var instance := inventory_store.get_instance(item_id)
		if instance == null: return _blocked("inventory.instance_missing", "消耗引用的Instance不存在。", {"instance_id": item_id})
		_add_delete(plan, "instance", item_id)
		_add_delete(plan, "ownership", ownership.ownership_id)
		plan.inputs.append(item_id)
		_add_change(plan, transaction, "consume", item_kind, item_id, -quantity, source_id, "", ownership.owner_id, ownership.owner_id, ownership.holder_id, ownership.holder_id, source_id, source_id, instance.provenance_id, before_quantity, after_quantity, "唯一库存物品已被消耗。", {"consumed": true, "definition_id": instance.definition_id})
	_add_upsert(plan, "container", source_id, source_copy.to_dict())
	plan.source_claims.append({"container_id": source_id, "item_kind": item_kind, "item_id": item_id, "quantity": quantity})
	return {"ok": true}

func _add_change(plan: Dictionary, transaction: GMDomainTransaction, operation: String, item_kind: String, item_id: String, quantity_delta: int, source_container: String, target_container: String, owner_before: String, owner_after: String, holder_before: String, holder_after: String, container_before: String, container_after: String, provenance_id: String, quantity_before: int, quantity_after: int, reason_zh: String, metadata: Dictionary = {}) -> void:
	var change_id := "gm.inventory.change.%s" % _slug(plan.fact_id + "." + str(plan.inventory_changes.size() + 1))
	var change := GMInventoryChange.new().configure(change_id, plan.fact_id, transaction.transaction_id, transaction.chain.chain_id, transaction.idempotency_key, operation, item_kind, item_id, quantity_delta, source_container, target_container, owner_before, owner_after, holder_before, holder_after, container_before, container_after, provenance_id, quantity_before, quantity_after, reason_zh, metadata)
	var validation := change.validate()
	if not validation.ok:
		plan["invalid_change"] = validation
		return
	plan.inventory_changes.append(change.to_dict())
	_add_upsert(plan, "change", change_id, change.to_dict())
	plan.changeset.append({"entity_id": item_id, "operation": "inventory.%s" % operation, "field": "container", "before": {"container_id": container_before, "quantity": quantity_before}, "after": {"container_id": container_after, "quantity": quantity_after}, "metadata": {"inventory_change_id": change_id, "operation": operation}})

func _add_upsert(plan: Dictionary, kind: String, record_id: String, value: Dictionary) -> void:
	var row := {"kind": kind, "id": record_id, "value": value.duplicate(true)}
	for index in plan.upserts.size():
		if str(plan.upserts[index].get("kind", "")) == kind and str(plan.upserts[index].get("id", "")) == record_id:
			plan.upserts[index] = row
			return
	plan.upserts.append(row)

func _add_delete(plan: Dictionary, kind: String, record_id: String) -> void:
	var key := "%s:%s" % [kind, record_id]
	if not plan.deletes.has(key): plan.deletes.append(key)

func _child_provenance(parent_id: String, source_fact_id: String, provenance_id: String, fact_id: String) -> GMProvenanceRecord:
	if feature_flags.detailed_provenance:
		return GMProvenanceRecord.new().configure(provenance_id, fact_id, "split", [parent_id], [source_fact_id, fact_id], {})
	return GMProvenanceRecord.simplified(provenance_id, fact_id, "split")

func _blocked(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	result.merge(details, true)
	return result

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in raw.length():
		var code := raw.unicode_at(index)
		result += raw.substr(index, 1) if ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45) else "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_") if not result.is_empty() else "inventory"
