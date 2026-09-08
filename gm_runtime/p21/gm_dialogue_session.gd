class_name GMDialogueSession
extends RefCounted

## DialogueSession is orchestration state only. It stores node/choice history,
## never NPC state, Task progress, rewards, inventory, or Store records.

const SCHEMA_VERSION := "gm.p21.dialogue.session.v1"
const FIELDS := ["schema_version", "session_id", "dialogue_id", "dialogue_revision", "current_node_id", "turn_index", "source_ref", "target_ref", "closed", "choice_history"]
const HISTORY_FIELDS := ["choice_id", "from_node_id", "to_node_id", "turn_index", "idempotency_key", "request"]

var schema_version := SCHEMA_VERSION
var session_id := ""
var dialogue: GMDialogueDefinition
var dialogue_id := ""
var dialogue_revision := 0
var current_node_id := ""
var turn_index := 0
var source_ref: Variant = ""
var target_ref: Variant = ""
var closed := false
var choice_history: Array[Dictionary] = []

func _init(p_dialogue: GMDialogueDefinition = null, p_session_id: String = "", p_source_ref: Variant = "", p_target_ref: Variant = "") -> void:
	if p_dialogue != null:
		configure(p_dialogue, p_session_id, p_source_ref, p_target_ref)

func configure(p_dialogue: GMDialogueDefinition, p_session_id: String, p_source_ref: Variant, p_target_ref: Variant) -> Dictionary:
	if p_dialogue == null or not p_dialogue.validate().ok:
		return GMP21Contract.failure("dialogue.session_definition_invalid", "DialogueSession需要有效DialogueDefinition。")
	if not GMP21Contract.stable_id(p_session_id):
		return GMP21Contract.failure("dialogue.session_id_invalid", "DialogueSession需要稳定session_id。")
	var source := GMP21Contract.target_ref(p_source_ref, true)
	if not source.ok:
		return source
	var target := GMP21Contract.target_ref(p_target_ref, true)
	if not target.ok:
		return target
	dialogue = p_dialogue
	session_id = p_session_id
	dialogue_id = p_dialogue.dialogue_id
	dialogue_revision = p_dialogue.revision
	current_node_id = p_dialogue.entry_node_id
	turn_index = 0
	source_ref = source.value
	target_ref = target.value
	closed = false
	choice_history.clear()
	return {"ok": true, "code": "dialogue.session_started", "session_id": session_id, "dialogue_id": dialogue_id, "node_id": current_node_id}

func current_node() -> GMDialogueNode:
	return dialogue.get_node(current_node_id) if dialogue != null else null

func available_choices(context: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if dialogue == null or closed:
		return result
	for choice in dialogue.available_choices(current_node_id, context):
		result.append({"choice_id": choice.choice_id, "display_name_zh": choice.display_name_zh, "text_zh": choice.text_zh, "order": choice.order, "next_node_id": choice.next_node_id, "has_request": not choice.request.is_empty()})
	return result

func select_choice(choice_id: String, context: Dictionary = {}, expected_revision: int = -1, explicit_idempotency_key: String = "") -> Dictionary:
	if dialogue == null:
		return GMP21Contract.failure("dialogue.session_definition_invalid", "DialogueSession尚未配置有效定义。")
	if expected_revision >= 0 and expected_revision != dialogue_revision:
		return GMP21Contract.failure("dialogue.choice_expired", "Dialogue定义版本已变化，Choice已过期。", {"expected_revision": expected_revision, "actual_revision": dialogue_revision})
	if not GMP21Contract.stable_id(choice_id):
		return GMP21Contract.failure("dialogue.choice_invalid", "Choice ID无效。")
	var context_check := GMP21Contract.pure(context)
	if not context_check.ok:
		return GMP21Contract.failure("dialogue.context_invalid", "Choice上下文必须是纯数据。", context_check)
	var key := explicit_idempotency_key if not explicit_idempotency_key.is_empty() else _choice_idempotency_key(choice_id)
	if not GMP21Contract.stable_id(key):
		return GMP21Contract.failure("dialogue.choice_idempotency_invalid", "Choice幂等键无效。")
	var replay := _history_by_key(key)
	if not replay.is_empty():
		if str(replay.get("choice_id", "")) != choice_id:
			return GMP21Contract.failure("dialogue.choice_idempotency_conflict", "同一对话幂等键已经绑定不同Choice。", {"idempotency_key": key, "existing_choice_id": str(replay.get("choice_id", "")), "requested_choice_id": choice_id})
		return {"ok": true, "code": "dialogue.choice_replayed", "duplicate": true, "idempotent": true, "session_id": session_id, "dialogue_id": dialogue_id, "choice_id": choice_id, "request": replay.get("request", {}).duplicate(true), "next_node_id": replay.get("to_node_id", ""), "turn_index": replay.get("turn_index", 0), "snapshot": snapshot()}
	if closed:
		return GMP21Contract.failure("dialogue.session_closed", "DialogueSession已结束，Choice被拒绝。")
	var node := current_node()
	if node == null:
		return GMP21Contract.failure("dialogue.node_missing", "DialogueSession当前Node不存在。")
	var selected: GMDialogueChoice = null
	for choice in node.choices:
		if choice.choice_id == choice_id:
			selected = choice
			break
	if selected == null:
		return GMP21Contract.failure("dialogue.choice_invalid", "当前DialogueNode不存在该Choice。", {"choice_id": choice_id, "node_id": current_node_id})
	if not selected.available(context):
		return GMP21Contract.failure("dialogue.choice_unavailable", "Choice当前条件不满足，已稳定拒绝。", {"choice_id": choice_id})
	var next_node_id := selected.next_node_id
	if not next_node_id.is_empty() and dialogue.get_node(next_node_id) == null:
		return GMP21Contract.failure("dialogue.choice_target_invalid", "Choice目标Node不存在。")
	var interaction_request := selected.build_interaction_request(source_ref, target_ref, key)
	var request_value := interaction_request.to_dict() if interaction_request != null else {}
	var history_row := {"choice_id": choice_id, "from_node_id": current_node_id, "to_node_id": next_node_id, "turn_index": turn_index, "idempotency_key": key, "request": request_value}
	var history_check := _validate_history_row(history_row)
	if not history_check.ok:
		return history_check
	# All checks happen before the small orchestration-state transition.
	choice_history.append(history_row)
	current_node_id = next_node_id
	turn_index += 1
	closed = next_node_id.is_empty()
	return {"ok": true, "code": "dialogue.choice_selected", "duplicate": false, "idempotent": false, "session_id": session_id, "dialogue_id": dialogue_id, "choice_id": choice_id, "from_node_id": history_row.from_node_id, "next_node_id": next_node_id, "turn_index": history_row.turn_index, "request": request_value, "closed": closed, "snapshot": snapshot()}

func snapshot() -> Dictionary:
	var history: Array = []
	for row in choice_history:
		history.append(row.duplicate(true))
	return {"schema_version": SCHEMA_VERSION, "session_id": session_id, "dialogue_id": dialogue_id, "dialogue_revision": dialogue_revision, "current_node_id": current_node_id, "turn_index": turn_index, "source_ref": GMStableData.clone(source_ref), "target_ref": GMStableData.clone(target_ref), "closed": closed, "choice_history": history}

func snapshot_json() -> String:
	return JSON.stringify(GMStableData.persistence_canonical(snapshot()), "", false, true)

func restore_snapshot(value: Variant, p_dialogue: GMDialogueDefinition) -> Dictionary:
	if p_dialogue == null or not p_dialogue.validate().ok:
		return GMP21Contract.failure("dialogue.session_definition_invalid", "恢复DialogueSession需要有效定义。")
	if not value is Dictionary or not GMP21Contract.exact(value, FIELDS):
		return GMP21Contract.failure("dialogue.session_snapshot_shape_invalid", "DialogueSession快照字段缺失或包含未知字段。")
	if value.schema_version != SCHEMA_VERSION or typeof(value.session_id) != TYPE_STRING or typeof(value.dialogue_id) != TYPE_STRING or typeof(value.dialogue_revision) != TYPE_INT or typeof(value.current_node_id) != TYPE_STRING or typeof(value.turn_index) != TYPE_INT or typeof(value.closed) != TYPE_BOOL or not value.choice_history is Array:
		return GMP21Contract.failure("dialogue.session_snapshot_invalid", "DialogueSession快照类型或Schema无效。")
	if value.dialogue_id != p_dialogue.dialogue_id or int(value.dialogue_revision) != p_dialogue.revision or not GMP21Contract.stable_id(value.session_id) or not GMP21Contract.nonnegative_integer(value.turn_index):
		return GMP21Contract.failure("dialogue.session_snapshot_identity_invalid", "DialogueSession快照与当前DialogueDefinition不一致。")
	var source := GMP21Contract.target_ref(value.source_ref, true)
	if not source.ok:
		return source
	var target := GMP21Contract.target_ref(value.target_ref, true)
	if not target.ok:
		return target
	if p_dialogue.get_node(value.current_node_id) == null and not bool(value.closed):
		return GMP21Contract.failure("dialogue.session_snapshot_node_invalid", "DialogueSession快照的当前Node不存在。")
	var staged_history: Array[Dictionary] = []
	for raw_row in value.choice_history:
		var row_check := _validate_history_row(raw_row)
		if not row_check.ok:
			return row_check
		staged_history.append(raw_row.duplicate(true))
	if staged_history.size() != int(value.turn_index):
		return GMP21Contract.failure("dialogue.session_snapshot_history_invalid", "DialogueSession快照turn_index与历史长度不一致。")
	var staged := GMDialogueSession.new()
	staged.dialogue = p_dialogue
	staged.session_id = str(value.session_id)
	staged.dialogue_id = p_dialogue.dialogue_id
	staged.dialogue_revision = p_dialogue.revision
	staged.current_node_id = str(value.current_node_id)
	staged.turn_index = int(value.turn_index)
	staged.source_ref = source.value
	staged.target_ref = target.value
	staged.closed = bool(value.closed)
	staged.choice_history = staged_history
	var history_chain := staged._validate_history_chain()
	if not history_chain.ok:
		return history_chain
	dialogue = staged.dialogue
	session_id = staged.session_id
	dialogue_id = staged.dialogue_id
	dialogue_revision = staged.dialogue_revision
	current_node_id = staged.current_node_id
	turn_index = staged.turn_index
	source_ref = staged.source_ref
	target_ref = staged.target_ref
	closed = staged.closed
	choice_history = staged.choice_history
	return {"ok": true, "code": "dialogue.session_restored", "session_id": session_id, "snapshot": snapshot()}

func restore_json(text: String, p_dialogue: GMDialogueDefinition) -> Dictionary:
	var parsed := GMP21Contract.normalize_json(text, "dialogue.session_json_invalid")
	if not parsed.ok:
		return parsed
	var canonical: Variant = GMStableData.persistence_canonical(parsed.value)
	return restore_snapshot(canonical, p_dialogue)

func _choice_idempotency_key(choice_id_value: String) -> String:
	return "gm.dialogue.choice.%s.%d.%s" % [session_id, turn_index, choice_id_value]

func _history_by_key(key: String) -> Dictionary:
	for row in choice_history:
		if str(row.get("idempotency_key", "")) == key:
			return row
	return {}

func _validate_history_chain() -> Dictionary:
	var expected_node := dialogue.entry_node_id
	var seen_keys: Dictionary = {}
	for index in choice_history.size():
		var row: Dictionary = choice_history[index]
		if str(row.from_node_id) != expected_node or int(row.turn_index) != index:
			return GMP21Contract.failure("dialogue.session_history_order_invalid", "DialogueSession历史不是确定性节点顺序。")
		var history_key := str(row.get("idempotency_key", ""))
		if seen_keys.has(history_key):
			return GMP21Contract.failure("dialogue.session_history_idempotency_duplicate", "DialogueSession历史不得重复使用幂等键。", {"idempotency_key": history_key})
		seen_keys[history_key] = true
		var node := dialogue.get_node(expected_node)
		if node == null:
			return GMP21Contract.failure("dialogue.session_history_node_invalid", "DialogueSession历史引用了不存在的Node。")
		var found: GMDialogueChoice = null
		for choice in node.choices:
			if choice.choice_id == str(row.choice_id) and choice.next_node_id == str(row.to_node_id):
				found = choice
				break
		if found == null:
			return GMP21Contract.failure("dialogue.session_history_choice_invalid", "DialogueSession历史Choice与定义不一致。")
		var expected_request := found.build_interaction_request(source_ref, target_ref, history_key)
		var expected_request_value := expected_request.to_dict() if expected_request != null else {}
		if not GMP21Contract.same_value(row.get("request", {}), expected_request_value):
			return GMP21Contract.failure("dialogue.session_history_request_invalid", "DialogueSession历史请求与Choice定义不一致。")
		expected_node = str(row.to_node_id)
	if closed and not current_node_id.is_empty():
		return GMP21Contract.failure("dialogue.session_closed_node_invalid", "已结束DialogueSession不能保留当前Node。")
	if closed != expected_node.is_empty() or (not closed and current_node_id != expected_node):
		return GMP21Contract.failure("dialogue.session_closed_state_invalid", "DialogueSession closed/current_node与历史不一致。")
	return {"ok": true}

static func _validate_history_row(value: Variant) -> Dictionary:
	if not value is Dictionary or not GMP21Contract.exact(value, HISTORY_FIELDS):
		return GMP21Contract.failure("dialogue.session_history_shape_invalid", "DialogueSession历史行字段必须精确匹配。")
	if typeof(value.choice_id) != TYPE_STRING or not GMP21Contract.stable_id(value.choice_id) or typeof(value.from_node_id) != TYPE_STRING or not GMP21Contract.stable_id(value.from_node_id) or typeof(value.to_node_id) != TYPE_STRING or not GMP21Contract.stable_id(value.to_node_id, true) or typeof(value.turn_index) != TYPE_INT or not GMP21Contract.nonnegative_integer(value.turn_index) or typeof(value.idempotency_key) != TYPE_STRING or not GMP21Contract.stable_id(value.idempotency_key) or not value.request is Dictionary:
		return GMP21Contract.failure("dialogue.session_history_identity_invalid", "DialogueSession历史行身份或顺序无效。")
	if not value.request.is_empty():
		var decoded := GMInteractionRequest.from_dict(value.request)
		if not decoded.ok:
			return decoded
	var pure_check := GMP21Contract.pure(value)
	return pure_check
