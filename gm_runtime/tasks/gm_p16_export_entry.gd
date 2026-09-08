extends Control

var service := GMTaskService.new()
var host := GMAbilitySystemHost.new()

func _ready() -> void:
	_build_ui()
	var facts := _run_scenario()
	print(JSON.stringify(facts))
	var json_path := OS.get_environment("GM_P16_RUNTIME_CAPTURE_JSON")
	if not json_path.is_empty():
		var absolute_json := ProjectSettings.globalize_path(json_path); DirAccess.make_dir_recursive_absolute(absolute_json.get_base_dir()); var file := FileAccess.open(absolute_json,FileAccess.WRITE); if file: file.store_string(JSON.stringify(facts,"  ") + "\n")
	var png_path := OS.get_environment("GM_P16_RUNTIME_CAPTURE_OUTPUT")
	if not png_path.is_empty(): call_deferred("_capture",png_path,facts)
	else: get_tree().quit(0 if facts.ok else 164)

func _build_ui() -> void:
	var background := ColorRect.new(); background.color=Color("101927"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var margin := MarginContainer.new(); margin.add_theme_constant_override("margin_left",48); margin.add_theme_constant_override("margin_top",36); margin.add_theme_constant_override("margin_right",48); margin.add_theme_constant_override("margin_bottom",36); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(margin)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",14); margin.add_child(column)
	var title := Label.new(); title.text="P16 统一Task运行样板"; title.add_theme_font_size_override("font_size",32); column.add_child(title)
	var subtitle := Label.new(); subtitle.text="唯一 Task / Objective / Assignment / DutyProvider / Reservation 事实域"; subtitle.add_theme_color_override("font_color",Color("8bd5ca")); subtitle.add_theme_font_size_override("font_size",18); column.add_child(subtitle)
	_add_card(column,"发布来源","玩家　AI　组织　世界事件　脚本　职责Provider\n全部进入同一 Task schema 与 GMStore。")
	_add_card(column,"执行链与目标推进","Ability → Resolver → Transaction → Fact / Change / Cue\nObjective 只消费已提交的类型化事实；重复 Fact ID 不重复推进。")
	_add_card(column,"委派与 Reservation","受派、改派、拒绝、撤销均可审计。独占/容量 Reservation 校验 owner、Task、Assignment、逻辑时钟；竞争者安全阻塞。")
	_add_card(column,"生命周期与持久化","草拟 → 可领取 → 进行中 → 完成 / 失败 / 取消。终态互斥且结果回执幂等；JSON 跨实例恢复前严格校验。")
	var boundary := Label.new(); boundary.text="边界：不直写角色/地图/物品；不实现 Planner(P17)、库存(P19)、生产(P20)、SceneSession(P23)。"; boundary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; boundary.add_theme_color_override("font_color",Color("f5c2e7")); column.add_child(boundary)

func _add_card(column: VBoxContainer, heading: String, body: String) -> void:
	var panel:=PanelContainer.new(); var box:=VBoxContainer.new(); box.add_theme_constant_override("separation",6); panel.add_child(box); var h:=Label.new(); h.text=heading; h.add_theme_font_size_override("font_size",20); h.add_theme_color_override("font_color",Color("89b4fa")); box.add_child(h); var b:=Label.new(); b.text=body; b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(b); column.add_child(panel)

func _run_scenario() -> Dictionary:
	var definition := GMTaskDefinition.new()
	var results: Array = []
	results.append(service.submit_operation(host,"register_definition",definition.to_dict(),"player","gm.source.player.sample","p16.runtime.definition"))
	results.append(service.submit_operation(host,"publish_task",{"task_id":"gm.task.runtime.sample","definition_id":definition.definition_id,"parent_task_id":"","group_id":"","execution_context":{"mode":"local","stable_context":{"map_id":"gm.map.neutral"}}},"ai","gm.source.ai.sample","p16.runtime.publish"))
	results.append(service.submit_operation(host,"assign",{"assignment_id":"gm.assignment.runtime.sample","task_id":"gm.task.runtime.sample","assignee":{"type":"actor","id":"gm.actor.runtime"},"kind":"actor"},"script","gm.script.runtime","p16.runtime.assign"))
	results.append(service.submit_operation(host,"transition",{"task_id":"gm.task.runtime.sample","to_state":"in_progress","reason_code":"task.started","result":{}},"script","gm.script.runtime","p16.runtime.start"))
	var execution := service.build_execution_request(host,"gm.task.runtime.sample","gm.assignment.runtime.sample","gm.ability.movement",{"movement_kind":"anchor"},"p16.runtime.execute")
	var ok := true
	for result in results: ok = ok and result is GMCommittedFactResult
	return {"event":"P16_RUNTIME_SAMPLE_SENTINEL","ok":ok and execution.ok,"task_state":service.read_task("gm.task.runtime.sample").state,"execution_request":execution.request is GMAbilityActivationRequest,"direct_world_write":execution.direct_world_write,"fact_count":service.fact_store.get_record_count(),"change_count":service.change_store.get_record_count(),"store_id":service.store.store_id,"chinese_first":true,"deferred":{"planner":"P17","inventory":"P19","process":"P20","scene_session":"P23"}}

func _capture(path: String, facts: Dictionary) -> void:
	for _frame in 3: await get_tree().process_frame
	var texture:=get_viewport().get_texture(); var absolute:=ProjectSettings.globalize_path(path); DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if texture == null: facts["screenshot_saved"]=false; facts["screenshot_path"]=absolute; facts["capture_code"]="p16.rendering_texture_unavailable"; print(JSON.stringify(facts)); get_tree().quit(164); return
	var image:=texture.get_image(); var err:=image.save_png(absolute); facts["screenshot_saved"]=err==OK; facts["screenshot_path"]=absolute; print(JSON.stringify(facts)); get_tree().quit(0 if err==OK and facts.ok else 164)
