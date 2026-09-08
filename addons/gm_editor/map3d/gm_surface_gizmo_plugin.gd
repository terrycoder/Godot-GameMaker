@tool
class_name GMSurfaceGizmoPlugin
extends EditorNode3DGizmoPlugin

const NODE_SCRIPT := preload("res://addons/gm_editor/map3d/gm_surface_gizmo_node.gd")
const PLACEMENT_NODE_SCRIPT := preload("res://addons/gm_editor/map3d/gm_scene_placement_gizmo_node.gd")

func _init() -> void:
    create_material("surface_courtyard", Color("4fc3a1"), false, true)
    create_material("surface_floor", Color("63a4ff"), false, true)
    create_material("surface_bridge", Color("f6bd60"), false, true)
    create_material("connection_preview", Color("ff7b72"), false, true)
    create_material("placement_selection", Color("ffe082"), false, true)
    create_material("placement_socket", Color("80cbc4"), false, true)

func _has_gizmo(node: Node3D) -> bool:
    return node != null and (node.get_script() == NODE_SCRIPT or node.get_script() == PLACEMENT_NODE_SCRIPT)

func _get_gizmo_name() -> String:
    return "GM Surface Graph Gizmo"

func _is_selectable_when_hidden() -> bool:
    return true

func _redraw(gizmo: EditorNode3DGizmo) -> void:
    gizmo.clear()
    var node := gizmo.get_node_3d()
    if node == null:
        return
    if node.get_script() == PLACEMENT_NODE_SCRIPT:
        _redraw_placement(gizmo, node)
        return
    var graph: Resource = node.get("graph") as Resource
    var surface_id := str(node.get("surface_id"))
    if graph == null or not graph.has_method("resolve_surface"):
        return
    var surface: Resource = graph.call("resolve_surface", surface_id) as Resource
    if surface == null:
        return
    var boundary: PackedVector2Array = surface.get("boundary")
    if boundary.size() < 2:
        return
    var outline := PackedVector3Array()
    for index in boundary.size():
        var current := surface.call("logical_to_world", boundary[index]) as Vector3
        var next := surface.call("logical_to_world", boundary[(index + 1) % boundary.size()]) as Vector3
        outline.append(current + Vector3.UP * 0.08)
        outline.append(next + Vector3.UP * 0.08)
    var surface_kind := str(surface.get("surface_kind"))
    var outline_material := get_material("surface_%s" % surface_kind, gizmo)
    if outline_material == null:
        outline_material = get_material("surface_floor", gizmo)
    gizmo.add_lines(outline, outline_material)

    var connection_lines := PackedVector3Array()
    if graph.has_method("resolve_surface"):
        for connection in graph.get("connections"):
            if connection == null:
                continue
            var source_id := str(connection.get("source_surface_id"))
            var target_id := str(connection.get("target_surface_id"))
            if source_id != surface_id and target_id != surface_id:
                continue
            var source_surface: Resource = graph.call("resolve_surface", source_id) as Resource
            var target_surface: Resource = graph.call("resolve_surface", target_id) as Resource
            if source_surface == null or target_surface == null:
                continue
            var start := source_surface.call("logical_to_world", connection.get("source_exit")) as Vector3
            var finish := target_surface.call("logical_to_world", connection.get("target_entry")) as Vector3
            connection_lines.append(start + Vector3.UP * 0.14)
            connection_lines.append(finish + Vector3.UP * 0.14)
    if not connection_lines.is_empty():
                gizmo.add_lines(connection_lines, get_material("connection_preview", gizmo))

func _redraw_placement(gizmo: EditorNode3DGizmo, node: Node3D) -> void:
    var range_value: Vector3 = node.get("gizmo_range") if node.get("gizmo_range") is Vector3 else Vector3.ONE
    var lines := PackedVector3Array()
    lines.append(Vector3(-range_value.x, 0.0, 0.0)); lines.append(Vector3(range_value.x, 0.0, 0.0))
    lines.append(Vector3(0.0, -range_value.y, 0.0)); lines.append(Vector3(0.0, range_value.y, 0.0))
    lines.append(Vector3(0.0, 0.0, -range_value.z)); lines.append(Vector3(0.0, 0.0, range_value.z))
    gizmo.add_lines(lines, get_material("placement_selection", gizmo))
    var socket_ids: PackedStringArray = node.get("socket_ids") if node.get("socket_ids") is PackedStringArray else PackedStringArray()
    if socket_ids.is_empty():
        return
    var socket_lines := PackedVector3Array()
    for index in socket_ids.size():
        var angle := TAU * float(index) / float(maxi(1, socket_ids.size()))
        socket_lines.append(Vector3(cos(angle) * 0.35, 0.0, sin(angle) * 0.35))
        socket_lines.append(Vector3(cos(angle) * 0.6, 0.0, sin(angle) * 0.6))
    gizmo.add_lines(socket_lines, get_material("placement_socket", gizmo))
