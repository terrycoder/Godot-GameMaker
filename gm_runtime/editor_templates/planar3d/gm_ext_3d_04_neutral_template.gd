extends RefCounted

## EXT04 editor/test-only neutral fixture.  It contains no project gameplay
## content and is excluded by the existing export planner.

const MAP_ID := "gm.map.ext3d04.neutral"
const COURTYARD_ID := "gm.surface.ext3d04.neutral.courtyard"
const INDOOR_ID := "gm.surface.ext3d04.neutral.indoor"
const BLOCKED_ID := "gm.surface.ext3d04.neutral.blocked"
const GRAPH_ID := "gm.surface_graph.ext3d04.neutral"

const RECIPE_SCRIPT := preload("res://gm_runtime/scene/gm_scene_recipe.gd")
const SKELETON_SCRIPT := preload("res://gm_runtime/scene/gm_scene_skeleton_definition.gd")
const CONTEXT_SCRIPT := preload("res://gm_runtime/scene/gm_task_execution_context.gd")
const SLOT_SCRIPT := preload("res://gm_runtime/scene/gm_semantic_slot_2d.gd")
const TARGET_SCRIPT := preload("res://gm_runtime/spatial_core/gm_spatial_target_ref.gd")
const DOMAIN_SCRIPT := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")
const GRAPH_SCRIPT := preload("res://gm_runtime/map/3d/gm_surface_graph.gd")
const SURFACE_SCRIPT := preload("res://gm_runtime/map/3d/gm_surface_definition_3d.gd")
const CONNECTION_SCRIPT := preload("res://gm_runtime/map/3d/gm_surface_connection.gd")
const PROFILE_SCRIPT := preload("res://gm_runtime/map/3d/gm_facility_visual_profile_3d.gd")

static func build_fixture(p_graph = null) -> Dictionary:
    var graph: GMSurfaceGraph = p_graph as GMSurfaceGraph if p_graph != null else build_graph()
    if graph == null:
        return {"ok": false, "code": "sample.graph_missing", "error_zh": "EXT04中性Surface Graph不存在。"}
    var map_id := str(graph.map_id)
    if map_id.is_empty():
        map_id = MAP_ID
    var surfaces: Array = graph.surfaces
    if surfaces.is_empty():
        return {"ok": false, "code": "sample.surface_missing", "error_zh": "EXT04中性样例至少需要一个Surface。"}
    var first_surface_id := ""
    var second_surface_id := ""
    for surface in surfaces:
        if not bool(surface.walkable):
            continue
        var candidate_id := str(surface.surface_id)
        if candidate_id.is_empty():
            continue
        if first_surface_id.is_empty() or str(surface.surface_kind) == "courtyard":
            if not first_surface_id.is_empty() and second_surface_id.is_empty():
                second_surface_id = first_surface_id
            first_surface_id = candidate_id
        elif second_surface_id.is_empty():
            second_surface_id = candidate_id
    if first_surface_id.is_empty():
        first_surface_id = str(surfaces[0].surface_id) if not surfaces.is_empty() else COURTYARD_ID
    if second_surface_id.is_empty():
        second_surface_id = first_surface_id
    var registry := _build_registry(map_id, _surface_ids(graph), first_surface_id, graph)
    var backend := GMMapBackend3D.new()
    var configured := backend.configure_graph(graph)
    if not configured.ok:
        return {"ok": false, "code": "sample.graph_invalid", "error_zh": "EXT04中性Surface Graph校验失败。", "detail": configured}
    var adapter := GMPlanar3DSpatialAdapter.new(registry, true, backend)
    var targets := _targets(map_id)
    var recipe := build_recipe(targets)
    var skeleton := build_skeleton(targets)
    var context := CONTEXT_SCRIPT.new("gm.task.ext3d04.neutral", "gm.assignment.ext3d04.neutral", "scene", targets.entry, [], [], {"agent_profile": "default"}, 404, {})
    var profile := PROFILE_SCRIPT.neutral_profile(map_id, targets.workspot, targets.navigation)
    return {"ok": true, "map_id": map_id, "graph": graph, "registry": registry, "backend": backend, "adapter": adapter, "recipe": recipe, "skeleton": skeleton, "context": context, "profile": profile, "targets": targets, "primary_surface_id": first_surface_id, "surface_ids": _surface_ids(graph), "anchor_ids": _anchor_ids()}

static func build_graph() -> GMSurfaceGraph:
    var graph := GRAPH_SCRIPT.new()
    graph.graph_id = GRAPH_ID
    graph.map_id = MAP_ID
    graph.display_name_zh = "EXT04中性策划样例"
    var courtyard := SURFACE_SCRIPT.rectangle(COURTYARD_ID, MAP_ID, "courtyard", Vector3(0.0, 0.0, 0.0), Vector2(20.0, 16.0))
    courtyard.display_name_zh = "中性庭院"
    var indoor := SURFACE_SCRIPT.rectangle(INDOOR_ID, MAP_ID, "floor", Vector3(23.0, 2.5, 0.0), Vector2(12.0, 8.0))
    indoor.display_name_zh = "中性室内"
    var blocked := SURFACE_SCRIPT.rectangle(BLOCKED_ID, MAP_ID, "floor", Vector3(0.0, 0.0, 24.0), Vector2(6.0, 6.0))
    blocked.display_name_zh = "不可达负例面"
    blocked.boundary = PackedVector2Array([Vector2(30.0, 24.0), Vector2(36.0, 24.0), Vector2(36.0, 30.0), Vector2(30.0, 30.0)])
    blocked.walkable = false
    graph.register_surface(courtyard)
    graph.register_surface(indoor)
    graph.register_surface(blocked)
    graph.register_connection(_connection("gm.connection.ext3d04.neutral.door", COURTYARD_ID, INDOOR_ID, "door", Vector2(18.0, 8.0), Vector2(0.0, 4.0), true))
    return graph

static func build_recipe(targets: Dictionary) -> GMSceneRecipe:
    var slots: Array = []
    for row in [
        ["gm.slot.ext3d04.entry", "entry", targets.entry, ["spawn"]],
        ["gm.slot.ext3d04.objective", "objective", targets.objective, ["objective"]],
        ["gm.slot.ext3d04.resource", "resource", targets.resource, ["resource"]],
        ["gm.slot.ext3d04.hostile", "hostile", targets.hostile, ["hostile"]],
        ["gm.slot.ext3d04.facility", "facility", targets.facility, ["facility"]],
        ["gm.slot.ext3d04.exit", "exit", targets.extraction, ["exit"]],
        ["gm.slot.ext3d04.extraction", "extraction", targets.extraction, ["exit"]],
    ]:
        var slot = SLOT_SCRIPT.new()
        slot.slot_id = row[0]
        slot.slot_kind = row[1]
        slot.target_ref = row[2].duplicate(true)
        slot.required = true
        slot.capacity = 1
        slot.tags = row[3]
        slots.append(slot.to_dict())
    var objectives := [{"objective_id": "gm.objective.ext3d04.facility", "kind": "interact", "target_value": 1, "contribution_field": "facility_interactions", "target_ref": targets.facility.duplicate(true), "requires_hostile_clear": false}]
    var results: Array = []
    for status in ["success", "partial_success", "failed", "extracted"]:
        results.append({"result_id": "gm.result.ext3d04.%s" % status, "status": status, "required_objective_ids": ["gm.objective.ext3d04.facility"], "reason_code": "" if status == "success" else "gm.result.ext3d04.%s" % status})
    return RECIPE_SCRIPT.new(
        "gm.recipe.ext3d04.neutral",
        "EXT04中性SceneRecipe",
        "gm.skeleton.ext3d04.neutral",
        targets.entry,
        targets.extraction,
        RECIPE_SCRIPT.REQUIRED_SLOT_KINDS.duplicate(),
        [
            {"object_id": "gm.object.ext3d04.neutral.building", "object_kind": "building", "required": true, "tags": ["neutral", "visual"]},
            {"object_id": "gm.object.ext3d04.neutral.facility", "object_kind": "facility", "required": true, "tags": ["neutral", "replaceable"]},
            {"object_id": "gm.object.ext3d04.neutral.npc", "object_kind": "actor", "required": true, "tags": ["neutral", "npc_point"]},
        ],
        [{"region_id": "gm.region.ext3d04.neutral.main", "region_kind": "play_space", "required": true, "tags": ["neutral"]}],
        slots,
        [{"type": "entity", "id": "gm.entity.ext3d04.neutral.npc"}],
        objectives,
        results,
        ["neutral", "workshop", "residence", "training"]
    )

static func build_skeleton(targets: Dictionary) -> GMSceneSkeletonDefinition:
    var recipe := build_recipe(targets)
    return SKELETON_SCRIPT.new("gm.skeleton.ext3d04.neutral", "EXT04中性人工骨架", [DOMAIN_SCRIPT.PLANAR_3D], [{"region_id": "gm.region.ext3d04.neutral.main", "region_kind": "play_space", "required": true, "tags": ["neutral"]}], recipe.slots.duplicate(true), ["neutral", "workshop", "residence", "training"])

static func _build_registry(map_id: String, surface_ids: Array, preferred_surface_id: String = "", graph: Resource = null) -> GMMapSemanticRegistry:
    var registry := GMMapSemanticRegistry.new()
    var semantic := GMMapSemanticResource.new()
    semantic.map_id = map_id
    semantic.surface_ids = PackedStringArray(surface_ids)
    var first_surface_id := preferred_surface_id if not preferred_surface_id.is_empty() else (str(surface_ids[0]) if not surface_ids.is_empty() else COURTYARD_ID)
    var second_surface_id := first_surface_id
    if surface_ids.size() > 1:
        second_surface_id = str(surface_ids[1])
    var rows := [
        ["gm.anchor.ext3d04.neutral.entry", Vector2(2.0, 2.0), first_surface_id, "Entrance"],
        ["gm.anchor.ext3d04.neutral.objective", Vector2(7.0, 4.0), first_surface_id, "Semantic Slot"],
        ["gm.anchor.ext3d04.neutral.resource", Vector2(4.0, 11.0), first_surface_id, "Resource Slot"],
        ["gm.anchor.ext3d04.neutral.hostile", Vector2(14.0, 11.0), first_surface_id, "Hostile Slot"],
        ["gm.anchor.ext3d04.neutral.facility", Vector2(8.0, 7.0), first_surface_id, "Facility Slot"],
        ["gm.anchor.ext3d04.neutral.workspot", Vector2(9.0, 7.0), first_surface_id, "WorkSpot"],
        ["gm.anchor.ext3d04.neutral.navigation", Vector2(8.0, 8.0), first_surface_id, "Navigation Anchor"],
        ["gm.anchor.ext3d04.neutral.extraction", Vector2(17.0, 13.0), first_surface_id, "Extraction"],
    ]
    var preferred_surface: Resource = graph.call("resolve_surface", preferred_surface_id) as Resource if graph != null and graph.has_method("resolve_surface") else null
    var preferred_boundary: PackedVector2Array = preferred_surface.get("boundary") if preferred_surface != null else PackedVector2Array()
    if surface_ids.has(BLOCKED_ID):
        rows.append(["gm.anchor.ext3d04.neutral.unreachable", Vector2(31.0, 25.0), BLOCKED_ID, "不可达负例"])
    for row in rows:
        var anchor := GMSemanticAnchor.new()
        anchor.anchor_id = row[0]
        anchor.position = _fit_position(row[1], preferred_boundary) if str(row[2]) == first_surface_id else row[1]
        anchor.surface_id = row[2]
        anchor.editor_label = row[3]
        semantic.anchors.append(anchor)
    var registered := registry.register_map(semantic)
    return registry if registered.ok else null

static func _fit_position(value: Variant, boundary: PackedVector2Array) -> Vector2:
    var position := value as Vector2
    if boundary.size() < 3:
        return position
    var min_x := boundary[0].x
    var max_x := boundary[0].x
    var min_y := boundary[0].y
    var max_y := boundary[0].y
    for point in boundary:
        min_x = minf(min_x, point.x)
        max_x = maxf(max_x, point.x)
        min_y = minf(min_y, point.y)
        max_y = maxf(max_y, point.y)
    if max_x - min_x <= 0.1 or max_y - min_y <= 0.1:
        return Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)
    return Vector2(clampf(position.x, min_x + 0.05, max_x - 0.05), clampf(position.y, min_y + 0.05, max_y - 0.05))

static func _targets(map_id: String) -> Dictionary:
    return {
        "entry": _anchor_target(map_id, "gm.anchor.ext3d04.neutral.entry"),
        "objective": _anchor_target(map_id, "gm.anchor.ext3d04.neutral.objective"),
        "resource": _anchor_target(map_id, "gm.anchor.ext3d04.neutral.resource"),
        "hostile": _anchor_target(map_id, "gm.anchor.ext3d04.neutral.hostile"),
        "facility": _anchor_target(map_id, "gm.anchor.ext3d04.neutral.facility"),
        "workspot": _anchor_target(map_id, "gm.anchor.ext3d04.neutral.workspot"),
        "navigation": _anchor_target(map_id, "gm.anchor.ext3d04.neutral.navigation"),
        "extraction": _anchor_target(map_id, "gm.anchor.ext3d04.neutral.extraction"),
    }

static func _anchor_target(map_id: String, anchor_id: String) -> Dictionary:
    return {"schema_version": TARGET_SCRIPT.SCHEMA_VERSION, "domain_id": DOMAIN_SCRIPT.PLANAR_3D, "kind": "anchor", "semantic_id": anchor_id, "map_id": map_id}

static func _connection(connection_id: String, source_surface: String, target_surface: String, kind: String, source_exit: Vector2, target_entry: Vector2, bidirectional: bool) -> GMSurfaceConnection:
    var connection := CONNECTION_SCRIPT.new()
    connection.connection_id = connection_id
    connection.source_map_id = MAP_ID
    connection.source_surface_id = source_surface
    connection.target_map_id = MAP_ID
    connection.target_surface_id = target_surface
    connection.connection_kind = kind
    connection.source_exit = source_exit
    connection.target_entry = target_entry
    connection.bidirectional = bidirectional
    connection.direction = "source_to_target"
    connection.agent_profiles = PackedStringArray(["default"])
    connection.traversal_cost = 1.0
    return connection

static func _surface_ids(graph: Resource) -> Array:
    var result: Array = []
    for surface in graph.surfaces:
        result.append(str(surface.surface_id))
    return result

static func _anchor_ids() -> Array:
    return ["gm.anchor.ext3d04.neutral.entry", "gm.anchor.ext3d04.neutral.objective", "gm.anchor.ext3d04.neutral.resource", "gm.anchor.ext3d04.neutral.hostile", "gm.anchor.ext3d04.neutral.facility", "gm.anchor.ext3d04.neutral.workspot", "gm.anchor.ext3d04.neutral.navigation", "gm.anchor.ext3d04.neutral.extraction"]
