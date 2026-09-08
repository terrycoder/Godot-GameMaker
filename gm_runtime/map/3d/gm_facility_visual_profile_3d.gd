@tool
class_name GMFacilityVisualProfile3D
extends Resource

## Presentation-only Facility profile.  It describes how a rule-owned
## Facility/WorldObject is shown and where stable semantic sockets are drawn;
## it does not own the Facility, WorkSpot, Process or interaction state.

const SCHEMA := "gm.facility.visual_profile_3d.v1"
const SCHEMA_VERSION := 1
const FIELDS := ["schema", "schema_version", "profile_id", "revision", "display_name_zh", "visual_scene_resource_path", "visual_mesh_resource_path", "interaction_points", "workspots", "input_sockets", "output_sockets", "vfx_sockets", "audio_sockets", "navigation_anchors", "tags"]

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const SOCKET_SCRIPT := preload("res://gm_runtime/map/3d/gm_semantic_socket_3d.gd")
const ANCHOR_SCRIPT := preload("res://gm_runtime/map/3d/gm_semantic_anchor_3d.gd")

@export var profile_id: StringName = &""
@export var revision: int = 1
@export var display_name_zh: String = ""
@export var visual_scene: PackedScene
@export var visual_mesh: Mesh
@export var interaction_points: Array[Resource] = []
@export var workspots: Array[Resource] = []
@export var input_sockets: Array[Resource] = []
@export var output_sockets: Array[Resource] = []
@export var vfx_sockets: Array[Resource] = []
@export var audio_sockets: Array[Resource] = []
@export var navigation_anchors: Array[Resource] = []
@export var tags: PackedStringArray = PackedStringArray()

func validate() -> Dictionary:
    var errors: Array[Dictionary] = []
    if not PLANAR_POSITION.is_valid_stable_id(str(profile_id)) or str(profile_id).is_empty():
        errors.append(_error("profile.id_invalid", "Facility Visual Profile必须是非空稳定ID。", "profile_id"))
    if revision < 1:
        errors.append(_error("profile.revision_invalid", "Facility Visual Profile revision必须为正整数。", "revision"))
    if display_name_zh.strip_edges().is_empty():
        errors.append(_error("profile.name_invalid", "Facility Visual Profile中文名称不能为空。", "display_name_zh"))
    var seen: Dictionary = {}
    var groups := [
        {"field": "interaction_points", "values": interaction_points, "kind": "interaction", "resource": "socket"},
        {"field": "workspots", "values": workspots, "kind": "workspot", "resource": "socket"},
        {"field": "input_sockets", "values": input_sockets, "kind": "input", "resource": "socket"},
        {"field": "output_sockets", "values": output_sockets, "kind": "output", "resource": "socket"},
        {"field": "vfx_sockets", "values": vfx_sockets, "kind": "vfx", "resource": "socket"},
        {"field": "audio_sockets", "values": audio_sockets, "kind": "audio", "resource": "socket"},
        {"field": "navigation_anchors", "values": navigation_anchors, "kind": "navigation", "resource": "anchor"},
    ]
    for group in groups:
        var values: Array = group.values
        for index in values.size():
            var resource = values[index]
            if group.resource == "socket" and not resource is GMSemanticSocket3D:
                errors.append(_error("profile.socket_type_invalid", "Facility Profile 的%s必须是Semantic Socket资源。" % group.field, "%s[%d]" % [group.field, index]))
                continue
            if group.resource == "anchor" and not resource is GMSemanticAnchor3D:
                errors.append(_error("profile.anchor_type_invalid", "Facility Profile 的%s必须是Semantic Anchor资源。" % group.field, "%s[%d]" % [group.field, index]))
                continue
            var native: Dictionary = resource.to_native()
            var identity := str(native.get("socket_id", native.get("anchor_id", "")))
            if str(native.get("socket_kind", native.get("anchor_kind", ""))) != str(group.kind):
                errors.append(_error("profile.socket_kind_invalid", "Facility Profile 的%s类型必须是%s。" % [group.field, group.kind], "%s[%d]" % [group.field, index]))
            if seen.has(identity):
                errors.append(_error("profile.socket_duplicate", "Facility Profile 的语义 Socket/Anchor ID重复：%s。" % identity, "%s[%d]" % [group.field, index]))
            else:
                seen[identity] = true
            var resource_validation: Dictionary = resource.validate()
            if not resource_validation.ok:
                errors.append(_error("profile.socket_invalid", "Facility Profile 的%s包含非法语义资源。" % group.field, "%s[%d]" % [group.field, index]))
            if bool(native.get("required", false)) and typeof(native.get("target_ref", null)) == TYPE_DICTIONARY and native.target_ref.is_empty():
                errors.append(_error("profile.socket_target_missing", "required Semantic Socket/Anchor必须绑定稳定target_ref。", "%s[%d]" % [group.field, index]))
    for raw_tag in tags:
        if not PLANAR_POSITION.is_valid_stable_id(str(raw_tag)):
            errors.append(_error("profile.tag_invalid", "Facility Visual Profile tags必须是稳定ID。", "tags"))
    return {"ok": errors.is_empty(), "code": "profile.valid" if errors.is_empty() else "profile.invalid", "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh), "profile_id": str(profile_id)}

func to_native() -> Dictionary:
    return {
        "schema": SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "profile_id": str(profile_id),
        "revision": revision,
        "display_name_zh": display_name_zh,
        "visual_scene_resource_path": visual_scene.resource_path if visual_scene != null else "",
        "visual_mesh_resource_path": visual_mesh.resource_path if visual_mesh != null else "",
        "interaction_points": _resource_values(interaction_points),
        "workspots": _resource_values(workspots),
        "input_sockets": _resource_values(input_sockets),
        "output_sockets": _resource_values(output_sockets),
        "vfx_sockets": _resource_values(vfx_sockets),
        "audio_sockets": _resource_values(audio_sockets),
        "navigation_anchors": _resource_values(navigation_anchors),
        "tags": Array(tags),
    }

func fingerprint() -> String:
    return VALUE.digest(to_native())

static func from_native(value: Variant) -> Dictionary:
    if not value is Dictionary:
        return _failure("profile.native_type_invalid", "Facility Visual Profile纯值必须是Dictionary。")
    var source: Dictionary = value
    for field in FIELDS:
        if not source.has(field):
            return _failure("profile.field_missing", "Facility Visual Profile缺少字段：%s。" % field)
    for raw_key in source.keys():
        if not FIELDS.has(str(raw_key)):
            return _failure("profile.field_unknown", "Facility Visual Profile包含未知字段：%s。" % raw_key)
    if str(source.get("schema", "")) != SCHEMA or int(source.get("schema_version", 0)) != SCHEMA_VERSION:
        return _failure("profile.schema_invalid", "Facility Visual Profile Schema版本不匹配。")
    var profile := GMFacilityVisualProfile3D.new()
    profile.profile_id = str(source.get("profile_id", ""))
    profile.revision = int(source.get("revision", 1))
    profile.display_name_zh = str(source.get("display_name_zh", ""))
    profile.tags = PackedStringArray(source.get("tags", []))
    var groups := [
        {"field": "interaction_points", "target": profile.interaction_points},
        {"field": "workspots", "target": profile.workspots},
        {"field": "input_sockets", "target": profile.input_sockets},
        {"field": "output_sockets", "target": profile.output_sockets},
        {"field": "vfx_sockets", "target": profile.vfx_sockets},
        {"field": "audio_sockets", "target": profile.audio_sockets},
        {"field": "navigation_anchors", "target": profile.navigation_anchors},
    ]
    for group in groups:
        if not source.get(group.field) is Array:
            return _failure("profile.collection_invalid", "Facility Visual Profile 的%s必须是数组。" % group.field)
        for raw in source.get(group.field):
            var parsed: Dictionary
            if group.field == "navigation_anchors":
                parsed = ANCHOR_SCRIPT.from_native(raw)
            else:
                parsed = SOCKET_SCRIPT.from_native(raw)
            if not parsed.ok:
                return _failure("profile.socket_invalid", "Facility Visual Profile 的%s包含非法语义资源。" % group.field)
            group.target.append(parsed.value)
    var validation := profile.validate()
    if not validation.ok:
        return validation
    return {"ok": true, "value": profile, "profile": profile, "native": profile.to_native()}

static func neutral_profile(p_map_id: String = "gm.map.ext3d04.neutral", p_workspot_target: Dictionary = {}, p_navigation_target: Dictionary = {}) -> GMFacilityVisualProfile3D:
    var workspot_target := p_workspot_target.duplicate(true)
    if workspot_target.is_empty():
        workspot_target = {"type": "facility_slot", "id": "gm.facility.ext3d04.neutral.workspot"}
    var navigation_target := p_navigation_target.duplicate(true)
    if navigation_target.is_empty():
        navigation_target = {"type": "anchor", "id": "gm.anchor.ext3d04.neutral.navigation"}
    var profile := GMFacilityVisualProfile3D.new()
    profile.profile_id = "gm.facility.profile.ext3d04.neutral"
    profile.revision = 1
    profile.display_name_zh = "中性 Facility（可替换外观）"
    profile.tags = PackedStringArray(["neutral", "replaceable", "workshop", "residence", "training"])
    profile.interaction_points.append(_socket("gm.socket.ext3d04.neutral.interaction", "interaction", "交互点", Vector3(0.0, 1.0, 1.5), workspot_target, true))
    profile.workspots.append(_socket("gm.socket.ext3d04.neutral.workspot", "workspot", "WorkSpot", Vector3(0.0, 0.0, 0.0), workspot_target, true))
    profile.input_sockets.append(_socket("gm.socket.ext3d04.neutral.input", "input", "Input Socket", Vector3(-1.2, 0.8, 0.0), {}, false))
    profile.output_sockets.append(_socket("gm.socket.ext3d04.neutral.output", "output", "Output Socket", Vector3(1.2, 0.8, 0.0), {}, false))
    profile.vfx_sockets.append(_socket("gm.socket.ext3d04.neutral.vfx", "vfx", "VFX Socket", Vector3(0.0, 2.4, 0.0), {}, false))
    profile.audio_sockets.append(_socket("gm.socket.ext3d04.neutral.audio", "audio", "Audio Socket", Vector3(0.0, 1.6, -1.5), {}, false))
    profile.navigation_anchors.append(_anchor("gm.anchor3d.ext3d04.neutral.navigation", "navigation", "Navigation Anchor", Vector3(0.0, 0.0, 1.9), navigation_target, true))
    return profile

static func _socket(p_id: String, p_kind: String, p_name: String, p_position: Vector3, p_target: Dictionary, p_required: bool) -> GMSemanticSocket3D:
    var socket := GMSemanticSocket3D.new()
    socket.socket_id = p_id
    socket.socket_kind = p_kind
    socket.display_name_zh = p_name
    socket.position = p_position
    socket.target_ref = p_target.duplicate(true)
    socket.required = p_required
    socket.capacity = 1
    socket.tags = PackedStringArray(["neutral", p_kind])
    return socket

static func _anchor(p_id: String, p_kind: String, p_name: String, p_position: Vector3, p_target: Dictionary, p_required: bool) -> GMSemanticAnchor3D:
    var anchor := GMSemanticAnchor3D.new()
    anchor.anchor_id = p_id
    anchor.anchor_kind = p_kind
    anchor.display_name_zh = p_name
    anchor.position = p_position
    anchor.target_ref = p_target.duplicate(true)
    anchor.required = p_required
    anchor.tags = PackedStringArray(["neutral", p_kind])
    return anchor

func _resource_values(values: Array[Resource]) -> Array:
    var result: Array = []
    for value in values:
        if value != null and value.has_method("to_native"):
            result.append(value.to_native())
    return result

func _error(code: String, message: String, field: String) -> Dictionary:
    return {"code": code, "error_zh": message, "field": field, "profile_id": str(profile_id)}

static func _failure(code: String, message: String) -> Dictionary:
    return {"ok": false, "code": code, "error_zh": message}
