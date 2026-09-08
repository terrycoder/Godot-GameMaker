@tool
class_name GMCueDefinition
extends Resource

const SCHEMA_VERSION := "gm.cue_definition.v2"
const STAGES := ["execute", "add", "remove"]

@export var cue_id: String = ""
@export var display_name_zh: String = ""
@export var semantic_tag: String = ""
@export var allowed_stages: PackedStringArray = PackedStringArray(["execute", "add", "remove"])
@export var required: bool = false
@export var content_version: String = "gm.content.v1"
@export var metadata: Dictionary = {}

func validate() -> Dictionary:
	var errors: Array[String] = []
	if cue_id.strip_edges().is_empty(): errors.append("Cue 缺少稳定 cue_id。")
	var seen: Dictionary = {}
	for stage in allowed_stages:
		var normalized := str(stage).to_lower()
		if not STAGES.has(normalized): errors.append("Cue 阶段不受支持：%s。" % stage)
		if seen.has(normalized): errors.append("Cue 阶段重复：%s。" % stage)
		seen[normalized] = true
	return {"ok": errors.is_empty(), "code": "cue_definition.valid" if errors.is_empty() else "cue_definition.invalid", "errors": errors}

func supports_stage(stage: String) -> bool:
	var normalized := stage.to_lower()
	return allowed_stages.is_empty() or allowed_stages.has(normalized)

func to_summary() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "cue_id": cue_id, "display_name_zh": display_name_zh, "semantic_tag": semantic_tag, "allowed_stages": Array(allowed_stages), "required": required, "content_version": content_version, "metadata": metadata.duplicate(true)}
