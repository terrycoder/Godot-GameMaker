class_name GMCharacterControlRouter
extends RefCounted

var host: GMAbilitySystemHost
var enabled_sources: PackedStringArray = PackedStringArray()
var selected_source: String = ""
var selected_owner: String = ""
var sequence: int = 0
var log: Array[Dictionary] = []

func configure(p_host: GMAbilitySystemHost, sources: PackedStringArray) -> Dictionary:
	if p_host == null: return _fail("control.host_missing", "控制路由缺少统一 GAS Host。")
	host = p_host
	enabled_sources = sources.duplicate()
	selected_source = ""
	selected_owner = ""
	return {"ok":true,"sources":enabled_sources}

func acquire(source: String, owner: String = "") -> Dictionary:
	if source not in enabled_sources: return _fail("control.source_disabled", "控制源未被当前身份启用。", {"source":source})
	if owner.strip_edges().is_empty(): return _fail("control.owner_missing", "P14 控制交接必须提供明确 owner。", {"source":source})
	if not selected_source.is_empty():
		return _fail("control.handoff_conflict", "当前角色已有控制源；P14 不提供可覆盖 lease，Reservation 所有权延期至 P16。", {"requested_source":source,"requested_owner":owner,"active_source":selected_source,"active_owner":selected_owner,"reservation_deferred_to":"P16"})
	sequence += 1
	selected_source = source
	selected_owner = owner
	log.append({"kind":"control_handoff_acquired","source":source,"owner":owner,"sequence":sequence})
	return {"ok":true,"source":source,"active_source":active_source()}

func release(source: String, owner: String = "") -> Dictionary:
	if selected_source.is_empty(): return _fail("control.handoff_missing", "当前没有可释放的 P14 控制交接。", {"source":source,"owner":owner})
	if source != selected_source or owner != selected_owner:
		return _fail("control.release_not_owner", "释放请求与当前控制 owner 不一致，原交接保持不变。", {"requested_source":source,"requested_owner":owner,"active_source":selected_source,"active_owner":selected_owner})
	var released := selected_source
	selected_source = ""
	selected_owner = ""
	log.append({"kind":"control_handoff_released","source":released,"owner":owner})
	return {"ok":true,"released":released,"active_source":""}

func active_source() -> String:
	return selected_source

func snapshot_state() -> Dictionary:
	return {"schema":"gm.character.control_handoff.v1","source":selected_source,"owner":selected_owner,"sequence":sequence}

func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	for field in ["schema","source","owner","sequence"]:
		if not snapshot.has(field): return _fail("control.snapshot_truncated", "控制交接快照缺少必要字段，请使用完整快照后重试。", {"missing":field})
	for field in ["schema","source","owner"]:
		if typeof(snapshot[field]) != TYPE_STRING:
			return _fail("control.snapshot_field_type_invalid", "控制交接快照字段“%s”类型错误，应为字符串；请检查存档写入器或迁移器。" % field, {"field":field,"expected_type":"String","actual_type":type_string(typeof(snapshot[field]))})
	if typeof(snapshot.sequence) != TYPE_INT:
		return _fail("control.snapshot_sequence_type_invalid", "控制交接快照字段“sequence”类型错误，应为整数；请检查存档写入器或迁移器。", {"field":"sequence","expected_type":"int","actual_type":type_string(typeof(snapshot.sequence))})
	var schema_value: String = snapshot.schema
	var source: String = snapshot.source
	var owner: String = snapshot.owner
	var sequence_value: int = snapshot.sequence
	if schema_value != "gm.character.control_handoff.v1": return _fail("control.snapshot_schema_invalid", "控制交接快照 schema 不一致，请使用当前版本快照。")
	if source.is_empty() != owner.is_empty(): return _fail("control.snapshot_truncated", "控制交接快照 source/owner 必须同时为空或同时存在。")
	if not source.is_empty() and source not in enabled_sources: return _fail("control.snapshot_source_disabled", "控制交接快照引用了当前身份未启用的控制源。", {"source":source})
	if sequence_value < 0: return _fail("control.snapshot_sequence_invalid", "控制交接快照 sequence 不能为负数，请检查快照来源。")
	return {"ok":true,"source":source,"owner":owner,"sequence":sequence_value}

func restore_state(snapshot: Dictionary) -> Dictionary:
	var checked := validate_snapshot(snapshot)
	if not checked.ok: return checked
	commit_prepared_state(checked)
	return {"ok":true,"active_source":selected_source,"owner":selected_owner}

func commit_prepared_state(prepared: Dictionary) -> void:
	selected_source = str(prepared.get("source", ""))
	selected_owner = str(prepared.get("owner", ""))
	sequence = int(prepared.get("sequence", 0))

func reset() -> void:
	host = null
	enabled_sources = PackedStringArray()
	selected_source = ""
	selected_owner = ""

func activation_request(source: String, ability_id: String, payload: Dictionary = {}, idempotency_key: String = "") -> Dictionary:
	if source != active_source(): return _fail("control.not_owner", "较高优先级控制源正在接管，请求未发送。", {"source":source,"active_source":active_source()})
	var request := GMAbilityActivationRequest.new(host, ability_id, "", null, payload, "character.%s" % source, {}, idempotency_key)
	var check := request.validate()
	if not check.ok: return check
	log.append({"kind":"ActivationRequest","source":source,"ability_id":ability_id,"request_id":request.request_id})
	return {"ok":true,"request":request,"kind":"ActivationRequest"}

func gameplay_event(source: String, tag: String, payload: Dictionary = {}) -> Dictionary:
	if source != active_source(): return _fail("control.not_owner", "非接管控制源不能发送事件。", {"source":source,"active_source":active_source()})
	var event := GMGameplayEvent.new(tag, host.entity if host != null else null, null, payload, "character.%s" % source)
	var check := event.validate()
	if not check.ok: return check
	log.append({"kind":"GameplayEvent","source":source,"event_tag":event.event_tag})
	return {"ok":true,"event":event,"kind":"GameplayEvent"}

func _fail(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok":false,"code":code,"error_zh":message,"details":details}
