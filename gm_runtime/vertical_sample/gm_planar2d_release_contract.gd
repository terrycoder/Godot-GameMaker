class_name GMPlanar2DReleaseContract
extends RefCounted

## 2D-only release contract.  This file intentionally has no preload or class
## reference into any 3D implementation root.  The base PlayerShell may load
## the enabled-only 3D validator dynamically, but this contract is the complete
## static dependency for the 2D entry.

const RELEASE_SCHEMA := "gm.planar2d.release_contract.v1"
const POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const REGISTRY := preload("res://gm_runtime/gm_module_registry.gd")
const EXPORT_PLANNER := preload("res://gm_runtime/gm_export_planner.gd")
const PROJECT_PROFILE := preload("res://gm_runtime/gm_project_profile.gd")
const WORLD_SNAPSHOT := preload("res://gm_runtime/simulation/gm_world_snapshot.gd")
const STORE := preload("res://gm_runtime/simulation/gm_store.gd")
const STABLE := preload("res://gm_runtime/simulation/gm_stable_data.gd")
const PLATFORM := preload("res://gm_runtime/gm_platform_version.tres")

const REQUIRED_SAVE_FIELDS := ["entity_id", "visual_recipe_id", "map_id", "spatial_domain", "logical_position", "surface_id", "facing", "world_state"]
const FORBIDDEN_SAVE_TOKENS := ["nodepath", "rid", "mesh_path", "meshinstance", "navigationagent", "navigationregion", "gizmo", "cache_path"]
const THREE_D_ROOTS := ["res://gm_runtime/map/3d", "res://gm_adapters/spatial3d", "res://gm_runtime/content/3d", "res://gm_runtime/characters/visual_3d", "res://gm_runtime/presentation/planar3d", "res://gm_runtime/full_3d"]
const PACK_SCAN_SKIP_DIRS := {".godot": true, ".git": true, "addons": true, "reports": true, "tests": true, "docs": true, "dev_samples": true}
const FORMAL_FORBIDDEN_PATH_TOKENS := ["fixture", "gm" + ".test.", "p18" + ".fixture", "gm_p18_export_entry", "gm_p18_authority_fixture"]
const FORMAL_FORBIDDEN_CONTENT_TOKENS := ["gm" + ".test.", "p18" + ".fixture", "gmp18authority" + "fixtureresource", "gm.source.script." + "p18_fixture"]
const FORMAL_TEXT_EXTENSIONS := ["gd", "tres", "tscn", "cfg", "godot", "json", "remap"]

static func validate_profile(profile: Resource) -> Dictionary:
        if profile == null or not profile.has_method("validate"):
                return _failure("release.profile_missing", "2D-only发布Profile缺失。")
        var checked: Dictionary = profile.call("validate")
        if not checked.ok:
                return _failure("release.profile_invalid", "2D-only发布Profile未通过既有样板校验。", {"details": checked})
        if str(_profile_value(profile, "release_id", "")).is_empty() or str(_profile_value(profile, "release_version", "")).is_empty():
                return _failure("release.freeze_identity_missing", "2D-only发布Profile缺少冻结版本身份。")
        return {"ok": true, "schema": RELEASE_SCHEMA, "profile_id": str(_profile_value(profile, "profile_id", "")), "release_id": str(_profile_value(profile, "release_id", "")), "release_version": str(_profile_value(profile, "release_version", ""))}

static func module_freeze(profile: Resource) -> Dictionary:
        var profile_check := validate_profile(profile)
        if not profile_check.ok:
                return profile_check
        var index_path := str(_profile_value(profile, "two_d_manifest_index", ""))
        OS.set_environment("GM_MODULE_INDEX_PATH", index_path)
        var modules := PackedStringArray(["core", "spatial.core", "spatial.planar_2d"])
        var resolution: Dictionary = REGISTRY.resolve(modules)
        if not resolution.ok:
                return _failure("release.module_resolution_failed", "2D-only发布模块依赖解析失败。", {"index_path": index_path, "requested": Array(modules), "details": resolution})
        var contract: Dictionary = REGISTRY.manifest_contract(PackedStringArray(resolution.selected))
        if not contract.ok:
                return _failure("release.module_contract_failed", "2D-only发布模块合同读取失败。", {"details": contract})
        var versions := {}
        for row in contract.get("modules", []):
                var module_id := str(row.get("module_id", ""))
                if resolution.selected.has(module_id): versions[module_id] = str(row.get("version", ""))
        return {"ok": true, "enabled": false, "index_path": index_path, "requested_modules": Array(modules), "selected_modules": resolution.selected, "module_versions": versions, "manifest_contract": contract}

static func export_contract(profile: Resource) -> Dictionary:
        var freeze := module_freeze(profile)
        if not freeze.ok:
                return freeze
        var candidate := PROJECT_PROFILE.new()
        candidate.template_id = "gm_ext_3d_11_release"
        candidate.enabled_modules = PackedStringArray(freeze.selected_modules)
        candidate.spatial_domain_id = "gm.spatial.planar_2d"
        candidate.spatial_backend_id = "gm.spatial.backend.planar_2d"
        candidate.spatial_backend_enabled = true
        var scene_path := str(_profile_value(profile, "disabled_entry_scene", ""))
        var plan: Dictionary = EXPORT_PLANNER.plan(candidate, scene_path)
        if not plan.ok:
                return _failure("release.export_plan_invalid", "2D-only发布导出规划失败。", {"details": plan})
        var leaks: Array[String] = []
        var excluded_3d: Array[String] = []
        for raw_path in plan.get("allowed_paths", []):
                var path := str(raw_path)
                for root in THREE_D_ROOTS:
                        if EXPORT_PLANNER.path_is_within(path, root): leaks.append(path)
        for raw_path in plan.get("excluded_paths", []):
                var path := str(raw_path)
                for root in THREE_D_ROOTS:
                        if EXPORT_PLANNER.path_is_within(path, root): excluded_3d.append(path)
        return {"ok": leaks.is_empty(), "enabled": false, "entry_scene": scene_path, "selected_modules": freeze.selected_modules, "allowed_paths": plan.get("allowed_paths", []), "excluded_paths": plan.get("excluded_paths", []), "allowed_3d_paths": [], "excluded_3d_paths": excluded_3d, "leaks": leaks, "has_runtime_3d": false, "planner": plan}

static func build_save_record(profile: Resource) -> Dictionary:
        var target: Dictionary = profile.call("player_target")
        var logical: Vector2 = profile.call("point", target.get("logical_position", {}))
        var position := POSITION.new(str(_profile_value(profile, "map_id", "")), str(target.get("surface_id", _profile_value(profile, "entry_surface_id", ""))), logical.x, logical.y)
        return {
                "entity_id": str(_profile_value(profile, "profile_id", "")) + ".player",
                "visual_recipe_id": "gm.character.visual_recipe.neutral",
                "map_id": str(_profile_value(profile, "map_id", "")),
                "spatial_domain": "gm.spatial.planar_2d",
                "logical_position": position.to_native(),
                "surface_id": position.surface_id,
                "facing": {"x": 0.0, "y": 1.0},
                "world_state": {"schema": "gm.planar2d.world_state.v1", "graph_id": str(_profile_value(profile, "graph_id", "")), "scene_recipe_id": str(_profile_value(profile, "scene_recipe_id", "")), "surface_count": Array(_profile_value(profile, "surface_specs", [])).size()},
        }

static func validate_save_payload(payload: Variant) -> Dictionary:
        if not payload is Dictionary:
                return _failure("release.save_payload_type_invalid", "2D-only保存记录必须是纯Dictionary。")
        var value: Dictionary = payload
        for field in REQUIRED_SAVE_FIELDS:
                if not value.has(field):
                        return _failure("release.save_field_missing", "2D-only保存记录缺少字段：%s。" % field, {"field": field})
        var stable := STABLE.validate_persistence(value)
        if not stable.ok:
                return _failure("release.save_payload_not_pure", "2D-only保存记录包含运行时对象。", {"errors": stable.errors})
        var hits: Array[String] = []
        _scan_forbidden(value, "$.", hits)
        if not hits.is_empty():
                return _failure("release.save_forbidden_reference", "2D-only保存记录引用了运行时对象或派生缓存权威。", {"paths": hits})
        var position_check := POSITION.validate_native(value.get("logical_position"))
        if not position_check.ok:
                return _failure("release.save_position_invalid", "2D-only保存记录的逻辑位置无效。", {"details": position_check})
        if str(value.get("entity_id", "")).is_empty() or str(value.get("visual_recipe_id", "")).is_empty() or str(value.get("map_id", "")).is_empty() or str(value.get("surface_id", "")).is_empty():
                return _failure("release.save_identity_invalid", "2D-only保存记录的稳定身份字段不能为空。")
        return {"ok": true, "schema": "gm.planar2d.save_record.v1", "fields": REQUIRED_SAVE_FIELDS.duplicate(), "failure_closed": true}

static func save_restore_drill(profile: Resource) -> Dictionary:
        var payload := build_save_record(profile)
        var valid := validate_save_payload(payload)
        if not valid.ok: return valid
        var entity := {"version": 1, "resolution": "committed", "data": {"spatial_position": payload.logical_position, "visual_recipe_id": payload.visual_recipe_id, "map_id": payload.map_id, "surface_id": payload.surface_id}}
        var world := WORLD_SNAPSHOT.new(7, int(_profile_value(profile, "seed", 0)), "release-drill-2d", {payload.entity_id: entity}, {"release_record": payload})
        var world_round_trip := WORLD_SNAPSHOT.from_dict(world.to_dict())
        var world_integrity := world_round_trip.verify_integrity()
        var store := STORE.new("gm.store.player_shell", "gm.player_shell.store.v1")
        var put := store.put("ext3d11_release", payload)
        var store_candidate := STORE.new("gm.store.player_shell", "gm.player_shell.store.v1")
        var store_restore := store_candidate.restore_snapshot(store.snapshot())
        var bad := payload.duplicate(true)
        bad.erase("surface_id")
        var bad_result := validate_save_payload(bad)
        return {"ok": valid.ok and world_integrity.ok and put.ok and store_restore.ok and not bad_result.ok, "valid_payload": valid, "world_schema": world.schema_version, "world_integrity": world_integrity, "store_schema": STORE.SNAPSHOT_SCHEMA, "store_put": put, "store_restore": store_restore, "bad_input_rejected": not bad_result.ok, "bad_input_code": str(bad_result.get("code", "")), "single_save_root": true}

static func pack_file_inventory(entry_scene: String, required_paths: Array, started: bool) -> Dictionary:
        var files: Array[String] = []
        _walk_files("res://", files)
        files.sort()
        var forbidden := _formal_forbidden_hits(files)
        var required: Array[Dictionary] = []
        for required_path in required_paths:
                required.append({"path": required_path, "present": files.has(required_path) or files.has(required_path + ".remap")})
        var recursive := recursive_dependencies(entry_scene)
        var dependency_paths: Array[String] = []
        for raw_path in recursive.get("dependencies", []): dependency_paths.append(str(raw_path))
        var recursive_forbidden := _formal_forbidden_path_hits(dependency_paths)
        return {"ok": forbidden.is_empty() and recursive_forbidden.is_empty() and bool(recursive.get("ok", false)) and required.all(func(row: Dictionary): return bool(row.get("present", false))) and started, "actual_pack": true, "entry_scene": entry_scene, "entry_started": started, "file_count": files.size(), "files": files, "forbidden_hits": forbidden, "formal_forbidden_hits": forbidden, "formal_forbidden_tokens": {"path": FORMAL_FORBIDDEN_PATH_TOKENS, "content": FORMAL_FORBIDDEN_CONTENT_TOKENS}, "required_paths": required, "recursive_dependencies": recursive, "recursive_forbidden_hits": recursive_forbidden}

static func recursive_dependencies(entry_scene: String) -> Dictionary:
        var pending: Array[String] = [entry_scene]
        var visited := {}
        var dependencies: Array[String] = []
        var errors: Array[String] = []
        while not pending.is_empty():
                var current: String = pending.pop_front()
                if visited.has(current): continue
                visited[current] = true
                dependencies.append(current)
                var direct := ResourceLoader.get_dependencies(current)
                for raw_dependency in direct:
                        var dependency: String = str(raw_dependency).split("::", true, 1)[0]
                        if not dependency.begins_with("res://"): continue
                        if not FileAccess.file_exists(dependency) and not FileAccess.file_exists(dependency + ".remap"):
                                errors.append(dependency)
                                continue
                        if not visited.has(dependency): pending.append(dependency)
        dependencies.sort()
        errors.sort()
        return {"ok": errors.is_empty(), "root": entry_scene, "count": dependencies.size(), "dependencies": dependencies, "missing": errors}

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

static func forbidden_area_scan() -> Dictionary:
        var hits: Array[Dictionary] = []
        var token := "c" + "aw."
        for root in ["res://gm_runtime", "res://gm_adapters", "res://project.godot", "res://export_presets.cfg"]:
                if FileAccess.file_exists(root): _scan_file(root, token, hits)
                elif DirAccess.open(root) != null: _scan_directory(root, token, hits)
        return {"ok": hits.is_empty(), "scanned_roots": ["res://gm_runtime", "res://gm_adapters", "res://project.godot", "res://export_presets.cfg"], "hits": hits, "hash_count": 0}

static func _scan_forbidden(value: Variant, path: String, hits: Array[String]) -> void:
        if value is Dictionary:
                for raw_key in value.keys():
                        var key := str(raw_key)
                        var lowered := key.to_lower()
                        for token in FORBIDDEN_SAVE_TOKENS:
                                if lowered.contains(token): hits.append(path + key)
                        _scan_forbidden(value[raw_key], path + key + ".", hits)
        elif value is Array:
                for index in value.size(): _scan_forbidden(value[index], path + str(index) + ".", hits)
        elif value is NodePath or value is RID:
                hits.append(path.trim_suffix("."))

static func _walk_files(path: String, files: Array[String]) -> void:
        var directory := DirAccess.open(path)
        if directory == null: return
        directory.list_dir_begin()
        var name := directory.get_next()
        while not name.is_empty():
                if name != "." and name != "..":
                        var child := path.path_join(name)
                        if directory.current_is_dir():
                                if not PACK_SCAN_SKIP_DIRS.has(name): _walk_files(child, files)
                        else: files.append(child)
                name = directory.get_next()
        directory.list_dir_end()

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
