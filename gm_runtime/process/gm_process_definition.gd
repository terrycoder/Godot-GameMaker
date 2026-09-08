@tool
class_name GMProcessDefinition
extends Resource

## One neutral, versioned Process recipe. Domain-specific meaning lives in the
## payload and downstream resolver, never in the kernel's control flow.

const SCHEMA_VERSION := 1
const COMPLETION_KINDS := ["none", "p19_transaction", "typed_domain_request"]

@export var definition_id: String = ""
@export var revision: int = 1
@export var display_name_zh: String = "持续过程"
@export var process_family: String = "generic"
@export var duration_units: int = 1
@export var capability_ids: PackedStringArray = []
@export var facility_target: Variant = {}
@export var completion_kind: String = "none"
@export var completion_payload: Dictionary = {}
@export var task_definition_id: String = ""
@export var duty_provider_id: String = ""

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not _stable_identity(definition_id): errors.append("ProcessDefinition ID 必须是稳定业务身份。")
	if revision <= 0 or revision > GMStableData.JSON_SAFE_INTEGER_MAX: errors.append("ProcessDefinition revision 必须为JSON安全范围内的正整数。")
	if display_name_zh.strip_edges().is_empty(): errors.append("中文显示名不能为空。")
	if not _stable_id(process_family): errors.append("process_family 只能是稳定数据标签。")
	if duration_units <= 0 or duration_units > GMStableData.JSON_SAFE_INTEGER_MAX: errors.append("持续单位必须为JSON安全范围内的正整数。")
	if not COMPLETION_KINDS.has(completion_kind): errors.append("completion_kind 不受支持。")
	var seen_capabilities: Dictionary = {}
	for capability_id in capability_ids:
		if not _stable_id(capability_id): errors.append("Capability ID 无效：%s" % capability_id)
		elif seen_capabilities.has(str(capability_id)): errors.append("Capability ID 重复：%s" % capability_id)
		else: seen_capabilities[str(capability_id)] = true
	for optional_id in [task_definition_id, duty_provider_id]:
		if not optional_id.is_empty() and not _stable_id(optional_id): errors.append("关联 ID 无效：%s" % optional_id)
	var facility_check := _validate_facility_target(facility_target)
	if not facility_check.ok: errors.append(str(facility_check.reason_zh))
	if not completion_payload is Dictionary: errors.append("完成请求必须是Dictionary纯数据。")
	else:
		var stable := GMStableData.validate_persistence(completion_payload)
		if not stable.ok: errors.append("完成请求必须是纯数据。")
		if completion_kind == "typed_domain_request":
			var request_type := str(completion_payload.get("request_type", ""))
			if not _stable_id(request_type): errors.append("typed_domain_request 必须声明稳定 request_type。")
		if completion_kind == "p19_transaction":
			var operation := str(completion_payload.get("p19_operation", completion_payload.get("inventory_operation", completion_payload.get("numeric_operation", ""))))
			if not _stable_id(operation): errors.append("P19 完成适配器必须声明稳定事务操作。")
	return {"ok": errors.is_empty(), "errors": errors}

func to_native() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"definition_id": definition_id,
		"revision": revision,
		"display_name_zh": display_name_zh,
		"process_family": process_family,
		"duration_units": duration_units,
		"capability_ids": Array(capability_ids),
		"facility_target": GMStableData.clone(facility_target),
		"completion_kind": completion_kind,
		"completion_payload": completion_payload.duplicate(true),
		"task_definition_id": task_definition_id,
		"duty_provider_id": duty_provider_id,
	}

func to_json() -> String:
	return JSON.stringify(to_native())

static func from_native(value: Variant, json_boundary: bool = false) -> Dictionary:
	var fields := ["schema_version", "definition_id", "revision", "display_name_zh", "process_family", "duration_units", "capability_ids", "facility_target", "completion_kind", "completion_payload", "task_definition_id", "duty_provider_id"]
	if not value is Dictionary or value.size() != fields.size(): return _failure("process.definition_shape_invalid", "ProcessDefinition 字段缺失或附加。")
	for field in fields:
		if not value.has(field): return _failure("process.definition_shape_invalid", "ProcessDefinition 缺少字段：%s" % field)
	if not _integer(value.schema_version, json_boundary) or int(value.schema_version) != SCHEMA_VERSION: return _failure("process.definition_version_invalid", "ProcessDefinition 版本不受支持。")
	if not _integer(value.revision, json_boundary) or not _integer(value.duration_units, json_boundary): return _failure("process.definition_integer_required", "revision/duration_units 必须是精确整数。")
	if not value.capability_ids is Array or not value.completion_payload is Dictionary: return _failure("process.definition_type_invalid", "ProcessDefinition 集合字段类型无效。")
	for capability_id in value.capability_ids:
		if typeof(capability_id) != TYPE_STRING: return _failure("process.definition_capability_type_invalid", "Capability ID 必须是字符串。")
	if not (value.facility_target is Dictionary or value.facility_target is String): return _failure("process.definition_type_invalid", "facility_target 必须是稳定语义ID或Dictionary。")
	for field in ["definition_id", "display_name_zh", "process_family", "completion_kind", "task_definition_id", "duty_provider_id"]:
		if typeof(value[field]) != TYPE_STRING: return _failure("process.definition_type_invalid", "%s 必须是字符串。" % field)
	var definition := GMProcessDefinition.new()
	definition.definition_id = value.definition_id
	definition.revision = int(value.revision)
	definition.display_name_zh = value.display_name_zh
	definition.process_family = value.process_family
	definition.duration_units = int(value.duration_units)
	definition.capability_ids = PackedStringArray(value.capability_ids)
	definition.facility_target = value.facility_target.duplicate(true) if value.facility_target is Dictionary else str(value.facility_target)
	definition.completion_kind = value.completion_kind
	definition.completion_payload = value.completion_payload.duplicate(true)
	definition.task_definition_id = value.task_definition_id
	definition.duty_provider_id = value.duty_provider_id
	var validation := definition.validate()
	if not validation.ok: return {"ok": false, "code": "process.definition_invalid", "reason_zh": "ProcessDefinition 验证失败。", "errors": validation.errors}
	return {"ok": true, "definition": definition, "value": definition.to_native()}

static func from_json(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK: return _failure("process.definition_json_invalid", "ProcessDefinition JSON 无效。")
	return from_native(parser.data, true)

static func _validate_facility_target(value: Variant) -> Dictionary:
	if value is Dictionary and value.is_empty(): return {"ok": true}
	if value is String:
		return {"ok": true} if _stable_id(value) else {"ok": false, "reason_zh": "Facility/WorkSpot 语义目标必须是稳定ID。"}
	if not value is Dictionary: return {"ok": false, "reason_zh": "Facility/WorkSpot 必须是稳定语义ID或 GMSpatialTargetRef。"}
	var spatial := GMSpatialTargetRef.from_native(value)
	if not spatial.ok: return {"ok": false, "reason_zh": "Facility/WorkSpot 必须是合法 GMSpatialTargetRef。"}
	if spatial.target.kind() == "logical_position": return {"ok": false, "reason_zh": "Process 只能引用稳定空间语义目标，不得保存自由坐标。"}
	return {"ok": true}

static func _stable_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges(): return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 46 or code == 45 or code == 95): return false
	return true

static func _stable_identity(value: String) -> bool:
	return _stable_id(value) and (value.begins_with("gm.") or value.begins_with("p20."))

static func _integer(value: Variant, json_boundary: bool) -> bool:
	if typeof(value) == TYPE_INT: return value >= 0 and value <= GMStableData.JSON_SAFE_INTEGER_MAX
	return json_boundary and typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value) and value >= 0.0 and value <= float(GMStableData.JSON_SAFE_INTEGER_MAX)

static func _failure(code: String, reason_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh}
