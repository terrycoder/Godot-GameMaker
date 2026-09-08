@tool
class_name GMScenePlacementDocument3D
extends Resource

## Saved editor presentation document.  It stores only transforms, stable
## semantic references and source fingerprints; Recipe and the existing map
## graph remain the content/spatial authorities.

const SCHEMA := "gm.scene.placement_3d.v1"
const SCHEMA_VERSION := 1
const FIELDS := ["schema", "schema_version", "document_id", "recipe_id", "recipe_fingerprint", "skeleton_id", "surface_graph_id", "profile_id", "scene_business_id", "scene_resource_path", "placements", "layout_options"]
const PLACEMENT_FIELDS := ["stable_id", "kind", "display_name_zh", "surface_id", "profile_id", "socket_id", "semantic_ref", "position", "rotation_degrees", "scale"]
const VECTOR_FIELDS := ["x", "y", "z"]

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

@export var document_id: String = ""
@export var recipe_id: String = ""
@export var recipe_fingerprint: String = ""
@export var skeleton_id: String = ""
@export var surface_graph_id: String = ""
@export var profile_id: String = ""
@export var scene_business_id: String = ""
@export var scene_resource_path: String = ""
@export var placements: Array[Dictionary] = []
@export var layout_options: Dictionary = {}

func validate() -> Dictionary:
    var errors: Array[Dictionary] = []
    for field in ["document_id", "recipe_id", "recipe_fingerprint", "skeleton_id", "surface_graph_id", "profile_id", "scene_business_id"]:
        if not PLANAR_POSITION.is_valid_stable_id(str(get(field))) or str(get(field)).is_empty():
            errors.append(_error("placement.identity_invalid", "3D摆放文档的%s必须是非空稳定ID。" % field, field))
    if typeof(scene_resource_path) != TYPE_STRING:
        errors.append(_error("placement.scene_path_invalid", "3D摆放文档的场景资源定位必须是字符串。", "scene_resource_path"))
    if typeof(layout_options) != TYPE_DICTIONARY or not VALUE.persistence(layout_options).ok:
        errors.append(_error("placement.options_invalid", "3D摆放文档的布局选项必须是纯值字典。", "layout_options"))
    var ids: Dictionary = {}
    for index in placements.size():
        var placement: Dictionary = placements[index]
        var check := _validate_placement(placement)
        if not check.ok:
            errors.append(_error("placement.item_invalid", "3D摆放文档包含非法摆放项。", "placements[%d]" % index))
            continue
        var stable_id := str(placement.get("stable_id", ""))
        if ids.has(stable_id):
            errors.append(_error("placement.item_duplicate", "3D摆放文档包含重复稳定ID：%s。" % stable_id, "placements[%d]" % index))
        else:
            ids[stable_id] = true
    return {"ok": errors.is_empty(), "code": "placement.document_valid" if errors.is_empty() else "placement.document_invalid", "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh), "document_id": document_id}

func to_native() -> Dictionary:
    return {
        "schema": SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "document_id": document_id,
        "recipe_id": recipe_id,
        "recipe_fingerprint": recipe_fingerprint,
        "skeleton_id": skeleton_id,
        "surface_graph_id": surface_graph_id,
        "profile_id": profile_id,
        "scene_business_id": scene_business_id,
        "scene_resource_path": scene_resource_path,
        "placements": VALUE.duplicate_value(placements),
        "layout_options": VALUE.duplicate_value(layout_options),
    }

func fingerprint() -> String:
    return VALUE.digest(to_native())

func set_placement(value: Dictionary) -> Dictionary:
    var candidate := GMScenePlacementDocument3D.from_native(to_native())
    if not candidate.ok:
        return candidate
    var normalized := _normalize_placement(value)
    if not normalized.ok:
        return normalized
    var document: GMScenePlacementDocument3D = candidate.value
    var replaced := false
    for index in document.placements.size():
        if str(document.placements[index].get("stable_id", "")) == str(normalized.value.get("stable_id", "")):
            document.placements[index] = normalized.value
            replaced = true
            break
    if not replaced:
        document.placements.append(normalized.value)
    var validation := document.validate()
    if not validation.ok:
        return validation
    return {"ok": true, "value": document, "replaced": replaced}

func remove_placement(stable_id: String) -> Dictionary:
    if not PLANAR_POSITION.is_valid_stable_id(stable_id) or stable_id.is_empty():
        return {"ok": false, "code": "placement.id_invalid", "error_zh": "待删除摆放项稳定ID无效。"}
    var candidate := GMScenePlacementDocument3D.from_native(to_native())
    if not candidate.ok:
        return candidate
    var document: GMScenePlacementDocument3D = candidate.value
    var removed := false
    for index in range(document.placements.size() - 1, -1, -1):
        if str(document.placements[index].get("stable_id", "")) == stable_id:
            document.placements.remove_at(index)
            removed = true
    if not removed:
        return {"ok": false, "code": "placement.item_missing", "error_zh": "待删除摆放项不存在。", "stable_id": stable_id}
    return {"ok": true, "value": document, "removed": true}

static func neutral_document(p_recipe_id: String, p_recipe_fingerprint: String, p_skeleton_id: String, p_graph_id: String, p_profile_id: String, p_path: String = "user://gm_ext_3d_04_scene_placement.tres") -> GMScenePlacementDocument3D:
    var document := GMScenePlacementDocument3D.new()
    document.document_id = "gm.scene.placement.ext3d04.neutral"
    document.recipe_id = p_recipe_id
    document.recipe_fingerprint = p_recipe_fingerprint
    document.skeleton_id = p_skeleton_id
    document.surface_graph_id = p_graph_id
    document.profile_id = p_profile_id
    document.scene_business_id = "gm.scene.ext3d04.neutral"
    document.scene_resource_path = p_path
    document.layout_options = {"grid_size": 1.0, "surface_snap": true, "rotation_snap_degrees": 15.0, "socket_snap_radius": 1.5, "ground_snap": true}
    return document

static func from_native(value: Variant) -> Dictionary:
    if not value is Dictionary:
        return {"ok": false, "code": "placement.native_type_invalid", "error_zh": "3D摆放文档必须是Dictionary。"}
    var source: Dictionary = value
    for field in FIELDS:
        if not source.has(field):
            return {"ok": false, "code": "placement.field_missing", "error_zh": "3D摆放文档缺少字段：%s。" % field}
    for raw_key in source.keys():
        if not FIELDS.has(str(raw_key)):
            return {"ok": false, "code": "placement.field_unknown", "error_zh": "3D摆放文档包含未知字段：%s。" % raw_key}
    if str(source.get("schema", "")) != SCHEMA or int(source.get("schema_version", 0)) != SCHEMA_VERSION:
        return {"ok": false, "code": "placement.schema_invalid", "error_zh": "3D摆放文档Schema版本不匹配。"}
    if not source.get("placements") is Array or not source.get("layout_options") is Dictionary:
        return {"ok": false, "code": "placement.collection_invalid", "error_zh": "3D摆放文档集合字段类型无效。"}
    var document := GMScenePlacementDocument3D.new()
    document.document_id = str(source.get("document_id", ""))
    document.recipe_id = str(source.get("recipe_id", ""))
    document.recipe_fingerprint = str(source.get("recipe_fingerprint", ""))
    document.skeleton_id = str(source.get("skeleton_id", ""))
    document.surface_graph_id = str(source.get("surface_graph_id", ""))
    document.profile_id = str(source.get("profile_id", ""))
    document.scene_business_id = str(source.get("scene_business_id", ""))
    document.scene_resource_path = str(source.get("scene_resource_path", ""))
    document.layout_options = source.get("layout_options", {}).duplicate(true)
    for raw in source.get("placements", []):
        var normalized := _normalize_placement(raw)
        if not normalized.ok:
            return normalized
        document.placements.append(normalized.value)
    var validation := document.validate()
    if not validation.ok:
        return validation
    return {"ok": true, "value": document, "document": document, "native": document.to_native()}

static func _normalize_placement(value: Variant) -> Dictionary:
    if not value is Dictionary:
        return {"ok": false, "code": "placement.item_type_invalid", "error_zh": "摆放项必须是Dictionary。"}
    var source: Dictionary = value
    for field in PLACEMENT_FIELDS:
        if not source.has(field):
            return {"ok": false, "code": "placement.item_field_missing", "error_zh": "摆放项缺少字段：%s。" % field}
    for raw_key in source.keys():
        if not PLACEMENT_FIELDS.has(str(raw_key)):
            return {"ok": false, "code": "placement.item_field_unknown", "error_zh": "摆放项包含未知字段：%s。" % raw_key}
    for field in ["stable_id", "kind", "display_name_zh", "surface_id", "profile_id", "socket_id"]:
        if not source.get(field) is String:
            return {"ok": false, "code": "placement.item_string_invalid", "error_zh": "摆放项%s必须是字符串。" % field}
    if not PLANAR_POSITION.is_valid_stable_id(str(source.get("stable_id"))) or str(source.get("stable_id")).is_empty():
        return {"ok": false, "code": "placement.item_id_invalid", "error_zh": "摆放项stable_id必须是非空稳定ID。"}
    for field in ["kind", "display_name_zh"]:
        if str(source.get(field)).is_empty():
            return {"ok": false, "code": "placement.item_value_invalid", "error_zh": "摆放项%s不能为空。" % field}
    if not str(source.get("surface_id")).is_empty() and not PLANAR_POSITION.is_valid_stable_id(str(source.get("surface_id"))):
        return {"ok": false, "code": "placement.item_surface_invalid", "error_zh": "摆放项Surface ID无效。"}
    if not str(source.get("profile_id")).is_empty() and not PLANAR_POSITION.is_valid_stable_id(str(source.get("profile_id"))):
        return {"ok": false, "code": "placement.item_profile_invalid", "error_zh": "摆放项Profile ID无效。"}
    if not str(source.get("socket_id")).is_empty() and not PLANAR_POSITION.is_valid_stable_id(str(source.get("socket_id"))):
        return {"ok": false, "code": "placement.item_socket_invalid", "error_zh": "摆放项Socket ID无效。"}
    if not source.get("semantic_ref").is_empty() and not VALUE.semantic_ref(source.get("semantic_ref"), false).ok:
        return {"ok": false, "code": "placement.item_target_invalid", "error_zh": "摆放项semantic_ref必须是合法稳定语义目标。"}
    var positions: Dictionary = {}
    for field in ["position", "rotation_degrees", "scale"]:
        var parsed := _parse_vector(source.get(field))
        if not parsed.ok:
            return parsed
        positions[field] = parsed.value
    if positions.scale.x <= 0.0 or positions.scale.y <= 0.0 or positions.scale.z <= 0.0:
        return {"ok": false, "code": "placement.scale_invalid", "error_zh": "摆放项scale必须为正数。"}
    return {"ok": true, "value": {"stable_id": str(source.get("stable_id")), "kind": str(source.get("kind")), "display_name_zh": str(source.get("display_name_zh")), "surface_id": str(source.get("surface_id")), "profile_id": str(source.get("profile_id")), "socket_id": str(source.get("socket_id")), "semantic_ref": VALUE.duplicate_value(source.get("semantic_ref")), "position": _vector_native(positions.position), "rotation_degrees": _vector_native(positions.rotation_degrees), "scale": _vector_native(positions.scale)}}

static func _validate_placement(value: Variant) -> Dictionary:
    return _normalize_placement(value)

static func _parse_vector(value: Variant) -> Dictionary:
    if not value is Dictionary:
        return {"ok": false, "code": "placement.vector_invalid", "error_zh": "摆放变换必须是包含x/y/z的字典。"}
    for field in ["x", "y", "z"]:
        if not value.has(field) or not is_finite(float(value.get(field))):
            return {"ok": false, "code": "placement.vector_invalid", "error_zh": "摆放变换必须包含有限x/y/z。"}
    return {"ok": true, "value": Vector3(float(value.get("x")), float(value.get("y")), float(value.get("z")))}

static func _vector_native(value: Vector3) -> Dictionary:
    return {"x": value.x, "y": value.y, "z": value.z}

func _error(code: String, message: String, field: String) -> Dictionary:
    return {"code": code, "error_zh": message, "field": field, "document_id": document_id}
