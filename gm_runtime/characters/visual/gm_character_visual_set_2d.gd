@tool
class_name GMCharacterVisualSet2D
extends Resource

const REQUIRED_SEMANTICS := [&"idle", &"move", &"attack", &"hurt", &"death"]

@export_group("外观身份")
@export var visual_set_id: String = ""
@export var display_name_zh: String = ""
@export var art_style: String = "pixel"
@export var category: String = "humanoid"
@export var tags: PackedStringArray = PackedStringArray()

@export_group("统一视觉资源")
@export var main_image: Texture2D
@export var avatar: Texture2D
@export var portrait: Texture2D
@export var shadow: Texture2D
@export var sprite_frames: SpriteFrames
@export var animation_player_scene: PackedScene
@export var custom_presenter_scene: PackedScene
@export var actions: Array[GMCharacterActionSlot2D] = []
@export var anchors: Array[GMCharacterAnchorTrack2D] = []
@export var visual_bounds: Rect2 = Rect2(-64, -64, 128, 128)

func action_for(semantic: StringName) -> GMCharacterActionSlot2D:
	for action in actions:
		if action != null and action.semantic == semantic: return action
	return null

func completeness() -> Dictionary:
	var present := PackedStringArray()
	var missing := PackedStringArray()
	for semantic in REQUIRED_SEMANTICS:
		var action := action_for(semantic)
		if action == null or action.animation_by_direction.is_empty(): missing.append(semantic)
		else: present.append(semantic)
	return {"complete": missing.is_empty(), "present": present, "missing": missing, "ratio": float(present.size()) / float(REQUIRED_SEMANTICS.size())}

func validate_visual_set() -> Dictionary:
	var issues: Array[Dictionary] = []
	if visual_set_id.strip_edges().is_empty(): issues.append(_fail("character.visual_set_id_missing", "外观包缺少稳定ID。"))
	if sprite_frames == null and animation_player_scene == null and custom_presenter_scene == null:
		issues.append(_fail("character.presenter_source_missing", "外观包没有 SpriteFrames、AnimationPlayer 场景或公开自定义 Presenter。"))
	var semantics := {}
	var event_keys := {}
	var animation_domain_introspectable := sprite_frames != null
	for action in actions:
		if action == null: issues.append(_fail("character.action_null", "动作列表包含空项。")); continue
		if semantics.has(action.semantic): issues.append(_fail("character.action_duplicate", "动作语义槽重名。", {"semantic": action.semantic}))
		semantics[action.semantic] = true
		issues.append_array(action.validate(_frame_count, animation_domain_introspectable))
		for event in action.events:
			if event == null: continue
			var event_key := "%s/%s/%s/%d" % [action.semantic, event.event_kind, event.event_name, event.frame_index]
			if event_keys.has(event_key): issues.append(_fail("character.event_duplicate", "帧事件重复。", {"event_key":event_key}))
			event_keys[event_key] = true
	var complete: Dictionary = completeness()
	for semantic in complete.missing:
		var code := "character.attack_missing_failure_closed" if semantic == &"attack" else "character.action_required_missing"
		issues.append(_fail(code, "缺少必需动作：%s。不会静默标记完整。" % semantic, {"semantic": semantic}))
	var anchor_names := {}
	var frame_counts := _anchor_frame_counts()
	for anchor in anchors:
		if anchor == null: issues.append(_fail("character.anchor_null", "锚点列表包含空项。")); continue
		if anchor_names.has(anchor.anchor_name): issues.append(_fail("character.anchor_duplicate", "锚点名称重复。", {"anchor": anchor.anchor_name}))
		anchor_names[anchor.anchor_name] = true
		issues.append_array(anchor.validate(frame_counts, visual_bounds))
	for action in actions:
		if action == null: continue
		for event in action.events:
			if event == null: continue
			var anchor_ref := StringName(str(event.payload.get("anchor", "")))
			if not anchor_ref.is_empty() and not anchor_names.has(anchor_ref): issues.append(_fail("character.event_anchor_reference_missing", "帧事件引用的锚点不存在。", {"semantic":action.semantic,"event":event.event_name,"anchor":anchor_ref}))
	if sprite_frames != null: issues.append_array(_validate_sprite_frame_dimensions())
	var boundaries := {
		"direction_domain":"verified",
		"sprite_frame_animation_and_dimensions":"verified" if sprite_frames != null else "not_applicable",
		"animation_player_animation_domain":"runtime_staging_required" if animation_player_scene != null else "not_applicable",
		"custom_presenter_animation_domain":"runtime_staging_required" if custom_presenter_scene != null else "not_applicable",
	}
	return {"ok": issues.is_empty(), "issues": issues, "completeness": complete, "validation_boundaries":boundaries}

func _validate_sprite_frame_dimensions() -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var expected := Vector2i.ZERO
	var expected_source := {}
	var visited := {}
	for action in actions:
		if action == null: continue
		for direction in action.animation_by_direction:
			var animation := StringName(action.animation_by_direction[direction])
			if visited.has(animation) or not sprite_frames.has_animation(animation): continue
			visited[animation] = true
			for frame in sprite_frames.get_frame_count(animation):
				var texture := sprite_frames.get_frame_texture(animation, frame)
				if texture == null:
					issues.append(_fail("character.sprite_frame_texture_missing", "SpriteFrames 帧缺少纹理。", {"semantic":action.semantic,"direction":direction,"animation":animation,"frame":frame,"expected":expected,"actual":"null","expected_source":expected_source.duplicate(true)}))
					continue
				var actual := Vector2i(texture.get_size())
				if expected == Vector2i.ZERO:
					expected = actual; expected_source = {"semantic":action.semantic,"direction":direction,"animation":animation,"frame":frame}
				elif actual != expected:
					issues.append(_fail("character.animation_frame_size_mismatch", "SpriteFrames 映射帧尺寸不一致。", {"semantic":action.semantic,"direction":direction,"animation":animation,"frame":frame,"expected":expected,"actual":actual,"expected_source":expected_source}))
	return issues

func _frame_count(animation: StringName) -> int:
	if sprite_frames != null and sprite_frames.has_animation(animation): return sprite_frames.get_frame_count(animation)
	return 1 if animation_player_scene != null or custom_presenter_scene != null else 0

func _anchor_frame_counts() -> Dictionary:
	var result := {}
	for action in actions:
		if action == null: continue
		for direction in action.animation_by_direction:
			var animation := StringName(action.animation_by_direction[direction])
			result["%s/%s" % [action.semantic, direction]] = _frame_count(animation)
		for requested in [&"down", &"left", &"right", &"up", &"down_left", &"down_right", &"up_left", &"up_right"]:
			var resolved: Dictionary = action.resolve_direction(requested)
			if resolved.ok: result["%s/%s" % [action.semantic, requested]] = _frame_count(resolved.animation)
	return result

func _fail(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": message, "details": details}
