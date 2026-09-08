@tool
class_name GMCharacterRuntime2D
extends Node2D

const SNAPSHOT_SCHEMA := "gm.character.snapshot.v2"
const ACTIVATION_STATES := ["inactive", "active"]

@export var stable_instance_id: String = ""
@export var map_id: String = ""
@export var spawn_anchor_id: String = ""
@export var role_profile: GMRoleProfile
@export var visual_set: GMCharacterVisualSet2D
@export var persistent_state: Dictionary = {}

var ability_host: GMAbilitySystemHost
var control_router := GMCharacterControlRouter.new()
var presenter: GMCharacterPresenter2D
var current_role_id: String = ""
var activation_state: String = "inactive"
var movement_velocity: Vector2 = Vector2.ZERO
var movement_facing: Vector2 = Vector2.DOWN
var movement_executor: GMMovementAbilityExecutor

func _ready() -> void:
	ensure_components()

func ensure_components() -> Dictionary:
	if stable_instance_id.strip_edges().is_empty(): stable_instance_id = "gm.character.%s" % str(get_instance_id())
	presenter = get_node_or_null("Presenter") as GMCharacterPresenter2D
	if presenter == null:
		presenter = GMCharacterPresenter2D.new(); presenter.name = "Presenter"; add_child(presenter); presenter.owner = owner
	if get_node_or_null("InteractionAnchor") == null:
		var anchor := Marker2D.new(); anchor.name = "InteractionAnchor"; add_child(anchor); anchor.owner = owner
	if get_node_or_null("CueAudio") == null:
		var audio := AudioStreamPlayer2D.new(); audio.name = "CueAudio"; add_child(audio); audio.owner = owner
	if visual_set != null:
		var configured := presenter.configure(visual_set)
		if not configured.ok: return configured
	return {"ok":true,"idempotent":true,"children":["Presenter","InteractionAnchor","CueAudio"],"movement_deferred_to":"P15"}

func mount_runtime(context: Object, definitions: Dictionary = {}) -> Dictionary:
	if role_profile == null: return _fail("character.role_missing", "角色缺少 GMRoleProfile。")
	var role_check := role_profile.validate_profile()
	if not role_check.ok: return role_check
	var attached := GMAbilitySystemHost.attach_to(self, context)
	if not attached.ok: return attached
	ability_host = attached.host
	for definition in definitions.values():
		if definition is GMAbilityDefinition: ability_host.register_definition(definition)
	var grant := role_profile.grant_to(ability_host, definitions)
	if not grant.ok: ability_host.dispose(); ability_host = null; return grant
	current_role_id = role_profile.role_id
	var routed := control_router.configure(ability_host, role_profile.enabled_control_sources)
	if not routed.ok: ability_host.dispose(); ability_host = null; return routed
	activation_state = "active"
	return {"ok":true,"role_id":current_role_id,"host":ability_host,"activation_handoff":"active","behavior_schedule_deferred_to":"P17"}

func unmount_runtime() -> Dictionary:
	if movement_executor != null: movement_executor.unregister_actor(stable_instance_id)
	if ability_host != null: ability_host.dispose()
	ability_host = null
	control_router.reset()
	activation_state = "inactive"
	return {"ok":true,"activation_handoff":"inactive"}

func configure_movement(registry: GMMapSemanticRegistry) -> Dictionary:
	if activation_state != "active" or ability_host == null: return _fail("movement.host_inactive", "角色尚未激活，无法安装P15移动能力。")
	if registry == null: return _fail("movement.semantic_registry_missing", "P15移动能力缺少SemanticMap注册表。")
	movement_executor = GMMovementAbilityExecutor.new(registry)
	var registered := movement_executor.register_actor(stable_instance_id, self, map_id)
	if not registered.ok: movement_executor = null; return registered
	var service := ability_host.set_domain_service(GMMovementAbilityExecutor.SERVICE_ID, movement_executor)
	if not service.ok: movement_executor = null; return service
	var definition := GMMovementAbilityDefinition.new()
	var definition_result := ability_host.register_definition(definition)
	if not definition_result.ok: movement_executor = null; return definition_result
	var grant := ability_host.grant_ability(definition, "gm.p15.character_runtime")
	if not grant.ok: movement_executor = null; return grant
	return {"ok": true, "ability_id": definition.ability_id, "executor_service_id": GMMovementAbilityExecutor.SERVICE_ID, "single_owner": true}

func register_movement_peer(peer: GMCharacterRuntime2D) -> Dictionary:
	if movement_executor == null: return _fail("movement.executor_missing", "角色尚未配置P15移动执行器。")
	if peer == null: return _fail("movement.peer_missing", "跟随目标角色为空。")
	return movement_executor.register_actor(peer.stable_instance_id, peer, peer.map_id)

func submit_movement_request(source: String, request_data: Dictionary, idempotency_key: String = "") -> Dictionary:
	if movement_executor == null: return _fail("movement.executor_missing", "角色尚未配置P15移动执行器。")
	var payload := {"movement_request": request_data.duplicate(true)}
	return submit_activation_request(source, "gm.ability.movement", payload, idempotency_key)

func movement_snapshot() -> Dictionary:
	return movement_executor.snapshot_actor(stable_instance_id) if movement_executor != null else {"schema": GMMovementAbilityExecutor.SNAPSHOT_SCHEMA, "actor_id": stable_instance_id, "active": false}

func submit_activation_request(source: String, ability_id: String, payload: Dictionary = {}, idempotency_key: String = "") -> Dictionary:
	if activation_state != "active" or ability_host == null: return _fail("character.activation_inactive", "角色运行时尚未激活，ActivationRequest 未发送。")
	var routed := control_router.activation_request(source, ability_id, payload, idempotency_key)
	if not routed.ok: return routed
	return ability_host.request_activation(routed.request)

func submit_gameplay_event(source: String, tag: String, payload: Dictionary = {}) -> Dictionary:
	if activation_state != "active" or ability_host == null: return _fail("character.activation_inactive", "角色运行时尚未激活，GameplayEvent 未发送。")
	var routed := control_router.gameplay_event(source, tag, payload)
	if not routed.ok: return routed
	return ability_host.emit_gameplay_event(routed.event)

func switch_role(next: GMRoleProfile, definitions: Dictionary) -> Dictionary:
	if ability_host == null or next == null: return _fail("character.role_switch_invalid", "身份切换缺少 Host 或候选身份。")
	var check := next.validate_profile()
	if not check.ok: return check
	var snapshot := ability_host._snapshot_ability_grant_state()
	var grant := next.grant_to(ability_host, definitions)
	if not grant.ok: return grant
	var old := role_profile
	if old != null:
		var revoke := old.revoke_from(ability_host)
		if not revoke.ok: ability_host._restore_ability_grant_state(snapshot); return _fail("character.role_revoke_failed", "旧身份撤销失败，已恢复完整能力来源。")
	role_profile = next; current_role_id = next.role_id
	control_router.configure(ability_host, next.enabled_control_sources)
	return {"ok":true,"role_id":current_role_id,"preserved_non_role_sources":true}

func save_snapshot() -> Dictionary:
	var role_id := current_role_id if not current_role_id.is_empty() else (role_profile.role_id if role_profile != null else "")
	return {"schema":SNAPSHOT_SCHEMA,"stable_instance_id":stable_instance_id,"map_id":map_id,"spawn_anchor_id":spawn_anchor_id,"role_id":role_id,"role_profile_id":role_profile.stable_profile_id() if role_profile != null else "","position":{"x":position.x,"y":position.y},"persistent_state":persistent_state.duplicate(true),"activation_state":activation_state,"control_handoff":control_router.snapshot_state()}

func prepare_snapshot(snapshot: Dictionary) -> Dictionary:
	# Validate every contributor before the first write. This is intentionally a
	# P14 adapter over the existing save domain, not a second store.
	var required := ["schema","stable_instance_id","map_id","spawn_anchor_id","role_id","role_profile_id","position","persistent_state","activation_state","control_handoff"]
	for key in required:
		if not snapshot.has(key): return _fail("character.snapshot_truncated", "角色快照缺少必要贡献者。", {"missing":key})
	for field in ["schema","stable_instance_id","map_id","spawn_anchor_id","role_id","role_profile_id","activation_state"]:
		if typeof(snapshot[field]) != TYPE_STRING:
			return _fail("character.snapshot_field_type_invalid", "角色快照字段“%s”类型错误，应为字符串；请检查存档写入器或迁移器。" % field, {"field":field,"expected_type":"String","actual_type":type_string(typeof(snapshot[field]))})
	var schema_value: String = snapshot.schema
	var snapshot_id: String = snapshot.stable_instance_id
	var snapshot_map: String = snapshot.map_id
	var snapshot_anchor: String = snapshot.spawn_anchor_id
	var snapshot_role: String = snapshot.role_id
	var snapshot_profile: String = snapshot.role_profile_id
	var snapshot_activation: String = snapshot.activation_state
	if schema_value != SNAPSHOT_SCHEMA: return _fail("character.snapshot_schema_invalid", "角色快照 schema 不匹配，请使用当前版本快照。")
	if snapshot_id.strip_edges().is_empty(): return _fail("character.snapshot_id_missing", "角色快照缺少稳定实例 ID，请检查保存来源。")
	if snapshot_id != stable_instance_id: return _fail("character.snapshot_id_mismatch", "角色快照与实例身份不匹配，请选择对应角色的快照。")
	if snapshot_map.strip_edges().is_empty() or snapshot_anchor.strip_edges().is_empty(): return _fail("character.snapshot_location_invalid", "角色快照缺少地图或语义锚点身份，请补全位置引用。")
	if snapshot_map != map_id or snapshot_anchor != spawn_anchor_id: return _fail("character.snapshot_location_mismatch", "角色快照的地图/语义锚点与当前装配不一致，请核对角色所在地图。")
	if role_profile == null: return _fail("character.snapshot_profile_missing", "当前角色缺少可核对的 RoleProfile。")
	if snapshot_role.strip_edges().is_empty() or snapshot_profile.strip_edges().is_empty(): return _fail("character.snapshot_profile_invalid", "角色快照缺少角色身份或身份配置标识，请检查保存来源。")
	if snapshot_role != role_profile.role_id or snapshot_profile != role_profile.stable_profile_id(): return _fail("character.snapshot_profile_mismatch", "角色快照的角色身份/身份配置与当前装配不一致，请选择匹配的角色快照。")
	var pos = snapshot.position
	if not pos is Dictionary or not pos.has("x") or not pos.has("y") or not (pos.x is float or pos.x is int) or not (pos.y is float or pos.y is int): return _fail("character.snapshot_position_invalid", "角色快照位置无效。")
	if not snapshot.persistent_state is Dictionary: return _fail("character.snapshot_persistent_invalid", "角色快照持久状态类型无效。")
	if snapshot_activation not in ACTIVATION_STATES: return _fail("character.snapshot_activation_invalid", "角色快照最小激活状态无效，请使用 active 或 inactive 的当前快照。")
	if (snapshot_activation == "active") != (ability_host != null): return _fail("character.snapshot_activation_mismatch", "角色快照激活状态与当前能力宿主生命周期不一致，请先完成对应挂载或卸载。")
	if not snapshot.control_handoff is Dictionary: return _fail("character.snapshot_control_invalid", "角色快照控制交接贡献者无效。")
	var handoff_check := control_router.validate_snapshot(snapshot.control_handoff)
	if not handoff_check.ok: return handoff_check
	var restored_position := Vector2(float(pos.x),float(pos.y))
	var restored_persistent: Dictionary = snapshot.persistent_state.duplicate(true)
	var restored_map := snapshot_map
	var restored_anchor := snapshot_anchor
	var restored_role := snapshot_role
	var restored_activation := snapshot_activation
	return {"ok":true,"prepared": {
		"map_id": restored_map,
		"spawn_anchor_id": restored_anchor,
		"current_role_id": restored_role,
		"position": restored_position,
		"persistent_state": restored_persistent,
		"activation_state": restored_activation,
		"control_handoff": handoff_check
	}}

func commit_prepared_snapshot(prepared: Dictionary) -> Dictionary:
	# All semantic checks, including the control-handoff contract, completed in prepare_snapshot.
	map_id = str(prepared.get("map_id", ""))
	spawn_anchor_id = str(prepared.get("spawn_anchor_id", ""))
	current_role_id = str(prepared.get("current_role_id", ""))
	position = prepared.get("position", Vector2.ZERO)
	persistent_state = prepared.get("persistent_state", {}).duplicate(true)
	activation_state = str(prepared.get("activation_state", "inactive"))
	control_router.commit_prepared_state(prepared.get("control_handoff", {}))
	return {"ok":true,"stable_instance_id":stable_instance_id,"atomic":true}

func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	var prepared := prepare_snapshot(snapshot)
	if not prepared.ok: return prepared
	return commit_prepared_snapshot(prepared.prepared)

func _exit_tree() -> void:
	if ability_host != null: ability_host.dispose(); ability_host = null

func _fail(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok":false,"code":code,"error_zh":message,"details":details}
