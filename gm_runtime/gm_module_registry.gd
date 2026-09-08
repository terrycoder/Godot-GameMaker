class_name GMModuleRegistry
extends RefCounted

const SPATIAL_BACKEND_SCRIPT := preload("res://gm_runtime/spatial_core/gm_spatial_backend_declaration.gd")

const DEFAULT_INDEX_PATH := "res://gm_runtime/manifests/manifest_index.tres"
static var injected_manifests: Array[Resource] = []
static var validate_injected_references := true
static var _committed_snapshot: Dictionary = {}
static var _has_committed_snapshot := false
static var _last_refresh_error: Dictionary = {}
static var _committed_generation := 0

static func set_runtime_manifests(resources: Array[Resource], strict_references: bool = true) -> void:
	injected_manifests.clear()
	for resource in resources:
		injected_manifests.append(resource)
	validate_injected_references = strict_references

## refresh_result reports only the latest refresh operation.  Its failed
## candidate is never a read view and never replaces the committed snapshot.
static func refresh_result() -> Dictionary:
	var candidate := _load_candidate()
	if bool(candidate.get("ok", false)):
		var is_new_generation := not _has_committed_snapshot or _snapshot_signature(_committed_snapshot) != _snapshot_signature(candidate)
		if is_new_generation:
			# Candidate state is never exposed directly.  A successful candidate
			# replaces the committed snapshot as one atomic operation; an
			# equivalent candidate only clears the operation error and retains the
			# existing detached snapshot.
			_committed_snapshot = _clone_snapshot(candidate)
			_committed_generation += 1
		_committed_snapshot["generation"] = _committed_generation
		_committed_snapshot["ok"] = true
		_has_committed_snapshot = true
		_last_refresh_error = {}
		var committed_result := _public_snapshot(_committed_snapshot, true)
		committed_result["operation"] = "refresh"
		committed_result["committed_generation"] = _committed_generation
		return committed_result
	var failure := _candidate_failure(candidate)
	_last_refresh_error = failure.duplicate(true)
	failure["operation"] = "refresh"
	failure["committed_generation"] = _committed_generation
	failure["current_view_available"] = _has_committed_snapshot
	# A failed refresh is an operation failure only.  The committed snapshot is
	# still available to read APIs and runtime operations until a valid refresh.
	return failure

## registry_result remains the historical refresh-operation API.  Callers that
## need the current committed read view must use current_view_result or one of
## the read APIs below; they must not infer view validity from a failed refresh.
static func registry_result() -> Dictionary:
	return refresh_result()

static func current_view_result() -> Dictionary:
	if not _has_committed_snapshot:
		return {"ok":false,"manifests":{},"errors_zh":_last_refresh_error.get("errors_zh",[]),"sources":[],"resources":[],"index_path":_configured_index_path(),"generation":0,"current_view_available":false}
	var view := _public_snapshot(_committed_snapshot, true)
	view["generation"] = _committed_generation
	view["current_view_available"] = true
	view["last_refresh_error"] = _last_refresh_error.duplicate(true)
	return view

static func manifest_contract(selected: PackedStringArray = PackedStringArray()) -> Dictionary:
	var view := current_view_result()
	if not view.ok:
		return {"ok":false,"schema_version":"gm.task01.manifest-contract.v1","index_path":view.get("index_path", _configured_index_path()),"selected_modules":[],"modules":[],"error_zh":"当前已提交Manifest视图不可用"}
	var selected_ids: Array[String] = []
	if selected.is_empty():
		selected_ids = _sorted_keys(view.manifests)
	else:
		for raw_id in selected:
			var id := str(raw_id)
			if view.manifests.has(id) and not selected_ids.has(id): selected_ids.append(id)
		selected_ids.sort()
	var modules: Array[Dictionary] = []
	var ids := _sorted_keys(view.manifests)
	for id in ids:
		var data: Dictionary = view.manifests[id]
		modules.append({
			"module_id":id,
			"source_path":str(data.get("source_path", "")),
			"version":str(data.get("version", "")),
			"runtime_root":str(data.get("runtime_root", "")),
			"editor_root":str(data.get("editor_root", "")),
			"required_modules":_string_array(data.get("required_modules", [])),
			"runtime_services":_string_array(data.get("runtime_services", [])),
			"service_spec_paths":_string_array(data.get("service_spec_paths", [])),
			"spatial_backends":_spatial_backend_contract_rows(data.get("spatial_backends", []), id),
			"export_required_paths":_string_array(data.get("export_required_paths", [])),
			"export_excluded_paths":_string_array(data.get("export_excluded_paths", []))
		})
	return {"ok":true,"schema_version":"gm.task01.manifest-contract.v1","index_path":str(view.get("index_path", _configured_index_path())),"selected_modules":selected_ids,"modules":modules}

static func spatial_backend_contract(selected: PackedStringArray = PackedStringArray()) -> Dictionary:
	var contract := manifest_contract(selected)
	if not contract.ok:
		return {"ok": false, "schema_version": "gm.spatial.backend-contract.v1", "backends": [], "errors_zh": [str(contract.get("error_zh", "Manifest空间后端合同不可用。"))]}
	var rows: Array[Dictionary] = []
	var by_id: Dictionary = {}
	var errors: Array[String] = []
	var selected_modules: Array = contract.get("selected_modules", [])
	for module in contract.get("modules", []):
		var module_id := str(module.get("module_id", ""))
		if not selected_modules.is_empty() and not selected_modules.has(module_id): continue
		for raw_backend in module.get("spatial_backends", []):
			if not raw_backend is Dictionary:
				errors.append("模块%s的空间后端声明不是Dictionary。" % module_id)
				continue
			var row: Dictionary = raw_backend.duplicate(true)
			row["module_id"] = module_id
			row["source_path"] = str(module.get("source_path", ""))
			var backend_id := str(row.get("backend_id", ""))
			if by_id.has(backend_id):
				errors.append("空间后端ID重复：%s；来源=%s | %s" % [backend_id, str(by_id[backend_id].get("source_path", "")), str(row.get("source_path", ""))])
			else:
				by_id[backend_id] = row
				rows.append(row)
	rows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left.get("backend_id", "")) < str(right.get("backend_id", "")))
	return {"ok": errors.is_empty(), "schema_version": "gm.spatial.backend-contract.v1", "backends": rows, "errors_zh": errors, "selected_modules": contract.get("selected_modules", [])}

static func last_refresh_error() -> Dictionary:
	return _last_refresh_error.duplicate(true)

static func _load_candidate() -> Dictionary:
	var resources: Array[Resource] = []
	var sources: Array[String] = []
	if not injected_manifests.is_empty():
		for index in injected_manifests.size():
			resources.append(injected_manifests[index])
			sources.append(_resource_source(injected_manifests[index], "<injected:%d>" % index))
	else:
		var raw_index_path := OS.get_environment("GM_MODULE_INDEX_PATH").strip_edges()
		var index_path := DEFAULT_INDEX_PATH
		if not raw_index_path.is_empty():
			var index_info := _resource_path_details(raw_index_path)
			if not bool(index_info.get("ok", false)):
				return _candidate_failure({"errors_zh":["Manifest索引文件入口无效：%s；规范候选=%s；来源=%s" % [raw_index_path, str(index_info.get("normalized_candidate", "")), raw_index_path.replace("\\", "/")]],"index_path":raw_index_path.replace("\\", "/"),"raw_path":raw_index_path,"normalized_candidate":str(index_info.get("normalized_candidate", "")),"source_path":raw_index_path.replace("\\", "/"),"entry_kind":"index"})
			index_path = str(index_info.get("normalized", DEFAULT_INDEX_PATH))
		var index_resource = load(index_path)
		if index_resource == null:
			return _candidate_failure({"errors_zh":["Manifest索引无法读取：%s；原始入口=%s" % [index_path, raw_index_path]],"index_path":index_path,"raw_path":raw_index_path,"normalized_candidate":index_path,"source_path":index_path,"entry_kind":"index"})
		if not index_resource is GMModuleManifestIndex:
			return _candidate_failure({"errors_zh":["Manifest索引类型无效：%s；原始入口=%s" % [index_path, raw_index_path]],"index_path":index_path,"raw_path":raw_index_path,"normalized_candidate":index_path,"source_path":index_path,"entry_kind":"index"})
		# Manifest item path shape is checked below, one item at a time, so an
		# invalid item keeps its raw path, candidate and declaring Index identity.
		var index_errors: Array[String] = index_resource.schema_errors(false)
		if not index_errors.is_empty():
			var sourced_index_errors: Array[String] = []
			for index_error in index_errors: sourced_index_errors.append("%s；来源=%s" % [index_error, index_path])
			return _candidate_failure({"errors_zh":sourced_index_errors,"index_path":index_path,"raw_path":raw_index_path,"normalized_candidate":index_path,"source_path":index_path,"entry_kind":"index"})
		for manifest_path in index_resource.manifest_paths:
			var raw_manifest_path := str(manifest_path)
			var manifest_info := _resource_path_details(raw_manifest_path)
			if not bool(manifest_info.get("ok", false)):
				return _candidate_failure({"errors_zh":["Manifest索引项路径无效：%s；规范候选=%s；来源=%s" % [raw_manifest_path, str(manifest_info.get("normalized_candidate", "")), index_path]],"index_path":index_path,"raw_path":raw_manifest_path,"normalized_candidate":str(manifest_info.get("normalized_candidate", "")),"source_path":index_path,"index_source":index_path,"entry_kind":"manifest"})
			var normalized_path := str(manifest_info.get("normalized", ""))
			if normalized_path.is_empty():
				return _candidate_failure({"errors_zh":["Manifest索引项路径无效：%s；规范候选=%s；来源=%s" % [raw_manifest_path, str(manifest_info.get("normalized_candidate", "")), index_path]],"index_path":index_path,"raw_path":raw_manifest_path,"normalized_candidate":str(manifest_info.get("normalized_candidate", "")),"source_path":index_path,"index_source":index_path,"entry_kind":"manifest"})
			var resource = load(normalized_path)
			if resource == null:
				return _candidate_failure({"errors_zh":["Manifest索引项无法读取：%s；原始项=%s；来源=%s" % [normalized_path, raw_manifest_path, index_path]],"index_path":index_path,"raw_path":raw_manifest_path,"normalized_candidate":normalized_path,"source_path":index_path,"index_source":index_path,"entry_kind":"manifest"})
			resources.append(resource)
			sources.append(_resource_source(resource, normalized_path))
	var external_reference_ids: PackedStringArray = _canonical_module_ids() if not injected_manifests.is_empty() and validate_injected_references else PackedStringArray()
	return _build_snapshot(resources, sources, _configured_index_path(), external_reference_ids, validate_injected_references)

static func all_manifests() -> Dictionary:
	refresh_result()
	var view := current_view_result()
	return view.get("manifests", {}) if bool(view.get("ok", false)) else {}

static func manifest(module_id: String) -> Dictionary:
	refresh_result()
	var view := current_view_result()
	return view.get("manifests", {}).get(module_id, {}) if bool(view.get("ok", false)) else {}

static func resolve(selected: PackedStringArray) -> Dictionary:
	var refresh := refresh_result()
	var snapshot := current_view_result()
	if not snapshot.ok:
		var refresh_errors: Array = refresh.get("errors_zh", [])
		return {"ok":false,"selected":[],"errors_zh":refresh_errors,"manifests":{},"registry_errors":refresh_errors,"sources":[],"registry_refresh":refresh}
	var modules: Dictionary = snapshot.manifests
	var errors: Array[String] = []
	var chosen: Dictionary = {}
	for raw_id in selected:
		var id := str(raw_id)
		if id.is_empty():
			errors.append("选择的模块ID不能为空")
		elif id != id.strip_edges():
			errors.append("选择的模块ID不得包含首尾空白：%s" % id)
		elif not modules.has(id):
			errors.append("未知模块ID：%s" % id)
		else:
			chosen[id] = true
	if not errors.is_empty():
		return {"ok":false,"selected":_sorted_keys(chosen),"errors_zh":errors,"manifests":modules,"sources":snapshot.sources,"registry_generation":snapshot.generation,"registry_refresh":refresh}
	var pending: Array[String] = _sorted_keys(chosen)
	while not pending.is_empty():
		pending.sort()
		var id: String = pending.pop_front()
		var manifest_data: Dictionary = modules[id]
		var dependencies: Array[String] = []
		for dependency in manifest_data.get("required_modules", []): dependencies.append(str(dependency))
		dependencies.sort()
		for dependency in dependencies:
			if not modules.has(dependency):
				errors.append("模块%s依赖未知模块%s" % [id, dependency])
			elif not chosen.has(dependency):
				chosen[dependency] = true
				pending.append(dependency)
	var selected_ids: Array[String] = _sorted_keys(chosen)
	for left_index in range(selected_ids.size()):
		for right_index in range(left_index + 1, selected_ids.size()):
			var left: String = selected_ids[left_index]
			var right: String = selected_ids[right_index]
			var left_conflicts: Array = modules[left].get("conflicts", [])
			var right_conflicts: Array = modules[right].get("conflicts", [])
			if right in left_conflicts or left in right_conflicts:
				errors.append("模块冲突：%s 与 %s；来源=%s | %s" % [left, right, _source_for_module(modules, left), _source_for_module(modules, right)])
	return {"ok":errors.is_empty(),"selected":selected_ids,"errors_zh":errors,"manifests":modules,"sources":snapshot.sources,"registry_generation":snapshot.generation,"registry_refresh":refresh}

static func topological_order(selected: PackedStringArray) -> Dictionary:
	var plan := resolve(selected)
	if not plan.ok: return plan
	var modules: Dictionary = plan.manifests
	var selected_ids: Array[String] = plan.selected
	var selected_set: Dictionary = {}
	var indegree: Dictionary = {}
	var dependents: Dictionary = {}
	for id in selected_ids:
		selected_set[id] = true
		indegree[id] = 0
		dependents[id] = []
	for id in selected_ids:
		var dependencies: Array[String] = []
		for dependency in modules[id].get("required_modules", []): dependencies.append(str(dependency))
		dependencies.sort()
		for dependency in dependencies:
			if not selected_set.has(dependency): continue
			indegree[id] = int(indegree[id]) + 1
			var children: Array = dependents[dependency]
			children.append(id)
			children.sort()
			dependents[dependency] = children
	var ready: Array[String] = []
	for id in selected_ids:
		if int(indegree[id]) == 0: ready.append(id)
	ready.sort()
	var ordered: Array[String] = []
	while not ready.is_empty():
		ready.sort()
		var current: String = ready.pop_front()
		ordered.append(current)
		for child in dependents[current]:
			indegree[child] = int(indegree[child]) - 1
			if int(indegree[child]) == 0: ready.append(child)
	var errors: Array[String] = []
	if ordered.size() != selected_ids.size():
		var remaining: Array[String] = []
		for id in selected_ids:
			if not ordered.has(id): remaining.append(id)
		errors.append("循环依赖：%s" % " -> ".join(remaining))
	return {"ok":errors.is_empty(),"order":ordered,"errors_zh":errors,"selected":selected_ids,"manifests":modules,"sources":plan.sources,"registry_generation":plan.get("registry_generation", 0),"registry_refresh":plan.get("registry_refresh", {})}

static func validate_explicit(selected: PackedStringArray) -> Dictionary:
	var refresh := refresh_result()
	var snapshot := current_view_result()
	if not snapshot.ok:
		var refresh_errors: Array = refresh.get("errors_zh", [])
		return {"ok":false,"errors_zh":refresh_errors,"registry_errors":refresh_errors,"registry_refresh":refresh}
	var modules: Dictionary = snapshot.manifests
	var selected_set: Dictionary = {}
	var errors: Array[String] = []
	for raw_id in selected:
		var id := str(raw_id)
		if id.is_empty():
			errors.append("选择的模块ID不能为空")
		elif id != id.strip_edges():
			errors.append("选择的模块ID不得包含首尾空白：%s" % id)
		elif not modules.has(id):
			errors.append("未知模块ID：%s" % id)
		else:
			selected_set[id] = true
	for id in _sorted_keys(selected_set):
		for dependency in modules[id].get("required_modules", []):
			if not selected_set.has(str(dependency)):
				errors.append("不能关闭被依赖模块：%s 仍依赖 %s" % [id, dependency])
	return {"ok":errors.is_empty(),"errors_zh":errors,"selected":_sorted_keys(selected_set),"manifests":modules,"sources":snapshot.sources,"registry_generation":snapshot.generation,"registry_refresh":refresh}

static func validate_graph(graph: Dictionary) -> Dictionary:
	var visiting: Array[String] = []
	var visited: Array[String] = []
	var errors: Array[String] = []
	var ids: Array[String] = []
	for id in graph: ids.append(str(id))
	ids.sort()
	for id in ids: _cycle_visit(id, graph, visiting, visited, errors)
	return {"ok":errors.is_empty(),"errors_zh":errors}

static func _cycle_visit(id: String, graph: Dictionary, visiting: Array[String], visited: Array[String], errors: Array[String]) -> void:
	if visited.has(id): return
	if visiting.has(id):
		errors.append("循环依赖：%s -> %s" % [" -> ".join(visiting), id])
		return
	visiting.append(id)
	var dependencies: Array[String] = []
	for dependency in graph.get(id, []): dependencies.append(str(dependency))
	dependencies.sort()
	for dependency in dependencies: _cycle_visit(dependency, graph, visiting, visited, errors)
	visiting.erase(id)
	visited.append(id)

static func _configured_index_path() -> String:
	var configured := OS.get_environment("GM_MODULE_INDEX_PATH").strip_edges()
	if configured.is_empty(): return DEFAULT_INDEX_PATH
	var details := _resource_path_details(configured)
	return str(details.get("normalized", "")) if bool(details.get("ok", false)) else configured.replace("\\", "/")

static func _build_snapshot(resources: Array[Resource], sources: Array[String], index_path: String, external_reference_ids: PackedStringArray = PackedStringArray(), validate_references: bool = true) -> Dictionary:
	var modules: Dictionary = {}
	var source_by_id: Dictionary = {}
	var raw_source_by_id: Dictionary = {}
	var resource_by_id: Dictionary = {}
	var known_ids: PackedStringArray = []
	var errors: Array[String] = []
	for index in resources.size():
		var resource = resources[index]
		var raw_source := sources[index] if index < sources.size() else _resource_source(resource, "<resource:%d>" % index)
		if resource == null:
			errors.append("Manifest资源为空：来源=%s" % raw_source)
			continue
		if not resource is GMModuleManifest:
			errors.append("Manifest资源类型无效：来源=%s" % raw_source)
			continue
		var typed: GMModuleManifest = resource
		var id := typed.module_id
		if not id.strip_edges().is_empty() and not known_ids.has(id): known_ids.append(id)
		if modules.has(id):
			errors.append("Manifest模块ID重复：%s；来源A=%s；来源B=%s" % [id, raw_source_by_id[id], raw_source])
			continue
		var source := _stable_source(typed, raw_source, id)
		var data := _resource_to_dict(typed)
		data["source_path"] = source
		modules[id] = data
		source_by_id[id] = source
		raw_source_by_id[id] = raw_source
		resource_by_id[id] = _duplicate_resource(typed)
	for external_id in external_reference_ids:
		if not known_ids.has(external_id): known_ids.append(external_id)
	for id in modules:
		var resource_data: Dictionary = modules[id]
		var source := str(resource_data.get("source_path", ""))
		var resource = resource_by_id.get(id, null)
		if resource is GMModuleManifest:
			var schema_errors: Array[String] = resource.schema_errors(known_ids, validate_references)
			for error in schema_errors: errors.append("%s；来源=%s" % [error, source])
		else:
			var data_id := str(resource_data.get("module_id", id))
			if data_id.is_empty(): errors.append("Manifest模块ID不能为空；来源=%s" % source)
			var version := str(resource_data.get("version", ""))
			if version.strip_edges().is_empty(): errors.append("Manifest版本不能为空；来源=%s" % source)
	var ordered_sources: Array[String] = []
	var ordered_resources: Array[Resource] = []
	for id in _sorted_keys(modules):
		ordered_sources.append(str(source_by_id.get(id, "")))
		ordered_resources.append(_duplicate_resource(resource_by_id.get(id, null)))
	return {"ok":errors.is_empty(),"manifests":modules,"errors_zh":errors,"sources":ordered_sources,"resources":ordered_resources,"index_path":index_path}

static func _candidate_failure(candidate: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	for error in candidate.get("errors_zh", []): errors.append(str(error))
	var index_path := str(candidate.get("index_path", _configured_index_path()))
	var result := {"ok":false,"manifests":{},"errors_zh":errors,"sources":[],"resources":[],"index_path":index_path,"candidate_committed":false,"retained_valid_snapshot":_has_committed_snapshot,"retained_generation":_committed_generation}
	for field in ["raw_path","normalized_candidate","source_path","index_source","entry_kind"]:
		if candidate.has(field): result[field] = candidate.get(field)
	if _has_committed_snapshot:
		result["retained_view"] = _public_snapshot(_committed_snapshot, true)
	else:
		result["retained_view"] = {"ok":false,"manifests":{},"sources":[],"resources":[],"generation":0,"current_view_available":false}
	return result

static func _public_snapshot(snapshot: Dictionary, valid: bool) -> Dictionary:
	var result := _clone_snapshot(snapshot)
	result["ok"] = valid
	if not valid:
		result["manifests"] = {}
		result["sources"] = []
		result["resources"] = []
	return result

static func _resource_to_dict(resource: GMModuleManifest) -> Dictionary:
	var specs: Array = []
	var spec_paths: Array[String] = []
	if resource.service_specs != null:
		for spec in resource.service_specs:
			if spec is Resource and not spec.resource_path.is_empty():
				var normalized_spec_path := _normalise_resource_path(spec.resource_path)
				if not normalized_spec_path.is_empty(): spec_paths.append(normalized_spec_path)
			specs.append(_duplicate_resource(spec) if spec is Resource else spec)
	return {"module_id":resource.module_id,"source_path":resource.resource_path,"service_spec_paths":spec_paths,"version":resource.version,"display_name_zh":resource.display_name_zh,"description_zh":resource.description_zh,"runtime_root":resource.runtime_root,"editor_root":resource.editor_root,"required_modules":_copy_string_array(resource.required_modules),"optional_modules":_copy_string_array(resource.optional_modules),"conflicts":_copy_string_array(resource.conflicts),"content_types":_copy_string_array(resource.content_types),"abilities":_copy_string_array(resource.abilities),"effects":_copy_string_array(resource.effects),"events":_copy_string_array(resource.events),"cues":_copy_string_array(resource.cues),"tags":_copy_string_array(resource.tags),"runtime_services":_copy_string_array(resource.runtime_services),"runtime_service_implementations":_copy_string_array(resource.runtime_service_implementations),"service_specs":specs,"spatial_backends":_duplicate_spatial_backends(resource.spatial_backends),"editor_entries":_copy_string_array(resource.editor_entries),"export_required_paths":_copy_string_array(resource.export_required_paths),"export_excluded_paths":_copy_string_array(resource.export_excluded_paths),"validation_rules":_copy_string_array(resource.validation_rules),"migrations":_copy_string_array(resource.migrations),"license_notes":resource.license_notes,"release_security_profile":resource.release_security_profile,"native_runtime_dependencies":_copy_string_array(resource.native_runtime_dependencies),"private_build_artifacts":_copy_string_array(resource.private_build_artifacts)}

static func _resource_source(resource: Resource, fallback: String) -> String:
	if resource != null and not resource.resource_path.is_empty():
		var normalized_resource := _normalise_resource_path(resource.resource_path)
		return normalized_resource if not normalized_resource.is_empty() else resource.resource_path.replace("\\", "/")
	var normalized_fallback := _normalise_resource_path(str(fallback))
	return normalized_fallback if not normalized_fallback.is_empty() else str(fallback).replace("\\", "/")

static func _stable_source(resource: Resource, fallback: String, module_id: String) -> String:
	if resource != null and not resource.resource_path.is_empty():
		var normalized_resource := _normalise_resource_path(resource.resource_path)
		return normalized_resource if not normalized_resource.is_empty() else resource.resource_path.replace("\\", "/")
	var normalized_fallback := _normalise_resource_path(str(fallback))
	if normalized_fallback.is_empty(): normalized_fallback = str(fallback).replace("\\", "/")
	if normalized_fallback.begins_with("<injected:"):
		return "<injected:%s>" % module_id
	return normalized_fallback

static func _canonical_module_ids() -> PackedStringArray:
	var result: PackedStringArray = []
	var index_resource = load(DEFAULT_INDEX_PATH)
	if not index_resource is GMModuleManifestIndex: return result
	for manifest_path in index_resource.manifest_paths:
		var resource = load(_normalise_resource_path(str(manifest_path)))
		if resource is GMModuleManifest and not result.has(resource.module_id): result.append(resource.module_id)
	return result

static func _source_for_module(modules: Dictionary, id: String) -> String:
	return str(modules.get(id, {}).get("source_path", "<unknown>"))

static func _sorted_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value in values.keys(): result.append(str(value))
	result.sort()
	return result

static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array and not value is PackedStringArray: return result
	for item in value: result.append(str(item))
	return result

static func _snapshot_signature(snapshot: Dictionary) -> String:
	var ids: Array[String] = []
	var manifests: Dictionary = snapshot.get("manifests", {})
	for raw_id in manifests.keys(): ids.append(str(raw_id))
	ids.sort()
	var rows: Array[Dictionary] = []
	for id in ids:
		var data: Dictionary = manifests.get(id, {})
		rows.append({
			"module_id":id,
			"source_path":str(data.get("source_path", "")),
			"version":str(data.get("version", "")),
			"display_name_zh":str(data.get("display_name_zh", "")),
			"description_zh":str(data.get("description_zh", "")),
			"runtime_root":str(data.get("runtime_root", "")),
			"editor_root":str(data.get("editor_root", "")),
			"required_modules":_sorted_string_array(data.get("required_modules", [])),
			"optional_modules":_sorted_string_array(data.get("optional_modules", [])),
			"conflicts":_sorted_string_array(data.get("conflicts", [])),
			"content_types":_sorted_string_array(data.get("content_types", [])),
			"abilities":_sorted_string_array(data.get("abilities", [])),
			"effects":_sorted_string_array(data.get("effects", [])),
			"events":_sorted_string_array(data.get("events", [])),
			"cues":_sorted_string_array(data.get("cues", [])),
			"tags":_sorted_string_array(data.get("tags", [])),
			"runtime_services":_sorted_string_array(data.get("runtime_services", [])),
                        "runtime_service_implementations":_sorted_string_array(data.get("runtime_service_implementations", [])),
                        "service_spec_paths":_sorted_string_array(data.get("service_spec_paths", [])),
                        "service_specs":_service_spec_signature(data.get("service_specs", [])),
                        "spatial_backends":_spatial_backend_signature(data.get("spatial_backends", [])),
                        "editor_entries":_sorted_string_array(data.get("editor_entries", [])),
			"export_required_paths":_sorted_string_array(data.get("export_required_paths", [])),
			"export_excluded_paths":_sorted_string_array(data.get("export_excluded_paths", [])),
			"validation_rules":_sorted_string_array(data.get("validation_rules", [])),
			"migrations":_sorted_string_array(data.get("migrations", [])),
			"license_notes":str(data.get("license_notes", "")),
			"release_security_profile":str(data.get("release_security_profile", "")),
			"native_runtime_dependencies":_sorted_string_array(data.get("native_runtime_dependencies", [])),
			"private_build_artifacts":_sorted_string_array(data.get("private_build_artifacts", []))
		})
	return JSON.stringify({"index_path":_source_identity(str(snapshot.get("index_path", ""))),"sources":_bound_sources_signature(rows),"manifests":rows})

static func _sorted_string_array(value: Variant) -> Array[String]:
	var result := _string_array(value)
	result.sort()
	return result

static func _service_spec_signature(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array: return result
	for spec in value:
		if spec == null:
			result.append({"service_id":"","module_id":"","implementation":""})
			continue
		var implementation_path := ""
		if spec is Resource:
			var implementation = spec.get("implementation")
			if implementation is Resource: implementation_path = _source_identity(str(implementation.resource_path))
		var service_value = spec.get("service_id")
		var module_value = spec.get("module_id")
		result.append({"service_id":"" if service_value == null else str(service_value),"module_id":"" if module_value == null else str(module_value),"implementation":implementation_path})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return JSON.stringify(left) < JSON.stringify(right)
	)
	return result

static func _is_spatial_backend(value: Variant) -> bool:
	return value is Resource and value.get_script() == SPATIAL_BACKEND_SCRIPT

static func _duplicate_spatial_backends(value: Variant) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	for backend in value:
		if _is_spatial_backend(backend):
			result.append(_duplicate_spatial_backend(backend))
		else:
			result.append(backend)
	return result

static func _spatial_backend_contract_rows(value: Variant, module_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array: return result
	for raw_backend in value:
		if _is_spatial_backend(raw_backend):
			var row: Dictionary = Dictionary(raw_backend.call("to_native"))
			row["module_id"] = module_id
			result.append(row)
		elif raw_backend is Dictionary:
			var row: Dictionary = raw_backend.duplicate(true)
			row["module_id"] = module_id
			result.append(row)
	return result

static func _spatial_backend_signature(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array: return result
	for raw_backend in value:
		var row: Dictionary = {}
		if _is_spatial_backend(raw_backend): row = Dictionary(raw_backend.call("to_native"))
		elif raw_backend is Dictionary: row = raw_backend.duplicate(true)
		else: continue
		row["capabilities"] = _sorted_string_array(row.get("capabilities", []))
		result.append(row)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return JSON.stringify(left) < JSON.stringify(right))
	return result

static func _bound_sources_signature(rows: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in rows:
		result.append({"module_id":str(row.get("module_id", "")),"source_path":_source_identity(str(row.get("source_path", "")))})
	return result

static func _copy_string_array(value: Variant) -> PackedStringArray:
	var result: PackedStringArray = []
	if value is PackedStringArray or value is Array:
		for item in value: result.append(str(item))
	return result

static func _duplicate_resource(resource: Resource) -> Resource:
	if resource == null: return null
	if resource is GMModuleManifest: return _duplicate_manifest(resource)
	if resource is GMServiceSpec: return _duplicate_service_spec(resource)
	if _is_spatial_backend(resource): return _duplicate_spatial_backend(resource)
	var duplicate = resource.duplicate(true)
	if duplicate is Resource and duplicate != resource: return duplicate
	return resource

static func _duplicate_service_spec(resource: GMServiceSpec) -> GMServiceSpec:
	if resource == null: return null
	var copy := GMServiceSpec.new()
	copy.service_id = resource.service_id
	copy.module_id = resource.module_id
	copy.implementation = resource.implementation
	return copy

static func _duplicate_spatial_backend(resource: Resource) -> Resource:
	if resource == null: return null
	var copy: Resource = SPATIAL_BACKEND_SCRIPT.new()
	copy.set("backend_id", str(resource.get("backend_id")))
	copy.set("domain_id", str(resource.get("domain_id")))
	copy.set("capabilities", _copy_string_array(resource.get("capabilities")))
	copy.set("implementation_path", str(resource.get("implementation_path")))
	return copy

static func _duplicate_manifest(resource: GMModuleManifest) -> GMModuleManifest:
	if resource == null: return null
	var copy := GMModuleManifest.new()
	copy.module_id = resource.module_id
	copy.version = resource.version
	copy.display_name_zh = resource.display_name_zh
	copy.description_zh = resource.description_zh
	copy.runtime_root = resource.runtime_root
	copy.editor_root = resource.editor_root
	copy.required_modules = _copy_string_array(resource.required_modules)
	copy.optional_modules = _copy_string_array(resource.optional_modules)
	copy.conflicts = _copy_string_array(resource.conflicts)
	copy.content_types = _copy_string_array(resource.content_types)
	copy.abilities = _copy_string_array(resource.abilities)
	copy.effects = _copy_string_array(resource.effects)
	copy.events = _copy_string_array(resource.events)
	copy.cues = _copy_string_array(resource.cues)
	copy.tags = _copy_string_array(resource.tags)
	copy.runtime_services = _copy_string_array(resource.runtime_services)
	copy.runtime_service_implementations = _copy_string_array(resource.runtime_service_implementations)
	copy.service_specs = []
	for spec in resource.service_specs:
		if spec == null:
			copy.service_specs.append(null)
		elif spec is GMServiceSpec:
			copy.service_specs.append(_duplicate_service_spec(spec))
	copy.spatial_backends = []
	for backend in resource.spatial_backends:
		if backend == null:
			copy.spatial_backends.append(null)
		elif _is_spatial_backend(backend):
			copy.spatial_backends.append(_duplicate_spatial_backend(backend))
	copy.editor_entries = _copy_string_array(resource.editor_entries)
	copy.export_required_paths = _copy_string_array(resource.export_required_paths)
	copy.export_excluded_paths = _copy_string_array(resource.export_excluded_paths)
	copy.validation_rules = _copy_string_array(resource.validation_rules)
	copy.migrations = _copy_string_array(resource.migrations)
	copy.license_notes = resource.license_notes
	copy.release_security_profile = resource.release_security_profile
	copy.native_runtime_dependencies = _copy_string_array(resource.native_runtime_dependencies)
	copy.private_build_artifacts = _copy_string_array(resource.private_build_artifacts)
	return copy

static func _clone_snapshot(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	var cloned_manifests: Dictionary = {}
	for raw_id in snapshot.get("manifests", {}).keys():
		var id := str(raw_id)
		var data: Dictionary = snapshot.get("manifests", {}).get(raw_id, {})
		var cloned_data := data.duplicate(true)
		var cloned_specs: Array = []
		for spec in data.get("service_specs", []):
			cloned_specs.append(_duplicate_resource(spec) if spec is Resource else spec)
		cloned_data["service_specs"] = cloned_specs
		cloned_manifests[id] = cloned_data
	result["manifests"] = cloned_manifests
	var cloned_resources: Array[Resource] = []
	for resource in snapshot.get("resources", []):
		cloned_resources.append(_duplicate_resource(resource))
	result["resources"] = cloned_resources
	return result

static func _normalise_resource_path(value: String) -> String:
	var details := _resource_path_details(value)
	return str(details.get("normalized", "")) if bool(details.get("ok", false)) else ""

static func _resource_path_details(value: String) -> Dictionary:
	var original := str(value)
	var normalized_candidate := _lexical_normalise_resource_path(original)
	if original != original.strip_edges():
		return {"ok":false,"code":"whitespace","raw_path":original,"normalized_candidate":normalized_candidate}
	if _has_trailing_separator(original):
		return {"ok":false,"code":"trailing_separator","raw_path":original,"normalized_candidate":normalized_candidate}
	var raw := original.strip_edges().replace("\\", "/")
	if _has_trailing_separator(raw):
		return {"ok":false,"code":"trailing_separator","raw_path":original,"normalized_candidate":normalized_candidate}
	if raw.is_empty() or not raw.begins_with("res://"):
		return {"ok":false,"code":"scheme","raw_path":original,"normalized_candidate":normalized_candidate}
	var stack: Array[String] = []
	var file_node_path := ""
	var parts := raw.trim_prefix("res://").split("/", false)
	for part_index in parts.size():
		var part := str(parts[part_index])
		if not file_node_path.is_empty():
			return {"ok":false,"code":"file_boundary","raw_path":original,"normalized_candidate":normalized_candidate,"file_node":file_node_path}
		if part.is_empty() or part == ".": continue
		if part == "..":
			if stack.is_empty(): return {"ok":false,"code":"escape","raw_path":original,"normalized_candidate":normalized_candidate}
			stack.pop_back()
			continue
		if part.contains(":"): return {"ok":false,"code":"drive","raw_path":original,"normalized_candidate":normalized_candidate}
		stack.append(part)
		var current := "res://" + "/".join(stack)
		# A suffix such as `.tres` is not enough to establish a file node: a
		# real directory may legitimately carry that name.  Only an actual file
		# on disk creates a boundary; unresolved components remain unresolved
		# until the resource loader gives the caller an explicit failure.
		if FileAccess.file_exists(ProjectSettings.globalize_path(current)):
			file_node_path = current
	var normalized := "res://" + "/".join(stack)
	return {"ok":true,"normalized":normalized,"normalized_candidate":normalized_candidate,"raw_path":original}

static func _lexical_normalise_resource_path(value: String) -> String:
	var raw := str(value).strip_edges().replace("\\", "/")
	if raw.is_empty() or not raw.begins_with("res://"): return ""
	var stack: Array[String] = []
	for part in raw.trim_prefix("res://").split("/", false):
		if part.is_empty() or part == ".": continue
		if part == "..":
			if stack.is_empty(): return ""
			stack.pop_back()
			continue
		if part.contains(":"): return ""
		stack.append(part)
	return "res://" + "/".join(stack)

static func _has_trailing_separator(value: String) -> bool:
	return not value.is_empty() and (value.ends_with("/") or value.ends_with("\\"))

static func _source_identity(value: String) -> String:
	if value.begins_with("<injected:"): return value
	var normalized := _normalise_resource_path(value)
	return normalized.to_lower() if not normalized.is_empty() else value.replace("\\", "/").to_lower()
