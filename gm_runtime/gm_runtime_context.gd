class_name GMRuntimeContext
extends Node

const REGISTRY := preload("res://gm_runtime/gm_module_registry.gd")
const SPATIAL_DOMAIN := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")
const SPATIAL_CAPABILITIES := preload("res://gm_runtime/spatial_core/gm_spatial_backend_capabilities.gd")
const SPATIAL_QUERY_RESULT := preload("res://gm_runtime/spatial_core/gm_spatial_query_result.gd")
const SPATIAL_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

var installed_services: Dictionary = {}
var service_objects: Dictionary = {}
var lifecycle_log: Array[String] = []
var installed_modules: Array[String] = []
var service_install_order: Array[String] = []
var active_connections: Array[Dictionary] = []
var last_error_zh: String = ""
var injected_service_specs: Array[Resource] = []
var forced_service_specs: Array[Resource] = []
var installed_registry_generation: int = 0
## Spatial backend objects are runtime-only.  They are never included in a
## world snapshot, save payload, content resource or editor profile.
var spatial_backend_objects: Dictionary = {}
var active_spatial_backend_id: String = ""
var active_spatial_domain_id: String = ""
var active_spatial_capabilities: PackedStringArray = PackedStringArray()
var spatial_last_blocked: Dictionary = {}

func install(selected: PackedStringArray) -> Dictionary:
	var before := _snapshot_state()
	var plan: Dictionary = REGISTRY.topological_order(selected)
	if not plan.ok:
		last_error_zh = "; ".join(plan.get("errors_zh", []))
		return {"ok":false,"error_zh":last_error_zh,"stage":"registry"}
	var plan_generation := int(plan.get("registry_generation", 0))
	if not installed_modules.is_empty() and installed_registry_generation > 0 and plan_generation != installed_registry_generation:
		last_error_zh = "Registry提交代际已变化，必须先释放旧运行时快照"
		return {"ok":false,"error_zh":last_error_zh,"stage":"generation","installed_generation":installed_registry_generation,"requested_generation":plan_generation}
	var preflight := _preflight_services(plan)
	if not preflight.ok:
		last_error_zh = "; ".join(preflight.errors_zh)
		return {"ok":false,"error_zh":last_error_zh,"stage":"preflight"}
	var new_objects: Array = []
	var new_service_names: Array[String] = []
	var new_module_names: Array[String] = []
	for descriptor in preflight.descriptors:
		var service_id := str(descriptor.service_id)
		var implementation = descriptor.get("implementation", null)
		var object = _create_service_from_implementation(implementation, service_id)
		if object == null:
			return _fail_and_rollback(before, new_objects, "缺少必需服务实现：%s" % service_id, "instantiate")
		new_objects.append(object)
		var initialized := true
		if object.has_method("initialize"):
			initialized = bool(object.call("initialize", self))
		if not initialized:
			return _fail_and_rollback(before, new_objects, "模块服务初始化失败：%s" % service_id, "initialize")
		installed_services[service_id] = descriptor.module_id
		service_objects[service_id] = object
		service_install_order.append(service_id)
		new_service_names.append(service_id)
		lifecycle_log.append("install:%s" % service_id)
	for module_id in plan.order:
		if not installed_modules.has(str(module_id)):
			installed_modules.append(str(module_id))
			new_module_names.append(str(module_id))
	installed_registry_generation = plan_generation
	last_error_zh = ""
	return {"ok":true,"modules":installed_modules.duplicate(),"services":installed_services.keys().duplicate(),"new_services":new_service_names,"new_modules":new_module_names,"registry_generation":installed_registry_generation}

func release() -> void:
	clear_spatial_backends()
	_disconnect_connections_after(0)
	var names: Array[String] = service_install_order.duplicate()
	if names.is_empty():
		for service in installed_services.keys(): names.append(str(service))
		names.sort()
	for index in range(names.size() - 1, -1, -1):
		var service: String = names[index]
		var object = service_objects.get(service, null)
		if object != null and object != self and object.has_method("shutdown"):
			object.call("shutdown")
		if installed_services.has(service): lifecycle_log.append("shutdown:%s" % service)
	service_install_order.clear()
	service_objects.clear()
	installed_services.clear()
	installed_modules.clear()
	active_connections.clear()
	installed_registry_generation = 0

func register_spatial_backend(backend_id: String, backend_object: Object, domain_id: String = "", declared_capabilities: PackedStringArray = PackedStringArray()) -> Dictionary:
	var normalized_backend_id := backend_id.strip_edges()
	if not SPATIAL_POSITION.is_valid_stable_id(normalized_backend_id):
		return _spatial_block("spatial.backend.id_invalid", "空间后端ID无效。", {"backend_id": backend_id})
	if backend_object == null or not is_instance_valid(backend_object):
		return _spatial_block("spatial.backend.object_missing", "空间后端实例不可用。", {"backend_id": normalized_backend_id})
	if spatial_backend_objects.has(normalized_backend_id):
		return _spatial_block("spatial.backend.duplicate", "空间后端ID重复注册，已拒绝覆盖。", {"backend_id": normalized_backend_id})
	if backend_object.has_method("capabilities"):
		var capability_object = backend_object.call("capabilities")
		if capability_object == null or not capability_object.has_method("domain_id") or not capability_object.has_method("supported"):
			return _spatial_block("spatial.backend.capability_mismatch", "空间后端没有可验证的能力合同。", {"backend_id": normalized_backend_id})
		var actual_domain := str(capability_object.call("domain_id"))
		var actual_capabilities := PackedStringArray(capability_object.call("supported"))
		if not domain_id.is_empty() and actual_domain != domain_id:
			return _spatial_block("spatial.backend.capability_mismatch", "空间后端域与声明不一致。", {"backend_id": normalized_backend_id, "declared_domain_id": domain_id, "actual_domain_id": actual_domain})
		if not declared_capabilities.is_empty() and _sorted_capabilities(actual_capabilities) != _sorted_capabilities(declared_capabilities):
			return _spatial_block("spatial.backend.capability_mismatch", "空间后端能力集合与声明不一致。", {"backend_id": normalized_backend_id, "declared": Array(declared_capabilities), "actual": Array(actual_capabilities)})
		domain_id = actual_domain
		declared_capabilities = actual_capabilities
	else:
		return _spatial_block("spatial.backend.interface_missing", "空间后端缺少capabilities接口。", {"backend_id": normalized_backend_id})
	var domain := SPATIAL_DOMAIN.validate_id(domain_id)
	if not domain.ok: return _spatial_block("spatial.backend.domain_invalid", "空间后端空间域无效。", {"backend_id": normalized_backend_id, "domain_id": domain_id})
	if not domain.get("execution_available", false):
		return _spatial_block("spatial.backend.domain_unavailable", "该空间域尚无可用执行后端，已失败关闭。", {"backend_id": normalized_backend_id, "domain_id": domain_id})
	spatial_backend_objects[normalized_backend_id] = {"object": backend_object, "domain_id": domain_id, "capabilities": _sorted_capabilities(declared_capabilities)}
	return {"ok": true, "backend_id": normalized_backend_id, "domain_id": domain_id, "capabilities": Array(_sorted_capabilities(declared_capabilities))}

func activate_spatial_backend(backend_id: String, backend_object: Object = null, semantic_registry: Object = null, selected_modules: PackedStringArray = PackedStringArray()) -> Dictionary:
	var normalized_backend_id := backend_id.strip_edges()
	if not active_spatial_backend_id.is_empty():
		if active_spatial_backend_id == normalized_backend_id:
			return {"ok": true, "active": true, "backend_id": active_spatial_backend_id, "domain_id": active_spatial_domain_id, "capabilities": Array(active_spatial_capabilities), "idempotent": true}
		return _spatial_block("spatial.backend.duplicate", "同一SceneContext只能激活一个空间执行后端。", {"active_backend_id": active_spatial_backend_id, "requested_backend_id": normalized_backend_id})
	# Activation is a runtime entry point, so make sure it observes the current
	# committed Manifest view even when the caller did not perform a separate
	# refresh first.
	var refresh := REGISTRY.refresh_result()
	if not refresh.ok: return _spatial_block("spatial.backend.contract_invalid", "Manifest空间后端合同刷新失败。", {"errors_zh": refresh.get("errors_zh", [])})
	var contract := REGISTRY.spatial_backend_contract(selected_modules)
	if not contract.ok: return _spatial_block("spatial.backend.contract_invalid", "Manifest空间后端合同不可用。", {"errors_zh": contract.get("errors_zh", [])})
	var rows: Array = []
	for row in contract.get("backends", []):
		if str(row.get("backend_id", "")) == normalized_backend_id: rows.append(row)
	if rows.size() == 0 and backend_object == null:
		return _spatial_block("spatial.backend.missing", "所选Manifest未注册请求的空间后端。", {"backend_id": normalized_backend_id})
	if rows.size() > 1:
		return _spatial_block("spatial.backend.duplicate", "Manifest注册了重复的空间后端ID。", {"backend_id": normalized_backend_id})
	var row: Dictionary = rows[0] if not rows.is_empty() else {}
	var domain_id := str(row.get("domain_id", ""))
	var declared := PackedStringArray(row.get("capabilities", []))
	if domain_id.is_empty() and backend_object != null and backend_object.has_method("capabilities"):
		var object_capabilities = backend_object.call("capabilities")
		if object_capabilities != null and object_capabilities.has_method("domain_id"): domain_id = str(object_capabilities.call("domain_id"))
	var domain := SPATIAL_DOMAIN.validate_id(domain_id)
	if not domain.ok: return _spatial_block("spatial.backend.domain_invalid", "空间后端域声明无效。", {"backend_id": normalized_backend_id, "domain_id": domain_id})
	# EXT01's reserved-domain probe must remain fail-closed.  EXT02 becomes
	# executable only through its official manifest row, never through an
	# injected test declaration or an arbitrary backend object.
	if domain_id == SPATIAL_DOMAIN.PLANAR_3D and str(row.get("module_id", "")) != "spatial.planar_3d":
		return _spatial_block("spatial.backend.domain_unavailable", "PLANAR_3D执行后端必须来自正式EXT02模块，当前声明已失败关闭。", {"backend_id": normalized_backend_id, "domain_id": domain_id, "module_id": str(row.get("module_id", ""))})
	if not domain.get("execution_available", false):
		return _spatial_block("spatial.backend.domain_unavailable", "该空间域尚无可用执行后端，已失败关闭。", {"backend_id": normalized_backend_id, "domain_id": domain_id})
	if backend_object == null:
		var implementation_path := str(row.get("implementation_path", ""))
		var implementation = load(implementation_path)
		if not implementation is Script: return _spatial_block("spatial.backend.implementation_missing", "空间后端实现脚本不可用。", {"backend_id": normalized_backend_id, "implementation_path": implementation_path})
		backend_object = implementation.new(semantic_registry, true)
	var registered := register_spatial_backend(normalized_backend_id, backend_object, domain_id, declared)
	if not registered.ok: return registered
	active_spatial_backend_id = normalized_backend_id
	active_spatial_domain_id = str(registered.get("domain_id", domain_id))
	active_spatial_capabilities = PackedStringArray(registered.get("capabilities", []))
	spatial_last_blocked = {}
	return {"ok": true, "active": true, "backend_id": active_spatial_backend_id, "domain_id": active_spatial_domain_id, "capabilities": Array(active_spatial_capabilities)}

func clear_spatial_backends() -> void:
	for row in spatial_backend_objects.values():
		var backend = row.get("object", null) if row is Dictionary else null
		if backend != null and is_instance_valid(backend) and backend.has_method("shutdown"): backend.call("shutdown")
	spatial_backend_objects.clear()
	active_spatial_backend_id = ""
	active_spatial_domain_id = ""
	active_spatial_capabilities = PackedStringArray()
	spatial_last_blocked = {}

func has_active_spatial_backend() -> bool:
	return not active_spatial_backend_id.is_empty() and spatial_backend_objects.has(active_spatial_backend_id)

func spatial_backend() -> Object:
	if not has_active_spatial_backend(): return null
	return spatial_backend_objects[active_spatial_backend_id].get("object", null)

func spatial_capabilities():
	return SPATIAL_CAPABILITIES.new(active_spatial_domain_id, active_spatial_capabilities)

func query_spatial(capability_id: String, method_name: String, arguments: Array = []) -> Dictionary:
	if not has_active_spatial_backend(): return _spatial_block("spatial.backend.missing", "SceneContext没有激活空间执行后端。")
	var capability := spatial_capabilities().query(capability_id)
	if not capability.ok: return _spatial_block("spatial.capability.unsupported", str(capability.get("error_zh", "空间能力不可用。")), {"capability_id": capability_id})
	var backend := spatial_backend()
	if backend == null or not backend.has_method(method_name): return _spatial_block("spatial.backend.interface_missing", "空间后端缺少请求的查询接口。", {"capability_id": capability_id, "method": method_name})
	var raw = backend.callv(method_name, arguments)
	if not raw is Dictionary: return _spatial_block("spatial.query.invalid_result", "空间后端返回了不可验证的结果。", {"capability_id": capability_id, "method": method_name})
	var validated := SPATIAL_QUERY_RESULT.validate_native(raw)
	if not validated.ok: return _spatial_block("spatial.query.invalid_result", "空间查询结果未通过结构化结果校验。", {"validation": validated})
	if not raw.ok: spatial_last_blocked = raw.get("blocked_reason", {}).duplicate(true) if raw.get("blocked_reason", {}) is Dictionary else {}
	return raw.duplicate(true)

func spatial_snapshot_state() -> Dictionary:
	if not has_active_spatial_backend(): return {}
	var result := {"schema_version": 1, "backend_id": active_spatial_backend_id, "domain_id": active_spatial_domain_id, "capabilities": Array(active_spatial_capabilities)}
	var backend := spatial_backend()
	if backend != null and backend.has_method("map_snapshot_state"):
		result["map_state"] = backend.call("map_snapshot_state")
	return result

func validate_spatial_snapshot_state(value: Variant) -> Dictionary:
	if value == null or value == {}: return {"ok": true, "inactive": true}
	if not value is Dictionary: return _spatial_block("spatial.snapshot.invalid", "空间快照状态必须是Dictionary。")
	if not has_active_spatial_backend(): return _spatial_block("spatial.backend.missing", "空间快照包含后端状态，但当前SceneContext没有对应执行后端。")
	for key in ["schema_version", "backend_id", "domain_id", "capabilities"]:
		if not value.has(key): return _spatial_block("spatial.snapshot.invalid", "空间快照状态缺少字段：%s" % key)
	if int(value.get("schema_version", -1)) != 1 or str(value.get("backend_id", "")) != active_spatial_backend_id or str(value.get("domain_id", "")) != active_spatial_domain_id:
		return _spatial_block("spatial.snapshot.invalid", "空间快照状态与当前空间后端不一致。")
	var snapshot_capabilities := _sorted_capabilities(PackedStringArray(value.get("capabilities", [])))
	if snapshot_capabilities != _sorted_capabilities(active_spatial_capabilities): return _spatial_block("spatial.snapshot.invalid", "空间快照能力集合与当前后端不一致。")
	if value.has("map_state"):
		var backend := spatial_backend()
		if backend == null or not backend.has_method("validate_map_snapshot_state"):
			return _spatial_block("spatial.snapshot.invalid", "空间快照包含地图Graph，但当前后端不支持Graph快照校验。")
		var map_result = backend.call("validate_map_snapshot_state", value.get("map_state"))
		if not map_result is Dictionary or not bool(map_result.get("ok", false)):
			return _spatial_block("spatial.snapshot.invalid", "空间地图Graph快照校验失败。", {"details": map_result})
	return {"ok": true}

func restore_spatial_map_snapshot_state(value: Variant) -> Dictionary:
	if not has_active_spatial_backend(): return _spatial_block("spatial.backend.missing", "当前SceneContext没有可恢复的空间执行后端。")
	var backend := spatial_backend()
	if backend == null or not backend.has_method("restore_map_snapshot_state"):
		return _spatial_block("spatial.snapshot.invalid", "当前空间后端不支持地图Graph快照恢复。")
	var result = backend.call("restore_map_snapshot_state", value)
	return result if result is Dictionary else _spatial_block("spatial.snapshot.invalid", "地图Graph快照恢复返回了不可验证结果。")

func validate_spatial_registry_against_map_state(registry: Object, map_state: Variant) -> Dictionary:
	if not has_active_spatial_backend(): return _spatial_block("spatial.backend.missing", "当前SceneContext没有可用的空间执行后端。")
	var backend := spatial_backend()
	if backend == null or not backend.has_method("validate_registry_positions"):
		return _spatial_block("spatial.snapshot.invalid", "当前空间后端不支持暂存Graph上的实体位置校验。")
	var result = backend.call("validate_registry_positions", registry, map_state)
	return result if result is Dictionary else _spatial_block("spatial.snapshot.invalid", "暂存Graph实体位置校验返回了不可验证结果。")

func spatial_map_snapshot_state() -> Dictionary:
	if not has_active_spatial_backend(): return {}
	var backend := spatial_backend()
	if backend != null and backend.has_method("map_snapshot_state"):
		var value = backend.call("map_snapshot_state")
		return value.duplicate(true) if value is Dictionary else {}
	return {}

func configure_spatial_map_graph(graph: Resource) -> Dictionary:
	if not has_active_spatial_backend(): return _spatial_block("spatial.backend.missing", "当前SceneContext没有激活空间执行后端。")
	var backend := spatial_backend()
	if backend == null or not backend.has_method("configure_graph"):
		return _spatial_block("spatial.backend.interface_missing", "当前空间后端不支持Surface Graph配置。")
	var result = backend.call("configure_graph", graph)
	return result if result is Dictionary else _spatial_block("spatial.graph.invalid_result", "Surface Graph配置返回了不可验证结果。")

func _sorted_capabilities(value: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray(value)
	result.sort()
	return result

func _spatial_block(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := SPATIAL_QUERY_RESULT.blocked(code, reason_zh, active_spatial_domain_id, "", details)
	spatial_last_blocked = result.get("blocked_reason", {}).duplicate(true) if result.get("blocked_reason", {}) is Dictionary else {}
	return result

func connect_signal(source: Object, signal_name: String, callback: Callable) -> Dictionary:
	if source == null or not source.has_signal(signal_name):
		return {"ok":false,"error_zh":"信号不存在：%s" % signal_name}
	if source.is_connected(signal_name, callback):
		return {"ok":false,"error_zh":"重复信号连接：%s" % signal_name}
	var code := source.connect(signal_name, callback)
	if code != OK:
		return {"ok":false,"error_zh":"信号连接失败：%s" % signal_name}
	active_connections.append({"source":source,"signal":signal_name,"callback":callback})
	return {"ok":true}

func disconnect_signal(source: Object, signal_name: String, callback: Callable) -> bool:
	if source == null or not source.has_signal(signal_name): return false
	if source.is_connected(signal_name, callback): source.disconnect(signal_name, callback)
	for index in range(active_connections.size() - 1, -1, -1):
		var item: Dictionary = active_connections[index]
		if item.get("source") == source and str(item.get("signal", "")) == signal_name and item.get("callback") == callback:
			active_connections.remove_at(index)
	return true

func _preflight_services(plan: Dictionary) -> Dictionary:
	var descriptors: Array[Dictionary] = []
	var seen_new_services: Dictionary = {}
	var errors: Array[String] = []
	for module_id in plan.order:
		var id := str(module_id)
		if installed_modules.has(id): continue
		var manifest: Dictionary = plan.manifests.get(id, {})
		var service_ids: Array[String] = []
		for raw_service in manifest.get("runtime_services", []):
			var service_id := str(raw_service).strip_edges()
			if service_id.is_empty():
				errors.append("模块%s声明空服务ID" % id)
			elif service_ids.has(service_id):
				errors.append("模块%s重复服务ID：%s" % [id, service_id])
			else:
				service_ids.append(service_id)
		for spec in injected_service_specs:
			_add_extension_service_id(spec, id, service_ids, errors)
		for spec in forced_service_specs:
			_add_extension_service_id(spec, id, service_ids, errors)
		for service_id in service_ids:
			if installed_services.has(service_id):
				errors.append("重复服务ID：%s；现有模块=%s；新模块=%s" % [service_id, installed_services[service_id], id])
				continue
			if seen_new_services.has(service_id):
				errors.append("重复服务ID：%s；模块A=%s；模块B=%s" % [service_id, seen_new_services[service_id], id])
				continue
			seen_new_services[service_id] = id
			var implementation = _find_service_implementation(manifest, id, service_id)
			if implementation == null:
				errors.append("缺少必需服务实现：%s；模块=%s" % [service_id, id])
			else:
				descriptors.append({"module_id":id,"service_id":service_id,"implementation":implementation})
	return {"ok":errors.is_empty(),"errors_zh":errors,"descriptors":descriptors}

func _add_extension_service_id(spec: Resource, module_id: String, service_ids: Array[String], errors: Array[String]) -> void:
	if spec == null or _spec_value(spec, "module_id") != module_id: return
	var service_id := _spec_value(spec, "service_id").strip_edges()
	if service_id.is_empty():
		errors.append("模块%s的扩展ServiceSpec缺少服务ID" % module_id)
		return
	if service_ids.has(service_id): return
	service_ids.append(service_id)

func _find_service_implementation(manifest: Dictionary, module_id: String, service_id: String):
	if service_id == "gm.runtime_context": return self
	for spec in manifest.get("service_specs", []):
		if spec != null and _spec_value(spec, "service_id") == service_id:
			var implementation = spec.get("implementation")
			if implementation != null: return implementation
	for spec in injected_service_specs:
		if spec != null and _spec_value(spec, "module_id") == module_id and _spec_value(spec, "service_id") == service_id:
			var implementation = spec.get("implementation")
			if implementation != null: return implementation
	for spec in forced_service_specs:
		if spec != null and _spec_value(spec, "module_id") == module_id and _spec_value(spec, "service_id") == service_id:
			var implementation = spec.get("implementation")
			if implementation != null: return implementation
	for raw_mapping in manifest.get("runtime_service_implementations", []):
		var mapping := str(raw_mapping).split("=", true, 1)
		if mapping.size() != 2 or mapping[0].strip_edges() != service_id: continue
		var path := mapping[1].strip_edges()
		var loaded = load(path)
		if loaded is Script: return loaded
	return null

func _spec_value(spec: Resource, field_name: String) -> String:
	if spec == null: return ""
	var value = spec.get(field_name)
	return "" if value == null else str(value)

func _create_service_from_implementation(implementation, service_id: String):
	if service_id == "gm.runtime_context": return self
	if implementation == null or not implementation is Script: return null
	return implementation.new()

func _snapshot_state() -> Dictionary:
	return {"installed_services":installed_services.duplicate(),"service_objects":service_objects.duplicate(),"installed_modules":installed_modules.duplicate(),"service_install_order":service_install_order.duplicate(),"active_connections":active_connections.duplicate(),"lifecycle_log":lifecycle_log.duplicate(),"installed_registry_generation":installed_registry_generation}

func _fail_and_rollback(before: Dictionary, new_objects: Array, error_zh: String, stage: String) -> Dictionary:
	_disconnect_connections_after(int(before.active_connections.size()))
	for index in range(new_objects.size() - 1, -1, -1):
		var object = new_objects[index]
		if object != null and object != self and object.has_method("shutdown"): object.call("shutdown")
	installed_services = before.installed_services
	service_objects = before.service_objects
	installed_modules = before.installed_modules
	service_install_order = before.service_install_order
	active_connections = before.active_connections
	lifecycle_log = before.lifecycle_log
	installed_registry_generation = int(before.get("installed_registry_generation", 0))
	last_error_zh = error_zh
	return {"ok":false,"error_zh":error_zh,"stage":stage,"rolled_back":true}

func _disconnect_connections_after(count: int) -> void:
	for index in range(active_connections.size() - 1, count - 1, -1):
		var item: Dictionary = active_connections[index]
		var source = item.get("source", null)
		var signal_name := str(item.get("signal", ""))
		var callback: Callable = item.get("callback", Callable())
		if source != null and is_instance_valid(source) and source.has_signal(signal_name) and source.is_connected(signal_name, callback):
			source.disconnect(signal_name, callback)
		active_connections.remove_at(index)
