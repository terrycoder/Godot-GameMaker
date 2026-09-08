class_name GMScheduleContextProvider
extends RefCounted

const SCHEMA := "gm.agent.readonly_context.v1"
const SCHEDULE_SCHEMA := "gm.agent.schedule_context.v1"
const ROLE_SCHEMA := "gm.agent.role_context.v1"
const DEPARTMENT_SCHEMA := "gm.agent.department_context.v1"
const PREFERENCE_SCHEMA := "gm.agent.preference_context.v1"

static func build(logical_tick:int, schedule_id:String, role_id:String, department_id:String, permission_ids:Array[String], preference_weights:Dictionary, active_window_ids:Array[String], preference_profile_id:String="gm.preference.default") -> Dictionary:
	if logical_tick<0 or logical_tick>GMAgentPlanner.MAX_SAFE_INT: return _fail("planner.context_tick_invalid","逻辑时间必须是JSON安全的非负整数。")
	for stable_id in [schedule_id,role_id,department_id,preference_profile_id]:
		if not GMTaskDefinition._stable_id(stable_id): return _fail("planner.context_reference_invalid","日程、职位、部门和偏好配置必须使用非空稳定ID。")
	var permissions:=_stable_array(permission_ids)
	if not permissions.ok:return permissions
	var windows:=_stable_array(active_window_ids)
	if not windows.ok:return windows
	var clean_weights:={}
	for key in preference_weights:
		if typeof(key)!=TYPE_STRING or not GMTaskDefinition._stable_id(str(key)) or typeof(preference_weights[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(preference_weights[key])): return _fail("planner.preference_invalid","偏好必须使用稳定ID和有限数值。")
		clean_weights[str(key)]=float(preference_weights[key])
	return {"ok":true,"schema":SCHEMA,"logical_tick":logical_tick,"schedule_context":{"schema":SCHEDULE_SCHEMA,"schedule_id":schedule_id,"logical_tick":logical_tick,"active_window_ids":windows.value,"readonly":true},"role_context":{"schema":ROLE_SCHEMA,"role_id":role_id,"logical_tick":logical_tick,"permission_ids":permissions.value,"readonly":true},"department_context":{"schema":DEPARTMENT_SCHEMA,"department_id":department_id,"logical_tick":logical_tick,"readonly":true},"preference_context":{"schema":PREFERENCE_SCHEMA,"profile_id":preference_profile_id,"logical_tick":logical_tick,"weights":clean_weights,"readonly":true},"can_write_task":false,"can_execute_ability":false}

static func validate_bundle(contexts:Dictionary, logical_tick:int)->Dictionary:
	var required:={"schedule_context":["schema","schedule_id","logical_tick","active_window_ids","readonly"],"role_context":["schema","role_id","logical_tick","permission_ids","readonly"],"department_context":["schema","department_id","logical_tick","readonly"],"preference_context":["schema","profile_id","logical_tick","weights","readonly"]}
	var schemas:={"schedule_context":SCHEDULE_SCHEMA,"role_context":ROLE_SCHEMA,"department_context":DEPARTMENT_SCHEMA,"preference_context":PREFERENCE_SCHEMA}
	var ids:={"schedule_context":"schedule_id","role_context":"role_id","department_context":"department_id","preference_context":"profile_id"}
	for key in required:
		if not contexts.has(key) or typeof(contexts[key])!=TYPE_DICTIONARY:return _fail("planner.context_provider_type_invalid","只读上下文Provider缺失或Variant错误。",{"field":key})
		var row:Dictionary=contexts[key]
		if not _exact(row,required[key]) or typeof(row.schema)!=TYPE_STRING or row.schema!=schemas[key] or typeof(row[ids[key]])!=TYPE_STRING or not GMTaskDefinition._stable_id(row[ids[key]]) or typeof(row.logical_tick)!=TYPE_INT or row.logical_tick!=logical_tick or typeof(row.readonly)!=TYPE_BOOL or not row.readonly:return _fail("planner.context_provider_invalid","只读上下文schema、字段、稳定ID、逻辑时间或readonly无效。",{"field":key})
	var schedule:Dictionary=contexts.schedule_context
	var role:Dictionary=contexts.role_context
	var preference:Dictionary=contexts.preference_context
	var windows:=_stable_array(schedule.active_window_ids);if not windows.ok:return windows
	var permissions:=_stable_array(role.permission_ids);if not permissions.ok:return permissions
	if typeof(preference.weights)!=TYPE_DICTIONARY:return _fail("planner.preference_invalid","偏好权重必须是Dictionary。")
	for weight_id in preference.weights:
		if typeof(weight_id)!=TYPE_STRING or not GMTaskDefinition._stable_id(str(weight_id)) or typeof(preference.weights[weight_id]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(preference.weights[weight_id])):return _fail("planner.preference_invalid","偏好权重包含错误ID、Variant或非有限数。")
	return {"ok":true,"value":{"schedule_context":schedule.duplicate(true),"role_context":role.duplicate(true),"department_context":contexts.department_context.duplicate(true),"preference_context":preference.duplicate(true)}}

static func _stable_array(value:Variant)->Dictionary:
	if typeof(value)!=TYPE_ARRAY:return _fail("planner.context_array_invalid","上下文ID集合必须是Array。")
	var seen:={};var clean:Array[String]=[]
	for item in value:
		if typeof(item)!=TYPE_STRING or not GMTaskDefinition._stable_id(item) or seen.has(item):return _fail("planner.context_array_invalid","上下文ID集合必须只含唯一稳定ID。")
		seen[item]=true;clean.append(item)
	clean.sort()
	return {"ok":true,"value":clean}

static func _exact(value:Dictionary,fields:Array)->bool:
	if value.size()!=fields.size():return false
	for field in fields:
		if not value.has(field):return false
	return true

static func _fail(code:String,reason:String,details:Dictionary={})->Dictionary:return {"ok":false,"code":code,"reason_zh":reason,"details":details,"wrote_domain_facts":false}
