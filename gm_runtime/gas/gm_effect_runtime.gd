class_name GMEffectRuntime
extends RefCounted

## 唯一 GameplayEffect 运行时。
## Definition 只描述内容，Spec 只描述一次应用，所有可变状态都落在 ActiveEffect。
## 该类不创建协程；调度推进由 GMAbilitySystemHost 显式调用，因此可以被真实存档/重开。

const MAX_PERIOD_TICKS_PER_ADVANCE := 4096

var host: Object
var effect_log: Array[Dictionary] = []
var last_error: Dictionary = {}

func _init(p_host: Object = null) -> void:
	host = p_host

func register_definition(definition: GMEffectDefinition) -> Dictionary:
	if definition == null: return _error("effect.definition_missing", "不能注册空 GameplayEffect 定义。")
	var check := definition.validate()
	if not check.ok: return check
	if host == null: return _error("effect.host_missing", "GameplayEffect 运行时缺少宿主。")
	if not host.effect_definitions.has(definition.effect_id):
		host.effect_definitions[definition.effect_id] = definition
		return {"ok": true, "effect_id": definition.effect_id, "registered": true}
	if host.effect_definitions[definition.effect_id] != definition:
		return _error("effect.definition_duplicate", "GameplayEffect 定义重复注册：%s。" % definition.effect_id)
	return {"ok": true, "effect_id": definition.effect_id, "registered": false}

func apply_effect(definition: GMEffectDefinition, spec: GMEffectSpec = null, owner_instance: Object = null) -> Dictionary:
	if definition == null: return _error("effect.definition_missing", "应用 GameplayEffect 缺少定义。")
	var definition_check := definition.validate()
	if not definition_check.ok: return definition_check
	if host == null or host.attribute_set == null or host.tags == null: return _error("effect.host_incomplete", "GameplayEffect 宿主缺少属性集或标签容器。")
	var registered := register_definition(definition)
	if not registered.ok: return registered
	var safe_spec := spec if spec != null else GMEffectSpec.new(definition)
	safe_spec.definition = definition
	if safe_spec.source_id.is_empty():
		safe_spec.configure_identity(_host_identity(), _host_identity(), safe_spec.context)
	if safe_spec.target_id.is_empty(): safe_spec.target_id = _host_identity()
	if safe_spec.source.is_empty(): safe_spec.source = safe_spec.source_id
	if safe_spec.target.is_empty(): safe_spec.target = safe_spec.target_id
	var immunity := _check_immunity(definition)
	if not immunity.ok: return immunity
	var cue_check := _route_definition_cue(definition, "execute", safe_spec, owner_instance)
	if not cue_check.ok and not bool(cue_check.get("optional_missing", false)): return cue_check
	if definition.is_instant():
		var instant := _apply_instant_modifiers(definition, safe_spec)
		if not instant.ok: return instant
		effect_log.append({"action": "execute", "effect_id": definition.effect_id, "source_id": safe_spec.source_id, "target_id": safe_spec.target_id, "kind": "instant", "result": instant.duplicate(true)})
		return {"ok": true, "kind": "instant", "effect_id": definition.effect_id, "spec": safe_spec.to_summary(), "changed": instant.get("changed", []), "cue": cue_check}

	var existing: Array[GMActiveEffect] = _matching_effects(definition.effect_id, safe_spec.source_id, safe_spec.target_id)
	var policy := definition._normalized_stack_policy()
	if not existing.is_empty():
		var selected: GMActiveEffect = existing[0]
		match policy:
			"ignore":
				return {"ok": true, "ignored": true, "effect_id": definition.effect_id, "active_effect_id": selected.active_effect_id, "reason_zh": "相同来源的 GameplayEffect 已存在，按忽略策略保留旧实例。"}
			"strongest":
				if _effect_strength(safe_spec, definition) <= _effect_strength(selected.effect_spec, definition):
					return {"ok": true, "ignored": true, "strongest": true, "effect_id": definition.effect_id, "active_effect_id": selected.active_effect_id, "reason_zh": "新 GameplayEffect 强度不高于当前实例。"}
				_remove_effect_internal(selected, "被更强效果覆盖", false, owner_instance)
			"replace":
				for old in existing: _remove_effect_internal(old, "被新效果覆盖", false, owner_instance)
			"add_stacks":
				return _add_stack_to_existing(selected, safe_spec, definition, owner_instance)
			"refresh":
				return _refresh_existing(selected, definition, safe_spec, owner_instance)
			_:
				if policy != "independent":
					return _error("effect.stack_policy_invalid", "GameplayEffect 叠层策略无效：%s。" % policy)

	var active := GMActiveEffect.new(safe_spec)
	active.effect_definition_id = definition.effect_id
	active.source_id = safe_spec.source_id
	active.target_id = safe_spec.target_id
	active.persisted = definition.persist
	active.created_scheduler = host.scheduler.snapshot() if host.scheduler != null else {}
	active.remaining_units = _duration_value(definition)
	active.remaining_seconds = active.remaining_units if definition.duration_unit == "seconds" else 0.0
	active.period_remaining = _period_value(definition)
	active.paused = false
	var contribution := _apply_contribution(active, definition, owner_instance)
	if not contribution.ok: return contribution
	host.active_effects.append(active)
	effect_log.append({"action": "add", "effect_id": definition.effect_id, "active_effect_id": active.active_effect_id, "source_id": active.source_id, "target_id": active.target_id, "stack_count": active.stack_count})
	return {"ok": true, "kind": definition._normalized_kind(), "effect_id": definition.effect_id, "active_effect_id": active.active_effect_id, "stack_count": active.stack_count, "remaining_units": active.remaining_units, "cue": cue_check}

func remove_effect(active_effect_id: String, reason_zh: String = "GameplayEffect 被移除。", owner_instance: Object = null) -> Dictionary:
	if host == null: return _error("effect.host_missing", "移除 GameplayEffect 缺少宿主。")
	for active in host.active_effects.duplicate():
		if active != null and active.active_effect_id == active_effect_id:
			return _remove_effect_internal(active, reason_zh, true, owner_instance)
	return {"ok": false, "code": "effect.already_removed", "reason_zh": "GameplayEffect 已经移除或不存在：%s。" % active_effect_id, "already_removed": true, "active_effect_id": active_effect_id}

func remove_source(source_id: String, reason_zh: String = "来源撤销，GameplayEffect 被移除。") -> Dictionary:
	var removed: Array[Dictionary] = []
	for active in host.active_effects.duplicate():
		if active != null and active.source_id == source_id:
			var definition: GMEffectDefinition = active.effect_spec.definition if active.effect_spec != null else null
			if definition != null and definition.remove_on_source_lost: removed.append(_remove_effect_internal(active, reason_zh, true, null))
	return {"ok": true, "source_id": source_id, "removed": removed}

func set_source_alive(source_id: String, alive: bool) -> Dictionary:
	var changed: Array[Dictionary] = []
	for active in host.active_effects.duplicate():
		if active == null or active.source_id != source_id: continue
		active.source_alive = alive
		if not alive and active.effect_spec != null and active.effect_spec.definition != null and active.effect_spec.definition.remove_on_source_lost:
			changed.append(_remove_effect_internal(active, "来源已死亡或撤销，GameplayEffect 自动移除。", true, null))
	return {"ok": true, "source_id": source_id, "alive": alive, "changes": changed}

func pause_effect(active_effect_id: String, paused: bool = true) -> Dictionary:
	for active in host.active_effects:
		if active != null and active.active_effect_id == active_effect_id:
			active.paused = paused
			return {"ok": true, "active_effect_id": active_effect_id, "paused": paused}
	return {"ok": false, "code": "effect.missing", "reason_zh": "GameplayEffect 不存在：%s。" % active_effect_id}

func advance(amount: float, unit: String = "auto", scheduler_result: Dictionary = {}) -> Dictionary:
	if host == null: return _error("effect.host_missing", "推进 GameplayEffect 缺少宿主。")
	if not scheduler_result.is_empty() and not bool(scheduler_result.get("advanced", false)):
		return {"ok": true, "advanced": false, "paused": bool(scheduler_result.get("paused", false)), "updates": []}
	var updates: Array[Dictionary] = []
	for active in host.active_effects.duplicate():
		if active == null or not active.is_active() or active.paused: continue
		var definition: GMEffectDefinition = active.effect_spec.definition if active.effect_spec != null else null
		if definition == null:
			updates.append(_remove_effect_internal(active, "效果定义缺失，安全移除。", true, null))
			continue
		if not active.source_alive and definition.remove_on_source_lost:
			updates.append(_remove_effect_internal(active, "来源已失效，安全移除。", true, null))
			continue
		if definition.remove_on_target_death and _target_is_dead(active):
			updates.append(_remove_effect_internal(active, "目标已死亡，安全移除。", true, null))
			continue
		var delta := _delta_for_effect(definition, amount, unit)
		if delta <= 0.0: continue
		var update := {"active_effect_id": active.active_effect_id, "effect_id": active.effect_definition_id, "delta": delta, "ticks": 0, "removed": false}
		if definition._normalized_kind() != "infinite":
			active.remaining_units -= delta
			if definition.duration_unit == "seconds": active.remaining_seconds = active.remaining_units
		if definition._normalized_kind() == "periodic" or (not definition.periodic_modifiers.is_empty() and definition.period_seconds > 0.0):
			var period_delta := _delta_for_period(definition, amount, unit)
			active.period_remaining -= period_delta
			var guard := 0
			while active.period_remaining <= 0.0 and definition.period_seconds > 0.0 and guard < MAX_PERIOD_TICKS_PER_ADVANCE:
				var tick := _apply_periodic_tick(active, definition)
				if not tick.ok:
					update["error"] = tick
					break
				active.tick_index += 1
				update["ticks"] = int(update["ticks"]) + 1
				active.period_remaining += _period_value(definition)
				guard += 1
			if guard >= MAX_PERIOD_TICKS_PER_ADVANCE: update["period_guard_exceeded"] = true
		if active.is_expired():
			var removal := _remove_effect_internal(active, "GameplayEffect 持续时间已结束。", true, null)
			update["removed"] = true
			update["removal"] = removal
		updates.append(update)
	return {"ok": true, "advanced": true, "unit": unit, "amount": amount, "updates": updates, "active_count": host.active_effects.size()}

func snapshot(include_non_persisted: bool = false) -> Dictionary:
	var effects: Array[Dictionary] = []
	for active in host.active_effects:
		if active == null or not active.is_active(): continue
		if include_non_persisted or active.persisted: effects.append(active.to_summary())
	return {"schema_version": "gm.effect_runtime.v2", "effects": effects, "effect_log": effect_log.duplicate(true)}

func restore_snapshot(value: Dictionary, migration_table: Dictionary = {}) -> Dictionary:
	if str(value.get("schema_version", "")) not in ["gm.effect_runtime.v2", "gm.effect_runtime.v1"]:
		return _error("persistence.effect_schema_invalid", "GameplayEffect 存档版本不受支持。")
	var saved: Variant = value.get("effects", [])
	if not saved is Array: return _error("persistence.effect_records_invalid", "GameplayEffect 存档记录不是数组。")
	var precheck: Array[Dictionary] = []
	for row in saved:
		if not row is Dictionary: return _error("persistence.effect_record_invalid", "GameplayEffect 存档包含非对象记录。")
		var effect_id := str(row.get("effect_id", ""))
		var definition: GMEffectDefinition = host.effect_definitions.get(effect_id, null)
		if definition == null:
			return _migration_error("persistence.effect_definition_missing", "存档引用的 GameplayEffect 定义缺失：%s。" % effect_id, effect_id, migration_table)
		var saved_effect: Dictionary = row.get("effect", {}) if row.get("effect", {}) is Dictionary else {}
		var source_id := str(row.get("source_id", saved_effect.get("source_id", ""))).strip_edges()
		if source_id.is_empty():
			return _migration_error("persistence.source_missing", "存档引用的 GameplayEffect 来源身份缺失：%s。" % effect_id, effect_id, migration_table, {"source_id": source_id})
		var saved_definition: Dictionary = saved_effect.get("definition", {}) if saved_effect.get("definition", {}) is Dictionary else {}
		var saved_version := str(saved_definition.get("content_version", definition.content_version))
		if saved_version != definition.content_version and not migration_table.has(effect_id):
			return _migration_error("persistence.content_version_mismatch", "GameplayEffect 内容版本发生变化，缺少显式迁移规则：%s（%s→%s）。" % [effect_id, saved_version, definition.content_version], effect_id, migration_table, {"from": saved_version, "to": definition.content_version})
		precheck.append(row)
	for active in host.active_effects.duplicate():
		if active != null: _remove_effect_internal(active, "恢复存档前清理旧效果。", false, null)
	host.active_effects.clear()
	for row in precheck:
		var restored := GMActiveEffect.from_summary(row, host.effect_definitions)
		var definition: GMEffectDefinition = host.effect_definitions.get(restored.effect_definition_id, null)
		if definition == null: return _error("persistence.effect_definition_missing", "恢复时找不到 GameplayEffect 定义：%s。" % restored.effect_definition_id)
		# AttributeSet snapshot and ActiveEffect snapshot both carry the same
		# contribution. Remove the serialized handles before rebuilding the
		# authoritative ActiveEffect contribution, otherwise restore would look
		# like a duplicate modifier instead of a round-trip.
		for handle in restored.applied_modifier_handles:
			if host.attribute_set.modifier_records.has(str(handle)): host.attribute_set.remove_modifier(str(handle))
		if host.tags != null and not restored.granted_tag_source.is_empty(): host.tags.remove_source(restored.granted_tag_source)
		# Loading state reconstructs an already committed contribution.  It must
		# neither emit a new success Cue nor depend on a live presentation target.
		var contribution := _apply_contribution(restored, definition, null, false)
		if not contribution.ok:
			host.active_effects.clear()
			return contribution
		host.active_effects.append(restored)
	effect_log.clear()
	var raw_log: Variant = value.get("effect_log", [])
	if raw_log is Array:
		for raw_entry in raw_log:
			if raw_entry is Dictionary: effect_log.append(raw_entry.duplicate(true))
	return {"ok": true, "restored": precheck.size(), "active_count": host.active_effects.size()}

func active_by_id(active_effect_id: String) -> GMActiveEffect:
	for active in host.active_effects:
		if active != null and active.active_effect_id == active_effect_id: return active
	return null

func _add_stack_to_existing(active: GMActiveEffect, spec: GMEffectSpec, definition: GMEffectDefinition, owner_instance: Object) -> Dictionary:
	var next_stack := mini(active.stack_count + 1, definition.max_stacks)
	if next_stack == active.stack_count: return {"ok": true, "ignored": true, "max_stacks": true, "active_effect_id": active.active_effect_id, "stack_count": active.stack_count}
	_clear_contribution(active, definition)
	active.stack_count = next_stack
	var contribution := _apply_contribution(active, definition, owner_instance)
	if not contribution.ok:
		active.stack_count -= 1
		_apply_contribution(active, definition, owner_instance)
		return contribution
	return {"ok": true, "stacked": true, "active_effect_id": active.active_effect_id, "stack_count": active.stack_count}

func _refresh_existing(active: GMActiveEffect, definition: GMEffectDefinition, _spec: GMEffectSpec, owner_instance: Object) -> Dictionary:
	active.remaining_units = _duration_value(definition)
	active.remaining_seconds = active.remaining_units if definition.duration_unit == "seconds" else active.remaining_seconds
	if definition._normalized_kind() == "periodic": active.period_remaining = _period_value(definition)
	var cue := _route_definition_cue(definition, "add", active.effect_spec, owner_instance)
	if not cue.ok and not bool(cue.get("optional_missing", false)): return cue
	return {"ok": true, "refreshed": true, "active_effect_id": active.active_effect_id, "stack_count": active.stack_count, "remaining_units": active.remaining_units, "cue": cue}

func _apply_contribution(active: GMActiveEffect, definition: GMEffectDefinition, owner_instance: Object, route_cue: bool = true) -> Dictionary:
	active.applied_modifier_handles.clear()
	active.granted_tag_source = active.active_effect_id
	for row in definition.normalized_modifiers(false):
		var attribute_id := str(row.get("attribute_id", row.get("attribute", "")))
		var modifier_type := str(row.get("type", row.get("operation", "add")))
		var value: Variant = row.get("value", row.get("amount", 0.0))
		var stacks := maxi(int(row.get("stacks", 1)), 1) * active.stack_count
		var handle := "%s.%s.%d" % [active.active_effect_id, _slug(attribute_id), active.applied_modifier_handles.size() + 1]
		var added: Dictionary = host.attribute_set.add_modifier(attribute_id, modifier_type, value, active.active_effect_id, stacks, handle)
		if not added.ok:
			_clear_contribution(active, definition)
			return added
		active.applied_modifier_handles.append(handle)
	for tag_value in definition.granted_tags:
		var tagged: Dictionary = host.tags.add_tag(str(tag_value), active.granted_tag_source)
		if not tagged.ok:
			_clear_contribution(active, definition)
			return tagged
	var cue := {"ok": true, "skipped": true, "restore": not route_cue}
	if route_cue:
		cue = _route_definition_cue(definition, "add", active.effect_spec, owner_instance)
		if not cue.ok and not bool(cue.get("optional_missing", false)):
			_clear_contribution(active, definition)
			return cue
	return {"ok": true, "modifier_handles": active.applied_modifier_handles.duplicate(), "cue": cue}

func _clear_contribution(active: GMActiveEffect, definition: GMEffectDefinition) -> void:
	for handle in active.applied_modifier_handles.duplicate(): host.attribute_set.remove_modifier(str(handle))
	active.applied_modifier_handles.clear()
	if host.tags != null and not active.granted_tag_source.is_empty(): host.tags.remove_source(active.granted_tag_source)

func _remove_effect_internal(active: GMActiveEffect, reason_zh: String, emit_cue: bool, owner_instance: Object) -> Dictionary:
	if active == null: return {"ok": false, "code": "effect.missing", "reason_zh": "GameplayEffect 实例不存在。"}
	if not active.is_active(): return {"ok": false, "code": "effect.already_removed", "reason_zh": "GameplayEffect 已经移除。", "already_removed": true}
	var definition: GMEffectDefinition = active.effect_spec.definition if active.effect_spec != null else null
	if definition != null: _clear_contribution(active, definition)
	active.state = "REMOVED"
	active.remove_reason_zh = reason_zh
	if host.active_effects.has(active): host.active_effects.erase(active)
	var cue: Dictionary = {"ok": true, "skipped": true}
	if emit_cue and definition != null: cue = _route_definition_cue(definition, "remove", active.effect_spec, owner_instance)
	effect_log.append({"action": "remove", "effect_id": active.effect_definition_id, "active_effect_id": active.active_effect_id, "reason_zh": reason_zh, "cue": cue})
	return {"ok": true, "removed": true, "active_effect_id": active.active_effect_id, "effect_id": active.effect_definition_id, "reason_zh": reason_zh, "cue": cue}

func _apply_instant_modifiers(definition: GMEffectDefinition, spec: GMEffectSpec) -> Dictionary:
	var changed: Array[Dictionary] = []
	for row in definition.normalized_modifiers(false):
		var attribute_id := str(row.get("attribute_id", row.get("attribute", "")))
		var modifier_type := str(row.get("type", row.get("operation", "add"))).to_lower()
		var amount: Variant = row.get("value", row.get("amount", 0.0))
		var numeric := _instant_delta(attribute_id, modifier_type, amount)
		if not numeric.ok: return numeric
		var result: Dictionary = host.attribute_set.apply_delta(attribute_id, numeric.delta, spec.source_id, "执行瞬时 GameplayEffect：%s。" % definition.effect_id)
		if not result.ok: return result
		changed.append(result)
	return {"ok": true, "changed": changed}

func _apply_periodic_tick(active: GMActiveEffect, definition: GMEffectDefinition) -> Dictionary:
	# A required execute Cue is a content gate. Route it before the tick so a
	# missing mandatory presentation cannot leave a partial gameplay mutation.
	if definition.execute_cue_id != "":
		var cue := _route_definition_cue(definition, "execute", active.effect_spec, null)
		if not cue.ok and not bool(cue.get("optional_missing", false)): return cue
	var rows := definition.normalized_modifiers(true)
	if rows.is_empty(): rows = definition.normalized_modifiers(false) if bool(definition.metadata.get("periodic_reuses_modifiers", false)) else []
	var changed: Array[Dictionary] = []
	for row in rows:
		var attribute_id := str(row.get("attribute_id", row.get("attribute", "")))
		var modifier_type := str(row.get("type", row.get("operation", "add"))).to_lower()
		var numeric := _instant_delta(attribute_id, modifier_type, row.get("value", row.get("amount", 0.0)))
		if not numeric.ok: return numeric
		var result: Dictionary = host.attribute_set.apply_delta(attribute_id, numeric.delta * active.stack_count, active.active_effect_id, "周期 GameplayEffect tick #%d。" % (active.tick_index + 1))
		if not result.ok: return result
		changed.append(result)
	return {"ok": true, "changed": changed}

func _instant_delta(attribute_id: String, modifier_type: String, amount: Variant) -> Dictionary:
	if not host.attribute_set.definitions.has(attribute_id): return _error("attribute.missing", "GameplayEffect 引用了缺失属性：%s。" % attribute_id)
	if typeof(amount) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(amount)) or is_inf(float(amount)):
		return _error("effect.value_invalid", "GameplayEffect 数值不能是 NaN 或无穷值：%s。" % attribute_id)
	var current: Variant = host.attribute_set.get_value(attribute_id, null)
	if typeof(current) not in [TYPE_INT, TYPE_FLOAT]: return _error("attribute.type_mismatch", "瞬时 GameplayEffect 只能修改数值属性：%s。" % attribute_id)
	var value := float(amount)
	match modifier_type:
		"add", "flat", "delta": return {"ok": true, "delta": value}
		"percent_add", "percent": return {"ok": true, "delta": float(current) * value}
		"multiply", "final_multiplier": return {"ok": true, "delta": float(current) * (value - 1.0)}
		"override": return {"ok": true, "delta": value - float(current)}
	return _error("effect.modifier_type_invalid", "瞬时 GameplayEffect 修正器类型无效：%s。" % modifier_type)

func _route_definition_cue(definition: GMEffectDefinition, stage: String, spec: GMEffectSpec, owner_instance: Object) -> Dictionary:
	var cue_id := ""
	var required := false
	match stage:
		"execute": cue_id = definition.execute_cue_id; required = definition.execute_cue_required
		"add": cue_id = definition.add_cue_id; required = definition.add_cue_required
		"remove": cue_id = definition.remove_cue_id; required = definition.remove_cue_required
	if cue_id.is_empty(): return {"ok": true, "skipped": true}
	var parameters := GMCueParameters.new(cue_id, host.entity, {"effect_id": definition.effect_id, "stage": stage, "value": spec.overrides.get("value", null) if spec != null else null, "tags": Array(definition.granted_tags), "context": spec.context if spec != null else {}})
	parameters.stage = stage
	parameters.source = spec.source_object if spec != null else null
	parameters.source_id = spec.source_id if spec != null else ""
	parameters.target = spec.target_object if spec != null else host.entity
	parameters.target_id = spec.target_id if spec != null else _host_identity()
	parameters.context["required"] = required
	var result: Dictionary = host.emit_cue(parameters, owner_instance)
	if not result.ok and not required and str(result.get("code", "")) == "cue.optional_missing": result["optional_missing"] = true
	return result

func _check_immunity(definition: GMEffectDefinition) -> Dictionary:
	for tag_value in definition.immunity_tags:
		if host.tags.matches(str(tag_value), "hierarchy"):
			return {"ok": false, "code": "effect.immune", "reason_zh": "目标拥有 GameplayEffect 免疫标签：%s。" % tag_value, "effect_id": definition.effect_id}
	return {"ok": true}

func _matching_effects(effect_id: String, source_id: String, target_id: String) -> Array[GMActiveEffect]:
	var result: Array[GMActiveEffect] = []
	for active in host.active_effects:
		if active != null and active.is_active() and active.effect_definition_id == effect_id and active.source_id == source_id and active.target_id == target_id: result.append(active)
	return result

func _effect_strength(spec: GMEffectSpec, definition: GMEffectDefinition) -> float:
	if spec != null and spec.overrides.has("strength"): return float(spec.overrides.get("strength", 0.0))
	if definition.metadata.has("strength"): return float(definition.metadata.get("strength", 0.0))
	var strongest := 0.0
	for row in definition.normalized_modifiers(false): strongest = maxf(strongest, absf(float(row.get("value", row.get("amount", 0.0)))))
	return strongest * float(spec.level if spec != null else 1)

func _duration_value(definition: GMEffectDefinition) -> float:
	return maxf(definition.duration_for(host.scheduler.mode if host.scheduler != null else "realtime"), 0.0)

func _period_value(definition: GMEffectDefinition) -> float:
	return maxf(definition.period_for(host.scheduler.mode if host.scheduler != null else "realtime"), 0.0)

func _delta_for_effect(definition: GMEffectDefinition, amount: float, unit: String) -> float:
	var effect_unit := definition.duration_unit.strip_edges().to_lower()
	if effect_unit == "auto" or effect_unit.is_empty(): effect_unit = "turns" if host.scheduler != null and host.scheduler.mode == "turn" else "seconds"
	return _convert_delta(amount, unit, effect_unit)

func _delta_for_period(definition: GMEffectDefinition, amount: float, unit: String) -> float:
	var effect_unit := definition.period_unit.strip_edges().to_lower()
	if effect_unit == "auto" or effect_unit.is_empty(): effect_unit = "turns" if host.scheduler != null and host.scheduler.mode == "turn" else "seconds"
	return _convert_delta(amount, unit, effect_unit)

func _convert_delta(amount: float, source_unit: String, target_unit: String) -> float:
	var source := source_unit if source_unit != "auto" and not source_unit.is_empty() else ("turns" if host.scheduler != null and host.scheduler.mode == "turn" else "seconds")
	if source == target_unit: return maxf(amount, 0.0)
	if source == "physics_frames" and target_unit == "seconds": return maxf(amount, 0.0) / 60.0
	if source == "seconds" and target_unit == "physics_frames": return maxf(amount, 0.0) * 60.0
	return 0.0

func _target_is_dead(active: GMActiveEffect) -> bool:
	var target: Object = active.effect_spec.target_object if active.effect_spec != null else null
	if target == null: target = host.entity
	return _object_bool(target, "is_dead", false) or not _object_bool(target, "is_alive", true)

func _object_bool(value: Object, property_name: String, default_value: bool) -> bool:
	if value == null or not is_instance_valid(value): return default_value
	for property in value.get_property_list():
		if str(property.get("name", "")) == property_name: return bool(value.get(property_name))
	return default_value

func _host_identity() -> String:
	if host != null and host.entity != null: return GMEffectSpec.stable_identity(host.entity)
	return "gm.host"

func _migration_error(code: String, reason_zh: String, effect_id: String, migration_table: Dictionary, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh, "effect_id": effect_id, "migration_required": true, "migration_table_key": effect_id, "details": details.duplicate(true)}
	result["known_migrations"] = migration_table.keys()
	return result

func _error(code: String, reason_zh: String) -> Dictionary:
	last_error = {"ok": false, "code": code, "reason_zh": reason_zh}
	return last_error.duplicate(true)

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in raw.length():
		var code := raw.unicode_at(index)
		result += raw.substr(index, 1) if ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45) else "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_") if not result.is_empty() else "effect"
