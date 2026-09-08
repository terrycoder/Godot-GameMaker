class_name GMP19TransactionResolver
extends "res://gm_runtime/transactions/gm_domain_resolver.gd"

## P19 composite Resolver. It delegates participant planning to the existing
## InventoryResolver and the numeric adapter, while GMDomainTransaction and its
## Coordinator remain the only lifecycle and Fact authorities.

var inventory_store: GMInventoryStore
var numeric_store: GMNumericResourceStore
var inventory_resolver: Object
var numeric_resolver: GMNumericResourceResolver
var plans: Dictionary = {}
var isolated: bool = false
var isolation_report: Dictionary = {}

func _init(p_inventory_store: GMInventoryStore = null, p_numeric_store: GMNumericResourceStore = null, p_inventory_resolver: Object = null, p_numeric_resolver: GMNumericResourceResolver = null) -> void:
        resolver_id = "gm.resolver.p19"
        inventory_store = p_inventory_store if p_inventory_store != null else GMInventoryStore.new()
        numeric_store = p_numeric_store if p_numeric_store != null else GMNumericResourceStore.new()
        inventory_resolver = p_inventory_resolver if p_inventory_resolver != null else GMInventoryResolver.new(inventory_store)
        numeric_resolver = p_numeric_resolver if p_numeric_resolver != null else GMNumericResourceResolver.new(numeric_store)

func preflight_transaction(transaction: GMDomainTransaction) -> Dictionary:
        if isolated: return _blocked("p19.resolver_isolated", "P19 Resolver处于恢复失败隔离状态，拒绝正常事务。", isolation_report)
        if transaction == null or transaction.request == null: return _blocked("p19.request_missing", "P19 事务缺少请求。")
        var data: Dictionary = transaction.request.event_data.duplicate(true)
        var adapter_target_check := GMP19RequestAdapter.validate_public_target(data)
        if not adapter_target_check.ok: return adapter_target_check
        var operation := str(data.get("p19_operation", data.get("transaction_operation", data.get("operation", data.get("inventory_operation", data.get("numeric_operation", "")))))).strip_edges().to_lower()
        var use_confirmation := _validate_use_confirmation(data, operation)
        if not use_confirmation.ok: return use_confirmation
        var has_inventory := _has_inventory(data, operation)
        var has_numeric := _has_numeric(data, operation)
        if not has_inventory and not has_numeric: return _blocked("p19.participants_missing", "P19 事务至少需要一个物品或数值资源参与者。")
        var fact_id := str(data.get("planned_fact_event_id", ""))
        if fact_id.is_empty(): fact_id = "gm.fact.p19.%s" % _slug(transaction.idempotency_key)
        if not fact_id.begins_with("gm.fact."): return _blocked("p19.fact_id_invalid", "P19 事务事实身份必须使用 gm.fact.*。")
        var request_data := transaction.request.event_data
        var had_fact_id := request_data.has("planned_fact_event_id")
        var original_fact_id: Variant = request_data.get("planned_fact_event_id", null)
        if not had_fact_id: request_data["planned_fact_event_id"] = fact_id
        var inventory_result: Dictionary = {"ok": true}
        var numeric_result: Dictionary = {"ok": true}
        if has_inventory:
                var had_inventory_operation := request_data.has("inventory_operation")
                var original_inventory_operation: Variant = request_data.get("inventory_operation", null)
                if not had_inventory_operation: request_data["inventory_operation"] = _inventory_operation(operation)
                inventory_result = inventory_resolver.preflight_transaction(transaction) if inventory_resolver != null and inventory_resolver.has_method("preflight_transaction") else _blocked("p19.inventory_interface_missing", "P19 缺少既有 InventoryResolver 预检接口。")
                if had_inventory_operation: request_data["inventory_operation"] = original_inventory_operation
                else: request_data.erase("inventory_operation")
                if not inventory_result.ok:
                        if numeric_resolver != null: numeric_resolver.discard_transaction_plan(transaction.transaction_id)
                        if not had_fact_id: request_data.erase("planned_fact_event_id")
                        else: request_data["planned_fact_event_id"] = original_fact_id
                        return inventory_result
        if has_numeric:
                numeric_result = numeric_resolver.preflight_transaction(transaction) if numeric_resolver != null else _blocked("p19.numeric_interface_missing", "P19 缺少数值资源 Resolver。")
                if not numeric_result.ok:
                        if has_inventory and inventory_resolver.has_method("rollback_transaction"): inventory_resolver.rollback_transaction(transaction, "数值资源预检失败，清理库存计划。")
                        if not had_fact_id: request_data.erase("planned_fact_event_id")
                        else: request_data["planned_fact_event_id"] = original_fact_id
                        return numeric_result
        if not had_fact_id: request_data.erase("planned_fact_event_id")
        else: request_data["planned_fact_event_id"] = original_fact_id
        var plan := GMP19TransactionPlan.new().configure(transaction.transaction_id, transaction.idempotency_key, operation if not operation.is_empty() else ("transfer" if has_inventory else "resource_transfer"), fact_id)
        if has_inventory:
                var inventory_plan: Dictionary = inventory_resolver.planned_transaction_plan(transaction.transaction_id) if inventory_resolver.has_method("planned_transaction_plan") else {}
                if inventory_plan.is_empty(): return _blocked("p19.inventory_plan_missing", "既有库存Resolver未返回预检计划。")
                plan.add_participant("inventory", inventory_plan)
        if has_numeric:
                var numeric_plan := numeric_resolver.planned_transaction_plan(transaction.transaction_id)
                if numeric_plan.is_empty():
                        if has_inventory and inventory_resolver.has_method("rollback_transaction"): inventory_resolver.rollback_transaction(transaction, "数值资源计划缺失，清理库存计划。")
                        return _blocked("p19.numeric_plan_missing", "数值资源Resolver未返回预检计划。")
                plan.add_participant("numeric_resource", numeric_plan)
        plan.inputs = []
        plan.outputs = []
        plan.changeset = []
        if has_inventory:
                plan.inputs.append_array(plan.inventory_plan.get("inputs", []))
                plan.outputs.append_array(plan.inventory_plan.get("outputs", []))
                plan.changeset.append_array(plan.inventory_plan.get("changeset", []))
        if has_numeric:
                plan.inputs.append_array(plan.numeric_plan.get("inputs", []))
                plan.outputs.append_array(plan.numeric_plan.get("outputs", []))
                plan.changeset.append_array(plan.numeric_plan.get("changeset", []))
        plan.payload = {"event_id": fact_id, "operation": plan.operation, "p19_operation": plan.operation, "participants": plan.participants.duplicate(), "source_id": str(data.get("source_id", transaction.request.source)), "target_id": str(data.get("target_id", "")), "p19_plan": plan.summary()}
        for key in ["amount", "quantity", "item_kind", "item_id", "lot_id", "instance_id", "source_container_id", "target_container_id", "source_account_id", "target_account_id", "resource_id"]:
                if data.has(key): plan.payload[key] = data[key]
        for key in ["drop_generation_target", "reward_id", "reward_receipt_id", "equipment_slot", "ability_source_request", "effect_request", "use_confirmation", "semantic_generation_target"]:
                if data.has(key): plan.payload[key] = data[key].duplicate(true) if data[key] is Dictionary else data[key]
        if has_inventory:
                plan.payload["inventory_changes"] = plan.inventory_plan.get("inventory_changes", []).duplicate(true)
        if has_numeric:
                plan.payload["numeric_changes"] = plan.numeric_plan.get("numeric_changes", []).duplicate(true)
        var plan_check := plan.validate()
        if not plan_check.ok:
                if has_inventory and inventory_resolver.has_method("rollback_transaction"): inventory_resolver.rollback_transaction(transaction, "P19 计划校验失败，清理库存计划。")
                if has_numeric: numeric_resolver.discard_transaction_plan(transaction.transaction_id)
                return plan_check
        plans[transaction.transaction_id] = plan.to_dict()
        transaction.commit_payload = plan.payload.duplicate(true)
        return {"ok": true, "stage": "PREFLIGHT", "operation": plan.operation, "participants": plan.participants, "inputs": plan.inputs, "outputs": plan.outputs, "changeset": plan.changeset}

func reserve_transaction(transaction: GMDomainTransaction) -> Dictionary:
        var plan: Dictionary = plans.get(transaction.transaction_id, {})
        if plan.is_empty(): return _blocked("p19.plan_missing", "P19 事务没有预检计划。")
        var handles: Array = []
        if plan.participants.has("inventory"):
                var inventory_result: Dictionary = inventory_resolver.reserve_transaction(transaction)
                if not inventory_result.ok: return inventory_result
                handles.append_array(inventory_result.get("reservations", []))
        if plan.participants.has("numeric_resource"):
                var numeric_result := numeric_resolver.reserve_transaction(transaction)
                if not numeric_result.ok:
                        if plan.participants.has("inventory"): inventory_resolver.release_transaction_reservations(transaction)
                        return numeric_result
                handles.append_array(numeric_result.get("reservations", []))
        plan["reservation_handles"] = handles.duplicate(true)
        plans[transaction.transaction_id] = plan
        return {"ok": true, "stage": "RESERVE", "reservations": handles}

func commit_transaction(transaction: GMDomainTransaction) -> Dictionary:
        var plan: Dictionary = plans.get(transaction.transaction_id, {})
        if plan.is_empty(): return _blocked("p19.plan_missing", "P19 事务没有预检计划。")
        var committed_parts: Array[String] = []
        var participant_results: Dictionary = {}
        if plan.participants.has("inventory"):
                var inventory_result: Dictionary = inventory_resolver.commit_transaction(transaction)
                participant_results["inventory"] = inventory_result.duplicate(true)
                if not inventory_result.ok:
                        _restore_after_partial_commit(transaction)
                        return inventory_result
                committed_parts.append("inventory")
        if plan.participants.has("numeric_resource"):
                var numeric_result := numeric_resolver.commit_transaction(transaction)
                participant_results["numeric_resource"] = numeric_result.duplicate(true)
                if not numeric_result.ok:
                        _restore_after_partial_commit(transaction)
                        return _blocked(str(numeric_result.get("code", "p19.numeric_commit_failed")), str(numeric_result.get("reason_zh", "数值资源提交失败，两个参与者已恢复。")), {"participant_results": participant_results, "atomic_restore": true})
                committed_parts.append("numeric_resource")
        var payload: Dictionary = plan.payload.duplicate(true)
        var inputs: Array = plan.get("inputs", []).duplicate(true)
        var outputs: Array = plan.get("outputs", []).duplicate(true)
        var changeset: Array = plan.get("changeset", []).duplicate(true)
        var tags: Array = ["gm.p19", "gm.p19.%s" % str(plan.operation)]
        if plan.participants.has("inventory"): tags.append("gm.inventory")
        if plan.participants.has("numeric_resource"): tags.append("gm.numeric_resource")
        payload["committed_participants"] = committed_parts
        payload["reservation_handles"] = plan.get("reservation_handles", []).duplicate(true)
        payload["participant_results"] = {"inventory": {"change_count": plan.inventory_plan.get("changeset", []).size()} if plan.participants.has("inventory") else {}, "numeric_resource": {"change_count": plan.numeric_plan.get("changeset", []).size()} if plan.participants.has("numeric_resource") else {}}
        plan["committed"] = true
        plans[transaction.transaction_id] = plan
        return {"ok": true, "stage": "COMMIT", "payload": payload, "inputs": inputs, "outputs": outputs, "tags": tags, "visibility": {"public": false, "witnesses": []}, "changeset": changeset, "participants": committed_parts}

func rollback_transaction(transaction: GMDomainTransaction, reason_zh: String) -> Dictionary:
        var plan: Dictionary = plans.get(transaction.transaction_id, {})
        var results: Dictionary = {}
        var ok := true
        if plan.is_empty():
                if inventory_resolver != null: results["inventory"] = inventory_resolver.release_transaction_reservations(transaction)
                if numeric_resolver != null: results["numeric_resource"] = numeric_resolver.release_transaction_reservations(transaction)
                return {"ok": true, "stage": "ROLLBACK", "rolled_back": true, "plan_missing": true, "reason_zh": reason_zh, "participants": results}
        if plan.participants.has("inventory"):
                results["inventory"] = inventory_resolver.rollback_transaction(transaction, reason_zh)
                ok = ok and bool(results.inventory.get("ok", false))
        if plan.participants.has("numeric_resource"):
                results["numeric_resource"] = numeric_resolver.rollback_transaction(transaction, reason_zh)
                ok = ok and bool(results.numeric_resource.get("ok", false))
        if ok: plans.erase(transaction.transaction_id)
        return {"ok": ok, "stage": "ROLLBACK", "rolled_back": ok, "reason_zh": reason_zh, "participants": results}

func capture_transaction_state(_transaction: GMDomainTransaction) -> Dictionary:
        if isolated: return _blocked("p19.resolver_isolated", "P19 Resolver处于隔离状态，不能建立恢复点。", isolation_report)
        return {"ok": true, "contract": "gm.p19.recovery.v1", "snapshot": {"inventory": inventory_store.snapshot(), "numeric": numeric_store.snapshot(), "inventory_reservations": GMStableData.clone(inventory_store.reservations), "numeric_reservations": GMStableData.clone(numeric_store.reservations)}}

func restore_transaction_state(transaction: GMDomainTransaction, snapshot: Variant) -> Dictionary:
        var shape := _validate_recovery_snapshot(transaction, snapshot)
        if not shape.ok: return shape
        var current := capture_transaction_state(transaction)
        var inventory_restored := inventory_store.restore_snapshot(snapshot.inventory)
        if not inventory_restored.ok: return _blocked("p19.recovery_restore_failed", "库存参与者无法从P19恢复点还原。", {"participant": "inventory", "restore": inventory_restored})
        var numeric_restored := numeric_store.restore_snapshot(snapshot.numeric)
        if not numeric_restored.ok:
                inventory_store.restore_snapshot(current.snapshot.inventory)
                inventory_store.reservations = GMStableData.clone(current.snapshot.inventory_reservations)
                return _blocked("p19.recovery_restore_failed", "数值资源参与者无法从P19恢复点还原，库存已恢复。", {"participant": "numeric_resource", "restore": numeric_restored})
        inventory_store.reservations = GMStableData.clone(snapshot.inventory_reservations)
        numeric_store.reservations = GMStableData.clone(snapshot.numeric_reservations)
        plans.erase(transaction.transaction_id)
        return {"ok": true, "stage": "RECOVERY", "restored": true, "contract": "gm.p19.recovery.v1"}

func release_transaction_reservations(transaction: GMDomainTransaction) -> Dictionary:
        if transaction == null: return _blocked("p19.transaction_missing", "释放P19预留需要事务身份。")
        var results: Dictionary = {}
        var ok := true
        if inventory_resolver != null:
                results["inventory"] = inventory_resolver.release_transaction_reservations(transaction)
                ok = ok and bool(results.inventory.get("ok", false))
        if numeric_resolver != null:
                results["numeric_resource"] = numeric_resolver.release_transaction_reservations(transaction)
                ok = ok and bool(results.numeric_resource.get("ok", false))
        return {"ok": ok, "released": ok, "participants": results, "transaction_id": transaction.transaction_id}

func isolate_transaction_state(transaction: GMDomainTransaction, failure: Dictionary) -> Dictionary:
        isolated = true
        isolation_report = {"transaction_id": transaction.transaction_id if transaction != null else "", "failure": failure.duplicate(true)}
        if inventory_resolver != null and inventory_resolver.has_method("isolate_transaction_state"): inventory_resolver.isolate_transaction_state(transaction, failure)
        if numeric_resolver != null: numeric_resolver.isolate_transaction_state(transaction, failure)
        return {"ok": true, "isolated": true, "resolver_id": resolver_id, "transaction_id": isolation_report.transaction_id}

func finalize_transaction(transaction: GMDomainTransaction) -> Dictionary:
        var results: Dictionary = {}
        var plan: Dictionary = plans.get(transaction.transaction_id, {})
        var participants: Array = plan.get("participants", []) if plan is Dictionary else []
        if participants.has("inventory"): results["inventory"] = inventory_resolver.finalize_transaction(transaction)
        if participants.has("numeric_resource"): results["numeric_resource"] = numeric_resolver.finalize_transaction(transaction)
        plans.erase(transaction.transaction_id)
        return {"ok": true, "stage": "FINALIZE", "finalized": true, "participants": results}

func version_for(key: String) -> int:
        if key == inventory_store.store_id or key == "inventory" or key == "gm.store.inventory": return inventory_store.version
        if key == numeric_store.store_id or key == "numeric" or key == "gm.store.numeric_resource": return numeric_store.version
        var account := numeric_store.get_account(key)
        if account != null: return account.account_version
        return 0

func build_candidate(request: GMAbilityActivationRequest, chain: GMCausalChain) -> GMCandidateResult:
        return GMCandidateResult.from_request(request, chain, 1.0, ["P19 事务同时支持库存与数值资源参与者。"])

func planned_transaction_plan(transaction_id: String) -> Dictionary:
        var value: Variant = plans.get(transaction_id, {})
        return value.duplicate(true) if value is Dictionary else {}

func _restore_after_partial_commit(transaction: GMDomainTransaction) -> Dictionary:
        if transaction != null and transaction.recovery_prepared and transaction.recovery_snapshot is Dictionary:
                return restore_transaction_state(transaction, transaction.recovery_snapshot)
        return {"ok": false, "code": "p19.recovery_snapshot_missing", "reason_zh": "P19部分提交缺少恢复点。"}

func _validate_recovery_snapshot(transaction: GMDomainTransaction, value: Variant) -> Dictionary:
        if not value is Dictionary or value.size() != 4:
                return _blocked("p19.recovery_snapshot_invalid", "P19恢复点字段集合无效。")
        for key in ["inventory", "numeric", "inventory_reservations", "numeric_reservations"]:
                if not value.has(key): return _blocked("p19.recovery_snapshot_invalid", "P19恢复点缺少参与者字段。", {"field": key})
        if not value.inventory is Dictionary or not value.numeric is Dictionary or not value.inventory_reservations is Dictionary or not value.numeric_reservations is Dictionary:
                return _blocked("p19.recovery_snapshot_invalid", "P19恢复点参与者结构无效。")
        var stable := GMStableData.validate_persistence({"inventory_reservations": value.inventory_reservations, "numeric_reservations": value.numeric_reservations})
        if not stable.ok: return _blocked("p19.recovery_snapshot_invalid", "P19恢复点预留包含不可保存值。", stable)
        var inventory_reservation_check := _validate_recovery_reservation_group(value.inventory_reservations, value.inventory, "gm.inventory.reservation.v1", "inventory", "inventory")
        if not inventory_reservation_check.ok: return inventory_reservation_check
        var numeric_reservation_check := _validate_recovery_reservation_group(value.numeric_reservations, value.numeric, "gm.numeric.reservation.v1", "numeric_resource", "numeric")
        if not numeric_reservation_check.ok: return numeric_reservation_check
        return {"ok": true}

func _validate_use_confirmation(data: Dictionary, operation: String) -> Dictionary:
        if operation != "use": return {"ok": true}
        var confirmation: Variant = data.get("use_confirmation", null)
        if not confirmation is Dictionary or typeof(confirmation.get("confirmed", null)) != TYPE_BOOL:
                return _blocked("p19.use_confirmation_required", "使用事务必须先获得类型化领域效果确认，未确认时不进入预留或提交。")
        if not bool(confirmation.get("confirmed", false)):
                return _blocked("p19.use_effect_not_confirmed", "领域效果未确认或已失败，使用事务不会消耗物品或写入Fact。", {"confirmation": confirmation.duplicate(true)})
        for key in ["ok", "success"]:
                if confirmation.has(key) and typeof(confirmation[key]) == TYPE_BOOL and not bool(confirmation[key]):
                        return _blocked("p19.use_effect_failed", "领域效果确认明确失败，使用事务不会消耗物品或写入Fact。", {"confirmation": confirmation.duplicate(true)})
        var status := str(confirmation.get("status", "")).strip_edges().to_lower()
        if ["failed", "failure", "rejected", "error"].has(status):
                return _blocked("p19.use_effect_failed", "领域效果确认状态为失败，使用事务不会消耗物品或写入Fact。", {"confirmation": confirmation.duplicate(true)})
        return {"ok": true}

func _validate_recovery_reservation_group(group: Dictionary, store_snapshot: Dictionary, expected_schema: String, expected_participant: String, reservation_kind: String) -> Dictionary:
        var fields: Array[String] = ["schema", "reservation_id", "participant", "transaction_id", "store_version"]
        if reservation_kind == "inventory": fields.append_array(["source_claims", "target_claims"])
        else: fields.append_array(["expected_version", "input_claims", "output_claims"])
        var snapshot_version: Variant = store_snapshot.get("version", null)
        if not _is_recovery_integer(snapshot_version) or int(snapshot_version) < 0:
                return _blocked("p19.recovery_reservation_invalid", "P19恢复点参与者Store版本字段无效。", {"participant": expected_participant})
        for raw_key in group:
                if typeof(raw_key) != TYPE_STRING or str(raw_key).strip_edges().is_empty():
                        return _blocked("p19.recovery_reservation_invalid", "P19预留键必须是非空稳定事务身份。", {"participant": expected_participant})
                var key := str(raw_key)
                var reservation: Variant = group[raw_key]
                if not reservation is Dictionary or reservation.size() != fields.size():
                        return _blocked("p19.recovery_reservation_invalid", "P19预留Schema字段集合无效。", {"participant": expected_participant, "transaction_id": key})
                for field in fields:
                        if not reservation.has(field):
                                return _blocked("p19.recovery_reservation_invalid", "P19预留缺少Schema字段。", {"participant": expected_participant, "transaction_id": key, "field": field})
                if str(reservation.get("schema", "")) != expected_schema or str(reservation.get("participant", "")) != expected_participant or str(reservation.get("transaction_id", "")) != key:
                        return _blocked("p19.recovery_reservation_invalid", "P19预留Schema、参与者或事务身份不一致。", {"participant": expected_participant, "transaction_id": key})
                var reservation_namespace := "inventory" if reservation_kind == "inventory" else "numeric"
                var expected_reservation_id := "gm.reservation.%s.%s" % [reservation_namespace, ("%s|%s" % [key, reservation_namespace]).sha256_text()]
                if str(reservation.get("reservation_id", "")) != expected_reservation_id:
                        return _blocked("p19.recovery_reservation_invalid", "P19预留reservation_id不符合稳定事务身份规则。", {"participant": expected_participant, "transaction_id": key})
                if not _is_recovery_integer(reservation.get("store_version", null)) or int(reservation.get("store_version")) != int(snapshot_version):
                        return _blocked("p19.recovery_reservation_invalid", "P19预留store_version与参与者恢复点版本不一致。", {"participant": expected_participant, "transaction_id": key})
                if reservation_kind == "inventory":
                        var source_check := _validate_inventory_source_claims(reservation.get("source_claims", null), key)
                        if not source_check.ok: return source_check
                        var target_check := _validate_inventory_target_claims(reservation.get("target_claims", null), key)
                        if not target_check.ok: return target_check
                else:
                        if not _is_recovery_integer(reservation.get("expected_version", null)) or int(reservation.get("expected_version")) < -1:
                                return _blocked("p19.recovery_reservation_invalid", "P19数值预留expected_version类型无效。", {"transaction_id": key})
                        var input_check := _validate_numeric_claims(reservation.get("input_claims", null), "input", key)
                        if not input_check.ok: return input_check
                        var output_check := _validate_numeric_claims(reservation.get("output_claims", null), "output", key)
                        if not output_check.ok: return output_check
        if reservation_kind == "inventory":
                var inventory_semantic_check := _validate_inventory_reservation_semantics(group, store_snapshot)
                if not inventory_semantic_check.ok: return inventory_semantic_check
        else:
                var numeric_semantic_check := _validate_numeric_reservation_semantics(group, store_snapshot)
                if not numeric_semantic_check.ok: return numeric_semantic_check
        return {"ok": true}

func _validate_inventory_source_claims(value: Variant, transaction_id: String) -> Dictionary:
        if not value is Array: return _blocked("p19.recovery_reservation_invalid", "P19库存源预留claims必须是数组。", {"transaction_id": transaction_id, "field": "source_claims"})
        for claim in value:
                if not claim is Dictionary or claim.size() != 4:
                        return _blocked("p19.recovery_reservation_invalid", "P19库存源预留claim字段集合无效。", {"transaction_id": transaction_id})
                for field in ["container_id", "item_kind", "item_id", "quantity"]:
                        if not claim.has(field): return _blocked("p19.recovery_reservation_invalid", "P19库存源预留claim缺少字段。", {"transaction_id": transaction_id, "field": field})
                for field in ["container_id", "item_kind", "item_id"]:
                        if typeof(claim.get(field)) != TYPE_STRING or str(claim.get(field)).strip_edges().is_empty(): return _blocked("p19.recovery_reservation_invalid", "P19库存源预留claim身份无效。", {"transaction_id": transaction_id, "field": field})
                if not _is_recovery_integer(claim.get("quantity", null)) or int(claim.get("quantity")) <= 0: return _blocked("p19.recovery_reservation_invalid", "P19库存源预留数量必须是正整数。", {"transaction_id": transaction_id})
        return {"ok": true}

func _validate_inventory_target_claims(value: Variant, transaction_id: String) -> Dictionary:
        if not value is Array: return _blocked("p19.recovery_reservation_invalid", "P19库存目标预留claims必须是数组。", {"transaction_id": transaction_id, "field": "target_claims"})
        for claim in value:
                if not claim is Dictionary or claim.size() != 2 or not claim.has("container_id") or not claim.has("slots"):
                        return _blocked("p19.recovery_reservation_invalid", "P19库存目标预留claim字段集合无效。", {"transaction_id": transaction_id})
                if typeof(claim.get("container_id")) != TYPE_STRING or str(claim.get("container_id")).strip_edges().is_empty() or not _is_recovery_integer(claim.get("slots", null)) or int(claim.get("slots")) < 0:
                        return _blocked("p19.recovery_reservation_invalid", "P19库存目标预留claim身份或槽位无效。", {"transaction_id": transaction_id})
        return {"ok": true}

func _validate_numeric_claims(value: Variant, side: String, transaction_id: String) -> Dictionary:
        if not value is Array: return _blocked("p19.recovery_reservation_invalid", "P19数值预留claims必须是数组。", {"transaction_id": transaction_id, "side": side})
        for claim in value:
                if not claim is Dictionary or claim.size() != 4:
                        return _blocked("p19.recovery_reservation_invalid", "P19数值预留claim字段集合无效。", {"transaction_id": transaction_id, "side": side})
                for field in ["account_id", "resource_id", "amount", "side"]:
                        if not claim.has(field): return _blocked("p19.recovery_reservation_invalid", "P19数值预留claim缺少字段。", {"transaction_id": transaction_id, "field": field})
                if typeof(claim.get("account_id")) != TYPE_STRING or not str(claim.get("account_id")).begins_with("gm.resource.account.") or typeof(claim.get("resource_id")) != TYPE_STRING or not str(claim.get("resource_id")).begins_with("gm.resource.") or str(claim.get("side")) != side:
                        return _blocked("p19.recovery_reservation_invalid", "P19数值预留claim身份或方向无效。", {"transaction_id": transaction_id, "side": side})
                if not _is_recovery_integer(claim.get("amount", null)) or int(claim.get("amount")) <= 0:
                        return _blocked("p19.recovery_reservation_invalid", "P19数值预留数量必须是正整数。", {"transaction_id": transaction_id, "side": side})
        return {"ok": true}

func _validate_inventory_reservation_semantics(group: Dictionary, store_snapshot: Dictionary) -> Dictionary:
        var source_totals: Dictionary = {}
        var source_capacities: Dictionary = {}
        var target_totals: Dictionary = {}
        var target_capacities: Dictionary = {}
        var item_capacities: Dictionary = {}
        for raw_transaction_id in group:
                var reservation: Dictionary = group[raw_transaction_id]
                for raw_claim in reservation.source_claims:
                        var claim: Dictionary = raw_claim
                        var container_id := str(claim.container_id)
                        var item_kind := str(claim.item_kind)
                        var item_id := str(claim.item_id)
                        var quantity := int(claim.quantity)
                        var container := _recovery_typed_record(store_snapshot, "container", container_id)
                        if container.is_empty():
                                return _blocked("p19.recovery_reservation_invalid", "P19库存reservation引用了不存在的Container。", {"transaction_id": raw_transaction_id, "container_id": container_id})
                        var item := _recovery_typed_record(store_snapshot, item_kind, item_id)
                        if item.is_empty():
                                return _blocked("p19.recovery_reservation_invalid", "P19库存reservation引用了不存在的Lot或Instance。", {"transaction_id": raw_transaction_id, "item_kind": item_kind, "item_id": item_id})
                        var ownership := _recovery_find_ownership(store_snapshot, item_kind, item_id)
                        if ownership.is_empty() or str(ownership.get("container_id", "")) != container_id:
                                return _blocked("p19.recovery_reservation_invalid", "P19库存reservation的Ownership与Container关系不一致。", {"transaction_id": raw_transaction_id, "item_kind": item_kind, "item_id": item_id, "container_id": container_id})
                        var entry := _recovery_container_entry(container, item_kind, item_id)
                        if entry.is_empty() or not _is_recovery_integer(entry.get("quantity", null)):
                                return _blocked("p19.recovery_reservation_invalid", "P19库存reservation引用的Container entry不存在或数量无效。", {"transaction_id": raw_transaction_id, "item_kind": item_kind, "item_id": item_id, "container_id": container_id})
                        var source_key := "%s|%s|%s" % [container_id, item_kind, item_id]
                        source_totals[source_key] = int(source_totals.get(source_key, 0)) + quantity
                        source_capacities[source_key] = int(entry.quantity)
                        if item_kind == "lot":
                                if not _is_recovery_integer(item.get("quantity", null)) or int(item.quantity) <= 0:
                                        return _blocked("p19.recovery_reservation_invalid", "P19库存reservation引用的Lot数量无效。", {"transaction_id": raw_transaction_id, "item_id": item_id})
                                item_capacities[source_key] = int(item.quantity)
                        else:
                                item_capacities[source_key] = 1
                for raw_claim in reservation.target_claims:
                        var claim: Dictionary = raw_claim
                        var container_id := str(claim.container_id)
                        var slots := int(claim.slots)
                        var container := _recovery_typed_record(store_snapshot, "container", container_id)
                        if container.is_empty() or not container.get("entries", null) is Array or not _is_recovery_integer(container.get("slot_limit", null)):
                                return _blocked("p19.recovery_reservation_invalid", "P19库存reservation引用的目标Container不存在或容量字段无效。", {"transaction_id": raw_transaction_id, "container_id": container_id})
                        var target_key := container_id
                        target_totals[target_key] = int(target_totals.get(target_key, 0)) + slots
                        target_capacities[target_key] = {"slot_limit": int(container.slot_limit), "slot_count": container.entries.size()}
        for source_key in source_totals:
                if int(source_totals[source_key]) > int(source_capacities[source_key]) or int(source_totals[source_key]) > int(item_capacities[source_key]):
                        return _blocked("p19.recovery_reservation_invalid", "P19库存reservation数量超过恢复点中的实际物品数量。", {"claim_key": source_key, "requested": source_totals[source_key], "container_available": source_capacities[source_key], "item_available": item_capacities[source_key]})
        for target_key in target_totals:
                var capacity: Dictionary = target_capacities[target_key]
                if int(capacity.slot_limit) >= 0 and int(capacity.slot_count) + int(target_totals[target_key]) > int(capacity.slot_limit):
                        return _blocked("p19.recovery_reservation_invalid", "P19库存reservation目标槽位超过恢复点容量。", {"container_id": target_key, "requested": target_totals[target_key], "slot_limit": capacity.slot_limit, "slot_count": capacity.slot_count})
        return {"ok": true}

func _validate_numeric_reservation_semantics(group: Dictionary, store_snapshot: Dictionary) -> Dictionary:
        var input_totals: Dictionary = {}
        var output_totals: Dictionary = {}
        var accounts: Dictionary = {}
        for raw_transaction_id in group:
                var reservation: Dictionary = group[raw_transaction_id]
                for raw_claim in reservation.input_claims:
                        var claim: Dictionary = raw_claim
                        var account_check := _validate_numeric_reservation_account(store_snapshot, claim, raw_transaction_id)
                        if not account_check.ok: return account_check
                        var account: Dictionary = account_check.account
                        var account_id := str(claim.account_id)
                        input_totals[account_id] = int(input_totals.get(account_id, 0)) + int(claim.amount)
                        accounts[account_id] = account
                for raw_claim in reservation.output_claims:
                        var claim: Dictionary = raw_claim
                        var account_check := _validate_numeric_reservation_account(store_snapshot, claim, raw_transaction_id)
                        if not account_check.ok: return account_check
                        var account: Dictionary = account_check.account
                        var account_id := str(claim.account_id)
                        output_totals[account_id] = int(output_totals.get(account_id, 0)) + int(claim.amount)
                        accounts[account_id] = account
        for account_id in input_totals:
                var account: Dictionary = accounts[account_id]
                if int(input_totals[account_id]) > int(account.balance):
                        return _blocked("p19.recovery_reservation_invalid", "P19数值reservation输入超过恢复点余额。", {"account_id": account_id, "requested": input_totals[account_id], "balance": account.balance})
        for account_id in output_totals:
                var account: Dictionary = accounts[account_id]
                var capacity := int(account.capacity)
                if capacity >= 0 and int(output_totals[account_id]) > capacity - int(account.balance):
                        return _blocked("p19.recovery_reservation_invalid", "P19数值reservation输出超过恢复点容量。", {"account_id": account_id, "requested": output_totals[account_id], "balance": account.balance, "capacity": capacity})
        return {"ok": true}

func _validate_numeric_reservation_account(store_snapshot: Dictionary, claim: Dictionary, transaction_id: String) -> Dictionary:
        var account_id := str(claim.account_id)
        var resource_id := str(claim.resource_id)
        var account := _recovery_typed_record(store_snapshot, "account", account_id)
        if account.is_empty():
                return _blocked("p19.recovery_reservation_invalid", "P19数值reservation引用了不存在的Account。", {"transaction_id": transaction_id, "account_id": account_id})
        if str(account.get("resource_id", "")) != resource_id:
                return _blocked("p19.recovery_reservation_invalid", "P19数值reservation的Account与Resource关系不一致。", {"transaction_id": transaction_id, "account_id": account_id, "expected": account.get("resource_id", ""), "actual": resource_id})
        var definition := _recovery_typed_record(store_snapshot, "definition", resource_id)
        if definition.is_empty():
                return _blocked("p19.recovery_reservation_invalid", "P19数值reservation引用的Resource Definition不存在。", {"transaction_id": transaction_id, "resource_id": resource_id})
        if not _is_recovery_integer(account.get("balance", null)) or not _is_recovery_integer(account.get("capacity", null)):
                return _blocked("p19.recovery_reservation_invalid", "P19数值reservation引用的Account余额或容量字段无效。", {"transaction_id": transaction_id, "account_id": account_id})
        var balance := int(account.balance)
        var capacity := int(account.capacity)
        if balance < 0 or capacity == 0 or capacity < -1 or capacity >= 0 and balance > capacity:
                return _blocked("p19.recovery_reservation_invalid", "P19数值reservation引用的Account余额或容量语义无效。", {"transaction_id": transaction_id, "account_id": account_id})
        return {"ok": true, "account": account}

func _recovery_typed_record(store_snapshot: Dictionary, kind: String, record_id: String) -> Dictionary:
        if not ["definition", "account", "lot", "instance", "container"].has(kind) or record_id.strip_edges().is_empty():
                return {}
        var records: Variant = store_snapshot.get("records", null)
        if not records is Dictionary:
                return {}
        var wrapped: Variant = records.get("%s:%s" % [kind, record_id], null)
        if not wrapped is Dictionary or str(wrapped.get("record_kind", "")) != kind or not wrapped.get("record", null) is Dictionary:
                return {}
        var record: Dictionary = wrapped.record
        var identity_field: String = str({"definition": "resource_id", "account": "account_id", "lot": "lot_id", "instance": "instance_id", "container": "container_id"}.get(kind, ""))
        if str(record.get(identity_field, "")) != record_id:
                return {}
        return GMStableData.clone(record)

func _recovery_find_ownership(store_snapshot: Dictionary, item_kind: String, item_id: String) -> Dictionary:
        var records: Variant = store_snapshot.get("records", null)
        if not records is Dictionary:
                return {}
        for raw_key in records:
                var key := str(raw_key)
                if not key.begins_with("ownership:"):
                        continue
                var wrapped: Variant = records[raw_key]
                if not wrapped is Dictionary or str(wrapped.get("record_kind", "")) != "ownership" or not wrapped.get("record", null) is Dictionary:
                        continue
                var record: Dictionary = wrapped.record
                if str(record.get("item_kind", "")) == item_kind and str(record.get("item_id", "")) == item_id:
                        return GMStableData.clone(record)
        return {}

func _recovery_container_entry(container: Dictionary, item_kind: String, item_id: String) -> Dictionary:
        var entries: Variant = container.get("entries", null)
        if not entries is Array:
                return {}
        for raw_entry in entries:
                if not raw_entry is Dictionary:
                        return {}
                if str(raw_entry.get("item_kind", "")) == item_kind and str(raw_entry.get("item_id", "")) == item_id:
                        return raw_entry.duplicate(true)
        return {}

func _is_recovery_integer(value: Variant) -> bool:
        if typeof(value) == TYPE_INT: return abs(value) <= GMStableData.JSON_SAFE_INTEGER_MAX
        return typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value) and abs(value) <= float(GMStableData.JSON_SAFE_INTEGER_MAX)

func _has_inventory(data: Dictionary, operation: String) -> bool:
                for key in ["inventory_operation", "item_inputs", "item_outputs", "item_id", "lot_id", "instance_id", "source_container_id", "target_container_id"]:
                                if not data.has(key): continue
                                var value: Variant = data[key]
                                if value is String and str(value).strip_edges().is_empty(): continue
                                if value is Array and value.is_empty(): continue
                                return true
                return operation in ["produce", "gather", "pickup", "trade", "store", "drop", "transfer", "split", "merge", "upgrade_instance", "downgrade_instance", "consume", "use", "equip", "unequip"]

func _has_numeric(data: Dictionary, operation: String) -> bool:
                for key in ["resource_inputs", "numeric_inputs", "resource_outputs", "numeric_outputs", "resource_costs", "resource_rewards", "resource_transfers", "source_account_id", "target_account_id"]:
                                if not data.has(key): continue
                                var value: Variant = data[key]
                                if value is String and str(value).strip_edges().is_empty(): continue
                                if value is Array and value.is_empty(): continue
                                return true
                return operation in ["resource_transfer", "numeric_transfer", "resource_cost", "resource_reward", "grant", "convert"]

func _inventory_operation(operation: String) -> String:
        if operation in ["use", "consume"]: return "consume"
        if operation in ["equip", "unequip"]: return "transfer"
        if operation == "resource_transfer" or operation == "numeric_transfer": return "transfer"
        return operation if not operation.is_empty() else "transfer"

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
        return result.strip_edges().trim_prefix("_").trim_suffix("_") if not result.is_empty() else "p19"
