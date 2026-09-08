class_name GMTravelHandoff
extends RefCounted

const SCHEMA := "gm.movement.travel_handoff.v1"

static func build(request: GMMovementRequest, registry: GMMapSemanticRegistry) -> Dictionary:
	if request == null: return _fail("movement.travel_request_missing", "旅行交接缺少移动请求。", "请重新提交旅行请求。")
	if registry == null: return _fail("movement.semantic_registry_missing", "旅行交接缺少SemanticMap注册表。", "请先加载语义地图。")
	var source_entry := registry.resolve_anchor(request.map_id, request.entry_anchor_id)
	if not source_entry.ok: return _wrap(source_entry, "旅行入口锚点无法解析，请检查当前地图与入口ID。")
	if not _anchor_numeric_valid(source_entry.anchor): return _fail("movement.travel_anchor_numeric_invalid", "旅行入口锚点包含非有限位置。", "请修正SemanticMap入口锚点。")
	var source_return := registry.resolve_anchor(request.map_id, request.return_anchor_id)
	if not source_return.ok: return _wrap(source_return, "旅行返回锚点无法解析，请在当前地图补全返回点。")
	if not _anchor_numeric_valid(source_return.anchor): return _fail("movement.travel_anchor_numeric_invalid", "旅行返回锚点包含非有限位置。", "请修正SemanticMap返回锚点。")
	var target_exit := registry.resolve_anchor(request.target_map_id, request.exit_anchor_id)
	if not target_exit.ok: return _wrap(target_exit, "旅行出口锚点无法解析，请检查目标地图与出口ID。")
	if not _anchor_numeric_valid(target_exit.anchor): return _fail("movement.travel_anchor_numeric_invalid", "旅行出口锚点包含非有限位置。", "请修正SemanticMap出口锚点。")
	return {"ok": true, "completed": true, "handoff": {"schema": SCHEMA, "actor_id": request.actor_id, "source_map_id": request.map_id, "target_map_id": request.target_map_id, "entry_anchor_id": request.entry_anchor_id, "exit_anchor_id": request.exit_anchor_id, "return_anchor_id": request.return_anchor_id, "request_source": request.source, "owner_id": request.owner_id}, "scene_session_created": false, "deferred_to": "P23"}

static func _wrap(failure: Dictionary, fix_zh: String) -> Dictionary:
	var result := failure.duplicate(true)
	result["reason_zh"] = str(result.get("error_zh", result.get("reason_zh", "旅行锚点解析失败。")))
	result["fix_zh"] = fix_zh
	return result

static func _anchor_numeric_valid(anchor: Variant) -> bool:
	return anchor is GMSemanticAnchor and is_finite(anchor.position.x) and is_finite(anchor.position.y)

static func _fail(code: String, reason_zh: String, fix_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": reason_zh, "reason_zh": reason_zh, "fix_zh": fix_zh}
