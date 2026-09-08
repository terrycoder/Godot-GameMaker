class_name GMAgentPlannerRuntime
extends RefCounted

const SNAPSHOT_SCHEMA := "gm.agent_planner.snapshot.v1"
var planner:=GMAgentPlanner.new()
var policy:=GMActivationPolicy.new()
var current_plan:Dictionary={}
var last_receipt:Dictionary={}
var attention_projection:Dictionary={}

func decide(context:Dictionary)->Dictionary:
	var fresh_inactive:=policy.state=="inactive" and policy.sequence==0
	if policy.state!="active" and not fresh_inactive:
		var trigger:="control_released" if policy.state=="player_takeover" else "context_valid" if policy.state in ["blocked","invalid_context","suspended"] else "mounted"
		return {"ok":false,"code":"planner.lifecycle_gate_closed","reason_zh":"ActivationPolicy尚未收到允许决策的显式生命周期事件。","retry_triggers":[trigger],"policy_state":policy.state,"wrote_domain_facts":false}
	var result:=planner.decide(context)
	# Candidate identity preflight is a write-before boundary: malformed or
	# duplicate stable IDs must not clear a prior plan/receipt or advance Policy.
	if str(result.get("code", "")) in ["planner.candidate_id_duplicate", "planner.candidate_identity_invalid"]:
		return result.duplicate(true)
	if result.ok:
		if fresh_inactive:return {"ok":false,"code":"planner.lifecycle_mount_required","reason_zh":"首次有效决策前必须显式mounted或context_valid。","retry_triggers":["mounted"],"policy_state":policy.state,"wrote_domain_facts":false}
		current_plan=result.plan.duplicate(true);last_receipt=result.receipt.duplicate(true)
	else:
		current_plan={};last_receipt={}
		var code:=str(result.get("code","planner.blocked"))
		var retries:Array=result.get("retry_triggers",[]).duplicate()
		if retries.is_empty():retries=["context_changed"]
		if code=="planner.player_takeover":policy.handle("player_takeover",{"retry_triggers":retries})
		elif fresh_inactive:policy.handle("blocked",{"code":code,"retry_triggers":retries})
		elif code.begins_with("planner.context") or code in ["planner.agent_not_actionable"]:policy.handle("context_invalid",{"code":code,"retry_triggers":retries})
		else:policy.handle("blocked",{"code":code,"retry_triggers":retries})
	return result.duplicate(true)

func handle_event(event:String,details:Dictionary={})->Dictionary:
	var result:=policy.handle(event,details)
	if result.get("clear_plan",false):current_plan={};last_receipt={}
	return result

func set_attention(value:Dictionary)->Dictionary:
	var checked:=GMAttentionBudget.validate_projection(value)
	if not checked.ok:return checked
	attention_projection=checked.value
	return {"ok":true,"atomic":true}

func snapshot(agent_id:String,seed:int,sequence:int)->Dictionary:
	return {"schema":SNAPSHOT_SCHEMA,"agent_id":agent_id,"seed":seed,"sequence":sequence,"plan":current_plan.duplicate(true),"receipt":last_receipt.duplicate(true),"policy":policy.snapshot(),"attention":attention_projection.duplicate(true)}

func restore(value:Variant,task_service:GMTaskService=null,json_boundary:bool=false)->Dictionary:
	if typeof(value)!=TYPE_DICTIONARY:return _fail("planner.snapshot_type_invalid")
	var v:Dictionary=value;var fields=["schema","agent_id","seed","sequence","plan","receipt","policy","attention"]
	if not _exact(v,fields):return _fail("planner.snapshot_fields_invalid")
	if typeof(v.schema)!=TYPE_STRING or v.schema!=SNAPSHOT_SCHEMA:return _fail("planner.snapshot_schema_invalid")
	if typeof(v.agent_id)!=TYPE_STRING or not GMTaskDefinition._stable_id(v.agent_id):return _fail("planner.snapshot_agent_invalid")
	if not _snapshot_integer(v.seed,json_boundary) or not _snapshot_integer(v.sequence,json_boundary) or v.sequence<0:return _fail("planner.snapshot_integer_invalid")
	if typeof(v.plan)!=TYPE_DICTIONARY or typeof(v.receipt)!=TYPE_DICTIONARY or typeof(v.policy)!=TYPE_DICTIONARY or typeof(v.attention)!=TYPE_DICTIONARY:return _fail("planner.snapshot_nested_variant_invalid")
	if v.plan.is_empty()!=v.receipt.is_empty():return _fail("planner.snapshot_plan_receipt_mismatch")
	if not v.plan.is_empty():
		var plan_checked:=GMAgentPlanner.validate_plan(v.plan,v.agent_id,json_boundary);if not plan_checked.ok:return _fail(plan_checked.code)
		var receipt_checked:=GMAgentPlanner.validate_receipt(v.receipt,v.plan,v.agent_id,json_boundary);if not receipt_checked.ok:return _fail(receipt_checked.code)
		if v.receipt.seed!=v.seed or v.receipt.sequence!=v.sequence:return _fail("planner.snapshot_receipt_sequence_mismatch")
		var authority:=_validate_authority(v.plan,task_service);if not authority.ok:return authority
	if not v.attention.is_empty():
		var attention_checked:=GMAttentionBudget.validate_projection(v.attention,json_boundary);if not attention_checked.ok:return _fail(attention_checked.code)
	var fresh_policy:=GMActivationPolicy.new();var restored:=fresh_policy.restore(v.policy,json_boundary)
	if not restored.ok:return _fail("planner.snapshot_policy_invalid")
	if not v.plan.is_empty() and fresh_policy.state!="active":return _fail("planner.snapshot_policy_plan_mismatch")
	# Apply only after every nested contributor and public P16 authority passed.
	current_plan=v.plan.duplicate(true);last_receipt=v.receipt.duplicate(true);attention_projection=v.attention.duplicate(true);policy=fresh_policy
	return {"ok":true,"agent_id":v.agent_id,"atomic":true}

func restore_json(text:String,task_service:GMTaskService=null)->Dictionary:
	var parsed:Variant=JSON.parse_string(text)
	if typeof(parsed)!=TYPE_DICTIONARY:return _fail("planner.snapshot_json_invalid")
	# The JSON boundary is validated in a throwaway runtime before any
	# normalization.  This keeps malformed, non-finite, out-of-range, or
	# relation-invalid input from reaching the stateful receiver at all.
	var boundary_validator:=GMAgentPlannerRuntime.new()
	var boundary_checked:=boundary_validator.restore(parsed,task_service,true)
	if not boundary_checked.ok:return boundary_checked
	var normalized:=_normalize_json(parsed)
	if not normalized.ok:return normalized
	# Normalization produces the native Variant contract (including integer
	# units), so the final restore deliberately uses the strict native path.
	return restore(normalized.value,task_service,false)

func _validate_authority(plan:Dictionary,task_service:GMTaskService)->Dictionary:
	if plan.source_kind=="free_action":return {"ok":true}
	if task_service==null:return _fail("planner.snapshot_authority_missing")
	var task:=task_service.read_task(plan.task_id);var assignment:=task_service.read_assignment(plan.assignment_id)
	if task.is_empty() or assignment.is_empty() or task.get("schema")!="gm.task.instance.v3" or assignment.get("schema")!="gm.task.assignment.v1" or assignment.get("state")!="active" or assignment.get("task_id")!=plan.task_id or task.get("assignment_id")!=plan.assignment_id or task.get("state") not in ["assigned","in_progress","blocked"] or typeof(assignment.get("assignee"))!=TYPE_DICTIONARY or assignment.assignee.get("type")!="actor" or assignment.assignee.get("id")!=plan.agent_id:return _fail("planner.snapshot_authority_stale")
	if not plan.reservation_id.is_empty():
		var reservation:=task_service.read_reservation(plan.reservation_id)
		if reservation.is_empty() or reservation.get("schema")!="gm.task.reservation.v1" or reservation.get("state")!="active" or reservation.get("task_id")!=plan.task_id or reservation.get("assignment_id")!=plan.assignment_id or reservation.get("owner")!=assignment.assignee:return _fail("planner.snapshot_reservation_stale")
		var expires:Variant=reservation.get("expires_at_tick")
		if typeof(expires)!=TYPE_INT or (expires>=0 and expires<=plan.logical_tick):return _fail("planner.snapshot_reservation_expired")
	return {"ok":true}

func _normalize_json(value:Dictionary)->Dictionary:
	# Deep-copy before touching nested Plan/Receipt dictionaries.  The parsed
	# caller-owned Variant must remain the raw JSON-boundary representation.
	var copy:Dictionary=value.duplicate(true)
	for key in ["seed","sequence"]:
		var integer:=_normalize_json_integer(copy,key)
		if not integer.ok:return integer
	if copy.get("policy") is Dictionary:
		var policy_copy:Dictionary[String,Variant]={}
		for source_key in copy.policy:policy_copy[source_key]=copy.policy[source_key]
		var policy_sequence:=_normalize_json_integer(policy_copy,"sequence")
		if not policy_sequence.ok:return policy_sequence
		copy.policy=policy_copy
	if copy.get("plan") is Dictionary and not copy.plan.is_empty():
		var plan_copy:Dictionary[String,Variant]={}
		for source_key in copy.plan:plan_copy[source_key]=copy.plan[source_key]
		var tick:=_normalize_json_integer(plan_copy,"logical_tick")
		if not tick.ok:return tick
		if plan_copy.get("steps") is Array:
			for index in plan_copy.steps.size():
				if typeof(plan_copy.steps[index])!=TYPE_DICTIONARY:return _fail("planner.snapshot_json_nested_invalid")
				var step:Dictionary=plan_copy.steps[index]
				var step_index:=_normalize_json_integer(step,"index")
				if not step_index.ok:return step_index
				plan_copy.steps[index]=step
		if plan_copy.get("reason_chain") is Array:
			for index in plan_copy.reason_chain.size():
				if typeof(plan_copy.reason_chain[index])!=TYPE_DICTIONARY:return _fail("planner.snapshot_json_nested_invalid")
				var reason:Dictionary=plan_copy.reason_chain[index]
				var reason_numeric:=_normalize_numeric_pair(reason)
				if not reason_numeric.ok:return reason_numeric
				plan_copy.reason_chain[index]=reason
			copy.plan=plan_copy
	if copy.get("receipt") is Dictionary and not copy.receipt.is_empty():
		var receipt_copy:Dictionary[String,Variant]={}
		for source_key in copy.receipt:receipt_copy[source_key]=copy.receipt[source_key]
		for key in ["logical_tick","seed","sequence"]:
			var integer:=_normalize_json_integer(receipt_copy,key)
			if not integer.ok:return integer
		var receipt_numeric:=_normalize_numeric_pair(receipt_copy)
		if not receipt_numeric.ok:return receipt_numeric
		if receipt_copy.get("ranked") is Array:
			for index in receipt_copy.ranked.size():
				if typeof(receipt_copy.ranked[index])!=TYPE_DICTIONARY:return _fail("planner.snapshot_json_nested_invalid")
				var row:Dictionary=receipt_copy.ranked[index]
				var priority:=_normalize_json_integer(row,"hard_priority")
				if not priority.ok:return priority
				var row_numeric:=_normalize_numeric_pair(row)
				if not row_numeric.ok:return row_numeric
				if row.get("breakdown") is Array:
					for breakdown_index in row.breakdown.size():
						if typeof(row.breakdown[breakdown_index])!=TYPE_DICTIONARY:return _fail("planner.snapshot_json_nested_invalid")
						var contribution:Dictionary=row.breakdown[breakdown_index]
						var contribution_numeric:=_normalize_numeric_pair(contribution)
						if not contribution_numeric.ok:return contribution_numeric
						row.breakdown[breakdown_index]=contribution
					receipt_copy.ranked[index]=row
		copy.receipt=receipt_copy
	if copy.get("attention") is Dictionary and not copy.attention.is_empty():
		var attention_copy:Dictionary[String,Variant]={}
		for source_key in copy.attention:attention_copy[source_key]=copy.attention[source_key]
		for key in ["capacity","candidate_count"]:
			var integer:=_normalize_json_integer(attention_copy,key)
			if not integer.ok:return integer
		copy.attention=attention_copy
	return {"ok":true,"value":copy}

func _normalize_numeric_pair(owner:Dictionary)->Dictionary:
	var number_key:String=""
	if owner.has("amount"):
		number_key="amount"
	elif owner.has("score"):
		number_key="score"
	else:
		return {"ok":true}
	var units_key:String="%s_units"%number_key
	if not owner.has(units_key):return _fail("planner.snapshot_json_numeric_invalid")
	if not GMAgentPlanner._numeric_pair_valid(owner[number_key],owner[units_key],true):return _fail("planner.snapshot_json_numeric_invalid")
	var stored:=GMAgentPlanner._stored_units(owner[units_key],true)
	if not stored.ok:return _fail("planner.snapshot_json_numeric_invalid")
	# Rewrite only the explicit, schema-authoritative pair after validating it.
	# This is canonicalization, not forgiveness: the pair was checked first.
	owner[units_key]=int(stored.units)
	owner[number_key]=GMAgentPlanner._units_to_number(int(stored.units))
	return {"ok":true}

func _normalize_json_integer(owner:Dictionary,key:String)->Dictionary:
	if not owner.has(key):return _fail("planner.snapshot_json_integer_invalid")
	var checked:=_json_to_int(owner[key])
	if not checked.ok:return checked
	owner[key]=int(checked.value)
	return {"ok":true}

func _json_to_int(value:Variant)->Dictionary:
	if typeof(value)!=TYPE_FLOAT or not GMAgentPlanner._safe_integer(value):return _fail("planner.snapshot_json_integer_invalid")
	var result:Dictionary[String,Variant]={"ok":true};result["value"]=int(value);return result

func _exact(value:Dictionary,fields:Array)->bool:
	if value.size()!=fields.size():return false
	for field in fields:
		if not value.has(field):return false
	return true

func _safe_integer(value:Variant)->bool:return GMAgentPlanner._safe_integer(value)
func _snapshot_integer(value:Variant,json_boundary:bool)->bool:
	if json_boundary:return typeof(value)==TYPE_FLOAT and _safe_integer(value)
	return typeof(value)==TYPE_INT and value>=-GMAgentPlanner.MAX_SAFE_INT and value<=GMAgentPlanner.MAX_SAFE_INT

func _fail(code:String)->Dictionary:return {"ok":false,"code":code,"reason_zh":"Planner快照校验失败，既有运行状态未改变。","atomic":true,"wrote_domain_facts":false}
