class_name GMFactEventStore
extends RefCounted

## 05A 的最小只追加事实账本。
const SNAPSHOT_SCHEMA := "gm.fact_event_store.snapshot.v2"
const COMMIT_PACKAGE_SCHEMA := "gm.fact.commit_package.v1"

var records: Array[GMFactEvent] = []
var by_id: Dictionary = {}
var by_idempotency: Dictionary = {}
var committed_packages: Dictionary = {}
var change_store: GMChangeRecordStore
var fail_next_append: bool = false
var _next_sequence: int = 1

func _init(p_change_store: GMChangeRecordStore = null) -> void:
	change_store = p_change_store if p_change_store != null else GMChangeRecordStore.new()

func append_fact(fact: GMFactEvent) -> Dictionary:
	return append_committed(fact, [])

func append_record_once(value: Variant) -> Dictionary:
	if value is GMCandidateResult or value is GMBlockedResult:
		return {"ok": false, "code": "fact.result_not_fact", "reason_zh": "Candidate/BlockedResult 不得摄入 FactEvent 账本。", "appended": false}
	if value is GMCommittedFactResult:
		var committed: GMCommittedFactResult = value
		return append_committed(committed.fact_event, committed.change_records)
	if not value is GMFactEvent:
		return {"ok": false, "code": "fact.type_invalid", "reason_zh": "事实账本只接受 GMFactEvent 或已提交结果。", "appended": false}
	return append_committed(value, [])

func append_result(value: Variant) -> Dictionary:
	if value is GMCommittedFactResult:
		var committed: GMCommittedFactResult = value
		return append_committed(committed.fact_event, committed.change_records)
	return append_record_once(value)

func append_committed(fact: GMFactEvent, supplied_changes: Array, authority_context: Dictionary = {}) -> Dictionary:
	if fact == null:
		return {"ok": false, "code": "fact.missing", "reason_zh": "不能写入空 FactEvent。", "appended": false}
	var validation := fact.validate()
	if not validation.ok: return {"ok": false, "code": "fact.invalid", "reason_zh": "FactEvent Schema 校验失败。", "errors": validation.errors, "appended": false}
	if not fact.has_commit_proof() or fact.commit_proof != fact.transaction_id:
		return {"ok": false, "code": "fact.commit_proof_missing", "reason_zh": "结构合法的 FactEvent 不能绕过 DomainResolver 直接写入事实账本。", "appended": false, "fix": {"action": "只能使用 Resolver 成功提交后的 GMCommittedFactResult。"}}
	var existing_by_key: GMFactEvent = by_idempotency.get(fact.idempotency_key, null)
	if existing_by_key != null:
		if existing_by_key.to_dict() == fact.to_dict():
			return {"ok": true, "appended": false, "duplicate_skipped": true, "fact": existing_by_key.to_dict(), "fact_event_id": existing_by_key.event_id, "record_count": records.size()}
		return {"ok": false, "code": "fact.idempotency_conflict", "reason_zh": "幂等键已经对应不同 FactEvent。", "idempotency_key": fact.idempotency_key, "appended": false}
	var existing_by_id: GMFactEvent = by_id.get(fact.event_id, null)
	if existing_by_id != null:
		if existing_by_id.to_dict() == fact.to_dict():
			return {"ok": true, "appended": false, "duplicate_skipped": true, "fact": existing_by_id.to_dict(), "fact_event_id": existing_by_id.event_id, "record_count": records.size()}
		return {"ok": false, "code": "fact.id_conflict", "reason_zh": "FactEvent ID 已存在但内容不同。", "event_id": fact.event_id, "appended": false}
	if fail_next_append:
		fail_next_append = false
		return {"ok": false, "code": "fact.append_injected_failure", "reason_zh": "FactEvent 写入器故障注入，事务批次未写入。", "appended": false}
	var changes := _normalize_changes(supplied_changes, fact)
	if changes.is_empty():
		var generated := GMChangeRecord.new()
		generated.configure(_next_sequence, fact.event_id, fact.transaction_id, fact.idempotency_key, fact.actor, "transaction.commit", "fact", null, fact.outputs.duplicate(true), {"causal_chain_id": fact.causal_chain_id})
		changes.append(generated)
	var change_validation := change_store.validate_batch(changes)
	if not change_validation.ok: return {"ok": false, "code": "fact.change_batch_invalid", "reason_zh": "FactEvent 对应 ChangeRecord 批次无效。", "errors": change_validation.errors, "appended": false}
	var fact_copy := GMFactEvent.from_dict(fact.to_dict())
	fact_copy.commit_proof = fact.commit_proof
	fact_copy._commit_authority = fact._commit_authority
	fact_copy.sequence = _next_sequence
	if fact_copy.event_id.is_empty(): fact_copy.event_id = GMFactEvent.make_event_id(_next_sequence, fact_copy.type, fact_copy.idempotency_key)
	for index in range(changes.size()):
		var record: GMChangeRecord = changes[index]
		if record.fact_event_id != fact_copy.event_id:
			return {"ok": false, "code": "fact.change_fact_mismatch", "reason_zh": "ChangeRecord 未指向同一 FactEvent。", "change_id": record.change_id, "appended": false}
		if record.sequence < 1: record.sequence = _next_sequence + index
		if record.causal_chain_id.is_empty(): record.causal_chain_id = fact_copy.causal_chain_id
		if record.change_id.is_empty(): record.change_id = GMChangeRecord.make_change_id(fact_copy.event_id, fact_copy.idempotency_key, index + 1)
	var store_preview := change_store.validate_batch(changes)
	if not store_preview.ok: return {"ok": false, "code": "fact.change_batch_invalid", "reason_zh": "ChangeRecord 批次最终校验失败。", "errors": store_preview.errors, "appended": false}
	var commit_package:Dictionary={}
	if not authority_context.is_empty():
		commit_package=_build_commit_package(fact_copy,changes,authority_context)
		var package_validation:=_validate_commit_package(commit_package)
		if not package_validation.ok:return {"ok":false,"code":"fact.commit_package_invalid","reason_zh":"权威提交包字段、因果链或Cue集合无效。","details":package_validation,"appended":false}
	var append_changes := change_store.append_batch_once(changes)
	if not append_changes.ok:
		return {"ok": false, "code": "fact.change_append_failed", "reason_zh": "ChangeRecord 写入失败，FactEvent 保持未写入。", "errors": [append_changes], "appended": false}
	records.append(fact_copy)
	by_id[fact_copy.event_id] = fact_copy
	by_idempotency[fact_copy.idempotency_key] = fact_copy
	if not commit_package.is_empty():committed_packages[fact_copy.event_id]=commit_package.duplicate(true)
	_next_sequence += 1
	return {"ok": true, "appended": true, "duplicate_skipped": false, "fact": fact_copy.to_dict(), "changes": append_changes, "fact_event_id": fact_copy.event_id, "record_count": records.size()}

func can_append_fact(fact: GMFactEvent, supplied_changes: Array = []) -> Dictionary:
	if fact == null: return {"ok": false, "code": "fact.missing", "reason_zh": "不能预检空 FactEvent。"}
	var validation := fact.validate()
	if not validation.ok: return {"ok": false, "code": "fact.invalid", "reason_zh": "FactEvent Schema 校验失败。", "errors": validation.errors}
	if not fact.has_commit_proof() or fact.commit_proof != fact.transaction_id: return {"ok": false, "code": "fact.commit_proof_missing", "reason_zh": "结构合法的 FactEvent 不能绕过 DomainResolver 直接写入事实账本。"}
	if by_idempotency.has(fact.idempotency_key): return {"ok": true, "duplicate": true}
	var changes := _normalize_changes(supplied_changes, fact)
	if changes.is_empty(): changes.append(GMChangeRecord.new().configure(1, fact.event_id, fact.transaction_id, fact.idempotency_key, fact.actor, "transaction.commit", "fact", null, fact.outputs, {"causal_chain_id": fact.causal_chain_id}))
	return change_store.validate_batch(changes)

func contains_id(event_id: String) -> bool:
	return by_id.has(event_id)

func contains_idempotency(key: String) -> bool:
	return by_idempotency.has(key)

func get_by_id(event_id: String) -> GMFactEvent:
	return _copy_fact(by_id.get(event_id, null))

func get_by_idempotency(key: String) -> GMFactEvent:
	return _copy_fact(by_idempotency.get(key, null))

func get_change_records_for_fact(event_id: String) -> Array:
	var result: Array = []
	for record in change_store.records:
		if record.fact_event_id == event_id: result.append(GMChangeRecord.from_dict(record.to_dict()))
	return result

func get_committed_package(event_id:String)->Dictionary:
	var value:Variant=committed_packages.get(event_id,{})
	if not value is Dictionary or not _validate_commit_package(value).ok:return {}
	return value.duplicate(true)

func find_committed_package_for_change(change_id:String)->Dictionary:
	for package in committed_packages.values():
		for record in package.get("changes",[]):
			if record is Dictionary and str(record.get("change_id",""))==change_id:return package.duplicate(true)
	return {}

func make_committed_result(event_id:String,idempotent:bool=false)->GMCommittedFactResult:
	var package:=get_committed_package(event_id)
	if package.is_empty():return null
	var fact:=GMFactEvent.from_dict(package.fact);fact.mark_committed(package.commit_proof,GMFactEvent._get_commit_capability())
	var changes:Array=[]
	for value in package.changes:changes.append(GMChangeRecord.from_dict(value))
	var chain:=GMCausalChain.from_dict(package.chain)
	if chain==null:return null
	var result:=GMCommittedFactResult.new(fact,changes,chain,package.transaction_id,idempotent);result.cues=package.cues.duplicate(true);result.authority_store=self
	return result

func get_records() -> Array:
	var result: Array = []
	for fact in records: result.append(fact.to_dict())
	return result

func get_record_count() -> int:
	return records.size()

func get_change_record_count() -> int:
	return change_store.get_record_count()

func snapshot() -> Dictionary:
	return {"schema":SNAPSHOT_SCHEMA,"next_sequence":_next_sequence,"fact_count":records.size(),"change_count":change_store.get_record_count(),"facts":get_records(),"changes":change_store.get_records(),"commit_packages":committed_packages.duplicate(true)}

func restore_snapshot(value:Dictionary)->Dictionary:
	var validated:=_validated_snapshot(value)
	if not validated.ok:return validated
	var new_change_store:=GMChangeRecordStore.new();var appended:=new_change_store.append_batch_once(validated.changes);if not appended.ok:return appended
	records=validated.facts;by_id={};by_idempotency={}
	for fact in records:by_id[fact.event_id]=fact;by_idempotency[fact.idempotency_key]=fact
	change_store=new_change_store;committed_packages=validated.packages;_next_sequence=validated.next_sequence
	return {"ok":true,"code":"fact.snapshot_restored","fact_count":records.size(),"change_count":change_store.get_record_count(),"package_count":committed_packages.size()}

func _validated_snapshot(value:Dictionary)->Dictionary:
	var fields:=["schema","next_sequence","fact_count","change_count","facts","changes","commit_packages"]
	if value.size()!=fields.size():return _snapshot_failure("fact.snapshot_shape_invalid","权威FactEventStore快照字段集合无效。")
	for field in fields:
		if not value.has(field):return _snapshot_failure("fact.snapshot_shape_invalid","权威FactEventStore快照缺少字段。")
	if value.schema!=SNAPSHOT_SCHEMA or typeof(value.next_sequence)!=TYPE_INT or int(value.next_sequence)<1 or typeof(value.fact_count)!=TYPE_INT or typeof(value.change_count)!=TYPE_INT or not value.facts is Array or not value.changes is Array or not value.commit_packages is Dictionary:return _snapshot_failure("fact.snapshot_header_invalid","权威FactEventStore快照Schema或类型无效。")
	if int(value.fact_count)!=value.facts.size() or int(value.change_count)!=value.changes.size():return _snapshot_failure("fact.snapshot_count_invalid","权威Fact/Change计数不一致。")
	var facts:Array[GMFactEvent]=[];var fact_ids:Dictionary={};var keys:Dictionary={};var max_sequence:=0
	for fact_value in value.facts:
		if not fact_value is Dictionary:return _snapshot_failure("fact.snapshot_fact_invalid","Fact行必须是Dictionary。")
		var fact:=GMFactEvent.from_dict(fact_value)
		if fact.to_dict()!=fact_value or not fact.validate().ok or fact_ids.has(fact.event_id) or keys.has(fact.idempotency_key):return _snapshot_failure("fact.snapshot_fact_invalid","Fact行字段、类型或稳定身份无效。")
		fact.mark_committed(fact.transaction_id,GMFactEvent._get_commit_capability());facts.append(fact);fact_ids[fact.event_id]=fact;keys[fact.idempotency_key]=true;max_sequence=maxi(max_sequence,fact.sequence)
	if int(value.next_sequence)<=max_sequence:return _snapshot_failure("fact.snapshot_sequence_invalid","next_sequence必须大于全部Fact全局序号。")
	var changes:Array[GMChangeRecord]=[];var change_ids:Dictionary={};var change_keys:Dictionary={}
	for change_value in value.changes:
		if not change_value is Dictionary:return _snapshot_failure("fact.snapshot_change_invalid","Change行必须是Dictionary。")
		var record:=GMChangeRecord.from_dict(change_value)
		if record.to_dict()!=change_value or not record.validate().ok or change_ids.has(record.change_id) or change_keys.has(record.idempotency_key) or not fact_ids.has(record.fact_event_id):return _snapshot_failure("fact.snapshot_change_invalid","Change行字段、类型、稳定身份或Fact关系无效。")
		var owner:GMFactEvent=fact_ids[record.fact_event_id]
		if record.transaction_id!=owner.transaction_id or record.causal_chain_id!=owner.causal_chain_id:return _snapshot_failure("fact.snapshot_change_relation_invalid","Change与所属Fact事务或因果链不一致。")
		changes.append(record);change_ids[record.change_id]=record;change_keys[record.idempotency_key]=true
	var packages:Dictionary={}
	for event_id in value.commit_packages:
		var package:Variant=value.commit_packages[event_id]
		if typeof(event_id)!=TYPE_STRING or not package is Dictionary or str(package.get("fact_event_id",""))!=str(event_id):return _snapshot_failure("fact.snapshot_package_invalid","权威提交包键或行无效。")
		var checked:=_validate_commit_package(package)
		if not checked.ok or not fact_ids.has(event_id) or package.fact!=fact_ids[event_id].to_dict():return _snapshot_failure("fact.snapshot_package_invalid","权威提交包不能与Fact账本逐值互证。")
		var authoritative_change_rows:Array=[]
		for record in changes:
			if record.fact_event_id==event_id:authoritative_change_rows.append(record.to_dict())
		if package.changes!=authoritative_change_rows:return _snapshot_failure("fact.snapshot_package_change_order_invalid","权威提交包Change必须逐项等于唯一ChangeStore中的产生顺序。")
		packages[event_id]=package.duplicate(true)
	return {"ok":true,"facts":facts,"changes":changes,"packages":packages,"next_sequence":int(value.next_sequence)}

func _build_commit_package(fact:GMFactEvent,changes:Array,context:Dictionary)->Dictionary:
	var row:={"schema":COMMIT_PACKAGE_SCHEMA,"fact_event_id":fact.event_id,"transaction_id":fact.transaction_id,"causal_chain_id":fact.causal_chain_id,"commit_proof":fact.commit_proof,"global_sequence":fact.sequence,"fact":fact.to_dict(),"changes":changes.map(func(record:GMChangeRecord):return record.to_dict()),"cues":context.get("cues",[]).duplicate(true) if context.get("cues",[]) is Array else [],"chain":context.get("chain",{}).duplicate(true) if context.get("chain",{}) is Dictionary else {},"verified_hash":""}
	row.verified_hash=_package_hash(row)
	return row

func _validate_commit_package(value:Dictionary)->Dictionary:
	var fields:=["schema","fact_event_id","transaction_id","causal_chain_id","commit_proof","global_sequence","fact","changes","cues","chain","verified_hash"]
	if value.size()!=fields.size():return _snapshot_failure("fact.commit_package_shape_invalid","权威提交包字段集合无效。")
	for field in fields:
		if not value.has(field):return _snapshot_failure("fact.commit_package_shape_invalid","权威提交包缺少字段。")
	if value.schema!=COMMIT_PACKAGE_SCHEMA or typeof(value.fact_event_id)!=TYPE_STRING or typeof(value.transaction_id)!=TYPE_STRING or typeof(value.causal_chain_id)!=TYPE_STRING or typeof(value.commit_proof)!=TYPE_STRING or value.commit_proof!=value.transaction_id or typeof(value.global_sequence)!=TYPE_INT or int(value.global_sequence)<1 or not value.fact is Dictionary or not value.changes is Array or not value.cues is Array or not value.chain is Dictionary or typeof(value.verified_hash)!=TYPE_STRING:return _snapshot_failure("fact.commit_package_type_invalid","权威提交包Schema、类型或提交证明无效。")
	var fact:=GMFactEvent.from_dict(value.fact)
	if fact.to_dict()!=value.fact or not fact.validate().ok or fact.event_id!=value.fact_event_id or fact.transaction_id!=value.transaction_id or fact.causal_chain_id!=value.causal_chain_id or fact.sequence!=value.global_sequence:return _snapshot_failure("fact.commit_package_fact_invalid","权威提交包Fact身份、事务、因果链或全局序号不一致。")
	var chain:=GMCausalChain.from_dict(value.chain)
	if chain==null or chain.chain_id!=value.causal_chain_id:return _snapshot_failure("fact.commit_package_chain_invalid","权威提交包因果链无效。")
	var transaction_ref:=chain.get_ref(value.transaction_id);var fact_ref:=chain.get_ref(value.fact_event_id)
	if transaction_ref==null or transaction_ref.kind!="domain_transaction" or fact_ref==null or fact_ref.kind!="fact_event" or not chain.has_direct_link(value.transaction_id,value.fact_event_id):return _snapshot_failure("fact.commit_package_link_invalid","权威提交包缺少Transaction到Fact直连。")
	var seen_changes:Dictionary={}
	var ordered_change_ids:=_ordered_direct_child_ids(chain,str(value.fact_event_id),"change_record")
	if ordered_change_ids.size()!=value.changes.size():return _snapshot_failure("fact.commit_package_change_order_invalid","权威提交包Change数量或因果链顺序无效。")
	var change_index:=0
	for record_value in value.changes:
		if not record_value is Dictionary:return _snapshot_failure("fact.commit_package_change_invalid","权威提交包Change行类型无效。")
		var record:=GMChangeRecord.from_dict(record_value);var ref:=chain.get_ref(record.change_id)
		if record.to_dict()!=record_value or not record.validate().ok or seen_changes.has(record.change_id) or record.fact_event_id!=value.fact_event_id or record.transaction_id!=value.transaction_id or record.causal_chain_id!=value.causal_chain_id or ref==null or ref.kind!="change_record" or not chain.has_direct_link(value.fact_event_id,record.change_id):return _snapshot_failure("fact.commit_package_change_invalid","权威提交包Change集合或链接无效。")
		if str(ordered_change_ids[change_index])!=record.change_id:return _snapshot_failure("fact.commit_package_change_order_invalid","权威提交包Change顺序必须逐项等于Coordinator因果链接顺序。")
		seen_changes[record.change_id]=true;change_index+=1
	var chain_change_refs:=chain.refs_of_kind("change_record")
	if chain_change_refs.size()!=seen_changes.size():return _snapshot_failure("fact.commit_package_change_invalid","权威提交包Change集合与因果链集合不一致。")
	for ref in chain_change_refs:
		if not seen_changes.has(str(ref.get("ref_id",""))):return _snapshot_failure("fact.commit_package_change_invalid","权威提交包缺少因果链中的Change。")
	var seen_cues:Dictionary={}
	var ordered_cue_ids:=_ordered_direct_child_ids(chain,str(value.fact_event_id),"cue")
	if ordered_cue_ids.size()!=value.cues.size():return _snapshot_failure("fact.commit_package_cue_order_invalid","权威提交包Cue数量或因果链顺序无效。")
	var cue_index:=0
	for cue_value in value.cues:
		if not cue_value is Dictionary or cue_value.size()!=3 or not cue_value.has("cue_id") or not cue_value.has("instance_id") or not cue_value.has("parameters") or typeof(cue_value.cue_id)!=TYPE_STRING or typeof(cue_value.instance_id)!=TYPE_STRING or not cue_value.parameters is Dictionary or seen_cues.has(cue_value.cue_id):return _snapshot_failure("fact.commit_package_cue_invalid","权威提交包Cue集合字段或身份无效。")
		var cue_ref:=chain.get_ref(cue_value.cue_id)
		if cue_ref==null or cue_ref.kind!="cue" or not chain.has_direct_link(value.fact_event_id,cue_value.cue_id) or cue_ref.metadata.get("instance_id")!=cue_value.instance_id or cue_ref.metadata.get("payload_hash")!=JSON.stringify(GMStableData.persistence_canonical(cue_value.parameters),"",true,true).sha256_text():return _snapshot_failure("fact.commit_package_cue_invalid","权威提交包Cue instance、payload或Fact链接无效。")
		if str(ordered_cue_ids[cue_index])!=str(cue_value.cue_id):return _snapshot_failure("fact.commit_package_cue_order_invalid","权威提交包Cue顺序必须逐项等于Coordinator因果链接顺序。")
		seen_cues[cue_value.cue_id]=true;cue_index+=1
	var chain_cue_refs:=chain.refs_of_kind("cue")
	if chain_cue_refs.size()!=seen_cues.size():return _snapshot_failure("fact.commit_package_cue_invalid","权威提交包Cue集合与因果链集合不一致。")
	for ref in chain_cue_refs:
		if not seen_cues.has(str(ref.get("ref_id",""))):return _snapshot_failure("fact.commit_package_cue_invalid","权威提交包缺少因果链中的Cue。")
	if value.verified_hash!=_package_hash(value):return _snapshot_failure("fact.commit_package_hash_invalid","权威提交包verified hash不一致。")
	return {"ok":true}

func _package_hash(value:Dictionary)->String:
	var copy:=value.duplicate(true);copy.erase("verified_hash");return JSON.stringify(GMStableData.persistence_canonical(copy),"",true,true).sha256_text()

func _ordered_direct_child_ids(chain:GMCausalChain,fact_event_id:String,kind:String)->Array:
	var result:Array=[]
	for link in chain.links:
		if str(link.get("parent_id",""))!=fact_event_id or str(link.get("relation","causes"))!="causes":continue
		var ref:=chain.get_ref(str(link.get("child_id","")))
		if ref!=null and ref.kind==kind:result.append(ref.ref_id)
	return result

func _copy_fact(value:Variant)->GMFactEvent:
	if not value is GMFactEvent:return null
	var copy:=GMFactEvent.from_dict(value.to_dict());copy.mark_committed(value.transaction_id,GMFactEvent._get_commit_capability());return copy

func _snapshot_failure(code:String,reason_zh:String)->Dictionary:
	return {"ok":false,"code":code,"reason_zh":reason_zh}

func _normalize_changes(values: Array, fact: GMFactEvent) -> Array[GMChangeRecord]:
	var result: Array[GMChangeRecord] = []
	var index := 1
	for value in values:
		if value is GMChangeRecord:
			var record: GMChangeRecord = value
			if record.fact_event_id.is_empty(): record.fact_event_id = fact.event_id
			if record.transaction_id.is_empty(): record.transaction_id = fact.transaction_id
			if record.idempotency_key.is_empty(): record.idempotency_key = "%s.change.%d" % [fact.idempotency_key, index]
			if record.entity_id.is_empty(): record.entity_id = fact.actor
			if record.operation.is_empty(): record.operation = "transaction.commit"
			if record.field.is_empty(): record.field = "state"
			if record.time.is_empty(): record.time = fact.time
			if record.sequence < 1: record.sequence = index
			if record.change_id.is_empty(): record.change_id = GMChangeRecord.make_change_id(fact.event_id, record.idempotency_key, index)
			result.append(record)
		elif value is Dictionary:
			result.append(GMChangeRecord.from_draft(value, index, fact.event_id, fact.transaction_id, "%s.change.%d" % [fact.idempotency_key, index], fact.causal_chain_id))
		index += 1
	return result
