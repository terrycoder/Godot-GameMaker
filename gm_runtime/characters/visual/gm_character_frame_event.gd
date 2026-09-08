@tool
class_name GMCharacterFrameEvent
extends Resource

const EVENT_KINDS := ["weapon", "effect", "hit", "sound", "dialogue", "overhead_ui", "cue"]

@export var event_name: StringName = &"event"
@export_enum("weapon", "effect", "hit", "sound", "dialogue", "overhead_ui", "cue") var event_kind: String = "cue"
@export_range(0, 4096, 1) var frame_index: int = 0
@export var payload: Dictionary = {}

func validate(frame_count: int) -> Dictionary:
	if event_name.is_empty(): return _fail("character.event_name_missing", "帧事件缺少名称。")
	if event_kind not in EVENT_KINDS: return _fail("character.event_kind_invalid", "帧事件类型不受支持。")
	if frame_index < 0 or frame_index >= frame_count:
		return _fail("character.event_frame_invalid", "帧事件已因动作帧数变化而失效。", {"frame": frame_index, "frame_count": frame_count})
	return {"ok": true}

func _fail(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": message, "details": details}
