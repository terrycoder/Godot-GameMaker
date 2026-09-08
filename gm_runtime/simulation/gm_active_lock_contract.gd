class_name GMActiveLockContract
extends RefCounted

## Neutral, typed projection for every condition that requires Active
## simulation resolution. Legacy flags are interpreted only here.

const COMBAT := "combat"
const STORY := "story"
const ABILITY := "ability"
const TRANSACTION := "transaction"
const EXPLICIT := "explicit"
const GENERIC := "generic"
const KNOWN_TYPES := [COMBAT, STORY, ABILITY, TRANSACTION, EXPLICIT, GENERIC]

static func project(flags: Dictionary) -> Dictionary:
	var locks: Array[Dictionary] = []
	var typed_value: Variant = flags.get("active_locks", [])
	if not typed_value is Array:
		return _failure("resolution.active_locks_invalid", "active_locks必须是类型化数组。")
	for value in typed_value:
		var lock := _normalize_lock(value, "active_locks")
		if not lock.ok: return lock
		_append_unique(locks, lock.lock)
	var legacy_value: Variant = flags.get("resolution_locks", [])
	if not legacy_value is Array:
		return _failure("resolution.legacy_locks_invalid", "resolution_locks兼容字段必须是数组。")
	for value in legacy_value:
		var lock := _normalize_lock(value, "resolution_locks")
		if not lock.ok: return lock
		_append_unique(locks, lock.lock)
	var adapters := {
		"in_combat": COMBAT,
		"story_locked": STORY,
		"active_ability": ABILITY,
		"pending_transaction": TRANSACTION,
		"must_be_active": EXPLICIT,
	}
	for flag_name in adapters:
		if not flags.has(flag_name): continue
		if not flags[flag_name] is bool:
			return _failure("resolution.legacy_flag_invalid", "Active锁兼容字段必须是布尔值：%s" % flag_name)
		if bool(flags[flag_name]):
			_append_unique(locks, {"type": adapters[flag_name], "source": flag_name})
	return {"ok": true, "locks": locks, "active_required": not locks.is_empty(), "contract": "gm.active_lock.v1"}

static func _normalize_lock(value: Variant, source: String) -> Dictionary:
	var lock_type := ""
	var lock_source := source
	if value is Dictionary:
		for key in value.keys():
			if str(key) not in ["type", "source"]: return _failure("resolution.lock_field_unknown", "Active锁对象包含未知字段：%s" % key)
		if not value.get("type", null) is String: return _failure("resolution.lock_type_invalid", "Active锁对象type必须是字符串。")
		if value.has("source") and not value.source is String: return _failure("resolution.lock_source_invalid", "Active锁对象source必须是字符串。")
		lock_type = str(value.get("type", "")).strip_edges().to_lower()
		lock_source = str(value.get("source", source)).strip_edges()
		if lock_source.is_empty(): return _failure("resolution.lock_source_invalid", "Active锁对象source不能为空。")
	elif value is String:
		var text := str(value).strip_edges().to_lower()
		if text == "gm.lock.active" or text == "generic": lock_type = GENERIC
		elif text.begins_with("gm.lock.active."): lock_type = text.trim_prefix("gm.lock.active.")
		else: lock_type = text
	else:
		return _failure("resolution.lock_type_invalid", "Active锁必须是字符串或类型化对象。")
	if not KNOWN_TYPES.has(lock_type):
		return _failure("resolution.lock_category_unknown", "未知Active锁类别，已失败关闭：%s" % lock_type)
	return {"ok": true, "lock": {"type": lock_type, "source": lock_source}}

static func _append_unique(locks: Array[Dictionary], lock: Dictionary) -> void:
	var identity := "%s|%s" % [lock.get("type", ""), lock.get("source", "")]
	for existing in locks:
		if "%s|%s" % [existing.get("type", ""), existing.get("source", "")] == identity: return
	locks.append(lock.duplicate(true))

static func _failure(code: String, reason_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "active_required": true, "fail_closed": true, "locks": []}
