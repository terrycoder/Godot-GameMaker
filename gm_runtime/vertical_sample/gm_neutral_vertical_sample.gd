class_name GMNeutralVerticalSample
extends GMPlayerShell

const PROFILE := preload("res://gm_runtime/vertical_sample/gm_neutral_vertical_sample_profile.gd")
const PROFILE_PATH := "res://gm_runtime/vertical_sample/gm_ext_3d_10_profile.tres"
const CHARACTER_LIBRARY := preload("res://gm_runtime/content/gm_content_library.gd")
const VISUAL_RESOLVER := preload("res://gm_runtime/characters/visual_3d/gm_character_visual_3d_resolver.gd")
const VISUAL_ASSEMBLER := preload("res://gm_runtime/characters/visual_3d/gm_character_assembler_3d.gd")
const WORKFLOW := preload("res://gm_runtime/player_shell/gm_ext_3d_10_workflow.gd")

@export var sample_profile: GMNeutralVerticalSampleProfile
var npc_rows: Array[Dictionary] = []
var npc_characters: Array[GMCharacterRuntime2D] = []
var npc_assemblers: Array = []
var npc_holders: Array[Node3D] = []
var workflow_3d_holders: Dictionary = {}
var process_service: GMProcessService
var resource_store: GMNumericResourceStore
var workflow_projection: Dictionary = {}
var workflow_result: Dictionary = {}
var vertical_ready := false
var vertical_error: Dictionary = {}

func _should_restore_on_start() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--gm-ext-3d-10-contract") or args.has("--gm-ext-3d-10-save") or args.has("--gm-ext-3d-10-restore") or args.has("--gm-ext-3d-10-list-pack") or args.has("--gm-ext-3d-10-record"):
		return false
	return super._should_restore_on_start()

func _ready() -> void:
	var selected := GMNeutralVerticalSampleProfile.resolve_configured(sample_profile, OS.get_cmdline_user_args())
	if not selected.ok:
		vertical_error = selected
		return
	sample_profile = selected.profile
	var configured := sample_profile.apply_shell_configuration(shell_configuration)
	if not configured.ok:
		vertical_error = configured
		return
	super._ready()
	if not _startup_error.is_empty():
		vertical_error = _startup_error.duplicate(true)
		return
	var built := _build_vertical_extensions()
	if not built.ok: vertical_error = built
	vertical_ready = bool(built.get("ok", false))
	if OS.get_cmdline_user_args().has("--gm-ext-3d-10-contract"): call_deferred("_run_ext10_contract")
	elif OS.get_cmdline_user_args().has("--gm-ext-3d-10-save"): call_deferred("_run_ext10_save")
	elif OS.get_cmdline_user_args().has("--gm-ext-3d-10-restore"): call_deferred("_run_ext10_restore")
	elif OS.get_cmdline_user_args().has("--gm-ext-3d-10-list-pack"): call_deferred("_run_ext10_pack_inventory")
	elif OS.get_cmdline_user_args().has("--gm-ext-3d-10-record"): call_deferred("_run_ext10_record")

func _build_vertical_extensions() -> Dictionary:
	var profile_check := sample_profile.validate()
	if not profile_check.ok: return profile_check
	var surface_result := _extend_surface_graph()
	if not surface_result.ok: return surface_result
	var npc_result := _build_npcs()
	if not npc_result.ok: return npc_result
	_build_surface_visuals()
	return {"ok": true, "surface_count": surface_graph_3d.surfaces.size(), "npc_count": npc_rows.size()}

func _extend_surface_graph() -> Dictionary:
	var base: GMSurfaceDefinition3D = surface_graph_3d.surfaces[0]
	var entry_spec: Dictionary = {}
	for spec in sample_profile.surface_specs:
		if str(spec.surface_id) == sample_profile.entry_surface_id: entry_spec = spec; break
	if entry_spec.is_empty(): return {"ok":false,"code":"sample.profile_entry_surface_missing","failure_state_unchanged":true}
	base.surface_id = str(entry_spec.surface_id)
	base.surface_kind = str(entry_spec.get("surface_kind", "floor"))
	base.display_name_zh = str(entry_spec.get("display_name_zh", "中性入口面"))
	base.world_origin_y = float(entry_spec.get("world_origin_y", 0.0))
	var size := Vector2(shell_configuration.map_size.x / shell_configuration.tile_size.x, shell_configuration.map_size.y / shell_configuration.tile_size.y)
	for spec in sample_profile.surface_specs:
		if str(spec.surface_id) == sample_profile.entry_surface_id: continue
		var surface := GMSurfaceDefinition3D.rectangle(str(spec.surface_id), shell_configuration.map_id, str(spec.get("surface_kind", "floor")), Vector3(0, float(spec.get("world_origin_y", 0.0)), 0), size)
		surface.display_name_zh = str(spec.get("display_name_zh", str(spec.surface_id)))
		var added: Dictionary = surface_graph_3d.register_surface(surface)
		if not added.ok: return added
	for spec in sample_profile.surface_specs:
		if str(spec.surface_id) == sample_profile.entry_surface_id: continue
		var semantic_added: Dictionary = semantic_registry.register_surface(shell_configuration.map_id, str(spec.surface_id))
		if not semantic_added.ok: return semantic_added
	for spec in sample_profile.connection_specs:
		var connection := GMSurfaceConnection.new()
		connection.connection_id = str(spec.connection_id)
		connection.source_map_id = shell_configuration.map_id
		connection.target_map_id = shell_configuration.map_id
		connection.source_surface_id = str(spec.from_surface_id)
		connection.target_surface_id = str(spec.to_surface_id)
		connection.connection_kind = str(spec.get("connection_kind", "link"))
		connection.source_exit = sample_profile.point(spec.source_exit)
		connection.target_entry = sample_profile.point(spec.target_entry)
		connection.traversal_cost = float(spec.cost)
		connection.enabled = not (connection.connection_id in sample_profile.temporarily_disabled_connection_ids and sample_profile.spatial_recovery_round > 0)
		var linked: Dictionary = surface_graph_3d.register_connection(connection)
		if not linked.ok: return linked
	var checked: Dictionary = surface_graph_3d.validate()
	if not checked.ok: return {"ok": false, "code": "sample.surface_graph_invalid", "reason_zh": "中性小院多Surface校验失败。", "details": checked}
	var map_result:Dictionary=semantic_registry.resolve_map(sample_profile.map_id)
	if not map_result.ok:return map_result
	var semantic_map:GMMapSemanticResource=map_result.map
	for facility in sample_profile.facility_specs:
		for target in facility.workspots:
			var anchor_result:Dictionary=semantic_registry.resolve_anchor(sample_profile.map_id,str(target.anchor_id))
			var anchor:GMSemanticAnchor
			if anchor_result.ok: anchor=anchor_result.anchor
			else: anchor=GMSemanticAnchor.new();anchor.anchor_id=str(target.anchor_id);semantic_map.anchors.append(anchor)
			anchor.surface_id=str(target.surface_id);anchor.position=sample_profile.point(target.logical_position);anchor.capacity=int(target.capacity)
	# Resource.duplicate(true) can alias typed subresource arrays in Godot 4.6.
	# Round-trip through the graph's public pure-value contract so the backend
	# receives a fully independent authored graph.
	var parsed_graph: Dictionary = GMSurfaceGraph.from_native(surface_graph_3d.to_native())
	if not parsed_graph.ok: return parsed_graph
	return map_backend_3d.configure_graph(parsed_graph.graph)

func _build_npcs() -> Dictionary:
	var workflow = WORKFLOW.new()
	var executed: Dictionary = workflow.execute(self, sample_profile, "3d", Callable(self, "_three_d_arrival_gate"))
	if not bool(executed.get("ok", false)): return executed
	workflow_result = executed
	process_service = executed.process_service
	resource_store = executed.resource_store
	npc_rows = executed.rows
	npc_characters = executed.characters
	workflow_projection = executed.projection
	var library := CHARACTER_LIBRARY.new()
	var scanned := library.scan(PackedStringArray(["res://gm_runtime/content/3d"] ))
	if not scanned.get("committed", false): return {"ok": false, "code": "sample.character_library_failed", "reason_zh": "中性角色资产库扫描失败。", "details": scanned}
	var visual_resolver = VISUAL_RESOLVER.new(library)
	var recipe_entry: Dictionary = library.entry_for_id("gm.character.visual_recipe.neutral")
	var recipe: GMCharacterVisualRecipe = recipe_entry.get("resource", null)
	if recipe == null: return {"ok": false, "code": "sample.character_recipe_missing", "reason_zh": "中性角色视觉配方不存在。"}
	for index in npc_rows.size():
		var row: Dictionary = npc_rows[index]
		var actor_id := str(row.actor_id)
		var logical: Dictionary = row.logical_position
		var surface: GMSurfaceDefinition3D = surface_graph_3d.resolve_surface(str(row.surface_id))
		if surface == null: return {"ok": false, "code": "sample.npc_surface_missing", "reason_zh": "NPC权威Surface无法解析。", "details": row}
		var holder: Node3D = workflow_3d_holders.get(actor_id, null)
		if holder == null: return {"ok": false, "code": "sample.3d_holder_missing", "reason_zh": "3D移动后端没有返回权威角色holder。", "details": row}
		holder.name = "NPC_%02d" % index
		holder.set_meta("gm_authoritative_surface_id", str(row.surface_id))
		holder.set_meta("gm_authoritative_logical_position", logical.duplicate(true))
		var assembler = VISUAL_ASSEMBLER.new()
		var assembled: Dictionary = assembler.assemble(holder, recipe, visual_resolver, "npc", actor_id)
		if not assembled.ok: return assembled
		var color := Color.from_hsv(float(index) / float(sample_profile.npc_count), 0.45, 0.85)
		var palette := assembler.set_palette({"palette_profile_id": "gm.character.palette.ext3d10.%02d" % index, "colors": {"all": color.to_html(), "outfit": color.darkened(0.25).to_html()}})
		if not palette.ok: return palette
		npc_assemblers.append(assembler)
		npc_holders.append(holder)
		row["recipe_id"] = recipe.content_id
		row["palette_profile_id"] = "gm.character.palette.ext3d10.%02d" % index
		row["holder_world_position"] = {"x": holder.position.x, "y": holder.position.y, "z": holder.position.z}
		row["holder_matches_authority"] = is_equal_approx(holder.position.y, surface.world_origin_y) and Vector2(holder.position.x, holder.position.z).distance_to(Vector2(float(logical.x), float(logical.y))) < 0.001
		npc_rows[index] = row
	return {"ok": true, "count": npc_rows.size()}

func _three_d_arrival_gate(actor_id: String, entity_id: String, _actual_position: Vector2, _expected_position: Vector2, round: int, plan: Dictionary, target: Dictionary) -> Dictionary:
	if round > sample_profile.spatial_recovery_round:
		for connection in surface_graph_3d.connections:
			if str(connection.connection_id) in sample_profile.temporarily_disabled_connection_ids:
				connection.enabled = true
		var configured: Dictionary = map_backend_3d.configure_graph(surface_graph_3d)
		if not configured.ok: return configured
	var spawn_spec: Dictionary = {}
	for spec in sample_profile.actor_specs:
		if str(spec.actor_id) == actor_id:
			spawn_spec = spec
			break
	var spawn := sample_profile.point(spawn_spec.get("spawn_logical", {}))
	var target_logical:=sample_profile.point(target.logical_position)
	var from := GMPlanarPosition.new(sample_profile.map_id, sample_profile.entry_surface_id, spawn.x, spawn.y)
	var to := GMPlanarPosition.new(sample_profile.map_id, str(target.surface_id), target_logical.x, target_logical.y)
	var route: Dictionary = adapter_3d.is_reachable(from, to)
	var transitions: Array = route.get("value", {}).get("surface_transitions", []) if bool(route.get("ok", false)) else []
	var trace: Array[String] = [sample_profile.entry_surface_id]
	for transition in transitions: trace.append(str(transition.get("to_surface_id", "")))
	if not bool(route.get("ok", false)) or not bool(route.get("value", {}).get("reachable", false)):
		return {"ok": false, "code": "sample.3d_surface_route_unavailable", "route": route}
	var actor := GMPlanar3DActor.new()
	actor.stable_instance_id = entity_id
	actor.map_id = shell_configuration.map_id
	actor.spatial_position = from.to_native()
	actor.movement_grant_source_id = "gm.planner.ext3d10"
	world_3d.add_child(actor)
	var mounted := actor.mount_movement(runtime_context, adapter_3d)
	if not bool(mounted.get("ok", false)): return mounted
	var target_context: Dictionary = plan.get("target_context", {})
	var request_data := {"schema": GMMovementRequest.SCHEMA, "kind": "anchor", "source": "ai", "owner_id": "gm.planner.ext3d10", "actor_id": entity_id, "map_id": sample_profile.map_id, "anchor_id": str(target.anchor_id), "target_actor_id": "", "route_id": "", "direction": {"x": 0.0, "y": 0.0}, "target_position": {"x": 0.0, "y": 0.0}, "speed": float(target_context.get("speed", 180.0)), "acceleration": float(target_context.get("acceleration", 1200.0)), "stop_distance": 0.05, "follow_distance": 8.0, "loop": false, "entry_anchor_id": "", "exit_anchor_id": "", "return_anchor_id": "", "target_map_id": "", "idempotency_key": "%s.gm.ability.movement.3d" % str(plan.get("plan_id", actor_id))}
	var submitted := actor.submit_movement_request("ai", request_data, str(request_data.idempotency_key))
	if not bool(submitted.get("ok", false)): return submitted
	var movement_steps := 0
	while movement_steps < WORKFLOW.MAX_MOVEMENT_STEPS and bool(actor.movement_snapshot().get("active", false)):
		actor.ability_host.tick(WORKFLOW.MOVEMENT_DELTA)
		movement_steps += 1
	var snapshot: Dictionary = actor.movement_snapshot()
	var position: Dictionary = snapshot.get("position", {})
	var arrived := not bool(snapshot.get("active", true)) and str(position.get("surface_id", "")) == to.surface_id and absf(float(position.get("x", -999.0)) - to.x) <= 0.05 and absf(float(position.get("y", -999.0)) - to.y) <= 0.05
	if arrived: workflow_3d_holders[actor_id] = actor
	return {"ok": arrived, "surface_id": to.surface_id, "surface_trace": trace, "transition_count": transitions.size(), "route": route, "movement_steps": movement_steps, "movement_snapshot": snapshot, "holder": actor}

func _combat_case(force_hit: bool = true, source_flow: Dictionary = {}) -> Dictionary:
	var attack: GMCombatAttackDefinition = GMCombatAttackDefinition.new().configure(sample_profile.attack_id, "中性训练投射", "projectile", "damage", 5.0, 8.0, 0.0, "", "gm.projectile.ext3d10.neutral")
	var projectile: GMCombatProjectileDefinition = GMCombatProjectileDefinition.new().configure("gm.projectile.ext3d10.neutral", "中性训练投射物", 10.0, 2.0, 0.1, 1)
	var hit_query := GMPlanarCombatAdapter3D.new(map_backend_3d)
	var resolver := GMCombatResolver.new(null, hit_query)
	var attack_registered := resolver.register_attack(attack)
	var projectile_registered := resolver.register_projectile(projectile)
	if not attack_registered.ok or not projectile_registered.ok: return {"ok": false, "code": "sample.combat_definition_failed"}
	var surface_id := str(shell_configuration.surface_id)
	var combat_surface: GMSurfaceDefinition3D = surface_graph_3d.resolve_surface(surface_id)
	if combat_surface == null: return {"ok": false, "code": "sample.combat_surface_missing"}
	var source := GMPlanarPosition.new(shell_configuration.map_id, surface_id, 4.0, 4.0)
	var target := GMPlanarPosition.new(shell_configuration.map_id, surface_id, 7.0, 4.0)
	var source_world: Vector3 = combat_surface.logical_to_world(Vector2(4.0, 4.0))
	var target_world: Vector3 = combat_surface.logical_to_world(Vector2(7.0, 4.0))
	var combat_actor_id := str(source_flow.get("actor_id", sample_profile.actor_specs[0].actor_id))
	var hit: GMCombatHitSpec = GMCombatHitSpec.new().configure("gm.hit.ext3d10.neutral", "projectile", combat_actor_id, "gm.actor.ext3d10.training_target", {"x": 1.0, "y": 0.0}, 3.0, 8.0)
	var flow_refs := {"task_id": str(source_flow.get("task_id", "")), "plan_id": str(source_flow.get("plan_id", "")), "process_instance_id": str(source_flow.get("process_instance_id", "")), "process_state": str(source_flow.get("process_state", ""))}
	var request: GMCombatRequest = GMCombatRequest.new().configure("gm.combat.request.ext3d10.neutral", "gm.ext3d10.combat.%s" % str(force_hit), "realtime", hit.source_id, hit.target_id, "gm.ability.ext3d10.combat", attack.attack_id, hit, "", projectile.projectile_id, {}, {"upstream_flow": flow_refs})
	var context := {"source_position": source.to_native(), "target_position": target.to_native(), "source_world_y": source_world.y, "target_world": {"x": target_world.x, "y": target_world.y, "z": target_world.z}, "target_point": {"schema": "gm.combat.target_point_3d.v1", "target_point_id": "gm.target_point.ext3d10.training", "target_ref": hit.target_id, "map_id": shell_configuration.map_id, "surface_id": surface_id, "height_tolerance": 0.75, "agent_profile": "default", "world_position": {"x": target_world.x, "y": target_world.y, "z": target_world.z}}, "force_hit": force_hit}
	var activation := GMAbilityActivationRequest.new(null, request.ability_id, "", null, {"source_id": request.source_id, "target_id": request.target_id, "combat_request": request.to_native(), "combat_query_context": context}, "gm.ext3d10.sample", {}, request.idempotency_key)
	var instance_id := activation.derive_instance_id()
	activation.event_data["ability_instance_id"] = instance_id
	var bound: Dictionary = activation.causal_chain.bind_ability_instance_identity(instance_id)
	if not bound.ok: return bound
	var linked: Dictionary = activation.causal_chain.add_ref(GMCausalRef.ability_instance(instance_id, activation.ability_id), [activation.request_id])
	if not linked.ok: return linked
	var changes := GMChangeRecordStore.new(); var facts := GMFactEventStore.new(changes); var coordinator := GMDomainTransactionCoordinator.new()
	var committed: Variant = coordinator.resolve(activation, resolver, facts, changes, {"resolver_id": resolver.resolver_id, "fact_type": GMCombatResolver.FACT_TYPE, "source_system": "gm.ext3d10", "ability_id": activation.ability_id, "ability_instance_id": activation.event_data.ability_instance_id}, activation.causal_chain)
	return {"ok": committed is GMCommittedFactResult, "status": "committed" if committed is GMCommittedFactResult else "blocked", "fact_count": facts.get_record_count(), "change_count": facts.get_change_record_count(), "cue_count": committed.cues.size() if committed is GMCommittedFactResult else 0, "result": committed.to_dict() if committed is GMCommittedFactResult else committed.to_dict() if committed is GMBlockedResult else committed}

func _parity_projection(dimension: String) -> Dictionary:
	var shared := {"definition_id": sample_profile.task_definition_id, "seed": sample_profile.seed, "task_count": npc_rows.size(), "task_states": [], "process_states": [], "targets": []}
	for row in npc_rows:
		shared.task_states.append(str(task_service.read_task(row.task_id).get("state", "")))
		shared.process_states.append(str(row.process_state))
		shared.targets.append({"actor_id":row.actor_id,"facility_id":row.facility_id,"workspot_id":row.workspot_id})
	shared.task_states.sort(); shared.process_states.sort()
	var source := GMPlanarPosition.new(shell_configuration.map_id, shell_configuration.surface_id, 4.0, 4.0)
	var target := GMPlanarPosition.new(shell_configuration.map_id, shell_configuration.surface_id, 7.0, 4.0)
	var spatial: Dictionary = adapter_3d.get_planar_distance(source, target) if dimension == "3d" else adapter_2d.get_planar_distance(source, target)
	shared["spatial_ok"] = bool(spatial.get("ok", false))
	shared["planar_distance"] = float(spatial.get("value", {}).get("distance", -1.0))
	return shared

func _surface_contract() -> Dictionary:
	var target:=sample_profile.player_target();var logical:=sample_profile.point(target.logical_position)
	var from := GMPlanarPosition.new(sample_profile.map_id, sample_profile.entry_surface_id, 4.0, 4.0)
	var to := GMPlanarPosition.new(sample_profile.map_id, str(target.surface_id), logical.x, logical.y)
	var reachable: Dictionary = adapter_3d.is_reachable(from, to)
	var transitions:Array=reachable.get("value",{}).get("surface_transitions",[]) if reachable.ok else []
	if transitions.is_empty():return {"ok":false,"code":"sample.target_route_transition_missing","reachable":reachable}
	var selected_id:="";var blocked:Dictionary={}
	for transition in transitions:
		var candidate_id:=str(transition.connection_id);var candidate:GMSurfaceConnection=null
		for connection in surface_graph_3d.connections:
			if str(connection.connection_id)==candidate_id:candidate=connection;break
		if candidate==null:continue
		candidate.enabled=false
		var disabled_configured:Dictionary=map_backend_3d.configure_graph(surface_graph_3d)
		var candidate_blocked:Dictionary=adapter_3d.is_reachable(from,to) if disabled_configured.ok else disabled_configured
		candidate.enabled=true
		var restored_configured:Dictionary=map_backend_3d.configure_graph(surface_graph_3d)
		if not restored_configured.ok:return restored_configured
		if candidate_blocked.ok and not bool(candidate_blocked.get("value",{}).get("reachable",true)):
			selected_id=candidate_id;blocked=candidate_blocked;break
	if selected_id.is_empty():return {"ok":false,"code":"sample.target_route_cut_connection_missing","reachable":reachable,"failure_state_unchanged":true}
	return {"ok": true, "reachable": reachable, "blocked": blocked, "selected_path_connection_id":selected_id,"failure_state_unchanged": surface_graph_3d.connections.size() == sample_profile.connection_specs.size()}

func _build_surface_visuals() -> void:
	if world_3d == null: return
	for index in surface_graph_3d.surfaces.size():
		var surface: GMSurfaceDefinition3D = surface_graph_3d.surfaces[index]
		var mesh := MeshInstance3D.new(); mesh.name = "Surface_%s" % str(surface.surface_id).get_file(); var box := BoxMesh.new(); box.size = Vector3(8.0, 0.18, 5.0); mesh.mesh = box; mesh.position = Vector3(12.0 + index * 2.0, surface.world_origin_y, 10.0); mesh.material_override = _material(Color.from_hsv(float(index) / 5.0, 0.35, 0.55), Color(0.02, 0.03, 0.05)); world_3d.add_child(mesh)

func _run_ext10_contract() -> void:
	await get_tree().process_frame
	if not vertical_ready or process_service == null:
		var failed_report := {"schema": "gm.ext3d10.contract_summary.v2", "event": "GM_EXT_3D_10_CONTRACT_SENTINEL", "ok": false, "vertical_error": vertical_error}
		print("GM_EXT_3D_10_CONTRACT_RESULT " + JSON.stringify(failed_report))
		get_tree().quit(1)
		return
	var assigned := assign_task("gm.ext3d10.player.assign")
	var interaction := interact_with_key("gm.ext3d10.player.interact")
	var surface := _surface_contract()
	var source_flow: Dictionary = npc_rows[0] if not npc_rows.is_empty() else {}
	var combat := _combat_case(true, source_flow)
	var combat_blocked := _combat_case(false, source_flow)
	var before_invalid := task_service.snapshot()
	var invalid_restore: Dictionary = task_service.restore_snapshot({"bad": true})
	var process_before_gate_failure: Dictionary = process_service.snapshot()
	var premature_process_blocked := not WORKFLOW.process_gate_allows(false, "active", {"ok": true}) and process_service.snapshot() == process_before_gate_failure
	var lifecycle_closed := _rows_close_authoritative_lifecycle()
	vertical_ready = vertical_ready and bool(_composition_context().get("matches_profile", false))
	var report := {"schema": "gm.ext3d10.contract_summary.v4", "event": "GM_EXT_3D_10_CONTRACT_SENTINEL", "ok": vertical_ready and str(assigned.get("status", "")) == "committed" and str(interaction.get("status", "")) == "committed" and surface.ok and combat.ok and combat.fact_count == 1 and combat.change_count > 0 and combat.cue_count > 0 and combat_blocked.ok and npc_rows.size() == sample_profile.actor_specs.size() and lifecycle_closed and premature_process_blocked and not invalid_restore.ok and task_service.snapshot() == before_invalid, "seed": sample_profile.seed, "npc_count": npc_rows.size(), "surface": surface, "facility_process": {"targets":npc_rows.map(func(row):return {"actor_id":row.actor_id,"facility_id":row.facility_id,"workspot_id":row.workspot_id,"definition_id":row.process_definition_id}), "completed_count": npc_rows.size(), "all_processes_after_authoritative_arrival_and_reservation": lifecycle_closed, "premature_process_blocked": premature_process_blocked}, "blocked_events": workflow_result.get("blocked_events", []), "retry_summary": workflow_result.get("retry_summary", {}), "composition_context":_composition_context(),"combat": combat, "combat_miss": combat_blocked, "independent_run": {"dimension": "3d", "projection": workflow_projection, "rows": npc_rows, "comparison_contract": "compare with a separate GM_EXT_3D_10_2D_SENTINEL process using the same formal profile"}, "interaction": interaction, "failure_atomic": premature_process_blocked and not invalid_restore.ok and task_service.snapshot() == before_invalid, "unified_authorities": {"task_store": task_service.STORE_ID, "process_store": process_service.process_store.STORE_ID, "resource_store": resource_store.store_id, "save_root": "GMSimulationWorld/GMStore", "second_fact_store": false}, "vertical_error": vertical_error}
	var evidence := WORKFLOW.write_json_if_requested(report)
	report["evidence_write"] = evidence
	print("GM_EXT_3D_10_CONTRACT_RESULT " + JSON.stringify(report))
	get_tree().quit(0 if report.ok and bool(evidence.get("ok", false)) else 1)

func _rows_close_authoritative_lifecycle() -> bool:
	if npc_rows.size() != sample_profile.actor_specs.size() or npc_holders.size() != npc_rows.size(): return false
	for row in npc_rows:
		if not bool(row.get("arrival_verified", false)) or str(row.get("reservation_state_at_process", "")) != "active" or str(row.get("reservation_final_state", "")) != "consumed" or not bool(row.get("process_started_after_gate", false)) or str(row.get("process_state", "")) != "completed" or not bool(row.get("holder_matches_authority", false)):
			return false
	return true

func _run_ext10_pack_inventory() -> void:
	await get_tree().process_frame
	var files := WORKFLOW.pack_file_inventory()
	var report := {"schema": "gm.ext3d10.pack_inventory.v1", "event": "GM_EXT_3D_10_PACK_INVENTORY_SENTINEL", "ok": true, "delivery": "enabled", "entry_scene": "res://gm_runtime/vertical_sample/gm_ext_3d_10_entry.tscn", "file_count": files.size(), "files": files}
	var written := WORKFLOW.write_json_if_requested(report)
	print("GM_EXT_3D_10_PACK_INVENTORY_RESULT " + JSON.stringify({"ok": bool(written.get("ok", false)), "delivery": "enabled", "file_count": files.size(), "written": written}))
	get_tree().quit(0 if bool(written.get("ok", false)) else 1)

func _run_ext10_record() -> void:
	await get_tree().process_frame
	world_2d.visible = false
	world_3d.visible = true
	if camera_rig_3d != null and camera_rig_3d.camera != null: camera_rig_3d.camera.current = false
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 34.0
	camera.position = Vector3(21.0, 24.0, 27.0)
	world_3d.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(18.0, 3.0, 9.0), Vector3.UP)
	camera.current = true
	var overlay := Label.new()
	overlay.position = Vector2(24.0, 176.0)
	overlay.add_theme_font_size_override("font_size", 24)
	overlay.add_theme_color_override("font_color", Color.WHITE)
	ui_root.add_child(overlay)
	var first_spawn := sample_profile.point(sample_profile.actor_specs[0].spawn_logical)
	var stages: Array[Dictionary] = [{"id": "task_planner_reservation", "label": "Task → Planner → Reservation（权威收据已提交）", "surface": sample_profile.entry_surface_id, "logical": first_spawn}]
	var trace: Array = npc_rows[0].get("surface_trace", []) if not npc_rows.is_empty() else []
	for trace_index in range(1, trace.size()):
		var from_surface := str(trace[trace_index - 1])
		var to_surface := str(trace[trace_index])
		var transition_position := sample_profile.point(sample_profile.player_target().logical_position)
		var transition_id := "surface_transition_%s" % to_surface.replace(".", "_")
		for connection in surface_graph_3d.connections:
			if str(connection.source_surface_id) == from_surface and str(connection.target_surface_id) == to_surface:
				transition_position = connection.target_entry
				transition_id = str(connection.connection_id)
				break
		stages.append({"id": transition_id, "label": "Move Ability：到达 Surface %s" % to_surface, "surface": to_surface, "logical": transition_position})
	var player_target:=sample_profile.player_target()
	stages.append({"id": "process_transaction_fact", "label": "到达＋有效预约 → Process → Transaction → Fact/Change/Cue", "surface": str(player_target.surface_id), "logical": sample_profile.point(player_target.logical_position)})
	var timeline: Array = []
	var frame := 0
	for stage in stages:
		overlay.text = "GM-EXT-3D-10 中性纵向样板\n%s\n%d NPC · seed %d" % [str(stage.label), sample_profile.actor_specs.size(), sample_profile.seed]
		_set_record_holders(str(stage.surface), stage.logical)
		var start_frame := frame
		for _step in 60:
			await get_tree().process_frame
			frame += 1
		timeline.append({"stage_id": str(stage.id), "label_zh": str(stage.label), "start_frame": start_frame, "end_frame": frame - 1, "start_second": float(start_frame) / 60.0, "end_second": float(frame) / 60.0, "surface_id": str(stage.surface)})
	var report := {"schema": "gm.ext3d10.operation_video_index.v1", "event": "GM_EXT_3D_10_OPERATION_VIDEO_SENTINEL", "ok": _rows_close_authoritative_lifecycle(), "video": "operation_full.avi", "fps": 60, "indexed_stage_frames": frame, "movie_frame_count": frame + 1, "capture_header_frames": 1, "duration_seconds": float(frame + 1) / 60.0, "timeline": timeline, "authority_note": "录像由正式产品场景按本轮真实 Task/Planner/Reservation/Move/Process 收据投影回放；Godot write-movie在首个Stage帧前记录1个捕获头帧；未调用私有成功入口。", "source_contract": {"npc_count": npc_rows.size(), "projection": workflow_projection}}
	var written := WORKFLOW.write_json_if_requested(report)
	print("GM_EXT_3D_10_OPERATION_VIDEO_RESULT " + JSON.stringify({"ok": bool(report.ok) and bool(written.get("ok", false)), "frames": frame, "written": written}))
	get_tree().quit(0 if bool(report.ok) and bool(written.get("ok", false)) else 1)

func _set_record_holders(surface_id: String, logical_base: Vector2) -> void:
	var surface: GMSurfaceDefinition3D = surface_graph_3d.resolve_surface(surface_id)
	if surface == null: return
	for index in npc_holders.size():
		var offset := Vector2(float(index % 5) * 0.7 - 1.4, float(index / 5) * 0.8 - 0.4)
		npc_holders[index].position = surface.logical_to_world(logical_base + offset)

func _run_ext10_save() -> void:
	await get_tree().process_frame
	assign_task("gm.ext3d10.save.assign")
	interact_with_key("gm.ext3d10.save.interact")
	shell_configuration.save_path = sample_profile.save_path
	var saved := save_world_snapshot()
	print("GM_EXT_3D_10_SAVE_RESULT " + JSON.stringify({"ok": saved.ok, "path": sample_profile.save_path, "npc_count": npc_rows.size(), "single_save_root": true}))
	get_tree().quit(0 if saved.ok else 1)

func _run_ext10_restore() -> void:
	await get_tree().process_frame
	shell_configuration.save_path = sample_profile.save_path
	var restored := restore_world_snapshot()
	var profile_value: Dictionary = player_shell_store.read("ext3d10_profile")
	var process_value: Dictionary = player_shell_store.read("ext3d10_process")
	var process_restored := process_service.restore_snapshot(process_value)
	var npc_value: Dictionary = player_shell_store.read("ext3d10_npcs")
	var profile_equal := _profile_value_matches(profile_value)
	var resource_value: Dictionary = player_shell_store.read("ext3d10_resource")
	var resource_restored := resource_store.restore_snapshot(resource_value)
	var composition_context:=_composition_context();var context_equal:=bool(composition_context.get("matches_profile",false))
	var ok: bool = restored.ok and process_restored.ok and resource_restored.ok and profile_equal and context_equal and Array(npc_value.get("rows", [])).size() == sample_profile.actor_specs.size()
	print("GM_EXT_3D_10_RESTORE_RESULT " + JSON.stringify({"ok": ok, "path": sample_profile.save_path, "npc_count": Array(npc_value.get("rows", [])).size(), "process_restored": process_restored.ok, "profile_equal": profile_equal,"composition_context":composition_context, "single_save_root": true, "restore": restored, "process_restore": process_restored, "store_keys": player_shell_store.keys()}))
	get_tree().quit(0 if ok else 1)

func _profile_value_matches(value: Dictionary) -> bool:
	return GMStableData.persistence_canonical_json(value) == GMStableData.persistence_canonical_json(sample_profile.to_native())

func _composition_context()->Dictionary:
	var recipe_id:=str(scene_session_definition.recipe.get("recipe_id","")) if scene_session_definition!=null else ""
	var context_seed:=int(scene_session_definition.context.get("seed",-1)) if scene_session_definition!=null else -1
	var projected_task_definition:=str(task_projection().get("definition_id",""))
	var value:={"seed":shell_configuration.seed,"scene_context_seed":context_seed,"scene_definition_id":str(scene_session_definition.definition_id) if scene_session_definition!=null else "","scene_recipe_id":recipe_id,"player_task_definition_id":projected_task_definition}
	value["matches_profile"]=int(value.seed)==sample_profile.seed and int(value.scene_context_seed)==sample_profile.seed and str(value.scene_definition_id)==sample_profile.scene_definition_id and str(value.scene_recipe_id)==sample_profile.scene_recipe_id and str(value.player_task_definition_id)==sample_profile.player_task_definition_id
	return value

func _capture_p25_contributors() -> Dictionary:
	var captured: Dictionary = super._capture_p25_contributors()
	if not captured.ok: return captured
	var additions := [
		["ext3d10_profile", sample_profile.to_native()],
		["ext3d10_process", process_service.snapshot()],
		["ext3d10_resource", resource_store.snapshot()],
		["ext3d10_npcs", {"rows": npc_rows}],
	]
	for row in additions:
		var written: Dictionary = player_shell_store.put(str(row[0]), row[1])
		if not written.ok: return written
	return {"ok": true, "store_id": P25_STORE_ID, "keys": player_shell_store.keys(), "record_count": player_shell_store.keys().size()}
