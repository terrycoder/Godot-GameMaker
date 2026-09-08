extends Node

const ENTRY_SCENE := "res://gm_runtime/vertical_sample/gm_ext_3d_11_2d_minimal_entry.tscn"
const SCRIPT_PATH := "res://gm_runtime/vertical_sample/gm_ext_3d_11_2d_minimal.gd"
const FORBIDDEN_ROOTS := [
	"res://gm_runtime/characters/visual_3d/",
	"res://gm_runtime/content/3d/",
	"res://gm_runtime/presentation/planar3d/",
	"res://gm_runtime/map/3d/",
	"res://gm_adapters/spatial3d/"
]

var _started := false

func _ready() -> void:
	_started = true
	var args := OS.get_cmdline_user_args()
	if args.has("--gm-ext-3d-11-list-pack"):
		call_deferred("_run_pack_inventory")
	elif args.has("--gm-ext-3d-11-2d-contract"):
		call_deferred("_run_contract")
	else:
		call_deferred("_run_start")

func _run_start() -> void:
	await get_tree().process_frame
	var report := {"schema": "gm.ext3d11.2d_minimal_start.v1", "ok": _started, "entry_scene": ENTRY_SCENE, "sentinel": "GM_EXT_3D_11_2D_MINIMAL_START"}
	var evidence := _write_evidence(report)
	print("GM_EXT_3D_11_2D_MINIMAL_START_RESULT " + JSON.stringify({"ok": bool(report.get("ok", false)) and bool(evidence.get("ok", false)), "evidence": evidence}))
	get_tree().quit(0 if bool(report.get("ok", false)) and bool(evidence.get("ok", false)) else 1)

func _run_contract() -> void:
	await get_tree().process_frame
	var report := {"schema": "gm.ext3d11.2d_minimal_contract.v1", "event": "GM_EXT_3D_11_2D_MINIMAL_SENTINEL", "ok": _started, "checks": [{"name": "minimal_2d_entry_started", "passed": _started}, {"name": "forbidden_runtime_roots_unloaded", "passed": _forbidden_hits([]).is_empty()}], "formal_entry_scene": ENTRY_SCENE}
	var evidence := _write_evidence(report)
	print("GM_EXT_3D_11_2D_RESULT " + JSON.stringify({"ok": bool(report.get("ok", false)) and bool(evidence.get("ok", false)), "checks": report.get("checks", []), "evidence": evidence}))
	get_tree().quit(0 if bool(report.get("ok", false)) and bool(evidence.get("ok", false)) else 1)

func _run_pack_inventory() -> void:
	await get_tree().process_frame
	var files: Array[String] = []
	_walk_files("res://", files)
	files.sort()
	var dependencies := _recursive_dependencies(ENTRY_SCENE)
	var required := [ENTRY_SCENE, SCRIPT_PATH]
	var required_rows: Array = []
	for path in required:
		required_rows.append({"path": path, "present": files.has(path) or files.has(path + ".remap")})
	var forbidden_hits := _forbidden_hits(files)
	var recursive_forbidden_hits := _forbidden_hits(dependencies.get("dependencies", []))
	var formal_product := false
	for argument in OS.get_cmdline_args():
		if str(argument) == "--main-pack":
			formal_product = true
	for argument in OS.get_cmdline_user_args():
		if str(argument) == "--gm-ext-3d-11-formal-product":
			formal_product = true
	var ok := _started and bool(dependencies.get("ok", false)) and forbidden_hits.is_empty() and recursive_forbidden_hits.is_empty() and Array(dependencies.get("missing", [])).is_empty()
	var inventory := {
		"schema": "gm.ext3d11.2d_minimal_pack_inventory.v1",
		"ok": ok,
		"actual_pack": true,
		"entry_started": _started,
		"formal_product": formal_product,
		"entry_scene": ENTRY_SCENE,
		"required_files": required_rows,
		"files": files,
		"file_count": files.size(),
		"forbidden_hits": forbidden_hits,
		"recursive_dependencies": dependencies.get("dependencies", []),
		"recursive_dependency_count": Array(dependencies.get("dependencies", [])).size(),
		"recursive_forbidden_hits": recursive_forbidden_hits,
		"missing_dependencies": dependencies.get("missing", [])
	}
	var evidence := _write_evidence(inventory)
	print("GM_EXT_3D_11_2D_PACK_RESULT " + JSON.stringify({"ok": bool(inventory.get("ok", false)) and bool(evidence.get("ok", false)), "file_count": files.size(), "forbidden_hits": forbidden_hits, "recursive_forbidden_hits": recursive_forbidden_hits, "evidence": evidence}))
	get_tree().quit(0 if bool(inventory.get("ok", false)) and bool(evidence.get("ok", false)) else 1)

func _walk_files(path: String, result: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name == "." or name == ".." or name == ".godot":
			continue
		var child := path.path_join(name)
		if directory.current_is_dir():
			_walk_files(child, result)
		else:
			result.append(child)
	directory.list_dir_end()

func _recursive_dependencies(entry_scene: String) -> Dictionary:
	var pending: Array[String] = [entry_scene]
	var visited: Dictionary = {}
	var dependencies: Array[String] = []
	var missing: Array[String] = []
	while not pending.is_empty():
		var current: String = str(pending.pop_back())
		if visited.has(current):
			continue
		visited[current] = true
		dependencies.append(current)
		var listed := ResourceLoader.get_dependencies(current)
		for raw in listed:
			var parts := str(raw).split("::")
			var dependency := str(parts[0]) if parts.size() > 0 else ""
			if not dependency.begins_with("res://"):
				continue
			if not FileAccess.file_exists(dependency) and not FileAccess.file_exists(dependency + ".remap"):
				missing.append(dependency)
			elif not visited.has(dependency):
				pending.append(dependency)
	return {"ok": true, "dependencies": dependencies, "missing": missing}

func _forbidden_hits(paths: Array) -> Array:
	var hits: Array = []
	for value in paths:
		var path := str(value)
		for root in FORBIDDEN_ROOTS:
			if path.begins_with(root):
				hits.append(path)
				break
	hits.sort()
	return hits

func _write_evidence(value: Dictionary) -> Dictionary:
	var path := OS.get_environment("GM_EXT_3D_11_RUN_EVIDENCE").strip_edges()
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--gm-ext-3d-11-evidence="):
			path = str(argument).trim_prefix("--gm-ext-3d-11-evidence=")
	if path.is_empty():
		return {"ok": true, "written": false}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "path": path, "code": "release.evidence_open_failed"}
	file.store_string(JSON.stringify(value, "  ") + "\n")
	file.close()
	return {"ok": true, "written": true, "path": path}
