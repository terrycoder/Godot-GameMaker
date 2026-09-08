class_name GMTaskService
extends GMDomainResolver

const SERVICE_ID := "gm.task.service"
const STORE_ID := "gm.store.task_domain"
const STORE_SCHEMA := "gm.task.domain.v3"
const SNAPSHOT_SCHEMA := "gm.task.snapshot.v3"
const SIGNAL_RECEIPT_SCHEMA := "gm.task.signal_receipt.v3"
const COMMAND_ABILITY_ID := "gm.ability.task.command"
const EXECUTION_REQUEST_SCHEMA := "gm.task.execution_request.v1"
const JSON_SAFE_BOUND := 9007199254740992.0
const TERMINAL_STATES := ["completed", "failed", "cancelled"]
const TASK_STATES := ["draft","available","assigned","in_progress","blocked","completed","failed","cancelled"]
const ASSIGNMENT_STATES := ["active","revoked","rejected"]
const RESERVATION_STATES := ["active","released","consumed","expired"]
const SOURCE_TYPES := ["player", "ai", "organization", "world_event", "script", "duty_provider"]
const CONTEXT_MODES := ["local", "summary", "scene"]

var store := GMStore.new(STORE_ID, STORE_SCHEMA)
var fact_store := GMFactEventStore.new()
var change_store: GMChangeRecordStore
var coordinator := GMDomainTransactionCoordinator.new()
var isolated: bool = false
var isolation_report: Dictionary = {}
var _verified_signal_hashes: Dictionary = {}

func _init() -> void:
	super._init(SERVICE_ID)
	change_store = fact_store.change_store

func submit_operation(host: GMAbilitySystemHost, operation: String, payload: Dictionary, source_type: String, source_id: String, idempotency_key: String) -> Variant:
	if isolated: return _failure("task.service_isolated", "Task服务已隔离，禁止继续写入。", "请恢复或重建服务后重试。")
	if host == null or not is_instance_valid(host): return _failure("task.host_missing", "Task命令缺少统一AbilityHost。", "请从已装配的AbilityHost提交。")
	if source_type not in SOURCE_TYPES: return _failure("task.source_type_invalid", "Task来源类型无效。", "请使用玩家、AI、组织、世界事件、脚本或职责Provider。")
	if not _stable_id(source_id): return _failure("task.source_id_invalid", "Task来源稳定ID无效。", "请填写小写英文稳定ID。")
	if idempotency_key.is_empty(): return _failure("task.idempotency_missing", "Task写命令必须提供幂等键。", "请为本次业务操作提供稳定幂等键。")
	var target_id := _command_target_id(payload)
	var event_data := {"operation":operation,"payload":payload.duplicate(true),"source_type":source_type,"source_id":source_id,"target_id":target_id}
	var request := GMAbilityActivationRequest.new(host, COMMAND_ABILITY_ID, "", null, event_data, source_type, {}, idempotency_key)
	var instance_id := request.derive_instance_id()
	request.event_data["ability_instance_id"] = instance_id
	var chain := request.causal_chain
	var bound := chain.bind_ability_instance_identity(instance_id)
	if not bound.ok: return bound
	var linked := chain.add_ref(GMCausalRef.ability_instance(instance_id, COMMAND_ABILITY_ID), [request.request_id])
	if not linked.ok: return linked
	return coordinator.resolve(request, self, fact_store, change_store, {"resolver_id":SERVICE_ID,"fact_type":"gm.fact.task.%s" % operation,"source_system":SERVICE_ID,"ability_instance_id":instance_id}, chain)

func build_execution_request(host: GMAbilitySystemHost, task_id: String, assignment_id: String, ability_id: String, event_data: Dictionary, idempotency_key: String) -> Dictionary:
	var domain := _domain()
	var task: Dictionary = domain.tasks.get(task_id, {}) if domain.get("tasks", {}) is Dictionary else {}
	if task.is_empty(): return _failure("task.missing", "Task不存在。", "请刷新Task列表后重试。")
	var assignment: Dictionary = domain.assignments.get(assignment_id, {}) if domain.get("assignments", {}) is Dictionary else {}
	if assignment.is_empty() or str(assignment.get("task_id", "")) != task_id or str(task.get("assignment_id", "")) != assignment_id: return _failure("task.assignment_mismatch", "Task与Assignment不一致。", "请使用当前有效委派。")
	if str(task.get("state", "")) not in ["assigned", "in_progress", "blocked"]: return _failure("task.execution_state_invalid", "当前Task状态不能提交Ability请求。", "请先完成分配并进入可执行状态。")
	if ability_id.is_empty() or not ability_id.begins_with("gm.ability."): return _failure("task.ability_id_invalid", "执行请求缺少稳定Ability ID。", "请选择已注册的GM Ability。")
	var payload := event_data.duplicate(true)
	payload["task_execution_context"] = {"schema":EXECUTION_REQUEST_SCHEMA,"task_id":task_id,"assignment_id":assignment_id,"mode":str(task.get("execution_context", {}).get("mode", "local")),"stable_context":task.get("execution_context", {}).get("stable_context", {}).duplicate(true)}
	var request := GMAbilityActivationRequest.new(host, ability_id, "", null, payload, str(task.get("source", {}).get("type", "script")), {}, idempotency_key)
	return {"ok":true,"request":request,"request_dict":request.to_dict(),"task_id":task_id,"assignment_id":assignment_id,"direct_world_write":false}

func consume_committed_signal(signal_identity: Dictionary, idempotency_key: String, host: GMAbilitySystemHost, source_id: String = "gm.task.objective_adapter", authority: Variant = null) -> Variant:
	var resolved := _resolve_committed_signal(signal_identity,authority)
	if not resolved.ok: return resolved
	var signal_value: Dictionary = resolved.signal
	var preview:=_preview_signal_application(_domain(),signal_value)
	if not preview.ok:return preview
	if int(preview.pending_count)==0:
		return {"ok":true,"code":"task.signal_already_received" if int(preview.duplicate_count)>0 else "task.signal_no_matching_objective","idempotent":int(preview.duplicate_count)>0,"no_op":true,"signal_kind":signal_value.kind,"signal_id":signal_value.signal_id,"pending_count":0,"duplicate_count":preview.duplicate_count,"matched_count":preview.matched_count}
	var verification_key := _signal_verification_key(signal_value)
	_verified_signal_hashes[verification_key] = _signal_hash(signal_value)
	var result: Variant = submit_operation(host,"apply_signal",signal_value,"script",source_id,idempotency_key)
	_verified_signal_hashes.erase(verification_key)
	return result

func snapshot() -> Dictionary:
	return {"snapshot_schema":SNAPSHOT_SCHEMA,"authority_store":fact_store.snapshot(),"store":store.snapshot()}

func snapshot_json() -> String:
	return JSON.stringify(GMStableData.persistence_canonical(snapshot()), "", true, true)

func restore_snapshot(value: Dictionary) -> Dictionary:
	var checked := _validated_snapshot(value)
	if not checked.ok: return checked
	var authority_before:=fact_store.snapshot()
	var authority_restored:=fact_store.restore_snapshot(checked.authority_snapshot)
	if not authority_restored.ok:return authority_restored
	change_store=fact_store.change_store
	var task_restored:=store.restore_snapshot(checked.store_snapshot)
	if not task_restored.ok:
		fact_store.restore_snapshot(authority_before);change_store=fact_store.change_store
		return task_restored
	return {"ok":true,"code":"task.snapshot_restored","authority":authority_restored,"task_store":task_restored}

func restore_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary: return _failure("task.snapshot_json_invalid", "Task快照不是有效JSON对象。", "请使用完整导出的Task快照。")
	var normalized := _normalize_json_snapshot(parsed)
	if not normalized.ok: return normalized
	return restore_snapshot(normalized.snapshot)

func read_task(task_id: String) -> Dictionary:
	return _domain().get("tasks", {}).get(task_id, {}).duplicate(true)

func read_assignment(assignment_id: String) -> Dictionary:
	return _domain().get("assignments", {}).get(assignment_id, {}).duplicate(true)

func read_reservation(reservation_id: String) -> Dictionary:
	return _domain().get("reservations", {}).get(reservation_id, {}).duplicate(true)

func domain_snapshot() -> Dictionary:
	return _domain().duplicate(true)

func capture_transaction_state(_transaction: GMDomainTransaction) -> Dictionary:
	return {"ok":true,"contract":SNAPSHOT_SCHEMA,"snapshot":store.snapshot()}

func restore_transaction_state(_transaction: GMDomainTransaction, value: Variant) -> Dictionary:
	if not value is Dictionary: return _failure("task.recovery_snapshot_invalid", "Task事务恢复点无效。", "请隔离损坏事务。")
	return store.restore_snapshot(value)

func release_transaction_reservations(_transaction: GMDomainTransaction) -> Dictionary:
	return {"ok":true,"released":true,"reservation_existed":false}

func isolate_transaction_state(transaction: GMDomainTransaction, failure: Dictionary) -> Dictionary:
	if transaction != null and transaction.recovery_snapshot is Dictionary: store.restore_snapshot(transaction.recovery_snapshot)
	isolated = true
	isolation_report = {"transaction_id":transaction.transaction_id if transaction != null else "","failure":failure.duplicate(true)}
	return {"ok":true,"isolated":true,"normal_reads_disabled":true}

func preflight_transaction(transaction: GMDomainTransaction) -> Dictionary:
	if transaction == null or transaction.request == null: return _failure("task.request_missing", "Task事务缺少Ability请求。", "请从统一Task入口重试。")
	var data: Dictionary = transaction.request.event_data
	for field in ["operation","payload","source_type","source_id","ability_instance_id"]:
		if not data.has(field): return _failure("task.command_truncated", "Task命令缺少字段“%s”。" % field, "请重新构造完整命令。")
	if typeof(data.operation) != TYPE_STRING or not data.payload is Dictionary or typeof(data.source_type) != TYPE_STRING or typeof(data.source_id) != TYPE_STRING: return _failure("task.command_type_invalid", "Task命令字段类型错误。", "请使用稳定字符串和Dictionary载荷。")
	if data.source_type not in SOURCE_TYPES or not _stable_id(data.source_id): return _failure("task.source_invalid", "Task来源身份无效。", "请修正来源类型和稳定ID。")
	var before := _domain()
	var applied := _apply_operation(before.duplicate(true), str(data.operation), data.payload.duplicate(true), str(data.source_type), str(data.source_id), transaction.idempotency_key)
	if not applied.ok: return applied
	var validation := _validate_domain(applied.after)
	if not validation.ok: return validation
	var targets: Array = applied.get("targets",[]).duplicate(true)
	if targets.is_empty(): targets.append(str(data.target_id))
	elif str(data.target_id) not in targets: targets.append(str(data.target_id))
	transaction.commit_payload = {"operation":str(data.operation),"source_id":str(data.source_id),"source_type":str(data.source_type),"target_id":str(data.target_id),"before":before,"after":applied.after,"result":applied.get("result",{}).duplicate(true),"targets":targets,"duplicate":bool(applied.get("duplicate",false)),"expected_store_version":store.version}
	return {"ok":true,"stage":"PREFLIGHT","operation":str(data.operation),"duplicate":bool(applied.get("duplicate",false))}

func reserve_transaction(_transaction: GMDomainTransaction) -> Dictionary:
	return {"ok":true,"stage":"RESERVE","reservations":[]}

func commit_transaction(transaction: GMDomainTransaction) -> Dictionary:
	var payload: Dictionary = transaction.commit_payload
	var before: Dictionary = payload.before
	var after: Dictionary = payload.after
	var changed := before != after
	if changed:
		var stored := store.put("domain", after, int(payload.expected_store_version))
		if not stored.ok: return stored
	var targets: Array = payload.targets
	return {"ok":true,"stage":"COMMIT","inputs":targets.duplicate(),"outputs":targets.duplicate(),"tags":["gm.task.domain","gm.task.operation.%s" % str(payload.operation)],"visibility":{"public":false,"witnesses":targets.duplicate()},"payload":{"operation":payload.operation,"source_id":payload.source_id,"source_type":payload.source_type,"target_id":payload.target_id,"targets":targets.duplicate(),"result":payload.result,"duplicate":payload.duplicate,"store_version":store.version},"changeset":[{"entity_id":str(targets[0]) if not targets.is_empty() else STORE_ID,"operation":"task.%s" % payload.operation,"field":"task_domain","before":before,"after":after,"metadata":{"store_id":STORE_ID,"duplicate":payload.duplicate}}],"cues":[{"cue_id":"gm.cue.task.%s" % payload.operation,"parameters":{"result":payload.result,"duplicate":payload.duplicate}}]}

func rollback_transaction(transaction: GMDomainTransaction, _reason_zh: String) -> Dictionary:
	if transaction != null and transaction.recovery_snapshot is Dictionary:
		var restored := store.restore_snapshot(transaction.recovery_snapshot)
		if not restored.ok: return restored
	return {"ok":true,"stage":"ROLLBACK","rolled_back":true}

func finalize_transaction(_transaction: GMDomainTransaction) -> Dictionary:
	return {"ok":true,"stage":"FINALIZE","finalized":true}

func version_for(key: String) -> int:
	return store.version if key in [STORE_ID, "domain"] else 0

func _apply_operation(domain: Dictionary, operation: String, payload: Dictionary, source_type: String, source_id: String, receipt_key: String) -> Dictionary:
	match operation:
		"register_definition": return _register_definition(domain, payload)
		"register_group": return _register_group(domain, payload)
		"create_draft": return _publish_task(domain, payload, source_type, source_id, "draft")
		"publish_task": return _publish_task(domain, payload, source_type, source_id)
		"assign": return _assign(domain, payload, false)
		"reassign": return _assign(domain, payload, true)
		"revoke_assignment": return _revoke_assignment(domain, payload)
		"reject_assignment": return _reject_assignment(domain, payload)
		"transition": return _transition(domain, payload, receipt_key)
		"apply_signal": return _apply_signal(domain, payload)
		"register_duty_provider": return _register_provider(domain, payload)
		"duty_event": return _duty_event(domain, payload, source_id)
		"acquire_reservation": return _acquire_reservation(domain, payload)
		"renew_reservation": return _renew_reservation(domain, payload)
		"release_reservation": return _release_reservation(domain, payload)
		"consume_reservation": return _consume_reservation(domain, payload)
		"advance_logical_clock": return _advance_clock(domain, payload)
		_: return _failure("task.operation_unknown", "Task操作类型不受支持：%s" % operation, "请使用P16稳定操作名。")

func _register_definition(domain: Dictionary, payload: Dictionary) -> Dictionary:
	var parsed := GMTaskDefinition.new()
	var applied := parsed.apply_dict(payload)
	if not applied.ok: return applied
	var rules_checked := _validate_definition_reservation_authority(domain,parsed.to_dict())
	if not rules_checked.ok: return rules_checked
	if domain.definitions.has(parsed.definition_id):
		if domain.definitions[parsed.definition_id] == parsed.to_dict(): return _applied(domain,{"definition_id":parsed.definition_id,"unchanged":true},[parsed.definition_id],true)
		return _failure("task.definition_conflict", "同一Task定义ID已存在不同内容。", "请使用新ID或加载既有定义。")
	domain.definitions[parsed.definition_id] = parsed.to_dict()
	return _applied(domain,{"definition_id":parsed.definition_id},[parsed.definition_id])

func _register_group(domain: Dictionary, payload: Dictionary) -> Dictionary:
	var required := _require(payload,["group_id","member_refs"]); if not required.ok:return required
	var group_id := str(payload.group_id)
	if not _stable_id(group_id) or not payload.member_refs is Array:return _failure("task.group_invalid","Task Group定义无效。","请填写稳定Group ID与成员稳定引用。")
	for member in payload.member_refs:
		if not _typed_ref(member):return _failure("task.group_member_invalid","Task Group成员必须是稳定类型+ID引用。","请移除Node、RID或NodePath。")
	var row := {"schema":"gm.task.group.v1","group_id":group_id,"member_refs":payload.member_refs.duplicate(true)}
	if domain.groups.has(group_id):
		if domain.groups[group_id]==row:return _applied(domain,{"group_id":group_id,"unchanged":true},[group_id],true)
		return _failure("task.group_conflict","Task Group ID已存在不同定义。","请读取既有Group或使用新ID。")
	domain.groups[group_id]=row
	return _applied(domain,{"group_id":group_id},[group_id])

func _publish_task(domain: Dictionary, payload: Dictionary, source_type: String, source_id: String, initial_state: String = "available") -> Dictionary:
	var required := _require(payload,["task_id","definition_id","parent_task_id","group_id","execution_context"])
	if not required.ok: return required
	var task_id := str(payload.task_id); var definition_id := str(payload.definition_id); var parent_id := str(payload.parent_task_id); var group_id := str(payload.group_id)
	if not _stable_id(task_id) or not _stable_id(definition_id) or (not parent_id.is_empty() and not _stable_id(parent_id)) or (not group_id.is_empty() and not _stable_id(group_id)): return _failure("task.identity_invalid", "Task、定义、父Task或Group稳定ID无效。", "请使用小写英文稳定ID。")
	if not domain.definitions.has(definition_id): return _failure("task.definition_missing", "Task引用的定义不存在。", "请先保存并注册Task定义。")
	if not group_id.is_empty() and not domain.groups.has(group_id): return _failure("task.group_missing", "Task引用的Group不存在。", "请先注册Task Group。")
	if domain.tasks.has(task_id): return _failure("task.instance_duplicate", "Task实例ID已存在。", "请读取既有Task或使用新ID。")
	if not parent_id.is_empty() and not domain.tasks.has(parent_id): return _failure("task.parent_missing", "父Task不存在。", "请先发布父Task。")
	var context := _validate_context(payload.execution_context)
	if not context.ok: return context
	var definition: Dictionary = domain.definitions[definition_id]
	if source_type not in definition.allowed_source_types: return _failure("task.source_not_allowed", "该Task定义不允许当前来源类型。", "请修改定义来源白名单。")
	var objective_state: Dictionary = {}
	for objective in definition.objectives: objective_state[objective.objective_id] = {"current":0,"target":int(objective.target_value),"complete":false,"receipt_ids":[],"last_signal_sequence":0}
	var task := {"schema":"gm.task.instance.v3","task_id":task_id,"definition_id":definition_id,"state":initial_state,"source":{"schema":"gm.task.source.v1","type":source_type,"id":source_id},"assignment_id":"","group_id":group_id,"parent_task_id":parent_id,"child_task_ids":[],"objectives":objective_state,"execution_context":context.context,"result":{},"result_receipts":[],"created_sequence":int(domain.next_sequence)}
	domain.next_sequence += 1
	if not parent_id.is_empty(): domain.tasks[parent_id].child_task_ids.append(task_id)
	domain.tasks[task_id]=task
	return _applied(domain,{"task_id":task_id,"state":initial_state},[task_id])

func _assign(domain: Dictionary, payload: Dictionary, replacing: bool) -> Dictionary:
	var required := _require(payload,["assignment_id","task_id","assignee","kind"])
	if not required.ok: return required
	var task_id:=str(payload.task_id); var assignment_id:=str(payload.assignment_id); var kind:=str(payload.kind)
	if not _stable_id(task_id) or not _stable_id(assignment_id) or kind not in ["actor","group","role","department"]: return _failure("task.assignment_identity_invalid", "Assignment身份或类型无效。", "请使用稳定ID及actor/group/role/department类型。")
	if not payload.assignee is Dictionary or not _typed_ref(payload.assignee): return _failure("task.assignee_invalid", "执行者必须是稳定类型+ID引用。", "请移除Node/RID/NodePath并填写稳定引用。")
	if not domain.tasks.has(task_id): return _failure("task.missing", "待分配Task不存在。", "请刷新Task列表。")
	var task: Dictionary=domain.tasks[task_id]
	if task.state in TERMINAL_STATES: return _failure("task.terminal_immutable", "终态Task不可重新分配。", "请发布新Task。")
	var old_id:=str(task.assignment_id)
	if replacing:
		if old_id.is_empty() or not domain.assignments.has(old_id): return _failure("task.assignment_missing", "重分配缺少当前Assignment。", "请先建立Assignment。")
		domain.assignments[old_id].state="revoked"; domain.assignments[old_id].reason_code="task.reassigned"
		_release_assignment_reservations(domain,old_id,"task.reassigned")
	elif not old_id.is_empty(): return _failure("task.already_assigned", "Task已有Assignment。", "请使用reassign操作。")
	if domain.assignments.has(assignment_id): return _failure("task.assignment_duplicate", "Assignment ID已存在。", "请使用新的稳定ID。")
	domain.assignments[assignment_id]={"schema":"gm.task.assignment.v1","assignment_id":assignment_id,"task_id":task_id,"kind":kind,"assignee":payload.assignee.duplicate(true),"state":"active","reason_code":"","created_sequence":int(domain.next_sequence)}; domain.next_sequence+=1
	task.assignment_id=assignment_id; task.state="assigned"; domain.tasks[task_id]=task
	return _applied(domain,{"task_id":task_id,"assignment_id":assignment_id,"state":"assigned"},[task_id,assignment_id])

func _revoke_assignment(domain: Dictionary, payload: Dictionary) -> Dictionary:
	var checked:=_assignment_owner(domain,payload); if not checked.ok:return checked
	var task:Dictionary=domain.tasks[checked.task_id]; var assignment:Dictionary=domain.assignments[checked.assignment_id]
	assignment.state="revoked"; assignment.reason_code=str(payload.get("reason_code","task.assignment_revoked")); task.assignment_id=""; task.state="available"; domain.assignments[checked.assignment_id]=assignment; domain.tasks[checked.task_id]=task
	_release_task_reservations(domain,checked.task_id,"task.assignment_revoked")
	return _applied(domain,{"task_id":checked.task_id,"assignment_id":checked.assignment_id,"state":"available"},[checked.task_id,checked.assignment_id])

func _reject_assignment(domain: Dictionary, payload: Dictionary) -> Dictionary:
	var checked:=_assignment_owner(domain,payload); if not checked.ok:return checked
	var task:Dictionary=domain.tasks[checked.task_id]; var assignment:Dictionary=domain.assignments[checked.assignment_id]
	assignment.state="rejected"; assignment.reason_code=str(payload.get("reason_code","task.assignment_rejected")); task.assignment_id=""; task.state="available"; domain.assignments[checked.assignment_id]=assignment; domain.tasks[checked.task_id]=task
	_release_task_reservations(domain,checked.task_id,"task.assignment_rejected")
	return _applied(domain,{"task_id":checked.task_id,"assignment_id":checked.assignment_id,"state":"available"},[checked.task_id,checked.assignment_id])

func _transition(domain: Dictionary, payload: Dictionary, receipt_key: String) -> Dictionary:
	var required:=_require(payload,["task_id","to_state","reason_code","result"]); if not required.ok:return required
	var task_id:=str(payload.task_id); var next:=str(payload.to_state)
	if not domain.tasks.has(task_id): return _failure("task.missing", "Task不存在。", "请刷新Task列表。")
	var task:Dictionary=domain.tasks[task_id]; var current:=str(task.state)
	if current in TERMINAL_STATES:
		if next==current and receipt_key in task.result_receipts:return _applied(domain,{"task_id":task_id,"state":current,"receipt_duplicate":true},[task_id],true)
		return _failure("task.terminal_immutable", "Task终态互斥且不可再次结算。", "请读取既有Result收据。")
	var allowed:Dictionary={"draft":["available","cancelled"],"available":["cancelled"],"assigned":["in_progress","available","blocked","failed","cancelled"],"in_progress":["blocked","completed","failed","cancelled"],"blocked":["in_progress","available","failed","cancelled"]}
	if next not in allowed.get(current,[]): return _failure("task.lifecycle_transition_invalid", "Task生命周期转换无效：%s→%s" % [current,next], "请按草拟/可接取/已分配/执行中/阻断/终态顺序操作。")
	if next=="completed" and not _objectives_complete(task): return _failure("task.objectives_incomplete", "Task目标尚未全部完成。", "请等待已提交Fact推进目标。")
	if next in TERMINAL_STATES:
		task.result={"schema":"gm.task.result.v1","result_id":"gm.task.result.%s"%receipt_key.sha256_text(),"state":next,"reason_code":str(payload.reason_code),"data":payload.result.duplicate(true)}; task.result_receipts.append(receipt_key); _close_task_assignment(domain,task,"task.%s"%next); _release_task_reservations(domain,task_id,"task.%s"%next)
	elif next=="available":
		_close_task_assignment(domain,task,"task.returned_available"); _release_task_reservations(domain,task_id,"task.returned_available")
	task.state=next; domain.tasks[task_id]=task
	return _applied(domain,{"task_id":task_id,"state":next,"result_receipt":receipt_key if next in TERMINAL_STATES else ""},[task_id])

func _apply_signal(domain: Dictionary, signal_value: Dictionary) -> Dictionary:
	var fields:=["kind","signal_id","type","payload","transaction_id","causal_chain_id","commit_proof","fact_event_id","global_sequence","instance_id"]
	if not _require_exact(signal_value,fields).ok:return _failure("task.signal_uncommitted","Objective Adapter拒绝调用方自填或截断的信号。","请仅通过consume_committed_signal传入权威身份。")
	if not _valid_signal_envelope(signal_value):return _failure("task.signal_invalid", "Objective Adapter只接受完整类型化且有全局提交序号的Fact/Change/Cue。", "请传入已提交信号的稳定身份、事务证明与全局序号。")
	if _verified_signal_hashes.get(_signal_verification_key(signal_value),"") != _signal_hash(signal_value): return _failure("task.signal_uncommitted","Objective Adapter拒绝未提交或内容不一致的事件。","请传入权威FactEventStore中的身份或真实CommittedFactResult收据。")
	var pending:Array=[];var changed:Array=[]
	for task_id in domain.tasks:
		var task:Dictionary=domain.tasks[task_id]
		var definition:Dictionary=domain.definitions[task.definition_id]
		for objective in definition.objectives:
			if str(objective.signal_kind)!=str(signal_value.kind) or str(objective.signal_type)!=str(signal_value.type):continue
			var matches:=true
			for key in objective.target_match:
				if signal_value.payload.get(key)!=objective.target_match[key]:matches=false;break
			if not matches:continue
			var progress:Dictionary=task.objectives[objective.objective_id]
			var receipt_id:=_signal_receipt_id(str(task_id),str(objective.objective_id),signal_value)
			if receipt_id in progress.receipt_ids:continue
			if task.state not in ["assigned","in_progress","blocked"]:continue
			var contribution := _objective_contribution(signal_value.payload.get(objective.contribution_field,0))
			if not contribution.ok:return contribution
			var amount: int = int(contribution.value)
			if int(signal_value.global_sequence)<=int(progress.last_signal_sequence):return _failure("task.signal_out_of_order","Objective拒绝晚到的旧提交事件。","请按权威账本全局提交序号消费事件或读取既有进度。")
			pending.append({"task_id":str(task_id),"objective_id":str(objective.objective_id),"amount":int(amount),"receipt":_build_signal_receipt(receipt_id,str(task_id),str(objective.objective_id),int(amount),signal_value)})
	for item in pending:
		var task:Dictionary=domain.tasks[item.task_id];var progress:Dictionary=task.objectives[item.objective_id];var receipt:Dictionary=item.receipt
		domain.signal_receipts[receipt.receipt_id]=receipt;progress.receipt_ids.append(receipt.receipt_id);progress.current=mini(int(progress.target),int(progress.current)+int(item.amount));progress.complete=int(progress.current)>=int(progress.target);progress.last_signal_sequence=int(receipt.global_sequence);task.objectives[item.objective_id]=progress
		if task.state in ["assigned","blocked"]:task.state="in_progress"
		domain.tasks[item.task_id]=task;if item.task_id not in changed:changed.append(item.task_id)
	return _applied(domain,{"signal_id":signal_value.signal_id,"tasks_changed":changed.duplicate()},changed)

func _preview_signal_application(domain:Dictionary,signal_value:Dictionary)->Dictionary:
	if not _valid_signal_envelope(signal_value):return _failure("task.signal_invalid","Objective Adapter只接受完整类型化且有全局提交序号的Fact/Change/Cue。","请传入权威账本中的已提交信号身份。")
	var pending_count:=0;var duplicate_count:=0;var matched_count:=0
	for task_id in domain.tasks:
		var task:Dictionary=domain.tasks[task_id]
		var definition:Dictionary=domain.definitions[task.definition_id]
		for objective in definition.objectives:
			if str(objective.signal_kind)!=str(signal_value.kind) or str(objective.signal_type)!=str(signal_value.type):continue
			var matches:=true
			for key in objective.target_match:
				if signal_value.payload.get(key)!=objective.target_match[key]:matches=false;break
			if not matches:continue
			matched_count+=1
			var progress:Dictionary=task.objectives[objective.objective_id]
			var receipt_id:=_signal_receipt_id(str(task_id),str(objective.objective_id),signal_value)
			if receipt_id in progress.receipt_ids:duplicate_count+=1;continue
			if task.state not in ["assigned","in_progress","blocked"]:continue
			var contribution := _objective_contribution(signal_value.payload.get(objective.contribution_field,0))
			if not contribution.ok:return contribution
			if int(signal_value.global_sequence)<=int(progress.last_signal_sequence):return _failure("task.signal_out_of_order","Objective拒绝晚到的旧提交事件。","请按权威账本全局提交序号消费事件或读取既有进度。")
			pending_count+=1
	return {"ok":true,"pending_count":pending_count,"duplicate_count":duplicate_count,"matched_count":matched_count}

func _register_provider(domain: Dictionary, payload: Dictionary) -> Dictionary:
	var required:=_require(payload,["provider_id","definition_id","event_type","key_field","subject"]);if not required.ok:return required
	var provider_id:=str(payload.provider_id)
	if not _stable_id(provider_id) or not domain.definitions.has(str(payload.definition_id)) or typeof(payload.event_type)!=TYPE_STRING or str(payload.event_type).is_empty() or typeof(payload.key_field)!=TYPE_STRING or str(payload.key_field).is_empty() or not payload.subject is Dictionary or not _typed_ref(payload.subject):return _failure("task.duty_provider_invalid","DutyProvider定义无效。","请配置稳定ID、Task定义、显式事件、幂等键字段和稳定主体引用。")
	var row:={"schema":"gm.task.duty_provider.v1","provider_id":provider_id,"definition_id":str(payload.definition_id),"event_type":str(payload.event_type),"key_field":str(payload.key_field),"subject":payload.subject.duplicate(true)}
	if domain.providers.has(provider_id):
		if domain.providers[provider_id]==row:return _applied(domain,{"provider_id":provider_id,"unchanged":true},[provider_id],true)
		return _failure("task.duty_provider_conflict","DutyProvider ID已存在不同定义。","请使用新ID或读取既有定义。")
	domain.providers[provider_id]=row
	return _applied(domain,{"provider_id":provider_id},[provider_id])

func _duty_event(domain:Dictionary,payload:Dictionary,source_id:String)->Dictionary:
	var required:=_require(payload,["provider_id","event_id","event_type","active","data"]);if not required.ok:return required
	if not domain.providers.has(str(payload.provider_id)):return _failure("task.duty_provider_missing","DutyProvider不存在。","请先注册Provider。")
	if typeof(payload.active)!=TYPE_BOOL or not payload.data is Dictionary or not _stable_id(str(payload.event_id)):return _failure("task.duty_event_invalid","职责事件字段无效。","请传入显式布尔条件、稳定事件ID与数据。")
	if domain.provider_receipts.has(payload.event_id):return _applied(domain,{"event_id":payload.event_id,"duplicate":true},[],true)
	var provider:Dictionary=domain.providers[payload.provider_id]
	if str(payload.event_type)!=str(provider.event_type):return _failure("task.duty_event_type_mismatch","职责事件类型与Provider不匹配。","请发送Provider声明的显式事件。")
	var key:=str(payload.data.get(provider.key_field,""));if not _stable_id(key):return _failure("task.duty_key_invalid","职责事件缺少稳定幂等键。","请填写Provider要求的数据键。")
	var task_id:="gm.task.duty.%s" % ("%s|%s|%s|%s"%[payload.provider_id,key,provider.subject.type,provider.subject.id]).sha256_text()
	domain.provider_receipts[payload.event_id]=true
	if payload.active:
		if domain.tasks.has(task_id) and domain.tasks[task_id].state not in TERMINAL_STATES:return _applied(domain,{"task_id":task_id,"duplicate":true},[task_id],true)
		var stable_context:={"provider_id":payload.provider_id,"key":key,"subject":provider.subject.duplicate(true)}
		for context_key in ["typed_domain_request","causal_identity"]:
			if payload.data.has(context_key):
				if not payload.data[context_key] is Dictionary:return _failure("task.duty_event_context_invalid","职责事件的下游上下文必须是纯数据字典。","请传入稳定的Process请求与因果身份。")
				stable_context[context_key]=payload.data[context_key].duplicate(true)
		var publish_payload:={"task_id":task_id,"definition_id":provider.definition_id,"parent_task_id":"","group_id":"","execution_context":{"mode":"summary","stable_context":stable_context}}
		return _publish_task(domain,publish_payload,"duty_provider",source_id)
	if domain.tasks.has(task_id) and domain.tasks[task_id].state not in TERMINAL_STATES:
		var task:Dictionary=domain.tasks[task_id];task.state="cancelled";task.result={"schema":"gm.task.result.v1","result_id":"gm.task.result.%s"%str(payload.event_id).sha256_text(),"state":"cancelled","reason_code":"task.duty_condition_inactive","data":{"event_id":payload.event_id}};task.result_receipts.append(str(payload.event_id));_close_task_assignment(domain,task,"task.duty_condition_inactive");domain.tasks[task_id]=task;_release_task_reservations(domain,task_id,"task.duty_condition_inactive")
	return _applied(domain,{"task_id":task_id,"active":false},[task_id])

func _acquire_reservation(domain:Dictionary,payload:Dictionary)->Dictionary:
	var required:=_require(payload,["reservation_id","task_id","assignment_id","owner","subject","rule_id","amount","expires_at_tick"]);if not required.ok:return required
	var rid:=str(payload.reservation_id);var task_id:=str(payload.task_id);var aid:=str(payload.assignment_id);var rule_id:=str(payload.rule_id)
	if not _stable_id(rid) or not _stable_id(task_id) or not _stable_id(aid) or not _stable_id(rule_id) or not payload.owner is Dictionary or not _typed_ref(payload.owner) or not payload.subject is Dictionary or not _typed_ref(payload.subject) or typeof(payload.amount)!=TYPE_INT or int(payload.amount)<=0 or typeof(payload.expires_at_tick)!=TYPE_INT:return _failure("task.reservation_invalid","Reservation字段或稳定引用无效。","请检查owner/task/assignment/subject、权威规则、数量和显式逻辑时钟。")
	if not domain.tasks.has(task_id) or not domain.assignments.has(aid) or str(domain.tasks[task_id].assignment_id)!=aid or str(domain.assignments[aid].task_id)!=task_id or domain.assignments[aid].state!="active":return _failure("task.reservation_assignment_mismatch","Reservation的Task与Assignment不一致。","请使用当前有效委派。")
	if domain.assignments[aid].assignee!=payload.owner:return _failure("task.reservation_owner_mismatch","Reservation owner不是当前执行者。","请使用Assignment中的稳定执行者引用。")
	var authority:=_reservation_rule(domain,task_id,rule_id,payload.subject);if not authority.ok:return authority
	var mode:=str(authority.rule.mode);var capacity:=int(authority.rule.capacity)
	if payload.has("mode") and (typeof(payload.mode)!=TYPE_STRING or str(payload.mode)!=mode):return _failure("task.reservation_rule_mismatch","请求模式与权威Reservation规则不一致。","请读取Task定义的权威规则。")
	if payload.has("capacity") and (typeof(payload.capacity)!=TYPE_INT or int(payload.capacity)!=capacity):return _failure("task.reservation_rule_mismatch","请求容量与权威Reservation规则不一致。","竞争请求不得自报或扩大容量。")
	if int(payload.expires_at_tick)>=0 and int(payload.expires_at_tick)<=int(domain.logical_tick):return _failure("task.reservation_expiry_invalid","Reservation到期逻辑时刻必须晚于当前时刻。","请由显式逻辑时钟设置未来到期值。")
	if domain.reservations.has(rid):
		var existing:Dictionary=domain.reservations[rid]
		if existing.task_id==task_id and existing.assignment_id==aid and existing.owner==payload.owner and existing.subject==payload.subject and existing.rule_id==rule_id and existing.mode==mode and int(existing.amount)==int(payload.amount) and existing.state=="active":return _applied(domain,{"reservation_id":rid,"duplicate":true},[rid],true)
		return _failure("task.reservation_id_conflict","Reservation ID已用于不同占用。","请读取既有Reservation或使用新ID。")
	var used:=0
	for value in domain.reservations.values():
		if value.state!="active" or value.subject!=payload.subject:continue
		if str(value.mode)!=mode or int(value.capacity)!=capacity:return _failure("task.reservation_rule_conflict","同一subject存在不同权威Reservation规则。","请统一Definition规则后再竞争。")
		if mode=="exclusive" or str(value.mode)=="exclusive":return _failure("task.reservation_conflict","稳定对象已有活动占用，独占与任何模式双向冲突。","请等待现有Reservation释放。")
		used+=int(value.amount)
	if mode=="capacity" and (used+int(payload.amount)>capacity):return _failure("task.reservation_capacity_exceeded","稳定对象剩余容量不足。","请降低占用量或等待释放。")
	if mode=="exclusive" and int(payload.amount)!=1:return _failure("task.reservation_exclusive_amount_invalid","排他占用量必须为1。","请把amount设为1。")
	domain.reservations[rid]={"schema":"gm.task.reservation.v1","reservation_id":rid,"task_id":task_id,"assignment_id":aid,"owner":payload.owner.duplicate(true),"subject":payload.subject.duplicate(true),"rule_id":rule_id,"mode":mode,"amount":int(payload.amount),"capacity":capacity,"expires_at_tick":int(payload.expires_at_tick),"state":"active","consume_receipts":[],"reason_code":""}
	return _applied(domain,{"reservation_id":rid,"state":"active"},[rid,task_id,aid])

func _renew_reservation(domain:Dictionary,payload:Dictionary)->Dictionary:
	var checked:=_reservation_owner(domain,payload,["active"]);if not checked.ok:return checked
	if typeof(payload.get("expires_at_tick"))!=TYPE_INT or int(payload.expires_at_tick)<=int(domain.logical_tick):return _failure("task.reservation_expiry_invalid","续期时刻必须晚于当前逻辑时刻。","请传入未来显式逻辑时刻。")
	var row:Dictionary=domain.reservations[checked.reservation_id];row.expires_at_tick=int(payload.expires_at_tick);domain.reservations[checked.reservation_id]=row
	return _applied(domain,{"reservation_id":checked.reservation_id,"expires_at_tick":row.expires_at_tick},[checked.reservation_id])

func _release_reservation(domain:Dictionary,payload:Dictionary)->Dictionary:
	var checked:=_reservation_owner(domain,payload,["active"]);if not checked.ok:return checked
	var row:Dictionary=domain.reservations[checked.reservation_id]
	row.state="released";row.reason_code=str(payload.get("reason_code","task.reservation_released"));domain.reservations[checked.reservation_id]=row
	return _applied(domain,{"reservation_id":checked.reservation_id,"state":"released"},[checked.reservation_id])

func _consume_reservation(domain:Dictionary,payload:Dictionary)->Dictionary:
	var checked:=_reservation_owner(domain,payload,["active"]);if not checked.ok:return checked
	var receipt:=str(payload.get("consume_receipt",""));if not _stable_id(receipt):return _failure("task.reservation_consume_receipt_invalid","消费缺少稳定收据ID。","请提供可幂等重放的消费收据。")
	var row:Dictionary=domain.reservations[checked.reservation_id]
	if receipt in row.consume_receipts:return _failure("task.reservation_consume_duplicate","消费收据已经终结该Reservation。","请读取既有消费结果。")
	row.consume_receipts.append(receipt);row.state="consumed";row.reason_code="task.reservation_consumed";domain.reservations[checked.reservation_id]=row
	return _applied(domain,{"reservation_id":checked.reservation_id,"state":"consumed","consume_receipt":receipt},[checked.reservation_id])

func _advance_clock(domain:Dictionary,payload:Dictionary)->Dictionary:
	if typeof(payload.get("to_tick"))!=TYPE_INT or int(payload.to_tick)<int(domain.logical_tick):return _failure("task.logical_clock_invalid","逻辑时钟只能由显式事件单调推进。","请提供不小于当前值的整数tick。")
	domain.logical_tick=int(payload.to_tick);var expired:Array=[]
	for rid in domain.reservations:
		var row:Dictionary=domain.reservations[rid]
		if row.state=="active" and int(row.expires_at_tick)>=0 and int(row.expires_at_tick)<=int(domain.logical_tick):row.state="expired";row.reason_code="task.reservation_expired";domain.reservations[rid]=row;expired.append(rid)
	return _applied(domain,{"logical_tick":domain.logical_tick,"expired":expired.duplicate()},expired)

func _assignment_owner(domain:Dictionary,payload:Dictionary)->Dictionary:
	var aid:=str(payload.get("assignment_id",""));var task_id:=str(payload.get("task_id",""))
	if not domain.assignments.has(aid) or not domain.tasks.has(task_id) or str(domain.assignments[aid].task_id)!=task_id or str(domain.tasks[task_id].assignment_id)!=aid or domain.assignments[aid].state!="active":return _failure("task.assignment_mismatch","Task与活动Assignment不一致。","请刷新并使用当前委派。")
	return {"ok":true,"assignment_id":aid,"task_id":task_id}

func _reservation_owner(domain:Dictionary,payload:Dictionary,allowed_states:Array)->Dictionary:
	var rid:=str(payload.get("reservation_id",""));if not domain.reservations.has(rid):return _failure("task.reservation_missing","Reservation不存在。","请刷新占用列表。")
	var row:Dictionary=domain.reservations[rid]
	for field in ["task_id","assignment_id","owner","subject"]:
		if not payload.has(field) or payload[field]!=row[field]:return _failure("task.reservation_owner_mismatch","释放、续期或消费的owner/task/assignment不匹配。","请使用取得占用时的完整所有权信息。")
	if str(row.state) not in allowed_states:return _failure("task.reservation_not_active","Reservation不是允许操作的活动状态。","请读取既有终态并停止重复操作。")
	var task_id:=str(row.task_id);var aid:=str(row.assignment_id)
	if not domain.tasks.has(task_id) or not domain.assignments.has(aid) or str(domain.tasks[task_id].assignment_id)!=aid or str(domain.assignments[aid].task_id)!=task_id or str(domain.assignments[aid].state)!="active" or domain.assignments[aid].assignee!=row.owner:return _failure("task.reservation_assignment_mismatch","Reservation不再属于当前活动Assignment。","改派、撤销或终结后不得继续操作旧占用。")
	var authority:=_reservation_rule(domain,task_id,str(row.rule_id),row.subject);if not authority.ok:return authority
	if str(authority.rule.mode)!=str(row.mode) or int(authority.rule.capacity)!=int(row.capacity):return _failure("task.reservation_rule_mismatch","Reservation与当前权威规则不一致。","请拒绝损坏占用。")
	return {"ok":true,"reservation_id":rid}

func _release_task_reservations(domain:Dictionary,task_id:String,reason:String)->void:
	for rid in domain.reservations:
		var row:Dictionary=domain.reservations[rid]
		if row.task_id==task_id and row.state=="active":row.state="released";row.reason_code=reason;domain.reservations[rid]=row

func _close_task_assignment(domain:Dictionary,task:Dictionary,reason:String)->void:
	var assignment_id:=str(task.get("assignment_id",""))
	if not assignment_id.is_empty() and domain.assignments.has(assignment_id):
		var assignment:Dictionary=domain.assignments[assignment_id]
		if assignment.state=="active":assignment.state="revoked";assignment.reason_code=reason;domain.assignments[assignment_id]=assignment
	task.assignment_id=""

func _release_assignment_reservations(domain:Dictionary,assignment_id:String,reason:String)->void:
	for rid in domain.reservations:
		var row:Dictionary=domain.reservations[rid]
		if row.assignment_id==assignment_id and row.state=="active":row.state="released";row.reason_code=reason;domain.reservations[rid]=row

func _objectives_complete(task:Dictionary)->bool:
	for progress in task.objectives.values():
		if not bool(progress.complete):return false
	return true

func _validate_context(value:Variant)->Dictionary:
	if not value is Dictionary or not value.has("mode") or not value.has("stable_context") or value.size()!=2 or typeof(value.mode)!=TYPE_STRING or value.mode not in CONTEXT_MODES or not value.stable_context is Dictionary:return _failure("task.execution_context_invalid","TaskExecutionContext字段无效。","请仅声明local/summary/scene与稳定上下文。")
	if not GMStableData.validate_persistence(value.stable_context).ok:return _failure("task.execution_context_unstable","执行上下文包含Node、RID、NodePath或非持久数据。","请改用稳定类型+ID引用。")
	return {"ok":true,"context":{"mode":value.mode,"stable_context":value.stable_context.duplicate(true),"planner_created":false,"scene_session_created":false}}

func _validate_definition_reservation_authority(domain:Dictionary,candidate:Dictionary)->Dictionary:
	for rule in candidate.reservation_rules:
		for definition in domain.definitions.values():
			for existing in definition.reservation_rules:
				if existing.subject!=rule.subject:continue
				if str(existing.mode)!=str(rule.mode) or int(existing.capacity)!=int(rule.capacity):return _failure("task.reservation_authority_conflict","同一稳定subject已由不同模式或容量的Definition声明。","请统一权威Reservation规则。")
	return {"ok":true}

func _reservation_rule(domain:Dictionary,task_id:String,rule_id:String,subject:Dictionary)->Dictionary:
	if not domain.tasks.has(task_id):return _failure("task.missing","Reservation引用的Task不存在。","请刷新Task。")
	var definition_id:=str(domain.tasks[task_id].definition_id)
	if not domain.definitions.has(definition_id):return _failure("task.definition_missing","Reservation引用的Task定义不存在。","请拒绝损坏事实域。")
	for rule in domain.definitions[definition_id].reservation_rules:
		if str(rule.rule_id)==rule_id:
			if rule.subject!=subject:return _failure("task.reservation_subject_mismatch","Reservation subject与权威规则不一致。","请使用Definition声明的稳定subject。")
			return {"ok":true,"rule":rule}
	return _failure("task.reservation_rule_missing","Task定义中不存在该Reservation规则。","请使用已注册Definition中的rule_id。")

func _resolve_committed_signal(identity:Dictionary,authority:Variant)->Dictionary:
	if not identity is Dictionary:return _failure("task.signal_identity_invalid","已提交事件身份必须是Dictionary。","请传入稳定信号身份。")
	var kind:=str(identity.get("kind",""));var signal_id:=str(identity.get("signal_id",""))
	var expected_fields:=["kind","signal_id","fact_event_id"] if kind=="cue" and authority is GMFactEventStore else ["kind","signal_id"]
	if not _require_exact(identity,expected_fields).ok or typeof(identity.get("kind"))!=TYPE_STRING or typeof(identity.get("signal_id"))!=TYPE_STRING or kind not in ["fact","change","cue"] or not _stable_id(signal_id):return _failure("task.signal_identity_invalid","已提交事件身份字段无效。","请传入kind、稳定signal_id以及Cue所属Fact身份。")
	if authority is GMFactEventStore and authority!=fact_store:return _failure("task.signal_authority_mismatch","信号来自不同FactEventStore。","请使用GMTaskService绑定的唯一权威事实账本。")
	if authority is GMCommittedFactResult:
		var supplied:GMCommittedFactResult=authority
		if supplied.authority_store!=fact_store or supplied.fact_event==null:return _failure("task.signal_authority_mismatch","提交结果未绑定本服务的权威事实账本。","请使用本服务FactEventStore对应Coordinator返回的结果。")
		var authoritative:=fact_store.make_committed_result(supplied.fact_event.event_id,supplied.idempotent)
		if authoritative==null or not _committed_result_equal(supplied,authoritative):return _failure("task.signal_authority_copy_changed","调用方持有的提交结果副本已改变或与权威提交包不一致。","请重新从唯一FactEventStore取得已提交结果。")
	var package:Dictionary={}
	if kind=="fact":package=fact_store.get_committed_package(signal_id)
	elif kind=="change":package=fact_store.find_committed_package_for_change(signal_id)
	elif authority is GMCommittedFactResult:package=fact_store.get_committed_package(authority.fact_event.event_id)
	else:package=fact_store.get_committed_package(str(identity.fact_event_id))
	if package.is_empty():return _failure("task.signal_uncommitted","信号身份无法在唯一权威FactEventStore提交包中验证。","请先经Coordinator完成事务提交。")
	var envelope:=_signal_from_package(kind,signal_id,str(package.fact_event_id),package)
	if not envelope.ok:return envelope
	return {"ok":true,"signal":envelope.signal}

func _committed_result_equal(left:GMCommittedFactResult,right:GMCommittedFactResult)->bool:
	if left==null or right==null or left.fact_event==null or right.fact_event==null or left.chain==null or right.chain==null:return false
	if left.transaction_id!=right.transaction_id or left.fact_event.to_dict()!=right.fact_event.to_dict() or left.fact_event.commit_proof!=right.fact_event.commit_proof or left.chain.to_dict()!=right.chain.to_dict() or left.cues!=right.cues:return false
	if left.change_records.size()!=right.change_records.size():return false
	for index in left.change_records.size():
		if left.change_records[index]==null or right.change_records[index]==null or left.change_records[index].to_dict()!=right.change_records[index].to_dict():return false
	return true

func _signal_from_package(kind:String,signal_id:String,fact_event_id:String,package:Dictionary)->Dictionary:
	if package.is_empty() or str(package.get("fact_event_id",""))!=fact_event_id:return _failure("task.signal_authority_link_invalid","信号与所属Fact提交包不一致。","请拒绝不同事务记录组合。")
	var fact:=GMFactEvent.from_dict(package.fact);fact.mark_committed(str(package.commit_proof),GMFactEvent._get_commit_capability())
	if kind=="fact":
		if signal_id!=fact.event_id:return _failure("task.signal_authority_link_invalid","Fact身份与权威提交包不一致。","请使用提交包中的Fact ID。")
		return {"ok":true,"signal":_signal_envelope("fact",fact.event_id,fact.type,fact.payload,fact,fact.event_id,fact.ability_instance_id)}
	if kind=="change":
		for value in package.changes:
			if str(value.get("change_id",""))==signal_id:
				var record:=GMChangeRecord.from_dict(value)
				return {"ok":true,"signal":_signal_envelope("change",record.change_id,record.operation,{"entity_id":record.entity_id,"field":record.field,"before":record.before,"after":record.after,"metadata":record.metadata.duplicate(true)},fact,fact.event_id,fact.ability_instance_id)}
		return _failure("task.signal_authority_link_invalid","Change不属于指定权威提交包。","请使用同一事务的Change身份。")
	for cue in package.cues:
		if str(cue.get("cue_id",""))==signal_id:
			var receipt_signal_id:="gm.cue.receipt.%s"%("%s|%s"%[fact.event_id,signal_id]).sha256_text()
			return {"ok":true,"signal":_signal_envelope("cue",receipt_signal_id,signal_id,cue.parameters,fact,fact.event_id,str(cue.instance_id))}
	return _failure("task.signal_authority_link_invalid","Cue不属于指定权威提交包。","请使用同一事务的Cue身份。")

func _signal_hash(value:Dictionary)->String:
	return JSON.stringify(GMStableData.persistence_canonical(value),"",true,true).sha256_text()

func _signal_envelope(kind:String,signal_id:String,signal_type:String,payload:Dictionary,fact:GMFactEvent,fact_event_id:String,instance_id:String)->Dictionary:
	return {"kind":kind,"signal_id":signal_id,"type":signal_type,"payload":payload.duplicate(true),"transaction_id":fact.transaction_id,"causal_chain_id":fact.causal_chain_id,"commit_proof":fact.commit_proof,"fact_event_id":fact_event_id,"global_sequence":int(fact.sequence),"instance_id":instance_id}

func _valid_signal_envelope(value:Dictionary)->bool:
	if value.kind not in ["fact","change","cue"] or not _stable_id(str(value.signal_id)) or typeof(value.type)!=TYPE_STRING or not _stable_id(str(value.type)) or not str(value.type).begins_with("gm.%s."%str(value.kind)):return false
	if not value.payload is Dictionary or typeof(value.transaction_id)!=TYPE_STRING or not _stable_id(str(value.transaction_id)) or typeof(value.causal_chain_id)!=TYPE_STRING or not _stable_id(str(value.causal_chain_id)) or typeof(value.commit_proof)!=TYPE_STRING or value.commit_proof!=value.transaction_id:return false
	return typeof(value.fact_event_id)==TYPE_STRING and _stable_id(str(value.fact_event_id)) and typeof(value.global_sequence)==TYPE_INT and int(value.global_sequence)>=1 and typeof(value.instance_id)==TYPE_STRING and _stable_id(str(value.instance_id))

func _signal_verification_key(value:Dictionary)->String:
	return "%s|%s"%[str(value.get("kind","")),str(value.get("signal_id",""))]

func _signal_receipt_id(task_id:String,objective_id:String,signal_value:Dictionary)->String:
	return "gm.task.signal_receipt.%s"%("%s|%s|%s|%s"%[task_id,objective_id,signal_value.kind,signal_value.signal_id]).sha256_text()

func _objective_contribution(value:Variant)->Dictionary:
	if typeof(value)==TYPE_INT and int(value)>=0:return {"ok":true,"value":int(value)}
	if typeof(value)==TYPE_FLOAT:
		var number:=float(value)
		if is_finite(number) and number>=0.0 and number==floor(number) and number<JSON_SAFE_BOUND:return {"ok":true,"value":int(number)}
	return _failure("task.signal_contribution_invalid", "Objective贡献必须是非负整数。", "请修正已提交信号的贡献字段。")

func _build_signal_receipt(receipt_id:String,task_id:String,objective_id:String,contribution:int,signal_value:Dictionary)->Dictionary:
	var row:={"schema":SIGNAL_RECEIPT_SCHEMA,"receipt_id":receipt_id,"task_id":task_id,"objective_id":objective_id,"signal_kind":str(signal_value.kind),"signal_id":str(signal_value.signal_id),"signal_type":str(signal_value.type),"signal_instance_id":str(signal_value.instance_id),"transaction_id":str(signal_value.transaction_id),"causal_chain_id":str(signal_value.causal_chain_id),"commit_proof":str(signal_value.commit_proof),"fact_event_id":str(signal_value.fact_event_id),"global_sequence":int(signal_value.global_sequence),"payload":signal_value.payload.duplicate(true),"contribution":contribution,"verified_hash":""}
	row.verified_hash=_receipt_verified_hash(row)
	return row

func _receipt_verified_hash(row:Dictionary)->String:
	return _signal_hash({"kind":row.get("signal_kind"),"signal_id":row.get("signal_id"),"type":row.get("signal_type"),"instance_id":row.get("signal_instance_id"),"payload":row.get("payload",{}),"transaction_id":row.get("transaction_id"),"causal_chain_id":row.get("causal_chain_id"),"commit_proof":row.get("commit_proof"),"fact_event_id":row.get("fact_event_id"),"global_sequence":row.get("global_sequence")})

func _validate_domain(domain:Dictionary,authority_store:GMFactEventStore=fact_store)->Dictionary:
	var exact:=_require_exact(domain,["schema","logical_tick","next_sequence","definitions","groups","tasks","assignments","providers","reservations","signal_receipts","provider_receipts"]);if not exact.ok:return exact
	if domain.schema!=STORE_SCHEMA or typeof(domain.logical_tick)!=TYPE_INT or int(domain.logical_tick)<0 or typeof(domain.next_sequence)!=TYPE_INT or int(domain.next_sequence)<1:return _failure("task.domain_header_invalid","Task事实域头部无效。","请拒绝损坏快照。",{"schema":domain.get("schema"),"expected_schema":STORE_SCHEMA,"logical_tick":domain.get("logical_tick"),"logical_tick_type":typeof(domain.get("logical_tick")),"next_sequence":domain.get("next_sequence"),"next_sequence_type":typeof(domain.get("next_sequence"))})
	for field in ["definitions","groups","tasks","assignments","providers","reservations","signal_receipts","provider_receipts"]:
		if not domain[field] is Dictionary:return _failure("task.domain_type_invalid","Task事实域字段%s类型无效。"%field,"请拒绝损坏快照。")
	for definition_id in domain.definitions:
		if typeof(definition_id)!=TYPE_STRING or not _stable_id(str(definition_id)) or not domain.definitions[definition_id] is Dictionary:return _failure("task.definition_row_invalid","Definition键或行类型无效。","请拒绝损坏快照。")
		var definition:=GMTaskDefinition.new();var applied:=definition.apply_dict(domain.definitions[definition_id]);if not applied.ok or definition.definition_id!=str(definition_id):return _failure("task.definition_row_invalid","Definition逐字段校验失败。","请使用当前Definition Schema。",{"definition_id":definition_id,"validation":applied})
		var authority:=_validate_definition_reservation_authority(domain,definition.to_dict());if not authority.ok:return authority
	for group_id in domain.groups:
		var group:Variant=domain.groups[group_id]
		if not group is Dictionary or not _require_exact(group,["schema","group_id","member_refs"]).ok or group.schema!="gm.task.group.v1" or typeof(group.group_id)!=TYPE_STRING or str(group.group_id)!=str(group_id) or not _stable_id(str(group_id)) or not group.member_refs is Array:return _failure("task.group_row_invalid","Task Group逐字段校验失败。","请拒绝损坏快照。")
		var member_keys:Dictionary={}
		for member in group.member_refs:
			if not _typed_ref(member):return _failure("task.group_member_invalid","Task Group成员引用无效。","请拒绝Node或重复引用。")
			var member_key:=JSON.stringify(member,"",true,true);if member_keys.has(member_key):return _failure("task.group_member_duplicate","Task Group包含重复成员。","请移除重复引用。");member_keys[member_key]=true
	for receipt_id in domain.signal_receipts:
		var receipt_checked:=_validate_signal_receipt_row(str(receipt_id),domain.signal_receipts[receipt_id],domain,authority_store);if not receipt_checked.ok:return receipt_checked
	var sequence_seen:Dictionary={};var maximum_sequence:=0
	for task_id in domain.tasks:
		var task:Variant=domain.tasks[task_id]
		var row_check:=_validate_task_row(str(task_id),task,domain);if not row_check.ok:return row_check
		var task_row:Dictionary=task;var sequence:=int(task_row.created_sequence);if sequence_seen.has(sequence):return _failure("task.sequence_duplicate","Task/Assignment创建序列重复。","请拒绝拼接快照。");sequence_seen[sequence]=true;maximum_sequence=maxi(maximum_sequence,sequence)
		var parent:=str(task.get("parent_task_id",""));if not parent.is_empty() and (not domain.tasks.has(parent) or task_id not in domain.tasks[parent].get("child_task_ids",[])):return _failure("task.parent_relation_invalid","父子Task关系不一致。","请拒绝循环或断边快照。")
		for child_id in task.child_task_ids:
			if not domain.tasks.has(child_id) or str(domain.tasks[child_id].get("parent_task_id",""))!=str(task_id):return _failure("task.child_relation_invalid","子Task反向关系不一致。","请拒绝断边快照。")
		if _parent_cycle(domain,str(task_id)):return _failure("task.parent_cycle","父子Task图包含循环。","请在写入前移除循环关系。")
		var aid:=str(task.get("assignment_id",""));if not aid.is_empty() and (not domain.assignments.has(aid) or str(domain.assignments[aid].get("task_id",""))!=str(task_id) or str(domain.assignments[aid].get("state",""))!="active"):return _failure("task.assignment_relation_invalid","Task与Assignment关系不一致。","请拒绝损坏快照。")
	for assignment_id in domain.assignments:
		var assignment_checked:=_validate_assignment_row(str(assignment_id),domain.assignments[assignment_id],domain);if not assignment_checked.ok:return assignment_checked
		var assignment:Dictionary=domain.assignments[assignment_id];var sequence:=int(assignment.created_sequence);if sequence_seen.has(sequence):return _failure("task.sequence_duplicate","Task/Assignment创建序列重复。","请拒绝拼接快照。");sequence_seen[sequence]=true;maximum_sequence=maxi(maximum_sequence,sequence)
		var current:=str(domain.tasks[assignment.task_id].assignment_id)
		if (assignment.state=="active" and current!=str(assignment_id)) or (assignment.state!="active" and current==str(assignment_id)):return _failure("task.assignment_relation_invalid","Assignment活动状态与Task当前委派不一致。","请拒绝损坏快照。")
	for provider_id in domain.providers:
		var provider_checked:=_validate_provider_row(str(provider_id),domain.providers[provider_id],domain);if not provider_checked.ok:return provider_checked
	var active_subjects:Dictionary={}
	for rid in domain.reservations:
		var reservation_checked:=_validate_reservation_row(str(rid),domain.reservations[rid],domain);if not reservation_checked.ok:return reservation_checked
		var row:Dictionary=domain.reservations[rid]
		if row.state=="active":
			var subject_key:=JSON.stringify(row.subject,"",true,true);var aggregate:Dictionary=active_subjects.get(subject_key,{"mode":row.mode,"capacity":row.capacity,"used":0})
			if aggregate.mode!=row.mode or int(aggregate.capacity)!=int(row.capacity) or row.mode=="exclusive" and int(aggregate.used)>0:return _failure("task.reservation_active_conflict","活动Reservation违反同一subject权威规则。","请拒绝冲突快照。")
			aggregate.used=int(aggregate.used)+int(row.amount);if row.mode=="exclusive" and int(aggregate.used)>1 or row.mode=="capacity" and int(aggregate.used)>int(row.capacity):return _failure("task.reservation_capacity_exceeded","活动Reservation总量超过权威上限。","请拒绝冲突快照。");active_subjects[subject_key]=aggregate
	if int(domain.next_sequence)<=maximum_sequence:return _failure("task.next_sequence_invalid","next_sequence未超过全部创建序列。","请拒绝可能重复身份的快照。")
	for receipt_id in domain.provider_receipts:
		if typeof(receipt_id)!=TYPE_STRING or not _stable_id(str(receipt_id)) or typeof(domain.provider_receipts[receipt_id])!=TYPE_BOOL or not bool(domain.provider_receipts[receipt_id]):return _failure("task.receipt_row_invalid","Provider事件收据键或值无效。","请拒绝伪造收据。")
	var stable:=GMStableData.validate_persistence(domain);if not stable.ok:return _failure("task.domain_unstable","Task事实域包含不可持久化值。","请移除Node、RID、NodePath或非有限数值。",{"errors":stable.errors})
	return {"ok":true}

func _validate_task_row(task_id:String,value:Variant,domain:Dictionary)->Dictionary:
	if not value is Dictionary:return _failure("task.task_row_invalid","Task行必须是Dictionary。","请拒绝损坏快照。")
	var row:Dictionary=value;var fields:=["schema","task_id","definition_id","state","source","assignment_id","group_id","parent_task_id","child_task_ids","objectives","execution_context","result","result_receipts","created_sequence"]
	if not _require_exact(row,fields).ok or row.schema!="gm.task.instance.v3" or typeof(row.task_id)!=TYPE_STRING or row.task_id!=task_id or not _stable_id(task_id) or typeof(row.definition_id)!=TYPE_STRING or not domain.definitions.has(row.definition_id) or typeof(row.state)!=TYPE_STRING or row.state not in TASK_STATES or typeof(row.assignment_id)!=TYPE_STRING or typeof(row.group_id)!=TYPE_STRING or typeof(row.parent_task_id)!=TYPE_STRING or not row.child_task_ids is Array or not row.objectives is Dictionary or not row.execution_context is Dictionary or not row.result is Dictionary or not row.result_receipts is Array or typeof(row.created_sequence)!=TYPE_INT or int(row.created_sequence)<1:return _failure("task.task_row_invalid","Task字段集合、Schema或Variant类型无效。","请拒绝截断、未知字段或错误类型快照。")
	if not row.assignment_id.is_empty() and not _stable_id(row.assignment_id) or not row.group_id.is_empty() and (not _stable_id(row.group_id) or not domain.groups.has(row.group_id)) or not row.parent_task_id.is_empty() and not _stable_id(row.parent_task_id):return _failure("task.task_identity_invalid","Task关系ID无效。","请拒绝损坏快照。")
	if not row.source is Dictionary or not _require_exact(row.source,["schema","type","id"]).ok or row.source.schema!="gm.task.source.v1" or typeof(row.source.type)!=TYPE_STRING or row.source.type not in SOURCE_TYPES or typeof(row.source.id)!=TYPE_STRING or not _stable_id(row.source.id) or row.source.type not in domain.definitions[row.definition_id].allowed_source_types:return _failure("task.source_row_invalid","Task Source逐字段或白名单校验失败。","请拒绝伪造来源。")
	if not _unique_stable_strings(row.child_task_ids,true):return _failure("task.child_ids_invalid","子Task ID必须稳定且唯一。","请拒绝重复或错误类型。")
	if not _unique_stable_strings(row.result_receipts,true):return _failure("task.result_receipts_invalid","Result收据必须稳定且唯一。","请拒绝重复收据。")
	if row.state in ["draft","available"] and not row.assignment_id.is_empty():return _failure("task.lifecycle_assignment_invalid","草拟或可接取Task不得保留当前Assignment。","请拒绝生命周期矛盾快照。")
	if row.state in ["assigned","in_progress","blocked"] and row.assignment_id.is_empty():return _failure("task.lifecycle_assignment_invalid","可执行Task必须绑定当前活动Assignment。","请拒绝生命周期矛盾快照。")
	if row.state in TERMINAL_STATES and not row.assignment_id.is_empty():return _failure("task.lifecycle_assignment_invalid","终态Task不得保留当前Assignment。","请拒绝未清理委派的快照。")
	var context:Dictionary=row.execution_context
	if not _require_exact(context,["mode","stable_context","planner_created","scene_session_created"]).ok or typeof(context.mode)!=TYPE_STRING or context.mode not in CONTEXT_MODES or not context.stable_context is Dictionary or typeof(context.planner_created)!=TYPE_BOOL or typeof(context.scene_session_created)!=TYPE_BOOL or context.planner_created or context.scene_session_created or not GMStableData.validate_persistence(context.stable_context).ok:return _failure("task.execution_context_invalid","持久TaskExecutionContext字段无效或越界创建延期对象。","请只保存稳定上下文声明。")
	var definition:Dictionary=domain.definitions[row.definition_id];var objective_ids:Dictionary={}
	for objective in definition.objectives:objective_ids[objective.objective_id]=objective
	if row.objectives.size()!=objective_ids.size():return _failure("task.objective_progress_invalid","Objective进度集合与Definition不一致。","请拒绝截断或附加目标。")
	for objective_id in row.objectives:
		if not objective_ids.has(objective_id):return _failure("task.objective_progress_invalid","Objective进度含未知ID。","请拒绝损坏快照。")
		var progress:Variant=row.objectives[objective_id]
		if not progress is Dictionary or not _require_exact(progress,["current","target","complete","receipt_ids","last_signal_sequence"]).ok or typeof(progress.current)!=TYPE_INT or typeof(progress.target)!=TYPE_INT or typeof(progress.complete)!=TYPE_BOOL or not progress.receipt_ids is Array or typeof(progress.last_signal_sequence)!=TYPE_INT or int(progress.last_signal_sequence)<0 or int(progress.current)<0 or int(progress.target)!=int(objective_ids[objective_id].target_value) or int(progress.current)>int(progress.target) or not _unique_stable_strings(progress.receipt_ids,true):return _failure("task.objective_progress_invalid","Objective进度字段、类型或完成关系无效。","请拒绝损坏快照。")
		var derived_current:=0;var derived_last:=0
		for receipt_id in progress.receipt_ids:
			if not domain.signal_receipts.has(receipt_id):return _failure("task.objective_receipt_missing","Objective进度引用未登记信号。","请拒绝收据洞或伪造推进。")
			var receipt:Dictionary=domain.signal_receipts[receipt_id]
			if receipt.task_id!=task_id or receipt.objective_id!=objective_id:return _failure("task.objective_receipt_mismatch","信号收据被跨Task或跨Objective挪用。","请拒绝拼接快照。")
			if int(receipt.global_sequence)<=derived_last:return _failure("task.objective_receipt_order_invalid","Objective收据必须按全局提交序号严格递增。","请拒绝重复或逆序收据。")
			derived_last=int(receipt.global_sequence);derived_current=mini(int(progress.target),derived_current+int(receipt.contribution))
		if progress.receipt_ids.is_empty() and int(progress.last_signal_sequence)!=0 or not progress.receipt_ids.is_empty() and int(progress.last_signal_sequence)!=derived_last:return _failure("task.objective_sequence_invalid","Objective最后序号不能由已验证收据精确推导。","请拒绝无收据大序号或伪造序号。")
		if int(progress.current)!=derived_current or bool(progress.complete)!=(derived_current>=int(progress.target)):return _failure("task.objective_progress_invalid","Objective current/complete不能由已验证收据精确证明。","请拒绝伪造进度。")
	if row.state in TERMINAL_STATES:
		if not _validate_result_row(row.result,row.state) or row.result_receipts.is_empty():return _failure("task.result_row_invalid","终态Task缺少严格Result或收据。","请拒绝假结算快照。")
		if row.state=="completed" and not _objectives_complete(row):return _failure("task.completed_objectives_invalid","完成态Task必须由全部Objective完成证明。","请拒绝提前完成快照。")
	elif not row.result.is_empty() or not row.result_receipts.is_empty():return _failure("task.result_row_invalid","非终态Task不得携带Result。","请拒绝提前结算。")
	return {"ok":true}

func _validate_result_row(value:Dictionary,state:String)->bool:
	return _require_exact(value,["schema","result_id","state","reason_code","data"]).ok and value.schema=="gm.task.result.v1" and typeof(value.result_id)==TYPE_STRING and _stable_id(value.result_id) and typeof(value.state)==TYPE_STRING and value.state==state and typeof(value.reason_code)==TYPE_STRING and _stable_id(value.reason_code) and value.data is Dictionary and GMStableData.validate_persistence(value.data).ok

func _validate_signal_receipt_row(receipt_id:String,value:Variant,domain:Dictionary,authority_store:GMFactEventStore)->Dictionary:
	if not value is Dictionary:return _failure("task.signal_receipt_invalid","信号收据行必须是Dictionary。","请拒绝损坏快照。")
	var row:Dictionary=value;var fields:=["schema","receipt_id","task_id","objective_id","signal_kind","signal_id","signal_type","signal_instance_id","transaction_id","causal_chain_id","commit_proof","fact_event_id","global_sequence","payload","contribution","verified_hash"]
	if not _require_exact(row,fields).ok or row.schema!=SIGNAL_RECEIPT_SCHEMA or typeof(row.receipt_id)!=TYPE_STRING or row.receipt_id!=receipt_id or not _stable_id(receipt_id) or typeof(row.task_id)!=TYPE_STRING or not domain.tasks.has(row.task_id) or typeof(row.objective_id)!=TYPE_STRING or not _stable_id(row.objective_id) or typeof(row.signal_kind)!=TYPE_STRING or row.signal_kind not in ["fact","change","cue"] or typeof(row.signal_id)!=TYPE_STRING or not _stable_id(row.signal_id) or typeof(row.signal_type)!=TYPE_STRING or not _stable_id(row.signal_type) or not row.signal_type.begins_with("gm.%s."%row.signal_kind) or typeof(row.signal_instance_id)!=TYPE_STRING or not _stable_id(row.signal_instance_id) or typeof(row.transaction_id)!=TYPE_STRING or not _stable_id(row.transaction_id) or typeof(row.causal_chain_id)!=TYPE_STRING or not _stable_id(row.causal_chain_id) or typeof(row.commit_proof)!=TYPE_STRING or row.commit_proof!=row.transaction_id or typeof(row.fact_event_id)!=TYPE_STRING or not _stable_id(row.fact_event_id) or typeof(row.global_sequence)!=TYPE_INT or int(row.global_sequence)<1 or not row.payload is Dictionary or typeof(row.contribution)!=TYPE_INT or int(row.contribution)<0 or typeof(row.verified_hash)!=TYPE_STRING:return _failure("task.signal_receipt_invalid","信号收据字段、Schema、Variant或证明身份无效。","请拒绝伪造收据。")
	var task:Dictionary=domain.tasks[row.task_id]
	if not task is Dictionary or not domain.definitions.has(task.get("definition_id","")):return _failure("task.signal_receipt_relation_invalid","信号收据引用的Task或Definition不存在。","请拒绝断边快照。")
	var objective:Dictionary={}
	for candidate in domain.definitions[task.definition_id].objectives:
		if str(candidate.objective_id)==row.objective_id:objective=candidate;break
	if objective.is_empty() or objective.signal_kind!=row.signal_kind or objective.signal_type!=row.signal_type:return _failure("task.signal_receipt_relation_invalid","信号收据类别或类型与Objective不一致。","请拒绝跨Objective拼接。")
	for key in objective.target_match:
		if row.payload.get(key)!=objective.target_match[key]:return _failure("task.signal_receipt_match_invalid","信号收据载荷不满足Objective匹配条件。","请拒绝伪造收据。")
	var contribution := _objective_contribution(row.payload.get(objective.contribution_field))
	if not contribution.ok or int(contribution.value)!=int(row.contribution):return _failure("task.signal_receipt_contribution_invalid","信号收据贡献不能由载荷推导。","请拒绝伪造贡献。")
	var envelope:={"kind":row.signal_kind,"signal_id":row.signal_id,"type":row.signal_type,"instance_id":row.signal_instance_id,"payload":row.payload,"transaction_id":row.transaction_id,"causal_chain_id":row.causal_chain_id,"commit_proof":row.commit_proof,"fact_event_id":row.fact_event_id,"global_sequence":row.global_sequence}
	if not _valid_signal_envelope(envelope) or row.receipt_id!=_signal_receipt_id(row.task_id,row.objective_id,envelope) or row.verified_hash!=_receipt_verified_hash(row):return _failure("task.signal_receipt_proof_invalid","信号收据ID或verified hash与提交证明不一致。","请拒绝篡改收据。")
	var package:=authority_store.get_committed_package(str(row.fact_event_id)) if authority_store!=null else {}
	var authority_signal:=_signal_from_package(str(row.signal_kind),str(row.signal_type) if row.signal_kind=="cue" else str(row.signal_id),str(row.fact_event_id),package)
	if not authority_signal.ok or authority_signal.signal!=envelope:return _failure("task.signal_receipt_unanchored","信号收据不能与唯一FactEventStore权威提交包逐值互证。","请先恢复权威事实账本，再恢复Task事实域。")
	return {"ok":true}

func _validate_assignment_row(assignment_id:String,value:Variant,domain:Dictionary)->Dictionary:
	if not value is Dictionary:return _failure("task.assignment_row_invalid","Assignment行必须是Dictionary。","请拒绝损坏快照。")
	var row:Dictionary=value
	if not _require_exact(row,["schema","assignment_id","task_id","kind","assignee","state","reason_code","created_sequence"]).ok or row.schema!="gm.task.assignment.v1" or typeof(row.assignment_id)!=TYPE_STRING or row.assignment_id!=assignment_id or not _stable_id(assignment_id) or typeof(row.task_id)!=TYPE_STRING or not domain.tasks.has(row.task_id) or typeof(row.kind)!=TYPE_STRING or row.kind not in ["actor","group","role","department"] or not _typed_ref(row.assignee) or typeof(row.state)!=TYPE_STRING or row.state not in ASSIGNMENT_STATES or typeof(row.reason_code)!=TYPE_STRING or typeof(row.created_sequence)!=TYPE_INT or int(row.created_sequence)<1:return _failure("task.assignment_row_invalid","Assignment字段、Schema、类型或关系无效。","请拒绝损坏快照。")
	if row.state=="active" and not row.reason_code.is_empty() or row.state!="active" and not _stable_id(row.reason_code):return _failure("task.assignment_reason_invalid","Assignment状态与原因码不一致。","请拒绝损坏快照。")
	if row.state=="active" and domain.tasks[row.task_id].state not in ["assigned","in_progress","blocked"]:return _failure("task.assignment_lifecycle_invalid","活动Assignment只能属于已分配、执行中或阻断Task。","请拒绝生命周期矛盾快照。")
	return {"ok":true}

func _validate_provider_row(provider_id:String,value:Variant,domain:Dictionary)->Dictionary:
	if not value is Dictionary:return _failure("task.provider_row_invalid","DutyProvider行必须是Dictionary。","请拒绝损坏快照。")
	var row:Dictionary=value
	if not _require_exact(row,["schema","provider_id","definition_id","event_type","key_field","subject"]).ok or row.schema!="gm.task.duty_provider.v1" or typeof(row.provider_id)!=TYPE_STRING or row.provider_id!=provider_id or not _stable_id(provider_id) or typeof(row.definition_id)!=TYPE_STRING or not domain.definitions.has(row.definition_id) or typeof(row.event_type)!=TYPE_STRING or not _stable_id(row.event_type) or typeof(row.key_field)!=TYPE_STRING or not _stable_id(row.key_field) or not _typed_ref(row.subject):return _failure("task.provider_row_invalid","DutyProvider字段、Schema、类型或关系无效。","请拒绝损坏快照。")
	return {"ok":true}

func _validate_reservation_row(reservation_id:String,value:Variant,domain:Dictionary)->Dictionary:
	if not value is Dictionary:return _failure("task.reservation_row_invalid","Reservation行必须是Dictionary。","请拒绝损坏快照。")
	var row:Dictionary=value;var fields:=["schema","reservation_id","task_id","assignment_id","owner","subject","rule_id","mode","amount","capacity","expires_at_tick","state","consume_receipts","reason_code"]
	if not _require_exact(row,fields).ok or row.schema!="gm.task.reservation.v1" or typeof(row.reservation_id)!=TYPE_STRING or row.reservation_id!=reservation_id or not _stable_id(reservation_id) or typeof(row.task_id)!=TYPE_STRING or not domain.tasks.has(row.task_id) or typeof(row.assignment_id)!=TYPE_STRING or not domain.assignments.has(row.assignment_id) or not _typed_ref(row.owner) or not _typed_ref(row.subject) or typeof(row.rule_id)!=TYPE_STRING or not _stable_id(row.rule_id) or typeof(row.mode)!=TYPE_STRING or row.mode not in ["exclusive","capacity"] or typeof(row.amount)!=TYPE_INT or int(row.amount)<=0 or typeof(row.capacity)!=TYPE_INT or int(row.capacity)<=0 or typeof(row.expires_at_tick)!=TYPE_INT or int(row.expires_at_tick)<-1 or typeof(row.state)!=TYPE_STRING or row.state not in RESERVATION_STATES or not row.consume_receipts is Array or typeof(row.reason_code)!=TYPE_STRING or not _unique_stable_strings(row.consume_receipts,true):return _failure("task.reservation_row_invalid","Reservation字段、Schema或Variant类型无效。","请拒绝损坏快照。")
	var assignment:Dictionary=domain.assignments[row.assignment_id]
	if assignment.task_id!=row.task_id or assignment.assignee!=row.owner:return _failure("task.reservation_relation_invalid","Reservation owner/task/assignment关系不一致。","请拒绝损坏快照。")
	var authority:=_reservation_rule(domain,row.task_id,row.rule_id,row.subject);if not authority.ok:return authority
	if authority.rule.mode!=row.mode or int(authority.rule.capacity)!=int(row.capacity) or row.mode=="exclusive" and int(row.amount)!=1:return _failure("task.reservation_rule_mismatch","Reservation行与权威规则不一致。","请拒绝自报模式或容量。")
	if row.state=="active" and (assignment.state!="active" or domain.tasks[row.task_id].assignment_id!=row.assignment_id or domain.tasks[row.task_id].state not in ["assigned","in_progress","blocked"] or not row.reason_code.is_empty()) or row.state!="active" and not _stable_id(row.reason_code):return _failure("task.reservation_state_invalid","Reservation状态、所有权、Task生命周期或原因码不一致。","请拒绝旧owner或损坏终态。")
	if row.state=="consumed" and row.consume_receipts.size()!=1 or row.state!="consumed" and not row.consume_receipts.is_empty():return _failure("task.reservation_receipt_invalid","Reservation消费收据与状态不一致。","请拒绝重复消费。")
	return {"ok":true}

func _unique_stable_strings(value:Variant,allow_empty_array:bool)->bool:
	if not value is Array:return false
	if not allow_empty_array and value.is_empty():return false
	var seen:Dictionary={}
	for item in value:
		if typeof(item)!=TYPE_STRING or not _stable_id(item) or seen.has(item):return false
		seen[item]=true
	return true

func _parent_cycle(domain:Dictionary,start:String)->bool:
	var seen:Dictionary={};var current:=start
	while not current.is_empty():
		if seen.has(current):return true
		seen[current]=true
		if not domain.tasks.has(current):return false
		current=str(domain.tasks[current].get("parent_task_id",""))
	return false

func _validated_snapshot(value:Dictionary)->Dictionary:
	if value.size()!=3 or value.get("snapshot_schema")!=SNAPSHOT_SCHEMA or not value.get("authority_store") is Dictionary or not value.get("store") is Dictionary:return _failure("task.snapshot_shape_invalid","Task快照必须同时包含唯一权威FactEventStore与Task Store。","请使用完整当前版本快照。")
	var temp_authority:=GMFactEventStore.new();var authority_restored:=temp_authority.restore_snapshot(value.authority_store);if not authority_restored.ok:return authority_restored
	var temp:=GMStore.new(STORE_ID,STORE_SCHEMA);var restored:=temp.restore_snapshot(value.store);if not restored.ok:return restored
	var domain:=temp.read("domain") if temp.has("domain") else _empty_domain();var checked:=_validate_domain(domain,temp_authority);if not checked.ok:return checked
	return {"ok":true,"authority_snapshot":value.authority_store.duplicate(true),"store_snapshot":value.store.duplicate(true)}

func _normalize_json_snapshot(value:Dictionary)->Dictionary:
	var canonical: Variant = GMStableData.persistence_canonical(value)
	var copy: Dictionary = canonical if canonical is Dictionary else {}
	if not copy.get("authority_store") is Dictionary or not copy.get("store") is Dictionary:return _failure("task.snapshot_shape_invalid","Task JSON快照缺少权威FactEventStore或Task Store。","请使用完整快照。")
	var authority_value:Dictionary=copy.authority_store
	for field in ["next_sequence","fact_count","change_count"]:
		var authority_integer:=_json_int(authority_value.get(field),"authority_store.%s"%field);if not authority_integer.ok:return authority_integer;authority_value[field]=authority_integer.value
	if authority_value.get("facts",[]) is Array:
		for index in authority_value.facts.size():
			if not authority_value.facts[index] is Dictionary:continue
			var fact:Dictionary=authority_value.facts[index]
			for field in ["sequence","timestamp_usec"]:
				var fact_integer:=_json_int(fact.get(field),"authority_store.fact.%s"%field);if not fact_integer.ok:return fact_integer;fact[field]=fact_integer.value
			authority_value.facts[index]=fact
	if authority_value.get("changes",[]) is Array:
		for index in authority_value.changes.size():
			if not authority_value.changes[index] is Dictionary:continue
			var change:Dictionary=authority_value.changes[index];var change_integer:=_json_int(change.get("sequence"),"authority_store.change.sequence");if not change_integer.ok:return change_integer;change.sequence=change_integer.value;authority_value.changes[index]=change
	if authority_value.get("commit_packages",{}) is Dictionary:
		for event_id in authority_value.commit_packages:
			if not authority_value.commit_packages[event_id] is Dictionary:continue
			var package:Dictionary=authority_value.commit_packages[event_id];var package_integer:=_json_int(package.get("global_sequence"),"authority_store.package.global_sequence");if not package_integer.ok:return package_integer;package.global_sequence=package_integer.value
			if package.get("fact",{}) is Dictionary:
				var package_fact:Dictionary=package.fact
				for field in ["sequence","timestamp_usec"]:
					var package_fact_integer:=_json_int(package_fact.get(field),"authority_store.package.fact.%s"%field);if not package_fact_integer.ok:return package_fact_integer;package_fact[field]=package_fact_integer.value
				package.fact=package_fact
			if package.get("changes",[]) is Array:
				for change_index in package.changes.size():
					if not package.changes[change_index] is Dictionary:continue
					var package_change:Dictionary=package.changes[change_index];var package_change_integer:=_json_int(package_change.get("sequence"),"authority_store.package.change.sequence");if not package_change_integer.ok:return package_change_integer;package_change.sequence=package_change_integer.value;package.changes[change_index]=package_change
			authority_value.commit_packages[event_id]=package
	copy.authority_store=authority_value
	var store_value: Dictionary = copy["store"]
	for field in ["version","persistence_revision"]:
		var integer:=_json_int(store_value.get(field),"store.%s"%field);if not integer.ok:return integer;store_value[field]=integer.value
	var task_records_value:Variant=store_value.get("records",{})
	if task_records_value is Dictionary and task_records_value.has("domain") and task_records_value.get("domain") is Dictionary:
		var records: Dictionary = task_records_value
		var domain:Dictionary=records.domain
		for field in ["logical_tick","next_sequence"]:
			var integer:=_json_int(domain.get(field),"domain.%s"%field);if not integer.ok:return integer;domain[field]=integer.value
		var definitions:Variant=domain.get("definitions",{})
		if not definitions is Dictionary:return _failure("task.snapshot_collection_type_invalid","definitions集合类型无效。","请拒绝错误Variant快照。")
		if definitions is Dictionary:
			for definition_id in definitions:
				var definition:Variant=definitions[definition_id]
				if not definition is Dictionary:continue
				var objectives:Variant=definition.get("objectives",[])
				if objectives is Array:
					for index in objectives.size():
						if not objectives[index] is Dictionary:continue
						var objective:Dictionary=objectives[index];var target:=_json_int(objective.get("target_value"),"definition.objective.target_value");if not target.ok:return target;objective.target_value=target.value;objectives[index]=objective
					definition.objectives=objectives
				var rules:Variant=definition.get("reservation_rules",[])
				if rules is Array:
					for index in rules.size():
						if not rules[index] is Dictionary:continue
						var rule:Dictionary=rules[index];var capacity:=_json_int(rule.get("capacity"),"definition.reservation.capacity");if not capacity.ok:return capacity;rule.capacity=capacity.value;rules[index]=rule
					definition.reservation_rules=rules
				var profile:Variant=definition.get("workbench_profile",{})
				if profile is Dictionary and profile.get("reservation",{}) is Dictionary:
					var reservation:Dictionary=profile.reservation
					for field in ["amount","expires_at_tick"]:
						var n:=_json_int(reservation.get(field),"definition.workbench.%s"%field);if not n.ok:return n;reservation[field]=n.value
					profile.reservation=reservation;definition.workbench_profile=profile
				definitions[definition_id]=definition
			domain.definitions=definitions
		var tasks: Variant = domain.get("tasks",{})
		if not tasks is Dictionary:return _failure("task.snapshot_collection_type_invalid","tasks集合类型无效。","请拒绝错误Variant快照。")
		for task_id in tasks:
			var task: Variant = tasks[task_id]
			if task is Dictionary:
				var seq:=_json_int(task.get("created_sequence"),"task.created_sequence");if not seq.ok:return seq;task.created_sequence=seq.value
				var objectives: Dictionary = task.get("objectives",{})
				for objective_id in objectives:
					var progress: Dictionary = objectives[objective_id]
					for field in ["current","target","last_signal_sequence"]:
						var n:=_json_int(progress.get(field),"objective.%s"%field);if not n.ok:return n;progress[field]=n.value
					objectives[objective_id] = progress
				task["objectives"] = objectives
				tasks[task_id] = task
		domain["tasks"] = tasks
		var signal_receipts:Variant=domain.get("signal_receipts",{})
		if not signal_receipts is Dictionary:return _failure("task.snapshot_collection_type_invalid","signal_receipts集合类型无效。","请拒绝错误Variant快照。")
		for receipt_id in signal_receipts:
			if not signal_receipts[receipt_id] is Dictionary:continue
			var receipt:Dictionary=signal_receipts[receipt_id]
			for field in ["global_sequence","contribution"]:
				var n:=_json_int(receipt.get(field),"signal_receipt.%s"%field);if not n.ok:return n;receipt[field]=n.value
			signal_receipts[receipt_id]=receipt
		domain["signal_receipts"]=signal_receipts
		var assignments: Variant = domain.get("assignments",{})
		if not assignments is Dictionary:return _failure("task.snapshot_collection_type_invalid","assignments集合类型无效。","请拒绝错误Variant快照。")
		for assignment_id in assignments:
			if not assignments[assignment_id] is Dictionary:continue
			var assignment: Dictionary = assignments[assignment_id]
			var seq:=_json_int(assignment.get("created_sequence"),"assignment.created_sequence");if not seq.ok:return seq;assignment.created_sequence=seq.value
			assignments[assignment_id] = assignment
		domain["assignments"] = assignments
		var reservations: Variant = domain.get("reservations",{})
		if not reservations is Dictionary:return _failure("task.snapshot_collection_type_invalid","reservations集合类型无效。","请拒绝错误Variant快照。")
		for reservation_id in reservations:
			if not reservations[reservation_id] is Dictionary:continue
			var reservation: Dictionary = reservations[reservation_id]
			for field in ["amount","capacity","expires_at_tick"]:
				var n:=_json_int(reservation.get(field),"reservation.%s"%field);if not n.ok:return n;reservation[field]=n.value
			reservations[reservation_id] = reservation
		domain["reservations"] = reservations
		records["domain"] = domain
		store_value["records"] = records
	copy["store"] = store_value
	return {"ok":true,"snapshot":copy}

func _json_int(value:Variant,field:String)->Dictionary:
	if typeof(value)==TYPE_INT:return {"ok":true,"value":int(value)}
	if typeof(value)!=TYPE_FLOAT:return _failure("task.snapshot_integer_type_invalid","快照整数%s类型无效。"%field,"请拒绝拼接快照。")
	var number:=float(value);if not is_finite(number) or number!=floor(number) or number<=-JSON_SAFE_BOUND or number>=JSON_SAFE_BOUND:return _failure("task.snapshot_integer_invalid","快照整数%s超出JSON安全范围或含小数。"%field,"请使用安全整数。")
	return {"ok":true,"value":int(number)}

func _domain()->Dictionary:
	return store.read("domain") if store.has("domain") else _empty_domain()

func _empty_domain()->Dictionary:
	return {"schema":STORE_SCHEMA,"logical_tick":0,"next_sequence":1,"definitions":{},"groups":{},"tasks":{},"assignments":{},"providers":{},"reservations":{},"signal_receipts":{},"provider_receipts":{}}

func _applied(domain:Dictionary,result:Dictionary,targets:Array=[],duplicate:bool=false)->Dictionary:
	return {"ok":true,"after":domain,"result":result,"targets":targets,"duplicate":duplicate}

func _require(value:Dictionary,fields:Array)->Dictionary:
	for field in fields:
		if not value.has(field):return _failure("task.payload_truncated","Task操作载荷缺少字段“%s”。"%field,"请提交完整字段。")
	return {"ok":true}

func _require_exact(value:Dictionary,fields:Array)->Dictionary:
	var required:=_require(value,fields);if not required.ok:return required
	if value.size()!=fields.size():return _failure("task.snapshot_extra_fields","Task快照包含未知字段。","请使用当前Schema重新导出。")
	return {"ok":true}

func _typed_ref(value:Variant)->bool:
	return value is Dictionary and value.size()==2 and typeof(value.get("type"))==TYPE_STRING and typeof(value.get("id"))==TYPE_STRING and _stable_id(str(value.type)) and _stable_id(str(value.id)) and not str(value.type).contains("node")

func _command_target_id(payload: Dictionary) -> String:
	for field in ["task_id","reservation_id","assignment_id","provider_id","definition_id","event_id","signal_id"]:
		var candidate := str(payload.get(field,""))
		if _stable_id(candidate): return candidate
	return STORE_ID

func _stable_id(value:String)->bool:
	return GMTaskDefinition._stable_id(value)

func _failure(code:String,reason_zh:String,fix_zh:String,details:Dictionary={})->Dictionary:
	return {"ok":false,"code":code,"reason_zh":reason_zh,"error_zh":reason_zh,"fix_zh":fix_zh,"details":details}
