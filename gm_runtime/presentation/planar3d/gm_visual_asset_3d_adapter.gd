class_name GMVisualAsset3DAdapter
extends RefCounted

## 六类轻量视觉适配器共享同一声明式入口。它们只创建/描述视觉节点，
## 不拥有 NPC、Task、Ability、Combat、Process、Inventory 或 Fact 状态。

const ASSET_KINDS := ["Sprite3D", "Billboard", "Decal", "Particles", "MultiMesh", "Instance Group"]
const PRESENTATION_AUTHORITY := "P18.presentation"

func describe(asset_kind: String, asset_id: String, target_ref: String = "", content_ref: String = "") -> Dictionary:
	if asset_kind not in ASSET_KINDS: return _failure("visual_adapter.kind_invalid", "未知3D轻量视觉类型：%s" % asset_kind)
	if asset_id.strip_edges().is_empty(): return _failure("visual_adapter.id_missing", "视觉适配器ID不能为空。")
	return {"ok": true, "code": "visual_adapter.described", "asset_kind": asset_kind, "asset_id": asset_id, "target_ref": target_ref, "content_ref": content_ref, "authority": PRESENTATION_AUTHORITY, "domain_facts_written": false, "owns_logic": false, "owns_collision": false}

func adapt_sprite3d(asset_id: String, target_ref: String = "") -> Dictionary:
	return describe("Sprite3D", asset_id, target_ref)

func adapt_billboard(asset_id: String, target_ref: String = "") -> Dictionary:
	return describe("Billboard", asset_id, target_ref)

func adapt_decal(asset_id: String, target_ref: String = "") -> Dictionary:
	return describe("Decal", asset_id, target_ref)

func adapt_particles(asset_id: String, target_ref: String = "") -> Dictionary:
	return describe("Particles", asset_id, target_ref)

func adapt_multimesh(asset_id: String, target_ref: String = "") -> Dictionary:
	return describe("MultiMesh", asset_id, target_ref)

func adapt_instance_group(asset_id: String, target_ref: String = "") -> Dictionary:
	return describe("Instance Group", asset_id, target_ref)

func build_node(descriptor: Dictionary) -> Dictionary:
	var checked := validate_descriptor(descriptor)
	if not bool(checked.get("ok", false)): return checked
	var node: Node3D
	match str(descriptor.get("asset_kind", "")):
		"Sprite3D", "Billboard": node = Sprite3D.new()
		"Decal": node = Decal.new()
		"Particles": node = GPUParticles3D.new()
		"MultiMesh": node = MultiMeshInstance3D.new()
		"Instance Group": node = Node3D.new()
		_: return _failure("visual_adapter.kind_invalid", "视觉类型未实现。")
	node.name = str(descriptor.get("asset_id", "GMVisualAsset3D"))
	node.set_meta("gm_presentation_authority", PRESENTATION_AUTHORITY)
	node.set_meta("gm_asset_kind", str(descriptor.get("asset_kind", "")))
	return {"ok": true, "code": "visual_adapter.node_created", "node": node, "descriptor": descriptor.duplicate(true), "domain_facts_written": false}

func validate_descriptor(descriptor: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if str(descriptor.get("asset_kind", "")) not in ASSET_KINDS: errors.append("visual_adapter.kind_invalid：asset_kind无效。")
	if str(descriptor.get("asset_id", "")).strip_edges().is_empty(): errors.append("visual_adapter.id_missing：asset_id不能为空。")
	for forbidden in ["ability_state", "task_state", "combat_state", "inventory_state", "fact_state", "collision_authority"]:
		if descriptor.has(forbidden): errors.append("visual_adapter.authority_forbidden：视觉描述不得拥有%s。" % forbidden)
	return {"ok": errors.is_empty(), "code": "visual_adapter.valid" if errors.is_empty() else "visual_adapter.invalid", "errors_zh": errors, "error_zh": "视觉适配器描述有效。" if errors.is_empty() else str(errors[0]), "failure_closed": true}

func snapshot() -> Dictionary:
	return {"asset_kinds": ASSET_KINDS.duplicate(), "authority": PRESENTATION_AUTHORITY, "owns_logic": false, "owns_collision": false, "domain_facts_written": false}

static func _failure(code: String, error_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": error_zh, "errors_zh": [error_zh], "failure_closed": true}
