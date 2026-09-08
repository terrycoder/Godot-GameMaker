class_name GMFeedbackRestoreDescriptor
extends RefCounted

## RETIRED P18 EXIT artifact.  It is preserved only for historical source
## compatibility; the playback service no longer consumes descriptors.

const SCHEMA_VERSION := "gm.feedback.restore_descriptor.v2"
const REFERENCE_FIELDS := ["schema", "binding_id", "descriptor_digest"]

var binding_id := ""
var descriptor_digest := ""
var request: GMSemanticFeedbackRequest
var definition: GMFeedbackSequenceDefinition
var authority: Dictionary
var authority_reader: GMFeedbackAuthorityReader
var attention_runtime: GMAgentPlannerRuntime
var presenter: Object
var cue_router: GMCueRouter
var backend_registry: Dictionary = {}
var mapper_artifact: GMFeedbackMapperBuildArtifact
var material: Dictionary = {}

static func from_mapper_result(mapped: Dictionary, presenter_value: Object, cue_value: GMCueRouter, backends_value: Dictionary, p_attention_runtime: GMAgentPlannerRuntime = null) -> Dictionary:
	return {"ok": false, "code": "feedback.restore_api_retired", "reason_zh": "P18 restore descriptor API已退役，不能重新注册或作为live播放根。", "details": {"api": "GMFeedbackRestoreDescriptor.from_mapper_result", "replayed": false, "logic_unchanged": true, "domain_facts_written": false}}
	# Historical descriptor construction is intentionally unreachable after EXIT.
	var artifact_value: Variant = mapped.get("mapper_build_artifact", null)
	if not artifact_value is GMFeedbackMapperBuildArtifact:
		return _failure("feedback.restore_descriptor_mapper_required", "恢复描述符只能由当前GMSemanticFeedbackMapper正式build路径构造。")
	var artifact: GMFeedbackMapperBuildArtifact = artifact_value
	var artifact_check := artifact.validate_for(mapped, artifact.source_mapper)
	if not artifact_check.ok:
		return artifact_check
	var request: GMSemanticFeedbackRequest = artifact.request
	var definition: GMFeedbackSequenceDefinition = artifact.definition
	var authority_reader: GMFeedbackAuthorityReader = artifact.authority_reader
	var authority := authority_reader.read_fact(request.source_fact_id)
	if not authority.ok:
		return authority
	var canonical := GMSemanticFeedbackMapper.canonical_restore_projection(authority, definition, request.target_ref, request.direction, request.anchor_id, request.attention_projection)
	if not canonical.ok or request.to_dict() != canonical.request_fields:
		return _failure("feedback.restore_descriptor_authority_mismatch", "恢复描述符与当前P16 authority或正式mapper投影不一致。")
	var attention_runtime := p_attention_runtime if p_attention_runtime != null else artifact.attention_runtime
	if not request.attention_projection.is_empty():
		if attention_runtime == null:
			return _failure("feedback.restore_descriptor_attention_runtime_missing", "含Attention的恢复描述符需要当前P17 runtime。")
		var attention_check := authority_reader.validate_attention_projection(request.source_fact_id, request.target_ref, request.attention_projection, attention_runtime.attention_projection)
		if not attention_check.ok:
			return _failure("feedback.restore_descriptor_attention_invalid", "恢复描述符的Attention投影无法与当前P16/P17逐值互证。", attention_check)
		request.attention_projection = attention_check.value.duplicate(true)
	var definition_copy := GMFeedbackSequenceDefinition.from_dict(definition.to_dict())
	if definition_copy == null:
		return _failure("feedback.restore_descriptor_definition_invalid", "当前注册的反馈定义无法形成运行时可信副本。")
	var descriptor := GMFeedbackRestoreDescriptor.new()
	descriptor.request = GMSemanticFeedbackRequest.from_dict(request.to_dict())
	descriptor.definition = definition_copy
	descriptor.authority = authority
	descriptor.authority_reader = authority_reader
	descriptor.attention_runtime = attention_runtime
	descriptor.presenter = presenter_value
	descriptor.cue_router = cue_value
	descriptor.backend_registry = backends_value
	descriptor.mapper_artifact = artifact
	var runtime := descriptor._build_runtime_material(presenter_value, cue_value, backends_value)
	if not runtime.ok:
		return runtime
	descriptor.material = descriptor._build_material(runtime.value)
	descriptor.binding_id = "gm.feedback.binding.v2.%s" % GMStableData.digest(descriptor.material)
	descriptor.descriptor_digest = GMStableData.digest({"schema": SCHEMA_VERSION, "binding_id": descriptor.binding_id, "material": descriptor.material, "request": descriptor.request.to_dict(), "definition": descriptor.definition.to_dict()})
	return {"ok": true, "code": "feedback.restore_descriptor_built", "descriptor": descriptor}

func reference_dict() -> Dictionary:
	return {}

func feedback_id() -> String:
	return ""

func idempotency_key() -> String:
	return ""

func validate_authority() -> Dictionary:
	return {"ok": false, "code": "feedback.restore_api_retired", "reason_zh": "P18 restore descriptor API已退役。", "details": {"replayed": false}}
	# Historical descriptor validation is intentionally unreachable after EXIT.
	if authority_reader == null or request == null or definition == null:
		return _failure("feedback.restore_descriptor_incomplete", "恢复描述符缺少运行时权威或定义。")
	var current := authority_reader.read_fact(request.source_fact_id)
	if not current.ok:
		return _failure("feedback.restore_descriptor_authority_stale", "恢复描述符的P16 Fact当前不可重新互证。", current)
	var canonical := GMSemanticFeedbackMapper.canonical_restore_projection(current, definition, request.target_ref, request.direction, request.anchor_id, request.attention_projection)
	if not canonical.ok or request.to_dict() != canonical.request_fields:
		return _failure("feedback.restore_descriptor_authority_stale", "恢复描述符的canonical request与当前P16 authority不一致。")
	if str(canonical.sequence_digest) != definition.digest():
		return _failure("feedback.restore_descriptor_definition_stale", "恢复描述符引用的definition摘要已变化。")
	return {"ok": true, "code": "feedback.restore_descriptor_authority_valid"}

func validate_runtime(current_cue_router: GMCueRouter, current_backends: Dictionary, current_presenters: Dictionary, current_attention_runtime: GMAgentPlannerRuntime = null) -> Dictionary:
	return {"ok": false, "code": "feedback.restore_api_retired", "reason_zh": "P18 restore descriptor runtime validation API已退役。", "details": {"replayed": false}}
	# Historical descriptor runtime validation is intentionally unreachable after EXIT.
	var authority_check := validate_authority()
	if not authority_check.ok:
		return authority_check
	if request == null or definition == null:
		return _failure("feedback.restore_descriptor_incomplete", "恢复描述符缺少请求或定义。")
	if not request.attention_projection.is_empty():
		var runtime := current_attention_runtime if current_attention_runtime != null else attention_runtime
		if runtime == null:
			return _failure("feedback.restore_descriptor_attention_runtime_missing", "恢复描述符当前缺少P17 runtime。")
		var attention_check := authority_reader.validate_attention_projection(request.source_fact_id, request.target_ref, request.attention_projection, runtime.attention_projection)
		if not attention_check.ok:
			return _failure("feedback.restore_descriptor_attention_stale", "恢复描述符的Attention投影已过期或跨对象。", attention_check)
	var presenter_value: Object = current_presenters.get(request.target_ref, null)
	if _requires_presenter():
		if presenter != presenter_value:
			return _failure("feedback.restore_descriptor_presenter_stale", "恢复描述符与当前目标Presenter实例不一致。")
	var runtime_material := _build_runtime_material(presenter_value, current_cue_router, current_backends)
	if not runtime_material.ok:
		return runtime_material
	var current_material := _build_material(runtime_material.value)
	if GMStableData.digest(current_material) != GMStableData.digest(material):
		return _failure("feedback.restore_descriptor_runtime_stale", "当前场景、Presenter、Cue或表现后端配置已改变，恢复描述符过期。")
	var expected_binding := "gm.feedback.binding.v2.%s" % GMStableData.digest(current_material)
	if expected_binding != binding_id:
		return _failure("feedback.restore_descriptor_binding_stale", "恢复binding不是当前运行时配置产生的可信binding。")
	var expected_digest := GMStableData.digest({"schema": SCHEMA_VERSION, "binding_id": binding_id, "material": material, "request": request.to_dict(), "definition": definition.to_dict()})
	if expected_digest != descriptor_digest:
		return _failure("feedback.restore_descriptor_digest_invalid", "恢复描述符摘要不匹配。")
	return {"ok": true, "code": "feedback.restore_descriptor_runtime_valid"}

func _build_material(runtime_material: Dictionary) -> Dictionary:
	return {"authority": material_authority(), "request_identity": {"feedback_id": request.feedback_id, "idempotency_key": request.idempotency_key, "sequence_key": request.sequence_key, "source_fact_id": request.source_fact_id, "sequence_id": request.sequence_id, "semantic_action_id": request.semantic_action_id, "target_ref": request.target_ref, "direction": request.direction, "anchor_id": request.anchor_id, "requested_logical_tick": request.requested_logical_tick}, "definition_digest": definition.digest(), "runtime": runtime_material}

func material_authority() -> Dictionary:
	var fact: GMFactEvent = authority.get("fact", null)
	return {"source_fact_id": fact.event_id if fact != null else "", "commit_package_id": str(authority.get("commit_package_id", "")), "transaction_id": fact.transaction_id if fact != null else "", "causal_chain_id": fact.causal_chain_id if fact != null else "", "global_sequence": fact.sequence if fact != null else 0, "source_type": str(authority.get("source_type", "")), "source_payload_digest": str(authority.get("source_payload_digest", ""))}

func _build_runtime_material(presenter_value: Object, cue_value: GMCueRouter, backends_value: Dictionary) -> Dictionary:
	if _requires_presenter() and (presenter_value == null or not is_instance_valid(presenter_value) or not presenter_value.has_method("play_semantic_action")):
		return {"ok": true, "value": {"presenter": {"available": false}, "cues": _cue_material(cue_value), "backends": _backend_material(backends_value)}}
	return {"ok": true, "value": {"presenter": _presenter_material(presenter_value), "cues": _cue_material(cue_value), "backends": _backend_material(backends_value)}}

func _requires_presenter() -> bool:
	for step in definition.ordered_steps():
		if step.step_kind == "semantic_action":
			return true
	return false

func _presenter_material(value: Object) -> Dictionary:
	if value == null or not is_instance_valid(value):
		return {"available": false}
	var snapshot := {}
	if value.has_method("snapshot"):
		var raw: Variant = value.call("snapshot")
		if raw is Dictionary and GMStableData.validate_persistence(raw).ok:
			snapshot = raw
	var script_path := ""
	if value.has_method("get_script"):
		var script_value: Variant = value.get_script()
		if script_value is Script:
			script_path = script_value.resource_path
	return {"available": true, "class": value.get_class(), "script": script_path, "snapshot": snapshot}

func _cue_material(router: GMCueRouter) -> Array:
	var rows: Array = []
	for step in definition.ordered_steps():
		if step.step_kind != "cue":
			continue
		var cue: GMCueDefinition = router.definitions.get(step.cue_id, null) if router != null else null
		rows.append({"cue_id": step.cue_id, "available": cue != null, "summary": cue.to_summary() if cue != null else {}})
	return rows

func _backend_material(registry: Dictionary) -> Array:
	var rows: Array = []
	for step in definition.ordered_steps():
		if step.step_kind in ["semantic_action", "cue", "noop"]:
			continue
		var backend: Variant = registry.get(step.step_kind, null)
		if backend == null:
			backend = registry.get("gm.feedback.backend.%s" % step.step_kind, null)
		rows.append({"step_kind": step.step_kind, "available": backend != null, "backend_id": str(backend.backend_id) if backend is GMFeedbackBackend else "", "class": backend.get_class() if backend is Object else ""})
	return rows

static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
