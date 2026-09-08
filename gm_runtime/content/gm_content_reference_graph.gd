@tool
class_name GMContentReferenceGraph
extends RefCounted

var library: GMContentLibrary
var edges: Array[Dictionary] = []
var issues: Array[Dictionary] = []
var cycles: Array[Array] = []
var incoming_by_id: Dictionary = {}
var outgoing_by_id: Dictionary = {}
var _visited_resources: Dictionary = {}

func build(content_library: GMContentLibrary, scan_roots: Array[String] = []) -> Dictionary:
	library = content_library
	edges.clear()
	issues.clear()
	cycles.clear()
	incoming_by_id.clear()
	outgoing_by_id.clear()
	_visited_resources.clear()
	var roots := scan_roots.duplicate()
	if roots.is_empty(): roots = library.roots.duplicate()
	for entry in library.entries:
		_walk_resource(str(entry.path), entry.resource, "资源", {})
	var scene_files: Array[String] = []
	for root in roots: _collect_scene_files(root, scene_files)
	for path in scene_files:
		var packed = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
		if packed == null:
			issues.append({"code":"scene.load_failed","path":path,"reason_zh":"PackedScene 无法加载，引用图已隔离该场景。","suggestion_zh":"检查场景的未知脚本或损坏外部资源。"})
			continue
		if packed is PackedScene: _walk_packed_scene(path, packed)
	for entry in library.entries:
		var count := get_incoming(str(entry.content_id)).size()
		library.set_usage_status(str(entry.content_id), "被引用" if count > 0 else "未使用", count)
	_detect_cycles()
	return snapshot()

func get_incoming(content_id_or_alias: String) -> Array[Dictionary]:
	var entry := library.entry_for_id(content_id_or_alias)
	var id := str(entry.get("content_id", content_id_or_alias))
	var result: Array[Dictionary] = []
	for edge in incoming_by_id.get(id, []): result.append(edge.duplicate(true))
	return result

func get_outgoing(content_id_or_alias: String) -> Array[Dictionary]:
	var entry := library.entry_for_id(content_id_or_alias)
	var id := str(entry.get("content_id", content_id_or_alias))
	var result: Array[Dictionary] = []
	for edge in outgoing_by_id.get(id, []): result.append(edge.duplicate(true))
	return result

func impact_analysis(content_id_or_alias: String, max_depth: int = 64) -> Dictionary:
	var entry := library.entry_for_id(content_id_or_alias)
	if entry.is_empty():
		return {"ok":false,"target_id":content_id_or_alias,"direct":[],"indirect":[],"chains":[],"error_zh":"找不到目标内容 ID：%s" % content_id_or_alias}
	var target_id := str(entry.content_id)
	var queue: Array[Dictionary] = [{"id":target_id,"depth":0,"chain":[]}]
	var visited := {target_id:true}
	var direct: Array[Dictionary] = []
	var indirect: Array[Dictionary] = []
	var chains: Array[Array] = []
	while not queue.is_empty():
		var current: Dictionary = queue.pop_front()
		var current_id := str(current.id)
		var depth := int(current.depth)
		for edge in get_incoming(current_id):
			var chain: Array = current.chain.duplicate(true)
			chain.append(edge)
			var source_id := str(edge.get("source_id", ""))
			var observation := edge.duplicate(true)
			observation["depth"] = depth + 1
			observation["chain"] = chain
			if depth == 0: direct.append(observation)
			else: indirect.append(observation)
			chains.append(chain)
			if not source_id.is_empty() and not visited.has(source_id) and depth + 1 < max_depth:
				visited[source_id] = true
				queue.append({"id":source_id,"depth":depth + 1,"chain":chain})
	var strong := direct.filter(func(item): return str(item.get("strength", "strong")) == "strong")
	return {"ok":true,"target_id":target_id,"target_path":entry.path,"direct":direct,"indirect":indirect,"chains":chains,"blocked_delete":not strong.is_empty(),"strong_incoming_count":strong.size(),"cycle_count":cycles.size()}

func can_delete(content_id_or_alias: String) -> Dictionary:
	var impact := impact_analysis(content_id_or_alias)
	if not impact.ok: return impact
	var allowed: bool = not bool(impact.get("blocked_delete", false))
	return {"ok":allowed,"can_delete":allowed,"target_id":impact.target_id,"strong_incoming_count":impact.strong_incoming_count,"impact":impact,"error_zh":"内容仍被引用，已阻止删除；请先处理反向引用。" if not allowed else ""}

func snapshot() -> Dictionary:
	return {"ok":issues.is_empty(),"edges":edges.duplicate(true),"issues":issues.duplicate(true),"cycles":cycles.duplicate(true),"edge_count":edges.size()}

func _walk_resource(source_path: String, resource: Resource, field_prefix: String, stack: Dictionary) -> void:
	if resource == null: return
	var key := "%s|%s" % [source_path, resource.get_instance_id()]
	if _visited_resources.has(key): return
	_visited_resources[key] = true
	if resource is GMContent:
		var content: GMContent = resource
		var source_id := content.content_id
		for spec in content.get_declared_reference_specs():
			_add_business_edge(source_path, source_id, str(spec.target_id), str(spec.kind), str(spec.field), str(spec.strength), str(spec.get("expected_type_id", "")), bool(spec.get("optional", false)))
	for property in resource.get_property_list():
		var usage := int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_STORAGE) == 0: continue
		var name := str(property.get("name", ""))
		if name in ["script", "resource_local_to_scene", "_edit_group_", "metadata/_edit_group_"]: continue
		var value = resource.get(name)
		_walk_value(source_path, _identity_for_resource(resource), value, "%s.%s" % [field_prefix, name], stack)

func _walk_value(source_path: String, source_id: String, value: Variant, field_path: String, stack: Dictionary) -> void:
	if value is Resource:
		var resource: Resource = value
		if resource is GMContentReference: return
		if resource is GMContent:
			var target_content: GMContent = resource
			var target_path: String = target_content.resource_path
			var target_id: String = target_content.content_id
			if target_path != source_path:
				_add_edge(source_path, source_id, target_path, target_id, "resource", field_path, "strong", true)
			_walk_resource(target_path if not target_path.is_empty() else source_path, resource, field_path, stack)
		return
	if value is Array or value is PackedStringArray:
		for item in value:
			if item is Resource: _walk_value(source_path, source_id, item, field_path, stack)
			elif item is Array or item is Dictionary: _walk_value(source_path, source_id, item, field_path, stack)
		return
	if value is Dictionary:
		for key in value:
			_walk_value(source_path, source_id, value[key], "%s[%s]" % [field_path, str(key)], stack)

func _walk_packed_scene(path: String, packed: PackedScene) -> void:
	var state := packed.get_state()
	var source_id := ""
	# Resolve the scene's own declared content_id before collecting the
	# remaining declaration fields so every scene edge can explain source→target
	# with the same stable business identity.
	for node_index in state.get_node_count():
		for property_index in state.get_node_property_count(node_index):
			var identity_name := str(state.get_node_property_name(node_index, property_index))
			if identity_name == "content_id":
				var identity_value = state.get_node_property_value(node_index, property_index)
				if identity_value is String:
					source_id = str(identity_value)
					break
		if not source_id.is_empty(): break
	for node_index in state.get_node_count():
		for property_index in state.get_node_property_count(node_index):
			var name := str(state.get_node_property_name(node_index, property_index))
			var value = state.get_node_property_value(node_index, property_index)
			if _is_declared_scene_field(name):
				_add_scene_declared_ids(path, source_id, name, value)
			_walk_value(path, source_id, value, "场景.%s.%s" % [str(state.get_node_name(node_index)), name], {})

func _add_scene_declared_ids(path: String, source_id: String, field_name: String, value: Variant) -> void:
	if value is String:
		if field_name == "content_id": return
		if field_name.ends_with("_content_id"):
			_add_business_edge(path, source_id, str(value), "business_id", field_name, "strong", "", false)
	elif value is PackedStringArray or value is Array:
		for item in value:
			if field_name == "ability_package_ids": _add_business_edge(path, source_id, str(item), "ability_package", field_name, "strong", "", false)
			else: _add_business_edge(path, source_id, str(item), "business_id", field_name, "strong", "", false)

func _is_declared_scene_field(field_name: String) -> bool:
	return field_name in ["content_id", "referenced_content_ids", "content_reference_ids", "ability_package_ids"] or field_name.ends_with("_content_id")

func _add_business_edge(source_path: String, source_id: String, target_id_value: String, kind: String, field: String, strength: String, expected_type_id: String, optional: bool) -> void:
	var target_entry := library.entry_for_id(target_id_value)
	if target_entry.is_empty() and target_id_value.begins_with("gm."):
		edges.append({"source_path":source_path,"source_id":source_id,"target_path":"","target_id":target_id_value,"kind":kind,"field":field,"strength":strength,"optional":optional,"expected_type_id":expected_type_id,"resolved":true,"external_platform":true,"chain_label":"%s → %s" % [source_id, target_id_value]})
		return
	if target_entry.is_empty():
		issues.append({"code":"reference.missing_target","path":source_path,"reason_zh":"声明式引用找不到目标业务 ID：%s（字段：%s）。" % [target_id_value, field],"suggestion_zh":"修正 ID、建立别名，或在删除前移除强引用。"})
		edges.append({"source_path":source_path,"source_id":source_id,"target_path":"","target_id":target_id_value,"kind":kind,"field":field,"strength":strength,"optional":optional,"expected_type_id":expected_type_id,"resolved":false,"chain_label":"%s → %s（缺失）" % [source_id, target_id_value]})
		return
	_add_edge(source_path, source_id, str(target_entry.path), str(target_entry.content_id), kind, field, strength, true, expected_type_id, optional)

func _add_edge(source_path: String, source_id: String, target_path: String, target_id: String, kind: String, field: String, strength: String, resolved: bool, expected_type_id: String = "", optional: bool = false) -> void:
	var edge := {"source_path":source_path,"source_id":source_id,"target_path":target_path,"target_id":target_id,"kind":kind,"field":field,"strength":strength,"optional":optional,"expected_type_id":expected_type_id,"resolved":resolved,"chain_label":"%s → %s" % [source_id if not source_id.is_empty() else source_path, target_id if not target_id.is_empty() else target_path]}
	edges.append(edge)
	if target_id.is_empty() or not resolved: return
	if not incoming_by_id.has(target_id): incoming_by_id[target_id] = []
	incoming_by_id[target_id].append(edge)
	if not source_id.is_empty():
		if not outgoing_by_id.has(source_id): outgoing_by_id[source_id] = []
		outgoing_by_id[source_id].append(edge)

func _identity_for_resource(resource: Resource) -> String:
	return resource.content_id if resource is GMContent else ""

func _detect_cycles() -> void:
	var graph := {}
	for edge in edges:
		var source_id := str(edge.get("source_id", ""))
		var target_id := str(edge.get("target_id", ""))
		if source_id.is_empty() or target_id.is_empty() or not bool(edge.get("resolved", false)): continue
		if not graph.has(source_id): graph[source_id] = []
		if not graph[source_id].has(target_id): graph[source_id].append(target_id)
	var visited := {}
	var stack := []
	for id in graph: _cycle_visit(str(id), graph, visited, stack)

func _cycle_visit(id: String, graph: Dictionary, visited: Dictionary, stack: Array) -> void:
	if stack.has(id):
		var start := stack.find(id)
		var cycle: Array = stack.slice(start)
		cycle.append(id)
		if not cycles.has(cycle): cycles.append(cycle)
		return
	if visited.has(id): return
	visited[id] = true
	stack.append(id)
	for next in graph.get(id, []): _cycle_visit(str(next), graph, visited, stack)
	stack.pop_back()

func _collect_scene_files(path: String, result: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty(): break
		if name in [".", "..", ".godot"]: continue
		var child := path.path_join(name)
		if dir.current_is_dir(): _collect_scene_files(child, result)
		elif name.ends_with(".tscn") or name.ends_with(".scn"): result.append(child)
	dir.list_dir_end()
