class_name GMHighlightAdapter3D
extends RefCounted

## Highlight is presentation-only.  The adapter may notify a visual object,
## but it never writes facts, interaction state, camera state or snapshots.

const TARGET_REF := preload("res://gm_runtime/spatial_core/gm_spatial_target_ref.gd")

var _candidate: Dictionary = {}
var _active: bool = false

func set_candidate(target_value: Variant, metadata: Dictionary = {}) -> Dictionary:
	var parsed := TARGET_REF.from_native(target_value)
	if not parsed.ok: return {"ok": false, "code": "highlight.target_invalid", "reason_zh": "高亮候选不是稳定空间目标。", "details": parsed}
	_candidate = {"target_ref": parsed.target.to_native(), "metadata": metadata.duplicate(true)}
	_active = true
	return preview()

func clear() -> Dictionary:
	_candidate = {}
	_active = false
	return preview()

func preview() -> Dictionary:
	return {"ok": true, "active": _active, "candidate": _candidate.duplicate(true), "presentation_only": true}

func apply_to_visual(visual: Object, enabled: bool = true) -> Dictionary:
	if visual != null and is_instance_valid(visual) and visual.has_method("set_highlight"):
		visual.call("set_highlight", enabled)
	return {"ok": true, "active": enabled, "presentation_only": true}
