class_name GMSceneRecipeCompileCache
extends RefCounted

## Derived cache only.  Every artifact is accepted only when the current
## Recipe, Skeleton, Facility Profile, Surface Graph and placement digest all
## match the cache record.  No cache entry is a content or world authority.

const SCHEMA := "gm.scene.recipe_compile_cache_3d.v1"
const LATEST_SCHEMA := "gm.scene.recipe_compile_cache_latest_3d.v1"
const BUILDER_VERSION := "gm-ext-3d-04.builder.1"
const DEFAULT_ROOT := "user://gm_ext_3d_04_compile_cache"
const RECORD_FIELDS := ["schema", "cache_key", "source_digest", "layout_digest", "builder_version", "recipe_id", "profile_id", "surface_graph_id", "artifact_path", "artifact_digest"]

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const BUILDER_SCRIPT := preload("res://gm_runtime/map/3d/gm_scene_builder_3d.gd")
const PROFILE_SCRIPT := preload("res://gm_runtime/map/3d/gm_facility_visual_profile_3d.gd")

func compile_cached(recipe_value: Variant, skeleton_value: Variant, context_value: Variant, backend: Object, profile_value: Variant, placements: Array = [], cache_root: String = DEFAULT_ROOT, options: Dictionary = {}) -> Dictionary:
    var graph_check := _resolve_graph(backend, context_value)
    if not graph_check.ok:
        return graph_check
    var source := source_digest(recipe_value, skeleton_value, profile_value, graph_check.graph, placements, options.get("layout_options", {}))
    var key := cache_key(source)
    var expected_artifact := _artifact_path(cache_root, key)
    var identity_key := latest_identity_key(recipe_value, skeleton_value, profile_value, graph_check.graph)
    var latest := load_latest(cache_root, identity_key)
    var invalidated := false
    var invalidation_reason := ""
    if latest.ok:
        var latest_key := str(latest.get("cache_key", ""))
        var latest_source := str(latest.get("source_digest", ""))
        if latest_key != key or latest_source != source:
            invalidated = true
            invalidation_reason = "scene.cache.invalidated.source_changed"
            _remove_cache_files(cache_root, latest_key)
    elif bool(latest.get("invalidated", false)):
        invalidated = true
        invalidation_reason = str(latest.get("code", "scene.cache.invalidated.latest"))
    var prior := load_record(cache_root, key, source)
    invalidated = invalidated or bool(prior.get("invalidated", false))
    if bool(prior.get("invalidated", false)):
        invalidation_reason = str(prior.get("code", "scene.cache.invalidated.record"))
        _remove_cache_files(cache_root, key)
    if prior.ok:
        var packed: Resource = ResourceLoader.load(str(prior.record.get("artifact_path", expected_artifact)), "PackedScene")
        if packed is PackedScene:
            var instance: Node = packed.instantiate()
            if instance != null:
                var latest_write := write_latest(cache_root, identity_key, key, source, expected_artifact)
                if not latest_write.ok:
                    instance.free()
                    return {"ok": false, "code": "scene.cache.latest_write_failed", "error_zh": "SceneRecipe3D编译缓存最新来源指针写入失败。", "detail": latest_write, "invalidated": invalidated, "cache_key": key, "source_digest": source}
                return {"ok": true, "cache_hit": true, "cache_status": "hit", "invalidated": false, "rebuild_reason": "", "artifact_digest_verified": true, "cache_key": key, "source_digest": source, "record": prior.record, "root": instance, "artifact": prior.record}
        invalidated = true
        invalidation_reason = "scene.cache.invalidated.artifact_unloadable"
        _remove_cache_files(cache_root, key)
    var rebuild_reason: String = invalidation_reason if not invalidation_reason.is_empty() else "scene.cache.miss"

    var builder := GMSceneBuilder3D.new()
    var built: Dictionary = builder.build_scene(recipe_value, skeleton_value, context_value, backend, profile_value, placements, options)
    if not built.ok:
        return {"ok": false, "code": "scene.cache.build_failed", "error_zh": "SceneRecipe3D编译缓存重建失败。", "invalidated": invalidated, "rebuild_reason": rebuild_reason, "cache_key": key, "source_digest": source, "detail": built}
    var packed_scene := PackedScene.new()
    var pack_error := packed_scene.pack(built.root)
    if pack_error != OK:
        built.root.free()
        return {"ok": false, "code": "scene.cache.pack_failed", "error_zh": "SceneRecipe3D派生PackedScene打包失败。", "error": pack_error, "invalidated": invalidated, "rebuild_reason": rebuild_reason, "cache_key": key}
    var absolute := ProjectSettings.globalize_path(expected_artifact)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var save_error := ResourceSaver.save(packed_scene, expected_artifact)
    if save_error != OK:
        built.root.free()
        return {"ok": false, "code": "scene.cache.save_failed", "error_zh": "SceneRecipe3D派生PackedScene保存失败。", "error": save_error, "invalidated": invalidated, "rebuild_reason": rebuild_reason, "cache_key": key}
    var record := {
        "schema": SCHEMA,
        "cache_key": key,
        "source_digest": source,
        "layout_digest": VALUE.digest({"placements": placements, "layout_options": options.get("layout_options", {})}),
        "builder_version": BUILDER_VERSION,
        "recipe_id": _identity(recipe_value, "recipe_id"),
        "profile_id": _identity(profile_value, "profile_id"),
        "surface_graph_id": str(graph_check.graph.get("graph_id")),
        "artifact_path": expected_artifact,
        "artifact_digest": _file_digest(expected_artifact),
    }
    var write := write_record(cache_root, key, record)
    if not write.ok:
        built.root.free()
        return {"ok": false, "code": "scene.cache.record_write_failed", "error_zh": "SceneRecipe3D编译缓存来源记录写入失败。", "detail": write, "invalidated": invalidated, "rebuild_reason": rebuild_reason, "cache_key": key}
    var latest_write := write_latest(cache_root, identity_key, key, source, expected_artifact)
    if not latest_write.ok:
        _remove_cache_files(cache_root, key)
        built.root.free()
        return {"ok": false, "code": "scene.cache.latest_write_failed", "error_zh": "SceneRecipe3D编译缓存最新来源指针写入失败。", "detail": latest_write, "invalidated": invalidated, "rebuild_reason": rebuild_reason, "cache_key": key, "source_digest": source}
    var cache_status: String = "rebuild_after_invalidation" if invalidated else "miss_rebuild"
    return {"ok": true, "cache_hit": false, "cache_status": cache_status, "invalidated": invalidated, "rebuild_reason": rebuild_reason, "artifact_digest_verified": true, "cache_key": key, "source_digest": source, "record": record, "root": built.root, "build": built, "artifact": record}

func source_digest(recipe_value: Variant, skeleton_value: Variant, profile_value: Variant, graph: Resource, placements: Array = [], layout_options: Dictionary = {}) -> String:
    var source := {
        "schema": SCHEMA,
        "builder_version": BUILDER_VERSION,
        "recipe": _native_value(recipe_value, "to_dict"),
        "skeleton": _native_value(skeleton_value, "to_dict"),
        "profile": _native_value(profile_value, "to_native"),
        "surface_graph": _native_value(graph, "to_native"),
        "placements": VALUE.duplicate_value(placements),
        "layout_options": VALUE.duplicate_value(layout_options),
    }
    return VALUE.digest(source)

func cache_key(source_digest_value: String) -> String:
    return "gm.cache.scene.recipe3d.%s" % source_digest_value

func latest_identity_key(recipe_value: Variant, skeleton_value: Variant, profile_value: Variant, graph: Resource) -> String:
    return VALUE.digest({
        "schema": LATEST_SCHEMA,
        "recipe_id": _identity(recipe_value, "recipe_id"),
        "skeleton_id": _identity(skeleton_value, "skeleton_id"),
        "profile_id": _identity(profile_value, "profile_id"),
        "surface_graph_id": str(graph.get("graph_id")),
    })

func load_record(cache_root: String, key: String, expected_source_digest: String = "") -> Dictionary:
    var path := _record_path(cache_root, key)
    if not FileAccess.file_exists(path):
        return {"ok": false, "cache_hit": false, "code": "scene.cache.miss", "error_zh": "SceneRecipe3D编译缓存不存在。", "path": path}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {"ok": false, "cache_hit": false, "code": "scene.cache.read_failed", "error_zh": "SceneRecipe3D编译缓存记录无法读取。", "path": path}
    var parsed = JSON.parse_string(file.get_as_text())
    if not parsed is Dictionary:
        return {"ok": false, "cache_hit": false, "invalidated": true, "code": "scene.cache.record_invalid", "error_zh": "SceneRecipe3D编译缓存记录格式无效。", "path": path}
    var record: Dictionary = parsed
    for field in RECORD_FIELDS:
        if not record.has(field):
            return {"ok": false, "cache_hit": false, "invalidated": true, "code": "scene.cache.record_invalid", "error_zh": "SceneRecipe3D编译缓存记录缺少字段：%s。" % field, "path": path}
    if str(record.get("schema", "")) != SCHEMA or str(record.get("cache_key", "")) != key or str(record.get("builder_version", "")) != BUILDER_VERSION:
        return {"ok": false, "cache_hit": false, "invalidated": true, "code": "scene.cache.record_identity_mismatch", "error_zh": "SceneRecipe3D编译缓存记录身份或Builder版本不匹配。", "record": record}
    if not expected_source_digest.is_empty() and str(record.get("source_digest", "")) != expected_source_digest:
        return {"ok": false, "cache_hit": false, "invalidated": true, "code": "scene.cache.invalidated.source_changed", "error_zh": "SceneRecipe3D编译缓存因Recipe/Profile/Surface来源变更自动失效。", "record": record, "expected_source_digest": expected_source_digest}
    var artifact_path := str(record.get("artifact_path", ""))
    if artifact_path.is_empty() or not FileAccess.file_exists(artifact_path):
        return {"ok": false, "cache_hit": false, "invalidated": true, "code": "scene.cache.invalidated.artifact_missing", "error_zh": "SceneRecipe3D编译缓存派生PackedScene不存在，已失效。", "record": record}
    var expected_artifact_digest := str(record.get("artifact_digest", ""))
    var current_artifact_digest := _file_digest(artifact_path)
    if expected_artifact_digest.is_empty() or current_artifact_digest.is_empty() or current_artifact_digest != expected_artifact_digest:
        return {"ok": false, "cache_hit": false, "invalidated": true, "code": "scene.cache.invalidated.artifact_changed", "error_zh": "SceneRecipe3D编译缓存PackedScene内容摘要与来源记录不一致，已失效并从Recipe重建。", "record": record, "artifact_path": artifact_path, "artifact_digest": expected_artifact_digest, "current_artifact_digest": current_artifact_digest}
    return {"ok": true, "cache_hit": true, "record": record, "path": path}

func write_record(cache_root: String, key: String, record: Dictionary) -> Dictionary:
    var path := _record_path(cache_root, key)
    var shape := _validate_record(record, key)
    if not shape.ok:
        return shape
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return {"ok": false, "code": "scene.cache.record_open_failed", "error_zh": "SceneRecipe3D编译缓存记录文件无法打开。", "path": path}
    file.store_string(JSON.stringify(record, "  ") + "\n")
    return {"ok": true, "path": path, "record": record.duplicate(true)}

func load_latest(cache_root: String, identity_key: String) -> Dictionary:
    var path := _latest_path(cache_root, identity_key)
    if not FileAccess.file_exists(path):
        return {"ok": false, "code": "scene.cache.latest_miss", "path": path}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {"ok": false, "invalidated": true, "code": "scene.cache.latest_read_failed", "error_zh": "SceneRecipe3D编译缓存最新来源指针无法读取。", "path": path}
    var parsed = JSON.parse_string(file.get_as_text())
    if not parsed is Dictionary:
        return {"ok": false, "invalidated": true, "code": "scene.cache.latest_invalid", "error_zh": "SceneRecipe3D编译缓存最新来源指针格式无效。", "path": path}
    var record: Dictionary = parsed
    if str(record.get("schema", "")) != LATEST_SCHEMA or str(record.get("identity_key", "")) != identity_key or str(record.get("cache_key", "")).is_empty():
        return {"ok": false, "invalidated": true, "code": "scene.cache.latest_identity_mismatch", "error_zh": "SceneRecipe3D编译缓存最新来源指针身份不匹配。", "record": record, "path": path}
    return {"ok": true, "record": record, "cache_key": str(record.get("cache_key", "")), "source_digest": str(record.get("source_digest", "")), "artifact_path": str(record.get("artifact_path", "")), "path": path}

func write_latest(cache_root: String, identity_key: String, key: String, source: String, artifact_path: String) -> Dictionary:
    var path := _latest_path(cache_root, identity_key)
    var record := {"schema": LATEST_SCHEMA, "identity_key": identity_key, "cache_key": key, "source_digest": source, "artifact_path": artifact_path}
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return {"ok": false, "code": "scene.cache.latest_open_failed", "error_zh": "SceneRecipe3D编译缓存最新来源指针文件无法打开。", "path": path}
    file.store_string(JSON.stringify(record, "  ") + "\n")
    return {"ok": true, "path": path, "record": record}

func delete_cache(cache_root: String = DEFAULT_ROOT) -> Dictionary:
    var removed: Array[String] = []
    var absolute := ProjectSettings.globalize_path(cache_root)
    var directory := DirAccess.open(absolute)
    if directory == null:
        return {"ok": true, "removed": removed, "cache_root": cache_root, "already_empty": true}
    directory.list_dir_begin()
    var file_name := directory.get_next()
    while not file_name.is_empty():
        if not directory.current_is_dir() and (file_name.ends_with(".json") or file_name.ends_with(".tscn")):
            var path := cache_root.path_join(file_name)
            var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
            if error == OK:
                removed.append(path)
        file_name = directory.get_next()
    directory.list_dir_end()
    return {"ok": true, "removed": removed, "cache_root": cache_root, "already_empty": removed.is_empty()}

func has_cache(cache_root: String = DEFAULT_ROOT) -> bool:
    var directory := DirAccess.open(ProjectSettings.globalize_path(cache_root))
    if directory == null:
        return false
    directory.list_dir_begin()
    var file_name := directory.get_next()
    var found := false
    while not file_name.is_empty():
        if not directory.current_is_dir() and file_name.ends_with(".json") and not file_name.begins_with("latest_"):
            found = true
            break
        file_name = directory.get_next()
    directory.list_dir_end()
    return found

func _resolve_graph(backend: Object, context_value: Variant) -> Dictionary:
    if backend == null or not is_instance_valid(backend) or not backend.has_method("map_backend"):
        return {"ok": false, "code": "scene.cache.backend_missing", "error_zh": "编译缓存缺少既有MapBackend。"}
    var map_backend = backend.map_backend()
    if map_backend == null or not map_backend.has_method("resolve_graph"):
        return {"ok": false, "code": "scene.cache.graph_resolver_missing", "error_zh": "编译缓存缺少既有Surface Graph入口。"}
    var map_id := ""
    if context_value is GMTaskExecutionContext:
        map_id = str(context_value.target.get("map_id", ""))
    elif context_value is Dictionary:
        map_id = str(context_value.get("target", {}).get("map_id", ""))
    var graph: Resource = map_backend.resolve_graph(map_id) if not map_id.is_empty() else null
    if graph == null and map_backend.has_method("map_ids"):
        var map_ids: Array = map_backend.map_ids()
        if map_ids.size() == 1:
            graph = map_backend.resolve_graph(str(map_ids[0]))
    if graph == null:
        return {"ok": false, "code": "scene.cache.graph_missing", "error_zh": "编译缓存无法解析Context对应的Surface Graph。"}
    return {"ok": true, "graph": graph}

func _native_value(value: Variant, method_name: String) -> Variant:
    if value is Object and is_instance_valid(value) and value.has_method(method_name):
        return VALUE.duplicate_value(value.call(method_name))
    if value is Dictionary:
        return VALUE.duplicate_value(value)
    return {}

func _identity(value: Variant, field: String) -> String:
    if value is Object and is_instance_valid(value) and value.get(field) != null:
        return str(value.get(field))
    if value is Dictionary:
        return str(value.get(field, ""))
    return ""

func _record_path(cache_root: String, key: String) -> String:
    return cache_root.path_join(key + ".json")

func _artifact_path(cache_root: String, key: String) -> String:
    return cache_root.path_join(key + ".tscn")

func _latest_path(cache_root: String, identity_key: String) -> String:
    return cache_root.path_join("latest_%s.json" % identity_key)

func _validate_record(record: Dictionary, key: String) -> Dictionary:
    for field in RECORD_FIELDS:
        if not record.has(field):
            return {"ok": false, "code": "scene.cache.record_field_missing", "error_zh": "缓存记录缺少字段：%s。" % field}
    for raw_key in record.keys():
        if not RECORD_FIELDS.has(str(raw_key)):
            return {"ok": false, "code": "scene.cache.record_field_unknown", "error_zh": "缓存记录包含未知字段：%s。" % raw_key}
    if str(record.get("schema", "")) != SCHEMA or str(record.get("cache_key", "")) != key:
        return {"ok": false, "code": "scene.cache.record_identity_invalid", "error_zh": "缓存记录Schema或cache_key无效。"}
    return {"ok": true}

func _remove_cache_files(cache_root: String, key: String) -> void:
    for path in [_record_path(cache_root, key), _artifact_path(cache_root, key)]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _file_digest(path: String) -> String:
    if not FileAccess.file_exists(path):
        return ""
    return VALUE.digest(FileAccess.get_file_as_bytes(path).hex_encode())
