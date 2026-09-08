class_name GMCommandBuffer
extends RefCounted

## 每个系统绑定一个不可变快照的写入缓冲；提交阶段前不触碰注册表。

var system_id: String = ""
var stage: int = 0
var priority: int = 0
var tick: int = 0
var snapshot_id: String = ""
var budget_units: int = 0
var used_units: int = 0
var closed: bool = false
var _sequence: int = 0
var _commands: Array = []
var _seen_idempotency: Dictionary = {}

func _init(p_system_id: String, snapshot: GMWorldSnapshot, p_stage: int = 0, p_priority: int = 0, p_budget_units: int = 0) -> void:
	system_id = p_system_id.strip_edges()
	stage = p_stage
	priority = p_priority
	if snapshot != null:
		tick = snapshot.tick
		snapshot_id = snapshot.snapshot_id
	budget_units = maxi(p_budget_units, 0)

func submit(operation: String, entity_id: String, payload: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	if closed: return _reject("command.closed", "命令缓冲已经关闭，不能继续写入。")
	var identity := GMEntityId.validate_value(entity_id)
	if not identity.ok: return _reject("command.entity_invalid", "命令缺少有效实体身份。", identity.errors)
	var stable := GMStableData.validate(payload)
	if not stable.ok: return _reject("command.payload_invalid", "命令载荷不得包含运行时对象。", stable.errors)
	var options_check := GMStableData.validate(options)
	if not options_check.ok: return _reject("command.options_invalid", "命令选项不得包含运行时对象。", options_check.errors)
	var resolution := str(options.get("resolution", GMResolutionState.ACTIVE))
	var resolution_check := GMResolutionState.command_allowed(resolution, operation, payload)
	if not resolution_check.ok: return resolution_check
	var cost := maxi(int(options.get("cost", 1)), 1)
	if budget_units > 0 and used_units + cost > budget_units:
		return _reject("command.budget_exceeded", "系统命令预算已用尽，命令被隔离。", [{"budget": budget_units, "used": used_units, "cost": cost}])
	_sequence += 1
	var command_id := "gm.command.%06d.%s.%04d" % [tick, _slug(system_id), _sequence]
	var idempotency_key := str(options.get("idempotency_key", command_id))
	if idempotency_key.is_empty(): return _reject("command.idempotency_missing", "命令缺少幂等键。")
	var command := {
		"schema_version": "gm.command.v1",
		"command_id": command_id,
		"idempotency_key": idempotency_key,
		"system_id": system_id,
		"stage": stage,
		"priority": priority,
		"tick": tick,
		"snapshot_id": snapshot_id,
		"sequence": _sequence,
		"operation": operation.strip_edges(),
		"entity_id": entity_id,
		"resolution": resolution,
		"expected_version": int(options.get("expected_version", -1)),
		"write_keys": _write_keys(entity_id, options),
		"payload": GMStableData.clone(payload),
		"cost": cost
	}
	if _seen_idempotency.has(idempotency_key):
		var previous: Dictionary = _seen_idempotency[idempotency_key]
		if _same_intent(previous, command):
			return {"ok": true, "duplicate": true, "command_id": previous.command_id, "idempotency_key": idempotency_key}
		return _reject("command.idempotency_conflict", "同一命令幂等键对应了不同写入意图。")
	_seen_idempotency[idempotency_key] = command
	_commands.append(command)
	used_units += cost
	return {"ok": true, "command": GMStableData.clone(command), "command_id": command_id, "idempotency_key": idempotency_key}

func close() -> Dictionary:
	closed = true
	return {"ok": true, "system_id": system_id, "command_count": _commands.size(), "used_units": used_units, "commands": get_commands()}

func get_commands() -> Array:
	return GMStableData.clone(_commands)

func count() -> int:
	return _commands.size()

func _write_keys(entity_id: String, options: Dictionary) -> Array:
	var raw: Variant = options.get("write_keys", [])
	var keys: Array[String] = []
	if raw is Array:
		for value in raw:
			var key := str(value)
			if not key.is_empty() and not keys.has(key): keys.append(key)
	if keys.is_empty(): keys.append(entity_id)
	keys.sort()
	return keys

func _reject(code: String, reason_zh: String, errors: Array = []) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "errors": errors.duplicate(true)}

func _same_intent(left: Dictionary, right: Dictionary) -> bool:
	var left_copy := left.duplicate(true)
	var right_copy := right.duplicate(true)
	for key in ["command_id", "sequence", "system_id"]:
		left_copy.erase(key)
		right_copy.erase(key)
	return GMStableData.canonical_json(left_copy) == GMStableData.canonical_json(right_copy)

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in raw.length():
		var code := raw.unicode_at(index)
		result += raw.substr(index, 1) if ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45) else "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_") if not result.is_empty() else "system"
