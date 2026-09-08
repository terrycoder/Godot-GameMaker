@tool
class_name GMTargetSelector
extends Resource

## 事件目标选择器基类与内置稳定身份选择器。
##
## 选择器只返回 GMTargetData；它不保存裸 NodePath，也不修改目标。实体
## 需要在运行时通过对象或注册表以业务 ID 解析，解析失败必须显式阻断。

const EVENT_TARGET := "事件目标"
const EVENT_INSTIGATOR := "事件发起者"
const PAYLOAD_ID := "载荷业务ID"
const PAYLOAD_LOCATION := "载荷位置"
const AREA := "区域"
const GDSCRIPT := "GDScript"

@export var selector_id: String = ""
@export var display_name_zh: String = "事件目标选择器"
@export_enum("事件目标", "事件发起者", "载荷业务ID", "载荷位置", "区域", "GDScript") var selector_kind: String = EVENT_TARGET
@export var payload_field: String = "target_id"
@export var target_type: String = GMTargetData.TYPE_ENTITY
@export var require_live_target: bool = true
@export_file("*.gd") var script_path: String = ""

func validate_definition(_context: Dictionary = {}) -> Dictionary:
	var errors: Array[Dictionary] = []
	if selector_id.strip_edges().is_empty(): errors.append({"code": "target.selector_id_missing", "reason_zh": "目标选择器缺少稳定选择器 ID。", "field": "selector_id"})
	var custom_path := _resolved_script_path()
	var custom_script: bool = selector_kind == GDSCRIPT or not custom_path.is_empty()
	if custom_script:
		var path := custom_path
		if path.is_empty(): errors.append({"code": "target.selector_script_missing", "reason_zh": "GDScript 目标选择器缺少脚本路径。", "field": "script_path"})
		else:
			var check := GMEventScriptValidator.validate_selector_script(path)
			if not check.ok: errors.append_array(check.get("errors", []))
	return {"ok": errors.is_empty(), "code": "target.selector_valid" if errors.is_empty() else "target.selector_invalid", "errors": errors, "errors_zh": _messages(errors), "selector_id": selector_id, "custom_script": custom_script}

func select(event: GMGameplayEvent, context: Dictionary = {}) -> Dictionary:
	var check := validate_definition(context)
	if not bool(check.get("ok", false)): return {"ok": false, "code": "target.selector_invalid", "reason_zh": "目标选择器验证失败。", "errors": check.get("errors", []), "selector_id": str(selector_id)}
	var raw: Variant
	if bool(check.get("custom_script", false)):
		raw = _select(event, context)
	else:
		raw = _select_builtin(event, context)
	if not raw is Dictionary:
		return {"ok": false, "code": "target.selector_return_type", "reason_zh": "目标选择器必须返回 Dictionary，不能静默跳过。", "selector_id": str(selector_id)}
	# Never deep-copy a selector result: GMTargetData may retain a live Node via
	# WeakRef, and a deep duplicate would traverse an engine-owned object graph.
	# Only the outer dictionary and the target container are copied shallowly;
	# each GMTargetData/Node remains the exact live object returned by the subclass.
	var result: Dictionary = {}
	for key in raw.keys(): result[key] = raw[key]
	if raw.has("targets"):
		var raw_targets: Variant = raw.get("targets")
		if not raw_targets is Array:
			return {"ok": false, "code": "target.selector_targets_type", "reason_zh": "目标选择器 targets 必须返回 Array。", "selector_id": str(selector_id), "normalization": {"raw_type": typeof(raw), "normalized_type": typeof(result)}}
		var shallow_targets: Array = []
		for item in raw_targets: shallow_targets.append(item)
		result["targets"] = shallow_targets
	if raw.has("target"):
		var raw_target: Variant = raw.get("target")
		if raw_target != null and not raw_target is GMTargetData:
			return {"ok": false, "code": "target.selector_target_type", "reason_zh": "目标选择器 target 必须是 GMTargetData。", "selector_id": str(selector_id), "normalization": {"raw_type": typeof(raw), "normalized_type": typeof(result)}}
	if not result.has("ok"): result["ok"] = true
	if not result.get("ok") is bool:
		return {"ok": false, "code": "target.selector_ok_type", "reason_zh": "目标选择器结果 ok 必须是 bool。", "selector_id": str(selector_id), "normalization": {"raw_type": typeof(raw), "normalized_type": typeof(result)}}
	if not bool(result.get("ok", false)): return result
	var targets: Array = []
	if result.has("targets"): targets = result.get("targets")
	elif result.get("target", null) is GMTargetData: targets = [result.get("target")]
	for index in targets.size():
		if targets[index] == null or not targets[index] is GMTargetData:
			return {"ok": false, "code": "target.selector_target_type", "reason_zh": "目标选择器第 %d 项不是 GMTargetData。" % index, "selector_id": str(selector_id)}
		var target_check: Dictionary = targets[index].validate()
		var target_valid: bool = bool(target_check.get("ok", false))
		var needs_live: bool = bool(require_live_target)
		if needs_live and not target_valid:
			return {"ok": false, "code": "target.missing", "reason_zh": "事件目标解析失败：%s" % str(target_check.get("reason_zh", "目标不存在。")), "target": target_check, "selector_id": str(selector_id)}
	result["targets"] = targets
	result["selector_id"] = str(selector_id)
	result["normalization"] = {"raw_type": typeof(raw), "normalized_type": typeof(result), "deep_copy": false, "live_objects_preserved": true}
	return result

## GDScript 扩展覆盖点。正式脚本必须显式声明：
## func _select(event: GMGameplayEvent, context: Dictionary) -> Dictionary
func _select(_event: GMGameplayEvent, _context: Dictionary) -> Dictionary:
	return {"ok": false, "code": "target.selector_script_not_implemented", "reason_zh": "目标选择器 GDScript 没有实现 _select。"}

func summary() -> Dictionary:
	return {"selector_id": selector_id, "display_name_zh": display_name_zh, "selector_kind": selector_kind, "payload_field": payload_field, "target_type": target_type, "require_live_target": require_live_target, "script_path": _resolved_script_path()}

func _select_builtin(event: GMGameplayEvent, context: Dictionary) -> Dictionary:
	match selector_kind:
		EVENT_TARGET:
			if event == null or event.target == null or not is_instance_valid(event.target): return _missing("事件没有有效目标实体。")
			return {"ok": true, "targets": [GMTargetData.from_entity(event.target, _stable_id(event.target))], "source": "event.target"}
		EVENT_INSTIGATOR:
			if event == null or event.instigator == null or not is_instance_valid(event.instigator): return _missing("事件没有有效发起者实体。")
			return {"ok": true, "targets": [GMTargetData.from_entity(event.instigator, _stable_id(event.instigator))], "source": "event.instigator"}
		PAYLOAD_ID:
			var payload_id: String = str(event.payload.get(payload_field, "")) if event != null else ""
			if payload_id.is_empty(): return _missing("事件载荷缺少目标业务 ID：%s。" % payload_field)
			var target: Object = _resolve_business_id(payload_id, context)
			var data: GMTargetData = GMTargetData.from_entity(target, payload_id)
			return {"ok": true, "targets": [data], "source": "event.payload.%s" % payload_field, "target_business_id": payload_id}
		PAYLOAD_LOCATION:
			var raw_location: Variant = event.payload.get(payload_field, null) if event != null else null
			var location: Variant = _coerce_location(raw_location)
			if location == null: return _missing("事件载荷缺少有效位置：%s。" % payload_field)
			return {"ok": true, "targets": [GMTargetData.from_location(location)], "source": "event.payload.%s" % payload_field}
		AREA:
			var area_id: String = str(event.payload.get(payload_field, "")) if event != null else ""
			if area_id.is_empty(): return _missing("事件载荷缺少区域业务 ID：%s。" % payload_field)
			return {"ok": true, "targets": [GMTargetData.from_area(area_id)], "source": "event.payload.%s" % payload_field}
		_: return {"ok": false, "code": "target.selector_kind_invalid", "reason_zh": "未知目标选择器类型：%s。" % selector_kind}

func _resolve_business_id(business_id: String, context: Dictionary) -> Object:
	var resolver: Variant = context.get("entity_resolver", null)
	if resolver is Callable and resolver.is_valid():
		var value: Variant = resolver.call(business_id)
		if value != null and is_instance_valid(value): return value
	var registry: Variant = context.get("entity_registry", null)
	if registry is Dictionary:
		var found: Variant = registry.get(business_id, null)
		if found != null and is_instance_valid(found): return found
	var host: Variant = context.get("host", null)
	if host != null and is_instance_valid(host):
		var host_entity: Variant = host.get("entity")
		if host_entity != null and is_instance_valid(host_entity) and _stable_id(host_entity) == business_id: return host_entity
	return null

func _coerce_location(value: Variant) -> Variant:
	if value is Vector2: return value
	if value is Dictionary and value.has("x") and value.has("y"): return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return null

func _missing(reason_zh: String) -> Dictionary:
	return {"ok": false, "code": "target.missing", "reason_zh": reason_zh, "selector_id": selector_id}

func _resolved_script_path() -> String:
	if not script_path.strip_edges().is_empty(): return script_path.strip_edges()
	var script_value: Variant = get_script()
	if script_value is Script and str(script_value.resource_path) != "res://gm_runtime/events/gm_target_selector.gd": return str(script_value.resource_path)
	return ""

func _stable_id(value: Object) -> String:
	if value == null or not is_instance_valid(value): return ""
	if value.has_method("get_business_id"): return str(value.get_business_id())
	if value.has_method("get_gm_id"): return str(value.get_gm_id())
	if value is Node and value.has_meta("gm_id"): return str(value.get_meta("gm_id"))
	return ""

func _messages(errors: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for row in errors: result.append(str(row.get("reason_zh", "目标选择器无效。")))
	return result
