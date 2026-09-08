@tool
class_name GMPlanar3DSafeRepair
extends RefCounted

## Only derived pose rate and bounded visual material parameters are safe to infer.
## IDs, bones, sockets, transforms, collision and game rules are never inferred.
static func preview(resources: Array) -> Dictionary:
	var changes: Array = []
	for resource in resources:
		if resource is GMSemanticMaterial:
			for field in ["roughness", "metallic"]:
				var value := float(resource.get(field))
				if not is_finite(value): return _failure("材质数值不是有限数，无法推断；整批未修改。")
				if value != clampf(value, 0.0, 1.0): changes.append({"resource": resource, "field": field, "before": value, "after": clampf(value, 0.0, 1.0)})
		elif resource is GMAnimationSamplingProfile:
			if resource.sampling_mode not in GMAnimationSamplingProfile.MODES: return _failure("姿态采样模式无效，不能推断采样率；整批未修改。")
			var expected := 0 if resource.sampling_mode == "Smooth" else int(resource.sampling_mode)
			if resource.samples_per_cycle != expected: changes.append({"resource": resource, "field": "samples_per_cycle", "before": resource.samples_per_cycle, "after": expected})
		else: return _failure("选择包含不支持安全修复的资源；请仅选择语义材质或姿态采样配置。")
	return {"ok": true, "changes": changes}

static func apply(resources: Array, undo: EditorUndoRedoManager, context: Object) -> Dictionary:
	var plan := preview(resources)
	if not plan.ok: return plan
	if undo == null: return _failure("撤销管理器不可用，整批未修改。")
	if plan.changes.is_empty(): return {"ok": true, "change_count": 0}
	undo.create_action("批量修复3D安全表现字段", UndoRedo.MERGE_DISABLE, context)
	for change in plan.changes:
		undo.add_do_property(change.resource, change.field, change.after)
		undo.add_undo_property(change.resource, change.field, change.before)
	undo.commit_action()
	return {"ok": true, "change_count": plan.changes.size()}

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "code": "planar3d.safe_repair_rejected", "error_zh": message}
