@tool
extends EditorExportPlugin

var _ext3d01_trace_path := ""
var _ext3d01_trace_features: PackedStringArray = PackedStringArray()
var _ext3d01_trace_profile_modules: Array = []
var _ext3d01_trace_included: Array[String] = []
var _ext3d01_trace_skipped: Array[String] = []
var _ext3d01_trace_planner_failures: Array[Dictionary] = []
var _trace_event := "GM_EXT_3D_01_REAL_EXPORT_PLUGIN_SENTINEL"

func _get_name() -> String:
	return "GMModuleWhitelist"

func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	_ext3d01_trace_path = OS.get_environment("GM_EXT_3D_01_EXPORT_EVIDENCE_JSON").strip_edges()
	var ext3d08_trace_path := OS.get_environment("GM_EXT_3D_08_EXPORT_EVIDENCE_JSON").strip_edges()
	var ext3d03_trace_path := OS.get_environment("GM_EXT_3D_03_EXPORT_EVIDENCE_JSON").strip_edges()
	var ext3d02_trace_path := OS.get_environment("GM_EXT_3D_02_EXPORT_EVIDENCE_JSON").strip_edges()
	if not ext3d08_trace_path.is_empty():
		_ext3d01_trace_path = ext3d08_trace_path
		_trace_event = "GM_EXT_3D_08_REAL_EXPORT_PLUGIN_SENTINEL"
	elif not ext3d03_trace_path.is_empty():
		_ext3d01_trace_path = ext3d03_trace_path
		_trace_event = "GM_EXT_3D_03_REAL_EXPORT_PLUGIN_SENTINEL"
	elif not ext3d02_trace_path.is_empty():
		_ext3d01_trace_path = ext3d02_trace_path
		_trace_event = "GM_EXT_3D_02_REAL_EXPORT_PLUGIN_SENTINEL"
	else:
		_trace_event = "GM_EXT_3D_01_REAL_EXPORT_PLUGIN_SENTINEL"
	_ext3d01_trace_features = features.duplicate()
	if _ext3d01_trace_path.is_empty(): return
	var profile = load("res://gm_runtime/gm_module_profile.tres")
	var target_module := OS.get_environment("GM_TASK01_TARGET_MODULE").strip_edges()
	if not target_module.is_empty():
		_ext3d01_trace_profile_modules = [target_module]
	elif profile != null:
		_ext3d01_trace_profile_modules = Array(profile.enabled_modules)

func _export_file(path: String, type: String, features: PackedStringArray) -> void:
	# Task11's explicit runtime character fixture is required by its release entry;
	# this narrow feature gate does not admit other samples or editor/test content.
	var task11_sample := path.begins_with("res://samples/task11_characters/")
	var ext3d_05_2d_fixture := path in [
		"res://samples/task11_characters/hero_complete.tres",
		"res://samples/task11_characters/hero_sprite.svg",
		"res://samples/task11_characters/hero_sprite.svg.import",
	]
	if (features.has("task11_characters") and task11_sample) or (features.has("gm_ext_3d_05_disabled") and ext3d_05_2d_fixture):
		if not _ext3d01_trace_path.is_empty(): _ext3d01_trace_included.append(path)
		return
	var profile = load("res://gm_runtime/gm_module_profile.tres")
	var target_module := OS.get_environment("GM_TASK01_TARGET_MODULE").strip_edges()
	if not target_module.is_empty():
		profile = profile.duplicate()
		profile.enabled_modules = PackedStringArray([target_module])
	var result: Dictionary = GMExportPlanner.plan(profile, path)
	if not result.ok and not _ext3d01_trace_path.is_empty():
		_ext3d01_trace_planner_failures.append({"path": path, "error_zh": str(result.get("error_zh", "")), "violations": result.get("violations", []).duplicate(true)})
	for root in result.excluded_paths:
		if path == root or path.begins_with(root + "/"):
			if not _ext3d01_trace_path.is_empty(): _ext3d01_trace_skipped.append(path)
			skip()
			return
	var included := false
	for root in result.allowed_paths:
		if path == root or path.begins_with(root + "/"):
			included = true
			break
	if included:
		if not _ext3d01_trace_path.is_empty(): _ext3d01_trace_included.append(path)
	else:
		if not _ext3d01_trace_path.is_empty(): _ext3d01_trace_skipped.append(path)
		skip()

func _export_end() -> void:
	if _ext3d01_trace_path.is_empty(): return
	_ext3d01_trace_included.sort()
	_ext3d01_trace_skipped.sort()
	var absolute := ProjectSettings.globalize_path(_ext3d01_trace_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({
		"event": _trace_event,
		"ok": _ext3d01_trace_planner_failures.is_empty(),
		"plugin": "GMModuleWhitelist",
		"features": Array(_ext3d01_trace_features),
		"profile_modules": _ext3d01_trace_profile_modules,
		"included_paths": _ext3d01_trace_included,
		"skipped_paths": _ext3d01_trace_skipped,
		"planner_failures": _ext3d01_trace_planner_failures,
		"trace_phase": "EditorExportPlugin._export_file",
	}, "  ") + "\n")
