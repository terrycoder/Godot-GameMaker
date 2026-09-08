class_name GMSceneBridge
extends RefCounted

## 前台只读投影：后台输出纯数据，桥接层不反向持有运行时对象。

var projections: Dictionary = {}
var last_snapshot_id: String = ""

func project_snapshot(snapshot: GMWorldSnapshot) -> Dictionary:
	if snapshot == null: return {"ok": false, "code": "scene_bridge.snapshot_missing", "reason_zh": "不能投影空快照。"}
	projections.clear()
	for entity_id in snapshot.entity_ids():
		var record := snapshot.get_entity(entity_id)
		projections[entity_id] = {
			"entity_id": entity_id,
			"kind": record.get("kind", "generic"),
			"resolution": record.get("resolution", GMResolutionState.ACTIVE),
			"version": record.get("version", 0),
			"data": GMStableData.clone(record.get("data", {}))
		}
	last_snapshot_id = snapshot.snapshot_id
	return {"ok": true, "snapshot_id": last_snapshot_id, "projections": get_projections(), "count": projections.size()}

func get_projection(entity_id: String) -> Dictionary:
	var value: Variant = projections.get(entity_id, null)
	return GMStableData.clone(value) if value is Dictionary else {}

func get_projections() -> Dictionary:
	return GMStableData.clone(projections)

func validate_read_only_projection(value: Variant) -> Dictionary:
	var stable := GMStableData.validate(value)
	if not stable.ok: return {"ok": false, "code": "scene_bridge.projection_invalid", "reason_zh": "SceneBridge 投影包含运行时对象。", "errors": stable.errors}
	return {"ok": true}
