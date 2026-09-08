@tool
class_name GMSemanticPortal
extends Resource

enum Direction { ONE_WAY, BIDIRECTIONAL }

@export var portal_id: StringName
@export var source_map_id: StringName
@export var source_anchor_id: StringName
@export var target_map_id: StringName
@export var target_anchor_id: StringName
@export var return_anchor_id: StringName
@export var direction: Direction = Direction.ONE_WAY
@export var required_ability_id: StringName
@export var loading_parameters: Dictionary = {}
@export_range(0.05, 60.0, 0.05) var immediate_loop_guard_seconds: float = 0.5

func validate_definition(registry: GMMapSemanticRegistry = null) -> Dictionary:
	var errors: Array[Dictionary] = []
	for pair in [["portal_id", portal_id], ["source_map_id", source_map_id], ["source_anchor_id", source_anchor_id], ["target_map_id", target_map_id], ["target_anchor_id", target_anchor_id]]:
		if str(pair[1]).strip_edges().is_empty(): errors.append(_error("semantic.portal_field_missing", "传送缺少字段：%s" % pair[0], pair[0]))
	if loading_parameters.has("scene_path") and str(target_map_id).strip_edges().is_empty(): errors.append(_error("semantic.portal_bare_scene_identity", "传送不得以裸场景路径作为唯一身份", "loading_parameters.scene_path"))
	if registry != null:
		var target := registry.resolve_anchor(target_map_id, target_anchor_id)
		if not target.ok: errors.append(_error("semantic.portal_target_missing", "传送目标地图或锚点不存在：%s/%s" % [target_map_id, target_anchor_id], "target_anchor_id"))
		var source := registry.resolve_anchor(source_map_id, source_anchor_id)
		if not source.ok: errors.append(_error("semantic.portal_source_missing", "传送源锚点不存在：%s/%s" % [source_map_id, source_anchor_id], "source_anchor_id"))
		if direction == Direction.BIDIRECTIONAL:
			if str(return_anchor_id).strip_edges().is_empty():
				errors.append(_error("semantic.portal_return_missing", "双向传送必须配置返回锚点", "return_anchor_id"))
			else:
				# 现有 schema 没有 return_map_id；返回行程落回源地图，因此返回锚点严格属于 source_map_id。
				var return_anchor := registry.resolve_anchor(source_map_id, return_anchor_id)
				if not return_anchor.ok: errors.append(_error("semantic.portal_return_anchor_missing", "双向传送返回锚点不存在：%s/%s" % [source_map_id, return_anchor_id], "return_anchor_id"))
	return {"ok": errors.is_empty(), "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh), "portal_id": str(portal_id)}

func request_transfer(registry: GMMapSemanticRegistry, granted_abilities: PackedStringArray = PackedStringArray(), chain: PackedStringArray = PackedStringArray()) -> Dictionary:
	var checked := validate_definition(registry)
	if not checked.ok: return {"ok": false, "code": "semantic.portal_invalid", "errors": checked.errors, "portal_id": str(portal_id)}
	if not str(required_ability_id).is_empty() and not granted_abilities.has(str(required_ability_id)):
		return {"ok": false, "code": "semantic.portal_ability_missing", "error_zh": "传送条件能力未满足：%s" % required_ability_id, "portal_id": str(portal_id)}
	if chain.has(str(portal_id)):
		return {"ok": false, "code": "semantic.portal_immediate_loop", "error_zh": "检测到立即传送循环：%s" % portal_id, "portal_chain": chain}
	var target := registry.resolve_anchor(target_map_id, target_anchor_id)
	var next_chain := chain.duplicate()
	next_chain.append(str(portal_id))
	return {"ok": true, "portal_id": str(portal_id), "target_map_id": str(target_map_id), "target_anchor_id": str(target_anchor_id), "target_position": target.anchor.position, "loading_parameters": loading_parameters.duplicate(true), "portal_chain": next_chain, "persist_identity": {"map_id": str(target_map_id), "anchor_id": str(target_anchor_id)}}

func _error(code: String, message: String, field: String) -> Dictionary:
	return {"code": code, "error_zh": message, "field": field, "object_id": str(portal_id), "map_id": str(source_map_id)}
