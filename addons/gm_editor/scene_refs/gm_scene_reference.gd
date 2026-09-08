@tool
class_name GMSceneReference
extends Resource

## 场景的语义引用：scene_business_id/content_id 是身份；资源路径只是可变
## 加载位置。节点移动、重命名和实例化不会改变业务引用。

@export var scene_business_id: String = ""
@export var scene_content_id: String = ""
@export_file("*.tscn", "*.scn") var scene_resource_path: String = ""
@export var root_node_id: String = ""
@export var expected_scene_kind: String = ""

func validate_definition() -> Dictionary:
	var errors: Array[Dictionary] = []
	if scene_business_id.strip_edges().is_empty() and scene_content_id.strip_edges().is_empty(): errors.append({"code": "scene.reference_identity_missing", "reason_zh": "场景引用必须声明稳定 scene_business_id 或 scene_content_id。", "field": "scene_business_id"})
	if not scene_resource_path.is_empty() and not FileAccess.file_exists(scene_resource_path): errors.append({"code": "scene.reference_path_missing", "reason_zh": "场景引用的加载位置不存在：%s；业务 ID 仍不可被路径替代。" % scene_resource_path, "field": "scene_resource_path"})
	return {"ok": errors.is_empty(), "code": "scene.reference_valid" if errors.is_empty() else "scene.reference_invalid", "errors": errors, "errors_zh": _messages(errors), "reference": to_dict()}

func resolve(root: Node, expected_node_id: String = "") -> Dictionary:
	if root == null or not is_instance_valid(root): return {"ok": false, "code": "scene.root_missing", "reason_zh": "场景引用解析失败：场景实例已释放。", "cause_chain": [scene_business_id, scene_content_id]}
	var identity := read_business_id(root)
	if not scene_business_id.is_empty() and identity != scene_business_id and not root_node_id.is_empty() and identity != root_node_id:
		return {"ok": false, "code": "scene.identity_mismatch", "reason_zh": "场景实例业务 ID 不匹配：期望 %s，实际 %s。" % [scene_business_id, identity], "cause_chain": [scene_business_id, identity]}
	var wanted := expected_node_id if not expected_node_id.is_empty() else root_node_id
	if wanted.is_empty(): return {"ok": true, "resolved": root, "scene_business_id": scene_business_id, "scene_content_id": scene_content_id, "cause_chain": [scene_business_id if not scene_business_id.is_empty() else scene_content_id]}
	var resolution := resolve_unique_node(root, wanted)
	if not resolution.ok:
		resolution["cause_chain"] = [scene_business_id, wanted]
		return resolution
	var found: Node = resolution.get("resolved", null)
	return {"ok": true, "code": "scene.node_resolved", "resolved": found, "scene_business_id": scene_business_id, "scene_content_id": scene_content_id, "node_business_id": wanted, "candidate_count": 1, "candidates": resolution.get("candidates", []), "cause_chain": [scene_business_id, wanted]}

func resolve_packed_scene() -> Dictionary:
	if scene_resource_path.is_empty(): return {"ok": false, "code": "scene.resource_path_missing", "reason_zh": "场景引用没有可加载位置；请由场景资源库按内容 ID 提供 PackedScene。"}
	var packed: Variant = ResourceLoader.load(scene_resource_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if packed == null or not packed is PackedScene: return {"ok": false, "code": "scene.load_failed", "reason_zh": "场景引用无法加载 PackedScene：%s。" % scene_resource_path, "cause_chain": [scene_business_id, scene_resource_path]}
	var instance: Node = packed.instantiate()
	var result := resolve(instance)
	if not result.ok: instance.free()
	else: result["packed_scene"] = packed
	return result

## Collect all live candidates before resolving. A stable ID is valid only when
## the candidate set has cardinality zero or one; traversal order never selects
## among multiple live nodes.
static func collect_business_id_candidates(root: Node, business_id: String) -> Array[Node]:
	var result: Array[Node] = []
	if root == null or not is_instance_valid(root) or business_id.strip_edges().is_empty(): return result
	_collect_business_id_candidates(root, business_id.strip_edges(), result)
	return result

static func resolve_unique_node(root: Node, business_id: String) -> Dictionary:
	var wanted := business_id.strip_edges()
	if root == null or not is_instance_valid(root):
		return {"ok": false, "code": "scene.root_missing", "reason_zh": "稳定业务 ID 解析失败：场景根节点已释放。", "business_id": wanted, "candidate_count": 0, "candidates": []}
	if wanted.is_empty():
		return {"ok": false, "code": "scene.node_id_missing", "reason_zh": "稳定业务 ID 解析失败：目标 ID 为空。", "business_id": wanted, "candidate_count": 0, "candidates": []}
	var pairs: Array[Dictionary] = []
	for node in collect_business_id_candidates(root, wanted): pairs.append({"node": node, "candidate": _candidate_info(node, wanted)})
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _candidate_sort_key(a) < _candidate_sort_key(b))
	var candidates: Array[Dictionary] = []
	for pair in pairs: candidates.append(pair.get("candidate", {}))
	if pairs.is_empty():
		return {"ok": false, "code": "scene.node_missing", "reason_zh": "场景引用找不到节点业务 ID：%s。" % wanted, "business_id": wanted, "candidate_count": 0, "candidates": candidates}
	if pairs.size() > 1:
		return {"ok": false, "code": "scene.node_ambiguous", "reason_zh": "稳定业务 ID %s 匹配到 %d 个节点，已拒绝按遍历顺序选取；请保证业务 ID 唯一。" % [wanted, pairs.size()], "business_id": wanted, "candidate_count": pairs.size(), "candidates": candidates}
	return {"ok": true, "code": "scene.node_resolved", "reason_zh": "", "resolved": pairs[0].get("node", null), "business_id": wanted, "candidate_count": 1, "candidates": candidates}

## Compatibility API: ambiguity is a hard miss, never the first DFS result.
static func find_by_business_id(root: Node, business_id: String) -> Node:
	var result := resolve_unique_node(root, business_id)
	return result.get("resolved", null) if bool(result.get("ok", false)) else null

static func read_business_id(node: Node) -> String:
	if node == null or not is_instance_valid(node): return ""
	if node.has_method("get_business_id"): return str(node.get_business_id())
	if node.has_method("get_gm_id"): return str(node.get_gm_id())
	for key in ["gm_id", "gm_content_id", "content_id", "anchor_id"]:
		if node.has_meta(key):
			var value := str(node.get_meta(key))
			if not value.is_empty(): return value
	return ""

static func validate_dependency_graph(graph: Dictionary) -> Dictionary:
	var cycles: Array[Array] = []
	var visited: Dictionary = {}
	var stack: Array = []
	for raw_id in graph.keys(): _visit_dependency(str(raw_id), graph, visited, stack, cycles)
	var errors: Array[Dictionary] = []
	for cycle in cycles: errors.append({"code": "scene.dependency_cycle", "reason_zh": "检测到循环场景依赖：%s。" % " → ".join(cycle), "cause_chain": cycle})
	return {"ok": errors.is_empty(), "cycles": cycles, "errors": errors, "errors_zh": _messages(errors), "graph_kind": "SceneDependency"}

static func _visit_dependency(id: String, graph: Dictionary, visited: Dictionary, stack: Array, cycles: Array[Array]) -> void:
	if stack.has(id):
		var cycle: Array = stack.slice(stack.find(id))
		cycle.append(id)
		if not cycles.has(cycle): cycles.append(cycle)
		return
	if visited.has(id): return
	visited[id] = true
	var next_stack := stack.duplicate()
	next_stack.append(id)
	var next: Variant = graph.get(id, [])
	if next is Array:
		for target in next: _visit_dependency(str(target), graph, visited, next_stack, cycles)

func to_dict() -> Dictionary:
	return {"scene_business_id": scene_business_id, "scene_content_id": scene_content_id, "scene_resource_path": scene_resource_path, "root_node_id": root_node_id, "expected_scene_kind": expected_scene_kind, "identity_policy": "stable_business_id_or_content_id; resource_path_is_locator_only"}

func _find_node_by_id(root: Node, wanted: String) -> Node:
	return find_by_business_id(root, wanted)

static func _collect_business_id_candidates(node: Node, wanted: String, result: Array[Node]) -> void:
	if node == null or not is_instance_valid(node): return
	if read_business_id(node) == wanted: result.append(node)
	for child in node.get_children():
		if child is Node: _collect_business_id_candidates(child, wanted, result)

static func _candidate_info(node: Node, wanted: String) -> Dictionary:
	return {"business_id": wanted, "locator": _node_locator(node), "node_name": node.name, "node_type": node.get_class(), "runtime_id": node.get_instance_id()}

static func _node_locator(node: Node) -> String:
	if node == null or not is_instance_valid(node): return ""
	if node.is_inside_tree(): return str(node.get_path())
	var names: Array[String] = []
	var current: Node = node
	while current != null and is_instance_valid(current):
		names.push_front(str(current.name))
		current = current.get_parent()
	return "<detached>/" + "/".join(names)

static func _candidate_sort_key(pair: Dictionary) -> String:
	var candidate: Dictionary = pair.get("candidate", {}) if pair.get("candidate", {}) is Dictionary else {}
	return "%s|%s|%s|%s" % [str(candidate.get("locator", "")), str(candidate.get("node_type", "")), str(candidate.get("node_name", "")), str(candidate.get("runtime_id", 0))]

static func _messages(errors: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for row in errors: result.append(str(row.get("reason_zh", "场景引用无效。")))
	return result
