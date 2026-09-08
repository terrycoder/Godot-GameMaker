class_name GMAgentPlanner
extends RefCounted

const CONTEXT_SCHEMA := "gm.agent.context.v1"
const PLAN_SCHEMA := "gm.execution_plan.v2"
const RECEIPT_SCHEMA := "gm.decision_receipt.v2"
const JSON_SAFE_BOUND_EXCLUSIVE: int = 1 << 53
const MAX_SAFE_INT: int = JSON_SAFE_BOUND_EXCLUSIVE - 1
# Plan/Receipt v2 require this fixed-point contract; v1 snapshots are rejected
# rather than implicitly migrated because their independent float sums are not
# cross-JSON stable.
const NUMERIC_CONTRACT := "gm.planner.numeric.fixed.v1"
const NUMERIC_SCALE: int = 1000000000000
const NUMERIC_DECIMAL_PLACES: int = 12
const NUMERIC_MAX_UNITS: int = MAX_SAFE_INT
const NUMERIC_ROUNDING_MODE := "round-half-away-from-zero"
const NUMERIC_INPUT_INTERPRETATION := "ieee754.finite.json.shortest-roundtrip-decimal.v1"
const CONTRIBUTIONS := ["source_duty", "urgency", "skill_tags", "preference", "distance", "resource_availability", "fatigue", "risk", "interrupt_cost", "schedule"]

func decide(context: Variant) -> Dictionary:
	var checked := validate_context(context)
	if not checked.ok: return checked
	var ctx: Dictionary = checked.value
	if str(ctx.control_state) == "player_takeover": return _blocked("planner.player_takeover", "玩家正在接管，Planner不生成计划。", ["control_released"])
	if str(ctx.action_state) != "actionable": return _blocked("planner.agent_not_actionable", "角色当前不可行动。", ["agent_actionable"])
	var identity_checked := _preflight_candidate_ids(ctx.candidates)
	if not identity_checked.ok: return identity_checked
	var rows: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	for raw in ctx.candidates:
		var evaluated := _evaluate(raw, ctx)
		if evaluated.ok: rows.append(evaluated.row)
		else: rejected.append(evaluated)
	if rows.is_empty(): return _blocked("planner.no_candidate", "没有可用候选，等待显式上下文事件。", ["task_changed", "schedule_changed", "context_changed"], rejected)
	rows.sort_custom(_before)
	var winner := rows[0].duplicate(true)
	var plan_id := "gm.plan.%s.%d.%s" % [ctx.agent_id, int(ctx.sequence), winner.candidate_id]
	var plan := {"schema":PLAN_SCHEMA,"numeric_contract":NUMERIC_CONTRACT,"plan_id":plan_id,"agent_id":ctx.agent_id,"source_kind":winner.kind,"candidate_id":winner.candidate_id,"task_id":winner.task_id,"assignment_id":winner.assignment_id,"reservation_id":winner.reservation_id,"free_action_id":winner.free_action_id,"ability_id":winner.ability_id,"target_context":winner.target_context.duplicate(true),"schedule_ref":str(ctx.schedule_context.get("schedule_id", "")),"role_ref":str(ctx.role_context.get("role_id", "")),"logical_tick":ctx.logical_tick,"steps":[{"index":0,"kind":"ability_request","ability_id":winner.ability_id}],"reason_chain":winner.breakdown.duplicate(true),"status":"planned"}
	var receipt := {"schema":RECEIPT_SCHEMA,"numeric_contract":NUMERIC_CONTRACT,"receipt_id":"gm.receipt.%s.%d" % [ctx.agent_id, int(ctx.sequence)],"agent_id":ctx.agent_id,"logical_tick":ctx.logical_tick,"seed":ctx.seed,"sequence":ctx.sequence,"selected_candidate_id":winner.candidate_id,"selected_kind":winner.kind,"score":winner.score,"score_units":winner.score_units,"tie_key":winner.tie_key,"ranked":rows.duplicate(true),"rejected":rejected.duplicate(true)}
	return {"ok":true,"plan":plan.duplicate(true),"receipt":receipt.duplicate(true),"selected":winner.duplicate(true)}

func validate_context(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY: return _fail("planner.context_type_invalid", "AgentContext必须是Dictionary。")
	var ctx: Dictionary = value
	var fields := ["schema","agent_id","logical_tick","seed","sequence","control_state","action_state","candidates","schedule_context","role_context","department_context","preference_context","random_offset_scale"]
	if not _exact(ctx, fields): return _fail("planner.context_fields_invalid", "AgentContext字段必须完整且无未知项。")
	if typeof(ctx.schema)!=TYPE_STRING or ctx.schema!=CONTEXT_SCHEMA or typeof(ctx.agent_id)!=TYPE_STRING or not _stable(ctx.agent_id): return _fail("planner.context_identity_invalid", "AgentContext schema或Agent稳定ID的原始Variant无效。")
	for key in ["logical_tick","seed","sequence"]:
		if not _safe_integer(ctx[key]): return _fail("planner.context_integer_invalid", "AgentContext整数必须处于JSON安全范围。", {"field":key})
	if int(ctx.logical_tick)<0 or int(ctx.sequence)<0: return _fail("planner.context_integer_invalid", "逻辑时间和序列不能为负数。")
	if typeof(ctx.control_state)!=TYPE_STRING or str(ctx.control_state) not in ["none","ai","player_takeover"]: return _fail("planner.control_state_invalid", "控制状态无效。")
	if typeof(ctx.action_state)!=TYPE_STRING or str(ctx.action_state) not in ["actionable","inactive","blocked","suspended","invalid_context"]: return _fail("planner.action_state_invalid", "行动状态无效。")
	if typeof(ctx.candidates)!=TYPE_ARRAY: return _fail("planner.candidates_type_invalid", "候选必须是Array。")
	for key in ["schedule_context","role_context","department_context","preference_context"]:
		if typeof(ctx[key])!=TYPE_DICTIONARY: return _fail("planner.context_provider_type_invalid", "上下文Provider输出必须是Dictionary。", {"field":key})
	var bundle:=GMScheduleContextProvider.validate_bundle({"schedule_context":ctx.schedule_context,"role_context":ctx.role_context,"department_context":ctx.department_context,"preference_context":ctx.preference_context},int(ctx.logical_tick))
	if not bundle.ok:return bundle
	if not _finite_number(ctx.random_offset_scale) or float(ctx.random_offset_scale)<0.0 or float(ctx.random_offset_scale)>1.0: return _fail("planner.random_scale_invalid", "随机偏移必须是0到1之间的有限数。")
	return {"ok":true,"value":ctx.duplicate(true)}

func _evaluate(raw: Variant, ctx: Dictionary) -> Dictionary:
	if typeof(raw)!=TYPE_DICTIONARY: return _fail("planner.candidate_type_invalid", "候选必须是Dictionary。")
	var c: Dictionary = raw
	var fields := ["candidate_id","kind","task_id","assignment_id","reservation_id","free_action_id","ability_id","target_context","contributions","hard_priority","available","blocked_reason","retry_triggers"]
	if not _exact(c, fields): return _fail("planner.candidate_fields_invalid", "候选字段必须完整且无未知项。")
	for key in ["candidate_id","kind","task_id","assignment_id","reservation_id","free_action_id","ability_id","blocked_reason"]:
		if typeof(c[key])!=TYPE_STRING: return _fail("planner.candidate_variant_invalid", "候选字符串字段Variant无效。", {"field":key})
	if not _stable(c.candidate_id) or not _stable(c.ability_id): return _fail("planner.candidate_identity_invalid", "候选或Ability稳定ID无效。")
	if c.kind not in ["task","free_action"]: return _fail("planner.candidate_kind_invalid", "候选只能是Task或FreeAction。")
	if c.kind=="task" and (not _stable(c.task_id) or not _stable(c.assignment_id) or not c.free_action_id.is_empty()): return _fail("planner.task_reference_invalid", "Task候选必须只引用有效Task/Assignment且不得含FreeAction ID。")
	if c.kind=="free_action" and (not _stable(c.free_action_id) or not c.task_id.is_empty() or not c.assignment_id.is_empty() or not c.reservation_id.is_empty()): return _fail("planner.free_action_reference_invalid", "FreeAction不得复制Task/Assignment/Reservation。")
	if typeof(c.available)!=TYPE_BOOL or typeof(c.hard_priority)!=TYPE_INT or not _safe_integer(c.hard_priority): return _fail("planner.candidate_variant_invalid", "候选布尔/整数Variant无效。")
	if typeof(c.target_context)!=TYPE_DICTIONARY or typeof(c.contributions)!=TYPE_DICTIONARY or typeof(c.retry_triggers)!=TYPE_ARRAY or not _stable_id_variants(c.target_context): return _fail("planner.candidate_variant_invalid", "候选上下文、评分或RetryTrigger类型无效。")
	var retry_seen:={}
	for trigger in c.retry_triggers:
		if typeof(trigger)!=TYPE_STRING or not _stable(trigger) or retry_seen.has(trigger):return _fail("planner.candidate_retry_invalid","RetryTrigger必须是唯一稳定String。")
		retry_seen[trigger]=true
	if not c.available: return _fail("planner.candidate_unavailable", c.blocked_reason if not c.blocked_reason.is_empty() else "候选不可用。", {"candidate_id":c.candidate_id,"retry_triggers":c.retry_triggers.duplicate()})
	var breakdown: Array[Dictionary] = []
	var score_units: int = 0
	for key in CONTRIBUTIONS:
		if not c.contributions.has(key) or not _finite_number(c.contributions[key]): return _fail("planner.score_non_finite", "评分贡献缺失、Variant错误或包含NaN/INF。", {"candidate_id":c.candidate_id,"field":key})
		var amount_units_result:=_canonical_units(c.contributions[key]);if not amount_units_result.ok:return _fail("planner.score_numeric_invalid", "评分贡献无法表示为固定精度数值。", {"candidate_id":c.candidate_id,"field":key})
		var amount_units:int=amount_units_result.units;var next_sum:=_add_units(score_units,amount_units);if not next_sum.ok:return _fail("planner.score_overflow", "评分贡献总和超出固定数值范围。", {"candidate_id":c.candidate_id,"field":key})
		score_units=next_sum.units;breakdown.append({"kind":key,"amount":_units_to_number(amount_units),"amount_units":amount_units})
	if c.contributions.size()!=CONTRIBUTIONS.size(): return _fail("planner.score_fields_invalid", "评分贡献含未知项或总分非有限。")
	var offset_result:=_stable_offset_units("%d|%s|%d|%s" % [int(ctx.seed),ctx.agent_id,int(ctx.sequence),c.candidate_id],ctx.random_offset_scale);if not offset_result.ok:return _fail("planner.score_numeric_invalid", "显式seed偏移无法表示为固定精度数值。", {"candidate_id":c.candidate_id})
	var with_offset:=_add_units(score_units,offset_result.units);if not with_offset.ok:return _fail("planner.score_overflow", "评分总和超出固定数值范围。", {"candidate_id":c.candidate_id})
	score_units=with_offset.units;breakdown.append({"kind":"explicit_seed_offset","amount":_units_to_number(offset_result.units),"amount_units":offset_result.units})
	return {"ok":true,"row":{"candidate_id":c.candidate_id,"kind":c.kind,"task_id":c.task_id,"assignment_id":c.assignment_id,"reservation_id":c.reservation_id,"free_action_id":c.free_action_id,"ability_id":c.ability_id,"target_context":c.target_context.duplicate(true),"hard_priority":c.hard_priority,"score":_units_to_number(score_units),"score_units":score_units,"tie_key":"%s|%s" % [c.kind,c.candidate_id],"breakdown":breakdown}}

func _before(a: Dictionary, b: Dictionary) -> bool:
	if int(a.hard_priority)!=int(b.hard_priority): return int(a.hard_priority)>int(b.hard_priority)
	# Exact finite IEEE values form a strict total order here.  Approximate
	# equality is intentionally forbidden because it is non-transitive.
	if int(a.score_units)!=int(b.score_units): return int(a.score_units)>int(b.score_units)
	if a.kind!=b.kind: return a.kind=="task"
	return str(a.candidate_id)<str(b.candidate_id)

static func validate_plan(value:Variant,expected_agent_id:String="",json_boundary:bool=false)->Dictionary:
	if typeof(value)!=TYPE_DICTIONARY:return _validation_fail("planner.plan_type_invalid")
	var plan:Dictionary=value
	var fields=["schema","numeric_contract","plan_id","agent_id","source_kind","candidate_id","task_id","assignment_id","reservation_id","free_action_id","ability_id","target_context","schedule_ref","role_ref","logical_tick","steps","reason_chain","status"]
	if not _exact(plan,fields):return _validation_fail("planner.plan_fields_invalid")
	for key in ["schema","numeric_contract","plan_id","agent_id","source_kind","candidate_id","task_id","assignment_id","reservation_id","free_action_id","ability_id","schedule_ref","role_ref","status"]:
		if typeof(plan[key])!=TYPE_STRING:return _validation_fail("planner.plan_variant_invalid",{"field":key})
	if plan.schema!=PLAN_SCHEMA or plan.numeric_contract!=NUMERIC_CONTRACT or not GMTaskDefinition._stable_id(plan.plan_id) or not GMTaskDefinition._stable_id(plan.agent_id) or (not expected_agent_id.is_empty() and plan.agent_id!=expected_agent_id) or not GMTaskDefinition._stable_id(plan.candidate_id) or not GMTaskDefinition._stable_id(plan.ability_id) or not GMTaskDefinition._stable_id(plan.schedule_ref) or not GMTaskDefinition._stable_id(plan.role_ref) or plan.status!="planned":return _validation_fail("planner.plan_identity_invalid")
	if not _integer_contract(plan.logical_tick,json_boundary) or plan.logical_tick<0 or typeof(plan.target_context)!=TYPE_DICTIONARY or not _json_safe_value(plan.target_context):return _validation_fail("planner.plan_variant_invalid")
	if plan.source_kind=="task":
		if not GMTaskDefinition._stable_id(plan.task_id) or not GMTaskDefinition._stable_id(plan.assignment_id) or not plan.free_action_id.is_empty() or (not plan.reservation_id.is_empty() and not GMTaskDefinition._stable_id(plan.reservation_id)):return _validation_fail("planner.plan_task_reference_invalid")
	elif plan.source_kind=="free_action":
		if not GMTaskDefinition._stable_id(plan.free_action_id) or not plan.task_id.is_empty() or not plan.assignment_id.is_empty() or not plan.reservation_id.is_empty():return _validation_fail("planner.plan_free_action_reference_invalid")
	else:return _validation_fail("planner.plan_source_kind_invalid")
	if typeof(plan.steps)!=TYPE_ARRAY or plan.steps.size()!=1 or typeof(plan.steps[0])!=TYPE_DICTIONARY or not _exact(plan.steps[0],["index","kind","ability_id"]) or not _integer_contract(plan.steps[0].index,json_boundary) or plan.steps[0].index!=0 or plan.steps[0].kind!="ability_request" or plan.steps[0].ability_id!=plan.ability_id:return _validation_fail("planner.plan_steps_invalid")
	if typeof(plan.reason_chain)!=TYPE_ARRAY or plan.reason_chain.size()!=CONTRIBUTIONS.size()+1:return _validation_fail("planner.plan_reason_invalid")
	for index in plan.reason_chain.size():
		var reason:Variant=plan.reason_chain[index]
		if typeof(reason)!=TYPE_DICTIONARY or not _exact(reason,["kind","amount","amount_units"]) or typeof(reason.kind)!=TYPE_STRING or reason.kind!=(CONTRIBUTIONS[index] if index<CONTRIBUTIONS.size() else "explicit_seed_offset") or not _numeric_pair_valid(reason.amount,reason.amount_units,json_boundary):return _validation_fail("planner.plan_reason_invalid")
	return {"ok":true,"value":plan.duplicate(true)}

static func validate_receipt(value:Variant,plan:Dictionary,expected_agent_id:String="",json_boundary:bool=false)->Dictionary:
	if typeof(value)!=TYPE_DICTIONARY:return _validation_fail("planner.receipt_type_invalid")
	var receipt:Dictionary=value
	var fields=["schema","numeric_contract","receipt_id","agent_id","logical_tick","seed","sequence","selected_candidate_id","selected_kind","score","score_units","tie_key","ranked","rejected"]
	if not _exact(receipt,fields):return _validation_fail("planner.receipt_fields_invalid")
	for key in ["schema","numeric_contract","receipt_id","agent_id","selected_candidate_id","selected_kind","tie_key"]:
		if typeof(receipt[key])!=TYPE_STRING:return _validation_fail("planner.receipt_variant_invalid",{"field":key})
	if receipt.schema!=RECEIPT_SCHEMA or receipt.numeric_contract!=NUMERIC_CONTRACT or not GMTaskDefinition._stable_id(receipt.receipt_id) or not GMTaskDefinition._stable_id(receipt.agent_id) or (not expected_agent_id.is_empty() and receipt.agent_id!=expected_agent_id) or receipt.agent_id!=plan.agent_id or receipt.selected_candidate_id!=plan.candidate_id or receipt.selected_kind!=plan.source_kind or receipt.logical_tick!=plan.logical_tick:return _validation_fail("planner.receipt_relation_invalid")
	for key in ["logical_tick","seed","sequence"]:
		if not _integer_contract(receipt[key],json_boundary):return _validation_fail("planner.receipt_integer_invalid",{"field":key})
	if receipt.logical_tick<0 or receipt.sequence<0 or not _numeric_pair_valid(receipt.score,receipt.score_units,json_boundary) or typeof(receipt.ranked)!=TYPE_ARRAY or receipt.ranked.is_empty() or typeof(receipt.rejected)!=TYPE_ARRAY:return _validation_fail("planner.receipt_variant_invalid")
	var candidate_ids:={}
	for row in receipt.ranked:
		var checked:=_validate_ranked_row(row,json_boundary);if not checked.ok:return checked
		if candidate_ids.has(row.candidate_id):return _validation_fail("planner.receipt_candidate_duplicate")
		candidate_ids[row.candidate_id]=true
	for index in range(1,receipt.ranked.size()):
		if _ranked_before(receipt.ranked[index],receipt.ranked[index-1]):return _validation_fail("planner.receipt_order_invalid")
	var winner:Dictionary=receipt.ranked[0]
	if winner.candidate_id!=receipt.selected_candidate_id or winner.score_units!=receipt.score_units or receipt.tie_key!=winner.tie_key or receipt.receipt_id!="gm.receipt.%s.%d"%[receipt.agent_id,int(receipt.sequence)] or plan.plan_id!="gm.plan.%s.%d.%s"%[receipt.agent_id,int(receipt.sequence),receipt.selected_candidate_id]:return _validation_fail("planner.receipt_winner_invalid")
	for key in ["candidate_id","kind","task_id","assignment_id","reservation_id","free_action_id","ability_id","target_context"]:
		var plan_key:String="source_kind" if key=="kind" else key
		if plan[plan_key]!=winner[key]:return _validation_fail("planner.plan_receipt_relation_invalid",{"field":key})
	if plan.reason_chain!=winner.breakdown:return _validation_fail("planner.plan_receipt_reason_mismatch")
	for rejected in receipt.rejected:
		if typeof(rejected)!=TYPE_DICTIONARY or not _exact(rejected,["ok","code","reason_zh","error_zh","details","wrote_domain_facts"]) or rejected.ok!=false or typeof(rejected.code)!=TYPE_STRING or typeof(rejected.reason_zh)!=TYPE_STRING or typeof(rejected.error_zh)!=TYPE_STRING or typeof(rejected.details)!=TYPE_DICTIONARY or not _json_safe_value(rejected.details) or typeof(rejected.wrote_domain_facts)!=TYPE_BOOL or rejected.wrote_domain_facts:return _validation_fail("planner.receipt_rejected_invalid")
	return {"ok":true,"value":receipt.duplicate(true)}

static func _validate_ranked_row(value:Variant,json_boundary:bool=false)->Dictionary:
	if typeof(value)!=TYPE_DICTIONARY:return _validation_fail("planner.receipt_ranked_invalid")
	var row:Dictionary=value;var fields=["candidate_id","kind","task_id","assignment_id","reservation_id","free_action_id","ability_id","target_context","hard_priority","score","score_units","tie_key","breakdown"]
	if not _exact(row,fields):return _validation_fail("planner.receipt_ranked_invalid")
	for key in ["candidate_id","kind","task_id","assignment_id","reservation_id","free_action_id","ability_id","tie_key"]:
		if typeof(row[key])!=TYPE_STRING:return _validation_fail("planner.receipt_ranked_invalid")
	if not GMTaskDefinition._stable_id(row.candidate_id) or row.kind not in ["task","free_action"] or not GMTaskDefinition._stable_id(row.ability_id) or typeof(row.target_context)!=TYPE_DICTIONARY or not _json_safe_value(row.target_context) or not _integer_contract(row.hard_priority,json_boundary) or not _numeric_pair_valid(row.score,row.score_units,json_boundary) or typeof(row.breakdown)!=TYPE_ARRAY or row.tie_key!="%s|%s"%[row.kind,row.candidate_id]:return _validation_fail("planner.receipt_ranked_invalid")
	if row.kind=="task" and (not GMTaskDefinition._stable_id(str(row.task_id)) or not GMTaskDefinition._stable_id(str(row.assignment_id)) or not str(row.free_action_id).is_empty()):return _validation_fail("planner.receipt_ranked_invalid")
	if row.kind=="free_action" and (not GMTaskDefinition._stable_id(str(row.free_action_id)) or not str(row.task_id).is_empty() or not str(row.assignment_id).is_empty() or not str(row.reservation_id).is_empty()):return _validation_fail("planner.receipt_ranked_invalid")
	if row.breakdown.size()!=CONTRIBUTIONS.size()+1:return _validation_fail("planner.receipt_ranked_invalid")
	var score_total_units:int=0
	for index in row.breakdown.size():
		var contribution:Variant=row.breakdown[index]
		if typeof(contribution)!=TYPE_DICTIONARY or not _exact(contribution,["kind","amount","amount_units"]) or typeof(contribution.kind)!=TYPE_STRING or contribution.kind!=(CONTRIBUTIONS[index] if index<CONTRIBUTIONS.size() else "explicit_seed_offset") or not _numeric_pair_valid(contribution.amount,contribution.amount_units,json_boundary):return _validation_fail("planner.receipt_ranked_invalid")
		var stored_units:=_stored_units(contribution.amount_units,json_boundary);if not stored_units.ok:return _validation_fail("planner.receipt_ranked_invalid")
		var next_units:=_add_units(score_total_units,stored_units.units);if not next_units.ok:return _validation_fail("planner.receipt_score_breakdown_mismatch")
		score_total_units=next_units.units
	if int(row.score_units)!=score_total_units:return _validation_fail("planner.receipt_score_breakdown_mismatch")
	return {"ok":true}

static func _ranked_before(a:Dictionary,b:Dictionary)->bool:
	if int(a.hard_priority)!=int(b.hard_priority):return int(a.hard_priority)>int(b.hard_priority)
	if int(a.score_units)!=int(b.score_units):return int(a.score_units)>int(b.score_units)
	if a.kind!=b.kind:return a.kind=="task"
	return a.candidate_id<b.candidate_id

static func _validation_fail(code:String,details:Dictionary={})->Dictionary:return {"ok":false,"code":code,"reason_zh":"Planner嵌套合同无效，写入前拒绝。","details":details,"wrote_domain_facts":false}

static func _canonical_units(value:Variant)->Dictionary:
	if typeof(value)==TYPE_INT:
		if value>NUMERIC_MAX_UNITS/NUMERIC_SCALE or value<-(NUMERIC_MAX_UNITS/NUMERIC_SCALE):return {"ok":false}
		return {"ok":true,"units":int(value)*NUMERIC_SCALE}
	if typeof(value)!=TYPE_FLOAT or not is_finite(value):return {"ok":false}
	if abs(value)>float(NUMERIC_MAX_UNITS)/float(NUMERIC_SCALE)+1.0:return {"ok":false}
	# Normative float interpretation: JSON.stringify emits Godot's shortest
	# round-trip decimal token for this finite IEEE-754 value.  We parse that
	# token as an exact decimal rational, then apply our own integer
	# round-half-away-from-zero at NUMERIC_SCALE.  The formatter only supplies
	# digits; no formatter tie rule is used for the contract decision.
	var text:String=JSON.stringify(value)
	if text.is_empty() or text=="null":return {"ok":false}
	var negative:bool=text.begins_with("-")
	if negative:text=text.substr(1)
	var exponent:int=0
	var exponent_index:int=text.find("e")
	if exponent_index<0:exponent_index=text.find("E")
	if exponent_index>=0:
		var exponent_text:String=text.substr(exponent_index+1)
		if exponent_text.is_empty():return {"ok":false}
		exponent=int(exponent_text);text=text.substr(0,exponent_index)
	var dot:int=text.find(".")
	var fraction_digits:int=0
	if dot>=0:
		fraction_digits=text.length()-dot-1
		text=text.substr(0,dot)+text.substr(dot+1)
	if text.is_empty():return {"ok":false}
	var magnitude:int=0
	for character in text:
		var digit:int=character.unicode_at(0)-48
		if digit<0 or digit>9:return {"ok":false}
		if magnitude>922337203685477580 or magnitude*10>9223372036854775807-digit:return {"ok":false}
		magnitude=magnitude*10+digit
	var unit_shift:int=exponent-fraction_digits+NUMERIC_DECIMAL_PLACES
	var rounded:=_round_decimal_units(magnitude,unit_shift)
	if not rounded.ok:return rounded
	var units:int=int(rounded.units)
	if negative:units=-units
	if units>NUMERIC_MAX_UNITS or units<-NUMERIC_MAX_UNITS:return {"ok":false}
	return {"ok":true,"units":units}

static func _round_decimal_units(magnitude:int,unit_shift:int)->Dictionary:
	if magnitude==0:return {"ok":true,"units":0}
	if unit_shift>=0:
		# A finite planner value within the public range never needs an
		# unbounded positive shift.  Guard the multiplication before it can
		# leave the signed 64-bit/JSON-safe contract.
		if unit_shift>18:return {"ok":false}
		var multiplier:int=1
		for _index in unit_shift:multiplier*=10
		if magnitude>NUMERIC_MAX_UNITS/multiplier:return {"ok":false}
		return {"ok":true,"units":magnitude*multiplier}
	var dropped:int=-unit_shift
	# JSON's finite decimal token has at most a small significand.  Once
	# more than 18 decimal places are dropped, its magnitude is strictly
	# below half a unit and rounds to zero without an approximation.
	if dropped>18:return {"ok":true,"units":0}
	var divisor:int=1
	for _index in dropped:divisor*=10
	var quotient:int=_trunc_divide(magnitude,divisor)
	var remainder:int=magnitude-quotient*divisor
	# Exact tie rule: |remainder|/divisor >= 1/2 increments magnitude.
	if remainder*2>=divisor:quotient+=1
	return {"ok":true,"units":quotient}

static func _trunc_divide(numerator:int,divisor:int)->int:
	if divisor<=0:return 0
	var negative:bool=numerator<0
	var remaining:int=-numerator if negative else numerator
	var denominator:int=divisor
	var factor:int=1
	# Build the largest doubled divisor that is still <= numerator.  The
	# subtraction comparison avoids a floating division and all intermediates
	# stay below the signed 64-bit input bound.
	while denominator<=remaining-denominator:
		denominator<<=1
		factor<<=1
	var quotient:int=0
	while factor>0:
		if denominator<=remaining:
			remaining-=denominator
			quotient+=factor
		denominator>>=1
		factor>>=1
	return -quotient if negative else quotient

static func _stored_units(value:Variant,json_boundary:bool)->Dictionary:
	if json_boundary:
		if typeof(value)!=TYPE_FLOAT or not _safe_integer(value):return {"ok":false}
		return {"ok":true,"units":int(value)}
	if typeof(value)!=TYPE_INT or value>NUMERIC_MAX_UNITS or value<-NUMERIC_MAX_UNITS:return {"ok":false}
	return {"ok":true,"units":int(value)}

static func _numeric_pair_valid(number:Variant,units:Variant,json_boundary:bool)->bool:
	var canonical:=_canonical_units(number);if not canonical.ok:return false
	var stored:=_stored_units(units,json_boundary);if not stored.ok or int(canonical.units)!=int(stored.units):return false
	# The display number itself is canonical, not merely quantized. This closes
	# sub-unit tamper gaps: a value that rounds to the same unit but is not the
	# exact canonical float is rejected before restore.
	return typeof(number)!=TYPE_FLOAT or float(number)==_units_to_number(int(canonical.units))

static func _units_to_number(units:int)->float:return float(units)/float(NUMERIC_SCALE)

static func _add_units(left:int,right:int)->Dictionary:
	if right>0 and left>NUMERIC_MAX_UNITS-right:return {"ok":false}
	if right<0 and left<-NUMERIC_MAX_UNITS-right:return {"ok":false}
	return {"ok":true,"units":left+right}

static func _stable_offset_units(text:String,scale_value:Variant)->Dictionary:
	var scale:=_canonical_units(scale_value)
	if not scale.ok or scale.units<0 or scale.units>NUMERIC_SCALE:return {"ok":false}
	var acc:int=17
	for i in text.length():acc=(acc*131+text.unicode_at(i))%1000003
	var base_micro:int=(acc%2001)-1000
	var numerator:int=base_micro*int(scale.units)
	var quotient:int=_trunc_divide(numerator,1000000)
	var remainder:int=numerator-quotient*1000000
	if abs(remainder)*2>=1000000:quotient+=1 if numerator>=0 else -1
	return {"ok":true,"units":quotient}

func _blocked(code:String, reason:String, triggers:Array, rejected:Array=[]) -> Dictionary:
	return {"ok":false,"code":code,"reason_zh":reason,"blocked_reason":{"code":code,"reason_zh":reason},"retry_triggers":triggers.duplicate(),"rejected":rejected.duplicate(true),"wrote_domain_facts":false}

static func _fail(code:String, reason:String, details:Dictionary={}) -> Dictionary:
	return {"ok":false,"code":code,"reason_zh":reason,"error_zh":reason,"details":details,"wrote_domain_facts":false}

static func _finite_number(value:Variant)->bool: return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))
static func _preflight_candidate_ids(value:Variant)->Dictionary:
	if typeof(value)!=TYPE_ARRAY: return _fail("planner.candidates_type_invalid", "候选必须是Array。")
	# Normative order is collection-wide: reject any malformed identity before
	# considering duplicate identities, so permutations cannot change the error
	# category. Only after every raw identity is a stable non-empty String do we
	# canonicalize duplicate reporting by lexicographic ID order.
	for raw in value:
		if typeof(raw)!=TYPE_DICTIONARY or not raw.has("candidate_id") or typeof(raw["candidate_id"])!=TYPE_STRING or not _stable(raw["candidate_id"]):
			return _fail("planner.candidate_identity_invalid", "候选集合的candidate_id必须是原始、非空且稳定的String。")
	var counts:Dictionary={}
	for raw in value:
		var candidate_id:String=raw["candidate_id"]
		counts[candidate_id]=int(counts.get(candidate_id,0))+1
	var duplicates:Array[String]=[]
	for candidate_id in counts:
		if int(counts[candidate_id])>1: duplicates.append(candidate_id)
	if duplicates.is_empty(): return {"ok":true}
	duplicates.sort()
	return _fail("planner.candidate_id_duplicate", "候选集合的candidate_id必须唯一，重复身份在写入前被拒绝。", {"candidate_id":duplicates[0],"duplicate_count":int(counts[duplicates[0]])})
static func _safe_integer(value:Variant)->bool:
	if typeof(value)==TYPE_INT:return value>=-MAX_SAFE_INT and value<=MAX_SAFE_INT
	return typeof(value)==TYPE_FLOAT and is_finite(value) and value==floor(value) and value>-float(JSON_SAFE_BOUND_EXCLUSIVE) and value<float(JSON_SAFE_BOUND_EXCLUSIVE)
static func _integer_contract(value:Variant,json_boundary:bool)->bool:
	if json_boundary:return typeof(value)==TYPE_FLOAT and _safe_integer(value)
	return typeof(value)==TYPE_INT and value>=-MAX_SAFE_INT and value<=MAX_SAFE_INT
static func _json_safe_value(value:Variant,depth:int=0)->bool:
	if depth>16:return false
	match typeof(value):
		TYPE_NIL,TYPE_BOOL,TYPE_STRING:return true
		TYPE_INT:return value>=-MAX_SAFE_INT and value<=MAX_SAFE_INT
		TYPE_FLOAT:
			if not is_finite(value):return false
			return value!=floor(value) or value>-float(JSON_SAFE_BOUND_EXCLUSIVE) and value<float(JSON_SAFE_BOUND_EXCLUSIVE)
		TYPE_ARRAY:
			for item in value:
				if not _json_safe_value(item,depth+1):return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key)!=TYPE_STRING or not _json_safe_value(value[key],depth+1):return false
			return true
		_:return false
static func _stable_id_variants(value:Variant,depth:int=0)->bool:
	if depth>16:return false
	if typeof(value)==TYPE_ARRAY:
		for item in value:
			if not _stable_id_variants(item,depth+1):return false
		return true
	if typeof(value)!=TYPE_DICTIONARY:return _json_safe_value(value,depth)
	for key in value:
		if typeof(key)!=TYPE_STRING:return false
		var item:Variant=value[key]
		if key.ends_with("_id") and (typeof(item)!=TYPE_STRING or not _stable(item)):return false
		if key.ends_with("_ids"):
			if typeof(item)!=TYPE_ARRAY:return false
			var seen:={}
			for stable_id in item:
				if typeof(stable_id)!=TYPE_STRING or not _stable(stable_id) or seen.has(stable_id):return false
				seen[stable_id]=true
		elif not _stable_id_variants(item,depth+1):return false
	return true
static func _stable(value:String)->bool: return GMTaskDefinition._stable_id(value)
static func _exact(value:Dictionary, fields:Array)->bool:
	if value.size()!=fields.size(): return false
	for field in fields:
		if not value.has(field): return false
	return true
