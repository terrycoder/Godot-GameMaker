extends Control

func _ready()->void:
	var title:=Label.new();title.text="P17 Agent决策中性样板";title.position=Vector2(40,30);title.add_theme_font_size_override("font_size",26);add_child(title)
	var info:=RichTextLabel.new();info.position=Vector2(40,80);info.size=Vector2(900,500);info.fit_content=true;add_child(info)
	var candidate={"candidate_id":"gm.candidate.sample.rest","kind":"free_action","task_id":"","assignment_id":"","reservation_id":"","free_action_id":"gm.free_action.sample.rest","ability_id":"gm.ability.movement","target_context":{"anchor_id":"gm.anchor.sample.rest"},"contributions":{"source_duty":0.0,"urgency":0.0,"skill_tags":0.0,"preference":2.0,"distance":0.0,"resource_availability":0.0,"fatigue":1.0,"risk":0.0,"interrupt_cost":0.0,"schedule":1.0},"hard_priority":0,"available":true,"blocked_reason":"","retry_triggers":["task_changed"]}
	var bundle:=GMScheduleContextProvider.build(1,"gm.schedule.sample.day","gm.role.sample.generalist","gm.department.sample.operations",["gm.permission.sample"],{"gm.preference.sample.rest":1.0},["gm.window.sample.day"],"gm.preference.sample")
	var context={"schema":GMAgentPlanner.CONTEXT_SCHEMA,"agent_id":"gm.agent.sample","logical_tick":1,"seed":17,"sequence":1,"control_state":"ai","action_state":"actionable","candidates":[candidate],"schedule_context":bundle.schedule_context,"role_context":bundle.role_context,"department_context":bundle.department_context,"preference_context":bundle.preference_context,"random_offset_scale":0.0}
	var result:=GMAgentPlanner.new().decide(context)
	info.text="无Task：选择休息/巡逻类FreeAction\n计划：%s\nAbility：%s\n原因：偏好、疲劳与日程上下文形成可解释评分\n\n边界：Planner不移动角色、不写Task/Reservation/库存/Process/伤害；Attention仅控制可见投影。"%[result.plan.plan_id,result.plan.ability_id]
	print(JSON.stringify({"event":"P17_EXPORT_STARTUP_SENTINEL","ok":result.ok,"source_kind":result.plan.source_kind,"ability_id":result.plan.ability_id,"ui_zh":true}))
	if "--p17-smoke" in OS.get_cmdline_user_args():get_tree().quit(0)
