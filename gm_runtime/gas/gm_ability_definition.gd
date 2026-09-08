@tool
class_name GMAbilityDefinition
extends Resource

## 静态能力定义：只描述规则、标签和领域服务，不保存宿主运行时状态。

@export_group("能力身份")
@export var ability_id: String = ""
@export var display_name_zh: String = ""
@export_multiline var description_zh: String = ""
@export var ability_tags: PackedStringArray = PackedStringArray()
@export var executor_service_id: String = ""

@export_group("事实事务")
## 非空时，能力执行会进入 GM 统一 DomainTransaction，并且只有提交成功才产生 FactEvent。
@export var resolver_id: String = ""
@export var fact_type: String = ""
@export var fact_source_system: String = "gm.domain"
@export var fact_tags: PackedStringArray = PackedStringArray()
@export var fact_visibility: Dictionary = {"public": false, "witnesses": []}

@export_group("成本与冷却")
## 数值成本行：{"attribute_id":"stamina", "amount":10}。
@export var costs: Array[Dictionary] = []
## 通过同一 GameplayEffect 运行时执行的瞬时成本效果。
@export var cost_effect_ids: PackedStringArray = PackedStringArray()
## 05C 唯一库存事务成本行，例如 {"item_kind":"lot", "item_id":"food.apple", "quantity":1}。
@export var inventory_costs: Array[Dictionary] = []
@export var cooldown_effect_id: String = ""
@export var cooldown_tag: String = ""
@export var cooldown_duration_seconds: float = 0.0
@export var cooldown_unit: String = "seconds"
@export_enum("不退款", "退属性与冷却", "全量退款（需领域逆操作）") var cancel_refund_policy: String = "不退款"
@export var required_cue_ids: PackedStringArray = PackedStringArray()
@export var activation_effect_ids: PackedStringArray = PackedStringArray()
@export var activation_cue_ids: PackedStringArray = PackedStringArray()
@export var content_version: String = "gm.content.v1"

@export_group("激活规则")
@export var required_tags: PackedStringArray = PackedStringArray()
@export var blocked_tags: PackedStringArray = PackedStringArray()
@export var grant_tags: PackedStringArray = PackedStringArray()
@export var blocked_ability_ids: PackedStringArray = PackedStringArray()
@export var owned_tags: PackedStringArray = PackedStringArray()
@export var cancel_tags: PackedStringArray = PackedStringArray()
@export var block_tags: PackedStringArray = PackedStringArray()
@export var cancel_ability_ids: PackedStringArray = PackedStringArray()
@export var block_ability_ids: PackedStringArray = PackedStringArray()
@export var concurrency_group: String = ""
@export_enum("允许并行", "同组拒绝", "同组替换", "同组排队") var concurrency_policy: String = "允许并行"
@export_enum("串行", "并行") var task_execution_mode: String = "串行"
@export var queue_timeout_seconds: float = 5.0
@export var queue_timeout_turns: int = 3
@export var event_trigger_tags: PackedStringArray = PackedStringArray()
@export var static_parameters: Dictionary = {}

func can_activate(host: GMAbilitySystemHost, request: GMAbilityActivationRequest, spec: GMAbilitySpec) -> Dictionary:
	if host == null:
		return {"ok": false, "code": "ability.host_missing", "reason_zh": "能力定义没有收到宿主。"}
	for tag_value in required_tags:
		if not host.tags.matches(str(tag_value), "hierarchy"):
			return {"ok": false, "code": "ability.required_tag_missing", "reason_zh": "能力“%s”缺少必需标签：%s" % [display_name_zh, str(tag_value)]}
	for tag_value in blocked_tags:
		if host.tags.matches(str(tag_value), "hierarchy"):
			return {"ok": false, "code": "ability.blocked_by_tag", "reason_zh": "能力“%s”被宿主标签阻断：%s" % [display_name_zh, str(tag_value)]}
	# block_tags/block_ability_ids are outgoing declarations: while this
	# ability is active the Host compares them with an incoming ability.
	for blocked_id in blocked_ability_ids:
		if host.has_active_ability(str(blocked_id)):
			return {"ok": false, "code": "ability.blocked_by_ability", "reason_zh": "能力“%s”被正在执行的能力阻断：%s" % [display_name_zh, str(blocked_id)]}
	if request != null and request.target_data != null:
		var target_check := request.target_data.validate()
		if not target_check.ok:
			return {"ok": false, "code": str(target_check.get("code", "target.invalid")), "reason_zh": str(target_check.get("reason_zh", "能力目标无效。")), "target": target_check}
	if host.has_method("check_ability_commit"):
		var commit_check: Dictionary = host.check_ability_commit(self, request, spec)
		if not commit_check.ok: return commit_check
	return {"ok": true}

func pre_commit(host: GMAbilitySystemHost, request: GMAbilityActivationRequest, spec: GMAbilitySpec) -> Dictionary:
	return host.prepare_ability_commit(self, request, spec) if host != null and host.has_method("prepare_ability_commit") else {"ok": true}

func commit_costs_and_cooldowns(host: GMAbilitySystemHost, request: GMAbilityActivationRequest, spec: GMAbilitySpec) -> Dictionary:
	return host.commit_ability_commit(self, request, spec) if host != null and host.has_method("commit_ability_commit") else {"ok": true}

func on_activate(host: GMAbilitySystemHost, request: GMAbilityActivationRequest, _spec: GMAbilitySpec) -> Dictionary:
	for effect_id in activation_effect_ids:
		var effect: GMEffectDefinition = host.effect_definitions.get(str(effect_id), null)
		if effect == null: return {"ok": false, "code": "ability.activation_effect_missing", "reason_zh": "能力激活效果定义缺失：%s。" % effect_id}
		var effect_spec := GMEffectSpec.new(effect, request.source if request != null else "ability")
		effect_spec.configure_identity(request.source if request != null else "ability", host.entity_id_for_gas() if host.has_method("entity_id_for_gas") else "gm.host", {"ability_id": ability_id, "stage": "activate"})
		var applied := host.apply_effect(effect, effect_spec)
		if not applied.ok: return applied
	for cue_id in activation_cue_ids:
		var cue_parameters := GMCueParameters.new(str(cue_id), host.entity, {"stage": "execute", "context": {"ability_id": ability_id, "source_id": request.source if request != null else ""}})
		var cue := host.emit_cue(cue_parameters)
		if not cue.ok: return cue
	return {"ok": true, "activation_effect_ids": Array(activation_effect_ids), "activation_cue_ids": Array(activation_cue_ids)}

func create_tasks(_host: GMAbilitySystemHost, _request: GMAbilityActivationRequest, _spec: GMAbilitySpec) -> Array:
	return []

func on_task_event(_host: GMAbilitySystemHost, _request: GMAbilityActivationRequest, _spec: GMAbilitySpec, _task_result: Dictionary) -> Dictionary:
	return {"ok": true}

func execute(host: GMAbilitySystemHost, request: GMAbilityActivationRequest, spec: GMAbilitySpec) -> Dictionary:
	if not fact_type.strip_edges().is_empty():
		var typed_result: Variant = host.execute_domain_transaction(self, request, spec)
		if typed_result is GMCommittedFactResult:
			var committed: GMCommittedFactResult = typed_result
			var committed_dict := committed.to_dict()
			committed_dict["ok"] = true
			committed_dict["result_code"] = "fact.committed"
			return committed_dict
		if typed_result is GMBlockedResult:
			var blocked: GMBlockedResult = typed_result
			var blocked_dict := blocked.to_dict()
			blocked_dict["ok"] = false
			blocked_dict["code"] = blocked.error_code
			blocked_dict["reason_zh"] = blocked.reason_zh
			return blocked_dict
		return {"ok": false, "code": "transaction.result_invalid", "reason_zh": "领域事务没有返回 Candidate/Blocked/CommittedFact 合同。"}
	if executor_service_id.is_empty():
		return {"ok": true, "result_code": "ability.completed_without_domain", "executor": ""}
	return host.execute_domain_command(executor_service_id, self, request, spec)

func on_end(_host: GMAbilitySystemHost, _request: GMAbilityActivationRequest, _spec: GMAbilitySpec, _result: Dictionary) -> void:
	pass

func on_cancel(_host: GMAbilitySystemHost, _request: GMAbilityActivationRequest, _spec: GMAbilitySpec, _reason_zh: String) -> void:
	pass

func on_fail(_host: GMAbilitySystemHost, _request: GMAbilityActivationRequest, _spec: GMAbilitySpec, _failure: Dictionary) -> void:
	pass

func to_summary() -> Dictionary:
	return {
		"ability_id": ability_id,
		"display_name_zh": display_name_zh,
		"description_zh": description_zh,
		"ability_tags": Array(ability_tags),
		"executor_service_id": executor_service_id,
		"resolver_id": resolver_id,
		"fact_type": fact_type,
		"fact_source_system": fact_source_system,
		"fact_tags": Array(fact_tags),
		"fact_visibility": fact_visibility.duplicate(true),
		"costs": costs.duplicate(true),
		"cost_effect_ids": Array(cost_effect_ids),
		"inventory_costs": inventory_costs.duplicate(true),
		"cooldown_effect_id": cooldown_effect_id,
		"cooldown_tag": cooldown_tag,
		"cooldown_duration_seconds": cooldown_duration_seconds,
		"cooldown_unit": cooldown_unit,
		"cancel_refund_policy": cancel_refund_policy,
		"required_cue_ids": Array(required_cue_ids),
		"activation_effect_ids": Array(activation_effect_ids),
		"activation_cue_ids": Array(activation_cue_ids),
		"content_version": content_version,
		"required_tags": Array(required_tags),
		"blocked_tags": Array(blocked_tags),
		"grant_tags": Array(grant_tags),
		"owned_tags": Array(owned_tags),
		"cancel_tags": Array(cancel_tags),
		"block_tags": Array(block_tags),
		"cancel_ability_ids": Array(cancel_ability_ids),
		"block_ability_ids": Array(block_ability_ids),
		"concurrency_group": concurrency_group,
		"concurrency_policy": concurrency_policy,
		"task_execution_mode": task_execution_mode,
		"queue_timeout_seconds": queue_timeout_seconds,
		"queue_timeout_turns": queue_timeout_turns,
		"event_trigger_tags": Array(event_trigger_tags),
		"static_parameters": static_parameters.duplicate(true),
	}
