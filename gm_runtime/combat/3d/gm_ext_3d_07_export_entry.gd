extends Node

## EXT07 export/runtime smoke entry.  It intentionally exercises the public
## pure-value edge, the existing P22 resolver, and the P18 Cue route without
## creating a second rule authority or writing a domain fact directly.

const MODULE_REGISTRY := preload("res://gm_runtime/gm_module_registry.gd")
const GRAPH := preload("res://gm_runtime/map/3d/gm_surface_graph.gd")
const SURFACE := preload("res://gm_runtime/map/3d/gm_surface_definition_3d.gd")
const MAP_BACKEND := preload("res://gm_runtime/map/3d/gm_map_backend_3d.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const VOLUME := preload("res://gm_runtime/combat/3d/gm_hit_volume_3d.gd")
const TARGET_POINT := preload("res://gm_runtime/combat/3d/gm_target_point_3d.gd")
const ADAPTER_3D := preload("res://gm_runtime/combat/3d/gm_planar_combat_adapter_3d.gd")
const PROJECTILE := preload("res://gm_runtime/combat/3d/gm_projectile_presentation_3d.gd")
const AOE := preload("res://gm_runtime/combat/3d/gm_aoe_presentation_3d.gd")
const ATTACK := preload("res://gm_runtime/combat/gm_combat_attack_definition.gd")
const HIT_SPEC := preload("res://gm_runtime/combat/gm_combat_hit_spec.gd")
const REQUEST := preload("res://gm_runtime/combat/gm_combat_request.gd")
const RESOLVER := preload("res://gm_runtime/combat/gm_combat_resolver.gd")
const PLANAR_2D := preload("res://gm_runtime/combat/gm_combat_planar_hit_query_adapter.gd")
const CUE_ROUTER := preload("res://gm_runtime/gas/gm_cue_router.gd")
const CUE_PARAMETERS := preload("res://gm_runtime/gas/gm_cue_parameters.gd")
const CUE_PRESENTATION := preload("res://gm_runtime/feedback/3d/gm_cue_presentation_3d.gd")

const MODULE_INDEX_PATH := "res://gm_runtime/manifests/gm_ext_3d_07_manifest_index.tres"
const MAP_ID := "gm.map.ext3d07.export"
const GRAPH_ID := "gm.graph.ext3d07.export"
const SURFACE_ID := "gm.surface.ext3d07.export.floor"
const SOURCE_ID := "gm.actor.ext3d07.export.source"
const TARGET_ID := "gm.actor.ext3d07.export.target"
const ABILITY_ID := "gm.ability.planar_combat_3d"
const SEED := "gm.ext3d07.export.seed.7"

func _ready() -> void:
	var report: Dictionary = _run_smoke()
	_write_output(report)
	print(JSON.stringify(report))
	get_tree().quit(0 if bool(report.get("ok", false)) else 173)

func _run_smoke() -> Dictionary:
	OS.set_environment("GM_MODULE_INDEX_PATH", MODULE_INDEX_PATH)
	var registry: Dictionary = MODULE_REGISTRY.resolve(PackedStringArray(["presentation.planar_3d"]))
	var graph: GMSurfaceGraph = GRAPH.new()
	graph.graph_id = GRAPH_ID
	graph.map_id = MAP_ID
	graph.display_name_zh = "EXT07导出中性Surface Graph"
	var surface: GMSurfaceDefinition3D = SURFACE.rectangle(SURFACE_ID, MAP_ID, "floor", Vector3.ZERO, Vector2(20.0, 20.0))
	surface.display_name_zh = "EXT07导出Floor"
	var graph_registration: Dictionary = graph.register_surface(surface)
	var map_backend: GMMapBackend3D = MAP_BACKEND.new()
	var backend_configuration: Dictionary = map_backend.configure_graph(graph)
	var target_point: GMTargetPoint3D = TARGET_POINT.new()
	target_point.configure("gm.target_point.ext3d07.export", TARGET_ID, MAP_ID, SURFACE_ID, 0.75, "gm.anchor.ext3d07.export.target")
	target_point.position = Vector3(4.0, 0.0, 4.0)
	add_child(target_point)
	var volume: GMHitVolume3D = VOLUME.new()
	volume.configure("gm.hit_volume.ext3d07.export", SOURCE_ID, "direct", 0.7, 0.75)
	volume.position = Vector3(1.0, 0.0, 1.0)
	add_child(volume)
	var source_position: GMPlanarPosition = PLANAR_POSITION.new(MAP_ID, SURFACE_ID, 1.0, 1.0)
	var candidate: Dictionary = volume.candidate_for(source_position, target_point, map_backend, {"export_smoke": true})
	var attack: GMCombatAttackDefinition = ATTACK.new()
	attack.configure("gm.attack.ext3d07.export.slash", "EXT07导出中性斩击", "melee", "damage", 10.0, 8.0)
	var adapter_3d: GMPlanarCombatAdapter3D = ADAPTER_3D.new(map_backend, 0.75)
	var resolver_3d: GMCombatResolver = RESOLVER.new(null, adapter_3d)
	var registered_3d: Dictionary = resolver_3d.register_attack(attack)
	var request_3d: GMCombatRequest = null
	var result_3d: GMCombatResult = null
	if bool(candidate.get("ok", false)):
		request_3d = REQUEST.new()
		request_3d.configure("gm.combat.request.ext3d07.export.3d", SEED, "realtime", SOURCE_ID, TARGET_ID, ABILITY_ID, attack.attack_id, candidate.get("hit_spec"))
		var resolved_3d_value: Variant = resolver_3d.resolve(request_3d, candidate.get("query_context", {}))
		result_3d = resolved_3d_value as GMCombatResult
	var resolver_2d: GMCombatResolver = RESOLVER.new(null, PLANAR_2D.new())
	var registered_2d: Dictionary = resolver_2d.register_attack(attack)
	var request_2d: GMCombatHitSpec = HIT_SPEC.new()
	request_2d.configure("gm.hit.ext3d07.export.2d", "direct", SOURCE_ID, TARGET_ID, {"x": 3.0, "y": 3.0}, sqrt(18.0), 0.0, 0.7, {"export_smoke": true})
	var combat_request_2d: GMCombatRequest = REQUEST.new()
	combat_request_2d.configure("gm.combat.request.ext3d07.export.2d", SEED, "realtime", SOURCE_ID, TARGET_ID, ABILITY_ID, attack.attack_id, request_2d)
	var resolved_2d_value: Variant = resolver_2d.resolve(combat_request_2d, {"source_position": {"x": 1.0, "y": 1.0}, "target_position": {"x": 4.0, "y": 4.0}, "force_hit": true})
	var result_2d: GMCombatResult = resolved_2d_value as GMCombatResult
	var projectile: GMProjectilePresentation3D = PROJECTILE.new()
	add_child(projectile)
	var projectile_start: Dictionary = projectile.launch("gm.projectile.presentation.ext3d07.export", "gm.projectile.seed.ext3d07.7", {"x": 1.0, "y": 1.0, "z": 1.0}, {"x": 4.0, "y": 0.0, "z": 4.0}, 20.0, 1)
	var projectile_tick: Dictionary = projectile.tick(1.0)
	var projectile_pool: Dictionary = projectile.release_to_pool()
	var aoe: GMAoEPresentation3D = AOE.new()
	add_child(aoe)
	var aoe_start: Dictionary = aoe.start("gm.aoe.presentation.ext3d07.export", "gm.aoe.seed.ext3d07.7", {"x": 4.0, "y": 0.0, "z": 4.0}, 2.0, 0.25, 4)
	var aoe_tick: Dictionary = aoe.tick(0.25)
	var aoe_pool: Dictionary = aoe.release_to_pool()
	var cue_router: GMCueRouter = CUE_ROUTER.new()
	var cue_backend: GMCuePresentation3D = CUE_PRESENTATION.new("cue")
	var cue_definitions: Dictionary = cue_backend.install_cue_definitions(cue_router, true)
	var camera_parameters: GMCueParameters = CUE_PARAMETERS.new("gm.cue.combat.3d.camera", null, {"stage": "execute", "source_id": SOURCE_ID, "target_id": TARGET_ID, "feedback_id": "gm.feedback.ext3d07.export", "value": 10.0})
	var camera_route: Dictionary = cue_router.route(camera_parameters, true)
	var rule_match: bool = bool(result_3d != null and result_2d != null and result_3d.status == "committed" and result_2d.status == "committed" and is_equal_approx(result_3d.amount, result_2d.amount) and result_3d.operation == result_2d.operation and result_3d.hit_confirmed == result_2d.hit_confirmed)
	var report: Dictionary = {
		"schema": "gm.ext_3d_07.export_smoke.v1",
		"event": "GM_EXT_3D_07_EXPORT_SENTINEL",
		"ok": bool(registry.get("ok", false)) and bool(graph_registration.get("ok", false)) and bool(backend_configuration.get("ok", false)) and bool(candidate.get("ok", false)) and bool(registered_3d.get("ok", false)) and bool(registered_2d.get("ok", false)) and rule_match and bool(projectile_start.get("ok", false)) and bool(projectile_tick.get("ok", false)) and bool(projectile_pool.get("ok", false)) and bool(aoe_start.get("ok", false)) and bool(aoe_tick.get("ok", false)) and bool(aoe_pool.get("ok", false)) and bool(cue_definitions.get("ok", false)) and bool(camera_route.get("ok", false)),
		"module": {"index_path": MODULE_INDEX_PATH, "selected": "presentation.planar_3d", "resolved": bool(registry.get("ok", false)), "required_runtime_root": "res://gm_runtime/combat/3d"},
		"surface_backend": {"graph_registration": graph_registration, "backend_configuration": backend_configuration, "map_id": MAP_ID, "surface_id": SURFACE_ID},
		"candidate": {"ok": bool(candidate.get("ok", false)), "code": str(candidate.get("code", "")), "hit_spec": candidate.get("hit_spec_native", {}), "query_context": candidate.get("query_context", {}), "representation": str(candidate.get("representation", ""))},
		"same_ability_seed_2d_3d": {"ability_id": ABILITY_ID, "seed": SEED, "rule_match": rule_match, "result_3d": result_3d.to_native() if result_3d != null else {}, "result_2d": result_2d.to_native() if result_2d != null else {}},
		"presentation_lifecycle": {"projectile_start": projectile_start, "projectile_tick": projectile_tick, "projectile_pool": projectile_pool, "aoe_start": aoe_start, "aoe_tick": aoe_tick, "aoe_pool": aoe_pool},
		"cue": {"definitions": cue_definitions, "route": camera_route, "router_snapshot": cue_router.snapshot(), "domain_facts_written": false},
		"authority": {"combat_rule_owner": "gm.resolver.combat", "presentation_owner": "gm.feedback.playback", "direct_store_write": false, "height_used_for_rule": false, "area3d_damage_method": volume.has_method("apply_damage")}
	}
	return report

func _write_output(report: Dictionary) -> void:
	var output_path: String = OS.get_environment("GM_EXT_3D_07_EXPORT_OUTPUT").strip_edges()
	if output_path.is_empty():
		return
	var parent: String = output_path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)
	var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report))
		file.close()
