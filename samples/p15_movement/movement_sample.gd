extends Control

var registry := GMMapSemanticRegistry.new()
var executor: GMMovementAbilityExecutor
var actors: Dictionary = {}
var hosts: Dictionary = {}
var status_label: Label
var detail_label: RichTextLabel
var phase_by_actor: Dictionary = {}
var request_sequence: int = 0

func _ready() -> void:
	_build_maps()
	executor = GMMovementAbilityExecutor.new(registry)
	_build_ui()
	_make_actor("actor.player", "玩家", "player", Vector2(170, 430), Color("58a6ff"))
	_make_actor("actor.ai", "AI", "ai", Vector2(430, 430), Color("d29922"))
	_make_actor("actor.script", "脚本", "script", Vector2(690, 430), Color("8bdb81"))
	for actor_id in actors: executor.register_actor(actor_id, actors[actor_id], "map.neutral.alpha")
	status_label.text = "中性样板已就绪：三种来源共享gm.ability.movement。"
	_refresh_details()
	call_deferred("_capture_if_requested")

func _process(delta: float) -> void:
	for host in hosts.values(): host.tick(delta, "seconds")
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(110, 370, 760, 190), Color("18232d"), true)
	draw_line(Vector2(130, 500), Vector2(830, 500), Color("506579"), 2.0)
	draw_circle(Vector2(800, 430), 10, Color("b4e1ff")); draw_string(ThemeDB.fallback_font, Vector2(746, 405), "语义目标锚点", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

func _build_maps() -> void:
	var alpha := GMMapSemanticResource.new(); alpha.map_id = &"map.neutral.alpha"
	alpha.anchors = [_anchor("anchor.entry", Vector2(140, 430)), _anchor("anchor.destination", Vector2(800, 430)), _anchor("anchor.return", Vector2(140, 500))]
	var route := GMSemanticRoute.new(); route.route_id = &"route.neutral.loop"; route.map_id = alpha.map_id; route.closed = true
	route.points = [{"position": Vector2(300, 410), "wait": 0.2}, {"position": Vector2(560, 410), "wait": 0.2}, {"position": Vector2(560, 520), "wait": 0.2}, {"position": Vector2(300, 520), "wait": 0.2}]
	alpha.routes = [route]
	var beta := GMMapSemanticResource.new(); beta.map_id = &"map.neutral.beta"; beta.anchors = [_anchor("anchor.exit", Vector2(180, 180))]
	registry.register_map(alpha); registry.register_map(beta)

func _anchor(id: String, value: Vector2) -> GMSemanticAnchor:
	var anchor := GMSemanticAnchor.new(); anchor.anchor_id = StringName(id); anchor.position = value; return anchor

func _build_ui() -> void:
	var background := ColorRect.new(); background.color = Color("0d141b"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background); move_child(background, 0)
	var title := Label.new(); title.text = "P15 统一移动能力 · 中性运行样板"; title.position = Vector2(32, 20); title.add_theme_font_size_override("font_size", 26); add_child(title)
	var subtitle := Label.new(); subtitle.text = "玩家 / AI / 脚本 → ActivationRequest → AbilityTask → 单owner移动执行器"; subtitle.position = Vector2(34, 58); subtitle.modulate = Color("a9c7d8"); add_child(subtitle)
	var buttons := HBoxContainer.new(); buttons.position = Vector2(32, 100); buttons.size = Vector2(1035, 42); add_child(buttons)
	_add_button(buttons, "三来源直达", _run_equivalent_anchor)
	_add_button(buttons, "AI跟随玩家", _run_follow)
	_add_button(buttons, "脚本巡逻", _run_patrol)
	_add_button(buttons, "取消全部", _cancel_all)
	_add_button(buttons, "旅行交接", _run_travel)
	var boundary := Label.new(); boundary.text = "延期边界：不创建Task/Reservation（P16）、Planner/Schedule（P17）或SceneSession（P23）"; boundary.position = Vector2(34, 154); boundary.modulate = Color("e3b341"); add_child(boundary)
	status_label = Label.new(); status_label.position = Vector2(34, 195); status_label.size = Vector2(1030, 32); status_label.add_theme_font_size_override("font_size", 17); add_child(status_label)
	var detail_title := Label.new(); detail_title.text = "来源 / 当前阶段 / 阻断原因"; detail_title.position = Vector2(34, 235); detail_title.add_theme_font_size_override("font_size", 16); add_child(detail_title)
	detail_label = RichTextLabel.new(); detail_label.position = Vector2(34, 268); detail_label.size = Vector2(1030, 80); detail_label.bbcode_enabled = false; detail_label.fit_content = false; add_child(detail_label)

func _add_button(parent: HBoxContainer, text_value: String, callback: Callable) -> void:
	var button := Button.new(); button.text = text_value; button.custom_minimum_size = Vector2(170, 40); button.pressed.connect(callback); parent.add_child(button)

func _make_actor(actor_id: String, display_name: String, source: String, start: Vector2, color: Color) -> void:
	var actor := GMCharacterRuntime2D.new(); actor.stable_instance_id = actor_id; actor.map_id = "map.neutral.alpha"; actor.position = start; actor.name = display_name; add_child(actor)
	var body := ColorRect.new(); body.color = color; body.position = Vector2(-14, -14); body.size = Vector2(28, 28); actor.add_child(body)
	var label := Label.new(); label.text = "%s（%s）" % [display_name, source]; label.position = Vector2(-42, 22); label.size = Vector2(120, 25); actor.add_child(label)
	var attached := GMAbilitySystemHost.attach_to(actor, self); var host: GMAbilitySystemHost = attached.host
	host.set_domain_service(GMMovementAbilityExecutor.SERVICE_ID, executor)
	var definition := GMMovementAbilityDefinition.new(); host.register_definition(definition); host.grant_ability(definition, "gm.p15.sample")
	actors[actor_id] = actor; hosts[actor_id] = host; phase_by_actor[actor_id] = {"source": source, "phase": "等待", "blocked": ""}

func _request(actor_id: String, source: String, kind: String, extra: Dictionary = {}) -> Dictionary:
	request_sequence += 1
	var data := {"schema": GMMovementRequest.SCHEMA, "kind": kind, "source": source, "owner_id": "sample.%s" % source, "actor_id": actor_id, "map_id": "map.neutral.alpha", "speed": 150.0, "acceleration": 600.0, "stop_distance": 4.0, "follow_distance": 34.0}
	data.merge(extra, true)
	var host: GMAbilitySystemHost = hosts[actor_id]
	var activation := GMAbilityActivationRequest.new(host, "gm.ability.movement", "", null, {"movement_request": data}, "character.%s" % source, {}, "sample.%d" % request_sequence)
	var result := host.request_activation(activation)
	phase_by_actor[actor_id] = {"source": source, "phase": str(result.get("state", "已提交")), "blocked": str(result.get("failure_reason_zh", ""))}
	_refresh_details(); return result

func _run_equivalent_anchor() -> void:
	_cancel_all(false)
	for row in [["actor.player", "player"], ["actor.ai", "ai"], ["actor.script", "script"]]: _request(row[0], row[1], "anchor", {"anchor_id": "anchor.destination"})
	status_label.text = "已从玩家、AI、脚本提交等价语义锚点请求。"

func _run_follow() -> void:
	_request("actor.ai", "ai", "follow", {"target_actor_id": "actor.player"}); status_label.text = "AI已通过统一Ability入口跟随玩家；目标丢失或跨图将结构化阻断。"

func _run_patrol() -> void:
	_request("actor.script", "script", "patrol", {"route_id": "route.neutral.loop", "loop": true}); status_label.text = "脚本已通过统一Ability入口启动巡逻。"

func _cancel_all(update_status: bool = true) -> void:
	for row in [["actor.player", "player"], ["actor.ai", "ai"], ["actor.script", "script"]]: _request(row[0], row[1], "cancel")
	if update_status: status_label.text = "已按owner取消移动；无残留导航写入。"

func _run_travel() -> void:
	var result := _request("actor.player", "player", "travel", {"target_map_id": "map.neutral.beta", "entry_anchor_id": "anchor.entry", "exit_anchor_id": "anchor.exit", "return_anchor_id": "anchor.return"})
	status_label.text = "旅行交接已生成；SceneSession仍为P23延期。" if result.ok else str(result.get("failure_reason_zh", "旅行交接失败。"))

func _refresh_details() -> void:
	var lines := []
	for actor_id in ["actor.player", "actor.ai", "actor.script"]:
		var row: Dictionary = phase_by_actor[actor_id]
		lines.append("%s · %s · %s" % [_source_display(str(row.source)), _phase_display(str(row.phase)), row.blocked if not row.blocked.is_empty() else "无"])
	detail_label.text = "\n".join(lines)

func _source_display(value: String) -> String:
	return {"player": "玩家（player）", "ai": "AI（ai）", "script": "脚本（script）"}.get(value, "未知来源（%s）" % value)

func _phase_display(value: String) -> String:
	return {"ACTIVE": "激活（ACTIVE）", "FAILED": "失败（FAILED）", "ENDED": "结束（ENDED）", "CANCELLED": "已取消（CANCELLED）", "等待": "等待"}.get(value, "已提交（%s）" % value)

func _exit_tree() -> void:
	for host in hosts.values(): host.dispose()

func _capture_if_requested() -> void:
	var output := OS.get_environment("GM_P15_RUNTIME_CAPTURE_OUTPUT")
	if output.is_empty(): return
	_run_equivalent_anchor()
	await get_tree().create_timer(0.35).timeout
	var image := get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(output); DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()); var error := image.save_png(absolute)
	var facts := {"event": "P15_RUNTIME_CAPTURE_SENTINEL", "ok": error == OK, "path": absolute, "bytes": FileAccess.get_file_as_bytes(absolute).size() if error == OK else 0, "godot": Engine.get_version_info().string, "sources": ["player", "ai", "script"], "ability_id": "gm.ability.movement", "actors": actors.keys(), "maps": registry.map_ids(), "phase_by_actor": phase_by_actor.duplicate(true), "deferred": ["P16", "P17", "P23"], "scene_session_created": false}
	var json_path := OS.get_environment("GM_P15_RUNTIME_CAPTURE_JSON")
	if not json_path.is_empty():
		var file := FileAccess.open(ProjectSettings.globalize_path(json_path), FileAccess.WRITE); if file: file.store_string(JSON.stringify(facts, "  ") + "\n")
	print(JSON.stringify(facts)); get_tree().quit(0 if facts.ok else 161)
