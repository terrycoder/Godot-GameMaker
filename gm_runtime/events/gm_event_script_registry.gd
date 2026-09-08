class_name GMEventScriptRegistry
extends RefCounted

## GDScript 编辑→重载→重新发现/使用位置的运行时可审计索引。

var discovered: Dictionary = {}
var last_root: String = ""
var reload_count: int = 0

func discover(root: String, expected_kind: String = "") -> Dictionary:
	discovered.clear()
	last_root = root
	var files: Array[String] = []
	_collect_gd_files(root, files)
	var rows: Array[Dictionary] = []
	for path in files:
		var check := _validate_for_kind(path, expected_kind)
		var row := {"path": path, "validation": check, "kind": _kind_for_source(path)}
		rows.append(row)
		if check.ok: discovered[path] = row
	return {"ok": rows.all(func(item): return bool(item.get("validation", {}).get("ok", false))), "root": root, "expected_kind": expected_kind, "files": rows, "discovered": discovered.keys(), "reload_count": reload_count}

func reload_and_discover(root: String, expected_kind: String = "") -> Dictionary:
	reload_count += 1
	for path in discovered.keys(): ResourceLoader.load(str(path), "", ResourceLoader.CACHE_MODE_IGNORE)
	return discover(root, expected_kind)

func usage_locations(path: String, trigger_resources: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for trigger in trigger_resources:
		if trigger is GMGameplayEventTrigger:
			if trigger.target_selector != null and trigger.target_selector._resolved_script_path() == path: result.append({"trigger_id": trigger.trigger_id, "kind": "GMTargetSelector", "field": "target_selector", "path": path, "locatable": true})
			if trigger.handler != null and trigger.handler._resolved_script_path() == path: result.append({"trigger_id": trigger.trigger_id, "kind": "GMEventHandler", "field": "handler", "path": path, "locatable": true})
			for index in trigger.conditions.size():
				var condition: Variant = trigger.conditions[index]
				if condition is GMEventCondition and condition._resolved_script_path() == path: result.append({"trigger_id": trigger.trigger_id, "kind": "GMEventCondition", "field": "conditions[%d]" % index, "path": path, "locatable": true})
	return result

func snapshot() -> Dictionary:
	var rows: Array = []
	for path in discovered.keys(): rows.append(discovered[path])
	return {"root": last_root, "reload_count": reload_count, "discovered_count": discovered.size(), "discovered": rows}

func _validate_for_kind(path: String, expected_kind: String) -> Dictionary:
	var source := FileAccess.get_file_as_string(path)
	var kind := expected_kind
	if kind.is_empty(): kind = _kind_from_extends(source)
	match kind:
		"GMEventCondition": return GMEventScriptValidator.validate_condition_script(path)
		"GMEventHandler": return GMEventScriptValidator.validate_handler_script(path)
		"GMTargetSelector": return GMEventScriptValidator.validate_selector_script(path)
		_: return {"ok": false, "code": "script.kind_unknown", "reason_zh": "无法从 GDScript 推断事件扩展基类：%s。" % path, "path": path, "errors": [{"code": "script.kind_unknown", "reason_zh": "无法从 GDScript 推断事件扩展基类：%s。" % path}]}

func _kind_for_source(path: String) -> String:
	return _kind_from_extends(FileAccess.get_file_as_string(path))

func _kind_from_extends(source: String) -> String:
	if source.contains("extends GMEventCondition"): return "GMEventCondition"
	if source.contains("extends GMEventHandler"): return "GMEventHandler"
	if source.contains("extends GMTargetSelector"): return "GMTargetSelector"
	return ""

func _collect_gd_files(path: String, result: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty(): break
		if name in [".", "..", ".godot"]: continue
		var child := path.path_join(name)
		if dir.current_is_dir(): _collect_gd_files(child, result)
		elif name.ends_with(".gd") and not name.ends_with(".gd.uid"): result.append(child)
	dir.list_dir_end()
	result.sort()
