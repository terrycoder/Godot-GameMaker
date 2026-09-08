@tool
class_name GMP20WorkbenchModel
extends RefCounted

const RESULT_SCHEMA := "gm.p20.workbench_operation.v1"

func apply_definition(definition: GMProcessDefinition, next_value: Dictionary, editor_undo_redo: Object = null, save_path: String = "") -> Dictionary:
	if definition == null: return _failure("p20.workbench.definition_missing", "ProcessDefinition 不存在。")
	var parsed: Dictionary = GMProcessDefinition.from_native(next_value)
	if not parsed.ok: return _failure(str(parsed.get("code", "p20.workbench.definition_invalid")), str(parsed.get("reason_zh", "ProcessDefinition 验证失败。")))
	var before := definition.to_native()
	var after: Dictionary = parsed.definition.to_native()
	if editor_undo_redo != null:
		editor_undo_redo.create_action("Process定义：保存编辑")
		editor_undo_redo.add_do_method(Callable(self, "_apply_snapshot").bind(definition, after, save_path))
		editor_undo_redo.add_undo_method(Callable(self, "_apply_snapshot").bind(definition, before, save_path))
		editor_undo_redo.commit_action()
	else:
		var applied: Dictionary = _apply_snapshot(definition, after, save_path)
		if not applied.ok: return applied
	return {"schema_version": RESULT_SCHEMA, "ok": true, "code": "p20.workbench.definition_saved", "before": before, "after": after, "undo_redo": editor_undo_redo != null, "direct_store_write": false}

func reopen_definition(path: String) -> Dictionary:
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or not loaded is GMProcessDefinition: return _failure("p20.workbench.reopen_failed", "ProcessDefinition 重开失败。")
	var validation: Dictionary = loaded.validate()
	if not validation.ok: return _failure("p20.workbench.definition_invalid", "ProcessDefinition 验证失败。", {"errors": validation.errors})
	return {"schema_version": RESULT_SCHEMA, "ok": true, "definition": loaded, "definition_data": loaded.to_native(), "resource_reused": false, "direct_store_write": false}

func reopen_definition_into(definition: GMProcessDefinition, path: String) -> Dictionary:
	if definition == null: return _failure("p20.workbench.definition_missing", "ProcessDefinition 不存在。")
	var reopened: Dictionary = reopen_definition(path)
	if not reopened.ok: return reopened
	var synchronized: Dictionary = _apply_snapshot(definition, reopened.definition_data, "")
	if not synchronized.ok: return synchronized
	return {"schema_version": RESULT_SCHEMA, "ok": true, "definition": definition, "definition_data": definition.to_native(), "resource_reused": true, "direct_store_write": false}

func instance_projection(store: GMProcessStore) -> Dictionary:
	if store == null: return _failure("p20.workbench.store_missing", "Process Store 不存在。")
	return {"schema_version": RESULT_SCHEMA, "ok": true, "read_only": true, "instances": store.instance_projection(), "direct_store_write": false}

func _apply_snapshot(definition: GMProcessDefinition, value: Dictionary, save_path: String) -> Dictionary:
	var parsed: Dictionary = GMProcessDefinition.from_native(value)
	if not parsed.ok: return _failure(str(parsed.get("code", "p20.workbench.definition_invalid")), str(parsed.get("reason_zh", "ProcessDefinition 验证失败。")))
	var source: GMProcessDefinition = parsed.definition
	definition.definition_id = source.definition_id
	definition.revision = source.revision
	definition.display_name_zh = source.display_name_zh
	definition.process_family = source.process_family
	definition.duration_units = source.duration_units
	definition.capability_ids = source.capability_ids
	definition.facility_target = GMStableData.clone(source.facility_target)
	definition.completion_kind = source.completion_kind
	definition.completion_payload = source.completion_payload.duplicate(true)
	definition.task_definition_id = source.task_definition_id
	definition.duty_provider_id = source.duty_provider_id
	if not save_path.is_empty():
		var save_error := ResourceSaver.save(definition, save_path)
		if save_error != OK: return _failure("p20.workbench.save_failed", "ProcessDefinition Resource 保存失败。", {"error": save_error, "path": save_path})
	return {"ok": true, "path": save_path}

static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"schema_version": RESULT_SCHEMA, "ok": false, "code": code, "reason_zh": reason_zh, "direct_store_write": false}
	if not details.is_empty(): result["details"] = details
	return result
