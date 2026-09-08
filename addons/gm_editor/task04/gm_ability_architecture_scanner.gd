extends RefCounted

## 开发/测试层架构门禁。正式运行时仅依赖 GMAbilityActivationRequest 契约。

const FORBIDDEN_PATTERNS := [
	"movement_executor.",
	"movement_service.",
	"loot_service.",
	"production_service.",
	"eat_service.",
	"drop_loot(",
	"move_directly(",
	"produce_directly(",
]

func scan(root: String = "res://", excluded_paths: Array[String] = []) -> Dictionary:
	var files: Array[String] = []
	_collect_files(root, files)
	return _scan_files(files, excluded_paths)

func scan_paths(roots: Array[String], excluded_paths: Array[String] = []) -> Dictionary:
	var files: Array[String] = []
	for root in roots:
		_collect_files(root, files)
	return _scan_files(files, excluded_paths)

func scan_project() -> Dictionary:
	var roots: Array[String] = ["res://gm_runtime", "res://gm_adapters", "res://addons/gm_editor"]
	var excludes: Array[String] = []
	var result := scan_paths(roots, excludes)
	result["scope"] = "正式项目代码（排除负面夹具；扫描器自身属于开发工具层）"
	return result

func _scan_files(files: Array[String], excluded_paths: Array[String]) -> Dictionary:
	var violations: Array[Dictionary] = []
	files.sort()
	for path in files:
		if not path.ends_with(".gd"): continue
		if _is_excluded(path, excluded_paths): continue
		if path.begins_with("res://gm_runtime/gas/"): continue
		if path.begins_with("res://addons/gm_editor/task04/"): continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for line_number in lines.size():
			var line := str(lines[line_number])
			for pattern in FORBIDDEN_PATTERNS:
				if line.to_lower().contains(pattern.to_lower()):
					violations.append({
						"code": "architecture.direct_domain_call",
						"path": path,
						"line": line_number + 1,
						"pattern": pattern,
						"reason_zh": "发现触发来源或样板直接调用领域执行器：%s；必须构造 GMAbilityActivationRequest。" % pattern,
						"source_contract": "输入/AI/日程/调试器 → GMAbilityActivationRequest → GMAbilitySystemHost",
					})
	return {"ok": violations.is_empty(), "violations": violations, "forbidden_patterns": FORBIDDEN_PATTERNS.duplicate(), "scanned_files": files.size()}

func _is_excluded(path: String, excluded_paths: Array[String]) -> bool:
	for excluded in excluded_paths:
		if path.begins_with(str(excluded)): return true
	return false

func _collect_files(path: String, result: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty(): break
		if name in [".", "..", ".godot"]: continue
		var child := path.path_join(name)
		if dir.current_is_dir(): _collect_files(child, result)
		else: result.append(child)
	dir.list_dir_end()
