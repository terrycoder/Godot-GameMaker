@tool
class_name GMCharacterAnchorTrack2D
extends Resource

const ANCHOR_KINDS := ["weapon", "effect", "hit", "sound", "dialogue", "overhead_ui"]

@export var anchor_name: StringName = &"weapon"
@export_enum("weapon", "effect", "hit", "sound", "dialogue", "overhead_ui") var anchor_kind: String = "weapon"
## key: semantic/direction, value: Array[Vector2] indexed by animation frame.
@export var positions: Dictionary = {}

func sample(semantic: StringName, direction: StringName, frame: int) -> Dictionary:
	var keys := ["%s/%s" % [semantic, direction], "%s/*" % semantic, "*/%s" % direction, "*/*"]
	for key in keys:
		if positions.has(key):
			var track = positions[key]
			if not track is Array or frame < 0 or frame >= track.size():
				return _fail("character.anchor_frame_invalid", "锚点轨迹已因动作帧数变化而失效。", {"anchor": anchor_name, "key": key, "frame": frame, "track_size": track.size() if track is Array else -1})
			var point = track[frame]
			if not point is Vector2: return _fail("character.anchor_value_invalid", "锚点轨迹包含非 Vector2 值。", {"anchor": anchor_name, "key": key})
			return {"ok": true, "position": point, "source_key": key}
	return _fail("character.anchor_mapping_missing", "锚点缺少当前动作/方向轨迹。", {"anchor": anchor_name, "semantic": semantic, "direction": direction})

func validate(frame_counts: Dictionary, bounds: Rect2) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if anchor_name.is_empty(): issues.append(_fail("character.anchor_name_missing", "锚点缺少名称。"))
	if anchor_kind not in ANCHOR_KINDS: issues.append(_fail("character.anchor_kind_invalid", "锚点类型不受支持。"))
	for key in positions:
		var track = positions[key]
		if not track is Array: issues.append(_fail("character.anchor_track_invalid", "锚点轨迹必须是 Vector2 数组。", {"key": key})); continue
		var expected := int(frame_counts.get(key, -1))
		if expected < 0 and not str(key).contains("*"):
			issues.append(_fail("character.anchor_reference_missing", "锚点轨迹引用的动作或方向不存在。", {"anchor":anchor_name,"key":key}))
		if expected >= 0 and track.size() != expected:
			issues.append(_fail("character.anchor_track_length_changed", "锚点轨迹长度与动作帧数不一致。", {"key": key, "expected": expected, "actual": track.size()}))
		for index in track.size():
			if not track[index] is Vector2: continue
			if not bounds.has_point(track[index]): issues.append(_fail("character.anchor_out_of_bounds", "锚点超出视觉边界。", {"key": key, "frame": index, "position": track[index]}))
	return issues

func _fail(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": message, "details": details}
