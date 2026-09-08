@tool
class_name GMMovementAbilityDefinition
extends GMAbilityDefinition

func _init() -> void:
	ability_id = "gm.ability.movement"
	display_name_zh = "统一移动"
	description_zh = "玩家、AI与脚本共用的移动、朝向、跟随、巡逻和旅行交接入口。"
	ability_tags = PackedStringArray(["Ability.Movement"])
	blocked_tags = PackedStringArray(["state.stunned"])
	concurrency_group = "gm.movement.single_owner"
	# GAS允许取消请求抵达同一执行器；真正的单owner与目标替换冲突由
	# P15 movement backend在任何写入前统一裁定。
	concurrency_policy = "允许并行"

func can_activate(host: GMAbilitySystemHost, request: GMAbilityActivationRequest, spec: GMAbilitySpec) -> Dictionary:
	var base := super.can_activate(host, request, spec)
	if not base.ok: return base
	var parsed := GMMovementRequest.from_dict(request.event_data.get("movement_request", null))
	if not parsed.ok: return parsed
	if request.source != "character.%s" % parsed.request.source:
		return {"ok": false, "code": "movement.source_mismatch", "reason_zh": "ActivationRequest来源与移动请求来源不一致。", "fix_zh": "请通过统一ControlSource适配器提交请求。"}
	var service: Object = host.domain_services.get("gm.movement.executor", null)
	if service == null: return {"ok": false, "code": "movement.executor_missing", "reason_zh": "能力宿主缺少P15移动执行器。", "fix_zh": "请注册gm.movement.executor领域服务。"}
	if not service.has_method("preflight"): return {"ok": false, "code": "movement.executor_interface_missing", "reason_zh": "能力宿主的移动执行器缺少统一P15预检接口。", "fix_zh": "请注册实现preflight/start_request/tick_command的移动后端。"}
	return service.preflight(parsed.request, host.entity)

func create_tasks(host: GMAbilitySystemHost, request: GMAbilityActivationRequest, _spec: GMAbilitySpec) -> Array:
	var parsed := GMMovementRequest.from_dict(request.event_data.get("movement_request", null))
	if not parsed.ok: return []
	var service: Object = host.domain_services.get("gm.movement.executor", null)
	return [GMMovementAbilityTask.new(parsed.request, service, host.entity, "gm.task.movement.%s" % request.request_id)]
