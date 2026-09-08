@tool
class_name GMEventAction
extends Resource

## 事件触发器的声明式动作。
##
## “激活能力”和“发送 GameplayEvent”是仅有的领域入口。动作本身不写
## 库存、战斗、任务或移动状态，保证事件规则不会形成第二套事实链。

const ACTIVATE_ABILITY := "激活能力"
const SEND_EVENT := "发送GameplayEvent"

@export_enum("激活能力", "发送GameplayEvent") var action_kind: String = ACTIVATE_ABILITY
@export var action_id: String = ""
@export_group("能力动作")
@export var ability_id: String = ""
@export var ability_tag: String = ""
@export var target_required: bool = true
@export_group("事件动作")
@export var event_tag: String = ""
@export var event_schema: Dictionary = {}
@export var payload: Dictionary = {}
@export var target_event_from_selector: bool = true

func validate_definition(_context: Dictionary = {}) -> Dictionary:
	var errors: Array[Dictionary] = []
	if action_id.strip_edges().is_empty(): errors.append({"code": "event.action_id_missing", "reason_zh": "事件动作缺少稳定动作 ID。", "field": "action_id"})
	match action_kind:
		ACTIVATE_ABILITY:
			if ability_id.strip_edges().is_empty() and ability_tag.strip_edges().is_empty(): errors.append({"code": "event.ability_missing", "reason_zh": "激活能力动作必须声明能力 ID 或能力标签。", "field": "ability_id"})
		SEND_EVENT:
			if event_tag.strip_edges().is_empty(): errors.append({"code": "event.send_tag_missing", "reason_zh": "发送 GameplayEvent 动作缺少事件标签。", "field": "event_tag"})
			elif not (event_tag.begins_with("gm.event.") or event_tag.contains(".event.")): errors.append({"code": "event.send_tag_invalid", "reason_zh": "发送的 GameplayEvent 标签必须使用事件命名空间：%s。" % event_tag, "field": "event_tag"})
		_:
			errors.append({"code": "event.action_kind_invalid", "reason_zh": "未知事件动作类型：%s。" % action_kind, "field": "action_kind"})
	return {"ok": errors.is_empty(), "code": "event.action_valid" if errors.is_empty() else "event.action_invalid", "errors": errors, "errors_zh": _messages(errors), "action_id": action_id}

func execute(host: Object, event: GMGameplayEvent, trigger_id: String, target_data: GMTargetData = null, trigger_context: Dictionary = {}) -> Dictionary:
	var check := validate_definition(trigger_context)
	if not check.ok: return {"ok": false, "code": "event.action_invalid", "reason_zh": "事件动作验证失败。", "errors": check.errors, "action_id": action_id}
	if target_required and (target_data == null or not target_data.validate().ok):
		var target_check := target_data.validate() if target_data != null else {"ok": false, "code": "target.missing", "reason_zh": "动作需要目标，但目标选择器没有返回有效目标。"}
		return {"ok": false, "code": "target.missing", "reason_zh": str(target_check.get("reason_zh", "动作目标缺失。")), "target": target_check, "action_id": action_id}
	if host == null or not is_instance_valid(host): return {"ok": false, "code": "event.host_missing", "reason_zh": "事件动作缺少有效能力宿主。", "action_id": action_id}
	match action_kind:
		ACTIVATE_ABILITY:
			return _execute_ability(host, event, trigger_id, target_data, trigger_context)
		SEND_EVENT:
			return _execute_event(host, event, trigger_id, target_data, trigger_context)
	return {"ok": false, "code": "event.action_kind_invalid", "reason_zh": "未知事件动作类型：%s。" % action_kind, "action_id": action_id}

func summary() -> Dictionary:
	return {"action_id": action_id, "action_kind": action_kind, "ability_id": ability_id, "ability_tag": ability_tag, "target_required": target_required, "event_tag": event_tag, "payload": payload.duplicate(true), "event_schema": event_schema.duplicate(true)}

func _execute_ability(host: Object, event: GMGameplayEvent, trigger_id: String, target_data: GMTargetData, trigger_context: Dictionary) -> Dictionary:
	var resolved_ability_id := ability_id
	if resolved_ability_id.is_empty() and not ability_tag.is_empty():
		var probe := GMAbilityActivationRequest.new(host, "", ability_tag, target_data, {}, "event_trigger", {}, "")
		resolved_ability_id = host.resolve_ability_id(probe) if host.has_method("resolve_ability_id") else ""
	if resolved_ability_id.is_empty() or not host.has_ability(resolved_ability_id):
		return {"ok": false, "code": "event.ability_missing", "reason_zh": "事件触发器要激活的能力不存在或未授予：%s。" % (ability_id if not ability_id.is_empty() else ability_tag), "ability_id": resolved_ability_id if not resolved_ability_id.is_empty() else ability_id, "action_id": action_id}
	var event_data := _activation_event_data(event, trigger_id, target_data, trigger_context)
	var source_id := str(event_data.get("source_id", "event"))
	var target_id := str(event_data.get("target_id", ""))
	var idempotency := "gm.event.activation.%s.%s.%s" % [_slug(trigger_id), _slug(event.dispatch_id), _slug(target_id if not target_id.is_empty() else "none")]
	var request := GMAbilityActivationRequest.new(host, resolved_ability_id, "", target_data, event_data, "event_trigger:%s" % trigger_id, {"event_trigger_id": trigger_id, "event_depth": event.dispatch_depth}, idempotency)
	var activation: Dictionary = host.activate(request)
	return {"ok": bool(activation.get("ok", false)), "code": "event.ability_activated" if bool(activation.get("ok", false)) else str(activation.get("failure_code", activation.get("code", "event.ability_blocked"))), "reason_zh": "" if bool(activation.get("ok", false)) else str(activation.get("failure_reason_zh", activation.get("reason_zh", "事件能力激活被阻断。"))), "action_id": action_id, "ability_id": resolved_ability_id, "activation": activation, "source_id": source_id, "target_id": target_id}

func _execute_event(host: Object, event: GMGameplayEvent, trigger_id: String, target_data: GMTargetData, trigger_context: Dictionary) -> Dictionary:
	var next_payload := event.payload.duplicate(true) if event != null else {}
	next_payload.merge(payload, true)
	var next_target: Object = target_data.target if target_data != null and target_data.target != null and is_instance_valid(target_data.target) else (event.target if event != null else null)
	var next_context := event.context.duplicate(true) if event != null else {}
	var stack: Array = next_context.get("trigger_stack", []) if next_context.get("trigger_stack", []) is Array else []
	var next_stack := stack.duplicate(true)
	next_stack.append(trigger_id)
	next_context["trigger_stack"] = next_stack
	next_context["cause_event_id"] = event.event_id if event != null else ""
	next_context["cause_trigger_id"] = trigger_id
	next_context["event_trigger_context"] = trigger_context.get("cause_chain", {})
	var next_event := GMGameplayEvent.new(event_tag, event.instigator if event != null else null, next_target, next_payload, "event_trigger:%s" % trigger_id, next_context, event_schema)
	var emitted: Dictionary = host.emit_gameplay_event(next_event) if host.has_method("emit_gameplay_event") else {"ok": false, "code": "event.host_dispatch_missing", "reason_zh": "能力宿主没有 GameplayEvent 分发入口。"}
	return {"ok": bool(emitted.get("ok", false)), "code": "event.emitted" if bool(emitted.get("ok", false)) else str(emitted.get("code", "event.emit_blocked")), "reason_zh": "" if bool(emitted.get("ok", false)) else str(emitted.get("reason_zh", "GameplayEvent 发送失败。")), "action_id": action_id, "event": next_event.to_dict(), "dispatch": emitted}

func _activation_event_data(event: GMGameplayEvent, trigger_id: String, target_data: GMTargetData, trigger_context: Dictionary) -> Dictionary:
	var data := event.payload.duplicate(true) if event != null else {}
	data["gameplay_event"] = event.to_dict() if event != null else {}
	data["trigger_id"] = trigger_id
	data["cause_chain"] = trigger_context.get("cause_chain", {})
	data["source_id"] = _stable_id(event.instigator) if event != null else ""
	data["target_id"] = target_data.target_business_id if target_data != null else (_stable_id(event.target) if event != null else "")
	return data

func _stable_id(value: Object) -> String:
	if value == null or not is_instance_valid(value): return ""
	if value.has_method("get_business_id"): return str(value.get_business_id())
	if value.has_method("get_gm_id"): return str(value.get_gm_id())
	if value is Node and value.has_meta("gm_id"): return str(value.get_meta("gm_id"))
	return ""

func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in raw.length():
		var code := raw.unicode_at(index)
		result += raw.substr(index, 1) if ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45) else "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_") if not result.is_empty() else "action"

func _messages(errors: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for row in errors: result.append(str(row.get("reason_zh", "事件动作无效。")))
	return result
