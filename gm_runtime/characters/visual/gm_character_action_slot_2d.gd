@tool
class_name GMCharacterActionSlot2D
extends Resource

const SEMANTICS := ["idle", "move", "attack", "hurt", "death"]
const DIRECTION_MODES := ["one", "four", "eight", "four_mirrored"]

@export_enum("idle", "move", "attack", "hurt", "death") var semantic: String = "idle"
@export_enum("one", "four", "eight", "four_mirrored") var direction_mode: String = "four"
@export var animation_by_direction: Dictionary = {
	"down": &"idle_down", "left": &"idle_left", "right": &"idle_right", "up": &"idle_up"
}
@export_range(0.1, 120.0, 0.1) var frame_rate: float = 8.0
@export var loop: bool = true
@export var events: Array[GMCharacterFrameEvent] = []
@export var fallback_semantic: StringName = &""
@export var allow_mirror: bool = false

func resolve_direction(direction: StringName) -> Dictionary:
	var normalized: StringName = _normalize_direction(direction)
	if animation_by_direction.has(normalized):
		return {"ok": true, "animation": StringName(animation_by_direction[normalized]), "direction": normalized, "mirror_x": false}
	if allow_mirror:
		var opposite: StringName = {&"left": &"right", &"right": &"left", &"up_left": &"up_right", &"up_right": &"up_left", &"down_left": &"down_right", &"down_right": &"down_left"}.get(normalized, &"")
		if not opposite.is_empty() and animation_by_direction.has(opposite):
			return {"ok": true, "animation": StringName(animation_by_direction[opposite]), "direction": opposite, "mirror_x": true}
	if animation_by_direction.has(&"any"):
		return {"ok": true, "animation": StringName(animation_by_direction[&"any"]), "direction": &"any", "mirror_x": false}
	return _fail("character.direction_mapping_missing", "动作缺少方向映射。", {"semantic": semantic, "direction": normalized})

func validate(frame_count_lookup: Callable, animation_domain_introspectable: bool = true) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if semantic not in SEMANTICS: issues.append(_fail("character.semantic_invalid", "动作语义槽不受支持。"))
	if direction_mode not in DIRECTION_MODES: issues.append(_fail("character.direction_mode_invalid", "方向模式不受支持。"))
	if frame_rate <= 0.0: issues.append(_fail("character.frame_rate_invalid", "动作帧率必须大于零。"))
	if animation_by_direction.is_empty(): issues.append(_fail("character.action_mapping_empty", "动作没有任何动画映射。"))
	for required_direction in required_directions():
		var resolved := resolve_declared_direction(required_direction)
		if not resolved.ok:
			issues.append(_fail("character.direction_mode_incomplete", "动作方向模式缺少必需方向映射。", {"semantic":semantic,"direction_mode":direction_mode,"direction":required_direction,"allow_mirror":allow_mirror,"resolution":resolved}))
	for direction in animation_by_direction:
		var animation := StringName(animation_by_direction[direction])
		if animation.is_empty():
			issues.append(_fail("character.animation_mapping_empty", "动作方向映射的动画名为空。", {"semantic":semantic,"direction":direction,"animation":animation}))
			continue
		if not animation_domain_introspectable: continue
		var frame_count := int(frame_count_lookup.call(animation))
		if frame_count <= 0:
			issues.append(_fail("character.animation_missing", "动作映射的动画不存在或没有帧。", {"semantic": semantic, "direction": direction, "animation": animation}))
			continue
		for event in events:
			if event == null: issues.append(_fail("character.event_null", "动作包含空事件。")); continue
			var result: Dictionary = event.validate(frame_count)
			if not result.ok: issues.append(result.merged({"semantic": semantic, "direction": direction}, true))
	return issues

func required_directions() -> Array[StringName]:
	match direction_mode:
		"one": return [&"any"]
		"four", "four_mirrored": return [&"down", &"left", &"right", &"up"]
		"eight": return [&"down", &"left", &"right", &"up", &"down_left", &"down_right", &"up_left", &"up_right"]
		_: return []

# Capability validation is deliberately stricter than runtime resolution.
# Runtime may retain the legacy `any` fallback, but a multi-direction resource
# must declare its supported domain explicitly (or through the one documented
# four_mirrored closure).
func resolve_declared_direction(direction: StringName) -> Dictionary:
	var normalized: StringName = _normalize_direction(direction)
	if animation_by_direction.has(normalized):
		return {"ok":true,"animation":StringName(animation_by_direction[normalized]),"direction":normalized,"mirror_x":false,"declaration":"explicit"}
	if direction_mode == &"four_mirrored" and allow_mirror:
		var opposite: StringName = {&"left":&"right",&"right":&"left"}.get(normalized, &"")
		if not opposite.is_empty() and animation_by_direction.has(opposite):
			return {"ok":true,"animation":StringName(animation_by_direction[opposite]),"direction":opposite,"mirror_x":true,"declaration":"mirrored_opposite"}
	return _fail("character.direction_declaration_missing", "动作能力声明缺少必需方向；运行时 any 回退不能满足多向完整性。", {"semantic":semantic,"direction_mode":direction_mode,"direction":normalized,"allow_mirror":allow_mirror,"runtime_any_available":animation_by_direction.has(&"any")})

func _normalize_direction(direction: StringName) -> StringName:
	if direction_mode == &"one": return &"any"
	if direction_mode == &"four" or direction_mode == &"four_mirrored":
		return {&"up_left": &"up", &"up_right": &"up", &"down_left": &"down", &"down_right": &"down"}.get(direction, direction)
	return direction

func _fail(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": message, "details": details}
