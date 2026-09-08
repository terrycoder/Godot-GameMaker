class_name GMCueRouter
extends RefCounted

## 统一 Gameplay Cue 路由。它只记录和通知语义，不拥有任何规则状态。

signal cue_routed(cue: Dictionary)

var definitions: Dictionary = {}
var listeners: Array[Callable] = []
var log: Array[Dictionary] = []
var missing_optional: Array[Dictionary] = []
var missing_required: Array[Dictionary] = []

func register_definition(definition: GMCueDefinition) -> Dictionary:
	if definition == null: return _failure("cue.definition_missing", "不能注册空 Cue 定义。")
	var check := definition.validate()
	if not check.ok: return check
	if definitions.has(definition.cue_id) and definitions[definition.cue_id] != definition: return _failure("cue.definition_duplicate", "Cue 定义重复注册：%s。" % definition.cue_id)
	definitions[definition.cue_id] = definition
	return {"ok": true, "cue_id": definition.cue_id}

func add_listener(listener: Callable) -> Dictionary:
	if not listener.is_valid(): return _failure("cue.listener_invalid", "Cue 监听器无效。")
	if not listeners.has(listener): listeners.append(listener)
	return {"ok": true}

func route(parameters: GMCueParameters, required_override: bool = false) -> Dictionary:
	if parameters == null: return _failure("cue.missing", "不能路由空 Gameplay Cue。")
	if parameters.cue_id.strip_edges().is_empty(): return _failure("cue.id_missing", "Gameplay Cue 缺少稳定 ID。")
	var definition: GMCueDefinition = definitions.get(parameters.cue_id, null)
	var required := required_override or (definition != null and definition.required)
	if definition == null:
		var missing := {"cue_id": parameters.cue_id, "stage": parameters.stage, "required": required, "reason_zh": "Cue 定义未注册：%s。" % parameters.cue_id}
		if required: missing_required.append(missing)
		else: missing_optional.append(missing)
		return {"ok": false, "code": "cue.required_missing" if required else "cue.optional_missing", "reason_zh": missing.reason_zh, "logic_unchanged": true, "cue": parameters.to_dict()}
	if not definition.supports_stage(parameters.stage): return _failure("cue.stage_invalid", "Cue 定义不允许当前阶段：%s → %s。" % [parameters.cue_id, parameters.stage])
	var snapshot := parameters.to_dict()
	snapshot["definition"] = definition.to_summary()
	snapshot["required"] = required
	log.append(snapshot.duplicate(true))
	cue_routed.emit(snapshot)
	for listener in listeners.duplicate():
		if listener.is_valid(): listener.call(snapshot.duplicate(true))
	return {"ok": true, "cue": snapshot, "logic_unchanged": true}

func validate_required_content() -> Dictionary:
	var errors: Array[Dictionary] = []
	for entry in missing_required: errors.append(entry.duplicate(true))
	return {"ok": errors.is_empty(), "code": "cue.content_valid" if errors.is_empty() else "cue.content_invalid", "errors": errors, "optional_missing": missing_optional.duplicate(true)}

func snapshot() -> Dictionary:
	return {"registered_ids": definitions.keys(), "log": log.duplicate(true), "missing_optional": missing_optional.duplicate(true), "missing_required": missing_required.duplicate(true)}

func _failure(code: String, reason_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh}
