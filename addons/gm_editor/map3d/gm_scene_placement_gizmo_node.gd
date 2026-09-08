@tool
class_name GMScenePlacementGizmoNode
extends Node3D

## Editor-only selectable placement handle.  Its stable ID and socket list are
## references to the placement document; it is never used by runtime code.

@export var stable_id: StringName = &""
@export var gizmo_range: Vector3 = Vector3(1.5, 1.5, 1.5)
@export var socket_ids: PackedStringArray = PackedStringArray()
@export var snap_mode: String = "grid_surface_rotation_socket_ground"

func configure(p_stable_id: String, p_socket_ids: PackedStringArray = PackedStringArray()) -> void:
    stable_id = p_stable_id
    socket_ids = p_socket_ids
    name = "Gizmo_%s" % p_stable_id.replace(".", "_")
    set_meta("gm_id", "gm.gizmo.%s" % p_stable_id)
    set_meta("gm_placement_id", p_stable_id)
    set_meta("gm_gizmo_range", {"x": gizmo_range.x, "y": gizmo_range.y, "z": gizmo_range.z})
    set_meta("gm_socket_ids", Array(socket_ids))
