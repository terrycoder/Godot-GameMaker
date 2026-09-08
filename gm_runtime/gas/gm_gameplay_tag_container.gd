class_name GMGameplayTagContainer
extends RefCounted

## 标签容器以“标签 -> 来源 -> 计数”保存状态，移除单一来源不会误删其他来源。

signal gameplay_event(event: GMGameplayEvent)

var registry: GMGameplayTagRegistry
var source_counts: Dictionary = {}
var event_log: Array[Dictionary] = []

func _init(p_registry: GMGameplayTagRegistry = null) -> void:
	registry = p_registry if p_registry != null else GMGameplayTagRegistry.create_default()

func add_tag(tag_value: String, source: String = "unknown", amount: int = 1) -> Dictionary:
	if amount <= 0:
		return {"ok": false, "code": "tag.invalid_count", "reason_zh": "GameplayTag 来源计数必须大于 0。"}
	if source.strip_edges().is_empty():
		return {"ok": false, "code": "tag.source_empty", "reason_zh": "GameplayTag 来源不能为空。"}
	var resolved := registry.resolve(tag_value)
	if not resolved.ok:
		return resolved
	var canonical := str(resolved.canonical)
	if not source_counts.has(canonical): source_counts[canonical] = {}
	var counts: Dictionary = source_counts[canonical]
	counts[source] = int(counts.get(source, 0)) + amount
	source_counts[canonical] = counts
	_emit_change("add", canonical, source, amount)
	return {"ok": true, "tag": canonical, "source": source, "count": int(counts[source]), "total": total_count(canonical)}

func remove_tag(tag_value: String, source: String = "unknown", amount: int = 1) -> Dictionary:
	if amount <= 0:
		return {"ok": false, "code": "tag.invalid_count", "reason_zh": "GameplayTag 来源计数必须大于 0。"}
	var resolved := registry.resolve(tag_value)
	if not resolved.ok: return resolved
	var canonical := str(resolved.canonical)
	if not source_counts.has(canonical) or not source_counts[canonical].has(source):
		return {"ok": false, "code": "tag.source_missing", "reason_zh": "GameplayTag 没有该来源：%s ← %s" % [canonical, source]}
	var counts: Dictionary = source_counts[canonical]
	var before := int(counts[source])
	var removed := mini(before, amount)
	counts[source] = before - removed
	if int(counts[source]) <= 0: counts.erase(source)
	if counts.is_empty(): source_counts.erase(canonical)
	else: source_counts[canonical] = counts
	_emit_change("remove", canonical, source, removed)
	return {"ok": true, "tag": canonical, "source": source, "removed": removed, "remaining_source": int(counts.get(source, 0)), "total": total_count(canonical)}

func remove_source(source: String) -> Dictionary:
	var removed: Array[Dictionary] = []
	for tag_value in source_counts.keys().duplicate():
		if source_counts[tag_value].has(source):
			removed.append(remove_tag(str(tag_value), source, int(source_counts[tag_value][source])))
	return {"ok": true, "source": source, "removed": removed}

func has_exact(tag_value: String) -> bool:
	var resolved := registry.resolve(tag_value)
	return resolved.ok and source_counts.has(str(resolved.canonical))

func has_parent_match(tag_value: String) -> bool:
	var resolved := registry.resolve(tag_value)
	if not resolved.ok: return false
	var query := str(resolved.canonical)
	for stored in source_counts:
		if str(stored) == query or str(stored).begins_with(query + "."): return true
	return false

func has_ancestor_match(tag_value: String) -> bool:
	var resolved := registry.resolve(tag_value)
	if not resolved.ok: return false
	var query := str(resolved.canonical)
	for stored in source_counts:
		if query.begins_with(str(stored) + "."): return true
	return false

func matches(tag_value: String, mode: String = "exact") -> bool:
	match mode:
		"exact": return has_exact(tag_value)
		"parent": return has_parent_match(tag_value)
		"ancestor": return has_ancestor_match(tag_value)
		"hierarchy": return has_parent_match(tag_value) or has_ancestor_match(tag_value)
	return false

## 旧模拟 GAS 容器常用的兼容方法名。
func add(tag_value: String, source: String = "legacy", amount: int = 1) -> Dictionary:
	return add_tag(tag_value, source, amount)

func remove(tag_value: String, source: String = "legacy", amount: int = 1) -> Dictionary:
	return remove_tag(tag_value, source, amount)

func has(tag_value: String, include_parent: bool = false) -> bool:
	return has_parent_match(tag_value) if include_parent else has_exact(tag_value)

func total_count(tag_value: String) -> int:
	var resolved := registry.resolve(tag_value)
	if not resolved.ok: return 0
	var counts: Dictionary = source_counts.get(str(resolved.canonical), {})
	var total := 0
	for value in counts.values(): total += int(value)
	return total

func get_source_counts(tag_value: String) -> Dictionary:
	var resolved := registry.resolve(tag_value)
	if not resolved.ok: return {}
	return source_counts.get(str(resolved.canonical), {}).duplicate()

func get_tags() -> PackedStringArray:
	var tags := PackedStringArray()
	for tag_value in source_counts.keys(): tags.append(str(tag_value))
	tags.sort()
	return tags

func snapshot() -> Dictionary:
	return {"tags": Array(get_tags()), "source_counts": source_counts.duplicate(true), "event_count": event_log.size()}

func restore_snapshot(value: Dictionary) -> Dictionary:
	var raw_counts: Variant = value.get("source_counts", null)
	if not raw_counts is Dictionary: return {"ok": false, "code": "tag.snapshot_invalid", "reason_zh": "GameplayTag 存档缺少来源计数字典。"}
	var next: Dictionary = {}
	for raw_tag in raw_counts:
		var resolved := registry.resolve(str(raw_tag))
		if not resolved.ok: return {"ok": false, "code": "tag.snapshot_tag_invalid", "reason_zh": "GameplayTag 存档包含未注册标签：%s。" % raw_tag}
		var raw_sources: Variant = raw_counts[raw_tag]
		if not raw_sources is Dictionary: return {"ok": false, "code": "tag.snapshot_source_invalid", "reason_zh": "GameplayTag 来源计数格式无效：%s。" % raw_tag}
		var counts: Dictionary = {}
		for raw_source in raw_sources:
			var amount := int(raw_sources[raw_source])
			if amount <= 0: return {"ok": false, "code": "tag.snapshot_count_invalid", "reason_zh": "GameplayTag 来源计数必须为正：%s ← %s。" % [raw_tag, raw_source]}
			counts[str(raw_source)] = amount
		next[str(resolved.canonical)] = counts
	source_counts = next
	event_log.clear()
	var raw_events: Variant = value.get("event_log", [])
	if raw_events is Array:
		for raw_event in raw_events:
			if raw_event is Dictionary: event_log.append(raw_event.duplicate(true))
	return {"ok": true, "restored": true, "tag_count": source_counts.size()}

func _emit_change(action: String, tag_value: String, source: String, amount: int) -> void:
	var event := GMGameplayEvent.new("gm.event.tag.changed", null, null, {"action": action, "tag": tag_value, "source": source, "amount": amount, "total": total_count(tag_value)}, source)
	event_log.append(event.to_dict())
	gameplay_event.emit(event)
