extends Node

## 任务07正式运行时导出探针。
## 不引用 addons、tests、dev_samples 或 reports；事件触发仍挂到既有 Host
## 的 gameplay_event signal，动作仅使用发送 GameplayEvent 的正式入口。

const HOST := preload("res://gm_runtime/gas/gm_ability_system_host.gd")
const TRIGGER := preload("res://gm_runtime/events/gm_gameplay_event_trigger.gd")
const CONDITION := preload("res://gm_runtime/events/gm_event_condition.gd")
const ACTION := preload("res://gm_runtime/events/gm_event_action.gd")

func _ready() -> void:
	var host: GMAbilitySystemHost = HOST.new()
	var condition: GMEventCondition = CONDITION.new()
	condition.condition_id = "gm.condition.task07.export.tag"
	condition.condition_kind = CONDITION.KIND_TAG
	condition.tag_query = "gm.event.task07.export.root"
	var action: GMEventAction = ACTION.new()
	action.action_id = "gm.action.task07.export.followup"
	action.action_kind = GMEventAction.SEND_EVENT
	action.event_tag = "gm.event.task07.export.followup"
	action.target_required = false
	var trigger: GMGameplayEventTrigger = TRIGGER.new()
	trigger.trigger_id = "gm.trigger.task07.export"
	trigger.display_name_zh = "任务07导出运行时触发器"
	trigger.event_tag = "gm.event.task07.export.root"
	trigger.conditions = [condition]
	trigger.actions = [action]
	var registration: Dictionary = host.register_event_trigger(trigger)
	var event := GMGameplayEvent.new("gm.event.task07.export.root", null, null, {"probe": "task07"}, "gm_task07_export")
	var dispatch: Dictionary = host.emit_gameplay_event(event)
	var runtime: Dictionary = dispatch.get("trigger_runtime", {}) if dispatch.get("trigger_runtime", {}) is Dictionary else {}
	var triggered: Array = runtime.get("triggered", []) if runtime.get("triggered", []) is Array else []
	var snapshot: Dictionary = host.event_trigger_snapshot()
	var signal_source := str(snapshot.get("signal_source", ""))
	var ok: bool = bool(registration.get("ok", false)) and bool(dispatch.get("ok", false)) and triggered.size() == 1 and bool(triggered[0].get("ok", false)) and signal_source == "GMAbilitySystemHost.gameplay_event"
	var payload := {"schema_version": "gm.task07.export_runtime.v1", "registration": registration, "dispatch": dispatch, "dispatch_ok": dispatch.get("ok", false), "triggered_count": triggered.size(), "signal_source": signal_source, "formal_runtime_only": true}
	print("GM_TASK07_EXPORT_RUNTIME_%s %s" % ["OK" if ok else "FAIL", JSON.stringify(payload)])
	host.unmount()
	get_tree().quit(0 if ok else 1)
