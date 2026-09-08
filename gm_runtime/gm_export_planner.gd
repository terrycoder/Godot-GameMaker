class_name GMExportPlanner
extends RefCounted

const REGISTRY := preload("res://gm_runtime/gm_module_registry.gd")
const SCANNER := preload("res://gm_runtime/gm_dependency_scanner.gd")
const ALWAYS_EXCLUDED := ["res://addons/gm_editor", "res://DOCS"]

static func plan(profile: Resource, source_root: String = "res://") -> Dictionary:
	if profile == null:
		return _failure("导出规划缺少Profile", source_root, [], ALWAYS_EXCLUDED)
	var local_path := source_root.path_join("profile.tres")
	if not source_root.ends_with(".tscn") and FileAccess.file_exists(local_path):
		var local = load(local_path)
		if local != null: profile = local
	var selected: PackedStringArray = profile.enabled_modules
	var target := OS.get_environment("GM_TASK01_TARGET_MODULE").strip_edges()
	if selected.is_empty() and not target.is_empty(): selected = PackedStringArray([target])
	var resolution: Dictionary = REGISTRY.resolve(selected)
	if not resolution.ok:
		return {"ok":false,"profile_modules":resolution.get("selected", []),"allowed_paths":[],"excluded_paths":ALWAYS_EXCLUDED,"ownership":[],"platform_generated":{},"violations":[],"source_root":source_root,"registry_errors":resolution.get("errors_zh", []),"error_zh":"Manifest Registry无法用于导出：%s" % "; ".join(resolution.get("errors_zh", []))}
	var registry_view := REGISTRY.current_view_result()
	if not registry_view.ok:
		return {"ok":false,"profile_modules":[],"allowed_paths":[],"excluded_paths":ALWAYS_EXCLUDED,"ownership":[],"platform_generated":{},"violations":[],"source_root":source_root,"registry_errors":registry_view.get("errors_zh", []),"error_zh":"Manifest Registry当前提交视图不可用"}
	var manifest_contract := _export_manifest_contract(REGISTRY.manifest_contract(resolution.selected), resolution.selected)
	var ownership := _ownership(registry_view.manifests, resolution.selected)
	var platform_generated := platform_generated_contract(registry_view.manifests, resolution.selected, source_root)
	var allowed: Array[String] = ["res://gm_runtime/gm_runtime_context.gd", "res://gm_runtime/gm_module_registry.gd", "res://gm_runtime/gm_module_manifest.gd", "res://gm_runtime/gm_module_manifest_index.gd", "res://gm_runtime/gm_service_spec.gd", "res://gm_runtime/gm_platform_version.gd", "res://gm_runtime/gm_platform_version.tres", "res://gm_runtime/gm_project_profile.gd", "res://gm_runtime/manifests/manifest_index.tres"]
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if not main_scene.is_empty(): _append_unique_path(allowed, main_scene)
	if source_root.ends_with(".tscn"):
		_append_unique_path(allowed, source_root)
		for raw_dependency in ResourceLoader.get_dependencies(source_root):
			var dependency_path := str(raw_dependency).split("::", true, 1)[0]
			if dependency_path.begins_with("res://"): _append_unique_path(allowed, dependency_path)
	var excluded: Array[String] = []
	for path in ALWAYS_EXCLUDED: _append_unique_path(excluded, path)
	var violations: Array[Dictionary] = []
	if not resolution.ok:
		for error in resolution.get("errors_zh", []): violations.append({"source":"ManifestRegistry","target":"module-selection","chain":["ManifestRegistry","module-selection"],"fix_zh":str(error)})
	for id in resolution.get("selected", []):
		var manifest: Dictionary = resolution.manifests.get(id, {})
		var manifest_path := str(manifest.get("source_path", ""))
		if not manifest_path.is_empty(): _append_unique_path(allowed, manifest_path)
		for path in manifest.get("service_spec_paths", []): _append_unique_path(allowed, str(path))
		for path in manifest.get("export_required_paths", []):
			var required_info := _path_info(path)
			var required_path := str(required_info.get("path", ""))
			if not bool(required_info.get("ok", false)):
				violations.append({"source":manifest_path,"target":str(path),"chain":[manifest_path,str(path)],"module_id":id,"fix_zh":"Manifest导出必需路径存在越界或非法段"})
				continue
			_append_unique_path(allowed, required_path)
			if _is_always_excluded(required_path):
				violations.append({"source":manifest_path,"target":required_path,"chain":[manifest_path,required_path],"module_id":id,"fix_zh":"正式运行时路径不得位于编辑器、测试或开发目录"})
		for path in manifest.get("export_excluded_paths", []): _append_unique_path(excluded, str(path))
		for path in manifest.get("private_build_artifacts", []): _append_unique_path(excluded, str(path))
		var runtime_root := _normalise_path(manifest.get("runtime_root", ""))
		if not runtime_root.is_empty(): _append_unique_path(allowed, runtime_root)
		if not runtime_root.is_empty() and _is_always_excluded(runtime_root):
			violations.append({"source":manifest_path,"target":runtime_root,"chain":[manifest_path,runtime_root],"module_id":id,"fix_zh":"Manifest.runtime_root必须指向正式运行时目录"})
	var ownership_resolution: Dictionary = _resolve_excluded_ownership(excluded, ownership, resolution.get("selected", []))
	var resolved_excluded: Array[String] = []
	for raw_excluded in ownership_resolution.get("excluded_paths", []):
		_append_unique_path(resolved_excluded, str(raw_excluded))
	excluded = resolved_excluded
	var scan: Dictionary = SCANNER.scan(source_root)
	for raw in scan.get("violations", []):
		_classify(str(raw.get("source", "")), str(raw.get("target", "")), raw.get("chain", []), str(raw.get("fix_zh", "")), resolution.get("selected", []), ownership, allowed, excluded, violations)
	var seen: Dictionary = {}
	var final: Array[Dictionary] = []
	for item in violations:
		var key := "%s|%s|%s" % [item.get("source", ""), item.get("target", ""), JSON.stringify(item.get("chain", []))]
		if seen.has(key): continue
		seen[key] = true
		final.append(item)
	var public_allowed := allowed.duplicate()
	var public_excluded := excluded.duplicate()
	var public_ownership := ownership.duplicate(true)
	var public_ownership_resolutions: Array = ownership_resolution.get("resolutions", []).duplicate(true)
	# The planner keeps core's future-module exclusion metadata in its internal
	# ownership graph so broad runtime roots remain safe.  A 2D-only plan exposes
	# the selected-module view, however: disabled Planar 3D paths must not appear
	# as an accidental public dependency in the plan JSON.
	if not resolution.get("selected", []).has("spatial.planar_3d"):
		public_allowed = _public_non_3d_paths(allowed)
		public_excluded = _public_non_3d_paths(excluded)
		public_ownership = _public_non_3d_ownership(ownership)
		public_ownership_resolutions = _public_non_3d_resolutions(public_ownership_resolutions)
	return {"ok":resolution.ok and final.is_empty(),"profile_modules":resolution.get("selected", []),"allowed_paths":public_allowed,"excluded_paths":public_excluded,"ownership":public_ownership,"ownership_resolutions":public_ownership_resolutions,"platform_generated":platform_generated,"manifest_contract":manifest_contract,"violations":final,"source_root":source_root,"registry_index_path":registry_view.index_path,"error_zh":"导出预检阻断：%s" % final[0].get("fix_zh", "") if not final.is_empty() else ""}

static func _failure(error_zh: String, source_root: String, allowed: Array, excluded: Array) -> Dictionary:
	return {"ok":false,"profile_modules":[],"allowed_paths":allowed,"excluded_paths":excluded,"ownership":[],"platform_generated":{},"violations":[{"source":source_root,"target":"export-plan","chain":[source_root,"export-plan"],"fix_zh":error_zh}],"source_root":source_root,"error_zh":error_zh}

static func _export_manifest_contract(contract: Dictionary, selected: PackedStringArray) -> Dictionary:
	# The general registry contract is a complete read view.  An export
	# plan embeds only selected-module backend declarations so a disabled
	# 3D module cannot become an accidental export dependency; this also
	# preserves the EXT01 2D-only evidence shape.
	var result := contract.duplicate(true)
	var selected_ids: PackedStringArray = PackedStringArray(selected)
	var modules: Array = []
	for raw_module in result.get("modules", []):
		if not raw_module is Dictionary: continue
		var module: Dictionary = raw_module
		if not selected_ids.has(str(module.get("module_id", ""))):
			module.erase("spatial_backends")
			module.erase("runtime_root")
			module.erase("editor_root")
			module.erase("service_spec_paths")
			module.erase("export_required_paths")
			module.erase("export_excluded_paths")
		elif not selected_ids.has("spatial.planar_3d"):
			module["export_required_paths"] = _public_non_3d_paths(module.get("export_required_paths", []))
			module["export_excluded_paths"] = _public_non_3d_paths(module.get("export_excluded_paths", []))
		modules.append(module)
	result["modules"] = modules
	return result

static func _is_planar3d_export_path(value: Variant) -> bool:
	var path := _normalise_path(value)
	return path == "res://gm_runtime/manifests/spatial_planar_3d.tres" or path == "res://gm_runtime/manifests/render_style_planar_3d.tres" or path == "res://gm_runtime/manifests/gm_ext_3d_08_manifest_index.tres" or path_is_within(path, "res://gm_runtime/map/3d") or path_is_within(path, "res://gm_adapters/spatial3d") or path_is_within(path, "res://gm_runtime/presentation/planar3d") or path_is_within(path, "res://gm_runtime/content/3d")

static func _public_non_3d_paths(paths: Variant) -> Array[String]:
	var result: Array[String] = []
	if not paths is Array and not paths is PackedStringArray: return result
	for raw_path in paths:
		if _is_planar3d_export_path(raw_path): continue
		result.append(str(raw_path))
	return result

static func _public_non_3d_ownership(entries: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not entries is Array: return result
	for raw_entry in entries:
		if not raw_entry is Dictionary: continue
		if _is_planar3d_export_path(raw_entry.get("path", "")): continue
		result.append(raw_entry.duplicate(true))
	return result

static func _public_non_3d_resolutions(entries: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not entries is Array: return result
	for raw_entry in entries:
		if not raw_entry is Dictionary: continue
		if _is_planar3d_export_path(raw_entry.get("path", "")): continue
		result.append(raw_entry.duplicate(true))
	return result

static func _ownership(modules: Dictionary, selected: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[String] = []
	if selected.is_empty():
		for value in modules.keys(): ids.append(str(value))
	else:
		for value in selected: ids.append(str(value))
	ids.sort()
	for id in ids:
		if not modules.has(id): continue
		var manifest: Dictionary = modules[id]
		for path in manifest.get("export_required_paths", []): _append_ownership(result, id, "required", str(path))
		var runtime_root := _normalise_path(manifest.get("runtime_root", ""))
		if not runtime_root.is_empty(): _append_ownership(result, id, "required", runtime_root)
		for path in manifest.get("export_excluded_paths", []): _append_ownership(result, id, "excluded", str(path))
		if not str(manifest.get("editor_root", "")).is_empty(): _append_ownership(result, id, "excluded", str(manifest.editor_root))
	return result

static func _append_ownership(result: Array[Dictionary], module_id: String, kind: String, raw_path: String) -> void:
	var path := _normalise_path(raw_path)
	if path.is_empty(): return
	for existing in result:
		if str(existing.get("module_id", "")) == module_id and str(existing.get("kind", "")) == kind and str(existing.get("path", "")) == path: return
	result.append({"module_id":module_id,"path":path,"kind":kind})

static func _resolve_excluded_ownership(excluded: Array, ownership: Array[Dictionary], selected: Variant = []) -> Dictionary:
	var effective: Array[String] = []
	var resolutions: Array[Dictionary] = []
	var selected_ids: Array[String] = []
	for raw_selected in selected: selected_ids.append(str(raw_selected))
	for raw_path in excluded:
		var path := _normalise_path(raw_path)
		if path.is_empty(): continue
		# ALWAYS_EXCLUDED is an absolute safety boundary.  A selected required
		# path under it remains a planner violation and can never win here.
		if _is_always_excluded(path):
			_append_unique_path(effective, path)
			continue
		var required_modules: Array[String] = []
		var excluded_modules: Array[String] = []
		for entry in ownership:
			var entry_path := _normalise_path(entry.get("path", ""))
			if entry_path.is_empty() or not _paths_overlap(path, entry_path): continue
			var module_id := str(entry.get("module_id", ""))
			if entry.get("kind", "") == "required" and (selected_ids.is_empty() or selected_ids.has(module_id)):
				if not required_modules.has(module_id): required_modules.append(module_id)
			elif entry.get("kind", "") == "excluded":
				if not excluded_modules.has(module_id): excluded_modules.append(module_id)
		if not required_modules.is_empty():
			required_modules.sort()
			excluded_modules.sort()
			resolutions.append({"path":path,"winner":"selected_required","required_modules":required_modules,"excluded_modules":excluded_modules})
			continue
		_append_unique_path(effective, path)
	return {"excluded_paths": effective, "resolutions": resolutions}

static func _paths_overlap(left: String, right: String) -> bool:
	return path_is_within(left, right) or path_is_within(right, left)

## Platform-generated files are an explicit, finite part of the export
## ownership universe.  They are derived from the same selected Manifest
## snapshot as ordinary ownership; arbitrary files under .godot/exported are
## never accepted by this contract.
static func platform_generated_contract(modules: Dictionary, selected: Array = [], source_root: String = "") -> Dictionary:
	var ids: Array[String] = []
	if selected.is_empty():
		for value in modules.keys(): ids.append(str(value))
	else:
		for value in selected:
			var selected_id := str(value)
			if modules.has(selected_id) and not ids.has(selected_id): ids.append(selected_id)
	ids.sort()
	var descriptors: Array[Dictionary] = []
	for id in ids:
		var manifest: Dictionary = modules.get(id, {})
		_append_generated_path(descriptors, id, str(manifest.get("source_path", "")))
		for raw_path in manifest.get("service_spec_paths", []): _append_generated_path(descriptors, id, str(raw_path))
		for raw_path in manifest.get("export_required_paths", []): _append_generated_path(descriptors, id, str(raw_path))
	if not source_root.is_empty() and str(source_root).get_extension().to_lower() == "tscn":
		var scene_name := str(source_root).get_file().get_basename()
		var owner := "core"
		if scene_name.begins_with("gm_task01_"):
			var candidate := "module_" + scene_name.trim_prefix("gm_task01_")
			if ids.has(candidate): owner = candidate
		_append_generated_descriptor(descriptors, owner, scene_name, "scn")
	descriptors.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_key := "%s|%s" % [str(left.get("module_id", "")), str(left.get("name", ""))]
		var right_key := "%s|%s" % [str(right.get("module_id", "")), str(right.get("name", ""))]
		return left_key < right_key
	)
	return {"schema_version":"gm.task01.platform-generated.v1","shared_exact":["res://.godot/global_script_class_cache.cfg","res://.godot/uid_cache.bin","res://project.binary"],"exported_root":"res://.godot/exported","exported":descriptors}

static func _append_generated_path(result: Array[Dictionary], module_id: String, raw_path: String) -> void:
	var path := _normalise_path(raw_path)
	if path.is_empty(): return
	var extension := path.get_extension().to_lower()
	if extension != "res" and extension != "tres" and extension != "scn" and extension != "tscn": return
	var name := path.get_file().get_basename()
	if name.is_empty(): return
	var generated_extension := "res" if extension == "tres" else "scn" if extension == "tscn" else extension
	_append_generated_descriptor(result, module_id, name, generated_extension)

static func _append_generated_descriptor(result: Array[Dictionary], module_id: String, name: String, extension: String) -> void:
	for descriptor in result:
		if str(descriptor.get("module_id", "")) != module_id or str(descriptor.get("name", "")) != name: continue
		var extensions: Array[String] = []
		for value in descriptor.get("extensions", []): extensions.append(str(value))
		if not extensions.has(extension): extensions.append(extension)
		extensions.sort()
		descriptor["extensions"] = extensions
		return
	result.append({"module_id":module_id,"name":name,"extensions":[extension]})

static func platform_generated_entry(value: Variant, contract: Dictionary) -> Dictionary:
	var info := _path_info(value)
	if not bool(info.get("ok", false)): return {}
	var path := str(info.get("path", ""))
	for raw_shared in contract.get("shared_exact", []):
		if path == _normalise_path(raw_shared): return {"kind":"shared","path":path}
	var exported_root := _normalise_path(contract.get("exported_root", "res://.godot/exported"))
	var prefix := exported_root.trim_suffix("/") + "/"
	if not path.begins_with(prefix): return {}
	var parts := path.trim_prefix(prefix).split("/", false)
	if parts.size() != 2: return {}
	var numeric_pattern := RegEx.new()
	if numeric_pattern.compile("^[0-9]+$") != OK or numeric_pattern.search(parts[0]) == null: return {}
	var exported_pattern := RegEx.new()
	if exported_pattern.compile("^export-([0-9a-f]{8,64})-([A-Za-z0-9._-]+)\\.([A-Za-z0-9]+)$") != OK: return {}
	var match := exported_pattern.search(parts[1])
	if match == null: return {}
	var name := str(match.get_string(2))
	var extension := str(match.get_string(3)).to_lower()
	for descriptor in contract.get("exported", []):
		var extensions: Array = descriptor.get("extensions", [])
		if str(descriptor.get("name", "")) == name and extensions.has(extension):
			return {"kind":"exported","module_id":str(descriptor.get("module_id", "")),"name":name,"extension":extension,"path":path}
	return {}

static func _classify(source: String, target: String, chain: Array, fix: String, selected: Array, ownership: Array[Dictionary], allowed: Array[String], excluded: Array[String], out: Array[Dictionary]) -> void:
	if target.is_empty(): return
	var target_info := _path_info(target)
	if not bool(target_info.get("ok", false)):
		out.append({"source":source,"target":target,"chain":chain,"fix_zh":fix if not fix.is_empty() else "移除越界或非法路径引用"})
		return
	var normalized_target := str(target_info.get("path", ""))
	if _is_always_excluded(normalized_target):
		out.append({"source":source,"target":normalized_target,"chain":chain,"fix_zh":fix if not fix.is_empty() else "移除对编辑器、测试或开发资源的引用"})
		return
	var selected_required_owner := ""
	var excluded_owner := ""
	for entry in ownership:
		var entry_path := _normalise_path(entry.get("path", ""))
		if not _path_is_within(normalized_target, entry_path): continue
		var module_id := str(entry.get("module_id", ""))
		if entry.get("kind", "") == "required" and selected.has(module_id):
			if selected_required_owner.is_empty() or module_id < selected_required_owner: selected_required_owner = module_id
		elif entry.get("kind", "") == "excluded" and excluded_owner.is_empty():
			excluded_owner = module_id
	if not selected_required_owner.is_empty(): return
	if not excluded_owner.is_empty():
		out.append({"source":source,"target":normalized_target,"chain":chain,"module_id":excluded_owner,"fix_zh":"引用了模块排除内容：%s" % excluded_owner})
		return
	for root in allowed:
		var normalized_root := _normalise_path(root)
		if _path_is_within(normalized_target, normalized_root): return
	for root in excluded:
		var normalized_root := _normalise_path(root)
		if _path_is_within(normalized_target, normalized_root):
			out.append({"source":source,"target":normalized_target,"chain":chain,"fix_zh":fix if not fix.is_empty() else "移除对被排除资源的依赖"})
			return
	if normalized_target.begins_with("res://"):
		out.append({"source":source,"target":normalized_target,"chain":chain,"fix_zh":"未知或未获Profile/Manifest许可的导出依赖，默认拒绝"})

static func _append_unique_path(paths: Array[String], raw_path: String) -> void:
	var path_info := _path_info(raw_path, true)
	if not bool(path_info.get("ok", false)): return
	var normalized := str(path_info.get("path", ""))
	if normalized.is_empty(): return
	for existing in paths:
		if _normalise_path(existing) == normalized: return
	var display := str(path_info.get("display_path", normalized))
	paths.append(display if bool(path_info.get("canonical", false)) else normalized)

static func _normalise_path(value: Variant) -> String:
	return str(_path_info(value, true).get("path", ""))

static func _path_info(value: Variant, allow_case_variant: bool = false) -> Dictionary:
	var raw := str(value)
	if raw.is_empty() or raw != raw.strip_edges(): return {"ok":false,"path":"","canonical":false,"code":"path_whitespace"}
	var slash := raw.replace("\\", "/")
	var has_scheme := slash.begins_with("res://")
	var remainder := slash.trim_prefix("res://") if has_scheme else slash
	if remainder.begins_with("/") or remainder.begins_with("~"): return {"ok":false,"path":"","canonical":false,"code":"path_absolute"}
	var parts := remainder.split("/", false)
	var stack: Array[String] = []
	var noncanonical := slash.contains("\\") or (slash.to_lower() != slash and not allow_case_variant)
	if remainder.contains("//") or remainder.ends_with("/"): noncanonical = true
	for part in parts:
		if part.is_empty():
			noncanonical = true
			continue
		if part == ".":
			noncanonical = true
			continue
		if part == "..":
			noncanonical = true
			if stack.is_empty(): return {"ok":false,"path":"","canonical":false,"code":"path_escape"}
			stack.pop_back()
			continue
		if part.contains(":"): return {"ok":false,"path":"","canonical":false,"code":"path_drive"}
		if part.ends_with(".") or part.ends_with(" "): return {"ok":false,"path":"","canonical":false,"code":"path_windows_trailing"}
		if _is_windows_reserved_component(part): return {"ok":false,"path":"","canonical":false,"code":"path_windows_reserved_device"}
		stack.append(part)
	var path := "res://" + "/".join(stack).to_lower()
	if stack.is_empty(): path = "res://"
	var canonical_spelling := ("res://" if has_scheme else "") + "/".join(stack)
	if canonical_spelling.is_empty(): canonical_spelling = "res://" if has_scheme else ""
	var lower_canonical := canonical_spelling.to_lower()
	var case_only := slash != lower_canonical and slash.to_lower() == lower_canonical
	if slash != canonical_spelling and not (allow_case_variant and case_only): noncanonical = true
	return {"ok":true,"path":path,"display_path":canonical_spelling,"canonical":not noncanonical,"case_only":case_only,"code":"path_case" if case_only else ""}

static func path_info(value: Variant) -> Dictionary:
	return _path_info(value)

static func _is_windows_reserved_component(part: String) -> bool:
	var trimmed := part.strip_edges()
	var base := trimmed
	var dot := base.find(".")
	if dot >= 0: base = base.substr(0, dot)
	base = base.strip_edges().to_lower()
	if base in ["con", "prn", "aux", "nul"]: return true
	if base.length() == 4 and (base.begins_with("com") or base.begins_with("lpt")):
		var suffix := base.substr(3, 1)
		return suffix >= "1" and suffix <= "9"
	return false

static func path_is_within(path: Variant, root: Variant) -> bool:
	var path_info := _path_info(path)
	var root_info := _path_info(root)
	if not bool(path_info.get("ok", false)) or not bool(root_info.get("ok", false)): return false
	var normalized_path := str(path_info.get("path", ""))
	var normalized_root := str(root_info.get("path", ""))
	if normalized_root == "res://": return normalized_path.begins_with("res://")
	return normalized_path == normalized_root or normalized_path.begins_with(normalized_root.trim_suffix("/") + "/")

static func _path_is_within(path: Variant, root: Variant) -> bool:
	return path_is_within(path, root)

static func _is_always_excluded(path: String) -> bool:
	var normalized := _normalise_path(path)
	for root in ALWAYS_EXCLUDED:
		if path_is_within(normalized, root): return true
	return false
