@tool
class_name GMEventHandler
extends Resource

## Gameplay Event 处理器基类。
##
## 处理器只能把事件翻译为声明式后续动作/诊断结果，不能直接写领域事实。
## 领域变化必须由 GMEventAction 走 GMAbilityActivationRequest。

@export var handler_id: String = ""
@export var display_name_zh: String = "事件处理器"
@export_file("*.gd") var script_path: String = ""

func validate_definition(_context: Dictionary = {}) -> Dictionary:
	var errors: Array[Dictionary] = []
	if handler_id.strip_edges().is_empty(): errors.append({"code": "event.handler_id_missing", "reason_zh": "事件处理器缺少稳定处理器 ID。", "field": "handler_id"})
	var path := _resolved_script_path()
	if not path.is_empty():
		var script_check := GMEventScriptValidator.validate_handler_script(path)
		if not script_check.ok: errors.append_array(script_check.get("errors", []))
	return {"ok": errors.is_empty(), "code": "event.handler_valid" if errors.is_empty() else "event.handler_invalid", "errors": errors, "errors_zh": _messages(errors), "handler_id": handler_id, "script_path": path}

func handle_event(event: GMGameplayEvent, context: Dictionary = {}) -> Dictionary:
	var check := validate_definition(context)
	if not check.ok: return {"ok": false, "code": "event.handler_invalid", "reason_zh": "事件处理器验证失败。", "errors": check.errors, "handler_id": handler_id}
	var value: Variant = _handle_event(event, context)
	if not value is Dictionary:
		return {"ok": false, "code": "event.handler_return_type", "reason_zh": "事件处理器 GDScript 必须返回 Dictionary，不能静默忽略。", "handler_id": handler_id}
	var result: Dictionary = value.duplicate(true)
	if not result.has("ok"): result["ok"] = true
	result["handler_id"] = handler_id
	return result

## GDScript 扩展覆盖点。正式脚本必须显式声明：
## func _handle_event(event: GMGameplayEvent, context: Dictionary) -> Dictionary
func _handle_event(_event: GMGameplayEvent, _context: Dictionary) -> Dictionary:
	return {"ok": true, "actions": [], "handled": false}

func summary() -> Dictionary:
	return {"handler_id": handler_id, "display_name_zh": display_name_zh, "script_path": _resolved_script_path()}

func _resolved_script_path() -> String:
	if not script_path.strip_edges().is_empty(): return script_path.strip_edges()
	var script_value: Variant = get_script()
	if script_value is Script and str(script_value.resource_path) != "res://gm_runtime/events/gm_event_handler.gd": return str(script_value.resource_path)
	return ""

func _messages(errors: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for row in errors: result.append(str(row.get("reason_zh", "事件处理器无效。")))
	return result
