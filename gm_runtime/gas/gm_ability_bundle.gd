@tool
class_name GMAbilityBundle
extends Resource

## 批量能力组合。Bundle 只负责声明授予/撤销，不建立平行 Feature 生命周期。

@export var bundle_id: String = ""
@export var display_name_zh: String = ""
@export_multiline var description_zh: String = ""
@export var entries: Array[Dictionary] = []

func add_ability(ability_id: String, level: int = 1, overrides: Dictionary = {}) -> void:
	entries.append({"ability_id": ability_id, "level": maxi(level, 1), "overrides": overrides.duplicate(true)})

func grant_to(host: GMAbilitySystemHost, source: String, definitions: Dictionary) -> Dictionary:
	if host == null:
		return {"ok": false, "code": "bundle.host_missing", "reason_zh": "能力包授予缺少宿主。"}
	var host_check := host._validate_ability_grant_host()
	if not host_check.ok:
		return {"ok": false, "bundle_id": bundle_id, "source": source, "results": [host_check], "preflight": true, "rolled_back": true, "committed_count": 0, "error_zh": "能力包授予宿主预检失败。"}
	if source.strip_edges().is_empty():
		var source_failure := {"ok": false, "code": "ability.source_missing", "reason_zh": "能力包授予缺少来源。"}
		return {"ok": false, "bundle_id": bundle_id, "source": source, "results": [source_failure], "preflight": true, "rolled_back": true, "committed_count": 0, "error_zh": "能力包授予来源预检失败。"}

	var rows: Array[Dictionary] = []
	var preflight_results: Array[Dictionary] = []
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var id := str(entry.get("ability_id", ""))
		if id.strip_edges().is_empty():
			var id_failure := {"ok": false, "code": "bundle.entry_invalid", "reason_zh": "能力包条目缺少能力 ID。", "index": index}
			preflight_results.append(id_failure)
			return _failed_result(source, preflight_results, "能力包预检失败；宿主保持调用前快照。")
		var raw_definition: Variant = definitions.get(id, null)
		if raw_definition == null or not raw_definition is GMAbilityDefinition:
			var missing := {"ok": false, "code": "bundle.definition_missing", "reason_zh": "能力包引用的定义不存在：%s" % id, "index": index, "ability_id": id}
			preflight_results.append(missing)
			return _failed_result(source, preflight_results, "能力包预检失败；宿主保持调用前快照。")
		var raw_overrides: Variant = entry.get("overrides", {})
		if not raw_overrides is Dictionary:
			var overrides_failure := {"ok": false, "code": "bundle.entry_invalid", "reason_zh": "能力包条目覆盖参数必须是 Dictionary：%s" % id, "index": index, "ability_id": id}
			preflight_results.append(overrides_failure)
			return _failed_result(source, preflight_results, "能力包预检失败；宿主保持调用前快照。")
		var definition: GMAbilityDefinition = raw_definition
		var level := int(entry.get("level", 1))
		var overrides: Dictionary = raw_overrides
		var check := host.preflight_ability_grant(definition, source, level, overrides)
		if not check.ok:
			check["index"] = index
			preflight_results.append(check)
			return _failed_result(source, preflight_results, "能力包预检失败；宿主保持调用前快照。")
		rows.append({"index": index, "ability_id": id, "definition": definition, "level": level, "overrides": overrides.duplicate(true), "sort_key": "%s|%s|%s" % [id, str(level), _canonical_variant_key(overrides)]})
		preflight_results.append({"ok": true, "index": index, "ability_id": id})

	# Commit in canonical order so entry permutation cannot change the final
	# definitions/specs/source state. The snapshot is a fail-safe for any
	# unexpected middle-commit failure after preflight.
	var commit_rows := rows.duplicate()
	commit_rows.sort_custom(func(a: Dictionary, b: Dictionary):
		var left := str(a.get("sort_key", ""))
		var right := str(b.get("sort_key", ""))
		if left == right: return int(a.get("index", 0)) < int(b.get("index", 0))
		return left < right
	)
	var snapshot := host._snapshot_ability_grant_state()
	var committed_by_index: Dictionary = {}
	var commit_failure: Dictionary = {}
	var committed_count := 0
	for row in commit_rows:
		var grant := host.grant_ability(row.definition, source, int(row.level), row.overrides)
		committed_by_index[int(row.index)] = grant
		if not grant.ok:
			commit_failure = grant
			break
		committed_count += 1
	if not commit_failure.is_empty():
		host._restore_ability_grant_state(snapshot)
		var failed_results: Array[Dictionary] = []
		for index in entries.size():
			if committed_by_index.has(index):
				var committed_result: Dictionary = committed_by_index[index]
				failed_results.append(committed_result)
			else:
				failed_results.append({"ok": false, "code": "bundle.not_committed", "reason_zh": "能力包因中间失败未提交该条目。", "index": index})
		return {"ok": false, "bundle_id": bundle_id, "source": source, "results": failed_results, "preflight": false, "rolled_back": true, "committed_count": committed_count, "failure": commit_failure, "error_zh": "能力包中间提交失败，已完整回滚宿主状态。"}

	var results: Array[Dictionary] = []
	for index in entries.size():
		var result: Dictionary = committed_by_index.get(index, {"ok": true, "code": "bundle.empty"})
		results.append(result)
	return {"ok": true, "bundle_id": bundle_id, "source": source, "results": results, "preflight": true, "rolled_back": false, "committed_count": committed_count, "error_zh": ""}

func _failed_result(source: String, results: Array[Dictionary], error_zh: String) -> Dictionary:
	return {"ok": false, "bundle_id": bundle_id, "source": source, "results": results, "preflight": true, "rolled_back": true, "committed_count": 0, "error_zh": error_zh}

func _canonical_variant_key(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array[String] = []
		for key in value.keys(): keys.append(str(key))
		keys.sort()
		var parts: Array[String] = []
		for key in keys: parts.append(JSON.stringify(key) + ":" + _canonical_variant_key(value[key]))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var array_parts: Array[String] = []
		for item in value: array_parts.append(_canonical_variant_key(item))
		return "[" + ",".join(array_parts) + "]"
	if value is PackedStringArray: return _canonical_variant_key(Array(value))
	return JSON.stringify(value)

func revoke_from(host: GMAbilitySystemHost, source: String) -> Dictionary:
	if host == null:
		return {"ok": false, "code": "bundle.host_missing", "reason_zh": "能力包撤销缺少宿主。"}
	var results: Array[Dictionary] = []
	for entry in entries: results.append(host.revoke_ability(str(entry.get("ability_id", "")), source))
	var ok := results.all(func(item): return bool(item.get("ok", false)))
	return {"ok": ok, "bundle_id": bundle_id, "source": source, "results": results}

func to_summary() -> Dictionary:
	return {"bundle_id": bundle_id, "display_name_zh": display_name_zh, "description_zh": description_zh, "entries": entries.duplicate(true)}
