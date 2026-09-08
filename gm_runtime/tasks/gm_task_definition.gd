@tool
class_name GMTaskDefinition
extends Resource

const SCHEMA_VERSION := "gm.task.definition.v2"
const LEGACY_SCHEMA_VERSION := "gm.task.definition.v1"

@export var definition_id: String = "gm.task.definition.sample_transport"
@export var display_name_zh: String = "搬运三份样板资源"
@export_multiline var description_zh: String = "通过统一能力请求搬运样板资源，并由已提交事实推进目标。"
@export var objectives: Array[Dictionary] = [{"objective_id":"gm.objective.sample_transport","display_name_zh":"搬运三份样板资源","signal_kind":"fact","signal_type":"gm.fact.inventory.transferred","target_value":3,"contribution_field":"amount","target_match":{"resource_id":"gm.sample.resource.neutral"}}]
@export var allowed_source_types: Array[String] = ["player", "ai", "organization", "world_event", "script", "duty_provider"]
@export_enum("本地执行:local", "摘要执行:summary", "场景上下文声明:scene") var default_context_mode: String = "local"
@export var reservation_rules: Array[Dictionary] = [{"rule_id":"gm.reservation_rule.sample_resource","subject":{"type":"resource","id":"gm.resource.shared"},"mode":"exclusive","capacity":1},{"rule_id":"gm.reservation_rule.sample_capacity","subject":{"type":"resource","id":"gm.resource.capacity_pool"},"mode":"capacity","capacity":10}]
@export var workbench_profile: Dictionary = {
	"source_type":"player",
	"task_id":"gm.task.sample.workbench",
	"parent_task_id":"",
	"assignment_id":"gm.assignment.sample.workbench",
	"assignment_kind":"actor",
	"assignee":{"type":"actor","id":"gm.actor.sample"},
	"provider":{"provider_id":"gm.duty.sample_workbench","event_type":"gm.fact.duty.condition","key_field":"duty_key","subject":{"type":"resource","id":"gm.resource.sample_duty"}},
	"reservation":{"reservation_id":"gm.reservation.sample_workbench","rule_id":"gm.reservation_rule.sample_resource","amount":1,"expires_at_tick":10}
}

func validate_definition() -> Dictionary:
	var errors: Array[String] = []
	if not _stable_id(definition_id): errors.append("definition_id 必须是稳定英文ID。")
	if display_name_zh.strip_edges().is_empty(): errors.append("中文显示名不能为空。")
	if description_zh.strip_edges().is_empty(): errors.append("中文说明不能为空。")
	if objectives.is_empty(): errors.append("至少需要一个Objective。")
	if default_context_mode not in ["local", "summary", "scene"]: errors.append("执行上下文模式无效。")
	var seen: Dictionary = {}
	for index in objectives.size():
		var objective: Variant = objectives[index]
		if not objective is Dictionary:
			errors.append("Objective[%d] 必须是Dictionary。" % index)
			continue
		var row: Dictionary = objective
		var exact := _exact(row, ["objective_id", "display_name_zh", "signal_kind", "signal_type", "target_value", "contribution_field", "target_match"])
		if not exact.ok: errors.append("Objective[%d] 字段必须完整且无附加项。" % index)
		var objective_id := str(row.get("objective_id", ""))
		if not _stable_id(objective_id): errors.append("Objective[%d] 的ID无效。" % index)
		elif seen.has(objective_id): errors.append("Objective ID重复：%s" % objective_id)
		seen[objective_id] = true
		if typeof(row.get("display_name_zh")) != TYPE_STRING or str(row.get("display_name_zh", "")).strip_edges().is_empty(): errors.append("Objective[%d] 缺少中文显示名。" % index)
		var signal_kind := str(row.get("signal_kind", ""))
		var signal_type := str(row.get("signal_type", ""))
		if typeof(row.get("signal_kind")) != TYPE_STRING or signal_kind not in ["fact", "change", "cue"]: errors.append("Objective[%d] signal_kind无效。" % index)
		if typeof(row.get("signal_type")) != TYPE_STRING or not _stable_id(signal_type) or not signal_type.begins_with("gm.%s." % signal_kind): errors.append("Objective[%d] signal_type必须与signal_kind一致。" % index)
		if typeof(row.get("target_value")) != TYPE_INT or int(row.get("target_value", 0)) <= 0: errors.append("Objective[%d] target_value必须是正整数。" % index)
		if typeof(row.get("contribution_field")) != TYPE_STRING or str(row.get("contribution_field", "")).strip_edges().is_empty(): errors.append("Objective[%d] contribution_field无效。" % index)
		if not row.get("target_match", null) is Dictionary: errors.append("Objective[%d] target_match必须是Dictionary。" % index)
	for source_type in allowed_source_types:
		if source_type not in ["player", "ai", "organization", "world_event", "script", "duty_provider"]: errors.append("Source类型无效：%s" % source_type)
	if allowed_source_types.is_empty() or _duplicates(allowed_source_types): errors.append("Source白名单不能为空或包含重复项。")
	var rule_ids: Dictionary = {}
	var subjects: Dictionary = {}
	for index in reservation_rules.size():
		var rule: Variant = reservation_rules[index]
		if not rule is Dictionary:
			errors.append("Reservation规则[%d]必须是Dictionary。" % index)
			continue
		var row: Dictionary = rule
		if not _exact(row,["rule_id","subject","mode","capacity"]).ok: errors.append("Reservation规则[%d]字段必须完整且无附加项。" % index)
		var rule_id := str(row.get("rule_id",""))
		if not _stable_id(rule_id) or rule_ids.has(rule_id): errors.append("Reservation规则[%d]的规则ID无效或重复。" % index)
		rule_ids[rule_id] = true
		if not _typed_ref(row.get("subject",{})): errors.append("Reservation规则[%d]的subject必须是稳定类型+ID。" % index)
		var subject_key := JSON.stringify(row.get("subject",{}),"",true,true)
		if subjects.has(subject_key): errors.append("同一Task定义不得重复声明Reservation subject。")
		subjects[subject_key] = true
		var mode := str(row.get("mode",""))
		if mode not in ["exclusive","capacity"]: errors.append("Reservation规则[%d]模式无效。" % index)
		if typeof(row.get("capacity")) != TYPE_INT or int(row.get("capacity",0)) <= 0: errors.append("Reservation规则[%d]容量必须是正整数。" % index)
		if mode == "exclusive" and int(row.get("capacity",0)) != 1: errors.append("独占Reservation规则容量必须为1。")
	_validate_workbench_profile(workbench_profile,rule_ids,errors)
	return {"ok": errors.is_empty(), "code": "task.definition.valid" if errors.is_empty() else "task.definition.invalid", "reason_zh": "Task定义有效。" if errors.is_empty() else "Task定义校验失败，请修正字段。", "errors": errors}

func to_dict() -> Dictionary:
	return {"schema_version":SCHEMA_VERSION,"definition_id":definition_id,"display_name_zh":display_name_zh,"description_zh":description_zh,"objectives":objectives.duplicate(true),"allowed_source_types":allowed_source_types.duplicate(),"default_context_mode":default_context_mode,"reservation_rules":reservation_rules.duplicate(true),"workbench_profile":workbench_profile.duplicate(true)}

func apply_dict(value: Dictionary) -> Dictionary:
	var exact := _exact(value, ["schema_version","definition_id","display_name_zh","description_zh","objectives","allowed_source_types","default_context_mode","reservation_rules","workbench_profile"])
	if typeof(value.get("schema_version")) == TYPE_STRING and value.get("schema_version") == LEGACY_SCHEMA_VERSION: return {"ok":false,"code":"task.definition.legacy_schema_rejected","reason_zh":"v1 Objective仅表达Fact，不能无歧义迁移为Fact/Change/Cue；请显式重存为v2。"}
	if not exact.ok or typeof(value.get("schema_version")) != TYPE_STRING or value.get("schema_version") != SCHEMA_VERSION: return {"ok":false,"code":"task.definition.schema_invalid","reason_zh":"Task定义Schema或字段集合无效。"}
	if typeof(value.get("definition_id")) != TYPE_STRING or typeof(value.get("display_name_zh")) != TYPE_STRING or typeof(value.get("description_zh")) != TYPE_STRING or not value.get("objectives") is Array or not value.get("allowed_source_types") is Array or typeof(value.get("default_context_mode")) != TYPE_STRING or not value.get("reservation_rules") is Array or not value.get("workbench_profile") is Dictionary: return {"ok":false,"code":"task.definition.type_invalid","reason_zh":"Task定义字段类型无效。"}
	for item in value.objectives:
		if not item is Dictionary: return {"ok":false,"code":"task.definition.type_invalid","reason_zh":"Objective行类型无效。"}
	for item in value.allowed_source_types:
		if typeof(item) != TYPE_STRING: return {"ok":false,"code":"task.definition.type_invalid","reason_zh":"Source白名单行类型无效。"}
	for item in value.reservation_rules:
		if not item is Dictionary: return {"ok":false,"code":"task.definition.type_invalid","reason_zh":"Reservation规则行类型无效。"}
	var before := to_dict()
	definition_id=value.definition_id; display_name_zh=value.display_name_zh; description_zh=value.description_zh; objectives=[]
	for item in value.objectives: objectives.append((item as Dictionary).duplicate(true))
	allowed_source_types=[]
	for item in value.allowed_source_types: allowed_source_types.append(str(item))
	default_context_mode=value.default_context_mode; reservation_rules=[]
	for item in value.reservation_rules: reservation_rules.append((item as Dictionary).duplicate(true))
	workbench_profile=value.workbench_profile.duplicate(true)
	var checked := validate_definition()
	if not checked.ok:
		_apply_unchecked(before)
		return checked
	return {"ok":true,"code":"task.definition.applied"}

func _apply_unchecked(value: Dictionary) -> void:
	definition_id=value.definition_id; display_name_zh=value.display_name_zh; description_zh=value.description_zh; objectives=[]
	for item in value.objectives: objectives.append((item as Dictionary).duplicate(true))
	allowed_source_types=[]
	for item in value.allowed_source_types: allowed_source_types.append(str(item))
	default_context_mode=value.default_context_mode; reservation_rules=[]
	for item in value.reservation_rules: reservation_rules.append((item as Dictionary).duplicate(true))
	workbench_profile=value.workbench_profile.duplicate(true)

static func _validate_workbench_profile(value: Variant, rule_ids: Dictionary, errors: Array[String]) -> void:
	if not value is Dictionary or not _exact(value,["source_type","task_id","parent_task_id","assignment_id","assignment_kind","assignee","provider","reservation"]).ok:
		errors.append("工作台配置字段必须完整且无附加项。")
		return
	if typeof(value.source_type)!=TYPE_STRING or value.source_type not in ["player","ai","organization","world_event","script","duty_provider"]: errors.append("工作台发布来源无效。")
	for field in ["task_id","assignment_id"]:
		if typeof(value[field])!=TYPE_STRING or not _stable_id(str(value[field])): errors.append("工作台%s必须是稳定ID。"%field)
	if typeof(value.parent_task_id)!=TYPE_STRING or (not str(value.parent_task_id).is_empty() and not _stable_id(str(value.parent_task_id))): errors.append("工作台父Task ID无效。")
	if typeof(value.assignment_kind)!=TYPE_STRING or value.assignment_kind not in ["actor","group","role","department"]: errors.append("工作台Assignment类型无效。")
	if not _typed_ref(value.assignee): errors.append("工作台受派对象必须是稳定类型+ID。")
	if not value.provider is Dictionary or not _exact(value.provider,["provider_id","event_type","key_field","subject"]).ok: errors.append("工作台DutyProvider配置字段无效。")
	else:
		if not _stable_id(str(value.provider.provider_id)) or typeof(value.provider.event_type)!=TYPE_STRING or not str(value.provider.event_type).begins_with("gm.fact.") or typeof(value.provider.key_field)!=TYPE_STRING or not _stable_id(str(value.provider.key_field)) or not _typed_ref(value.provider.subject): errors.append("工作台DutyProvider稳定值无效。")
	if not value.reservation is Dictionary or not _exact(value.reservation,["reservation_id","rule_id","amount","expires_at_tick"]).ok: errors.append("工作台Reservation配置字段无效。")
	else:
		if not _stable_id(str(value.reservation.reservation_id)) or not rule_ids.has(str(value.reservation.rule_id)) or typeof(value.reservation.amount)!=TYPE_INT or int(value.reservation.amount)<=0 or typeof(value.reservation.expires_at_tick)!=TYPE_INT or int(value.reservation.expires_at_tick)<0: errors.append("工作台Reservation稳定值无效。")

static func _typed_ref(value: Variant) -> bool:
	return value is Dictionary and value.size()==2 and typeof(value.get("type"))==TYPE_STRING and typeof(value.get("id"))==TYPE_STRING and _stable_id(str(value.type)) and _stable_id(str(value.id)) and not str(value.type).contains("node")

static func _duplicates(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if seen.has(value): return true
		seen[value]=true
	return false

static func _stable_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges() or value.length() > 160: return false
	for i in value.length():
		var code := value.unicode_at(i)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code in [46, 95, 45]): return false
	return true

static func _exact(value: Dictionary, fields: Array) -> Dictionary:
	if value.size() != fields.size(): return {"ok":false}
	for field in fields:
		if not value.has(field): return {"ok":false}
	return {"ok":true}
