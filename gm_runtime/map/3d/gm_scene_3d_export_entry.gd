extends Node

## EXT04 enabled release entry.  It proves that the runtime package can start
## the same P23 Recipe -> SceneRecipe3D projection without editor code.

const DOMAIN_SCRIPT := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")
const TARGET_SCRIPT := preload("res://gm_runtime/spatial_core/gm_spatial_target_ref.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const RECIPE_SCRIPT := preload("res://gm_runtime/scene/gm_scene_recipe.gd")
const SKELETON_SCRIPT := preload("res://gm_runtime/scene/gm_scene_skeleton_definition.gd")
const CONTEXT_SCRIPT := preload("res://gm_runtime/scene/gm_task_execution_context.gd")
const SLOT_SCRIPT := preload("res://gm_runtime/scene/gm_semantic_slot_2d.gd")
const BUILDER_SCRIPT := preload("res://gm_runtime/map/3d/gm_scene_builder_3d.gd")
const PROFILE_SCRIPT := preload("res://gm_runtime/map/3d/gm_facility_visual_profile_3d.gd")
const GRAPH_SCRIPT := preload("res://gm_runtime/map/3d/gm_surface_graph.gd")
const SURFACE_SCRIPT := preload("res://gm_runtime/map/3d/gm_surface_definition_3d.gd")
const BACKEND_SCRIPT := preload("res://gm_runtime/map/3d/gm_map_backend_3d.gd")
const ADAPTER_SCRIPT := preload("res://gm_adapters/spatial3d/gm_planar_3d_spatial_adapter.gd")
const REGISTRY_SCRIPT := preload("res://gm_runtime/map/semantic/gm_map_semantic_registry.gd")
const MAP_SCRIPT := preload("res://gm_runtime/map/semantic/gm_map_semantic_resource.gd")
const ANCHOR_SCRIPT := preload("res://gm_runtime/map/semantic/gm_semantic_anchor.gd")

const MAP_ID := "gm.map.ext3d04.export"
const GRAPH_ID := "gm.graph.ext3d04.export"
const SURFACE_ID := "gm.surface.ext3d04.export.floor"

func _ready() -> void:
    var built := _build_release_scene()
    var root: Node3D = built.get("root", null) as Node3D
    if root != null:
        add_child(root)
    var result := {
        "event": "GM_EXT_3D_04_ENABLED_RUNTIME_SENTINEL",
        "ok": bool(built.get("ok", false)),
        "godot": Engine.get_version_info().get("string", ""),
        "entry": "gm_runtime/map/3d/gm_scene_3d_export_entry.tscn",
        "builder": BUILDER_SCRIPT.BUILDER_VERSION,
        "runtime_3d_started": root != null,
        "artifact": built.get("artifact", {}),
        "error": built.get("error", ""),
        "code": built.get("code", ""),
    }
    _write_result(result)
    print(JSON.stringify(result))
    get_tree().quit(0 if result.ok else 248)

func _build_release_scene() -> Dictionary:
    var graph := GRAPH_SCRIPT.new()
    graph.graph_id = GRAPH_ID
    graph.map_id = MAP_ID
    graph.display_name_zh = "EXT04正式运行Surface Graph"
    var surface := SURFACE_SCRIPT.rectangle(SURFACE_ID, MAP_ID, "floor", Vector3.ZERO, Vector2(20.0, 14.0))
    surface.display_name_zh = "运行时中性Floor"
    var surface_result: Dictionary = graph.register_surface(surface)
    if not surface_result.ok:
        return _failure(surface_result)

    var registry := REGISTRY_SCRIPT.new()
    var semantic := MAP_SCRIPT.new()
    semantic.map_id = MAP_ID
    semantic.surface_ids = PackedStringArray([SURFACE_ID])
    var positions := {
        "entry": Vector2(2.0, 2.0),
        "objective": Vector2(6.0, 4.0),
        "resource": Vector2(4.0, 8.0),
        "hostile": Vector2(12.0, 8.0),
        "facility": Vector2(8.0, 6.0),
        "workspot": Vector2(9.0, 6.0),
        "navigation": Vector2(8.0, 5.0),
        "extraction": Vector2(16.0, 10.0),
    }
    for key in positions.keys():
        var anchor := ANCHOR_SCRIPT.new()
        anchor.anchor_id = "gm.anchor.ext3d04.export.%s" % str(key)
        anchor.position = positions[key]
        anchor.surface_id = SURFACE_ID
        anchor.editor_label = "EXT04 %s" % str(key)
        semantic.anchors.append(anchor)
    var registered: Dictionary = registry.register_map(semantic)
    if not registered.ok:
        return _failure(registered)

    var map_backend := BACKEND_SCRIPT.new()
    var configured: Dictionary = map_backend.configure_graph(graph)
    if not configured.ok:
        return _failure(configured)
    var adapter := ADAPTER_SCRIPT.new(registry, true, map_backend)
    var targets := _targets()
    var recipe := _recipe(targets)
    var skeleton := SKELETON_SCRIPT.new(
        "gm.skeleton.ext3d04.export",
        "EXT04正式运行人工骨架",
        [DOMAIN_SCRIPT.PLANAR_3D],
        [{"region_id": "gm.region.ext3d04.export.main", "region_kind": "play_space", "required": true, "tags": ["neutral"]}],
        recipe.slots.duplicate(true),
        ["neutral", "workshop", "residence", "training"]
    )
    var context := CONTEXT_SCRIPT.new(
        "gm.task.ext3d04.export",
        "gm.assignment.ext3d04.export",
        "scene",
        targets.entry,
        [{"type": "entity", "id": "gm.entity.ext3d04.export.npc"}],
        [],
        {"agent_profile": "default", "path_sample_spacing": 1.0},
        4,
        {}
    )
    var profile := PROFILE_SCRIPT.neutral_profile(MAP_ID, targets.workspot, targets.navigation)
    var placements := [
        _placement("gm.placement.ext3d04.export.building", "building", "运行时 Building", Vector3(6.0, 0.0, 4.0), profile.profile_id),
        _placement("gm.placement.ext3d04.export.facility", "facility", "运行时 Facility", Vector3(12.0, 0.0, 7.0), profile.profile_id),
    ]
    var builder := BUILDER_SCRIPT.new()
    return builder.build_scene(recipe, skeleton, context, adapter, profile, placements, {"strict_profile_targets": true})

func _targets() -> Dictionary:
    var result := {}
    for key in ["entry", "objective", "resource", "hostile", "facility", "workspot", "navigation", "extraction"]:
        result[key] = _anchor_target("gm.anchor.ext3d04.export.%s" % key)
    return result

func _anchor_target(anchor_id: String) -> Dictionary:
    return {
        "schema_version": TARGET_SCRIPT.SCHEMA_VERSION,
        "domain_id": DOMAIN_SCRIPT.PLANAR_3D,
        "kind": "anchor",
        "semantic_id": anchor_id,
        "map_id": MAP_ID,
    }

func _recipe(targets: Dictionary) -> GMSceneRecipe:
    var slots: Array = []
    for row in [
        ["gm.slot.ext3d04.export.entry", "entry", targets.entry, ["spawn"]],
        ["gm.slot.ext3d04.export.objective", "objective", targets.objective, ["objective"]],
        ["gm.slot.ext3d04.export.resource", "resource", targets.resource, ["resource"]],
        ["gm.slot.ext3d04.export.hostile", "hostile", targets.hostile, ["hostile"]],
        ["gm.slot.ext3d04.export.facility", "facility", targets.facility, ["facility"]],
        ["gm.slot.ext3d04.export.exit", "exit", targets.extraction, ["exit"]],
        ["gm.slot.ext3d04.export.extraction", "extraction", targets.extraction, ["exit"]],
    ]:
        var slot := SLOT_SCRIPT.new()
        slot.slot_id = row[0]
        slot.slot_kind = row[1]
        slot.target_ref = row[2].duplicate(true)
        slot.required = true
        slot.capacity = 1
        slot.tags = row[3]
        slots.append(slot.to_dict())
    var objective := {
        "objective_id": "gm.objective.ext3d04.export.facility",
        "kind": "interact",
        "target_value": 1,
        "contribution_field": "facility_interactions",
        "target_ref": targets.facility.duplicate(true),
        "requires_hostile_clear": false,
    }
    var results: Array = []
    for status in ["success", "partial_success", "failed", "extracted"]:
        results.append({
            "result_id": "gm.result.ext3d04.export.%s" % status,
            "status": status,
            "required_objective_ids": ["gm.objective.ext3d04.export.facility"],
            "reason_code": "" if status == "success" else "gm.result.ext3d04.export.%s" % status,
        })
    return RECIPE_SCRIPT.new(
        "gm.recipe.ext3d04.export",
        "EXT04正式运行SceneRecipe",
        "gm.skeleton.ext3d04.export",
        targets.entry,
        targets.extraction,
        RECIPE_SCRIPT.REQUIRED_SLOT_KINDS.duplicate(),
        [
            {"object_id": "gm.object.ext3d04.export.building", "object_kind": "building", "required": true, "tags": ["neutral", "visual"]},
            {"object_id": "gm.object.ext3d04.export.facility", "object_kind": "facility", "required": true, "tags": ["neutral", "replaceable"]},
            {"object_id": "gm.object.ext3d04.export.npc", "object_kind": "actor", "required": true, "tags": ["neutral", "npc_point"]},
        ],
        [{"region_id": "gm.region.ext3d04.export.main", "region_kind": "play_space", "required": true, "tags": ["neutral"]}],
        slots,
        [{"type": "entity", "id": "gm.entity.ext3d04.export.npc"}],
        [objective],
        results,
        ["neutral", "workshop", "residence", "training"]
    )

func _placement(stable_id: String, kind: String, label: String, position: Vector3, profile_id: String) -> Dictionary:
    return {
        "stable_id": stable_id,
        "kind": kind,
        "display_name_zh": label,
        "surface_id": SURFACE_ID,
        "profile_id": profile_id,
        "socket_id": "",
        "semantic_ref": {},
        "position": {"x": position.x, "y": position.y, "z": position.z},
        "rotation_degrees": {"x": 0.0, "y": 0.0, "z": 0.0},
        "scale": {"x": 1.0, "y": 1.0, "z": 1.0},
    }

func _failure(result: Dictionary) -> Dictionary:
    var failure := result.duplicate(true)
    failure["ok"] = false
    return failure

func _write_result(result: Dictionary) -> void:
    var output_path := OS.get_environment("GM_EXT_3D_04_EXPORT_OUTPUT").strip_edges()
    if output_path.is_empty():
        return
    var absolute := output_path if output_path.contains(":") else ProjectSettings.globalize_path(output_path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var output := FileAccess.open(absolute, FileAccess.WRITE)
    if output == null:
        return
    output.store_string(JSON.stringify(result, "  ") + "\n")
    output.close()
