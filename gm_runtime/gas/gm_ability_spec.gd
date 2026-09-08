class_name GMAbilitySpec
extends RefCounted

## 一个宿主内同能力的所有来源合并为一个 Spec；同来源再次授予采用升级合并策略。

const DUPLICATE_STRATEGY := "MERGE_BY_ABILITY_AND_SOURCE_UPGRADE"

var definition: GMAbilityDefinition
var ability_id: String = ""
var source_records: Dictionary = {}
var dynamic_tags: GMGameplayTagContainer
var created_at_usec: int = 0

func _init(p_definition: GMAbilityDefinition = null) -> void:
	definition = p_definition
	ability_id = p_definition.ability_id if p_definition != null else ""
	dynamic_tags = GMGameplayTagContainer.new()
	created_at_usec = Time.get_ticks_usec()

func validate_grant_request(source: String, _level: int = 1, _overrides: Dictionary = {}) -> Dictionary:
	if source.strip_edges().is_empty():
		return {"ok": false, "code": "spec.source_missing", "reason_zh": "能力 Spec 来源不能为空。"}
	return {"ok": true, "source": source}

func grant_source(source: String, level: int = 1, overrides: Dictionary = {}) -> Dictionary:
	var validation := validate_grant_request(source, level, overrides)
	if not validation.ok: return validation
	var safe_level := maxi(level, 1)
	var was_present := source_records.has(source)
	var previous: Dictionary = source_records.get(source, {})
	var next_level := maxi(int(previous.get("level", 0)), safe_level)
	var merged_overrides: Dictionary = previous.get("overrides", {}).duplicate(true)
	for key in overrides: merged_overrides[key] = overrides[key]
	var next_source_records := source_records.duplicate(true)
	next_source_records[source] = {"source": source, "level": next_level, "overrides": merged_overrides, "granted_at_usec": int(previous.get("granted_at_usec", Time.get_ticks_usec()))}
	source_records = next_source_records
	return {"ok": true, "source": source, "level": next_level, "upgraded": was_present and next_level > int(previous.get("level", 0)), "duplicate_strategy": DUPLICATE_STRATEGY}

func revoke_source(source: String) -> Dictionary:
	if not source_records.has(source):
		return {"ok": false, "code": "spec.source_missing", "reason_zh": "能力 Spec 没有该来源：%s" % source}
	var removed: Dictionary = source_records[source]
	source_records.erase(source)
	return {"ok": true, "source": source, "removed": removed, "remaining_sources": sources()}

func has_sources() -> bool:
	return not source_records.is_empty()

func sources() -> PackedStringArray:
	var result := PackedStringArray()
	for source in source_records.keys(): result.append(str(source))
	result.sort()
	return result

func effective_level() -> int:
	var level := 0
	for record in source_records.values(): level = maxi(level, int(record.get("level", 1)))
	return level

func effective_overrides() -> Dictionary:
	var result: Dictionary = {}
	for source in sources():
		var record: Dictionary = source_records[source]
		for key in record.get("overrides", {}): result[key] = record.overrides[key]
	return result

func to_summary() -> Dictionary:
	return {
		"ability_id": ability_id,
		"level": effective_level(),
		"sources": Array(sources()),
		"source_records": source_records.duplicate(true),
		"dynamic_tags": dynamic_tags.snapshot(),
		"duplicate_strategy": DUPLICATE_STRATEGY,
		"definition": definition.to_summary() if definition != null else {},
	}
