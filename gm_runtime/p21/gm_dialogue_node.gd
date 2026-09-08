class_name GMDialogueNode
extends RefCounted

const SCHEMA_VERSION := GMP21Contract.DIALOGUE_NODE_SCHEMA_VERSION
const FIELDS := ["schema_version", "node_id", "speaker_ref", "text_zh", "choices"]

var schema_version := SCHEMA_VERSION
var node_id := ""
var speaker_ref: Variant = ""
var text_zh := ""
var choices: Array[GMDialogueChoice] = []

func _init(p_node_id: String = "", p_text_zh: String = "", p_speaker_ref: Variant = "") -> void:
	node_id = p_node_id
	text_zh = p_text_zh
	speaker_ref = p_speaker_ref

func validate() -> Dictionary:
	var value := to_dict()
	if not GMP21Contract.exact(value, FIELDS):
		return GMP21Contract.failure("dialogue.node_shape_invalid", "DialogueNode字段集合必须精确匹配。")
	if schema_version != SCHEMA_VERSION or not GMP21Contract.stable_id(node_id) or text_zh.strip_edges().is_empty():
		return GMP21Contract.failure("dialogue.node_identity_invalid", "DialogueNode的版本、节点ID或中文正文无效。")
	var speaker_check := GMP21Contract.target_ref(speaker_ref, true)
	if not speaker_check.ok:
		return speaker_check
	var ids: Dictionary = {}
	for choice in choices:
		if choice == null:
			return GMP21Contract.failure("dialogue.node_choice_missing", "DialogueNode不能包含空Choice。")
		var checked := choice.validate()
		if not checked.ok:
			return checked
		if ids.has(choice.choice_id):
			return GMP21Contract.failure("dialogue.node_choice_duplicate", "同一DialogueNode中的Choice ID不得重复。", {"choice_id": choice.choice_id})
		ids[choice.choice_id] = true
	return {"ok": true, "code": "dialogue.node_valid", "value": value}

func ordered_choices() -> Array[GMDialogueChoice]:
	var result: Array[GMDialogueChoice] = []
	for choice in choices:
		if choice != null:
			result.append(choice)
	result.sort_custom(Callable(self, "_choice_before"))
	return result

func _choice_before(left: GMDialogueChoice, right: GMDialogueChoice) -> bool:
	if left.order != right.order:
		return left.order < right.order
	return left.choice_id < right.choice_id

func to_dict() -> Dictionary:
	var rows: Array = []
	for choice in ordered_choices():
		rows.append(choice.to_dict())
	return {"schema_version": schema_version, "node_id": node_id, "speaker_ref": GMStableData.clone(speaker_ref), "text_zh": text_zh, "choices": rows}

static func from_dict(value: Variant, json_boundary: bool = false) -> GMDialogueNode:
	if not value is Dictionary or not GMP21Contract.exact(value, FIELDS):
		return null
	if typeof(value.get("schema_version")) != TYPE_STRING or typeof(value.get("node_id")) != TYPE_STRING or typeof(value.get("text_zh")) != TYPE_STRING or not value.get("choices") is Array:
		return null
	var result := GMDialogueNode.new()
	result.schema_version = str(value.schema_version)
	result.node_id = str(value.node_id)
	result.speaker_ref = GMStableData.clone(value.get("speaker_ref", ""))
	result.text_zh = str(value.text_zh)
	for raw_choice in value.choices:
		var choice := GMDialogueChoice.from_dict(raw_choice, json_boundary)
		if choice == null:
			return null
		result.choices.append(choice)
	return result if result.validate().ok else null
