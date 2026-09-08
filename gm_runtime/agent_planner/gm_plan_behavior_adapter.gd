class_name GMPlanBehaviorAdapter
extends RefCounted

func submit(plan:Variant, character:GMCharacterRuntime2D, control_source:String="ai") -> Dictionary:
	if typeof(plan)!=TYPE_DICTIONARY or plan.get("schema")!=GMAgentPlanner.PLAN_SCHEMA: return {"ok":false,"code":"planner.plan_invalid","reason_zh":"ExecutionPlan无效。"}
	if character==null: return {"ok":false,"code":"planner.character_missing","reason_zh":"角色运行时缺失。"}
	var payload={"execution_plan_id":plan.plan_id,"candidate_id":plan.candidate_id,"source_kind":plan.source_kind,"task_id":plan.task_id,"assignment_id":plan.assignment_id,"reservation_id":plan.reservation_id,"free_action_id":plan.free_action_id,"target_context":plan.target_context.duplicate(true),"schedule_ref":plan.schedule_ref,"role_ref":plan.role_ref}
	# P15 owns movement semantics and execution.  This adapter only translates
	# the neutral plan target into P15's public ActivationRequest payload.
	if str(plan.ability_id)=="gm.ability.movement":
		var target:Dictionary=plan.target_context
		payload.movement_request={"schema":GMMovementRequest.SCHEMA,"kind":str(target.get("kind","anchor")),"source":control_source,"owner_id":character.control_router.selected_owner,"actor_id":character.stable_instance_id,"map_id":str(target.get("map_id",character.map_id)),"anchor_id":str(target.get("anchor_id","")),"speed":float(target.get("speed",160.0)),"acceleration":float(target.get("acceleration",1200.0)),"stop_distance":float(target.get("stop_distance",0.5)),"follow_distance":float(target.get("follow_distance",8.0))}
	return character.submit_activation_request(control_source,str(plan.ability_id),payload,"%s.%s"%[plan.plan_id,str(plan.ability_id)])
