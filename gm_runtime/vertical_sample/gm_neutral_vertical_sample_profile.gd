@tool
class_name GMNeutralVerticalSampleProfile
extends Resource

const SCHEMA := "gm.neutral_vertical_sample.profile.v3"

@export_group("场景身份")
@export var profile_id := "gm.profile.ext3d10.neutral_yard"
@export var display_name_zh := "Planar 3D 中性纵向小院"
@export var seed := 310260905
@export var map_id := "gm.map.ext3d10.neutral_yard"
@export var graph_id := "gm.graph.ext3d10.neutral_yard"
@export var entry_surface_id := "gm.surface.ext3d10.courtyard"
@export var scene_definition_id := "gm.scene_definition.ext3d10.neutral_yard"
@export var scene_recipe_id := "gm.recipe.ext3d10.neutral_yard"
@export var player_task_definition_id := "gm.definition.ext3d10.neutral_work"
@export var task_definition_id := "gm.definition.ext3d10.workflow"
@export var player_target_workspot_id := "gm.workspot.ext3d10.workshop.main"
@export var attack_id := "gm.attack.ext3d10.neutral_projectile"

@export_group("动态恢复")
@export_range(0, 16, 1) var spatial_recovery_round := 0
@export var temporarily_disabled_connection_ids: PackedStringArray = PackedStringArray()

@export_group("角色声明")
@export var actor_specs: Array[Dictionary] = [
	{"actor_id":"gm.actor.ext3d10.npc.aurora","entity_id":"gm.entity.ext3d10.npc.aurora","spawn_logical":{"x":5.0,"y":10.0},"target_workspot_id":"gm.workspot.ext3d10.workshop.main"},
	{"actor_id":"gm.actor.ext3d10.npc.birch","entity_id":"gm.entity.ext3d10.npc.birch","spawn_logical":{"x":5.3,"y":10.3},"target_workspot_id":"gm.workspot.ext3d10.workshop.main"},
	{"actor_id":"gm.actor.ext3d10.npc.cedar","entity_id":"gm.entity.ext3d10.npc.cedar","spawn_logical":{"x":5.6,"y":9.7},"target_workspot_id":"gm.workspot.ext3d10.workshop.main"},
	{"actor_id":"gm.actor.ext3d10.npc.delta","entity_id":"gm.entity.ext3d10.npc.delta","spawn_logical":{"x":5.9,"y":10.2},"target_workspot_id":"gm.workspot.ext3d10.workshop.main"},
	{"actor_id":"gm.actor.ext3d10.npc.ember","entity_id":"gm.entity.ext3d10.npc.ember","spawn_logical":{"x":6.2,"y":9.8},"target_workspot_id":"gm.workspot.ext3d10.workshop.main"},
	{"actor_id":"gm.actor.ext3d10.npc.flint","entity_id":"gm.entity.ext3d10.npc.flint","spawn_logical":{"x":6.5,"y":10.1},"target_workspot_id":"gm.workspot.ext3d10.workshop.main"},
	{"actor_id":"gm.actor.ext3d10.npc.grove","entity_id":"gm.entity.ext3d10.npc.grove","spawn_logical":{"x":6.8,"y":9.9},"target_workspot_id":"gm.workspot.ext3d10.workshop.main"},
	{"actor_id":"gm.actor.ext3d10.npc.hazel","entity_id":"gm.entity.ext3d10.npc.hazel","spawn_logical":{"x":7.1,"y":10.3},"target_workspot_id":"gm.workspot.ext3d10.workshop.main"},
	{"actor_id":"gm.actor.ext3d10.npc.indigo","entity_id":"gm.entity.ext3d10.npc.indigo","spawn_logical":{"x":7.4,"y":9.7},"target_workspot_id":"gm.workspot.ext3d10.workshop.main"},
	{"actor_id":"gm.actor.ext3d10.npc.jade","entity_id":"gm.entity.ext3d10.npc.jade","spawn_logical":{"x":7.7,"y":10.0},"target_workspot_id":"gm.workspot.ext3d10.workshop.main"},
]

@export_group("Facility / WorkSpot 声明")
@export var facility_specs: Array[Dictionary] = [
	{"facility_id":"gm.facility.ext3d10.workshop","workspots":[
		{"workspot_id":"gm.workspot.ext3d10.workshop.main","anchor_id":"gm.anchor.ext3d10.workshop","surface_id":"gm.surface.ext3d10.bridge","logical_position":{"x":25.0,"y":10.0},"capacity":10,"reservation_rule_id":"gm.reservation_rule.ext3d10.workspot","process_definition_id":"gm.process.ext3d10.neutral_work","resource_id":"gm.resource.ext3d10.supply","resource_account_id":"gm.resource.account.ext3d10.workshop_supply","resource_initial_balance":10,"resource_recovery_balance":10,"resource_amount_per_process":1}
	]}
]

@export_group("Surface Graph 声明")
@export var surface_specs: Array[Dictionary] = [
	{"surface_id":"gm.surface.ext3d10.courtyard","surface_kind":"courtyard","world_origin_y":0.0},
	{"surface_id":"gm.surface.ext3d10.floor1","surface_kind":"floor","world_origin_y":3.0},
	{"surface_id":"gm.surface.ext3d10.floor2","surface_kind":"floor","world_origin_y":6.0},
	{"surface_id":"gm.surface.ext3d10.bridge","surface_kind":"bridge","world_origin_y":4.5},
]
@export var connection_specs: Array[Dictionary] = [
	{"connection_id":"gm.connection.ext3d10.stairs_a","from_surface_id":"gm.surface.ext3d10.courtyard","to_surface_id":"gm.surface.ext3d10.floor1","connection_kind":"stairs","source_exit":{"x":4.0,"y":4.0},"target_entry":{"x":5.0,"y":4.0},"cost":2.0},
	{"connection_id":"gm.connection.ext3d10.stairs_b","from_surface_id":"gm.surface.ext3d10.floor1","to_surface_id":"gm.surface.ext3d10.floor2","connection_kind":"stairs","source_exit":{"x":5.0,"y":4.0},"target_entry":{"x":6.0,"y":4.0},"cost":3.0},
	{"connection_id":"gm.connection.ext3d10.bridge_link","from_surface_id":"gm.surface.ext3d10.floor2","to_surface_id":"gm.surface.ext3d10.bridge","connection_kind":"bridge","source_exit":{"x":6.0,"y":4.0},"target_entry":{"x":7.0,"y":4.0},"cost":4.0},
]
@export_file("*.json") var save_path := "user://gm_ext3d10_neutral_yard.world.json"

var npc_count: int:
	get: return actor_specs.size()

func validate() -> Dictionary:
	for value in [profile_id,map_id,graph_id,entry_surface_id,scene_definition_id,scene_recipe_id,player_task_definition_id,task_definition_id,player_target_workspot_id,attack_id]:
		if not GMPlanarPosition.is_valid_stable_id(str(value)): return _failure("sample.profile_id_invalid","中性纵向样板包含无效稳定ID。")
	if display_name_zh.strip_edges().is_empty(): return _failure("sample.profile_name_missing","中性纵向样板需要中文名称。")
	if actor_specs.is_empty(): return _failure("sample.profile_actor_missing","中性纵向样板至少需要一个显式角色声明。")
	if seed < 0 or spatial_recovery_round < 0: return _failure("sample.profile_numeric_invalid","Seed与恢复轮次必须为非负整数。")
	var surfaces: Dictionary = {}
	for row in surface_specs:
		if not row is Dictionary: return _failure("sample.profile_surface_invalid","Surface声明必须是对象。")
		var surface_id := str(row.get("surface_id",""))
		if not GMPlanarPosition.is_valid_stable_id(surface_id) or surfaces.has(surface_id) or not is_finite(float(row.get("world_origin_y",NAN))): return _failure("sample.profile_surface_invalid","Surface声明无效或重复。")
		surfaces[surface_id] = true
	if not surfaces.has(entry_surface_id): return _failure("sample.profile_entry_surface_missing","显式入口Surface未在Surface集合中声明。")
	var connections: Dictionary = {}
	for row in connection_specs:
		if not row is Dictionary: return _failure("sample.profile_connection_invalid","连接声明必须是对象。")
		var connection_id := str(row.get("connection_id",""))
		if not GMPlanarPosition.is_valid_stable_id(connection_id) or connections.has(connection_id) or not surfaces.has(str(row.get("from_surface_id",""))) or not surfaces.has(str(row.get("to_surface_id",""))) or not _point(row.get("source_exit",{})).ok or not _point(row.get("target_entry",{})).ok or not is_finite(float(row.get("cost",NAN))) or float(row.get("cost",0.0)) < 0.0: return _failure("sample.profile_connection_invalid","Surface连接声明无效。")
		connections[connection_id] = true
	for connection_id in temporarily_disabled_connection_ids:
		if not connections.has(str(connection_id)): return _failure("sample.profile_disabled_connection_missing","临时不可达连接未在拓扑中声明。")
	var workspots: Dictionary = {}; var facilities: Dictionary = {}; var anchors: Dictionary = {}; var accounts: Dictionary = {}; var processes: Dictionary = {}; var resources: Dictionary = {}
	if facility_specs.is_empty(): return _failure("sample.profile_facility_missing","至少需要一个Facility声明。")
	for facility in facility_specs:
		if not facility is Dictionary: return _failure("sample.profile_facility_invalid","Facility声明必须是对象。")
		var facility_id := str(facility.get("facility_id","")); var rows: Variant = facility.get("workspots", [])
		if not GMPlanarPosition.is_valid_stable_id(facility_id) or facilities.has(facility_id) or not rows is Array or rows.is_empty(): return _failure("sample.profile_facility_invalid","Facility身份无效、重复或没有WorkSpot。")
		facilities[facility_id] = true
		for workspot in rows:
			var result := _validate_workspot(workspot, surfaces, workspots, anchors, accounts, processes, resources)
			if not result.ok: return result
			workspots[str(workspot.workspot_id)] = {"facility_id":facility_id,"workspot":workspot.duplicate(true)}
			anchors[str(workspot.anchor_id)] = true; accounts[str(workspot.resource_account_id)] = true; processes[str(workspot.process_definition_id)] = true; resources[str(workspot.resource_id)] = true
	if not workspots.has(player_target_workspot_id): return _failure("sample.profile_player_workspot_missing","玩家目标WorkSpot未声明。")
	var actor_ids: Dictionary = {}; var entity_ids: Dictionary = {}
	for row in actor_specs:
		if not row is Dictionary or row.size()!=4 or not row.has("actor_id") or not row.has("entity_id") or not row.has("spawn_logical") or not row.has("target_workspot_id"): return _failure("sample.profile_actor_invalid","角色声明字段必须精确完整。")
		var actor_id:=str(row.actor_id); var entity_id:=str(row.entity_id)
		if not GMPlanarPosition.is_valid_stable_id(actor_id) or not actor_id.begins_with("gm.actor.") or not GMPlanarPosition.is_valid_stable_id(entity_id) or not entity_id.begins_with("gm.entity.") or actor_ids.has(actor_id) or entity_ids.has(entity_id): return _failure("sample.profile_actor_identity_invalid","角色声明身份无效或重复。")
		if not _point(row.spawn_logical).ok: return _failure("sample.profile_actor_position_invalid","角色出生逻辑坐标无效。")
		if not workspots.has(str(row.target_workspot_id)): return _failure("sample.profile_actor_workspot_missing","角色引用了未声明的WorkSpot。")
		actor_ids[actor_id]=true; entity_ids[entity_id]=true
	if not save_path.begins_with("user://"): return _failure("sample.profile_save_path_invalid","保存路径必须复用user://正式保存根。")
	return {"ok":true,"code":"sample.profile_valid"}

func _validate_workspot(value: Variant, surfaces: Dictionary, workspots: Dictionary, anchors: Dictionary, accounts: Dictionary, processes: Dictionary, resources: Dictionary) -> Dictionary:
	if not value is Dictionary: return _failure("sample.profile_workspot_invalid","WorkSpot声明必须是对象。")
	for key in ["workspot_id","anchor_id","surface_id","logical_position","capacity","reservation_rule_id","process_definition_id","resource_id","resource_account_id","resource_initial_balance","resource_recovery_balance","resource_amount_per_process"]:
		if not value.has(key): return _failure("sample.profile_workspot_field_missing","WorkSpot声明缺少字段：%s" % key)
	for key in ["workspot_id","anchor_id","reservation_rule_id","process_definition_id","resource_id","resource_account_id"]:
		if not GMPlanarPosition.is_valid_stable_id(str(value[key])): return _failure("sample.profile_workspot_identity_invalid","WorkSpot声明包含无效稳定ID。")
	if workspots.has(str(value.workspot_id)) or anchors.has(str(value.anchor_id)) or accounts.has(str(value.resource_account_id)) or processes.has(str(value.process_definition_id)) or resources.has(str(value.resource_id)): return _failure("sample.profile_workspot_identity_duplicate","WorkSpot、Anchor、Process或Resource身份重复。")
	if not surfaces.has(str(value.surface_id)) or not _point(value.logical_position).ok: return _failure("sample.profile_workspot_spatial_invalid","WorkSpot引用的Surface或坐标无效。")
	if int(value.capacity)<1 or int(value.resource_initial_balance)<0 or int(value.resource_recovery_balance)<int(value.resource_amount_per_process) or int(value.resource_amount_per_process)<1: return _failure("sample.profile_workspot_capacity_invalid","WorkSpot容量或资源配置无效。")
	return {"ok":true}

func target_for_workspot(workspot_id: String) -> Dictionary:
	for facility in facility_specs:
		for workspot in facility.get("workspots", []):
			if str(workspot.get("workspot_id", "")) == workspot_id:
				var result: Dictionary = workspot.duplicate(true); result["facility_id"] = str(facility.facility_id); return result
	return {}
func target_for_actor(actor_id: String) -> Dictionary:
	for actor in actor_specs:
		if str(actor.actor_id) == actor_id: return target_for_workspot(str(actor.target_workspot_id))
	return {}
func player_target() -> Dictionary: return target_for_workspot(player_target_workspot_id)
func actor_key(actor_id:String)->String: return actor_id.trim_prefix("gm.actor.").replace(".","_").replace("-","_")

func apply_shell_configuration(configuration:GMPlayerShellConfiguration)->Dictionary:
	if configuration==null:return _failure("sample.shell_configuration_missing","样板缺少PlayerShell配置。")
	var checked := validate(); if not checked.ok: return checked
	var target := player_target(); if target.is_empty(): return _failure("sample.profile_player_workspot_missing","玩家目标WorkSpot未声明。")
	configuration.seed=seed; configuration.map_id=map_id; configuration.graph_id=graph_id; configuration.surface_id=entry_surface_id
	configuration.target_anchor_id=str(target.anchor_id); configuration.target_position=point(target.logical_position)*configuration.tile_size
	configuration.facility_id=str(target.facility_id); configuration.resource_id=str(target.resource_id); configuration.reservation_rule_id=str(target.reservation_rule_id)
	configuration.scene_definition_id=scene_definition_id; configuration.scene_recipe_id=scene_recipe_id; configuration.task_definition_id=player_task_definition_id; configuration.save_path=save_path
	return {"ok":true}

func configure_semantic_anchors(registry:GMMapSemanticRegistry, position_scale:Vector2=Vector2.ONE)->Dictionary:
	if registry==null:return _failure("sample.semantic_registry_missing","正式语义地图注册表不存在。")
	var map_result:=registry.resolve_map(map_id);if not map_result.ok:return map_result
	var semantic_map:GMMapSemanticResource=map_result.map
	for surface in surface_specs:
		if not semantic_map.has_surface(str(surface.surface_id)):
			var registered:=semantic_map.register_surface(str(surface.surface_id));if not registered.ok:return registered
	for facility in facility_specs:
		for target in facility.workspots:
			var anchor_result:=registry.resolve_anchor(map_id,str(target.anchor_id));var anchor:GMSemanticAnchor
			if anchor_result.ok:anchor=anchor_result.anchor
			else:anchor=GMSemanticAnchor.new();anchor.anchor_id=str(target.anchor_id);semantic_map.anchors.append(anchor)
			anchor.surface_id=str(target.surface_id);anchor.position=point(target.logical_position)*position_scale;anchor.capacity=int(target.capacity)
	return {"ok":true,"anchor_count":facility_specs.reduce(func(count,facility):return count+facility.workspots.size(),0)}

func to_native()->Dictionary:
	return {"schema":SCHEMA,"profile_id":profile_id,"display_name_zh":display_name_zh,"seed":seed,"map_id":map_id,"graph_id":graph_id,"entry_surface_id":entry_surface_id,"scene_definition_id":scene_definition_id,"scene_recipe_id":scene_recipe_id,"player_task_definition_id":player_task_definition_id,"task_definition_id":task_definition_id,"player_target_workspot_id":player_target_workspot_id,"attack_id":attack_id,"spatial_recovery_round":spatial_recovery_round,"temporarily_disabled_connection_ids":Array(temporarily_disabled_connection_ids),"actor_specs":actor_specs.duplicate(true),"facility_specs":facility_specs.duplicate(true),"surface_specs":surface_specs.duplicate(true),"connection_specs":connection_specs.duplicate(true),"save_path":save_path}

static func resolve_configured(default_profile: GMNeutralVerticalSampleProfile, arguments: PackedStringArray) -> Dictionary:
	var selected := default_profile; var selected_path := ""
	for argument in arguments:
		if str(argument).begins_with("--gm-ext-3d-10-profile="): selected_path = str(argument).trim_prefix("--gm-ext-3d-10-profile="); break
	if not selected_path.is_empty():
		if not selected_path.begins_with("res://"): return _failure("sample.profile_path_invalid", "正式Profile覆盖路径必须位于res://。")
		selected = ResourceLoader.load(selected_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GMNeutralVerticalSampleProfile
		if selected == null: return _failure("sample.profile_load_failed", "无法加载指定的正式EXT10 Profile。")
	if selected == null: return _failure("sample.profile_missing", "EXT10入口缺少正式Profile资源。")
	var checked := selected.validate(); if not checked.ok: return checked
	return {"ok": true, "profile": selected, "path": selected_path}

static func _point(value:Variant)->Dictionary:
	if value is Vector2 and is_finite(value.x) and is_finite(value.y):return {"ok":true,"value":value}
	if value is Dictionary and value.has("x") and value.has("y") and is_finite(float(value.x)) and is_finite(float(value.y)):return {"ok":true,"value":Vector2(float(value.x),float(value.y))}
	return {"ok":false}
static func point(value:Variant)->Vector2:return _point(value).get("value",Vector2.ZERO)
static func _failure(code:String,reason_zh:String)->Dictionary:return {"ok":false,"code":code,"reason_zh":reason_zh,"failure_state_unchanged":true}
