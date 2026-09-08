@tool
class_name GMP21WorkbenchModel
extends RefCounted

## Chinese-first P21 authoring model. It edits neutral DialogueDefinition data,
## persists it as strict JSON, and reads P16 projections without a write path.

const RESULT_SCHEMA := "gm.p21.workbench_operation.v1"
const DIALOGUE_PATH := "user://gm_p21_dialogue_definition.json"

func new_neutral_choice(choice_id: String, display_name_zh: String, text_zh: String, next_node_id: String = "", order: int = 0, request: Dictionary = {}) -> Dictionary:
	return {
		"schema_version": GMP21Contract.DIALOGUE_CHOICE_SCHEMA_VERSION,
		"choice_id": choice_id,
		"display_name_zh": display_name_zh,
		"text_zh": text_zh,
		"next_node_id": next_node_id,
		"order": order,
		"condition": {},
		"request": request.duplicate(true),
	}

func new_neutral_node(node_id: String, speaker_ref: Variant, text_zh: String, choices: Array = []) -> Dictionary:
	return {
		"schema_version": GMP21Contract.DIALOGUE_NODE_SCHEMA_VERSION,
		"node_id": node_id,
		"speaker_ref": speaker_ref,
		"text_zh": text_zh,
		"choices": choices.duplicate(true),
	}

func new_dialogue(dialogue_id: String, display_name_zh: String, entry_node_id: String, nodes: Array, revision: int = 1) -> Dictionary:
	return {
		"schema_version": GMP21Contract.DIALOGUE_SCHEMA_VERSION,
		"dialogue_id": dialogue_id,
		"revision": revision,
		"display_name_zh": display_name_zh,
		"entry_node_id": entry_node_id,
		"nodes": nodes.duplicate(true),
	}

func preflight_dialogue(value: Variant) -> Dictionary:
	var data: Dictionary = value if value is Dictionary else {}
	if not value is Dictionary:
		return _failure("p21.workbench.dialogue_type_invalid", "对话定义必须是字典数据。")
	var parsed: GMDialogueDefinition = GMDialogueDefinition.from_dict(data)
	if parsed == null:
		return _failure("p21.workbench.dialogue_invalid", "对话定义未通过严格验证。")
	return {"schema_version": RESULT_SCHEMA, "ok": true, "code": "p21.workbench.dialogue_preflight_ok", "definition": parsed.to_dict(), "read_only_runtime_projection": true, "direct_store_write": false}

func apply_definition(definition: GMDialogueDefinition, next_value: Dictionary, editor_undo_redo: Object = null, save_path: String = DIALOGUE_PATH) -> Dictionary:
	if definition == null:
		return _failure("p21.workbench.dialogue_missing", "DialogueDefinition不存在。")
	var parsed: GMDialogueDefinition = GMDialogueDefinition.from_dict(next_value)
	if parsed == null:
		return _failure("p21.workbench.dialogue_invalid", "对话定义未通过严格验证。")
	var before := definition.to_dict()
	var after: Dictionary = parsed.to_dict()
	var saved := _write_json(save_path, after)
	if not saved.ok:
		return saved
	if editor_undo_redo != null:
		editor_undo_redo.create_action("P21对话定义：保存编辑")
		editor_undo_redo.add_do_method(Callable(self, "_apply_snapshot").bind(definition, after, save_path))
		editor_undo_redo.add_undo_method(Callable(self, "_apply_snapshot").bind(definition, before, save_path))
		editor_undo_redo.commit_action()
	else:
		var applied := _apply_snapshot(definition, after, "")
		if not applied.ok:
			return applied
	return {"schema_version": RESULT_SCHEMA, "ok": true, "code": "p21.workbench.dialogue_saved", "before": before, "after": after, "save_path": save_path, "undo_redo": editor_undo_redo != null, "direct_store_write": false}

func save_definition(definition: GMDialogueDefinition, editor_undo_redo: Object = null, save_path: String = DIALOGUE_PATH) -> Dictionary:
	if definition == null:
		return _failure("p21.workbench.dialogue_missing", "DialogueDefinition不存在。")
	return apply_definition(definition, definition.to_dict(), editor_undo_redo, save_path)

func reopen_definition(path: String = DIALOGUE_PATH) -> Dictionary:
	if path.strip_edges().is_empty():
		return _failure("p21.workbench.dialogue_path_missing", "对话定义重开路径为空。")
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return _failure("p21.workbench.dialogue_reopen_missing", "对话定义保存文件不存在。", {"path": path})
	var file := FileAccess.open(absolute, FileAccess.READ)
	if file == null:
		return _failure("p21.workbench.dialogue_reopen_failed", "对话定义保存文件无法读取。", {"path": path})
	var parsed_json := GMP21Contract.normalize_json(file.get_as_text(), "p21.workbench.dialogue_json_invalid")
	if not parsed_json.ok:
		return parsed_json
	var parsed: GMDialogueDefinition = GMDialogueDefinition.from_dict(parsed_json.value, true)
	if parsed == null:
		return _failure("p21.workbench.dialogue_reopen_invalid", "对话定义重开后未通过严格验证。")
	return {"schema_version": RESULT_SCHEMA, "ok": true, "code": "p21.workbench.dialogue_reopened", "definition": parsed, "definition_data": parsed.to_dict(), "save_path": path, "direct_store_write": false}

func reopen_definition_into(definition: GMDialogueDefinition, path: String = DIALOGUE_PATH) -> Dictionary:
	if definition == null:
		return _failure("p21.workbench.dialogue_missing", "DialogueDefinition不存在。")
	var reopened := reopen_definition(path)
	if not reopened.ok:
		return reopened
	var applied := _apply_snapshot(definition, reopened.definition_data, "")
	if not applied.ok:
		return applied
	return {"schema_version": RESULT_SCHEMA, "ok": true, "code": "p21.workbench.dialogue_reopened_into_same_object", "definition": definition, "definition_data": definition.to_dict(), "direct_store_write": false}

func task_projection(projection_service: GMTaskProjectionService, task_id: String) -> Dictionary:
	if projection_service == null:
		return _failure("p21.workbench.task_projection_missing", "P16 TaskProjectionService未连接。")
	var projection := projection_service.build(task_id)
	if not projection.ok:
		return projection
	return {"schema_version": RESULT_SCHEMA, "ok": true, "code": "p21.workbench.task_projection_read", "projection": projection.projection, "read_only": true, "direct_store_write": false}

func _apply_snapshot(definition: GMDialogueDefinition, value: Dictionary, save_path: String) -> Dictionary:
	var parsed: GMDialogueDefinition = GMDialogueDefinition.from_dict(value)
	if parsed == null:
		return _failure("p21.workbench.dialogue_invalid", "对话定义快照验证失败。")
	var source: GMDialogueDefinition = parsed
	definition.dialogue_id = source.dialogue_id
	definition.revision = source.revision
	definition.display_name_zh = source.display_name_zh
	definition.entry_node_id = source.entry_node_id
	definition.nodes = source.nodes.duplicate()
	if not save_path.is_empty():
		return _write_json(save_path, definition.to_dict())
	return {"ok": true, "direct_store_write": false}

func _write_json(path: String, value: Dictionary) -> Dictionary:
	if path.strip_edges().is_empty():
		return _failure("p21.workbench.dialogue_path_missing", "对话定义保存路径为空。")
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		return _failure("p21.workbench.dialogue_save_failed", "对话定义保存失败，原对象未提交。", {"path": path})
	file.store_string(JSON.stringify(GMStableData.persistence_canonical(value), "  ", true, true) + "\n")
	return {"ok": true, "path": path, "direct_store_write": false}

static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"schema_version": RESULT_SCHEMA, "ok": false, "code": code, "reason_zh": reason_zh, "direct_store_write": false}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
