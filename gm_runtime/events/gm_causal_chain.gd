class_name GMCausalChain
extends RefCounted

## 可验证的有向无环因果链。

var chain_id: String = ""
var root_ref_id: String = ""
var refs_by_id: Dictionary = {}
var links: Array[Dictionary] = []

func _init(p_chain_id: String = "") -> void:
	chain_id = p_chain_id if not p_chain_id.is_empty() else "gm.causal.chain.%d" % Time.get_ticks_usec()

static func from_activation_request(request: GMAbilityActivationRequest) -> GMCausalChain:
	var identity := request.request_id if request != null and not request.request_id.is_empty() else "request.unknown"
	var key := request.idempotency_key if request != null and not request.idempotency_key.is_empty() else identity
	var material := "gm.causal.chain|v2|activation_request|%s" % key
	var chain := GMCausalChain.new("gm.causal.chain.v2.%s" % material.sha256_text())
	var source := request.source if request != null else ""
	chain.add_ref(GMCausalRef.request(identity, source), [])
	return chain

static func from_dict(value: Dictionary) -> GMCausalChain:
	var expected:=["chain_id","root_ref_id","refs","links","depth","validation"]
	if value.size()!=expected.size():return null
	for field in expected:
		if not value.has(field):return null
	if typeof(value.chain_id)!=TYPE_STRING or typeof(value.root_ref_id)!=TYPE_STRING or not value.refs is Array or not value.links is Array or typeof(value.depth)!=TYPE_INT or not value.validation is Dictionary:return null
	var result:=GMCausalChain.new(value.chain_id);result.root_ref_id=value.root_ref_id
	for ref_value in value.refs:
		if not ref_value is Dictionary:return null
		var ref:=GMCausalRef.from_dict(ref_value)
		if ref==null or not ref.validate().ok or result.refs_by_id.has(ref.stable_id):return null
		result.refs_by_id[ref.stable_id]=ref
	for link_value in value.links:
		if not link_value is Dictionary:return null
		result.links.append(link_value.duplicate(true))
	if not result.validate().ok or result.depth()!=int(value.depth):return null
	var canonical:=result.to_dict()
	if canonical!=value:return null
	return result

func bind_ability_instance_identity(instance_id: String) -> Dictionary:
	if instance_id.is_empty(): return {"ok": false, "code": "causal.instance_identity_missing", "reason_zh": "因果链缺少能力实例身份。"}
	chain_id = "gm.causal.chain.v2.%s" % ("gm.causal.chain|v2|ability_instance|%s" % instance_id).sha256_text()
	return {"ok": true, "chain_id": chain_id, "instance_id": instance_id}

func add_ref(ref: GMCausalRef, parent_ids: Array = []) -> Dictionary:
	if ref == null:
		return {"ok": false, "code": "causal.ref_missing", "reason_zh": "因果链不能加入空引用。"}
	var ref_validation := ref.validate()
	if not ref_validation.ok:
		return {"ok": false, "code": "causal.ref_invalid", "reason_zh": "因果引用不合法。", "errors": ref_validation.errors}
	if refs_by_id.has(ref.stable_id):
		var existing: GMCausalRef = refs_by_id[ref.stable_id]
		if existing.kind != ref.kind:
			return {"ok": false, "code": "causal.ref_conflict", "reason_zh": "同一稳定 ID 对应多个因果类型。", "ref_id": ref.stable_id}
		for parent_id in parent_ids:
			var link_result := add_link(str(parent_id), ref.stable_id)
			if not link_result.ok: return link_result
		return {"ok": true, "duplicate": true, "ref_id": ref.stable_id}
	for parent_id in parent_ids:
		if not refs_by_id.has(str(parent_id)):
			return {"ok": false, "code": "causal.parent_missing", "reason_zh": "因果链父引用必须先存在：%s" % str(parent_id), "parent_id": str(parent_id)}
	refs_by_id[ref.stable_id] = ref
	if root_ref_id.is_empty(): root_ref_id = ref.stable_id
	for parent_id in parent_ids:
		var link_result := add_link(str(parent_id), ref.stable_id)
		if not link_result.ok:
			refs_by_id.erase(ref.stable_id)
			if root_ref_id == ref.stable_id: root_ref_id = ""
			return link_result
	return {"ok": true, "duplicate": false, "ref_id": ref.stable_id}

func add_link(parent_id: String, child_id: String, relation: String = "causes") -> Dictionary:
	if parent_id.is_empty() or child_id.is_empty():
		return {"ok": false, "code": "causal.link_id_missing", "reason_zh": "因果链边缺少父或子引用。"}
	if not refs_by_id.has(parent_id) or not refs_by_id.has(child_id):
		return {"ok": false, "code": "causal.link_ref_missing", "reason_zh": "因果链边引用不存在的节点。", "parent_id": parent_id, "child_id": child_id}
	if parent_id == child_id or _reachable(child_id, parent_id):
		return {"ok": false, "code": "causal.cycle", "reason_zh": "因果链禁止循环 causes。", "parent_id": parent_id, "child_id": child_id}
	for link in links:
		if str(link.get("parent_id", "")) == parent_id and str(link.get("child_id", "")) == child_id:
			return {"ok": true, "duplicate": true, "parent_id": parent_id, "child_id": child_id}
	links.append({"parent_id": parent_id, "child_id": child_id, "relation": relation})
	return {"ok": true, "duplicate": false, "parent_id": parent_id, "child_id": child_id}

func append(kind: String, stable_id: String, parent_ids: Array = [], metadata: Dictionary = {}) -> Dictionary:
	return add_ref(GMCausalRef.new(kind, stable_id, kind, metadata), parent_ids)

func has_ref(stable_id: String) -> bool:
	return refs_by_id.has(stable_id)

func refs_of_kind(kind: String) -> Array:
	var result: Array = []
	for ref in refs_by_id.values():
		if ref.kind == kind: result.append(ref.to_dict())
	return result

func get_ref(stable_id: String) -> GMCausalRef:
	return refs_by_id.get(stable_id, null)

func validate_activation_root(request_id: String) -> Dictionary:
	var structural := validate()
	if not structural.ok:
		return {"ok": false, "code": "causal.chain_invalid", "reason_zh": "ActivationRequest 因果链结构无效。", "errors": structural.errors}
	if request_id.is_empty() or root_ref_id != request_id:
		return {"ok": false, "code": "causal.request_root_mismatch", "reason_zh": "因果链根不属于当前 ActivationRequest。", "expected_request_id": request_id, "actual_root_id": root_ref_id}
	var root: GMCausalRef = refs_by_id.get(root_ref_id, null)
	if root == null or root.kind != "activation_request":
		return {"ok": false, "code": "causal.request_root_kind_invalid", "reason_zh": "因果链根必须是当前 ActivationRequest。"}
	var requests := refs_of_kind("activation_request")
	if requests.size() != 1:
		return {"ok": false, "code": "causal.request_root_ambiguous", "reason_zh": "单一事务因果链只能包含一个 ActivationRequest 根。", "request_count": requests.size()}
	return {"ok": true, "request_id": request_id}

func validate_activation_prefix(request_id: String, instance_id: String) -> Dictionary:
	var root_check := validate_activation_root(request_id)
	if not root_check.ok: return root_check
	if instance_id.is_empty() or not refs_by_id.has(instance_id):
		return {"ok": false, "code": "causal.instance_missing", "reason_zh": "因果链缺少 Host 分配的 AbilityInstance。", "instance_id": instance_id}
	var instance: GMCausalRef = refs_by_id.get(instance_id, null)
	if instance == null or instance.kind != "ability_instance":
		return {"ok": false, "code": "causal.instance_identity_mismatch", "reason_zh": "因果链中的 AbilityInstance 身份与 Host 分配身份不一致。", "instance_id": instance_id}
	var instances := refs_of_kind("ability_instance")
	if instances.size() != 1:
		return {"ok": false, "code": "causal.instance_ambiguous", "reason_zh": "单一事务因果链只能包含一个 AbilityInstance。", "instance_count": instances.size()}
	if refs_by_id.size() != 2 or links.size() != 1 or not has_direct_link(request_id, instance_id):
		return {"ok": false, "code": "causal.activation_prefix_invalid", "reason_zh": "领域事务开始前因果链必须严格为 ActivationRequest→AbilityInstance。", "ref_count": refs_by_id.size(), "link_count": links.size()}
	return {"ok": true, "request_id": request_id, "instance_id": instance_id}

func has_direct_link(parent_id: String, child_id: String) -> bool:
	for link in links:
		if str(link.get("parent_id", "")) == parent_id and str(link.get("child_id", "")) == child_id and str(link.get("relation", "causes")) == "causes":
			return true
	return false

func validate() -> Dictionary:
	var errors: Array[String] = []
	if chain_id.strip_edges().is_empty(): errors.append("因果链缺少 chain_id。")
	if root_ref_id.is_empty() or not refs_by_id.has(root_ref_id): errors.append("因果链 root_ref_id 无效。")
	for ref_id in refs_by_id:
		var ref: GMCausalRef = refs_by_id[ref_id]
		var ref_result := ref.validate()
		if not ref_result.ok: errors.append_array(ref_result.errors)
	for link in links:
		var parent_id := str(link.get("parent_id", ""))
		var child_id := str(link.get("child_id", ""))
		if not refs_by_id.has(parent_id) or not refs_by_id.has(child_id): errors.append("因果链边引用缺失：%s -> %s" % [parent_id, child_id])
	if _contains_cycle(): errors.append("因果链包含循环 causes。")
	return {"ok": errors.is_empty(), "code": "causal.chain_valid" if errors.is_empty() else "causal.chain_invalid", "errors": errors, "chain_id": chain_id}

func to_dict() -> Dictionary:
	var refs: Array = []
	var ids: Array = refs_by_id.keys()
	ids.sort()
	for ref_id in ids:
		refs.append(refs_by_id[ref_id].to_dict())
	return {
		"chain_id": chain_id,
		"root_ref_id": root_ref_id,
		"refs": refs,
		"links": links.duplicate(true),
		"depth": depth(),
		"validation": validate()
	}

func depth() -> int:
	var max_depth := 0
	for ref_id in refs_by_id:
		max_depth = maxi(max_depth, _depth_from(str(ref_id), {}))
	return max_depth

func clone() -> GMCausalChain:
	var result := GMCausalChain.new(chain_id)
	result.root_ref_id = root_ref_id
	for ref_id in refs_by_id:
		var ref: GMCausalRef = refs_by_id[ref_id]
		result.refs_by_id[ref_id] = GMCausalRef.from_dict(ref.to_dict())
	result.links = links.duplicate(true)
	return result

func _reachable(start_id: String, target_id: String) -> bool:
	var visited: Dictionary = {}
	var pending: Array[String] = [start_id]
	while not pending.is_empty():
		var current: String = str(pending.pop_back())
		if current == target_id: return true
		if visited.has(current): continue
		visited[current] = true
		for link in links:
			if str(link.get("parent_id", "")) == current: pending.append(str(link.get("child_id", "")))
	return false

func _contains_cycle() -> bool:
	for link in links:
		var parent_id := str(link.get("parent_id", ""))
		var child_id := str(link.get("child_id", ""))
		if parent_id == child_id or _reachable(child_id, parent_id): return true
	return false

func _depth_from(ref_id: String, memo: Dictionary) -> int:
	if memo.has(ref_id): return int(memo[ref_id])
	# Mark the node before visiting parents so deliberately malformed cyclic
	# input can still be serialized into a bounded failure report.
	memo[ref_id] = 0
	var best := 1
	for link in links:
		if str(link.get("child_id", "")) == ref_id:
			best = maxi(best, _depth_from(str(link.get("parent_id", "")), memo) + 1)
	memo[ref_id] = best
	return best

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in range(raw.length()):
		var code := raw.unicode_at(index)
		result += raw.substr(index, 1) if ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45) else "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_") if not result.is_empty() else "request"
