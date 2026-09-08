class_name GMP26NeutralSlices
extends GMNeutralVerticalSample

const CONTRACT_SCHEMA := "gm.p26.neutral_slices.contract.v1"
const CARRY_ABILITY_ID := "gm.ability.p26.carry_store"
const INVENTORY_STORE_ID := "gm.store.inventory"
const PLAYER_CONTAINER_ID := "gm.container.p26.player"
const WORLD_CONTAINER_ID := "gm.container.p26.world_pickup"
const NPC_CONTAINER_ID := "gm.container.p26.npc"
const WAREHOUSE_CONTAINER_ID := "gm.container.p26.warehouse"
const SUPPLY_LOT_ID := "gm.item.lot.p26.neutral_supply"
const NPC_LOT_ID := "gm.item.lot.p26.neutral_parts"

@export var planning_rules: Resource

var p26_inventory: GMInventoryStore
var p26_process: GMProcessService
var p26_action_session: GMTaskExecutionSession
var p26_production: Dictionary = {}
var p26_action: Dictionary = {}
var p26_production_button: Button
var p26_recovery_button: Button
var p26_action_button: Button
var p26_runtime_status: Label
var p26_readonly_projection: Label
var p26_danger_feedback_label: Label
var p26_last_player_entry: Dictionary = {}
var p26_player_moved_through_input := false
var p26_player_initial_position := Vector2.ZERO
var p26_production_phase := "idle"
var p26_production_blocked: Dictionary = {}
var p26_production_context: Dictionary = {}
var p26_duty_task: Dictionary = {}
var p26_planner_request: Dictionary = {}
var p26_typed_process_results: Array = []
var p26_danger_feedback: Dictionary = {}
var p26_restore_result: Dictionary = {}

func _should_restore_on_start() -> bool:
	# P25 restores before GMNeutralVerticalSample builds EXT10.  P26 keeps
	# the same WorldSnapshot atomic participant, but defers the formal load
	# until the shared EXT10 projection exists.  This makes ordinary startup
	# and command modes use one save root without replaying the initial
	# workspot workflow against a consumed Reservation.
	return false

func _ready() -> void:
	super._ready()
	if not vertical_ready:
		_reject_unsupported_p26_profile()
		return
	_ensure_p26_input_map()
	_build_p26_runtime_controls()
	p26_player_initial_position = player.position
	var args := OS.get_cmdline_user_args()
	if args.has("--p26-contract") or OS.get_environment("GM_P26_FREEZE_PROBE") == "1":
		call_deferred("_run_p26_contract")
	elif args.has("--p26-save"):
		call_deferred("_run_p26_save")
	elif args.has("--p26-restore"):
		call_deferred("_run_p26_restore")
	elif args.has("--p26-player-probe"):
		call_deferred("_run_p26_player_probe")
	elif FileAccess.file_exists(ProjectSettings.globalize_path(shell_configuration.save_path)):
		call_deferred("_restore_p26_formal_start")

func _reject_unsupported_p26_profile() -> void:
	var args := OS.get_cmdline_user_args()
	var environment_name := ""
	var result_prefix := ""
	if args.has("--p26-contract"):
		environment_name = "GM_P26_CONTRACT_JSON"
		result_prefix = "P26_CONTRACT_RESULT"
	elif args.has("--p26-save"):
		environment_name = "GM_P26_SAVE_JSON"
		result_prefix = "P26_SAVE_RESULT"
	elif args.has("--p26-restore"):
		environment_name = "GM_P26_RESTORE_JSON"
		result_prefix = "P26_RESTORE_RESULT"
	elif args.has("--p26-player-probe"):
		environment_name = "GM_P26_PLAYER_JSON"
		result_prefix = "P26_PLAYER_ENTRY_RESULT"
	if environment_name.is_empty():
		return
	var code := str(vertical_error.get("code", "p26.profile_unsupported"))
	var actor_count := 0 if code == "sample.profile_actor_missing" else -1
	var report := {"schema":"gm.p26.unsupported_profile.v1", "ok":false, "unsupported_domain":true, "code":code, "reason_zh":str(vertical_error.get("reason_zh", "当前Profile不属于P26支持域。")), "actor_count":actor_count, "failure_state_unchanged":true}
	_write_requested_evidence(environment_name, report)
	print(result_prefix + " " + JSON.stringify(report))
	set_process(false)
	set_process_unhandled_input(false)
	get_tree().quit(1)

func dispatch_input_event(event: InputEvent) -> Dictionary:
	if event == null: return super.dispatch_input_event(event)
	for action_id in ["gm.p26.production", "gm.p26.recovery", "gm.p26.action"]:
		if event.is_action_pressed(action_id):
			var result := _handle_p26_player_action(action_id, event)
			action_dispatched.emit(action_id, result.duplicate(true))
			_refresh_p26_projection()
			return result
	var inherited := super.dispatch_input_event(event)
	if str(inherited.get("action", "")).begins_with("move") and event is InputEventKey:
		p26_player_moved_through_input = p26_player_moved_through_input or player.position.distance_to(p26_player_initial_position) > 1.0
	return inherited

func _handle_p26_player_action(action_id: String, event: InputEvent) -> Dictionary:
	if action_id == "gm.p26.production":
		if p26_production_phase == "blocked":
			return {"ok":false, "action":action_id, "idempotent":true, "result":p26_production_blocked.duplicate(true), "projection":_p26_projection_value()}
		if not p26_production.is_empty() and bool(p26_production.get("ok", false)):
			return {"ok":true, "action":action_id, "idempotent":true, "projection":_p26_projection_value()}
		p26_production = run_production_slice(true)
		p26_last_player_entry = {"action":action_id, "input_event_class":event.get_class(), "world_control":true, "interaction_router":true, "task_projection_readonly":bool(task_projection().get("readonly", false)), "result_ok":bool(p26_production.get("ok", false)), "reason_zh":str(p26_production.get("reason_zh", "")), "next_step_zh":str(p26_production.get("next_step_zh", ""))}
		if p26_production_button != null: p26_production_button.disabled = bool(p26_production.get("ok", false))
		return {"ok":bool(p26_production.get("ok", false)), "action":action_id, "entry":p26_last_player_entry.duplicate(true), "result":p26_production}
	if action_id == "gm.p26.recovery":
		var recovery := _continue_production_after_rule_adjustment()
		if recovery.ok: p26_production = recovery
		p26_last_player_entry = {"action":action_id, "input_event_class":event.get_class(), "world_control":true, "interaction_router":true, "task_projection_readonly":bool(task_projection().get("readonly", false)), "result_ok":bool(recovery.get("ok", false)), "reason_zh":str(recovery.get("reason_zh", "")), "next_step_zh":str(recovery.get("next_step_zh", ""))}
		if p26_recovery_button != null: p26_recovery_button.disabled = bool(recovery.get("ok", false))
		if p26_production_button != null: p26_production_button.disabled = bool(recovery.get("ok", false))
		return {"ok":bool(recovery.get("ok", false)), "action":action_id, "entry":p26_last_player_entry.duplicate(true), "result":recovery}
	if action_id == "gm.p26.action":
		if not p26_action.is_empty() and bool(p26_action.get("ok", false)):
			return {"ok":true, "action":action_id, "idempotent":true, "projection":_p26_projection_value()}
		p26_action = run_action_slice()
		p26_last_player_entry = {"action":action_id, "input_event_class":event.get_class(), "world_control":true, "interaction_router":true, "task_projection_readonly":bool(task_projection().get("readonly", false)), "result_ok":bool(p26_action.get("ok", false))}
		if p26_action_button != null: p26_action_button.disabled = bool(p26_action.get("ok", false))
		return {"ok":bool(p26_action.get("ok", false)), "action":action_id, "entry":p26_last_player_entry.duplicate(true), "result":p26_action}
	return {"ok":false, "code":"p26.player_action_unknown", "reason_zh":"P26正式入口不认识该玩家动作。"}

func _build_p26_runtime_controls() -> void:
	if ui_root == null or p26_production_button != null: return
	p26_production_button = Button.new()
	p26_production_button.name = "P26ProductionControl"
	p26_production_button.text = "执行职责 / 生产"
	p26_production_button.position = Vector2(750.0, 116.0)
	p26_production_button.size = Vector2(150.0, 42.0)
	p26_production_button.tooltip_text = "通过正式InputEvent、Task/InteractionRouter与AbilityRequest执行生产闭环。"
	p26_production_button.pressed.connect(func(): _dispatch_p26_world_control("gm.p26.production"))
	ui_root.add_child(p26_production_button)
	p26_recovery_button = Button.new()
	p26_recovery_button.name = "P26RecoveryControl"
	p26_recovery_button.text = "调整容量并继续"
	p26_recovery_button.position = Vector2(750.0, 162.0)
	p26_recovery_button.size = Vector2(140.0, 42.0)
	p26_recovery_button.tooltip_text = "在正式容量规则调整后显式重试被阻断的库存职责。"
	p26_recovery_button.pressed.connect(func(): _dispatch_p26_world_control("gm.p26.recovery"))
	ui_root.add_child(p26_recovery_button)
	p26_action_button = Button.new()
	p26_action_button.name = "P26ActionControl"
	p26_action_button.text = "进入中性行动"
	p26_action_button.position = Vector2(912.0, 116.0)
	p26_action_button.size = Vector2(160.0, 42.0)
	p26_action_button.tooltip_text = "通过世界Task与TaskExecutionContext进入中性SceneSession。"
	p26_action_button.pressed.connect(func(): _dispatch_p26_world_control("gm.p26.action"))
	ui_root.add_child(p26_action_button)
	var panel := PanelContainer.new()
	panel.name = "P26ReadonlyProjectionPanel"
	panel.position = Vector2(370.0, 172.0)
	panel.size = Vector2(330.0, 250.0)
	ui_root.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_%s" % side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new(); margin.add_child(column)
	p26_runtime_status = Label.new(); p26_runtime_status.text = "P26玩家入口已就绪"; column.add_child(p26_runtime_status)
	p26_readonly_projection = Label.new(); p26_readonly_projection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(p26_readonly_projection)
	p26_danger_feedback_label = Label.new(); p26_danger_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; p26_danger_feedback_label.text = "危险反馈：待命"; column.add_child(p26_danger_feedback_label)
	_refresh_p26_projection()

func _dispatch_p26_world_control(action_id: String) -> Dictionary:
	var event := InputEventAction.new()
	event.action = action_id
	event.pressed = true
	event.strength = 1.0
	return dispatch_input_event(event)

func _ensure_p26_input_map() -> void:
	var bindings := {"gm.p26.production":KEY_G, "gm.p26.recovery":KEY_R, "gm.p26.action":KEY_H}
	for action_id in bindings:
		if not InputMap.has_action(action_id): InputMap.add_action(action_id)
		if InputMap.action_get_events(action_id).is_empty():
			var key := InputEventKey.new(); key.physical_keycode = int(bindings[action_id]); InputMap.action_add_event(action_id, key)

func _p26_projection_value() -> Dictionary:
	var production_state := "完成" if bool(p26_production.get("ok", false)) else "已阻断" if p26_production_phase == "blocked" else "待执行"
	return {"readonly":true, "production_state":production_state, "action_state":"完成" if bool(p26_action.get("ok", false)) else "待执行", "task":task_projection(), "last_player_entry":p26_last_player_entry.duplicate(true), "production_feedback":p26_production_blocked.duplicate(true), "danger_feedback":p26_danger_feedback.duplicate(true)}

func _refresh_p26_projection() -> void:
	if p26_readonly_projection == null: return
	var projection := _p26_projection_value()
	p26_readonly_projection.text = "只读投影\n职责 / 生产：%s\n行动 / SceneSession：%s\nTask：%s" % [projection.production_state, projection.action_state, str(projection.task.get("state", "unknown"))]
	if p26_runtime_status != null:
		if p26_production_phase == "blocked":
			p26_runtime_status.text = "生产已阻断：%s\n下一步：%s" % [str(p26_production_blocked.get("reason_zh", "仓库容量不足。")), str(p26_production_blocked.get("next_step_zh", "请调整容量后继续。"))]
		elif not p26_last_player_entry.is_empty():
			p26_runtime_status.text = "玩家入口：%s" % str(p26_last_player_entry.get("action", ""))
			var reason_zh := str(p26_last_player_entry.get("reason_zh", ""))
			var next_step_zh := str(p26_last_player_entry.get("next_step_zh", ""))
			if not reason_zh.is_empty(): p26_runtime_status.text += "\n原因：%s" % reason_zh
			if not next_step_zh.is_empty(): p26_runtime_status.text += "\n下一步：%s" % next_step_zh
	if p26_danger_feedback_label != null and not p26_danger_feedback.is_empty():
		p26_danger_feedback_label.text = "危险反馈：已送达正式表现消费者\nFact：%s\nPresentation：%s" % [str(p26_danger_feedback.get("source_fact_event_id", "")), str(p26_danger_feedback.get("presentation_id", ""))]

func _run_p26_contract() -> void:
	var blocked_phase := run_production_slice()
	var continued := _continue_production_after_rule_adjustment()
	p26_production = continued if bool(continued.get("ok", false)) else blocked_phase
	if bool(continued.get("ok", false)):
		p26_production["blocked_phase"] = blocked_phase.duplicate(true)
	p26_action = run_action_slice()
	var before_invalid := p26_inventory.snapshot() if p26_inventory != null else {}
	var invalid := before_invalid.duplicate(true)
	invalid["unexpected"] = true
	var invalid_restore := p26_inventory.restore_snapshot(invalid) if p26_inventory != null else {"ok": false}
	var ext10_compatible := vertical_ready and npc_rows.size() == sample_profile.actor_specs.size() and bool(_surface_contract().get("ok", false))
	var report := {
		"schema": CONTRACT_SCHEMA,
		"ok": bool(p26_production.get("ok", false)) and bool(p26_action.get("ok", false)) and ext10_compatible and not bool(invalid_restore.get("ok", false)) and p26_inventory.snapshot() == before_invalid,
		"production_slice": p26_production,
		"production_blocked_then_explicit_continue": {"blocked":blocked_phase, "continued":continued, "same_inventory_authority":p26_inventory != null and str(p26_inventory.store_id) == INVENTORY_STORE_ID},
		"action_slice": p26_action,
		"ext10_direct_reuse": {"profile_schema": sample_profile.SCHEMA, "npc_count": npc_rows.size(), "surface_contract": _surface_contract(), "second_3d_chain": false},
		"authority": {"task_store": task_service.STORE_ID, "inventory_store": INVENTORY_STORE_ID, "process_store": p26_process.process_store.STORE_ID if p26_process != null else "", "scene_session": "GMTaskExecutionSession", "save_root": "GMSimulationWorld/GMStore", "second_authority": false},
		"negative_restore": {"rejected": not bool(invalid_restore.get("ok", false)), "state_unchanged": p26_inventory.snapshot() == before_invalid},
	}
	_write_requested_evidence("GM_P26_CONTRACT_JSON", report)
	print("P26_CONTRACT_RESULT " + JSON.stringify(report))
	get_tree().quit(0 if bool(report.ok) else 1)

func run_production_slice(moved_through_formal_input: bool = false) -> Dictionary:
	if p26_production_phase == "complete" and not p26_production.is_empty():
		return p26_production.duplicate(true)
	if p26_production_phase == "blocked":
		return p26_production_blocked.duplicate(true)
	var moved := p26_player_moved_through_input if moved_through_formal_input else false
	if not moved_through_formal_input:
		var player_start := player.position
		drive_direction(Vector2.RIGHT)
		advance_simulation(0.3)
		drive_direction(Vector2.ZERO)
		moved = player.position.distance_to(player_start) > 1.0
	if not moved:
		var unchanged_task := task_service.snapshot() if task_service != null else {}
		var unchanged_inventory := p26_inventory.snapshot() if p26_inventory != null else {}
		var unchanged_authority := task_service.fact_store.snapshot() if task_service != null else {}
		return {"ok":false, "phase":"precondition_blocked", "code":"p26.production.movement_required", "reason_zh":"生产职责的正式入口需要先完成一次玩家移动；本次未写入Task、Inventory、Fact、Process或Duty。", "next_step_zh":"请使用W/A/S/D移动玩家后，再点击“执行职责 / 生产”。", "failure_state_unchanged":(task_service == null or task_service.snapshot() == unchanged_task) and (p26_inventory == null or p26_inventory.snapshot() == unchanged_inventory) and (task_service == null or task_service.fact_store.snapshot() == unchanged_authority), "wrote_domain_facts":false}
	var upper_assignment := assign_task("gm.p26.production.upper.assign")
	if not _typed_success(upper_assignment):
		return _typed_failure(upper_assignment, "p26.upper_assignment_failed")
	var setup := _build_inventory_authority()
	if not setup.ok:
		return setup
	var player_pickup: Variant = _inventory_request(player_host, shell_configuration.player_id, "pickup", WORLD_CONTAINER_ID, PLAYER_CONTAINER_ID, SUPPLY_LOT_ID, 2, "gm.p26.production.player.pickup")
	if not player_pickup is GMCommittedFactResult:
		return _blocked_value(player_pickup, "p26.player_pickup_failed")
	var player_store: Variant = _inventory_request(player_host, shell_configuration.player_id, "store", PLAYER_CONTAINER_ID, WAREHOUSE_CONTAINER_ID, SUPPLY_LOT_ID, 2, "gm.p26.production.player.store")
	if not player_store is GMCommittedFactResult:
		return _blocked_value(player_store, "p26.player_store_failed")
	var process_setup := _build_shared_process()
	if not process_setup.ok:
		return process_setup
	var player_process := _complete_process(player_host, shell_configuration.player_id, "gm.p26.production.player", {"store_fact_id":player_store.fact_event.event_id, "actor_id":shell_configuration.player_id})
	if not player_process.ok:
		return player_process
	var player_typed_request: Dictionary = player_process.get("typed_domain_request", {}) if player_process.get("typed_domain_request", {}) is Dictionary else {}
	var player_process_identity := _typed_process_identity(player_typed_request, {"store_fact_id":player_store.fact_event.event_id, "actor_id":shell_configuration.player_id})
	if not player_process_identity.ok:
		return player_process_identity
	var duty := _publish_duty_task(player_typed_request, player_process_identity.get("identity", {}))
	if not duty.ok:
		return duty
	var npc_id := _select_production_actor_id()
	if npc_id.is_empty():
		return {"ok":false, "code":"p26.production.profile_no_actor", "reason_zh":"当前P26职责Profile没有可用的NPC执行者。"}
	var npc_host := GMAbilitySystemHost.new()
	var npc_assignment: Variant = _task_operation_via_router("assign", {"assignment_id":"gm.assignment.p26.inventory_maintenance", "task_id":duty.task_id, "assignee":{"type":"actor", "id":npc_id}, "kind":"actor"}, "player", shell_configuration.player_id, "gm.p26.production.npc.assign")
	if not _typed_success(npc_assignment):
		return _typed_failure(npc_assignment, "p26.npc_assignment_failed")
	var planner := _npc_plan(npc_id, str(duty.task_id))
	if not planner.ok:
		return planner
	p26_duty_task = duty.duplicate(true)
	p26_planner_request = planner.duplicate(true)
	var before_blocked := p26_inventory.snapshot()
	var plan: Dictionary = planner.get("plan", {}) if planner.get("plan", {}) is Dictionary else {}
	var plan_context: Dictionary = plan.get("target_context", {}) if plan.get("target_context", {}) is Dictionary else {}
	var blocked: Variant = _inventory_request(npc_host, npc_id, str(plan_context.get("operation", "store")), str(plan_context.get("source_container_id", NPC_CONTAINER_ID)), str(plan_context.get("target_container_id", WAREHOUSE_CONTAINER_ID)), str(plan_context.get("lot_id", NPC_LOT_ID)), int(plan_context.get("quantity", 1)), "gm.p26.production.npc.store.blocked")
	var blocked_code: String = blocked.error_code if blocked is GMBlockedResult else str(blocked.get("code", "")) if blocked is Dictionary else ""
	var blocked_atomic := blocked is GMBlockedResult and p26_inventory.snapshot() == before_blocked
	p26_production_context = {"upper_assignment":_public_value(upper_assignment), "player_pickup_fact_id":player_pickup.fact_event.event_id, "player_store_fact_id":player_store.fact_event.event_id, "player_process":player_process.duplicate(true), "duty":duty.duplicate(true), "npc_id":npc_id, "npc_assignment":_public_value(npc_assignment), "planner":planner.duplicate(true), "moved":moved, "before_blocked_inventory_version":p26_inventory.version}
	p26_production_blocked = {"ok":false, "phase":"blocked", "code":"p26.production.capacity_blocked", "blocked_code":blocked_code, "reason_zh":"仓库容量已满；NPC库存维护在正式Inventory预检阶段被阻断，未产生部分写入。", "next_step_zh":"请点击“调整容量并继续”，用同一Planner计划重试。", "blocked_result":_public_value(blocked), "blocked_atomic":blocked_atomic, "failure_state_unchanged":blocked_atomic, "wrote_domain_facts":false, "duty_task_id":str(duty.task_id), "duty_assignment_id":str(duty.assignment_id), "npc_id":npc_id, "planner_plan_id":str(plan.get("plan_id", "")), "planner_request":planner.duplicate(true), "moved":moved}
	p26_production_phase = "blocked"
	return p26_production_blocked.duplicate(true)

func _continue_production_after_rule_adjustment() -> Dictionary:
	if p26_production_phase == "complete" and not p26_production.is_empty():
		return p26_production.duplicate(true)
	if p26_production_phase != "blocked":
		return {"ok":false, "phase":"recovery_waiting", "code":"p26.production.recovery_without_block", "reason_zh":"当前没有等待容量调整的P26生产阻断。", "next_step_zh":"先通过正式玩家入口执行一次生产职责。", "wrote_domain_facts":false}
	if p26_inventory == null:
		return {"ok":false, "code":"p26.production.inventory_authority_missing", "reason_zh":"恢复时P26 Inventory权威缺失，未写入任何事实。", "next_step_zh":"重新打开正式世界后再重试。", "wrote_domain_facts":false}
	var context := p26_production_context.duplicate(true)
	if context.is_empty():
		context = {"duty":p26_production_blocked.get("duty", {}), "npc_id":str(p26_production_blocked.get("npc_id", "")), "planner":p26_production_blocked.get("planner_request", {}), "moved":bool(p26_production_blocked.get("moved", false)), "upper_assignment":{}}
	var npc_id := str(context.get("npc_id", ""))
	var planner: Dictionary = context.get("planner", {}) if context.get("planner", {}) is Dictionary else {}
	var plan: Dictionary = planner.get("plan", {}) if planner.get("plan", {}) is Dictionary else {}
	var plan_context: Dictionary = plan.get("target_context", {}) if plan.get("target_context", {}) is Dictionary else {}
	if npc_id.is_empty() or plan.is_empty():
		return {"ok":false, "code":"p26.production.recovery_context_missing", "reason_zh":"恢复缺少原Planner计划或NPC身份，拒绝重建第二套Store。", "next_step_zh":"返回正式生产入口重新生成计划。", "wrote_domain_facts":false}
	var adjusted := _apply_capacity_rule(int(planning_rules.get("recovery_warehouse_slot_limit")))
	if not adjusted.ok:
		return adjusted
	var npc_host := GMAbilitySystemHost.new()
	var recovered: Variant = _inventory_request(npc_host, npc_id, str(plan_context.get("operation", "store")), str(plan_context.get("source_container_id", NPC_CONTAINER_ID)), str(plan_context.get("target_container_id", WAREHOUSE_CONTAINER_ID)), str(plan_context.get("lot_id", NPC_LOT_ID)), int(plan_context.get("quantity", 1)), "gm.p26.production.npc.store.recovered")
	if not recovered is GMCommittedFactResult:
		return _blocked_value(recovered, "p26.npc_store_recovery_failed")
	var process_key := "gm.p26.production.npc.%s" % str(plan.get("plan_id", "recovery"))
	var npc_process := _complete_process(npc_host, npc_id, process_key, {"planner_plan_id":str(plan.get("plan_id", "")), "inventory_fact_id":recovered.fact_event.event_id})
	if not npc_process.ok:
		return npc_process
	var duty: Dictionary = context.get("duty", {}) if context.get("duty", {}) is Dictionary else {}
	var duty_task_id := str(duty.get("task_id", p26_production_blocked.get("duty_task_id", "")))
	var duty_assignment_id := str(duty.get("assignment_id", p26_production_blocked.get("duty_assignment_id", "")))
	var duty_consumption := _consume_committed_signal_for_task(recovered, duty_task_id, duty_assignment_id, "gm.p26.production.duty.signal", "p26.duty.inventory_completed")
	if not duty_consumption.ok:
		return duty_consumption
	p26_typed_process_results.append(npc_process.duplicate(true))
	p26_production_phase = "complete"
	p26_production_blocked["resolved"] = true
	p26_production_blocked["rule_adjustment"] = adjusted.duplicate(true)
	p26_production_blocked["recovered_fact_id"] = recovered.fact_event.event_id
	p26_production_blocked["duty_consumption"] = duty_consumption.duplicate(true)
	var warehouse := p26_inventory.get_container(WAREHOUSE_CONTAINER_ID)
	var result := {"ok":bool(context.get("moved", false)) and bool(p26_production_blocked.get("blocked_atomic", false)) and warehouse != null and warehouse.slot_count() == 2 and duty_consumption.ok, "phase":"complete", "flow":["上游搬运Task", "玩家移动", "拾取", "搬运入库", "通用Process", "中性职责事实", "Duty库存维护Task", "玩家指派NPC", "Planner请求", "同一Ability", "容量满Blocked", "正式容量规则调整", "恢复完成", "Task.consume_committed_signal", "Duty Task完成"], "upper_task":task_projection(), "player":{"moved":bool(context.get("moved", false)), "ability_id":CARRY_ABILITY_ID, "pickup_fact_id":str(context.get("player_pickup_fact_id", "")), "store_fact_id":str(context.get("player_store_fact_id", "")), "process":context.get("player_process", {})}, "duty":duty, "npc":{"actor_id":npc_id, "plan_id":str(plan.get("plan_id", "")), "ability_id":str(plan.get("ability_id", "")), "assignment_committed":not str(context.get("npc_assignment", {})).is_empty(), "blocked_code":str(p26_production_blocked.get("blocked_code", "")), "blocked_atomic":bool(p26_production_blocked.get("blocked_atomic", false)), "rule_adjustment":adjusted, "recovered_fact_id":recovered.fact_event.event_id, "process":npc_process, "typed_domain_request":npc_process.get("typed_domain_request", {}), "planner_request":planner, "task_consumption":duty_consumption, "causal_identity":{"planner_plan_id":str(plan.get("plan_id", "")), "inventory_fact_id":recovered.fact_event.event_id, "inventory_transaction_id":recovered.transaction_id, "process_instance_id":str(npc_process.get("instance_id", ""))}}, "inventory":{"store_id":p26_inventory.store_id, "warehouse_slots":warehouse.slot_count() if warehouse != null else -1, "warehouse_capacity":warehouse.slot_limit if warehouse != null else -1}}
	p26_production = result.duplicate(true)
	return result

func run_action_slice() -> Dictionary:
	if not p26_action.is_empty() and bool(p26_action.get("ok", false)):
		return p26_action.duplicate(true)
	if p26_action_session != null and str(p26_action_session.state.phase) == "returned" and not p26_action.is_empty():
		return p26_action.duplicate(true)
	if p26_inventory == null:
		var inventory_setup := _build_inventory_authority()
		if not inventory_setup.ok: return inventory_setup
	var world_task := _publish_world_task()
	if not world_task.ok:
		return world_task
	var opened := _open_action_session(str(world_task.task_id), str(world_task.assignment_id))
	if not opened.ok:
		return opened
	p26_action_session = opened.session
	var started := p26_action_session.start()
	if not started.ok:
		return started
	var session_id := str(p26_action_session.state.session_id)
	var explore := GMExecutionFacts.new("gm.fact.p26.action.explore", session_id, 1, "exploration", {"type":"actor", "id":shell_configuration.player_id}, {"type":"world_node", "id":"gm.world_node.p26.survey"}, {"danger":"present"}, {"collect":0}, [], ["neutral", "explore"], {})
	var explored := p26_action_session.record_fact(explore)
	if not explored.ok:
		return explored
	var combat := _combat_case(true, npc_rows[0] if not npc_rows.is_empty() else {})
	if not combat.ok:
		return combat
	var presentation := _present_p26_danger_feedback(combat)
	if not presentation.ok:
		return presentation
	var collect := GMExecutionFacts.new("gm.fact.p26.action.collect", session_id, 2, "objective_progress", {"type":"actor", "id":shell_configuration.player_id}, {"type":"world_node", "id":"gm.world_node.p26.survey"}, {"npc_id":"gm.actor.p26.field_contact", "contact_state":"located"}, {"collect":1}, [], ["neutral", "collect"], {})
	var collected := p26_action_session.record_fact(collect)
	if not collected.ok:
		return collected
	var extracted := p26_action_session.request_extraction("scene.extraction.p26.voluntary", "玩家与队友完成采集后主动撤离。")
	if not extracted.ok:
		return extracted
	var returned := p26_action_session.request_return("scene.return.p26.completed", "行动结果返回中性世界节点。")
	if not returned.ok:
		return returned
	var reward: Variant = _reward_after_result(str(extracted.result.get("status", "")))
	if not reward is GMCommittedFactResult:
		return _blocked_value(reward, "p26.action_reward_failed")
	var world_consumption := _consume_committed_signal_for_task(reward, str(world_task.task_id), str(world_task.assignment_id), "gm.p26.action.reward.signal", "p26.world_collection_completed")
	if not world_consumption.ok:
		return world_consumption
	return {
		"ok": str(extracted.result.get("status", "")) in ["partial_success", "extracted"] and str(p26_action_session.state.phase) == "returned" and combat.ok and presentation.ok and world_consumption.ok,
		"flow": ["世界节点Task", "TaskExecutionContext", "中性SceneRecipe", "玩家与队友进入", "探索", "采集", "Combat committed Fact/Change/Cue", "正式危险表现消费者", "撤离", "TaskExecutionResult", "Reward Fact", "Task.consume_committed_signal", "世界Task完成"],
		"world_task":world_task,
		"session": {"session_id":session_id, "participants":2, "recipe_id":"gm.recipe.p26.neutral_field", "result":extracted.result, "return_context":returned.return_context},
		"danger_feedback":combat,
		"presentation_feedback":presentation,
		"task_consumption":world_consumption,
		"updates": {"world_fact_id":"gm.fact.p26.action.explore", "npc_fact_id":"gm.fact.p26.action.collect", "reward_fact_id":reward.fact_event.event_id, "reward_committed_after_result":true},
	}

func _build_inventory_authority() -> Dictionary:
	if p26_inventory != null:
		return {"ok":true, "reused":true, "store_id":p26_inventory.store_id, "version":p26_inventory.version}
	p26_inventory = GMInventoryStore.new(INVENTORY_STORE_ID)
	var supply_definition := GMItemDefinition.new().configure("gm.item.p26.neutral_supply", PackedStringArray(["gm.item.material", "gm.p26.neutral"]), {"display_name_zh":"中性补给箱", "stackable":true, "max_stack":99})
	var parts_definition := GMItemDefinition.new().configure("gm.item.p26.neutral_parts", PackedStringArray(["gm.item.material", "gm.p26.neutral"]), {"display_name_zh":"中性维护件", "stackable":true, "max_stack":99})
	var supply_provenance := GMProvenanceRecord.new().configure("gm.provenance.p26.supply", "gm.fact.p26.world.supply", "starting", [], ["gm.fact.p26.world.supply"], {"source_label":"neutral_world_node"})
	var parts_provenance := GMProvenanceRecord.new().configure("gm.provenance.p26.parts", "gm.fact.p26.duty.parts", "production", [], ["gm.fact.p26.duty.parts"], {"source_label":"neutral_duty"})
	var supply_lot := GMItemLot.new().configure(SUPPLY_LOT_ID, supply_definition.definition_id, 2, 100, {}, supply_definition.tags, supply_provenance.provenance_id, "gm.fact.p26.world.supply")
	var npc_lot := GMItemLot.new().configure(NPC_LOT_ID, parts_definition.definition_id, 1, 100, {}, parts_definition.tags, parts_provenance.provenance_id, "gm.fact.p26.duty.parts")
	var world := GMInventoryContainer.new().configure(WORLD_CONTAINER_ID, "semantic_drop", 8); world.add_quantity("lot", SUPPLY_LOT_ID, 2)
	var player_container := GMInventoryContainer.new().configure(PLAYER_CONTAINER_ID, "character", 4)
	var npc_container := GMInventoryContainer.new().configure(NPC_CONTAINER_ID, "character", 4); npc_container.add_quantity("lot", NPC_LOT_ID, 1)
	if planning_rules == null or not planning_rules.has_method("validate") or not bool(planning_rules.call("validate").get("ok", false)):
		return {"ok":false, "code":"p26.planning_rules_invalid", "reason_zh":"正式P26策划规则资源缺失或无效。"}
	var warehouse := GMInventoryContainer.new().configure(WAREHOUSE_CONTAINER_ID, "storage", int(planning_rules.get("initial_warehouse_slot_limit")))
	var rows := [
		p26_inventory.register_definition(supply_definition), p26_inventory.register_definition(parts_definition),
		p26_inventory.register_provenance(supply_provenance), p26_inventory.register_provenance(parts_provenance),
		p26_inventory.register_lot(supply_lot), p26_inventory.register_lot(npc_lot),
		p26_inventory.register_ownership(GMOwnershipRecord.new().configure(GMOwnershipRecord.make_id("lot", SUPPLY_LOT_ID), "lot", SUPPLY_LOT_ID, "gm.world.p26", "gm.world.p26", WORLD_CONTAINER_ID, "world", "gm.fact.p26.world.supply", ["gm.fact.p26.world.supply"])),
		p26_inventory.register_ownership(GMOwnershipRecord.new().configure(GMOwnershipRecord.make_id("lot", NPC_LOT_ID), "lot", NPC_LOT_ID, str(sample_profile.actor_specs[0].actor_id), str(sample_profile.actor_specs[0].actor_id), NPC_CONTAINER_ID, "owned", "gm.fact.p26.duty.parts", ["gm.fact.p26.duty.parts"])),
		p26_inventory.register_container(world), p26_inventory.register_container(player_container), p26_inventory.register_container(npc_container), p26_inventory.register_container(warehouse),
	]
	for row in rows:
		if not bool(row.get("ok", false)):
			return row
	return {"ok":true}

func _inventory_request(host: GMAbilitySystemHost, actor_id: String, operation: String, source_container: String, target_container: String, lot_id: String, quantity: int, key: String) -> Variant:
	var event_data := {"p19_operation":operation, "inventory_operation":operation, "item_kind":"lot", "item_id":lot_id, "source_container_id":source_container, "target_container_id":target_container, "quantity":quantity, "source_id":actor_id, "target_id":target_container}
	var request := GMAbilityActivationRequest.new(host, CARRY_ABILITY_ID, "", null, event_data, actor_id, {}, key)
	var instance_id := request.derive_instance_id(); request.event_data["ability_instance_id"] = instance_id
	var bound := request.causal_chain.bind_ability_instance_identity(instance_id)
	if not bound.ok: return bound
	var linked := request.causal_chain.add_ref(GMCausalRef.ability_instance(instance_id, request.ability_id), [request.request_id])
	if not linked.ok: return linked
	var facts := task_service.fact_store
	return GMDomainTransactionCoordinator.new().resolve(request, GMP19TransactionResolver.new(p26_inventory, GMNumericResourceStore.new()), facts, facts.change_store, {"resolver_id":"gm.resolver.p19.transaction", "fact_type":"gm.fact.p26.inventory.%s" % operation, "source_system":"gm.p26.neutral_slice", "ability_id":request.ability_id, "ability_instance_id":instance_id}, request.causal_chain)

func _build_shared_process() -> Dictionary:
	if p26_process != null:
		return {"ok":true, "reused":true, "process_store":p26_process.process_store.STORE_ID}
	p26_process = GMProcessService.new(GMProcessStore.new(), GMProcessClock.new("turn", 0))
	var definition := GMProcessDefinition.new()
	definition.definition_id = "gm.process.p26.inventory_maintenance"
	definition.revision = 1
	definition.display_name_zh = "中性库存维护"
	definition.process_family = "production"
	definition.duration_units = 2
	definition.capability_ids = PackedStringArray([CARRY_ABILITY_ID])
	definition.completion_kind = "typed_domain_request"
	definition.completion_payload = {"request_type":"gm.domain.p26.inventory_maintained", "warehouse_id":WAREHOUSE_CONTAINER_ID}
	definition.task_definition_id = "gm.definition.p26.inventory_maintenance"
	definition.duty_provider_id = "gm.duty.p26.inventory_maintenance"
	return p26_process.register_definition(definition)

func _complete_process(host: GMAbilitySystemHost, actor_id: String, key: String, causal_context: Dictionary = {}) -> Dictionary:
	var started := p26_process.request(GMProcessAbilityAdapter.start(host, "gm.process.p26.inventory_maintenance", actor_id, "%s.start" % key))
	if not started.ok: return started
	if str(started.get("state", "")) == GMProcessState.COMPLETED:
		var completed_instance: Dictionary = started.get("instance", {}) if started.get("instance", {}) is Dictionary else {}
		return {"ok":true, "duplicate":true, "idempotent":true, "instance_id":str(completed_instance.get("instance_id", "")), "state":str(started.get("state", "")), "ability_contract":CARRY_ABILITY_ID, "typed_domain_request":completed_instance.get("result", {}), "causal_context":causal_context.duplicate(true)}
	var instance_id := str(started.instance.instance_id)
	var participated := p26_process.request(GMProcessAbilityAdapter.action(host, "participate", instance_id, actor_id, "%s.participate" % key, actor_id))
	if not participated.ok: return participated
	var completed := p26_process.advance(instance_id, 2)
	return {"ok":bool(completed.get("ok", false)), "instance_id":instance_id, "state":str(completed.get("state", "")), "ability_contract":CARRY_ABILITY_ID, "typed_domain_request":completed.get("result", {}) if completed.get("result", {}) is Dictionary else {}, "process_result":completed.duplicate(true), "causal_context":causal_context.duplicate(true)}

func _typed_process_identity(value: Variant, extra: Dictionary = {}) -> Dictionary:
	if not value is Dictionary:
		return {"ok":false, "code":"p26.process.typed_request_missing", "reason_zh":"Process完成没有返回可消费的typed_domain_request。", "next_step_zh":"请从同一Process完成收据进入职责发布。"}
	var typed: Dictionary = value
	var request_value: Variant = typed.get("request", {})
	if str(typed.get("kind", "")) != "typed_domain_request" or not bool(typed.get("ok", false)) or not request_value is Dictionary:
		return {"ok":false, "code":"p26.process.typed_request_invalid", "reason_zh":"Process typed_domain_request结构无效，职责发布已拒绝。", "next_step_zh":"请使用现有ProcessDefinition的类型化完成请求。"}
	var request: Dictionary = request_value
	var process_instance_id := str(typed.get("process_instance_id", ""))
	var request_type := str(request.get("request_type", ""))
	var warehouse_id := str(request.get("warehouse_id", ""))
	var idempotency_key := str(typed.get("idempotency_key", ""))
	if process_instance_id.is_empty() or request_type != "gm.domain.p26.inventory_maintained" or warehouse_id != WAREHOUSE_CONTAINER_ID or idempotency_key.is_empty():
		return {"ok":false, "code":"p26.process.typed_request_identity_invalid", "reason_zh":"Process typed_domain_request缺少一致的Process、request_type或warehouse身份。", "next_step_zh":"请重新读取同一Process完成收据，不要手写职责输入。"}
	var identity := {"process_instance_id":process_instance_id, "request_type":request_type, "warehouse_id":warehouse_id, "idempotency_key":idempotency_key}
	for key in extra:
		identity[str(key)] = extra[key]
	return {"ok":true, "typed_domain_request":typed.duplicate(true), "identity":identity}

func _publish_duty_task(typed_domain_request_value: Variant = {}, causal_identity: Dictionary = {}) -> Dictionary:
	var typed_checked := _typed_process_identity(typed_domain_request_value, causal_identity)
	if not typed_checked.ok: return typed_checked
	var typed_domain_request: Dictionary = typed_checked.get("typed_domain_request", {})
	var event_identity: Dictionary = typed_checked.get("identity", {}).duplicate(true)
	var definition := GMTaskDefinition.new()
	definition.definition_id = "gm.definition.p26.inventory_maintenance"
	definition.display_name_zh = "保持中性仓库库存"
	definition.description_zh = "由中性职责事实产生，并可由玩家指派NPC执行。"
	definition.objectives = [{"objective_id":"gm.objective.p26.inventory_maintenance", "display_name_zh":"完成一次库存维护", "signal_kind":"fact", "signal_type":"gm.fact.p26.inventory.store", "target_value":1, "contribution_field":"quantity", "target_match":{}}]
	definition.allowed_source_types = ["duty_provider"]
	definition.default_context_mode = "summary"
	var registered: Variant = task_service.submit_operation(player_host, "register_definition", definition.to_dict(), "script", shell_configuration.player_id, "gm.p26.duty.definition.register")
	if not _typed_success(registered): return _typed_failure(registered, "p26.duty_definition_failed")
	var provider: Variant = task_service.submit_operation(player_host, "register_duty_provider", {"provider_id":"gm.duty.p26.inventory_maintenance", "definition_id":definition.definition_id, "event_type":"gm.fact.p26.role_granted", "key_field":"duty_key", "subject":{"type":"facility", "id":"gm.facility.p26.warehouse"}}, "script", shell_configuration.player_id, "gm.p26.duty.provider.register")
	if not _typed_success(provider): return _typed_failure(provider, "p26.duty_provider_failed")
	var event_data := {"duty_key":"gm.key.p26.inventory_maintenance", "typed_domain_request":typed_domain_request.duplicate(true), "causal_identity":event_identity.duplicate(true)}
	var event: Variant = task_service.submit_operation(player_host, "duty_event", {"provider_id":"gm.duty.p26.inventory_maintenance", "event_id":"gm.event.p26.role_granted", "event_type":"gm.fact.p26.role_granted", "active":true, "data":event_data}, "script", shell_configuration.player_id, "gm.p26.duty.event")
	if not _typed_success(event): return _typed_failure(event, "p26.duty_event_failed")
	var duty_task_id := ""
	var domain: Dictionary = task_service.domain_snapshot()
	for task_id in domain.get("tasks", {}):
		var task: Dictionary = domain.tasks[task_id]
		if str(task.get("definition_id", "")) == definition.definition_id:
			duty_task_id = str(task_id)
			break
	if duty_task_id.is_empty(): return {"ok":false, "code":"p26.duty_task_missing"}
	var task_domain: Dictionary = domain.get("tasks", {}) if domain.get("tasks", {}) is Dictionary else {}
	var duty_task: Dictionary = task_domain.get(duty_task_id, {}) if task_domain.get(duty_task_id, {}) is Dictionary else {}
	var execution_context: Dictionary = duty_task.get("execution_context", {}) if duty_task.get("execution_context", {}) is Dictionary else {}
	var stable_context: Dictionary = execution_context.get("stable_context", {}) if execution_context.get("stable_context", {}) is Dictionary else {}
	var consumed_request: Dictionary = stable_context.get("typed_domain_request", {}) if stable_context.get("typed_domain_request", {}) is Dictionary else {}
	var consumed_identity: Dictionary = stable_context.get("causal_identity", {}) if stable_context.get("causal_identity", {}) is Dictionary else {}
	var typed_request_consumed := consumed_request == typed_domain_request and consumed_identity == event_identity
	if not typed_request_consumed:
		return {"ok":false, "code":"p26.duty_typed_request_not_consumed", "reason_zh":"职责Task没有消费同一Process typed_domain_request。", "next_step_zh":"请检查GMTaskService Duty事件到Task上下文的正式接线。", "task_id":duty_task_id, "typed_domain_request":typed_domain_request, "causal_identity":event_identity, "consumed_request":consumed_request, "consumed_identity":consumed_identity}
	var event_public: Dictionary = _public_value(event) if _public_value(event) is Dictionary else {}
	var duplicate := bool(event_public.get("idempotent", false))
	return {"ok":true, "provider_id":"gm.duty.p26.inventory_maintenance", "role_fact":"gm.fact.p26.role_granted", "task_id":duty_task_id, "assignment_id":"gm.assignment.p26.inventory_maintenance", "typed_domain_request":typed_domain_request, "causal_identity":event_identity, "typed_request_consumed":true, "downstream_consumer":"GMTaskService._duty_event→Task.execution_context.stable_context", "duplicate":duplicate, "idempotent":duplicate}

func _npc_plan(npc_id: String, task_id: String) -> Dictionary:
	var candidate := {"candidate_id":"gm.candidate.p26.inventory_maintenance", "kind":"task", "task_id":task_id, "assignment_id":"gm.assignment.p26.inventory_maintenance", "reservation_id":"", "free_action_id":"", "ability_id":CARRY_ABILITY_ID, "target_context":{"kind":"facility", "facility_id":"gm.facility.p26.warehouse", "workspot_id":sample_profile.player_target_workspot_id, "operation":"store", "source_container_id":NPC_CONTAINER_ID, "target_container_id":WAREHOUSE_CONTAINER_ID, "lot_id":NPC_LOT_ID, "quantity":1, "actor_id":npc_id}, "contributions":{"source_duty":10.0,"urgency":5.0,"skill_tags":2.0,"preference":0.0,"distance":0.0,"resource_availability":1.0,"fatigue":0.0,"risk":0.0,"interrupt_cost":0.0,"schedule":1.0}, "hard_priority":10, "available":true, "blocked_reason":"", "retry_triggers":["inventory_capacity_changed"]}
	var schedule := GMScheduleContextProvider.build(1, "gm.schedule.p26.day", "gm.role.p26.worker", "gm.department.p26.neutral", ["gm.permission.p26.inventory"], {}, ["gm.window.p26.day"])
	return GMAgentPlanner.new().decide({"schema":GMAgentPlanner.CONTEXT_SCHEMA, "agent_id":npc_id, "logical_tick":1, "seed":sample_profile.seed, "sequence":1, "control_state":"ai", "action_state":"actionable", "candidates":[candidate], "schedule_context":schedule.schedule_context, "role_context":schedule.role_context, "department_context":schedule.department_context, "preference_context":schedule.preference_context, "random_offset_scale":0.0})

func _apply_capacity_rule(new_capacity: int) -> Dictionary:
	var warehouse := p26_inventory.get_container(WAREHOUSE_CONTAINER_ID)
	if warehouse == null: return {"ok":false, "code":"p26.warehouse_missing"}
	var before := warehouse.slot_limit
	if before == new_capacity:
		return {"ok":true, "idempotent":true, "operation":"正式容量规则调整", "before":before, "after":new_capacity, "through_inventory_definition":true, "formal_rule_resource":planning_rules.resource_path, "rule_id":str(planning_rules.get("rule_id"))}
	warehouse.slot_limit = new_capacity
	var applied := p26_inventory.register_container(warehouse)
	return {"ok":bool(applied.get("ok", false)), "operation":"正式容量规则调整", "before":before, "after":new_capacity, "through_inventory_definition":true, "formal_rule_resource":planning_rules.resource_path, "rule_id":str(planning_rules.get("rule_id"))}

func _publish_world_task() -> Dictionary:
	var participant_actor_id := _select_action_participant_id()
	if participant_actor_id.is_empty():
		return {"ok":false, "code":"p26.action.profile_no_actor", "reason_zh":"当前P26行动Profile没有可用的NPC参与者。"}
	var definition := GMTaskDefinition.new()
	definition.definition_id = "gm.definition.p26.world_collection"
	definition.display_name_zh = "调查中性世界节点"
	definition.description_zh = "进入中性场景，探索、采集并安全撤离。"
	definition.objectives = [{"objective_id":"gm.objective.p26.world_collection", "display_name_zh":"采集一份中性样本", "signal_kind":"fact", "signal_type":"gm.fact.p26.action.reward", "target_value":1, "contribution_field":"quantity", "target_match":{}}]
	definition.allowed_source_types = ["world_event"]
	definition.default_context_mode = "scene"
	var registered: Variant = task_service.submit_operation(player_host, "register_definition", definition.to_dict(), "script", shell_configuration.player_id, "gm.p26.action.definition.register")
	if not _typed_success(registered): return _typed_failure(registered, "p26.action_definition_failed")
	var task_id := "gm.task.p26.world_collection"
	var published: Variant = task_service.submit_operation(player_host, "publish_task", {"task_id":task_id, "definition_id":definition.definition_id, "parent_task_id":"", "group_id":"", "execution_context":{"mode":"scene", "stable_context":{"world_node_id":"gm.world_node.p26.survey", "participants":[{"type":"actor","id":shell_configuration.player_id},{"type":"actor","id":participant_actor_id}], "seed":sample_profile.seed}}}, "world_event", "gm.world_node.p26.survey", "gm.p26.action.task.publish")
	if not _typed_success(published): return _typed_failure(published, "p26.action_task_publish_failed")
	var assignment_id := "gm.assignment.p26.world_collection"
	var assigned: Variant = _task_operation_via_router("assign", {"assignment_id":assignment_id, "task_id":task_id, "assignee":{"type":"actor","id":shell_configuration.player_id}, "kind":"actor"}, "player", shell_configuration.player_id, "gm.p26.action.task.assign")
	if not _typed_success(assigned): return _typed_failure(assigned, "p26.action_task_assign_failed")
	var execution := task_service.build_execution_request(player_host, task_id, assignment_id, "gm.ability.p26.enter_scene", {"source_id":shell_configuration.player_id, "target_id":"gm.world_node.p26.survey"}, "gm.p26.action.execution_request")
	var execution_request: Variant = execution.get("request", {})
	return {"ok":bool(execution.get("ok", false)), "task_id":task_id, "assignment_id":assignment_id, "source_type":"world_event", "execution_request":execution_request.to_dict() if execution_request is GMAbilityActivationRequest else {}}

func _open_action_session(task_id: String, assignment_id: String) -> Dictionary:
	var participant_actor_id := _select_action_participant_id()
	if participant_actor_id.is_empty():
		return {"ok":false, "code":"p26.action.profile_no_actor", "reason_zh":"当前P26行动Profile没有可用的NPC参与者。"}
	var domain := "gm.spatial.planar_3d"
	var entry := _spatial_target_native("anchor", shell_configuration.target_anchor_id, domain)
	var exit_ref := _spatial_target_native("anchor", shell_configuration.target_anchor_id, domain)
	var participants := [{"type":"actor","id":shell_configuration.player_id},{"type":"actor","id":participant_actor_id}]
	var context := GMTaskExecutionContext.new(task_id, assignment_id, "scene", {"type":"world_node","id":"gm.world_node.p26.survey"}, participants, [{"type":"resource","id":"gm.resource.p26.neutral_sample"}], {"allow_hostile_remaining":true}, sample_profile.seed, {})
	var slot_kinds := ["entry","exit","objective","resource","hostile","facility","extraction"]
	var skeleton_slots := []
	for kind in slot_kinds: skeleton_slots.append(GMSemanticSlot2D.new("gm.slot.p26.%s" % kind, kind).to_dict())
	var regions := [{"region_id":"gm.region.p26.neutral_field", "region_kind":"play_space", "required":true, "tags":["neutral"]}]
	var skeleton := GMSceneSkeletonDefinition.new("gm.skeleton.p26.neutral_field", "中性行动场景骨架", [domain], regions, skeleton_slots, ["survey_route"])
	var recipe_slots := [
		GMSemanticSlot2D.new("gm.slot.p26.entry", "entry", entry).to_dict(), GMSemanticSlot2D.new("gm.slot.p26.exit", "exit", exit_ref).to_dict(),
		GMSemanticSlot2D.new("gm.slot.p26.objective", "objective", {"type":"object","id":"gm.object.p26.neutral_sample"}).to_dict(), GMSemanticSlot2D.new("gm.slot.p26.resource", "resource", {"type":"resource","id":"gm.resource.p26.neutral_sample"}).to_dict(),
		GMSemanticSlot2D.new("gm.slot.p26.hostile", "hostile", {"type":"actor_group","id":"gm.actor_group.p26.hazard"}).to_dict(), GMSemanticSlot2D.new("gm.slot.p26.facility", "facility", {"type":"facility","id":"gm.facility.p26.field_station"}).to_dict(),
		GMSemanticSlot2D.new("gm.slot.p26.extraction", "extraction", exit_ref).to_dict(),
	]
	var recipe := GMSceneRecipe.new("gm.recipe.p26.neutral_field", "中性采集与寻人行动", skeleton.skeleton_id, entry, exit_ref, slot_kinds, [{"object_id":"gm.object.p26.neutral_sample","object_kind":"collectible","required":true,"tags":["neutral"]}], regions, recipe_slots, participants, [{"objective_id":"gm.objective.p26.collect","kind":"collect","target_value":2,"contribution_field":"collect","target_ref":{},"requires_hostile_clear":false}], [{"result_id":"gm.result.p26.success","status":"success","required_objective_ids":["gm.objective.p26.collect"],"reason_code":"scene.objectives.p26.completed"},{"result_id":"gm.result.p26.partial","status":"partial_success","required_objective_ids":[],"reason_code":"scene.extraction.p26.partial"},{"result_id":"gm.result.p26.extracted","status":"extracted","required_objective_ids":[],"reason_code":"scene.extraction.p26.voluntary"},{"result_id":"gm.result.p26.failed","status":"failed","required_objective_ids":[],"reason_code":"scene.execution.p26.failed"}], ["survey_route"])
	var definition := GMSceneSessionDefinition.new("gm.scene_definition.p26.neutral_field", task_id, assignment_id, context.to_dict(), skeleton.to_dict(), recipe.to_dict(), {})
	return GMTaskExecutionSession.open(definition, GMSceneRecipeBuilder.new(), adapter_3d)

func _select_action_participant_id() -> String:
	if sample_profile == null or sample_profile.actor_specs.is_empty():
		return ""
	# The first declared NPC is the stable fallback for the minimum supported
	# one-NPC Profile; larger Profiles retain the established second-NPC role.
	var participant_index := 1 if sample_profile.actor_specs.size() > 1 else 0
	return str(sample_profile.actor_specs[participant_index].actor_id)

func _select_production_actor_id() -> String:
	if sample_profile == null or sample_profile.actor_specs.is_empty():
		return ""
	return str(sample_profile.actor_specs[0].actor_id)

func _public_value(value: Variant) -> Variant:
	if value is GMCommittedFactResult or value is GMBlockedResult or value is GMInteractionResult:
		return value.to_dict()
	if value is Dictionary:
		return value.duplicate(true)
	if value is Array:
		return value.duplicate(true)
	return value

func _snapshot_diff_keys(left: Dictionary, right: Dictionary) -> Array:
	var all_keys: Dictionary = {}
	for key in left: all_keys[str(key)] = true
	for key in right: all_keys[str(key)] = true
	var differences: Array = []
	for key in all_keys:
		if GMStableData.canonical_json(left.get(key, null)) != GMStableData.canonical_json(right.get(key, null)): differences.append(str(key))
	return differences

func _consume_committed_signal_for_task(committed: GMCommittedFactResult, task_id: String, assignment_id: String, signal_key: String, completion_reason: String) -> Dictionary:
	if committed == null or committed.fact_event == null:
		return {"ok":false, "code":"p26.task_signal_missing", "reason_zh":"Task消费缺少Coordinator返回的CommittedFactResult。", "next_step_zh":"请从同一权威FactEventStore重新取得提交收据。"}
	if committed.authority_store != task_service.fact_store:
		return {"ok":false, "code":"p26.task_signal_authority_mismatch", "reason_zh":"Task消费拒绝跨FactEventStore提交结果。", "next_step_zh":"请使用P26绑定的唯一Task Fact authority。"}
	if task_id.is_empty() or assignment_id.is_empty():
		return {"ok":false, "code":"p26.task_signal_target_missing", "reason_zh":"Task消费缺少稳定Task或Assignment身份。", "next_step_zh":"请通过正式Task/Assignment入口重试。"}
	var task_before := task_service.read_task(task_id)
	if task_before.is_empty():
		return {"ok":false, "code":"p26.task_signal_task_missing", "reason_zh":"Task消费目标不存在，未写入任何Task状态。", "next_step_zh":"请重新发布并指派对应P26 Task。"}
	var fact_id := str(committed.fact_event.event_id)
	var identity := {"kind":"fact", "signal_id":fact_id}
	var consumed: Variant = task_service.consume_committed_signal(identity, signal_key, player_host, "gm.task.objective_adapter", committed)
	var consumed_public: Variant = _public_value(consumed)
	if not _typed_success(consumed):
		return {"ok":false, "code":"p26.task_signal_consume_failed", "reason_zh":"权威Fact已提交，但Objective Adapter拒绝消费该Task信号。", "next_step_zh":"请保留同一Fact身份并修复Task定义匹配后重试。", "task_id":task_id, "assignment_id":assignment_id, "signal":identity, "consume":consumed_public}
	var task_after_signal := task_service.read_task(task_id)
	var objectives: Dictionary = task_after_signal.get("objectives", {}) if task_after_signal.get("objectives", {}) is Dictionary else {}
	var objective_complete := false
	for objective_id in objectives:
		var progress: Dictionary = objectives[objective_id] if objectives[objective_id] is Dictionary else {}
		if bool(progress.get("complete", false)) or int(progress.get("current", 0)) >= int(progress.get("target", 0)):
			objective_complete = true
			break
	var transition_public: Variant = {"ok":true, "idempotent":true, "skipped":true, "reason":"Task已完成或无需再次转换。"}
	if objective_complete and str(task_after_signal.get("state", "")) != "completed":
		var transition_raw: Variant = task_service.submit_operation(player_host, "transition", {"task_id":task_id, "to_state":"completed", "reason_code":completion_reason, "result":{"signal_id":fact_id, "fact_event_id":fact_id, "transaction_id":committed.transaction_id, "causal_chain_id":committed.fact_event.causal_chain_id, "assignment_id":assignment_id, "source":"p26"}}, "script", shell_configuration.player_id, "%s.complete" % signal_key)
		transition_public = _public_value(transition_raw)
		if not _typed_success(transition_raw):
			return {"ok":false, "code":"p26.task_transition_failed", "reason_zh":"Objective已达到目标，但Task完成转换未通过正式TaskService。", "next_step_zh":"请使用同一Task/Assignment身份重试完成转换。", "task_id":task_id, "assignment_id":assignment_id, "signal":identity, "consume":consumed_public, "transition":transition_public}
	var task_after := task_service.read_task(task_id)
	return {"ok":str(task_after.get("state", "")) == "completed", "task_id":task_id, "assignment_id":assignment_id, "signal":{"kind":"fact", "signal_id":fact_id, "fact_event_id":fact_id, "transaction_id":committed.transaction_id, "causal_chain_id":committed.fact_event.causal_chain_id}, "consume":consumed_public, "task_before":task_before, "task_after_signal":task_after_signal, "transition":transition_public, "task_after":task_after, "duplicate":bool(consumed_public.get("idempotent", false)) if consumed_public is Dictionary else false}

func _present_p26_danger_feedback(combat: Dictionary) -> Dictionary:
	var package: Dictionary = combat.get("authority_package", {}) if combat.get("authority_package", {}) is Dictionary else {}
	var result_value: Dictionary = combat.get("result", {}) if combat.get("result", {}) is Dictionary else {}
	var fact_value: Dictionary = result_value.get("fact_event", {}) if result_value.get("fact_event", {}) is Dictionary else {}
	var fact_id := str(package.get("fact_event_id", fact_value.get("event_id", "")))
	if fact_id.is_empty():
		return {"ok":false, "code":"p26.danger_presentation_fact_missing", "reason_zh":"危险反馈缺少同一Combat提交Fact身份。", "next_step_zh":"请从正式Combat消费者重读权威提交包。"}
	var reader := GMFeedbackAuthorityReader.new(task_service.fact_store)
	var authority_read := reader.read_fact(fact_id)
	if not authority_read.ok:
		return {"ok":false, "code":"p26.danger_presentation_authority_read_failed", "reason_zh":"正式危险表现消费者无法读取权威Combat提交包。", "next_step_zh":"请检查Combat Fact/Change/Cue权威链后重试。", "authority_read":authority_read}
	package = authority_read.package
	var changes: Array = package.get("changes", []) if package.get("changes", []) is Array else []
	var cues: Array = package.get("cues", []) if package.get("cues", []) is Array else []
	var change_ids: Array = []
	for change in changes:
		if change is Dictionary: change_ids.append(str(change.get("change_id", "")))
	var cue_ids: Array = []
	for cue in cues:
		if cue is Dictionary: cue_ids.append(str(cue.get("cue_id", "")))
	var presentation_id := "gm.presentation.p26.danger.%s" % fact_id
	var presentation := {"schema":"gm.p26.danger_feedback.presentation.v1", "presentation_id":presentation_id, "consumer":"P26DangerPresentationConsumer", "status":"completed", "visible":true, "source_fact_event_id":fact_id, "source_transaction_id":str(package.get("transaction_id", "")), "source_causal_chain_id":str(package.get("causal_chain_id", "")), "source_change_ids":change_ids, "source_cue_ids":cue_ids, "domain_facts_written":false}
	p26_danger_feedback = presentation.duplicate(true)
	return {"ok":true, "consumer":"P26DangerPresentationConsumer", "presentation":presentation, "authority_read":authority_read, "presentation_receipt":{"presentation_id":presentation_id, "status":"completed", "source_fact_id":fact_id, "domain_facts_written":false}}

func _combat_case(force_hit: bool = true, source_flow: Dictionary = {}) -> Dictionary:
	var attack: GMCombatAttackDefinition = GMCombatAttackDefinition.new().configure(sample_profile.attack_id, "中性训练投射", "projectile", "damage", 5.0, 8.0, 0.0, "", "gm.projectile.ext3d10.neutral")
	var projectile: GMCombatProjectileDefinition = GMCombatProjectileDefinition.new().configure("gm.projectile.ext3d10.neutral", "中性训练投射物", 10.0, 2.0, 0.1, 1)
	var hit_query := GMPlanarCombatAdapter3D.new(map_backend_3d)
	var resolver := GMCombatResolver.new(null, hit_query)
	var attack_registered := resolver.register_attack(attack)
	var projectile_registered := resolver.register_projectile(projectile)
	if not attack_registered.ok or not projectile_registered.ok: return {"ok":false, "code":"sample.combat_definition_failed"}
	var surface_id := str(shell_configuration.surface_id)
	var combat_surface: GMSurfaceDefinition3D = surface_graph_3d.resolve_surface(surface_id)
	if combat_surface == null: return {"ok":false, "code":"sample.combat_surface_missing"}
	var source := GMPlanarPosition.new(shell_configuration.map_id, surface_id, 4.0, 4.0)
	var target := GMPlanarPosition.new(shell_configuration.map_id, surface_id, 7.0, 4.0)
	var source_world: Vector3 = combat_surface.logical_to_world(Vector2(4.0, 4.0))
	var target_world: Vector3 = combat_surface.logical_to_world(Vector2(7.0, 4.0))
	var combat_actor_id := str(source_flow.get("actor_id", sample_profile.actor_specs[0].actor_id))
	var hit: GMCombatHitSpec = GMCombatHitSpec.new().configure("gm.hit.ext3d10.neutral", "projectile", combat_actor_id, "gm.actor.ext3d10.training_target", {"x":1.0, "y":0.0}, 3.0, 8.0)
	var flow_refs := {"task_id":str(source_flow.get("task_id", "")), "plan_id":str(source_flow.get("plan_id", "")), "process_instance_id":str(source_flow.get("process_instance_id", "")), "process_state":str(source_flow.get("process_state", ""))}
	var request: GMCombatRequest = GMCombatRequest.new().configure("gm.combat.request.ext3d10.neutral", "gm.ext3d10.combat.%s" % str(force_hit), "realtime", hit.source_id, hit.target_id, "gm.ability.ext3d10.combat", attack.attack_id, hit, "", projectile.projectile_id, {}, {"upstream_flow":flow_refs})
	var context := {"source_position":source.to_native(), "target_position":target.to_native(), "source_world_y":source_world.y, "target_world":{"x":target_world.x, "y":target_world.y, "z":target_world.z}, "target_point":{"schema":"gm.combat.target_point_3d.v1", "target_point_id":"gm.target_point.ext3d10.training", "target_ref":hit.target_id, "map_id":shell_configuration.map_id, "surface_id":surface_id, "height_tolerance":0.75, "agent_profile":"default", "world_position":{"x":target_world.x, "y":target_world.y, "z":target_world.z}}, "force_hit":force_hit}
	var activation := GMAbilityActivationRequest.new(null, request.ability_id, "", null, {"source_id":request.source_id, "target_id":request.target_id, "combat_request":request.to_native(), "combat_query_context":context}, "gm.ext3d10.sample", {}, request.idempotency_key)
	var instance_id := activation.derive_instance_id()
	activation.event_data["ability_instance_id"] = instance_id
	var bound: Dictionary = activation.causal_chain.bind_ability_instance_identity(instance_id)
	if not bound.ok: return bound
	var linked: Dictionary = activation.causal_chain.add_ref(GMCausalRef.ability_instance(instance_id, activation.ability_id), [activation.request_id])
	if not linked.ok: return linked
	var facts := task_service.fact_store
	var changes := facts.change_store
	var coordinator := GMDomainTransactionCoordinator.new()
	var committed: Variant = coordinator.resolve(activation, resolver, facts, changes, {"resolver_id":resolver.resolver_id, "fact_type":GMCombatResolver.FACT_TYPE, "source_system":"gm.p26.formal_combat", "ability_id":activation.ability_id, "ability_instance_id":activation.event_data.ability_instance_id}, activation.causal_chain)
	var is_committed := committed is GMCommittedFactResult
	var authority_package := facts.get_committed_package(committed.fact_event.event_id) if is_committed else {}
	var authority_read := GMFeedbackAuthorityReader.new(facts).read_result(committed) if is_committed else {}
	return {"ok":is_committed, "status":"committed" if is_committed else "blocked", "fact_count":facts.get_record_count(), "change_count":facts.get_change_record_count(), "cue_count":committed.cues.size() if is_committed else 0, "result":_public_value(committed), "authority_package":authority_package, "authority_read":authority_read}

func _reward_after_result(result_status: String) -> Variant:
	var request := GMP19RewardAdapter.new().build_request(player_host, "gm.reward.p26.neutral_sample", "gm.receipt.p26.action.reward", "gm.world.p26", shell_configuration.player_id, "gm.p26.action.reward", "gm.item.p26.neutral_supply", PLAYER_CONTAINER_ID, 1, [], {"scene_result_status":result_status})
	var instance_id := request.derive_instance_id(); request.event_data["ability_instance_id"] = instance_id
	var bound := request.causal_chain.bind_ability_instance_identity(instance_id)
	if not bound.ok: return bound
	var linked := request.causal_chain.add_ref(GMCausalRef.ability_instance(instance_id, request.ability_id), [request.request_id])
	if not linked.ok: return linked
	return GMDomainTransactionCoordinator.new().resolve(request, GMP19TransactionResolver.new(p26_inventory, GMNumericResourceStore.new()), task_service.fact_store, task_service.fact_store.change_store, {"resolver_id":"gm.resolver.p19.transaction", "fact_type":"gm.fact.p26.action.reward", "source_system":"gm.p26.scene_result", "ability_id":request.ability_id, "ability_instance_id":instance_id}, request.causal_chain)

func _restore_p26_formal_start() -> void:
	var before_world: Dictionary = simulation_world.save_snapshot() if simulation_world != null else {}
	var restored := restore_world_snapshot()
	var after_world: Dictionary = simulation_world.save_snapshot() if simulation_world != null else {}
	var contributors: Array = player_shell_store.keys() if player_shell_store != null else []
	var inventory_expected := contributors.has("p26_inventory")
	var process_expected := contributors.has("p26_process")
	var session_expected := contributors.has("p26_action_session")
	var recovery_expected := contributors.has("p26_recovery_state")
	var action_summary_expected := contributors.has("p26_action_summary")
	var inventory_restored := not inventory_expected or p26_inventory != null
	var process_restored := not process_expected or p26_process != null
	var session_restored := not session_expected or p26_action_session != null
	var recovery_restored := not recovery_expected or p26_production_phase != "idle"
	var action_summary_restored := not action_summary_expected or not p26_action.is_empty()
	var report := {"schema":"gm.p26.ordinary_startup_restore.v1", "mode":"ordinary_startup_no_self_check_args", "ok":bool(restored.get("ok", false)) and inventory_restored and process_restored and session_restored and recovery_restored and action_summary_restored and process_service != null and resource_store != null and npc_rows.size() == sample_profile.actor_specs.size(), "path":shell_configuration.save_path, "restore":restored, "contributors":contributors, "contributors_expected":{"p26_inventory":inventory_expected, "p26_process":process_expected, "p26_action_session":session_expected, "p26_recovery_state":recovery_expected, "p26_action_summary":action_summary_expected}, "p26_inventory_restored":p26_inventory != null, "p26_process_restored":p26_process != null, "p26_scene_session_restored":p26_action_session != null, "p26_recovery_state_restored":recovery_restored, "p26_action_summary_restored":action_summary_restored, "ext10_process_restored":process_service != null, "ext10_resource_restored":resource_store != null, "ext10_npcs_restored":npc_rows.size() == sample_profile.actor_specs.size(), "p26_production_phase":p26_production_phase, "p26_action_phase":str(p26_action_session.state.phase) if p26_action_session != null else "", "failure_state_unchanged":bool(restored.get("ok", false)) or before_world == after_world, "single_save_root":true}
	p26_restore_result = report.duplicate(true)
	_refresh_p26_projection()
	_write_requested_evidence("GM_P26_NORMAL_RESTORE_JSON", report)
	print("P26_NORMAL_RESTORE_RESULT " + JSON.stringify(report))
	if not OS.get_environment("GM_P26_NORMAL_RESTORE_JSON").is_empty():
		get_tree().quit(0 if bool(report.get("ok", false)) else 1)

func _run_p26_save() -> void:
	var blocked_phase := run_production_slice()
	var continued := _continue_production_after_rule_adjustment()
	p26_production = continued if bool(continued.get("ok", false)) else blocked_phase
	if bool(continued.get("ok", false)):
		p26_production["blocked_phase"] = blocked_phase.duplicate(true)
	p26_action = run_action_slice()
	var saved := save_world_snapshot()
	var report := {"ok":bool(p26_production.get("ok", false)) and bool(p26_action.get("ok", false)) and bool(saved.get("ok", false)), "path":shell_configuration.save_path, "contributors":player_shell_store.keys(), "production":p26_production, "action":p26_action, "saved":saved, "single_save_root":true}
	_write_requested_evidence("GM_P26_SAVE_JSON", report)
	print("P26_SAVE_RESULT " + JSON.stringify(report))
	get_tree().quit(0 if bool(p26_production.get("ok", false)) and bool(p26_action.get("ok", false)) and bool(saved.get("ok", false)) else 1)

func _run_p26_restore() -> void:
	# Restore after the inherited EXT10 projection is built.  This preserves the
	# existing atomic world loader while avoiding a projection rebuild against a
	# half-restored task graph during _ready().
	var world_restored := restore_world_snapshot()
	if not bool(world_restored.get("ok", false)):
		var failed := {"ok":false, "code":"p26.world_restore_failed", "details":world_restored, "single_save_root":true}
		_write_requested_evidence("GM_P26_RESTORE_JSON", failed)
		print("P26_RESTORE_RESULT " + JSON.stringify(failed))
		get_tree().quit(1)
		return
	var inventory_value: Dictionary = player_shell_store.read("p26_inventory")
	var process_value: Dictionary = player_shell_store.read("p26_process")
	var session_value: Dictionary = player_shell_store.read("p26_action_session")
	var contributor_keys: Array = player_shell_store.keys() if player_shell_store != null else []
	var inventory_expected := contributor_keys.has("p26_inventory")
	var process_expected := contributor_keys.has("p26_process")
	var session_expected := contributor_keys.has("p26_action_session")
	var action_summary_expected := contributor_keys.has("p26_action_summary")
	var live_inventory_snapshot: Dictionary = p26_inventory.snapshot() if p26_inventory != null else {}
	var live_process_snapshot: Dictionary = p26_process.snapshot() if p26_process != null else {}
	var live_session_snapshot: Dictionary = p26_action_session.snapshot() if p26_action_session != null else {}
	var live_inventory_records: Dictionary = live_inventory_snapshot.get("records", {}) if live_inventory_snapshot.get("records", {}) is Dictionary else {}
	var saved_inventory_records: Dictionary = inventory_value.get("records", {}) if inventory_value.get("records", {}) is Dictionary else {}
	var live_process_store: Dictionary = live_process_snapshot.get("process_store", {}) if live_process_snapshot.get("process_store", {}) is Dictionary else {}
	var saved_process_store: Dictionary = process_value.get("process_store", {}) if process_value.get("process_store", {}) is Dictionary else {}
	var live_process_records: Dictionary = live_process_store.get("records", {}) if live_process_store.get("records", {}) is Dictionary else {}
	var saved_process_records: Dictionary = saved_process_store.get("records", {}) if saved_process_store.get("records", {}) is Dictionary else {}
	var live_session_state: Dictionary = live_session_snapshot.get("state", {}) if live_session_snapshot.get("state", {}) is Dictionary else {}
	var saved_session_state: Dictionary = session_value.get("state", {}) if session_value.get("state", {}) is Dictionary else {}
	var inventory_restored := {"ok":not inventory_expected or p26_inventory != null and str(live_inventory_snapshot.get("store_id", "")) == str(inventory_value.get("store_id", "")) and int(live_inventory_snapshot.get("version", -1)) == int(inventory_value.get("version", -1)) and int(live_inventory_snapshot.get("persistence_revision", -1)) == int(inventory_value.get("persistence_revision", -1)) and live_inventory_records.size() == saved_inventory_records.size(), "expected":inventory_expected, "reused_live_candidate":true}
	var process_restored := {"ok":not process_expected or p26_process != null and str(live_process_store.get("store_id", "")) == str(saved_process_store.get("store_id", "")) and str(live_process_snapshot.get("clock", {}).get("mode", "")) == str(process_value.get("clock", {}).get("mode", "")) and int(live_process_snapshot.get("clock", {}).get("value", -1)) == int(process_value.get("clock", {}).get("value", -1)) and live_process_records.size() == saved_process_records.size(), "expected":process_expected, "reused_live_candidate":true}
	var session_restored := {"ok":not session_expected or p26_action_session != null and str(live_session_state.get("session_id", "")) == str(saved_session_state.get("session_id", "")) and str(live_session_state.get("phase", "")) == str(saved_session_state.get("phase", "")) and int(live_session_state.get("sequence", -1)) == int(saved_session_state.get("sequence", -1)), "expected":session_expected, "reused_live_candidate":true}
	var authority_before_repeat := task_service.fact_store.snapshot()
	var reward_marker_count_before := JSON.stringify(authority_before_repeat).count("gm.fact.p26.action.reward")
	var second_inventory := GMInventoryStore.new(INVENTORY_STORE_ID)
	var repeated_inventory := second_inventory.restore_snapshot(inventory_value) if inventory_expected else {"ok":true, "skipped":true}
	var second_process := GMProcessService.new(GMProcessStore.new(), GMProcessClock.new("turn", 0))
	var repeated_process := second_process.restore_snapshot(process_value) if process_expected else {"ok":true, "skipped":true}
	var second_session_opened := _open_action_session("gm.task.p26.world_collection", "gm.assignment.p26.world_collection") if session_expected else {"ok":true, "skipped":true}
	var repeated_session: Dictionary = second_session_opened.session.restore_snapshot(session_value) if session_expected and bool(second_session_opened.get("ok", false)) else second_session_opened
	var authority_after_repeat := task_service.fact_store.snapshot()
	var inventory_same: bool = not inventory_expected or bool(repeated_inventory.get("ok", false)) and p26_inventory != null and str(second_inventory.store_id) == str(p26_inventory.store_id) and second_inventory.version == p26_inventory.version and second_inventory.snapshot().get("records", {}).size() == p26_inventory.snapshot().get("records", {}).size()
	var process_same: bool = not process_expected or bool(repeated_process.get("ok", false)) and p26_process != null and str(second_process.process_store.backend.store_id) == str(p26_process.process_store.backend.store_id) and str(second_process.snapshot().get("clock", {}).get("mode", "")) == str(p26_process.snapshot().get("clock", {}).get("mode", "")) and int(second_process.snapshot().get("clock", {}).get("value", -1)) == int(p26_process.snapshot().get("clock", {}).get("value", -1)) and second_process.snapshot().get("process_store", {}).get("records", {}).size() == p26_process.snapshot().get("process_store", {}).get("records", {}).size()
	var session_same: bool = not session_expected or bool(repeated_session.get("ok", false)) and p26_action_session != null and bool(second_session_opened.get("ok", false)) and str(second_session_opened.session.state.session_id) == str(p26_action_session.state.session_id) and str(second_session_opened.session.state.phase) == str(p26_action_session.state.phase) and int(second_session_opened.session.state.sequence) == int(p26_action_session.state.sequence)
	var authority_same: bool = authority_before_repeat == authority_after_repeat
	var reward_marker_count_after := JSON.stringify(authority_after_repeat).count("gm.fact.p26.action.reward")
	var reward_marker_same: bool = not action_summary_expected and reward_marker_count_before == reward_marker_count_after or action_summary_expected and reward_marker_count_before > 0 and reward_marker_count_before == reward_marker_count_after
	var ok: bool = persistence_loaded and inventory_restored.ok and process_restored.ok and session_restored.ok and inventory_same and process_same and session_same and authority_same and reward_marker_same
	var live_meta := {"inventory":{"live_store_id":str(live_inventory_snapshot.get("store_id", "")), "saved_store_id":str(inventory_value.get("store_id", "")), "live_version":int(live_inventory_snapshot.get("version", -1)), "saved_version":int(inventory_value.get("version", -1)), "live_persistence_revision":int(live_inventory_snapshot.get("persistence_revision", -1)), "saved_persistence_revision":int(inventory_value.get("persistence_revision", -1)), "live_record_count":live_inventory_records.size(), "saved_record_count":saved_inventory_records.size(), "diff_keys":_snapshot_diff_keys(live_inventory_snapshot, inventory_value)}, "process":{"live_store_id":str(live_process_store.get("store_id", "")), "saved_store_id":str(saved_process_store.get("store_id", "")), "live_record_count":live_process_store.get("record_count", -1), "saved_record_count":saved_process_store.get("record_count", -1), "live_clock":live_process_snapshot.get("clock", {}), "saved_clock":process_value.get("clock", {}), "diff_keys":_snapshot_diff_keys(live_process_snapshot, process_value)}, "session":{"live_session_id":str(live_session_state.get("session_id", "")), "saved_session_id":str(saved_session_state.get("session_id", "")), "live_phase":str(live_session_state.get("phase", "")), "saved_phase":str(saved_session_state.get("phase", "")), "live_sequence":int(live_session_state.get("sequence", -1)), "saved_sequence":int(saved_session_state.get("sequence", -1)), "diff_keys":_snapshot_diff_keys(live_session_snapshot, session_value)}}
	var report := {"ok":ok, "path":shell_configuration.save_path, "contributors_expected":{"p26_inventory":inventory_expected, "p26_process":process_expected, "p26_action_session":session_expected, "p26_action_summary":action_summary_expected}, "inventory":inventory_restored, "process":process_restored, "scene_session":session_restored, "live_meta":live_meta, "complete_repeated_restore":{"inventory":{"ok":inventory_same, "second_restore":repeated_inventory}, "process":{"ok":process_same, "second_restore":repeated_process}, "p26_scene_session":{"ok":session_same, "second_restore":repeated_session}, "fact_authority_unchanged":authority_same, "reward_marker_count_unchanged":{"ok":reward_marker_same, "before":reward_marker_count_before, "after":reward_marker_count_after}, "no_duplicate_fact_or_reward":authority_same and reward_marker_same}, "single_save_root":true}
	_write_requested_evidence("GM_P26_RESTORE_JSON", report)
	print("P26_RESTORE_RESULT " + JSON.stringify(report))
	get_tree().quit(0 if ok else 1)

func _capture_p25_contributors() -> Dictionary:
	var captured := super._capture_p25_contributors()
	if not captured.ok: return captured
	# Only canonical serializable authorities enter the existing P25 store.  The
	# verbose execution report contains RefCounted result objects and is evidence,
	# not save authority.
	var values: Array = []
	if p26_inventory != null: values.append(["p26_inventory", p26_inventory.snapshot()])
	if p26_process != null: values.append(["p26_process", p26_process.snapshot()])
	if p26_action_session != null: values.append(["p26_action_session", p26_action_session.snapshot()])
	if p26_production_phase != "idle":
		values.append(["p26_recovery_state", {"schema":"gm.p26.recovery_state.v1", "phase":p26_production_phase, "blocked":p26_production_blocked.duplicate(true), "context":p26_production_context.duplicate(true), "summary":p26_production.duplicate(true)}])
	if not p26_action.is_empty():
		var action_session_value: Dictionary = p26_action.get("session", {}) if p26_action.get("session", {}) is Dictionary else {}
		var action_updates: Dictionary = p26_action.get("updates", {}) if p26_action.get("updates", {}) is Dictionary else {}
		var action_presentation: Dictionary = p26_action.get("presentation_feedback", {}) if p26_action.get("presentation_feedback", {}) is Dictionary else {}
		var action_receipt: Dictionary = action_presentation.get("presentation_receipt", {}) if action_presentation.get("presentation_receipt", {}) is Dictionary else {}
		values.append(["p26_action_summary", {"schema":"gm.p26.action_summary.v1", "ok":bool(p26_action.get("ok", false)), "session_id":str(action_session_value.get("session_id", "")), "world_task_id":str(p26_action.get("world_task", {}).get("task_id", "")) if p26_action.get("world_task", {}) is Dictionary else "", "assignment_id":str(p26_action.get("world_task", {}).get("assignment_id", "")) if p26_action.get("world_task", {}) is Dictionary else "", "reward_fact_id":str(action_updates.get("reward_fact_id", "")), "danger_presentation":action_receipt.duplicate(true)}])
	for row in values:
		var written: Dictionary = player_shell_store.put(str(row[0]), row[1])
		if not written.ok: return written
	return {"ok":true, "store_id":P25_STORE_ID, "keys":player_shell_store.keys(), "record_count":player_shell_store.keys().size()}

func _prepare_p25_contributors(world_snapshot: Dictionary, staged_stores: Dictionary) -> Dictionary:
	var base := super._prepare_p25_contributors(world_snapshot, staged_stores)
	if not base.ok: return base
	var prepared: Dictionary = base.get("prepared", {}) if base.get("prepared", {}) is Dictionary else {}
	var shell_candidate: GMStore = prepared.get("shell_store", null)
	if shell_candidate == null:
		return _failure("p26.save.shell_candidate_missing", "P26无法在既有原子恢复边界读取玩家外壳Store候选。")
	var inventory_value: Dictionary = shell_candidate.read("p26_inventory")
	if not inventory_value.is_empty():
		var inventory_candidate := GMInventoryStore.new(INVENTORY_STORE_ID)
		var inventory_checked := inventory_candidate.restore_snapshot(inventory_value)
		if not inventory_checked.ok: return _failure("p26.save.contributor_prepare_invalid", "P26 Inventory候选未通过既有05B恢复合同。", {"contributor":"p26_inventory", "details":inventory_checked})
		prepared["p26_inventory"] = inventory_candidate
	var process_value: Dictionary = shell_candidate.read("p26_process")
	if not process_value.is_empty():
		var process_candidate := GMProcessService.new(GMProcessStore.new(), GMProcessClock.new("turn", 0))
		var process_checked := process_candidate.restore_snapshot(process_value)
		if not process_checked.ok: return _failure("p26.save.contributor_prepare_invalid", "P26 Process候选未通过既有Process恢复合同。", {"contributor":"p26_process", "details":process_checked})
		prepared["p26_process"] = process_candidate
	var session_value: Dictionary = shell_candidate.read("p26_action_session")
	if not session_value.is_empty():
		var session_opened := _open_action_session("gm.task.p26.world_collection", "gm.assignment.p26.world_collection")
		if not session_opened.ok: return _failure("p26.save.contributor_prepare_invalid", "P26 SceneSession候选无法从正式配方打开。", {"contributor":"p26_action_session", "details":session_opened})
		var session_checked: Dictionary = session_opened.session.prepare_snapshot(session_value)
		if not session_checked.ok: return _failure("p26.save.contributor_prepare_invalid", "P26 SceneSession候选未通过既有恢复合同。", {"contributor":"p26_action_session", "details":session_checked})
		prepared["p26_action_session"] = {"session":session_opened.session, "prepared":session_checked.get("prepared", {})}
	var profile_value: Dictionary = shell_candidate.read("ext3d10_profile")
	if not profile_value.is_empty() and not _profile_value_matches(profile_value):
		return _failure("p26.save.profile_mismatch", "EXT10 Profile候选与当前正式Profile不一致，原子恢复已拒绝。")
	var ext_process_value: Dictionary = shell_candidate.read("ext3d10_process")
	if not ext_process_value.is_empty():
		var ext_process_candidate := GMProcessService.new(GMProcessStore.new(), GMProcessClock.new("turn", 0))
		var ext_process_checked := ext_process_candidate.restore_snapshot(ext_process_value)
		if not ext_process_checked.ok: return _failure("p26.save.contributor_prepare_invalid", "EXT10 Process候选未通过既有恢复合同。", {"contributor":"ext3d10_process", "details":ext_process_checked})
		prepared["ext3d10_process"] = ext_process_candidate
	var resource_value: Dictionary = shell_candidate.read("ext3d10_resource")
	if not resource_value.is_empty():
		var resource_candidate := GMNumericResourceStore.new("gm.store.ext3d10.resource")
		var resource_checked := resource_candidate.restore_snapshot(resource_value)
		if not resource_checked.ok: return _failure("p26.save.contributor_prepare_invalid", "EXT10 Resource候选未通过既有恢复合同。", {"contributor":"ext3d10_resource", "details":resource_checked})
		prepared["ext3d10_resource"] = resource_candidate
	var npc_value: Dictionary = shell_candidate.read("ext3d10_npcs")
	if not npc_value.is_empty():
			var rows: Variant = npc_value.get("rows", [])
			if not rows is Array or rows.size() != sample_profile.actor_specs.size():
				return _failure("p26.save.npc_rows_invalid", "EXT10 NPC候选数量与当前Profile不一致，原子恢复已拒绝。")
			var seen: Dictionary = {}
			for row in rows:
				if not row is Dictionary or str(row.get("actor_id", "")).is_empty() or seen.has(str(row.get("actor_id", ""))):
					return _failure("p26.save.npc_rows_invalid", "EXT10 NPC候选缺少唯一稳定Actor身份，原子恢复已拒绝。")
				seen[str(row.get("actor_id", ""))] = true
			prepared["ext3d10_npcs"] = rows.duplicate(true)
	var recovery_value: Dictionary = shell_candidate.read("p26_recovery_state")
	if not recovery_value.is_empty(): prepared["p26_recovery_state"] = recovery_value.duplicate(true)
	var action_value: Dictionary = shell_candidate.read("p26_action_summary")
	if not action_value.is_empty(): prepared["p26_action_summary"] = action_value.duplicate(true)
	return {"ok":true, "prepared":prepared}

func _commit_p25_contributors(prepared: Dictionary, world) -> void:
	super._commit_p25_contributors(prepared, world)
	if prepared.get("p26_inventory", null) is GMInventoryStore: p26_inventory = prepared.get("p26_inventory")
	if prepared.get("p26_process", null) is GMProcessService: p26_process = prepared.get("p26_process")
	var session_candidate: Variant = prepared.get("p26_action_session", null)
	if session_candidate is Dictionary and session_candidate.get("session", null) is GMTaskExecutionSession:
		var session: GMTaskExecutionSession = session_candidate.get("session")
		session.commit_prepared_snapshot(session_candidate.get("prepared", {}))
		p26_action_session = session
	if prepared.get("ext3d10_process", null) is GMProcessService: process_service = prepared.get("ext3d10_process")
	if prepared.get("ext3d10_resource", null) is GMNumericResourceStore: resource_store = prepared.get("ext3d10_resource")
	var npc_candidate: Variant = prepared.get("ext3d10_npcs", null)
	if npc_candidate is Array:
		npc_rows.clear()
		for row in npc_candidate:
			if row is Dictionary: npc_rows.append(row.duplicate(true))
		if workflow_result is Dictionary: workflow_result["rows"] = npc_rows.duplicate(true)
		if workflow_projection is Dictionary: workflow_projection["rows"] = npc_rows.duplicate(true)
	var recovery_candidate: Variant = prepared.get("p26_recovery_state", null)
	if recovery_candidate is Dictionary:
		p26_production_phase = str(recovery_candidate.get("phase", "idle"))
		p26_production_blocked = recovery_candidate.get("blocked", {}).duplicate(true) if recovery_candidate.get("blocked", {}) is Dictionary else {}
		p26_production_context = recovery_candidate.get("context", {}).duplicate(true) if recovery_candidate.get("context", {}) is Dictionary else {}
		var summary: Variant = recovery_candidate.get("summary", {})
		p26_production = summary.duplicate(true) if summary is Dictionary else {}
	var action_candidate: Variant = prepared.get("p26_action_summary", null)
	if action_candidate is Dictionary: p26_action = action_candidate.duplicate(true)
	if p26_production_button != null: p26_production_button.disabled = p26_production_phase == "complete"
	if p26_recovery_button != null: p26_recovery_button.disabled = p26_production_phase == "complete"
	if p26_action_button != null: p26_action_button.disabled = bool(p26_action.get("ok", false))
	_refresh_p26_projection()

func _blocked_value(value: Variant, fallback_code: String) -> Dictionary:
	if value is GMBlockedResult: return {"ok":false, "code":value.error_code, "reason_zh":value.reason_zh, "details":value.to_dict()}
	if value is Dictionary: return value
	return {"ok":false, "code":fallback_code, "reason_zh":"既有权威服务没有返回可验证结果。"}

func _typed_success(value: Variant) -> bool:
	if value is GMInteractionResult: return value.is_success()
	if value is Dictionary and str(value.get("status", "")) in ["accepted", "committed"]: return true
	return super._typed_success(value)

func _typed_failure(value: Variant, fallback_code: String) -> Dictionary:
	if value is GMInteractionResult:
		var public: Dictionary = value.to_dict()
		return {"ok":false, "code":str(public.get("code", fallback_code)), "reason_zh":str(public.get("reason_zh", "正式InteractionRouter拒绝了Task操作。")), "details":public}
	return super._typed_failure(value, fallback_code)

func _task_operation_via_router(operation: String, payload_value: Dictionary, source_type: String, source_id: String, key: String) -> Variant:
	var payload := payload_value.duplicate(true)
	payload["operation"] = operation
	payload["task_operation"] = operation
	payload["source_type"] = source_type
	payload["source_id"] = source_id
	var target_id := str(payload.get("task_id", payload.get("definition_id", payload.get("provider_id", source_id))))
	var request := GMInteractionRequest.task("gm.interaction.p26.%s" % operation, {"type":source_type, "id":source_id}, {"type":"task", "id":target_id}, payload, key)
	return interaction_router.submit(request)

func _run_p26_player_probe() -> void:
	var task_view := _find_button_by_text(ui_root, "查看任务")
	if task_view != null: task_view.pressed.emit()
	var task_before_invalid := task_service.snapshot()
	var authority_before_invalid := task_service.fact_store.snapshot()
	var invalid_first := _dispatch_p26_world_control("gm.p26.production")
	var invalid_second := _dispatch_p26_world_control("gm.p26.production")
	var invalid_first_result: Dictionary = invalid_first.get("result", {}) if invalid_first.get("result", {}) is Dictionary else {}
	var invalid_second_result: Dictionary = invalid_second.get("result", {}) if invalid_second.get("result", {}) is Dictionary else {}
	var invalid_task_unchanged := task_service.snapshot() == task_before_invalid
	var invalid_authority_unchanged := task_service.fact_store.snapshot() == authority_before_invalid
	var invalid_retry_stable := not bool(invalid_first.get("ok", false)) and not bool(invalid_second.get("ok", false)) and str(invalid_first_result.get("code", "")) == "p26.production.movement_required" and str(invalid_second_result.get("code", "")) == str(invalid_first_result.get("code", "")) and invalid_task_unchanged and invalid_authority_unchanged and bool(invalid_first_result.get("failure_state_unchanged", false))
	var move_press := InputEventKey.new(); move_press.physical_keycode = KEY_D; move_press.pressed = true
	var move_started := dispatch_input_event(move_press)
	var start_position := player.position
	advance_simulation(0.3)
	var move_release := InputEventKey.new(); move_release.physical_keycode = KEY_D; move_release.pressed = false
	var move_stopped := dispatch_input_event(move_release)
	p26_player_moved_through_input = player.position.distance_to(start_position) > 1.0
	var production_blocked := _dispatch_p26_world_control("gm.p26.production")
	var recovery_result := _dispatch_p26_world_control("gm.p26.recovery")
	var action_result := _dispatch_p26_world_control("gm.p26.action")
	var projection := _p26_projection_value()
	var report := {"schema":"gm.p26.player_entry_probe.v1", "ok":invalid_retry_stable and bool(move_started.get("single_input_source", false)) and str(move_stopped.get("action", "")) == "move" and p26_player_moved_through_input and not bool(production_blocked.get("ok", false)) and str(production_blocked.get("result", {}).get("phase", "")) == "blocked" and bool(recovery_result.get("ok", false)) and bool(action_result.get("ok", false)) and task_panel_visible and projection.readonly, "precondition_retry":{"first":invalid_first, "second":invalid_second, "stable":invalid_retry_stable, "task_unchanged":invalid_task_unchanged, "authority_unchanged":invalid_authority_unchanged}, "world_controls":{"production":{"label":p26_production_button.text, "node":p26_production_button.name, "disabled_after_blocked":p26_production_button.disabled}, "recovery":{"label":p26_recovery_button.text, "node":p26_recovery_button.name, "disabled_after_success":p26_recovery_button.disabled}, "action":{"label":p26_action_button.text, "node":p26_action_button.name, "disabled_after_success":p26_action_button.disabled}}, "input":{"class":"InputEventKey", "move_started":move_started, "move_stopped":move_stopped, "moved":p26_player_moved_through_input}, "routes":{"production_blocked":production_blocked.get("entry", {}), "recovery":recovery_result.get("entry", {}), "action":action_result.get("entry", {}), "interaction_router":"GMInteractionRouter", "inventory_entry":"GMAbilityActivationRequest", "npc_entry":"GMAgentPlanner + same ability"}, "production_blocked":production_blocked, "recovery":recovery_result, "action":action_result, "readonly_projection":projection, "command_contract_is_only_validation":true}
	_write_requested_evidence("GM_P26_PLAYER_JSON", report)
	print("P26_PLAYER_ENTRY_RESULT " + JSON.stringify(report))
	get_tree().quit(0 if report.ok else 1)

func _write_requested_evidence(environment_name: String, value: Dictionary) -> void:
	var path := OS.get_environment(environment_name)
	if path.is_empty(): return
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(value, "  ") + "\n")
