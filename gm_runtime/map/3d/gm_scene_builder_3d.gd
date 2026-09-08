class_name GMSceneBuilder3D
extends RefCounted

## The 3D projection builder consumes the sealed P23 pure-value build and
## turns it into a disposable Node3D presentation.  It never adds facts to
## Recipe, Process, Spatial, Object Registry or Save state.

const SCHEMA := "gm.scene.recipe_build_3d.v1"
const BUILDER_VERSION := "gm-ext-3d-04.builder.1"

const RECIPE_BUILDER := preload("res://gm_runtime/scene/gm_scene_recipe_builder.gd")
const RECIPE_SCRIPT := preload("res://gm_runtime/scene/gm_scene_recipe.gd")
const SKELETON_SCRIPT := preload("res://gm_runtime/scene/gm_scene_skeleton_definition.gd")
const CONTEXT_SCRIPT := preload("res://gm_runtime/scene/gm_task_execution_context.gd")
const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const PROFILE_SCRIPT := preload("res://gm_runtime/map/3d/gm_facility_visual_profile_3d.gd")
const VISUAL_SCRIPT := preload("res://gm_runtime/map/3d/gm_world_object_visual_3d.gd")
const SOCKET_SCRIPT := preload("res://gm_runtime/map/3d/gm_semantic_socket_3d.gd")
const ANCHOR_SCRIPT := preload("res://gm_runtime/map/3d/gm_semantic_anchor_3d.gd")

var last_build: Dictionary = {}

func build(recipe_value: Variant, skeleton_value: Variant, context_value: Variant, backend: Object, profile_value: Variant = null, placements: Array = [], options: Dictionary = {}) -> Dictionary:
    return build_scene(recipe_value, skeleton_value, context_value, backend, profile_value, placements, options)

func build_scene(recipe_value: Variant, skeleton_value: Variant, context_value: Variant, backend: Object, profile_value: Variant = null, placements: Array = [], options: Dictionary = {}) -> Dictionary:
    if backend == null or not is_instance_valid(backend):
        return _failure("scene.builder3d.backend_missing", "SceneRecipe3D缺少既有Planar 3D空间后端。")
    var recipe_check := _as_recipe(recipe_value)
    var skeleton_check := _as_skeleton(skeleton_value)
    var context_check := _as_context(context_value)
    var profile_check := _as_profile(profile_value)
    if not recipe_check.ok:
        return recipe_check
    if not skeleton_check.ok:
        return skeleton_check
    if not context_check.ok:
        return context_check
    if not profile_check.ok:
        return profile_check
    var recipe = recipe_check.value
    var skeleton = skeleton_check.value
    var context = context_check.value
    var profile: GMFacilityVisualProfile3D = profile_check.value

    # P23 remains the only content compilation authority.
    var p23_builder := RECIPE_BUILDER.new()
    var pure_build: Dictionary = p23_builder.build(recipe, skeleton, context, backend)
    if not pure_build.ok:
        return {"ok": false, "code": "scene.builder3d.recipe_build_failed", "error_zh": "SceneRecipe3D未能通过P23纯值Builder。", "detail": pure_build}

    var graph_check := _resolve_graph(backend, context)
    if not graph_check.ok:
        return graph_check
    var graph: Resource = graph_check.graph
    var graph_validation: Dictionary = graph.call("validate") if graph.has_method("validate") else {"ok": true}
    if not graph_validation.ok:
        return _failure("scene.builder3d.surface_graph_invalid", "SceneRecipe3D引用的Surface Graph校验失败。", {"detail": graph_validation})
    var target_validation := validate_profile_targets(profile, backend, context)
    if not target_validation.ok and bool(options.get("strict_profile_targets", true)):
        return {"ok": false, "code": "scene.builder3d.profile_target_invalid", "error_zh": "Facility Visual Profile 的语义目标无法由既有Spatial后端解析。", "profile_targets": target_validation}
    var placement_check := _validate_placements(placements)
    if not placement_check.ok:
        return placement_check

    var root := Node3D.new()
    root.name = "SceneRecipe3D_%s" % str(recipe.recipe_id).replace(".", "_")
    root.set_meta("gm_id", "gm.scene.3d.%s" % str(recipe.recipe_id))
    root.set_meta("gm_scene_schema", SCHEMA)
    root.set_meta("gm_builder_version", BUILDER_VERSION)
    root.set_meta("gm_recipe_id", str(recipe.recipe_id))
    root.set_meta("gm_recipe_fingerprint", recipe.fingerprint())
    root.set_meta("gm_skeleton_id", str(skeleton.skeleton_id))
    root.set_meta("gm_surface_graph_id", str(graph.get("graph_id")))
    root.set_meta("gm_profile_id", str(profile.profile_id))
    root.set_meta("gm_projection_only", true)

    var surface_ids: Array[String] = []
    for surface in graph.get("surfaces"):
        if surface == null:
            continue
        var surface_id := str(surface.get("surface_id"))
        surface_ids.append(surface_id)
        _add_surface_projection(root, surface)

    var slot_ids: Array[String] = []
    for resolved_slot in pure_build.value.get("resolved_slots", []):
        if not resolved_slot is Dictionary:
            continue
        var slot_id := str(resolved_slot.get("slot_id", ""))
        slot_ids.append(slot_id)
        _add_slot_projection(root, resolved_slot, backend)

    var visual_ids: Array[String] = []
    for placement in placement_check.placements:
        var placed := _add_placement_projection(root, placement, profile)
        if not placed.ok:
            root.free()
            return placed
        visual_ids.append(str(placement.get("stable_id", "")))

    _set_owner_recursive(root, root)
    _set_business_ids_recursive(root, str(root.get_meta("gm_id", "gm.scene.3d.root")))
    var artifact: Dictionary = {
        "schema": SCHEMA,
        "builder_version": BUILDER_VERSION,
        "recipe_id": str(recipe.recipe_id),
        "recipe_fingerprint": recipe.fingerprint(),
        "skeleton_id": str(skeleton.skeleton_id),
        "surface_graph_id": str(graph.get("graph_id")),
        "surface_graph_digest": str(graph.call("stable_digest")) if graph.has_method("stable_digest") else VALUE.digest(graph.get("graph_id")),
        "profile_id": str(profile.profile_id),
        "profile_fingerprint": profile.fingerprint(),
        "build_fingerprint": str(pure_build.value.get("build_fingerprint", "")),
        "surface_ids": surface_ids,
        "semantic_slot_ids": slot_ids,
        "visual_ids": visual_ids,
        "profile_targets": target_validation,
        "placement_count": placement_check.placements.size(),
        "projection_only": true,
    }
    last_build = {"ok": true, "artifact": artifact, "root": root, "build": pure_build.value, "recipe": recipe, "skeleton": skeleton, "context": context, "profile": profile, "profile_targets": target_validation}
    return last_build

func validate_profile_targets(profile_value: Variant, backend: Object, context_value: Variant = null) -> Dictionary:
    var profile_check := _as_profile(profile_value)
    if not profile_check.ok:
        return profile_check
    if backend == null or not is_instance_valid(backend):
        return _failure("scene.builder3d.backend_missing", "Facility Profile目标校验缺少空间后端。")
    var profile: GMFacilityVisualProfile3D = profile_check.value
    var context_check := _as_context(context_value) if context_value != null else {"ok": false}
    var context = context_check.value if context_check.ok else null
    var start_result: Dictionary = {}
    if context != null:
        start_result = backend.resolve_target(context.target)
    var rows: Array = []
    var failures: Array = []
    for group in [
        {"field": "interaction_points", "values": profile.interaction_points, "kind": "interaction"},
        {"field": "workspots", "values": profile.workspots, "kind": "workspot"},
        {"field": "input_sockets", "values": profile.input_sockets, "kind": "input"},
        {"field": "output_sockets", "values": profile.output_sockets, "kind": "output"},
        {"field": "vfx_sockets", "values": profile.vfx_sockets, "kind": "vfx"},
        {"field": "audio_sockets", "values": profile.audio_sockets, "kind": "audio"},
    ]:
        for socket in group.values:
            if not socket is GMSemanticSocket3D:
                failures.append({"code": "scene.builder3d.socket_type_invalid", "error_zh": "Facility Profile包含非Semantic Socket资源。", "field": group.field})
                continue
            var target: Dictionary = socket.target_ref
            var row := {"id": str(socket.socket_id), "kind": group.kind, "required": bool(socket.required), "target_ref": VALUE.duplicate_value(target), "resolved": false, "reachable": null, "ok": true, "error_zh": ""}
            if target.is_empty():
                if socket.required:
                    row.ok = false
                    row.error_zh = "required Socket没有稳定target_ref。"
                    failures.append(row)
                rows.append(row)
                continue
            var resolved: Dictionary = backend.resolve_target(target)
            if not resolved.ok:
                row.ok = not socket.required
                row.error_zh = str(resolved.get("error_zh", "语义目标解析失败。"))
                row["code"] = str(resolved.get("code", "scene.builder3d.target_unresolvable"))
                if socket.required:
                    failures.append(row)
                rows.append(row)
                continue
            row.resolved = true
            if group.kind == "workspot" and context != null and start_result.get("ok", false):
                var from_planar = start_result.value.get("planar_position", {})
                var to_planar = resolved.value.get("planar_position", {})
                var reachable: Dictionary = backend.is_reachable(from_planar, to_planar, {"agent_profile": str(context.constraints.get("agent_profile", "default"))}) if backend.has_method("is_reachable") else {"ok": false, "code": "scene.builder3d.reachability_missing", "error_zh": "空间后端没有既有is_reachable能力。"}
                row.reachable = bool(reachable.get("ok", false)) and bool(reachable.get("value", {}).get("reachable", false))
                if socket.required and not row.reachable:
                    row.ok = false
                    row.error_zh = str(reachable.get("error_zh", "WorkSpot不可达。"))
                    row["code"] = str(reachable.get("code", "spatial.path.unreachable"))
                    failures.append(row)
            rows.append(row)
    for anchor in profile.navigation_anchors:
        if not anchor is GMSemanticAnchor3D:
            failures.append({"code": "scene.builder3d.anchor_type_invalid", "error_zh": "Facility Profile包含非Semantic Anchor资源。", "field": "navigation_anchors"})
            continue
        var target: Dictionary = anchor.target_ref
        var row := {"id": str(anchor.anchor_id), "kind": "navigation", "required": bool(anchor.required), "target_ref": VALUE.duplicate_value(target), "resolved": false, "reachable": null, "ok": true, "error_zh": ""}
        if target.is_empty():
            if anchor.required:
                row.ok = false
                row.error_zh = "required Navigation Anchor没有稳定target_ref。"
                failures.append(row)
            rows.append(row)
            continue
        var resolved: Dictionary = backend.resolve_target(target)
        row.resolved = bool(resolved.get("ok", false))
        if not row.resolved:
            row.ok = not anchor.required
            row.error_zh = str(resolved.get("error_zh", "Navigation Anchor解析失败。"))
            row["code"] = str(resolved.get("code", "scene.builder3d.target_unresolvable"))
            if anchor.required:
                failures.append(row)
        rows.append(row)
    return {"ok": failures.is_empty(), "code": "scene.builder3d.profile_targets_valid" if failures.is_empty() else "scene.builder3d.profile_targets_invalid", "errors": failures, "rows": rows, "profile_id": str(profile.profile_id)}

func _add_surface_projection(parent: Node3D, surface: Resource) -> void:
    var boundary: PackedVector2Array = surface.get("boundary")
    if boundary.size() < 3:
        return
    var min_x := boundary[0].x
    var max_x := boundary[0].x
    var min_z := boundary[0].y
    var max_z := boundary[0].y
    for point in boundary:
        min_x = minf(min_x, point.x)
        max_x = maxf(max_x, point.x)
        min_z = minf(min_z, point.y)
        max_z = maxf(max_z, point.y)
    var instance := MeshInstance3D.new()
    instance.name = "Surface_%s" % str(surface.get("surface_id")).replace(".", "_")
    var mesh := BoxMesh.new()
    mesh.size = Vector3(maxf(max_x - min_x, 0.25), 0.08, maxf(max_z - min_z, 0.25))
    instance.mesh = mesh
    instance.material_override = _material(_surface_color(str(surface.get("surface_kind"))))
    var center := Vector2((min_x + max_x) * 0.5, (min_z + max_z) * 0.5)
    instance.position = surface.call("logical_to_world", center) as Vector3
    instance.set_meta("gm_surface_id", str(surface.get("surface_id")))
    instance.set_meta("gm_projection_only", true)
    parent.add_child(instance)
    var label := Label3D.new()
    label.name = "SurfaceLabel_%s" % str(surface.get("surface_id")).replace(".", "_")
    label.text = "%s  [%s]" % [str(surface.get("display_name_zh")), str(surface.get("surface_kind"))]
    label.position = instance.position + Vector3(0.0, 0.35, 0.0)
    label.font_size = 28
    label.modulate = Color("eef5ff")
    parent.add_child(label)

func _add_slot_projection(parent: Node3D, resolved_slot: Dictionary, backend: Object) -> void:
    var resolution: Dictionary = resolved_slot.get("resolution", {})
    var planar: Dictionary = resolution.get("planar_position", {})
    var world := _world_from_planar(backend, planar)
    if not world.ok:
        return
    var marker := MeshInstance3D.new()
    marker.name = "SemanticSlot_%s" % str(resolved_slot.get("slot_id", "")).replace(".", "_")
    var mesh := SphereMesh.new()
    mesh.radius = 0.22
    mesh.height = 0.44
    marker.mesh = mesh
    marker.material_override = _material(_slot_color(str(resolved_slot.get("slot_kind", "object"))))
    marker.position = world.position + Vector3.UP * 0.3
    marker.set_meta("gm_semantic_slot_id", str(resolved_slot.get("slot_id", "")))
    marker.set_meta("gm_semantic_slot_kind", str(resolved_slot.get("slot_kind", "")))
    marker.set_meta("gm_projection_only", true)
    parent.add_child(marker)
    var label := Label3D.new()
    label.name = "SemanticSlotLabel_%s" % str(resolved_slot.get("slot_id", "")).replace(".", "_")
    label.text = "Slot · %s" % str(resolved_slot.get("slot_kind", ""))
    label.position = marker.position + Vector3.UP * 0.35
    label.font_size = 22
    label.modulate = Color("fff3b0")
    parent.add_child(label)

func _add_placement_projection(parent: Node3D, placement: Dictionary, profile: GMFacilityVisualProfile3D) -> Dictionary:
    var visual := GMWorldObjectVisual3D.new()
    var configured := visual.configure(str(placement.get("stable_id", "")), str(placement.get("kind", "")), "placement_%s" % str(placement.get("kind", "")), str(placement.get("profile_id", "")))
    if not configured.ok:
        return configured
    parent.add_child(visual)
    visual.position = _vector3(placement.get("position", {}))
    visual.rotation_degrees = _vector3(placement.get("rotation_degrees", {}))
    visual.scale = _vector3(placement.get("scale", {}))
    var kind := str(placement.get("kind", ""))
    if kind == "facility" or kind == "building":
        if profile.visual_scene != null:
            visual.bind_scene(profile.visual_scene)
        else:
            var mesh: Mesh = profile.visual_mesh
            if mesh == null:
                var box := BoxMesh.new()
                box.size = Vector3(3.6, 2.4, 2.8) if kind == "facility" else Vector3(6.0, 3.0, 5.0)
                mesh = box
            visual.bind_mesh(mesh, _material(Color("5f78a8") if kind == "facility" else Color("405a78")))
        _add_profile_markers(visual, profile)
    elif kind == "npc_point":
        visual.bind_mesh(_marker_mesh(0.3, 0.9), _material(Color("ffcf70")))
        _add_label(visual, "NPC 点")
    elif kind == "entrance":
        visual.bind_mesh(_marker_mesh(0.28, 0.7), _material(Color("7ee787")))
        _add_label(visual, "Entrance")
    elif kind == "workspot":
        visual.bind_mesh(_marker_mesh(0.24, 0.48), _material(Color("ff8a80")))
        _add_label(visual, "WorkSpot")
    elif kind == "semantic_slot":
        visual.bind_mesh(_marker_mesh(0.22, 0.44), _material(Color("ffe082")))
        _add_label(visual, "Semantic Slot")
    elif kind == "navigation_anchor":
        visual.bind_mesh(_marker_mesh(0.2, 0.8), _material(Color("ce93d8")))
        _add_label(visual, "Navigation Anchor")
    else:
        visual.bind_mesh(_marker_mesh(0.25, 0.5), _material(Color("90caf9")))
        _add_label(visual, str(placement.get("display_name_zh", kind)))
    return {"ok": true, "stable_id": str(placement.get("stable_id", "")), "visual": visual}

func _add_profile_markers(parent: Node3D, profile: GMFacilityVisualProfile3D) -> void:
    for socket in profile.interaction_points + profile.workspots + profile.input_sockets + profile.output_sockets + profile.vfx_sockets + profile.audio_sockets:
        if not socket is GMSemanticSocket3D:
            continue
        var marker := MeshInstance3D.new()
        marker.name = "Socket_%s" % str(socket.socket_id).replace(".", "_")
        marker.mesh = _marker_mesh(0.1, 0.2)
        marker.material_override = _material(_socket_color(socket.socket_kind))
        marker.position = socket.position
        marker.rotation_degrees = socket.rotation_degrees
        marker.set_meta("gm_socket_id", str(socket.socket_id))
        marker.set_meta("gm_socket_kind", socket.socket_kind)
        marker.set_meta("gm_projection_only", true)
        parent.add_child(marker)
        var label := Label3D.new()
        label.name = "SocketLabel_%s" % str(socket.socket_id).replace(".", "_")
        label.text = socket.display_name_zh
        label.position = socket.position + Vector3.UP * 0.24
        label.font_size = 18
        label.modulate = _socket_color(socket.socket_kind)
        parent.add_child(label)
    for anchor in profile.navigation_anchors:
        if not anchor is GMSemanticAnchor3D:
            continue
        var marker := MeshInstance3D.new()
        marker.name = "Anchor_%s" % str(anchor.anchor_id).replace(".", "_")
        marker.mesh = _marker_mesh(0.12, 0.55)
        marker.material_override = _material(Color("ce93d8"))
        marker.position = anchor.position
        marker.rotation_degrees = anchor.rotation_degrees
        marker.set_meta("gm_anchor_id", str(anchor.anchor_id))
        marker.set_meta("gm_anchor_kind", anchor.anchor_kind)
        marker.set_meta("gm_projection_only", true)
        parent.add_child(marker)
        _add_label_at(parent, anchor.position + Vector3.UP * 0.35, anchor.display_name_zh, Color("e1bee7"), "AnchorLabel_%s" % str(anchor.anchor_id).replace(".", "_"))

func _add_label(parent: Node3D, text: String) -> void:
    _add_label_at(parent, Vector3(0.0, 0.65, 0.0), text, Color("f4f7fb"), "RoleLabel")

func _add_label_at(parent: Node3D, at: Vector3, text: String, color: Color, label_name: String) -> void:
    var label := Label3D.new()
    label.name = label_name
    label.text = text
    label.position = at
    label.font_size = 20
    label.modulate = color
    parent.add_child(label)

func _resolve_graph(backend: Object, context) -> Dictionary:
    if not backend.has_method("map_backend"):
        return _failure("scene.builder3d.map_backend_missing", "SceneRecipe3D后端没有既有MapBackend入口。")
    var map_backend = backend.map_backend()
    if map_backend == null or not map_backend.has_method("resolve_graph"):
        return _failure("scene.builder3d.graph_resolver_missing", "SceneRecipe3D后端没有既有Surface Graph解析入口。")
    var map_id := str(context.target.get("map_id", ""))
    var graph: Resource = map_backend.resolve_graph(map_id) if not map_id.is_empty() else null
    if graph == null and map_backend.has_method("map_ids"):
        var map_ids: Array = map_backend.map_ids()
        if map_ids.size() == 1:
            graph = map_backend.resolve_graph(str(map_ids[0]))
    if graph == null:
        return _failure("scene.builder3d.graph_missing", "SceneRecipe3D无法解析Context目标对应的Surface Graph。", {"map_id": map_id})
    return {"ok": true, "graph": graph, "map_id": str(graph.get("map_id"))}

func _validate_placements(values: Array) -> Dictionary:
    var normalized: Array = []
    var ids: Dictionary = {}
    for raw in values:
        if not raw is Dictionary:
            return _failure("scene.builder3d.placement_invalid", "SceneRecipe3D摆放输入必须是纯字典数组。")
        var value: Dictionary = raw
        for field in ["stable_id", "kind", "position", "rotation_degrees", "scale"]:
            if not value.has(field):
                return _failure("scene.builder3d.placement_field_missing", "SceneRecipe3D摆放输入缺少字段：%s。" % field)
        var stable_id := str(value.get("stable_id", ""))
        if stable_id.is_empty() or ids.has(stable_id):
            return _failure("scene.builder3d.placement_duplicate", "SceneRecipe3D摆放输入包含重复或空稳定ID。", {"stable_id": stable_id})
        ids[stable_id] = true
        for field in ["position", "rotation_degrees", "scale"]:
            var vector := _parse_vector(value.get(field, {}))
            if not vector.ok:
                return vector
        var scale := _vector3(value.get("scale", {}))
        if scale.x <= 0.0 or scale.y <= 0.0 or scale.z <= 0.0:
            return _failure("scene.builder3d.placement_scale_invalid", "SceneRecipe3D摆放scale必须为正数。")
        normalized.append({"stable_id": stable_id, "kind": str(value.get("kind", "")), "display_name_zh": str(value.get("display_name_zh", value.get("kind", ""))), "surface_id": str(value.get("surface_id", "")), "profile_id": str(value.get("profile_id", "")), "socket_id": str(value.get("socket_id", "")), "semantic_ref": VALUE.duplicate_value(value.get("semantic_ref", {})), "position": VALUE.duplicate_value(value.get("position", {})), "rotation_degrees": VALUE.duplicate_value(value.get("rotation_degrees", {})), "scale": VALUE.duplicate_value(value.get("scale", {}))})
    return {"ok": true, "placements": normalized}

func _set_business_ids_recursive(node: Node, parent_id: String) -> void:
    var child_index := 0
    for child in node.get_children():
        var current_id := str(child.get_meta("gm_id", ""))
        if current_id.is_empty():
            var safe_name := str(child.name).replace(" ", "_").replace("/", "_").replace("\\", "_")
            current_id = "%s.%s.%d" % [parent_id, safe_name, child_index]
            child.set_meta("gm_id", current_id)
        _set_business_ids_recursive(child, current_id)
        child_index += 1

func _as_recipe(value: Variant) -> Dictionary:
    if value is GMSceneRecipe:
        return {"ok": true, "value": value}
    return RECIPE_SCRIPT.from_dict(value)

func _as_skeleton(value: Variant) -> Dictionary:
    if value is GMSceneSkeletonDefinition:
        return {"ok": true, "value": value}
    return SKELETON_SCRIPT.from_dict(value)

func _as_context(value: Variant) -> Dictionary:
    if value is GMTaskExecutionContext:
        return {"ok": true, "value": value}
    return CONTEXT_SCRIPT.from_dict(value)

func _as_profile(value: Variant) -> Dictionary:
    if value is GMFacilityVisualProfile3D:
        var validation: Dictionary = value.validate()
        return {"ok": true, "value": value} if validation.ok else validation
    if value is Dictionary:
        return PROFILE_SCRIPT.from_native(value)
    return _failure("scene.builder3d.profile_missing", "SceneRecipe3D必须显式提供Facility Visual Profile。")

func _world_from_planar(backend: Object, value: Dictionary) -> Dictionary:
    if value.is_empty() or not backend.has_method("logical_to_world"):
        return {"ok": false}
    var result: Dictionary = backend.logical_to_world(value)
    if not result.ok:
        return result
    var raw_world: Dictionary = result.value.get("world_position", {})
    return {"ok": true, "position": Vector3(float(raw_world.get("x", 0.0)), float(raw_world.get("y", 0.0)), float(raw_world.get("z", 0.0)))}

func _parse_vector(value: Variant) -> Dictionary:
    if not value is Dictionary:
        return _failure("scene.builder3d.vector_invalid", "3D摆放变换必须包含x/y/z字典。")
    for field in ["x", "y", "z"]:
        if not value.has(field) or not is_finite(float(value.get(field))):
            return _failure("scene.builder3d.vector_invalid", "3D摆放变换必须是有限x/y/z。")
    return {"ok": true}

func _vector3(value: Dictionary) -> Vector3:
    return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))

func _set_owner_recursive(node: Node, owner: Node) -> void:
    for child in node.get_children():
        child.owner = owner
        _set_owner_recursive(child, owner)

func _marker_mesh(radius: float, height: float) -> Mesh:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    return mesh

func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.78
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.emission_enabled = true
    material.emission = color * 0.22
    return material

func _surface_color(kind: String) -> Color:
    match kind:
        "courtyard": return Color("4db6ac")
        "bridge": return Color("f4b183")
        _: return Color("7197c8")

func _slot_color(kind: String) -> Color:
    match kind:
        "entry": return Color("81c784")
        "exit", "extraction": return Color("ba68c8")
        "hostile": return Color("e57373")
        "facility": return Color("ffb74d")
        "resource": return Color("64b5f6")
        _: return Color("fff176")

func _socket_color(kind: String) -> Color:
    match kind:
        "interaction": return Color("80cbc4")
        "workspot": return Color("ff8a80")
        "input": return Color("64b5f6")
        "output": return Color("81c784")
        "vfx": return Color("ce93d8")
        "audio": return Color("fff59d")
        _: return Color("e0e0e0")

func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
    var result := {"ok": false, "code": code, "error_zh": message}
    if not details.is_empty():
        result["details"] = VALUE.duplicate_value(details)
    return result
