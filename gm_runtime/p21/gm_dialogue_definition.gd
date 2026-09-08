class_name GMDialogueDefinition
extends RefCounted

const SCHEMA_VERSION := GMP21Contract.DIALOGUE_SCHEMA_VERSION
const FIELDS := ["schema_version", "dialogue_id", "revision", "display_name_zh", "entry_node_id", "nodes"]

var schema_version := SCHEMA_VERSION
var dialogue_id := ""
var revision := 1
var display_name_zh := ""
var entry_node_id := ""
var nodes: Array[GMDialogueNode] = []

func _init(p_dialogue_id: String = "", p_display_name_zh: String = "") -> void:
	dialogue_id = p_dialogue_id
	display_name_zh = p_display_name_zh

func validate() -> Dictionary:
	var value := to_dict()
	if not GMP21Contract.exact(value, FIELDS):
		return GMP21Contract.failure("dialogue.definition_shape_invalid", "DialogueDefinition字段集合必须精确匹配。")
	if schema_version != SCHEMA_VERSION or not GMP21Contract.stable_id(dialogue_id) or not GMP21Contract.positive_integer(revision) or display_name_zh.strip_edges().is_empty() or not GMP21Contract.stable_id(entry_node_id):
		return GMP21Contract.failure("dialogue.definition_identity_invalid", "DialogueDefinition的版本、身份、修订号或入口节点无效。")
	if nodes.is_empty():
		return GMP21Contract.failure("dialogue.definition_nodes_missing", "DialogueDefinition至少需要一个Node。")
	var node_ids: Dictionary = {}
	for node in nodes:
		if node == null:
			return GMP21Contract.failure("dialogue.definition_node_missing", "DialogueDefinition不能包含空Node。")
		var node_check := node.validate()
		if not node_check.ok:
			return node_check
		if node_ids.has(node.node_id):
			return GMP21Contract.failure("dialogue.definition_node_duplicate", "DialogueDefinition中的Node ID不得重复。", {"node_id": node.node_id})
		node_ids[node.node_id] = true
	if not node_ids.has(entry_node_id):
		return GMP21Contract.failure("dialogue.definition_entry_missing", "DialogueDefinition入口Node不存在。")
	for node in nodes:
		for choice in node.choices:
			if not choice.next_node_id.is_empty() and not node_ids.has(choice.next_node_id):
				return GMP21Contract.failure("dialogue.definition_choice_target_missing", "Choice引用了不存在的目标Node。", {"choice_id": choice.choice_id, "next_node_id": choice.next_node_id})
	return {"ok": true, "code": "dialogue.definition_valid", "value": value, "digest": digest()}

func get_node(node_id: String) -> GMDialogueNode:
	for node in nodes:
		if node != null and node.node_id == node_id:
			return node
	return null

func available_choices(node_id: String, context: Dictionary = {}) -> Array[GMDialogueChoice]:
	var node := get_node(node_id)
	var result: Array[GMDialogueChoice] = []
	if node == null:
		return result
	var context_check := GMP21Contract.pure(context)
	if not context_check.ok:
		return result
	for choice in node.ordered_choices():
		if choice.available(context):
			result.append(choice)
	return result

func digest() -> String:
	return GMP21Contract.digest(to_dict())

func to_dict() -> Dictionary:
	var rows: Array = []
	var ordered := nodes.duplicate()
	ordered.sort_custom(func(left: GMDialogueNode, right: GMDialogueNode): return left.node_id < right.node_id)
	for node in ordered:
		rows.append(node.to_dict())
	return {"schema_version": schema_version, "dialogue_id": dialogue_id, "revision": revision, "display_name_zh": display_name_zh, "entry_node_id": entry_node_id, "nodes": rows}

func to_json() -> String:
	return JSON.stringify(GMStableData.persistence_canonical(to_dict()), "", false, true)

static func from_dict(value: Variant, json_boundary: bool = false) -> GMDialogueDefinition:
	if not value is Dictionary or not GMP21Contract.exact(value, FIELDS):
		return null
	if typeof(value.get("schema_version")) != TYPE_STRING or typeof(value.get("dialogue_id")) != TYPE_STRING or not _integer_value(value.get("revision"), json_boundary) or typeof(value.get("display_name_zh")) != TYPE_STRING or typeof(value.get("entry_node_id")) != TYPE_STRING or not value.get("nodes") is Array:
		return null
	var result := GMDialogueDefinition.new()
	result.schema_version = str(value.schema_version)
	result.dialogue_id = str(value.dialogue_id)
	result.revision = int(value.revision)
	result.display_name_zh = str(value.display_name_zh)
	result.entry_node_id = str(value.entry_node_id)
	for raw_node in value.nodes:
		var node := GMDialogueNode.from_dict(raw_node, json_boundary)
		if node == null:
			return null
		result.nodes.append(node)
	return result if result.validate().ok else null

static func from_json(text: String) -> Dictionary:
	var parsed := GMP21Contract.normalize_json(text, "dialogue.definition_json_invalid")
	if not parsed.ok:
		return parsed
	var definition := from_dict(parsed.value, true)
	if definition == null:
		return GMP21Contract.failure("dialogue.definition_json_invalid", "DialogueDefinition JSON未通过严格合同校验。")
	return {"ok": true, "code": "dialogue.definition_decoded", "definition": definition}

static func _integer_value(value: Variant, json_boundary: bool) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) > 0 and int(value) <= GMStableData.JSON_SAFE_INTEGER_MAX
	return json_boundary and typeof(value) == TYPE_FLOAT and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) > 0.0 and float(value) <= float(GMStableData.JSON_SAFE_INTEGER_MAX)

