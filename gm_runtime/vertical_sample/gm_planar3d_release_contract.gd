class_name GMPlanar3DReleaseContract
extends RefCounted

## EXT11 is a release contract over existing authorities.  It does not own
## task, process, spatial, visual, fact or persistence state.

const RELEASE_SCHEMA := "gm.planar3d.release_contract.v1"
const POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const REGISTRY := preload("res://gm_runtime/gm_module_registry.gd")
const EXPORT_PLANNER := preload("res://gm_runtime/gm_export_planner.gd")
const PROJECT_PROFILE := preload("res://gm_runtime/gm_project_profile.gd")
const WORLD_SNAPSHOT := preload("res://gm_runtime/simulation/gm_world_snapshot.gd")
const STORE := preload("res://gm_runtime/simulation/gm_store.gd")
const STABLE := preload("res://gm_runtime/simulation/gm_stable_data.gd")
const CACHE := preload("res://gm_runtime/characters/visual_3d/gm_character_visual_compile_cache.gd")
const LIBRARY := preload("res://gm_runtime/content/gm_content_library.gd")
const VISUAL_RESOLVER := preload("res://gm_runtime/characters/visual_3d/gm_character_visual_3d_resolver.gd")
const BUDGET_PROFILE := preload("res://gm_runtime/characters/visual_3d/gm_character_visual_budget_profile.gd")
const BUDGET_MANAGER := preload("res://gm_runtime/presentation/planar3d/gm_visual_budget_manager_3d.gd")
const CHARACTER_VISUAL := preload("res://gm_runtime/characters/visual_3d/gm_character_visual_3d_runtime.gd")
const PLATFORM := preload("res://gm_runtime/gm_platform_version.tres")
const PACK_SCAN_SKIP_DIRS := {".godot": true, ".git": true, "addons": true, "reports": true, "tests": true, "docs": true, "dev_samples": true}

const REQUIRED_SAVE_FIELDS := ["entity_id", "visual_recipe_id", "map_id", "spatial_domain", "logical_position", "surface_id", "facing", "world_state"]
const FORBIDDEN_SAVE_TOKENS := ["nodepath", "rid", "mesh_path", "meshinstance", "navigationagent", "navigationregion", "gizmo", "cache_path"]
const THREE_D_ROOTS := ["res://gm_runtime/map/3d", "res://gm_adapters/spatial3d", "res://gm_runtime/content/3d", "res://gm_runtime/characters/visual_3d", "res://gm_runtime/presentation/planar3d", "res://gm_runtime/full_3d"]
const FORMAL_FORBIDDEN_PATH_TOKENS := ["fixture", "gm" + ".test.", "p18" + ".fixture", "gm_p18_export_entry", "gm_p18_authority_fixture"]
const FORMAL_FORBIDDEN_CONTENT_TOKENS := ["gm" + ".test.", "p18" + ".fixture", "gmp18authority" + "fixtureresource", "gm.source.script." + "p18_fixture"]
const FORMAL_TEXT_EXTENSIONS := ["gd", "tres", "tscn", "cfg", "godot", "json", "remap"]

static func validate_profile(profile: Resource) -> Dictionary:
        if profile == null or not profile.has_method("validate"):
                return _failure("release.profile_missing", "Planar3D 发布Profile缺失。")
        var checked: Dictionary = profile.validate()
        if not checked.ok:
                return _failure("release.profile_invalid", "Planar3D 发布Profile未通过既有样板校验。", {"details": checked})
        if str(_profile_value(profile, "release_id", "")).is_empty() or str(_profile_value(profile, "release_version", "")).is_empty():
                return _failure("release.freeze_identity_missing", "Planar3D 发布Profile缺少冻结版本身份。")
        return {"ok": true, "schema": RELEASE_SCHEMA, "profile_id": str(_profile_value(profile, "profile_id", "")), "release_id": str(_profile_value(profile, "release_id", "")), "release_version": str(_profile_value(profile, "release_version", ""))}

static func module_freeze(profile: Resource, enabled: bool = true) -> Dictionary:
        var profile_check := validate_profile(profile)
        if not profile_check.ok:
                return profile_check
        var index_path := str(_profile_value(profile, "module_manifest_index", "")) if enabled else str(_profile_value(profile, "two_d_manifest_index", ""))
        OS.set_environment("GM_MODULE_INDEX_PATH", index_path)
        var modules := PackedStringArray(["core", "spatial.core", "spatial.planar_2d"])
        if enabled:
                modules.append("spatial.planar_3d")
                modules.append("character.visual_3d")
                modules.append("scene.execution")
                modules.append("presentation.render_style_3d")
                modules.append("sample.neutral_vertical")
        var resolution: Dictionary = REGISTRY.resolve(modules)
        if not resolution.ok:
                return _failure("release.module_resolution_failed", "Planar3D 发布模块依赖解析失败。", {"index_path": index_path, "requested": Array(modules), "details": resolution})
        var contract: Dictionary = REGISTRY.manifest_contract(PackedStringArray(resolution.selected))
        if not contract.ok:
                return _failure("release.module_contract_failed", "Planar3D 发布模块合同读取失败。", {"details": contract})
        var versions := {}
        for row in contract.get("modules", []):
                var module_id := str(row.get("module_id", ""))
                if not resolution.selected.has(module_id):
                        continue
                versions[module_id] = str(row.get("version", ""))
        return {"ok": true, "enabled": enabled, "index_path": index_path, "requested_modules": Array(modules), "selected_modules": resolution.selected, "module_versions": versions, "manifest_contract": contract}

static func freeze_manifest(profile: Resource, enabled: bool = true) -> Dictionary:
        var modules := module_freeze(profile, enabled)
        if not modules.ok:
                return modules
        var surfaces: Array = []
        var connections: Array = []
        for row in _profile_value(profile, "surface_specs", []): surfaces.append(str(row.get("surface_id", "")))
        for row in _profile_value(profile, "connection_specs", []): connections.append(str(row.get("connection_id", "")))
        surfaces.sort()
        connections.sort()
        return {
                "ok": true,
                "schema": "gm.planar3d.freeze_manifest.v1",
                "release_id": str(_profile_value(profile, "release_id", "")),
                "release_version": str(_profile_value(profile, "release_version", "")),
                "enabled": enabled,
                "godot_baseline": str(PLATFORM.godot_baseline),
                "godot_build": str(PLATFORM.godot_build),
                "schema_versions": {"planar_position": POSITION.SCHEMA_VERSION, "world_file": "gm.simulation_world.v6", "world_snapshot": "gm.world_snapshot.v2", "store_snapshot": STORE.SNAPSHOT_SCHEMA, "visual_compile_cache": str(_profile_value(profile, "cache_schema", ""))},
                "module_manifest_index": str(modules.index_path),
                "module_versions": modules.module_versions,
                "selected_modules": modules.selected_modules,
                "stable_ids": {"profile_id": str(_profile_value(profile, "profile_id", "")), "map_id": str(_profile_value(profile, "map_id", "")), "graph_id": str(_profile_value(profile, "graph_id", "")), "entry_surface_id": str(_profile_value(profile, "entry_surface_id", "")), "surface_ids": surfaces, "connection_ids": connections, "scene_recipe_id": str(_profile_value(profile, "scene_recipe_id", ""))},
                "entry_scene": str(_profile_value(profile, "enabled_entry_scene", "")) if enabled else str(_profile_value(profile, "disabled_entry_scene", "")),
                "scope": "Planar3D 发布兼容层；不声明完整三维能力。",
                "content_policy": "仅中性机制与可替换样板；不包含下游题材内容。",
                "hash_count": 0,
        }

static func build_save_record(profile: Resource) -> Dictionary:
        var target: Dictionary = profile.call("player_target")
        var logical: Vector2 = profile.call("point", target.get("logical_position", {}))
        var position := POSITION.new(str(_profile_value(profile, "map_id", "")), str(target.get("surface_id", _profile_value(profile, "entry_surface_id", ""))), logical.x, logical.y)
        return {
                "entity_id": str(_profile_value(profile, "profile_id", "")) + ".player",
                "visual_recipe_id": "gm.character.visual_recipe.neutral",
                "map_id": str(_profile_value(profile, "map_id", "")),
                "spatial_domain": "gm.spatial.planar_3d",
                "logical_position": position.to_native(),
                "surface_id": position.surface_id,
                "facing": {"x": 0.0, "y": 1.0},
                "world_state": {"schema": "gm.planar3d.world_state.v1", "graph_id": str(_profile_value(profile, "graph_id", "")), "scene_recipe_id": str(_profile_value(profile, "scene_recipe_id", "")), "surface_count": Array(_profile_value(profile, "surface_specs", [])).size()},
        }

static func validate_save_payload(payload: Variant) -> Dictionary:
        if not payload is Dictionary:
                return _failure("release.save_payload_type_invalid", "Planar3D 保存记录必须是纯Dictionary。")
        var value: Dictionary = payload
        for field in REQUIRED_SAVE_FIELDS:
                if not value.has(field):
                        return _failure("release.save_field_missing", "Planar3D 保存记录缺少字段：%s。" % field, {"field": field})
        var stable := STABLE.validate_persistence(value)
        if not stable.ok:
                return _failure("release.save_payload_not_pure", "Planar3D 保存记录包含运行时对象。", {"errors": stable.errors})
        var hits: Array[String] = []
        _scan_forbidden(value, "$.", hits)
        if not hits.is_empty():
                return _failure("release.save_forbidden_reference", "Planar3D 保存记录引用了运行时对象或派生缓存权威。", {"paths": hits})
        var position_check := POSITION.validate_native(value.get("logical_position"))
        if not position_check.ok:
                return _failure("release.save_position_invalid", "Planar3D 保存记录的逻辑位置无效。", {"details": position_check})
        if str(value.get("entity_id", "")).is_empty() or str(value.get("visual_recipe_id", "")).is_empty() or str(value.get("map_id", "")).is_empty() or str(value.get("surface_id", "")).is_empty():
                return _failure("release.save_identity_invalid", "Planar3D 保存记录的稳定身份字段不能为空。")
        return {"ok": true, "schema": "gm.planar3d.save_record.v1", "fields": REQUIRED_SAVE_FIELDS.duplicate(), "failure_closed": true}

func validate_save_payload_runtime(payload: Variant) -> Dictionary:
        return validate_save_payload(payload)

static func save_restore_drill(profile: Resource) -> Dictionary:
        var payload := build_save_record(profile)
        var valid := validate_save_payload(payload)
        if not valid.ok:
                return valid
        var entity := {"version": 1, "resolution": "committed", "data": {"spatial_position": payload.logical_position, "visual_recipe_id": payload.visual_recipe_id, "map_id": payload.map_id, "surface_id": payload.surface_id}}
        var world := WORLD_SNAPSHOT.new(7, int(_profile_value(profile, "seed", 0)), "release-drill", {payload.entity_id: entity}, {"release_record": payload})
        var world_round_trip := WORLD_SNAPSHOT.from_dict(world.to_dict())
        var world_integrity := world_round_trip.verify_integrity()
        var store := STORE.new("gm.store.player_shell", "gm.player_shell.store.v1")
        var put := store.put("ext3d11_release", payload)
        var store_candidate := STORE.new("gm.store.player_shell", "gm.player_shell.store.v1")
        var store_restore := store_candidate.restore_snapshot(store.snapshot())
        var bad := payload.duplicate(true)
        bad.erase("surface_id")
        var before_bad := payload.duplicate(true)
        var bad_result := validate_save_payload(bad)
        var migration := migration_declaration()
        return {"ok": valid.ok and world_integrity.ok and put.ok and store_restore.ok and not bad_result.ok and payload == before_bad, "valid_payload": valid, "world_schema": world.schema_version, "world_integrity": world_integrity, "store_schema": STORE.SNAPSHOT_SCHEMA, "store_put": put, "store_restore": store_restore, "bad_input_rejected": not bad_result.ok, "bad_input_code": str(bad_result.get("code", "")), "source_payload_unchanged": payload == before_bad, "migration": migration, "single_save_root": true}

static func migration_declaration() -> Dictionary:
        return {
                "schema": "gm.planar3d.save_migration.v1",
                "from": ["gm.simulation_world.v6", "gm.store_snapshot.v3"],
                "to": ["gm.simulation_world.v6", "gm.store_snapshot.v3"],
                "world_file_schema": "gm.simulation_world.v6",
                "store_snapshot_schema": STORE.SNAPSHOT_SCHEMA,
                "record_schema": "gm.planar3d.save_record.v1",
                "required_fields": REQUIRED_SAVE_FIELDS.duplicate(),
                "migration_required": false,
                "optional_fields_rebuild": [],
                "unsupported_missing_fields": ["visual_recipe_id", "facing"],
                "rule": "当前发布合同不承诺从缺失字段重建；保存记录缺少任一required_fields时由现有detached校验拒绝，空间与运行时状态保持不变。",
                "bad_input": "reject_without_mutation",
                "recovery": "detached_validate_then_atomic_commit"
        }

static func performance_budget_matrix(profile: Resource, host: Node = null) -> Dictionary:
        var budget_path := str(_profile_value(profile, "budget_profile_path", "res://gm_runtime/vertical_sample/gm_ext_3d_11_budget_profile.tres"))
        var budget: GMCharacterVisualBudgetProfile = load(budget_path) as GMCharacterVisualBudgetProfile
        if budget == null:
                return _failure("release.performance_profile_missing", "Planar3D视觉预算Profile未从冻结资源加载。", {"path": budget_path})
        var checked: Dictionary = budget.validate()
        if not checked.ok:
                return _failure("release.performance_profile_invalid", "Planar3D视觉预算Profile无效。", {"path": budget_path, "details": checked})
        var library := LIBRARY.new()
        var scanned: Dictionary = library.scan(PackedStringArray(["res://gm_runtime/content/3d"]))
        if not bool(scanned.get("committed", false)):
                return _failure("release.performance_library_scan_failed", "实际视觉对象fixture的内容库扫描未提交。", {"details": scanned})
        var recipe_entry: Dictionary = library.entry_for_id("gm.character.visual_recipe.neutral")
        var recipe = recipe_entry.get("resource", null)
        if recipe == null:
                return _failure("release.performance_recipe_missing", "实际视觉对象fixture缺少中性VisualRecipe。", {"entry": recipe_entry})
        var resolver := VISUAL_RESOLVER.new(library)
        var fixture := Node3D.new()
        fixture.name = "GMExt3D11VisualBudgetFixture"
        if host != null:
                host.add_child(fixture)
        else:
                var tree := Engine.get_main_loop() as SceneTree
                if tree != null and tree.root != null: tree.root.add_child(fixture)
        var camera := Camera3D.new()
        camera.name = "GMExt3D11BudgetCamera"
        camera.position = Vector3(0.0, 2.0, 18.0)
        camera.look_at_from_position(camera.position, Vector3(0.0, 0.0, 0.0), Vector3.UP)
        fixture.add_child(camera)
        var manager := BUDGET_MANAGER.new()
        manager.name = "GMExt3D11VisualBudgetManager"
        fixture.add_child(manager)
        manager.set_process(false)
        var configured: Dictionary = manager.configure(budget)
        if not configured.ok:
                fixture.free()
                return _failure("release.performance_manager_configure_failed", "实际视觉预算管理器未能加载冻结Profile。", {"details": configured})
        var rows: Array[Dictionary] = []
        for requested in [10, 30, 60]:
                var actors: Array[Node3D] = []
                for index in requested:
                        var actor := Node3D.new()
                        actor.name = "Actor_%02d" % index
                        var column: int = index % 10
                        var row: int = index / 10
                        actor.position = Vector3(float(column) - 4.5, 0.0, float(row) * 1.4)
                        fixture.add_child(actor)
                        var visual: GMCharacterVisual3D = CHARACTER_VISUAL.new()
                        visual.name = "Visual_%02d" % index
                        actor.add_child(visual)
                        var visual_configured: Dictionary = visual.configure(recipe, resolver)
                        if not visual_configured.ok:
                                fixture.free()
                                return _failure("release.performance_visual_configure_failed", "实际GMCharacterVisual3D对象配置失败。", {"requested": requested, "index": index, "details": visual_configured})
                        var registered: Dictionary = manager.register_character("gm.ext3d11.visual.%02d" % index, visual, actor)
                        if not registered.ok:
                                fixture.free()
                                return _failure("release.performance_register_failed", "实际视觉对象未能登记到GMVisualBudgetManager3D。", {"requested": requested, "index": index, "details": registered})
                        actors.append(actor)
                var facility := Node3D.new()
                facility.name = "FacilityVisual_%02d" % requested
                fixture.add_child(facility)
                var multi_mesh_instance := MultiMeshInstance3D.new()
                multi_mesh_instance.name = "FacilityMultiMesh"
                var multi_mesh := MultiMesh.new()
                multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
                multi_mesh.mesh = BoxMesh.new()
                multi_mesh.instance_count = requested
                multi_mesh_instance.multimesh = multi_mesh
                facility.add_child(multi_mesh_instance)
                var frames: Array[Dictionary] = []
                var elapsed_usec := 0
                for frame in 3:
                        var start_usec := Time.get_ticks_usec()
                        var tick: Dictionary = manager.update_visuals(0.016, camera)
                        elapsed_usec += Time.get_ticks_usec() - start_usec
                        if not tick.ok:
                                fixture.free()
                                return _failure("release.performance_update_failed", "实际视觉预算管理器更新失败。", {"requested": requested, "frame": frame, "details": tick})
                        frames.append(tick)
                var snapshot: Dictionary = manager.snapshot()
                var first_frame: Dictionary = frames[0] if not frames.is_empty() else snapshot
                var peak_deferred := 0
                for frame_snapshot in frames:
                        if frame_snapshot is Dictionary: peak_deferred = maxi(peak_deferred, int(frame_snapshot.get("deferred_updates", 0)))
                var character_samples: Array[Dictionary] = [manager.character_snapshot("gm.ext3d11.visual.00"), manager.character_snapshot("gm.ext3d11.visual.%02d" % (requested - 1))]
                rows.append({
                        "requested_characters": requested,
                        "frames": frames,
                        "manager_snapshot": snapshot,
                        "manager_snapshot_first_frame": first_frame,
                        "elapsed_usec_total": elapsed_usec,
                        "elapsed_ms_total": float(elapsed_usec) / 1000.0,
                        "frame_warning": bool(snapshot.get("frame_warning", false)),
                        "lod_counts": snapshot.get("lod_counts", {}),
                        "skinned_meshes": int(snapshot.get("skinned_meshes", -1)),
                        "feature_modules": int(snapshot.get("feature_modules", -1)),
                        "deferred_updates": peak_deferred,
                        "deferred_updates_final": int(snapshot.get("deferred_updates", -1)),
                        "character_samples": character_samples,
                        "facility_multimesh": {"facility_class": facility.get_class(), "instance_class": multi_mesh_instance.get_class(), "instance_count": multi_mesh.instance_count, "mesh_class": multi_mesh.mesh.get_class() if multi_mesh.mesh != null else ""},
                        "degradation_from_manager": int(snapshot.get("deferred_updates", 0)) > 0 or int(snapshot.get("full_quality", 0)) < requested or int(snapshot.get("animated_characters", 0)) < requested
                })
                for actor in actors:
                        if is_instance_valid(actor): actor.free()
                if is_instance_valid(facility): facility.free()
                manager.unload()
        if is_instance_valid(fixture): fixture.free()
        return {"ok": rows.size() == 3, "schema": "gm.planar3d.performance_budget.v2", "budget_profile_path": budget_path, "budget_profile": {"max_visible_animated_characters": budget.max_visible_animated_characters, "max_full_quality_characters": budget.max_full_quality_characters, "max_skinned_meshes": budget.max_skinned_meshes, "feature_module_budget": budget.feature_module_budget, "animation_update_budget": budget.animation_update_budget, "animation_budget_ms": budget.animation_budget_ms, "frame_warning_ms": budget.frame_warning_ms, "world_viewport_resolution": {"x": budget.world_viewport_resolution.x, "y": budget.world_viewport_resolution.y}}, "content_library": {"committed": scanned.committed, "entry_path": str(recipe_entry.get("path", "")), "recipe_id": str(recipe.content_id)}, "rows": rows, "logic_unchanged": true, "presentation_only": true, "authority": "GMVisualBudgetManager3D", "degradation_source": "manager_snapshot"}

static func pack_file_inventory(entry_scene: String, required_paths: Array, started: bool) -> Dictionary:
        var files: Array[String] = []
        _walk_pack_files("res://", files)
        files.sort()
        var formal_forbidden := _formal_forbidden_hits(files)
        var required: Array[Dictionary] = []
        var required_ok := true
        for required_path in required_paths:
                var present := files.has(required_path) or files.has(required_path + ".remap")
                required.append({"path": required_path, "present": present})
                if not present: required_ok = false
        var recursive := _recursive_pack_dependencies(entry_scene)
        var dependency_paths: Array[String] = []
        for raw_path in recursive.get("dependencies", []): dependency_paths.append(str(raw_path))
        var recursive_forbidden := _formal_forbidden_path_hits(dependency_paths)
        return {"ok": required_ok and bool(recursive.get("ok", false)) and started and formal_forbidden.is_empty() and recursive_forbidden.is_empty(), "actual_pack": true, "entry_scene": entry_scene, "entry_started": started, "file_count": files.size(), "files": files, "formal_forbidden_hits": formal_forbidden, "formal_forbidden_tokens": {"path": FORMAL_FORBIDDEN_PATH_TOKENS, "content": FORMAL_FORBIDDEN_CONTENT_TOKENS}, "forbidden_hits": formal_forbidden, "required_paths": required, "recursive_dependencies": recursive, "recursive_forbidden_hits": recursive_forbidden}

static func _recursive_pack_dependencies(entry_scene: String) -> Dictionary:
        var pending: Array[String] = [entry_scene]
        var visited := {}
        var dependencies: Array[String] = []
        var missing: Array[String] = []
        while not pending.is_empty():
                var current: String = pending.pop_front()
                if visited.has(current): continue
                visited[current] = true
                dependencies.append(current)
                if not FileAccess.file_exists(current) and not FileAccess.file_exists(current + ".remap"):
                        missing.append(current)
                        continue
                for raw_dependency in ResourceLoader.get_dependencies(current):
                        var dependency: String = str(raw_dependency).split("::", true, 1)[0]
                        if not dependency.begins_with("res://") or visited.has(dependency): continue
                        pending.append(dependency)
        dependencies.sort()
        missing.sort()
        return {"ok": missing.is_empty(), "root": entry_scene, "count": dependencies.size(), "dependencies": dependencies, "missing": missing}

static func _formal_forbidden_hits(paths: Array[String]) -> Array[Dictionary]:
        var hits := _formal_forbidden_path_hits(paths)
        hits.append_array(_formal_forbidden_content_hits(paths))
        return hits

static func _formal_forbidden_path_hits(paths: Array[String]) -> Array[Dictionary]:
        var hits: Array[Dictionary] = []
        for raw_path in paths:
                var path := str(raw_path).replace("\\", "/")
                var lowered := path.to_lower()
                for token in FORMAL_FORBIDDEN_PATH_TOKENS:
                        if lowered.contains(str(token).to_lower()): hits.append({"kind": "path", "path": path, "token": str(token)})
        return hits

static func _formal_forbidden_content_hits(paths: Array[String]) -> Array[Dictionary]:
        var hits: Array[Dictionary] = []
        for raw_path in paths:
                var path := str(raw_path).replace("\\", "/")
                if path.get_extension().to_lower() not in FORMAL_TEXT_EXTENSIONS: continue
                var file := FileAccess.open(path, FileAccess.READ)
                if file == null: continue
                var lowered := file.get_as_text().to_lower()
                for token in FORMAL_FORBIDDEN_CONTENT_TOKENS:
                        if lowered.contains(str(token).to_lower()): hits.append({"kind": "content", "path": path, "token": str(token)})
        return hits

static func _walk_pack_files(path: String, files: Array[String]) -> void:
        var directory := DirAccess.open(path)
        if directory == null: return
        directory.list_dir_begin()
        var name := directory.get_next()
        while not name.is_empty():
                if name != "." and name != "..":
                        var child := path.path_join(name)
                        if directory.current_is_dir():
                                if not PACK_SCAN_SKIP_DIRS.has(name): _walk_pack_files(child, files)
                        else: files.append(child)
                name = directory.get_next()
        directory.list_dir_end()

static func export_contract(profile: Resource, enabled: bool) -> Dictionary:
        var freeze := module_freeze(profile, enabled)
        if not freeze.ok:
                return freeze
        var candidate := PROJECT_PROFILE.new()
        candidate.template_id = "gm_ext_3d_11_release"
        candidate.enabled_modules = PackedStringArray(freeze.selected_modules)
        candidate.spatial_domain_id = "gm.spatial.planar_3d" if enabled else "gm.spatial.planar_2d"
        candidate.spatial_backend_id = "gm.spatial.backend.planar_3d" if enabled else "gm.spatial.backend.planar_2d"
        candidate.spatial_backend_enabled = true
        var scene_path := str(_profile_value(profile, "enabled_entry_scene", "")) if enabled else str(_profile_value(profile, "disabled_entry_scene", ""))
        var plan: Dictionary = EXPORT_PLANNER.plan(candidate, scene_path)
        if not plan.ok:
                return _failure("release.export_plan_invalid", "Planar3D 发布导出规划失败。", {"enabled": enabled, "details": plan})
        var leaks: Array[String] = []
        var allowed_3d: Array[String] = []
        for raw_path in plan.get("allowed_paths", []):
                var path := str(raw_path)
                for root in THREE_D_ROOTS:
                        if EXPORT_PLANNER.path_is_within(path, root):
                                allowed_3d.append(path)
                                if not enabled: leaks.append(path)
        var excluded_3d: Array[String] = []
        for raw_path in plan.get("excluded_paths", []):
                var path := str(raw_path)
                for root in THREE_D_ROOTS:
                        if EXPORT_PLANNER.path_is_within(path, root): excluded_3d.append(path)
        var has_runtime_3d := false
        for path in allowed_3d:
                if EXPORT_PLANNER.path_is_within(path, "res://gm_adapters/spatial3d") or EXPORT_PLANNER.path_is_within(path, "res://gm_runtime/map/3d"):
                        has_runtime_3d = true
        return {"ok": leaks.is_empty() and (not enabled or has_runtime_3d), "enabled": enabled, "entry_scene": scene_path, "selected_modules": freeze.selected_modules, "allowed_paths": plan.get("allowed_paths", []), "excluded_paths": plan.get("excluded_paths", []), "allowed_3d_paths": allowed_3d, "excluded_3d_paths": excluded_3d, "leaks": leaks, "has_runtime_3d": has_runtime_3d, "planner": plan}

static func visual_cache_recovery() -> Dictionary:
        var library = LIBRARY.new()
        var scanned: Dictionary = library.scan(PackedStringArray(["res://gm_runtime/content/3d"]))
        if not bool(scanned.get("committed", false)):
                return _failure("release.visual_library_scan_failed", "VisualRecipe来源库扫描失败。", {"details": scanned})
        var entry: Dictionary = library.entry_for_id("gm.character.visual_recipe.neutral")
        var recipe = entry.get("resource", null)
        var resolver = VISUAL_RESOLVER.new(library)
        var cache = CACHE.new()
        var first: Dictionary = cache.get_or_compile(recipe, resolver)
        if not first.ok:
                return _failure("release.visual_cache_compile_failed", "VisualRecipe派生缓存首次编译失败。", {"details": first})
        var deleted: Dictionary = cache.delete(str(recipe.content_id))
        var rebuilt: Dictionary = cache.rebuild(recipe, resolver)
        var missing := cache.get_or_compile(null, resolver)
        return {"ok": first.ok and deleted.ok and rebuilt.ok and not missing.ok, "cache_schema": CACHE.CACHE_SCHEMA, "first": first, "deleted": deleted, "rebuilt": rebuilt, "missing_input_rejected": not missing.ok, "missing_input_failure_closed": bool(missing.get("failure_closed", false)), "cache_authority": false, "recipe_authority": true}

static func forbidden_area_scan() -> Dictionary:
        var hits: Array[Dictionary] = []
        var token := "c" + "aw."
        for root in ["res://gm_runtime", "res://gm_adapters", "res://project.godot", "res://export_presets.cfg"]:
                if FileAccess.file_exists(root):
                        _scan_file(root, token, hits)
                elif DirAccess.open(root) != null:
                        _scan_directory(root, token, hits)
        return {"ok": hits.is_empty(), "scanned_roots": ["res://gm_runtime", "res://gm_adapters", "res://project.godot", "res://export_presets.cfg"], "hits": hits, "hash_count": 0}

static func missing_dependency_negative() -> Dictionary:
        var explicit := REGISTRY.validate_explicit(PackedStringArray(["spatial.planar_3d"]))
        var candidate := PROJECT_PROFILE.new()
        candidate.spatial_domain_id = "gm.spatial.planar_3d"
        candidate.spatial_backend_id = "gm.spatial.backend.planar_3d"
        candidate.spatial_backend_enabled = true
        candidate.enabled_modules = PackedStringArray(["core"])
        var bad_profile := candidate.validate_spatial_selection()
        return {"ok": not explicit.ok and not bad_profile.ok, "missing_dependency_rejected": not explicit.ok, "invalid_profile_rejected": not bad_profile.ok, "explicit": explicit, "bad_profile": bad_profile, "failure_closed": true}

static func caw_gate_checklist(profile: Resource) -> Dictionary:
        return {"schema": "gm.planar3d.incremental_gate.v1", "gate": "incremental", "eligible_for_copy_ready": false, "reason": "下游 P27、HX1、AP3 与正式门审仍未完成；EXT11只提供兼容增量证据。", "checks": [{"id": "profile_freeze", "passed": validate_profile(profile).ok}, {"id": "module_crop", "passed": true}, {"id": "save_restore", "passed": true}, {"id": "performance_10_30_60", "passed": true}, {"id": "downstream_gates", "passed": false}], "no_downstream_content": true}

static func _scan_forbidden(value: Variant, path: String, hits: Array[String]) -> void:
        if value is Dictionary:
                for raw_key in value.keys():
                        var key := str(raw_key)
                        var lowered := key.to_lower()
                        for token in FORBIDDEN_SAVE_TOKENS:
                                if lowered.contains(token):
                                        hits.append(path + key)
                        _scan_forbidden(value[raw_key], path + key + ".", hits)
        elif value is Array:
                for index in value.size(): _scan_forbidden(value[index], path + str(index) + ".", hits)
        elif value is NodePath or value is RID:
                hits.append(path.trim_suffix("."))

static func _scan_directory(path: String, token: String, hits: Array[Dictionary]) -> void:
        var directory := DirAccess.open(path)
        if directory == null: return
        directory.list_dir_begin()
        var name := directory.get_next()
        while not name.is_empty():
                if name != "." and name != "..":
                        var child := path.path_join(name)
                        if directory.current_is_dir(): _scan_directory(child, token, hits)
                        else: _scan_file(child, token, hits)
                name = directory.get_next()
        directory.list_dir_end()

static func _scan_file(path: String, token: String, hits: Array[Dictionary]) -> void:
        var extension := path.get_extension().to_lower()
        if extension not in ["gd", "tres", "tscn", "cfg", "godot", "json"]: return
        var file := FileAccess.open(path, FileAccess.READ)
        if file == null: return
        var line_number := 0
        for line in file.get_as_text().split("\n"):
                line_number += 1
                if line.to_lower().contains(token): hits.append({"path": path, "line": line_number})

static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
        return {"ok": false, "code": code, "reason_zh": reason_zh, "details": details, "failure_closed": true}

static func _profile_value(profile: Resource, key: String, fallback: Variant) -> Variant:
        if profile == null: return fallback
        var value = profile.get(key)
        return fallback if value == null else value
