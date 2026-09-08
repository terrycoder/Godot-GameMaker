@tool
class_name GMCharacterPresenter2D
extends Node2D

signal frame_event_emitted(event: GMCharacterFrameEvent, context: Dictionary)

var visual_set: GMCharacterVisualSet2D
var semantic: StringName = &"idle"
var direction: StringName = &"down"
var current_frame := 0
var playback_id := 0
var emitted_event_sequence := 0
var _sprite: AnimatedSprite2D
var _animation_player: AnimationPlayer

func configure(p_visual_set: GMCharacterVisualSet2D) -> Dictionary:
	if p_visual_set == null: return _fail("character.visual_set_null", "Presenter 未收到外观包；现有配置保持不变。")
	var initial_action := p_visual_set.action_for(&"idle")
	if initial_action == null: return _fail("character.initial_action_missing", "候选外观缺少初始 idle 动作；现有配置保持不变。")
	var initial_resolution := initial_action.resolve_direction(&"down")
	if not initial_resolution.ok: return _fail("character.initial_direction_failed", "候选外观初始方向无法解析；现有配置保持不变。", initial_resolution)
	var staged := _stage_backend(p_visual_set, initial_action, initial_resolution)
	if not staged.ok: return staged
	# The candidate is now fully accepted.  This is the only commit point: the old
	# backend and all observable playback facts remain untouched before this line.
	_release_backend()
	var backend := staged.backend as Node
	add_child(backend)
	_sprite = staged.get("sprite", null) as AnimatedSprite2D
	_animation_player = staged.get("animation_player", null) as AnimationPlayer
	visual_set = p_visual_set
	semantic = &"idle"; direction = &"down"; current_frame = 0
	playback_id += 1; emitted_event_sequence = 0
	return {"ok":true,"semantic":semantic,"direction":direction,"animation":initial_resolution.animation,"mirror_x":initial_resolution.mirror_x,"playback_id":playback_id,"staged_then_committed":true}

func clear_configuration() -> Dictionary:
	_release_backend()
	visual_set = null; semantic = &"idle"; direction = &"down"; current_frame = 0; playback_id = 0; emitted_event_sequence = 0
	return {"ok":true,"code":"character.presenter_cleared","idempotent":true}

func _stage_backend(candidate: GMCharacterVisualSet2D, action: GMCharacterActionSlot2D, resolved: Dictionary) -> Dictionary:
	if candidate.custom_presenter_scene != null:
		var custom := candidate.custom_presenter_scene.instantiate()
		if custom == null or not custom.has_method("play_semantic_action"):
			if custom != null: custom.free()
			return _fail("character.custom_presenter_invalid", "自定义 Presenter 必须公开 play_semantic_action；候选已释放。")
		var custom_result = custom.call("play_semantic_action", &"idle", &"down", resolved)
		if custom_result is Dictionary and not custom_result.get("ok", true):
			custom.free()
			return _fail("character.initial_action_rejected", "自定义 Presenter 拒绝初始动作；候选已释放。", {"provider_result":custom_result})
		return {"ok":true,"backend":custom,"backend_kind":"custom"}
	if candidate.sprite_frames != null:
		if not candidate.sprite_frames.has_animation(resolved.animation): return _fail("character.initial_animation_missing", "SpriteFrames 缺少初始动画；现有配置保持不变。", resolved)
		var sprite := AnimatedSprite2D.new(); sprite.sprite_frames = candidate.sprite_frames; sprite.centered = true
		sprite.animation = resolved.animation; sprite.sprite_frames.set_animation_speed(resolved.animation, action.frame_rate); sprite.sprite_frames.set_animation_loop(resolved.animation, action.loop); sprite.flip_h = bool(resolved.mirror_x); sprite.play()
		return {"ok":true,"backend":sprite,"backend_kind":"sprite_frames","sprite":sprite}
	if candidate.animation_player_scene != null:
		var root := candidate.animation_player_scene.instantiate()
		if root == null: return _fail("character.animation_player_scene_instantiate_failed", "AnimationPlayer 场景实例化失败；现有配置保持不变。")
		var player := _find_animation_player(root)
		if player == null:
			root.free(); return _fail("character.animation_player_missing", "AnimationPlayer 场景中没有 AnimationPlayer；候选已释放。")
		if not player.has_animation(resolved.animation):
			root.free(); return _fail("character.initial_animation_missing", "AnimationPlayer 缺少初始动画；候选已释放。", resolved)
		player.play(resolved.animation)
		return {"ok":true,"backend":root,"backend_kind":"animation_player","animation_player":player}
	return _fail("character.presenter_source_missing", "外观包没有可用表现源；现有配置保持不变。")

func play_semantic_action(p_semantic: StringName, p_direction: StringName) -> Dictionary:
	if visual_set == null: return _fail("character.presenter_not_configured", "Presenter 尚未配置外观包。")
	var action: GMCharacterActionSlot2D = visual_set.action_for(p_semantic)
	if action == null:
		return _fail("character.action_missing", "请求的语义动作不存在；失败关闭。", {"semantic": p_semantic})
	var resolved: Dictionary = action.resolve_direction(p_direction)
	if not resolved.ok: return resolved
	if _sprite != null:
		if not _sprite.sprite_frames.has_animation(resolved.animation): return _fail("character.animation_missing", "SpriteFrames 动画不存在。", resolved)
		_sprite.animation = resolved.animation
		_sprite.sprite_frames.set_animation_speed(resolved.animation, action.frame_rate)
		_sprite.sprite_frames.set_animation_loop(resolved.animation, action.loop)
		_sprite.flip_h = bool(resolved.mirror_x)
		_sprite.play()
	elif _animation_player != null:
		if not _animation_player.has_animation(resolved.animation): return _fail("character.animation_missing", "AnimationPlayer 动画不存在。", resolved)
		_animation_player.play(resolved.animation)
	else:
		var custom := get_child(0) if get_child_count() > 0 else null
		if custom == null: return _fail("character.custom_presenter_released", "自定义 Presenter 已释放。")
		var custom_result = custom.call("play_semantic_action", p_semantic, p_direction, resolved)
		if custom_result is Dictionary and not custom_result.get("ok", true): return custom_result
	# Commit presenter state only after the backend accepted the request.  Missing
	# actions/animations therefore cannot partially switch the live presenter.
	semantic = p_semantic
	direction = p_direction
	current_frame = 0
	playback_id += 1
	emitted_event_sequence = 0
	return {"ok": true, "semantic": semantic, "direction": direction, "animation": resolved.animation, "mirror_x": resolved.mirror_x, "playback_id": playback_id}

func seek_frame(frame: int, emit_events: bool = true) -> Dictionary:
	var action: GMCharacterActionSlot2D = visual_set.action_for(semantic) if visual_set != null else null
	if action == null: return _fail("character.action_missing", "当前语义动作不存在。")
	var resolved: Dictionary = action.resolve_direction(direction)
	if not resolved.ok: return resolved
	var count := visual_set._frame_count(resolved.animation)
	if frame < 0 or frame >= count: return _fail("character.frame_out_of_range", "预览帧超出动作范围。", {"frame": frame, "frame_count": count})
	current_frame = frame
	if _sprite != null: _sprite.frame = frame; _sprite.pause()
	if emit_events:
		for event in action.events:
			if event != null and event.frame_index == frame:
				emitted_event_sequence += 1
				frame_event_emitted.emit(event, {"semantic": semantic, "direction": direction, "frame": frame, "playback_id":playback_id, "event_sequence":emitted_event_sequence})
	return {"ok": true, "frame": frame, "events": action.events.size(), "playback_id":playback_id, "emitted_event_sequence":emitted_event_sequence}

func anchor_position(anchor_name: StringName) -> Dictionary:
	if visual_set == null: return _fail("character.presenter_not_configured", "Presenter 尚未配置外观包。")
	for anchor in visual_set.anchors:
		if anchor != null and anchor.anchor_name == anchor_name: return anchor.sample(semantic, direction, current_frame)
	return _fail("character.anchor_not_found", "外观包没有指定锚点。", {"anchor": anchor_name})

func snapshot() -> Dictionary:
	return {"semantic": semantic, "direction": direction, "frame": current_frame, "visual_set_id": visual_set.visual_set_id if visual_set != null else "", "playback_id":playback_id, "emitted_event_sequence":emitted_event_sequence}

func _release_backend() -> void:
	for child in get_children(): child.free()
	_sprite = null
	_animation_player = null

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer: return root
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null: return found
	return null

func _fail(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": message, "details": details}
