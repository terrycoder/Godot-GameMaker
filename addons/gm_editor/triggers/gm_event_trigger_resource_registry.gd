@tool
class_name GMEventTriggerResourceRegistry
extends RefCounted

## Saved GMGameplayEventTrigger Resource registry.
## Resource paths are locators only; trigger_id remains the stable identity.

var entries: Dictionary = {}
var errors: Array[Dictionary] = []
var candidate_entries: Dictionary = {}

func rescan(root_path: String) -> Dictionary:
	entries.clear()
	errors.clear()
	candidate_entries.clear()
	if root_path.strip_edges().is_empty():
		errors.append({"code": "event.registry_root_missing", "reason_zh": "事件触发器资源注册表缺少扫描根目录。"})
	else:
		_scan(root_path)
	var rows: Array[Dictionary] = []
	for trigger_id in entries.keys():
		rows.append(entries[trigger_id].duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("trigger_id", "")) < str(b.get("trigger_id", "")))
	return {"ok": errors.is_empty(), "code": "event.registry_valid" if errors.is_empty() else "event.registry_invalid", "root": root_path, "entry_count": rows.size(), "entries": rows, "errors": errors.duplicate(true), "errors_zh": _messages()}

func find_usage(trigger_id: String) -> Array[Dictionary]:
	var resolution := resolve_unique(trigger_id)
	if not resolution.ok: return []
	return [resolution.get("resolved", {}).duplicate(true)]

func resolve_unique(trigger_id: String) -> Dictionary:
	var wanted := trigger_id.strip_edges()
	var candidates: Array[Dictionary] = []
	var raw: Variant = candidate_entries.get(wanted, [])
	if raw is Array:
		for row in raw:
			if row is Dictionary: candidates.append(row.duplicate(false))
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("resource_path", "")) < str(b.get("resource_path", "")))
	if candidates.is_empty():
		return {"ok": false, "code": "event.registry_missing", "reason_zh": "事件触发器资源注册表找不到稳定 trigger_id：%s。" % wanted, "trigger_id": wanted, "candidate_count": 0, "candidates": []}
	if candidates.size() > 1:
		return {"ok": false, "code": "event.registry_ambiguous", "reason_zh": "稳定 trigger_id %s 匹配到 %d 个资源，已拒绝按扫描顺序选取；请保证资源 ID 唯一。" % [wanted, candidates.size()], "trigger_id": wanted, "candidate_count": candidates.size(), "candidates": candidates}
	return {"ok": true, "code": "event.registry_resolved", "reason_zh": "", "trigger_id": wanted, "candidate_count": 1, "candidates": candidates, "resolved": candidates[0]}

func snapshot() -> Dictionary:
	return {"entry_count": entries.size(), "entries": entries.values().duplicate(true), "errors": errors.duplicate(true)}

func _scan(root_path: String) -> void:
	var directory := DirAccess.open(root_path)
	if directory == null:
		errors.append({"code": "event.registry_root_missing", "reason_zh": "事件触发器资源注册表无法打开扫描目录：%s。" % root_path, "root": root_path})
		return
	for file_name in directory.get_files():
		var full_path := root_path.path_join(file_name)
		var lower := file_name.to_lower()
		if lower.ends_with(".tres") or lower.ends_with(".res"):
			var resource: Variant = ResourceLoader.load(full_path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if resource is GMGameplayEventTrigger:
				var trigger: GMGameplayEventTrigger = resource
				var trigger_id := trigger.trigger_id.strip_edges()
				if trigger_id.is_empty():
					errors.append({"code": "event.registry_id_missing", "reason_zh": "触发器资源缺少稳定 trigger_id：%s。" % full_path, "resource_path": full_path})
				else:
					var candidate := {"trigger_id": trigger_id, "resource_path": full_path, "resource": resource, "locatable": true, "identity_policy": "trigger_id; resource_path_is_locator_only", "resource_type": resource.get_class()}
					if not candidate_entries.has(trigger_id): candidate_entries[trigger_id] = []
					candidate_entries[trigger_id].append(candidate)
					if entries.has(trigger_id):
						errors.append({"code": "event.registry_duplicate_id", "reason_zh": "触发器资源稳定 ID 重复：%s；已拒绝唯一解析。" % trigger_id, "resource_path": full_path, "candidate_count": candidate_entries[trigger_id].size(), "candidates": _candidate_summaries(candidate_entries[trigger_id])})
					else:
						entries[trigger_id] = candidate
	for directory_name in directory.get_directories():
		_scan(root_path.path_join(directory_name))

func _messages() -> Array[String]:
	var result: Array[String] = []
	for row in errors:
		result.append(str(row.get("reason_zh", "事件触发器资源注册表无效。")))
	return result

func _candidate_summaries(rows: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw in rows:
		if raw is Dictionary:
			var row: Dictionary = raw.duplicate(false)
			row.erase("resource")
			result.append(row)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("resource_path", "")) < str(b.get("resource_path", "")))
	return result
