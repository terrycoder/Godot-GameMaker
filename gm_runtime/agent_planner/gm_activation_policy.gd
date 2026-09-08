class_name GMActivationPolicy
extends RefCounted

const SCHEMA := "gm.activation_policy.snapshot.v1"
const STATES := ["inactive","active","blocked","suspended","player_takeover","invalid_context"]
var state:String="inactive"
var blocked_reason:Dictionary={}
var retry_triggers:Array[String]=[]
var sequence:int=0

func handle(event:String, details:Dictionary={}) -> Dictionary:
	if state=="inactive" and sequence>0 and event in ["ability_failed","target_lost","assignment_revoked","reservation_invalid","blocked","suspended","context_invalid"]:
		return {"ok":true,"state":state,"sequence":sequence,"clear_plan":false,"wait_for_event":false,"ignored_late_event":true}
	if state=="player_takeover" and event in ["ability_failed","target_lost","assignment_revoked","reservation_invalid","blocked","suspended","context_invalid","player_takeover"]:
		return {"ok":true,"state":state,"sequence":sequence,"clear_plan":false,"wait_for_event":true,"ignored_late_event":true}
	var next:=state
	match event:
		"mounted":
			if state=="player_takeover":return {"ok":false,"code":"planner.policy_release_required","state":state}
			next="active"
		"context_valid":
			if state=="player_takeover":return {"ok":false,"code":"planner.policy_release_required","state":state}
			next="active"
		"control_released":
			if state!="player_takeover":return {"ok":false,"code":"planner.policy_release_out_of_order","state":state}
			next="active"
		"blocked": next="blocked"
		"suspended": next="suspended"
		"player_takeover": next="player_takeover"
		"context_invalid","assignment_revoked","reservation_invalid","target_lost","ability_failed": next="invalid_context" if event=="context_invalid" else "blocked"
		"unloaded","unmounted","cancelled": next="inactive"
		_: return {"ok":false,"code":"planner.policy_event_unknown","reason_zh":"ActivationPolicy事件未知。"}
	sequence+=1; state=next
	blocked_reason = details.duplicate(true) if state in ["blocked","invalid_context"] else {}
	retry_triggers=[]
	for item in details.get("retry_triggers",[]):
		if typeof(item)==TYPE_STRING and GMTaskDefinition._stable_id(item) and item not in retry_triggers:retry_triggers.append(item)
	retry_triggers.sort()
	return {"ok":true,"state":state,"sequence":sequence,"clear_plan":event in ["blocked","suspended","player_takeover","assignment_revoked","reservation_invalid","target_lost","ability_failed","unloaded","unmounted","cancelled","context_invalid"],"wait_for_event":state in ["blocked","suspended","player_takeover","invalid_context"]}

func snapshot()->Dictionary: return {"schema":SCHEMA,"state":state,"blocked_reason":blocked_reason.duplicate(true),"retry_triggers":retry_triggers.duplicate(),"sequence":sequence}

func restore(value:Variant,json_boundary:bool=false)->Dictionary:
	if typeof(value)!=TYPE_DICTIONARY: return {"ok":false,"code":"planner.policy_snapshot_invalid"}
	var v:Dictionary=value
	var sequence_value:Variant=v.get("sequence")
	var sequence_valid:bool=typeof(sequence_value)==TYPE_FLOAT and GMAgentPlanner._safe_integer(sequence_value) and sequence_value>=0 if json_boundary else typeof(sequence_value)==TYPE_INT and sequence_value>=0 and sequence_value<=GMAgentPlanner.MAX_SAFE_INT
	if v.size()!=5 or typeof(v.get("schema"))!=TYPE_STRING or v.get("schema")!=SCHEMA or typeof(v.get("state"))!=TYPE_STRING or v.get("state") not in STATES or typeof(v.get("blocked_reason"))!=TYPE_DICTIONARY or typeof(v.get("retry_triggers"))!=TYPE_ARRAY or not sequence_valid:return {"ok":false,"code":"planner.policy_snapshot_invalid"}
	if not GMAgentPlanner._json_safe_value(v.blocked_reason):return {"ok":false,"code":"planner.policy_snapshot_invalid"}
	if v.state not in ["blocked","invalid_context"] and not v.blocked_reason.is_empty():return {"ok":false,"code":"planner.policy_snapshot_invalid"}
	var seen:={}
	for item in v.retry_triggers:
		if typeof(item)!=TYPE_STRING or not GMTaskDefinition._stable_id(item) or seen.has(item):return {"ok":false,"code":"planner.policy_snapshot_invalid"}
		seen[item]=true
	var canonical:Array=v.retry_triggers.duplicate();canonical.sort()
	if canonical!=v.retry_triggers:return {"ok":false,"code":"planner.policy_snapshot_invalid"}
	state=v.state; blocked_reason=v.blocked_reason.duplicate(true); retry_triggers=[]
	for item in v.retry_triggers: retry_triggers.append(str(item))
	sequence=int(sequence_value)
	return {"ok":true,"state":state}
