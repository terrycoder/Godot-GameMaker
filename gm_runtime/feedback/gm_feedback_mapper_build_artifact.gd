class_name GMFeedbackMapperBuildArtifact
extends RefCounted

## Runtime-only evidence that a live playback context came from the formal
## mapper build path. It intentionally has no dictionary deserializer: a
## persisted snapshot can never manufacture this object.

var source_mapper: Object
var authority_reader: GMFeedbackAuthorityReader
var authority: Dictionary
var request: GMSemanticFeedbackRequest
var definition: GMFeedbackSequenceDefinition
var attention_runtime: GMAgentPlannerRuntime
var projection_digest := ""
var token := RefCounted.new()

func _init(p_source_mapper: Object, p_authority_reader: GMFeedbackAuthorityReader, p_authority: Dictionary, p_request: GMSemanticFeedbackRequest, p_definition: GMFeedbackSequenceDefinition, p_attention_runtime: GMAgentPlannerRuntime, p_projection_digest: String) -> void:
	source_mapper = p_source_mapper
	authority_reader = p_authority_reader
	authority = p_authority
	request = p_request
	definition = p_definition
	attention_runtime = p_attention_runtime
	projection_digest = p_projection_digest

func validate_for(mapped: Dictionary, mapper: Object) -> Dictionary:
	if source_mapper != mapper or authority_reader == null or request == null or definition == null:
		return {"ok": false, "code": "feedback.mapper_build_artifact_invalid", "reason_zh": "live表现上下文必须来自当前语义反馈映射器的正式构建产物。"}
	if mapped.get("request", null) != request or mapped.get("definition", null) != definition or mapped.get("authority", null) != authority:
		return {"ok": false, "code": "feedback.mapper_build_artifact_mismatch", "reason_zh": "映射产物已被替换，拒绝构造live表现上下文。"}
	var request_check := request.validate()
	if not request_check.ok:
		return request_check
	var definition_check := definition.validate()
	if not definition_check.ok:
		return definition_check
	if not authority.has("fact") or not authority.has("package"):
		return {"ok": false, "code": "feedback.mapper_build_authority_missing", "reason_zh": "映射产物缺少可重新互证的P16权威来源。"}
	return {"ok": true, "code": "feedback.mapper_build_artifact_valid"}
