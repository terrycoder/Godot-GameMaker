extends Node

const REGISTRY := preload("res://gm_runtime/gm_module_registry.gd")
const PROFILE := preload("res://gm_runtime/gm_project_profile.gd")
const INDEX := preload("res://gm_runtime/gm_module_manifest_index.gd")
const TASK_SERVICE := preload("res://gm_runtime/tasks/gm_task_service.gd")
const TASK_DEFINITION := preload("res://gm_runtime/tasks/gm_task_definition.gd")
const ABILITY_HOST := preload("res://gm_runtime/gas/gm_ability_system_host.gd")
const COMMITTED_RESULT := preload("res://gm_runtime/events/gm_committed_fact_result.gd")
const MAP_REGISTRY := preload("res://gm_runtime/map/semantic/gm_map_semantic_registry.gd")
const MAP_RESOURCE := preload("res://gm_runtime/map/gm_map_resource.gd")
const SEMANTIC_MAP := preload("res://gm_runtime/map/semantic/gm_map_semantic_resource.gd")
const ANCHOR := preload("res://gm_runtime/map/semantic/gm_semantic_anchor.gd")
const CHARACTER := preload("res://gm_runtime/characters/gm_character_runtime_2d.gd")
const MOVEMENT_EXECUTOR := preload("res://gm_runtime/movement/gm_movement_ability_executor.gd")
const MOVEMENT_REQUEST := preload("res://gm_runtime/movement/gm_movement_request.gd")
const ADAPTER := preload("res://gm_adapters/spatial/gm_planar_2d_spatial_adapter.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

const ENABLED_INDEX_PATH := "res://gm_runtime/manifests/p23_enabled_manifest_index.tres"
const DISABLED_INDEX_PATH := "res://gm_runtime/manifests/p23_disabled_manifest_index.tres"
const ENABLED_PROFILE_PATH := "res://gm_runtime/manifests/p23_enabled_profile.tres"
const DISABLED_PROFILE_PATH := "res://gm_runtime/manifests/p23_disabled_profile.tres"
const SCENE_SESSION_PATH := "res://gm_runtime/scene/gm_task_execution_session.gd"

func _ready() -> void:
	var has_enabled_feature := OS.has_feature("p23_enabled")
	var has_disabled_feature := OS.has_feature("p23_disabled")
	var enabled := has_enabled_feature or not has_disabled_feature
	var report := _run_product(enabled, has_disabled_feature)
	print("P23_PRODUCT_STARTUP=" + JSON.stringify(report, "", true, true))
	get_tree().quit(0 if bool(report.get("ok", false)) else 1)

func _run_product(enabled: bool, is_disabled_pack: bool) -> Dictionary:
	var index_path := ENABLED_INDEX_PATH if enabled else DISABLED_INDEX_PATH
	var profile_path := ENABLED_PROFILE_PATH if enabled else DISABLED_PROFILE_PATH
	var index_value: Variant = ResourceLoader.load(index_path)
	var profile_value: Variant = ResourceLoader.load(profile_path)
	if index_value == null or not index_value is INDEX:
		return _failure("product.index_missing", "P23产品ManifestIndex加载失败。", {"path": index_path})
	if profile_value == null or not profile_value is PROFILE:
		return _failure("product.profile_missing", "P23产品Profile加载失败。", {"path": profile_path})
	var mounted: Dictionary = _mount_index(index_value)
	if not mounted.ok:
		return mounted
	var profile_check: Dictionary = profile_value.validate_spatial_selection(profile_value.enabled_modules)
	if not profile_check.ok:
		return _failure("product.profile_invalid", "P23产品Profile空间选择校验失败。", profile_check)
	var resolution: Dictionary = REGISTRY.resolve(profile_value.enabled_modules)
	if not resolution.ok:
		return _failure("product.modules_invalid", "P23产品模块依赖解析失败。", resolution)
	var view: Dictionary = REGISTRY.current_view_result()
	var base := {
		"mode": "enabled" if enabled else "disabled",
		"profile": profile_path,
		"manifest_index": index_path,
		"selected_modules": resolution.selected,
		"registry_generation": int(view.get("generation", 0)),
		"spatial_profile_active": bool(profile_check.get("active", false)),
		"spatial_backend_id": str(profile_check.get("backend_id", profile_value.spatial_backend_id)),
		"p15_entry_present": ResourceLoader.exists("res://gm_runtime/movement/gm_p15_export_entry.tscn"),
		"p16_entry_present": ResourceLoader.exists("res://gm_runtime/tasks/gm_p16_export_entry.tscn")
	}
	if not enabled:
		# Source-tree runs intentionally keep the full repository visible. The real
		# disabled PCK is the authoritative crop check and must omit all P23 scene code.
		var residue_ok := true if not is_disabled_pack else not ResourceLoader.exists(SCENE_SESSION_PATH)
		base["scene_runtime_omitted"] = residue_ok
		base["scene_runtime_probe"] = "checked" if is_disabled_pack else "source_tree_only"
		base["ok"] = residue_ok and bool(base.p15_entry_present) and bool(base.p16_entry_present) and not bool(profile_check.get("active", true))
		if not base.ok:
			base["error"] = {"code": "product.disabled_crop_invalid", "scene_session_path": SCENE_SESSION_PATH}
		return base
	var enabled_result := _run_enabled_product()
	for key in enabled_result: base[key] = enabled_result[key]
	base["ok"] = bool(enabled_result.get("ok", false))
	return base

func _mount_index(index_value: INDEX) -> Dictionary:
	var manifests: Array[Resource] = []
	for path in index_value.manifest_paths:
		var manifest: Variant = ResourceLoader.load(str(path))
		if manifest == null or not manifest is GMModuleManifest:
			return _failure("product.manifest_missing", "P23产品Manifest加载失败。", {"path": str(path)})
		manifests.append(manifest)
	REGISTRY.set_runtime_manifests(manifests, true)
	var refreshed: Dictionary = REGISTRY.refresh_result()
	if not refreshed.ok:
		return _failure("product.registry_refresh_failed", "P23产品Manifest视图提交失败。", refreshed)
	return {"ok": true, "manifest_count": manifests.size(), "registry": refreshed}

func _run_enabled_product() -> Dictionary:
	var task_service := TASK_SERVICE.new()
	var host := ABILITY_HOST.new()
	var definition := TASK_DEFINITION.new()
	definition.definition_id = "gm.definition.p23.product"
	definition.display_name_zh = "P23产品链路任务"
	definition.description_zh = "P16执行请求经P15旅行交接进入P23"
	var return_context := {
		"schema_version": "gm.scene.return_context.v1",
		"map_id": "gm.map.p23.source",
		"anchor_id": "gm.anchor.return",
		"position": PLANAR_POSITION.new("gm.map.p23.source", "gm.surface.p23.product", 16.0, 48.0).to_native()
	}
	var stable_context := {
		"target": {"type": "task_target", "id": "gm.target.p23.product"},
		"participants": [{"type": "actor", "id": "gm.actor.p23.product"}],
		"resources": [{"type": "resource", "id": "gm.resource.p23.product"}],
		"constraints": {"allow_hostile_remaining": true},
		"seed": 11,
		"return_context": return_context
	}
	var register: Variant = task_service.submit_operation(host, "register_definition", definition.to_dict(), "script", "gm.source.p23.product", "p23.product.register")
	if not _committed(register): return _stage_failure("p16_register", register)
	var task_id := "gm.task.p23.product"
	var assignment_id := "gm.assignment.p23.product"
	var publish: Variant = task_service.submit_operation(host, "publish_task", {
		"task_id": task_id,
		"definition_id": definition.definition_id,
		"parent_task_id": "",
		"group_id": "",
		"execution_context": {"mode": "scene", "stable_context": stable_context}
	}, "script", "gm.source.p23.product", "p23.product.publish")
	if not _committed(publish): return _stage_failure("p16_publish", publish)
	var assign: Variant = task_service.submit_operation(host, "assign", {
		"assignment_id": assignment_id,
		"task_id": task_id,
		"assignee": {"type": "actor", "id": "gm.actor.p23.product"},
		"kind": "actor"
	}, "script", "gm.source.p23.product", "p23.product.assign")
	if not _committed(assign): return _stage_failure("p16_assign", assign)
	var transition: Variant = task_service.submit_operation(host, "transition", {
		"task_id": task_id,
		"to_state": "in_progress",
		"reason_code": "task.p23.started",
		"result": {}
	}, "script", "gm.source.p23.product", "p23.product.transition")
	if not _committed(transition): return _stage_failure("p16_transition", transition)
	var execution := task_service.build_execution_request(host, task_id, assignment_id, "gm.ability.scene.execution", {"scene_recipe_id": "gm.recipe.p23.product"}, "p23.product.execution")
	if not execution.ok or execution.get("request", null) == null:
		return _stage_failure("p16_execution_request", execution)
	var request_dict: Dictionary = execution.request_dict
	var task_execution_context: Dictionary = request_dict.get("event_data", {}).get("task_execution_context", {})
	var context_script: Variant = load("res://gm_runtime/scene/gm_task_execution_context.gd")
	var context_check: Dictionary = context_script.from_task_context(task_execution_context)
	if not context_check.ok: return _stage_failure("p23_context", context_check)
	var context_value: Object = context_check.value
	var maps := MAP_REGISTRY.new()
	var source_map := _make_map("gm.map.p23.source", [
		{"id": "gm.anchor.entry", "position": Vector2(16.0, 16.0)},
		{"id": "gm.anchor.goal", "position": Vector2(48.0, 16.0)},
		{"id": "gm.anchor.return", "position": Vector2(16.0, 48.0)}
	])
	var target_map := _make_map("gm.map.p23.target", [
		{"id": "gm.anchor.entry", "position": Vector2(16.0, 16.0)},
		{"id": "gm.anchor.exit", "position": Vector2(48.0, 16.0)}
	])
	if not maps.register_map(source_map).ok or not maps.register_map(target_map).ok:
		return _failure("p15_map_registration", "P15产品语义地图注册失败。")
	var actor := CHARACTER.new()
	actor.stable_instance_id = "gm.actor.p23.product"
	actor.map_id = "gm.map.p23.source"
	actor.spawn_anchor_id = "gm.anchor.entry"
	actor.position = Vector2(16.0, 16.0)
	add_child(actor)
	var executor := MOVEMENT_EXECUTOR.new(maps)
	var actor_registered := executor.register_actor(actor.stable_instance_id, actor, actor.map_id)
	if not actor_registered.ok: return _stage_failure("p15_actor", actor_registered)
	var movement_data := {
		"schema": MOVEMENT_REQUEST.SCHEMA,
		"kind": "anchor",
		"source": "script",
		"owner_id": actor.stable_instance_id,
		"actor_id": actor.stable_instance_id,
		"map_id": actor.map_id,
		"anchor_id": "gm.anchor.goal",
		"speed": 160.0,
		"acceleration": 1200.0,
		"stop_distance": 0.5,
		"follow_distance": 8.0,
		"idempotency_key": "p23.product.direct"
	}
	var movement_check := MOVEMENT_REQUEST.from_dict(movement_data)
	if not movement_check.ok: return _stage_failure("p15_movement_request", movement_check)
	var started := executor.start_request(movement_check.request, actor)
	if not started.ok: return _stage_failure("p15_movement_start", started)
	var direct_result := started
	for _step in 120:
		direct_result = executor.tick_command(str(started.command_id), 0.025)
		if bool(direct_result.get("completed", false)): break
	if not direct_result.ok or not direct_result.completed:
		return _stage_failure("p15_movement_complete", direct_result)
	var travel_data := movement_data.duplicate(true)
	travel_data.kind = "travel"
	travel_data.erase("anchor_id")
	travel_data.entry_anchor_id = "gm.anchor.entry"
	travel_data.exit_anchor_id = "gm.anchor.exit"
	travel_data.return_anchor_id = "gm.anchor.return"
	travel_data.target_map_id = "gm.map.p23.target"
	travel_data.idempotency_key = "p23.product.travel"
	var travel_check := MOVEMENT_REQUEST.from_dict(travel_data)
	if not travel_check.ok: return _stage_failure("p15_travel_request", travel_check)
	var travel := executor.start_request(travel_check.request, actor)
	if not travel.ok or not travel.completed or travel.scene_session_created or str(travel.deferred_to) != "P23":
		return _stage_failure("p15_travel_handoff", travel)
	var skeleton_script: Variant = load("res://gm_runtime/scene/gm_scene_skeleton_definition.gd")
	var slot_script: Variant = load("res://gm_runtime/scene/gm_semantic_slot_2d.gd")
	var recipe_script: Variant = load("res://gm_runtime/scene/gm_scene_recipe.gd")
	var definition_script: Variant = load("res://gm_runtime/scene/gm_scene_session_definition.gd")
	var target_script: Variant = load("res://gm_runtime/spatial_core/gm_spatial_target_ref.gd")
	var entry_target_check: Dictionary = target_script.from_native({"schema_version": 1, "domain_id": "gm.spatial.planar_2d", "kind": "anchor", "semantic_id": "gm.anchor.entry", "map_id": "gm.map.p23.target"})
	var exit_target_check: Dictionary = target_script.from_native({"schema_version": 1, "domain_id": "gm.spatial.planar_2d", "kind": "anchor", "semantic_id": "gm.anchor.exit", "map_id": "gm.map.p23.target"})
	if not entry_target_check.ok or not exit_target_check.ok: return _failure("p23_targets", "P23产品空间目标构造失败.")
	var entry_ref: Dictionary = entry_target_check.target.to_native()
	var exit_ref: Dictionary = exit_target_check.target.to_native()
	var skeleton_slots: Array = []
	for pair in [["slot.entry", "entry"], ["slot.exit", "exit"], ["slot.objective", "objective"], ["slot.resource", "resource"], ["slot.hostile", "hostile"], ["slot.facility", "facility"], ["slot.extraction", "extraction"]]:
		skeleton_slots.append(slot_script.new(str(pair[0]), str(pair[1])).to_dict())
	var skeleton: Object = skeleton_script.new("gm.skeleton.p23.product", "P23产品骨架", ["gm.spatial.planar_2d", "gm.spatial.planar_3d"], [{"region_id": "gm.region.p23.product", "region_kind": "arena", "required": true, "tags": ["product"]}], skeleton_slots, ["route_a", "route_b"])
	var recipe_slots: Array = [
		slot_script.new("slot.entry", "entry", entry_ref).to_dict(),
		slot_script.new("slot.exit", "exit", exit_ref).to_dict(),
		slot_script.new("slot.objective", "objective", {"type": "object", "id": "gm.object.p23.product"}).to_dict(),
		slot_script.new("slot.resource", "resource", {"type": "resource", "id": "gm.resource.p23.product"}).to_dict(),
		slot_script.new("slot.hostile", "hostile", {"type": "actor_group", "id": "gm.actor.hostiles.p23.product"}).to_dict(),
		slot_script.new("slot.facility", "facility", {"type": "facility", "id": "gm.facility.p23.product"}).to_dict(),
		slot_script.new("slot.extraction", "extraction", exit_ref).to_dict()
	]
	var recipe: Object = recipe_script.new(
		"gm.recipe.p23.product", "P23产品配方", skeleton.skeleton_id, entry_ref, exit_ref,
		["entry", "exit", "objective", "resource", "hostile", "facility", "extraction"],
		[{"object_id": "gm.object.p23.product", "object_kind": "beacon", "required": true, "tags": ["objective"]}],
		[{"region_id": "gm.region.p23.product", "region_kind": "arena", "required": true, "tags": ["product"]}],
		recipe_slots, context_value.participants,
		[{"objective_id": "gm.objective.p23.product", "kind": "reach", "target_value": 1, "contribution_field": "reach", "target_ref": {}, "requires_hostile_clear": false}],
		[
			{"result_id": "gm.result.p23.success", "status": "success", "required_objective_ids": ["gm.objective.p23.product"], "reason_code": "scene.objectives.completed"},
			{"result_id": "gm.result.p23.partial", "status": "partial_success", "required_objective_ids": [], "reason_code": "scene.extraction.partial"},
			{"result_id": "gm.result.p23.extracted", "status": "extracted", "required_objective_ids": [], "reason_code": "scene.extraction.voluntary"},
			{"result_id": "gm.result.p23.failed", "status": "failed", "required_objective_ids": [], "reason_code": "scene.execution.failed"}
		], ["route_a", "route_b"]
	)
	var definition_object: Object = definition_script.new("gm.definition.scene.p23.product", context_value.task_id, context_value.assignment_id, context_value.to_dict(), skeleton.to_dict(), recipe.to_dict(), return_context)
	var definition_check: Dictionary = definition_object.validate()
	if not definition_check.ok: return _stage_failure("p23_definition", definition_check)
	var adapter := ADAPTER.new(maps, true)
	var builder_script: Variant = load("res://gm_runtime/scene/gm_scene_recipe_builder.gd")
	var builder: Object = builder_script.new()
	var session_script: Variant = load(SCENE_SESSION_PATH)
	var opened: Dictionary = session_script.from_travel_handoff(travel, definition_object, builder, adapter)
	if not opened.ok: return _stage_failure("p23_open", opened)
	var session: Object = opened.session
	var snapshot_json: String = session.snapshot_json()
	var reopened: Dictionary = session_script.from_travel_handoff(travel, definition_object, builder, adapter)
	if not reopened.ok: return _stage_failure("p23_reopen", reopened)
	var restored: Dictionary = reopened.session.restore_snapshot_json(snapshot_json)
	if not restored.ok: return _stage_failure("p23_restore", restored)
	var fact_script: Variant = load("res://gm_runtime/scene/gm_execution_facts.gd")
	var fact: Object = fact_script.new("gm.scene.fact.p23.product", reopened.session.state.session_id, 1, "objective_progress", {"type": "actor", "id": actor.stable_instance_id}, {}, {"completed": true}, {"reach": 1}, [], [], {})
	var recorded: Dictionary = reopened.session.record_fact(fact)
	if not recorded.ok or str(reopened.session.state.phase) != "succeeded": return _stage_failure("p23_fact", recorded)
	var returned: Dictionary = reopened.session.request_return()
	if not returned.ok or str(reopened.session.state.phase) != "returned": return _stage_failure("p23_return", returned)
	return {
		"ok": true,
		"p16_execution_request": true,
		"p16_task_id": task_id,
		"p16_assignment_id": assignment_id,
		"p15_movement_completed": true,
		"p15_travel_completed": true,
		"p15_deferred_to": str(travel.deferred_to),
		"p23_session_opened": true,
		"p23_snapshot_restored": true,
		"p23_result_status": str(reopened.session.state.result.get("status", "")),
		"p23_return_map_id": str(returned.return_context.get("map_id", "")),
		"p23_return_anchor_id": str(returned.return_context.get("anchor_id", "")),
		"snapshot_fingerprint": snapshot_json.sha256_text()
	}

func _make_map(map_id: String, anchors: Array) -> SEMANTIC_MAP:
	var terrain := MAP_RESOURCE.new()
	terrain.map_id = map_id
	terrain.map_size = Vector2i(4, 4)
	terrain.tile_size = Vector2i(32, 32)
	for y in range(4):
		for x in range(4): terrain.set_logic_cell(Vector2i(x, y), {"ground_type": "floor", "walkable": true, "cost": 1.0})
	var resource := SEMANTIC_MAP.new()
	resource.map_id = map_id
	resource.terrain_map = terrain
	resource.surface_ids = PackedStringArray(["gm.surface.p23.product"])
	for row in anchors:
		var anchor := ANCHOR.new()
		anchor.anchor_id = str(row.id)
		anchor.position = row.position
		resource.anchors.append(anchor)
	return resource

func _committed(value: Variant) -> bool:
	return value is COMMITTED_RESULT

func _stage_failure(stage: String, value: Variant) -> Dictionary:
	var details: Variant = value.to_dict() if value is Object and value.has_method("to_dict") else value
	return _failure("product.%s_failed" % stage, "P23产品链路阶段失败。", {"stage": stage, "details": details})

func _failure(code: String, reason: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": reason, "details": details}
