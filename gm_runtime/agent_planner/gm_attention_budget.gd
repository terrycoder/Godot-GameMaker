class_name GMAttentionBudget
extends RefCounted

const SCHEMA := "gm.attention.projection.v1"
const ROW_FIELDS := ["attention_id","source_kind","source_id","initiator_id","target_id","consequence_zh","interruptible","reason_zh","salience"]
const PROJECTION_FIELDS := ["ok","schema","capacity","selected","candidate_count","planner_decision_affected","wrote_domain_facts"]

func project(candidates:Variant, capacity:Variant) -> Dictionary:
	if typeof(candidates)!=TYPE_ARRAY or candidates.size()>64 or typeof(capacity)!=TYPE_INT or capacity<0 or capacity>64:return _fail("attention.input_invalid","Attention候选必须是最多64项的Array，预算必须为原生0—64整数。")
	var rows:Array[Dictionary]=[];var identities:={}
	for raw in candidates:
		var checked:=validate_row(raw)
		if not checked.ok:return checked
		var row:Dictionary=checked.value
		if identities.has(row.attention_id):return _fail("attention.identity_duplicate","Attention ID必须唯一。")
		identities[row.attention_id]=true;rows.append(row)
	rows.sort_custom(_before)
	return {"ok":true,"schema":SCHEMA,"capacity":capacity,"selected":rows.slice(0,min(capacity,rows.size())).duplicate(true),"candidate_count":rows.size(),"planner_decision_affected":false,"wrote_domain_facts":false}

static func validate_projection(value:Variant,json_boundary:bool=false)->Dictionary:
	if typeof(value)!=TYPE_DICTIONARY:return _fail("attention.projection_type_invalid","Attention投影必须是Dictionary。")
	var projection:Dictionary=value
	if not _exact(projection,PROJECTION_FIELDS) or typeof(projection.ok)!=TYPE_BOOL or not projection.ok or typeof(projection.schema)!=TYPE_STRING or projection.schema!=SCHEMA or not _bounded_integer(projection.capacity,json_boundary) or projection.capacity<0 or projection.capacity>64 or not _bounded_integer(projection.candidate_count,json_boundary) or projection.candidate_count<0 or projection.candidate_count>64 or typeof(projection.selected)!=TYPE_ARRAY or projection.selected.size()>projection.capacity or projection.selected.size()>projection.candidate_count or typeof(projection.planner_decision_affected)!=TYPE_BOOL or projection.planner_decision_affected or typeof(projection.wrote_domain_facts)!=TYPE_BOOL or projection.wrote_domain_facts:return _fail("attention.projection_invalid","Attention投影schema、字段、整数边界、预算或只读标志无效。")
	var seen:={};var previous:Dictionary={}
	for raw in projection.selected:
		var checked:=validate_row(raw);if not checked.ok:return checked
		var row:Dictionary=checked.value
		if seen.has(row.attention_id):return _fail("attention.identity_duplicate","Attention投影含重复ID。")
		if not previous.is_empty() and _before(row,previous):return _fail("attention.order_invalid","Attention投影不是规范全序。")
		seen[row.attention_id]=true;previous=row
	return {"ok":true,"value":projection.duplicate(true)}

static func validate_row(value:Variant)->Dictionary:
	if typeof(value)!=TYPE_DICTIONARY:return _fail("attention.candidate_type_invalid","Attention候选类型无效。")
	var row:Dictionary=value
	if not _exact(row,ROW_FIELDS):return _fail("attention.fields_invalid","Attention候选字段集合必须精确匹配当前schema。")
	for key in ["attention_id","source_kind","source_id","initiator_id","target_id","consequence_zh","reason_zh"]:
		if typeof(row[key])!=TYPE_STRING:return _fail("attention.variant_invalid","Attention字符串字段Variant无效。")
	if not GMTaskDefinition._stable_id(row.attention_id) or row.source_kind not in ["task","plan","fact"] or not GMTaskDefinition._stable_id(row.source_id) or not GMTaskDefinition._stable_id(row.initiator_id) or not GMTaskDefinition._stable_id(row.target_id) or row.consequence_zh.strip_edges().is_empty() or row.reason_zh.strip_edges().is_empty() or typeof(row.interruptible)!=TYPE_BOOL or typeof(row.salience) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(row.salience)):return _fail("attention.reference_invalid","Attention必须使用唯一稳定身份、真实引用、布尔中断标志及有限显著度。")
	return {"ok":true,"value":row.duplicate(true)}

static func _before(a:Dictionary,b:Dictionary)->bool:
	if float(a.salience)!=float(b.salience):return float(a.salience)>float(b.salience)
	for key in ["attention_id","source_kind","source_id","initiator_id","target_id","consequence_zh","reason_zh"]:
		if str(a[key])!=str(b[key]):return str(a[key])<str(b[key])
	return int(a.interruptible)<int(b.interruptible)

static func _exact(value:Dictionary,fields:Array)->bool:
	if value.size()!=fields.size():return false
	for field in fields:
		if not value.has(field):return false
	return true

static func _bounded_integer(value:Variant,json_boundary:bool)->bool:
	if json_boundary:return typeof(value)==TYPE_FLOAT and is_finite(value) and value==floor(value) and abs(value)<GMAgentPlanner.MAX_SAFE_INT
	return typeof(value)==TYPE_INT

static func _fail(code:String,reason:String)->Dictionary:return {"ok":false,"code":code,"reason_zh":reason,"wrote_domain_facts":false}
