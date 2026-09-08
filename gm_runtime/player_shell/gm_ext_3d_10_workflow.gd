class_name GMExt3D10Workflow
extends RefCounted

const SCHEMA := "gm.ext3d10.independent_run.v2"
const WORKSPOT_TOLERANCE_PX := 0.75
const MAX_MOVEMENT_STEPS := 160
const MOVEMENT_DELTA := 0.2

func execute(shell:GMPlayerShell,profile:GMNeutralVerticalSampleProfile,dimension:String,arrival_gate:Callable=Callable())->Dictionary:
	if shell==null or profile==null or dimension not in ["2d","3d"]:return _fail("sample.workflow_input_invalid","独立样板工作流缺少外壳、正式Profile或有效维度。")
	var checked:=profile.validate()
	if not checked.ok:return checked
	var registered:=_register_task_definition(shell,profile)
	if not registered.ok:return registered
	var process_service:Variant=_build_process_service(profile,dimension)
	if process_service is Dictionary:return process_service
	var resource_result:=_build_resource_authority(profile)
	if not resource_result.ok:return resource_result
	var resource_store:GMNumericResourceStore=resource_result.store
	var states:Array[Dictionary]=[]
	for spec in profile.actor_specs:
		var prepared:=_prepare_actor(shell,profile,spec)
		if not prepared.ok:return prepared
		states.append(prepared.state)
	var rows:Array[Dictionary]=[];var blocked_events:Array[Dictionary]=[];var recovered_workspots:Dictionary={}
	var round:=0;var max_rounds:=maxi(4,states.size()*3+profile.spatial_recovery_round+2)
	while rows.size()<states.size() and round<max_rounds:
		round+=1
		var admitted:Array[Dictionary]=[];var resource_blocks:Dictionary={}
		for state in states:
			if str(state.status)=="completed":continue
			state.attempts=int(state.attempts)+1
			var lease:=_acquire_workspot(shell,profile,state,round)
			if not lease.ok:
				blocked_events.append(_blocked_event(state,round,"workspot",str(lease.get("code","task.reservation_blocked"))))
				continue
			if round <= profile.spatial_recovery_round:
				_release_workspot(shell,state,round,"spatial_blocked")
				blocked_events.append(_blocked_event(state,round,"spatial","spatial.temporarily_unreachable"))
				continue
			var resource_lease:=_acquire_resource(resource_store,profile,state,round)
			if not resource_lease.ok:
				resource_blocks[str(state.target.workspot_id)]=state.target
				_release_workspot(shell,state,round,"resource_blocked")
				blocked_events.append(_blocked_event(state,round,"resource",str(resource_lease.get("code","numeric.reservation_conflict"))))
				continue
			state["resource_authorized"] = true
			var movement:=_move_to_workspot(shell,profile,state,dimension,round,arrival_gate)
			if not movement.ok:
				resource_store.release_reservation(str(resource_lease.transaction_id));_release_workspot(shell,state,round,"spatial_blocked")
				blocked_events.append(_blocked_event(state,round,"spatial",str(movement.get("code","spatial.temporarily_unreachable"))))
				continue
			state["gate"]=movement;state["resource_transaction_id"]=str(resource_lease.transaction_id);admitted.append(state)
		for state in admitted:
			var completed:=_complete_actor(shell,profile,process_service,resource_store,state,round)
			if not completed.ok:return completed
			state.status="completed";rows.append(completed.row)
		for workspot_id in resource_blocks:
			var target:Dictionary=resource_blocks[workspot_id]
			if not recovered_workspots.has(workspot_id) and int(target.resource_recovery_balance)>int(target.resource_initial_balance):
				var recovered:=_recover_resource_authority(resource_store,target)
				if not recovered.ok:return recovered
				recovered_workspots[workspot_id]=true
		if admitted.is_empty() and resource_blocks.is_empty() and round>profile.spatial_recovery_round and rows.size()<states.size():
			return _fail("sample.retry_no_progress","权威条件已允许恢复但工作流没有取得进展。",{"round":round,"blocked_events":blocked_events})
	if rows.size()!=states.size():return _fail("sample.retry_exhausted","权威阻断条件在有界重试内未恢复。",{"rounds":round,"completed":rows.size(),"expected":states.size(),"blocked_events":blocked_events})
	var characters:Array[GMCharacterRuntime2D]=[]
	for state in states:characters.append(state.character)
	var projection:=semantic_projection(shell.task_service,rows,profile,dimension)
	return {"ok":true,"schema":SCHEMA,"dimension":dimension,"seed":profile.seed,"definition_id":profile.task_definition_id,"shared_key":"gm.ext3d10.shared.workflow.v3","rows":rows,"characters":characters,"process_service":process_service,"resource_store":resource_store,"projection":projection,"blocked_events":blocked_events,"retry_summary":{"rounds":round,"blocked_count":blocked_events.size(),"recovered_workspot_ids":recovered_workspots.keys()}}

func _register_task_definition(shell:GMPlayerShell,profile:GMNeutralVerticalSampleProfile)->Dictionary:
	var definition:=GMTaskDefinition.new();definition.definition_id=profile.task_definition_id;definition.display_name_zh="中性纵向工作";definition.description_zh="由正式配置声明的角色在权威WorkSpot和资源条件满足后完成Process。"
	definition.objectives=[{"objective_id":"gm.objective.ext3d10.workflow","display_name_zh":"完成中性工位流程","signal_kind":"fact","signal_type":"gm.fact.process.completed","target_value":1,"contribution_field":"count","target_match":{}}]
	definition.allowed_source_types=["script","ai"];definition.default_context_mode="local"
	definition.reservation_rules=[]
	for facility in profile.facility_specs:
		for target in facility.workspots:
			definition.reservation_rules.append({"rule_id":target.reservation_rule_id,"subject":{"type":"facility_slot","id":target.workspot_id},"mode":"capacity","capacity":target.capacity})
	var player_target:=profile.player_target()
	definition.workbench_profile={"source_type":"script","task_id":"gm.task.ext3d10.workbench","parent_task_id":"","assignment_id":"gm.assignment.ext3d10.workbench","assignment_kind":"actor","assignee":{"type":"actor","id":str(profile.actor_specs[0].actor_id)},"provider":{"provider_id":"gm.duty.ext3d10.workflow","event_type":"gm.fact.ext3d10.duty","key_field":"gm.key.ext3d10.duty","subject":{"type":"facility","id":player_target.facility_id}},"reservation":{"reservation_id":"gm.reservation.ext3d10.workbench","rule_id":player_target.reservation_rule_id,"amount":1,"expires_at_tick":profile.seed+1000}}
	var validation:=definition.validate_definition()
	if not validation.ok:return validation
	var value:Variant=shell.task_service.submit_operation(shell.player_host,"register_definition",definition.to_dict(),"script",str(profile.actor_specs[0].actor_id),"gm.ext3d10.shared.definition.register")
	return {"ok":true} if _typed_success(value) else _typed_failure(value,"sample.task_definition_register_failed")

func _build_process_service(profile:GMNeutralVerticalSampleProfile,dimension:String)->Variant:
	var service:=GMProcessService.new(GMProcessStore.new(),GMProcessClock.new("turn",0))
	for facility in profile.facility_specs:
		for target in facility.workspots:
			var definition:=GMProcessDefinition.new();definition.definition_id=target.process_definition_id;definition.revision=1;definition.display_name_zh="中性工位处理";definition.process_family="production";definition.duration_units=2;definition.capability_ids=PackedStringArray(["gm.capability.ext3d10.work"])
			definition.facility_target={"schema_version":1,"domain_id":"gm.spatial.planar_%s"%dimension,"kind":"facility_slot","semantic_id":target.workspot_id,"map_id":profile.map_id}
			definition.completion_kind="typed_domain_request";definition.completion_payload={"request_type":"gm.domain.ext3d10.work.completed","facility_id":facility.facility_id,"workspot_id":target.workspot_id};definition.task_definition_id=profile.task_definition_id;definition.duty_provider_id="gm.duty.ext3d10.workflow"
			var registered:=service.register_definition(definition);if not registered.ok:return registered
	return service

func _build_resource_authority(profile:GMNeutralVerticalSampleProfile)->Dictionary:
	var store:=GMNumericResourceStore.new("gm.store.ext3d10.resource")
	for facility in profile.facility_specs:
		for target in facility.workspots:
			var definition:=GMNumericResourceDefinition.new().configure(target.resource_id,"gm.unit.whole",{"display_name_zh":"中性工位资源","minimum_value":0,"maximum_capacity":maxi(target.resource_initial_balance,target.resource_recovery_balance)})
			var registered:=store.register_definition(definition);if not registered.ok:return registered
			var account:=GMNumericResourceAccount.new().configure(target.resource_account_id,target.resource_id,facility.facility_id,target.workspot_id,target.resource_initial_balance,maxi(target.resource_initial_balance,target.resource_recovery_balance))
			var account_registered:=store.register_account(account);if not account_registered.ok:return account_registered
	return {"ok":true,"store":store}

func _prepare_actor(shell:GMPlayerShell,profile:GMNeutralVerticalSampleProfile,spec:Dictionary)->Dictionary:
	var actor_id:=str(spec.actor_id);var key:=profile.actor_key(actor_id);var task_id:="gm.task.ext3d10.%s"%key;var assignment_id:="gm.assignment.ext3d10.%s"%key;var reservation_id:="gm.reservation.ext3d10.%s.workspot"%key;var prefix:="gm.ext3d10.shared.%s"%key
	var target:=profile.target_for_actor(actor_id);if target.is_empty():return _fail("sample.actor_target_missing","角色的正式WorkSpot引用无法解析。")
	var published:Variant=shell.task_service.submit_operation(shell.player_host,"publish_task",{"task_id":task_id,"definition_id":profile.task_definition_id,"parent_task_id":"","group_id":"","execution_context":{"mode":"local","stable_context":{"target":{"type":"facility","id":target.facility_id},"participants":[{"type":"actor","id":actor_id}],"resources":[{"type":"resource","id":target.resource_id}],"constraints":{"workspot_id":target.workspot_id},"seed":profile.seed}}},"script",actor_id,"%s.publish"%prefix)
	if not _typed_success(published):return _typed_failure(published,"sample.task_publish_failed")
	var owner:={"type":"actor","id":actor_id};var assigned:Variant=shell.task_service.submit_operation(shell.player_host,"assign",{"assignment_id":assignment_id,"task_id":task_id,"assignee":owner,"kind":"actor"},"script",actor_id,"%s.assign"%prefix)
	if not _typed_success(assigned):return _typed_failure(assigned,"sample.task_assign_failed")
	var character:=_make_character(shell,profile,spec);var mounted:=character.mount_runtime(GMRuntimeContext.new())
	if not mounted.ok:return mounted
	return {"ok":true,"state":{"spec":spec,"target":target,"actor_id":actor_id,"key":key,"task_id":task_id,"assignment_id":assignment_id,"reservation_id":reservation_id,"prefix":prefix,"owner":owner,"character":character,"attempts":0,"status":"pending"}}

func _acquire_workspot(shell:GMPlayerShell,profile:GMNeutralVerticalSampleProfile,state:Dictionary,round:int)->Dictionary:
	var target:Dictionary=state.target;var subject:={"type":"facility_slot","id":target.workspot_id};var value:Variant=shell.task_service.submit_operation(shell.player_host,"acquire_reservation",{"reservation_id":state.reservation_id,"task_id":state.task_id,"assignment_id":state.assignment_id,"owner":state.owner,"subject":subject,"rule_id":target.reservation_rule_id,"amount":1,"expires_at_tick":profile.seed+1000},"script",state.actor_id,"%s.reserve.%02d"%[state.prefix,round])
	if _typed_success(value):return {"ok":true,"subject":subject}
	return _typed_failure(value,"sample.workspot_reservation_blocked")

func _release_workspot(shell:GMPlayerShell,state:Dictionary,round:int,reason:String)->Dictionary:
	var value:Variant=shell.task_service.submit_operation(shell.player_host,"release_reservation",{"reservation_id":state.reservation_id,"reason_code":reason},"script",state.actor_id,"%s.release.%02d.%s"%[state.prefix,round,reason])
	return {"ok":_typed_success(value)}

func _acquire_resource(store:GMNumericResourceStore,profile:GMNeutralVerticalSampleProfile,state:Dictionary,round:int)->Dictionary:
	var target:Dictionary=state.target;var transaction_id:="gm.transaction.ext3d10.resource.%s.%02d"%[state.key,round];var claim:={"account_id":target.resource_account_id,"resource_id":target.resource_id,"amount":target.resource_amount_per_process}
	var reserved:=store.reserve(transaction_id,[claim],[],store.version)
	if not reserved.ok:return reserved
	return {"ok":true,"transaction_id":transaction_id,"reservation":reserved.reservation}

func _move_to_workspot(shell:GMPlayerShell,profile:GMNeutralVerticalSampleProfile,state:Dictionary,dimension:String,round:int,arrival_gate:Callable)->Dictionary:
	var character:GMCharacterRuntime2D=state.character
	var planner_result:=GMAgentPlanner.new().decide(_planner_context(shell,profile,state,round))
	if not planner_result.ok:return planner_result
	if dimension=="3d":
		if not arrival_gate.is_valid():return _fail("sample.3d_arrival_gate_missing","3D工作流缺少Planar 3D移动后端门。")
		var target_position:=profile.point(state.target.logical_position)*shell.shell_configuration.tile_size
		var gate: Dictionary = arrival_gate.call(state.actor_id,str(state.spec.entity_id),character.position,target_position,round,planner_result.plan,state.target)
		if bool(gate.get("ok", false)):
			character.position = target_position
		return gate
	var movement:=character.configure_movement(shell.semantic_registry)
	if not movement.ok:return movement
	var acquired:=character.control_router.acquire("ai","gm.planner.ext3d10")
	if not acquired.ok:return acquired
	var submitted:=GMPlanBehaviorAdapter.new().submit(planner_result.plan,character,"ai")
	if not submitted.ok:return submitted
	var steps:=0
	var target_position:=profile.point(state.target.logical_position)*shell.shell_configuration.tile_size
	while steps<MAX_MOVEMENT_STEPS and character.position.distance_to(target_position)>WORKSPOT_TOLERANCE_PX:character.ability_host.tick(MOVEMENT_DELTA);steps+=1
	character.ability_host.tick(MOVEMENT_DELTA)
	var arrived:=character.position.distance_to(target_position)<=WORKSPOT_TOLERANCE_PX
	return {"ok":arrived,"surface_id":profile.entry_surface_id,"surface_trace":[profile.entry_surface_id],"transition_count":0,"movement_steps":steps,"movement_ability":"gm.ability.movement"}

func _complete_actor(shell:GMPlayerShell,profile:GMNeutralVerticalSampleProfile,process_service:GMProcessService,resource_store:GMNumericResourceStore,state:Dictionary,round:int)->Dictionary:
	var target:Dictionary=state.target;var character:GMCharacterRuntime2D=state.character;var gate:Dictionary=state.gate;var reservation:=shell.task_service.read_reservation(state.reservation_id);var distance:=character.position.distance_to(profile.point(target.logical_position)*shell.shell_configuration.tile_size)
	var arrived: bool = distance <= WORKSPOT_TOLERANCE_PX and bool(gate.get("ok", false))
	if not process_gate_allows(arrived,str(reservation.get("state","")),gate) or resource_store.reservation_for(str(state.resource_transaction_id)).is_empty():return _fail("sample.workspot_gate_failed","权威到达、WorkSpot Reservation或资源Reservation不满足，Process未启动。",{"reservation":reservation,"gate":gate,"resource_reserved":not resource_store.reservation_for(str(state.resource_transaction_id)).is_empty()})
	var started:=process_service.request(GMProcessAbilityAdapter.start(character.ability_host,target.process_definition_id,state.actor_id,"%s.process.start"%state.prefix));if not started.ok:return started
	var instance_id:=str(started.instance.instance_id);var participated:=process_service.request(GMProcessAbilityAdapter.action(character.ability_host,"participate",instance_id,state.actor_id,"%s.process.participate"%state.prefix,state.actor_id));if not participated.ok:return participated
	var completed:=process_service.advance(instance_id,2);if not completed.ok:return completed
	var consumed:Variant=shell.task_service.submit_operation(shell.player_host,"consume_reservation",{"reservation_id":state.reservation_id,"task_id":state.task_id,"assignment_id":state.assignment_id,"owner":state.owner,"subject":{"type":"facility_slot","id":target.workspot_id},"consume_receipt":"%s.consume"%state.prefix},"script",state.actor_id,"%s.consume.operation"%state.prefix)
	if not _typed_success(consumed):return _typed_failure(consumed,"sample.task_reservation_consume_failed")
	resource_store.release_reservation(str(state.resource_transaction_id))
	var row:={"actor_id":state.actor_id,"entity_id":str(state.spec.entity_id),"facility_id":target.facility_id,"workspot_id":target.workspot_id,"process_definition_id":target.process_definition_id,"task_id":state.task_id,"assignment_id":state.assignment_id,"reservation_id":state.reservation_id,"reservation_state_at_process":"active","reservation_final_state":str(shell.task_service.read_reservation(state.reservation_id).get("state","")),"plan_id":str(gate.get("plan_id","")),"shared_key":state.prefix,"movement_ability":str(gate.get("movement_ability","gm.ability.movement")),"movement_steps":int(gate.get("movement_steps",0)),"arrival_verified":arrived,"workspot_distance_px":distance,"logical_position":{"x":character.position.x/shell.shell_configuration.tile_size.x,"y":character.position.y/shell.shell_configuration.tile_size.y},"surface_id":str(gate.get("surface_id",profile.entry_surface_id)),"surface_trace":Array(gate.get("surface_trace",[])).duplicate(true),"surface_transition_count":int(gate.get("transition_count",0)),"process_instance_id":instance_id,"process_state":str(completed.state),"process_started_after_gate":true,"completed_round":round}
	return {"ok":true,"row":row}

func _recover_resource_authority(store:GMNumericResourceStore,target:Dictionary)->Dictionary:
	var current:=store.get_account(target.resource_account_id);if current==null:return _fail("sample.resource_account_missing","资源恢复找不到权威账户。")
	var recovered:=GMNumericResourceAccount.from_dict(current.to_dict());recovered.balance=target.resource_recovery_balance;recovered.account_version+=1;recovered.last_fact_id="gm.fact.ext3d10.resource.recovered"
	return store.register_account(recovered)

func _make_character(shell:GMPlayerShell,profile:GMNeutralVerticalSampleProfile,spec:Dictionary)->GMCharacterRuntime2D:
	var character:=GMCharacterRuntime2D.new();character.stable_instance_id=str(spec.actor_id);character.map_id=profile.map_id;character.spawn_anchor_id=shell.shell_configuration.entry_anchor_id;character.position=profile.point(spec.spawn_logical)*shell.shell_configuration.tile_size
	var role:=GMRoleProfile.new();role.role_id="gm.role.ext3d10.worker";role.display_name_zh="中性工作者";role.enabled_control_sources=PackedStringArray(["ai"]);character.role_profile=role;shell.world_2d.add_child(character);return character

func _planner_context(shell:GMPlayerShell,profile:GMNeutralVerticalSampleProfile,state:Dictionary,round:int)->Dictionary:
	var resource_available := 1.0 if bool(state.get("resource_authorized", false)) else 0.0
	var target:Dictionary=state.target
	var candidate:={"candidate_id":"gm.candidate.ext3d10.%s"%state.key,"kind":"task","task_id":state.task_id,"assignment_id":state.assignment_id,"reservation_id":state.reservation_id,"free_action_id":"","ability_id":"gm.ability.movement","target_context":{"kind":"anchor","map_id":profile.map_id,"anchor_id":target.anchor_id,"target_surface_id":target.surface_id,"facility_id":target.facility_id,"workspot_id":target.workspot_id,"speed":180.0,"acceleration":1200.0,"stop_distance":0.5},"contributions":{"source_duty":10.0,"urgency":1.0,"skill_tags":1.0,"preference":0.0,"distance":0.0,"resource_availability":resource_available,"fatigue":0.0,"risk":0.0,"interrupt_cost":0.0,"schedule":1.0},"hard_priority":10,"available":resource_available > 0.0,"blocked_reason":"" if resource_available > 0.0 else "resource_unavailable","retry_triggers":["context_changed","resource_changed","spatial_graph_changed"]}
	var schedule:=GMScheduleContextProvider.build(round,"gm.schedule.ext3d10.day","gm.role.ext3d10.worker","gm.department.ext3d10.neutral",["gm.permission.ext3d10.work"],{},["gm.window.ext3d10.day"])
	return {"schema":GMAgentPlanner.CONTEXT_SCHEMA,"agent_id":state.actor_id,"logical_tick":round,"seed":profile.seed,"sequence":round,"control_state":"ai","action_state":"actionable","candidates":[candidate],"schedule_context":schedule.schedule_context,"role_context":schedule.role_context,"department_context":schedule.department_context,"preference_context":schedule.preference_context,"random_offset_scale":0.0}

func semantic_projection(task_service:GMTaskService,rows:Array[Dictionary],profile:GMNeutralVerticalSampleProfile,dimension:String)->Dictionary:
	var tasks:Array=[];var processes:Array=[]
	for row in rows:
		var task:=task_service.read_task(str(row.task_id));tasks.append({"actor_id":row.actor_id,"task_id":row.task_id,"definition_id":str(task.get("definition_id","")),"state":str(task.get("state","")),"assignment_id":row.assignment_id,"facility_id":row.facility_id,"workspot_id":row.workspot_id,"reservation_final_state":row.reservation_final_state});processes.append({"actor_id":row.actor_id,"definition_id":row.process_definition_id,"facility_id":row.facility_id,"workspot_id":row.workspot_id,"state":row.process_state,"arrival_verified":row.arrival_verified,"reservation_state_at_process":row.reservation_state_at_process,"process_started_after_gate":row.process_started_after_gate})
	tasks.sort_custom(func(a:Dictionary,b:Dictionary):return str(a.actor_id)<str(b.actor_id));processes.sort_custom(func(a:Dictionary,b:Dictionary):return str(a.actor_id)<str(b.actor_id))
	var facts:Array=[]
	for fact in task_service.fact_store.get_records():
		var key:=str(fact.get("idempotency_key",""));if not key.begins_with("gm.ext3d10.shared."):continue
		facts.append({"type":str(fact.get("type","")),"idempotency_key":key,"actor":str(fact.get("actor","")),"targets":Array(fact.get("targets",[])).duplicate(true)})
	facts.sort_custom(func(a:Dictionary,b:Dictionary):return str(a.idempotency_key)<str(b.idempotency_key))
	return {"schema":"gm.ext3d10.semantic_projection.v3","dimension":dimension,"profile_id":profile.profile_id,"seed":profile.seed,"definition_id":profile.task_definition_id,"shared_key":"gm.ext3d10.shared.workflow.v3","facts":facts,"tasks":tasks,"processes":processes,"fact_count":facts.size(),"task_count":tasks.size(),"process_count":processes.size()}

func _blocked_event(state:Dictionary,round:int,stage:String,code:String)->Dictionary:
	var triggers: Array[String] = ["context_changed"]
	if stage == "workspot": triggers = ["reservation_released", "context_changed"]
	elif stage == "resource": triggers = ["resource_changed"]
	elif stage == "spatial": triggers = ["spatial_graph_changed"]
	return {"actor_id":state.actor_id,"round":round,"stage":stage,"code":code,"process_started":false,"retry_triggers":triggers}
static func comparable_projection(projection:Dictionary)->Dictionary:var value:=projection.duplicate(true);value.erase("dimension");return value
static func process_gate_allows(arrived:bool,reservation_state:String,gate:Dictionary)->bool:return arrived and reservation_state=="active" and bool(gate.get("ok",false))
static func write_json_if_requested(value:Dictionary)->Dictionary:
	var path:=OS.get_environment("GM_EXT_3D_10_RUN_EVIDENCE")
	if path.strip_edges().is_empty():
		for argument in OS.get_cmdline_user_args():
			if str(argument).begins_with("--gm-ext-3d-10-evidence="):path=str(argument).trim_prefix("--gm-ext-3d-10-evidence=");break
	if path.strip_edges().is_empty():return {"ok":true,"written":false}
	var file:=FileAccess.open(path,FileAccess.WRITE);if file==null:return {"ok":false,"code":"sample.evidence_open_failed","path":path}
	file.store_string(JSON.stringify(value,"  ",false,true));file.close();return {"ok":true,"written":true,"path":path}
static func pack_file_inventory()->Array[String]:var files:Array[String]=[];_walk_files("res://",files);files.sort();return files
static func _walk_files(path:String,files:Array[String])->void:
	var directory:=DirAccess.open(path);if directory==null:return
	directory.list_dir_begin();var name:=directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child := path.path_join(name)
			if directory.current_is_dir():
				_walk_files(child, files)
			else:
				files.append(child)
		name=directory.get_next()
	directory.list_dir_end()
func _typed_success(value:Variant)->bool:return value is GMCommittedFactResult or (value is Dictionary and bool(value.get("ok",false)))
func _typed_failure(value:Variant,fallback_code:String)->Dictionary:
	if value is GMBlockedResult:return {"ok":false,"code":value.error_code,"reason_zh":value.reason_zh,"details":value.to_dict()}
	if value is Dictionary:return value
	return _fail(fallback_code,"既有领域服务没有返回可验证的提交结果。")
func _fail(code:String,reason_zh:String,details:Dictionary={})->Dictionary:return {"ok":false,"code":code,"reason_zh":reason_zh,"details":details}
