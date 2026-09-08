class_name GMTask04DomainServices
extends RefCounted

## 样板领域服务只通过 Host.execute_domain_command 被能力调用。

var calls: Array[Dictionary] = []

func execute_ability(definition: GMAbilityDefinition, request: GMAbilityActivationRequest, spec: GMAbilitySpec) -> Dictionary:
	var ability_id: String = definition.ability_id
	var action: String = str({
		"gm.ability.move": "移动命令已提交",
		"gm.ability.eat": "进食库存事务已提交",
		"gm.ability.drop_loot": "死亡掉落随机表已提交",
		"gm.ability.produce": "建筑生产占位事务已提交",
	}.get(ability_id, "领域命令已提交"))
	var record := {
		"ability_id": ability_id,
		"executor": definition.executor_service_id,
		"source": request.source,
		"level": spec.effective_level(),
		"event_data": request.event_data.duplicate(true),
		"schedule_context": request.schedule_context.duplicate(true),
		"action": action,
	}
	calls.append(record)
	return {
		"ok": true,
		"result_code": "domain.accepted",
		"action_zh": action,
		"domain_call": record,
		"canonical_path": GMAbilitySystemHost.ACTIVATION_PATH,
	}

func summary() -> Dictionary:
	return {"call_count": calls.size(), "calls": calls.duplicate(true)}
