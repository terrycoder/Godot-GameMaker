class_name GMWorldObjectVisual3D
extends Node3D

## Runtime/editor projection node only.  Rules, abilities, interactions,
## processes, inventory and save state stay on their existing authorities.

const SCHEMA := "gm.world_object.visual_3d.v1"

@export var stable_object_id: StringName = &""
@export var visual_definition_id: StringName = &""
@export var visual_role: String = "world_object"
@export var source_profile_id: StringName = &""

var _visual_instance: Node

func configure(p_object_id: String, p_definition_id: String = "", p_role: String = "world_object", p_profile_id: String = "") -> Dictionary:
    if p_object_id.is_empty() or p_object_id.contains(" ") or p_object_id.contains("/") or p_object_id.contains("\\"):
        return {"ok": false, "code": "visual.object_id_invalid", "error_zh": "3D世界对象呈现必须使用稳定对象ID。"}
    stable_object_id = p_object_id
    visual_definition_id = p_definition_id
    visual_role = p_role
    source_profile_id = p_profile_id
    name = "Visual_%s" % p_object_id.replace(".", "_")
    set_meta("gm_id", p_object_id)
    set_meta("gm_visual_schema", SCHEMA)
    set_meta("gm_visual_role", p_role)
    if not p_profile_id.is_empty():
        set_meta("gm_profile_id", p_profile_id)
    return {"ok": true, "stable_object_id": p_object_id, "visual_definition_id": p_definition_id, "visual_role": p_role}

func bind_mesh(mesh: Mesh, material: Material = null) -> Dictionary:
    if mesh == null:
        return {"ok": false, "code": "visual.mesh_missing", "error_zh": "3D世界对象呈现缺少Mesh。"}
    _clear_visual_instance()
    var instance := MeshInstance3D.new()
    instance.name = "MeshVisual"
    instance.mesh = mesh
    if material != null:
        instance.material_override = material
    add_child(instance)
    _visual_instance = instance
    return {"ok": true, "kind": "mesh", "mesh_type": mesh.get_class()}

func bind_scene(scene: PackedScene) -> Dictionary:
    if scene == null:
        return {"ok": false, "code": "visual.scene_missing", "error_zh": "3D世界对象呈现缺少PackedScene。"}
    _clear_visual_instance()
    var instance := scene.instantiate()
    if instance == null:
        return {"ok": false, "code": "visual.scene_instantiate_failed", "error_zh": "3D世界对象PackedScene实例化失败。"}
    add_child(instance)
    _visual_instance = instance
    return {"ok": true, "kind": "scene", "scene_path": scene.resource_path}

func visual_snapshot() -> Dictionary:
    return {"schema": SCHEMA, "stable_object_id": str(stable_object_id), "visual_definition_id": str(visual_definition_id), "visual_role": visual_role, "source_profile_id": str(source_profile_id), "position": {"x": position.x, "y": position.y, "z": position.z}, "rotation_degrees": {"x": rotation_degrees.x, "y": rotation_degrees.y, "z": rotation_degrees.z}, "scale": {"x": scale.x, "y": scale.y, "z": scale.z}, "projection_only": true}

func _clear_visual_instance() -> void:
    if _visual_instance != null and is_instance_valid(_visual_instance):
        _visual_instance.queue_free()
    _visual_instance = null
