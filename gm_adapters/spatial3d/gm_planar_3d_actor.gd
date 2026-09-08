class_name GMPlanar3DActor
extends Node3D

## Runtime projection for an actor that owns a stable PlanarPosition.  The
## actor is not a persistence root: its spatial projection is copied into the
## existing EntityRegistry/WorldSnapshot pipeline by the caller.

const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

@export var stable_instance_id: String = ""
@export var map_id: String = ""
@export var spatial_position: Dictionary = {}
@export var visual_recipe_id: String = "gm.visual.placeholder_3d"
@export var persistent_state: Dictionary = {}
@export var movement_grant_source_id: String = ""

var ability_host: GMAbilitySystemHost
var movement_executor: Object
var movement_velocity: Vector2 = Vector2.ZERO
var movement_facing: Vector2 = Vector2.DOWN
var identity_validation: Dictionary = {}

func _ready() -> void:
	identity_validation = validate_stable_identity()

func validate_stable_identity() -> Dictionary:
	var candidate := stable_instance_id.strip_edges()
	var checked := GMEntityId.validate_value(candidate)
	if not checked.ok:
		return {"ok": false, "code": "movement.3d.actor_identity_missing", "reason_zh": "Planar 3D角色必须配置可重复的稳定实体ID；禁止使用运行时实例身份。", "errors": checked.errors, "atomic": true}
	return {"ok": true, "stable_instance_id": candidate}

func current_planar_position():
	var parsed := PLANAR_POSITION.from_native(spatial_position)
	return parsed.position if parsed.ok else null

func apply_planar_position(position_value: Variant, world_value: Variant = null) -> Dictionary:
	var parsed := PLANAR_POSITION.from_native(position_value)
	if not parsed.ok:
		return {"ok": false, "code": "movement.3d.position_invalid", "reason_zh": "3D角色的PlanarPosition无效。", "details": parsed}
	var position: Variant = parsed.position
	spatial_position = position.to_native()
	map_id = position.map_id
	if world_value is Vector3:
		global_position = world_value
	elif world_value is Dictionary and world_value.has("x") and world_value.has("y") and world_value.has("z"):
		global_position = Vector3(float(world_value.x), float(world_value.y), float(world_value.z))
	return {"ok": true, "position": position.to_native(), "world_position": {"x": global_position.x, "y": global_position.y, "z": global_position.z}}

func set_movement_state(velocity: Vector2, facing: Vector2) -> void:
	movement_velocity = velocity
	if facing.length_squared() > 0.000001:
		movement_facing = facing.normalized()

func spatial_visual_snapshot() -> Dictionary:
	var identity := validate_stable_identity()
	if not identity.ok:
		return identity
	var position: Variant = current_planar_position()
	return {
		"stable_instance_id": identity.stable_instance_id,
		"map_id": map_id,
		"spatial_position": position.to_native() if position != null else {},
		"facing": {"x": movement_facing.x, "y": movement_facing.y},
		"visual_recipe_id": visual_recipe_id,
		"persistent_state": persistent_state.duplicate(true),
	}

func mount_movement(context: Object, adapter: Object) -> Dictionary:
	var identity := validate_stable_identity()
	if not identity.ok: return identity
	var grant_source := movement_grant_source_id.strip_edges()
	if grant_source.is_empty():
		return {"ok": false, "code": "movement.3d.grant_source_missing", "reason_zh": "Planar 3D角色缺少显式移动能力授予来源；请由内容/Profile配置。", "atomic": true}
	if context == null or not is_instance_valid(context):
		return {"ok": false, "code": "movement.3d.context_missing", "reason_zh": "Planar 3D角色缺少现有GMRuntimeContext。"}
	if adapter == null or not is_instance_valid(adapter):
		return {"ok": false, "code": "movement.3d.adapter_missing", "reason_zh": "Planar 3D角色缺少现有空间适配器。"}
	var attached := GMAbilitySystemHost.attach_to(self, context)
	if not attached.ok:
		return attached
	ability_host = attached.host
	movement_executor = GMMovementExecutor3D.new(adapter, context)
	var registered: Dictionary = movement_executor.register_actor(stable_instance_id, self, map_id, spatial_position)
	if not registered.ok:
		ability_host.dispose(); ability_host = null; movement_executor = null
		return registered
	var service := ability_host.set_domain_service("gm.movement.executor", movement_executor)
	if not service.ok:
		ability_host.dispose(); ability_host = null; movement_executor = null
		return service
	var definition := GMMovementAbilityDefinition.new()
	var definition_result := ability_host.register_definition(definition)
	if not definition_result.ok:
		ability_host.dispose(); ability_host = null; movement_executor = null
		return definition_result
	var grant := ability_host.grant_ability(definition, grant_source)
	if not grant.ok:
		ability_host.dispose(); ability_host = null; movement_executor = null
		return grant
	return {"ok": true, "ability_id": definition.ability_id, "executor_service_id": "gm.movement.executor", "single_owner": true}

func submit_movement_request(source: String, request_data: Dictionary, idempotency_key: String = "") -> Dictionary:
	if ability_host == null or not is_instance_valid(ability_host):
		return {"ok": false, "code": "movement.3d.host_missing", "reason_zh": "Planar 3D角色尚未挂载统一AbilityHost。"}
	var request := GMAbilityActivationRequest.new(ability_host, "gm.ability.movement", "", null, {"movement_request": request_data.duplicate(true)}, "character.%s" % source, {}, idempotency_key)
	var checked := request.validate()
	if not checked.ok:
		return checked
	return ability_host.request_activation(request)

func movement_snapshot() -> Dictionary:
	var identity := validate_stable_identity()
	if not identity.ok: return identity
	return movement_executor.snapshot_actor(identity.stable_instance_id) if movement_executor != null else {"schema": "gm.movement.3d.snapshot.v1", "actor_id": identity.stable_instance_id, "active": false}

func unmount_movement() -> Dictionary:
	if movement_executor != null and movement_executor.has_method("unregister_actor"):
		movement_executor.unregister_actor(stable_instance_id)
	if ability_host != null and is_instance_valid(ability_host):
		ability_host.dispose()
	ability_host = null
	movement_executor = null
	return {"ok": true, "active": false}

func _exit_tree() -> void:
	if ability_host != null and is_instance_valid(ability_host):
		ability_host.dispose()
	ability_host = null
