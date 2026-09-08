class_name GMLightAsset3D
extends RefCounted

## 可替换的轻量视觉 Asset 外壳；具体节点由 GMVisualAsset3DAdapter创建。

var descriptor: Dictionary = {}
var adapter := GMVisualAsset3DAdapter.new()

func configure(asset_kind: String, asset_id: String, target_ref: String = "", content_ref: String = "") -> Dictionary:
	var result := adapter.describe(asset_kind, asset_id, target_ref, content_ref)
	if bool(result.get("ok", false)): descriptor = result.duplicate(true)
	return result

func create_presentation_node() -> Dictionary:
	if descriptor.is_empty(): return {"ok": false, "code": "visual_asset.not_configured", "error_zh": "轻量视觉Asset尚未配置。", "failure_closed": true}
	return adapter.build_node(descriptor)

func snapshot() -> Dictionary:
	return {"descriptor": descriptor.duplicate(true), "authority": "P18.presentation", "domain_facts_written": false, "owns_logic": false, "owns_collision": false}
