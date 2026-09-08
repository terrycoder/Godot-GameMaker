@tool
class_name GMSemanticAnchor3D
extends Resource

## A profile-local presentation anchor.  The existing semantic map registry
## remains the authority for runtime anchors; this resource only describes a
## stable marker/socket on a facility visual.

const SCHEMA := "gm.scene.semantic_anchor_3d.v1"
const SCHEMA_VERSION := 1
const KINDS := ["navigation", "semantic_slot", "entrance", "npc_point", "visual"]
const FIELDS := ["schema", "schema_version", "anchor_id", "anchor_kind", "display_name_zh", "position", "rotation_degrees", "surface_id", "target_ref", "required", "tags"]

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

@export var anchor_id: StringName = &""
@export_enum("navigation", "semantic_slot", "entrance", "npc_point", "visual") var anchor_kind: String = "visual"
@export var display_name_zh: String = ""
@export var position: Vector3 = Vector3.ZERO
@export var rotation_degrees: Vector3 = Vector3.ZERO
@export var surface_id: StringName = &""
@export var target_ref: Dictionary = {}
@export var required: bool = false
@export var tags: PackedStringArray = PackedStringArray()

func validate() -> Dictionary:
    var errors: Array[Dictionary] = []
    if not PLANAR_POSITION.is_valid_stable_id(str(anchor_id)) or str(anchor_id).is_empty():
        errors.append(_error("anchor.id_invalid", "Anchor必须是非空稳定ID。", "anchor_id"))
    if not KINDS.has(anchor_kind):
        errors.append(_error("anchor.kind_invalid", "Anchor类型不受支持。", "anchor_kind"))
    if not _finite_vector(position) or not _finite_vector(rotation_degrees):
        errors.append(_error("anchor.transform_invalid", "Anchor位置与旋转必须是有限三维值。", "position"))
    if not str(surface_id).is_empty() and not PLANAR_POSITION.is_valid_stable_id(str(surface_id)):
        errors.append(_error("anchor.surface_invalid", "Anchor Surface ID必须是稳定ID。", "surface_id"))
    if typeof(target_ref) != TYPE_DICTIONARY:
        errors.append(_error("anchor.target_type_invalid", "Anchor target_ref必须是稳定字典值。", "target_ref"))
    elif not target_ref.is_empty() and not VALUE.semantic_ref(target_ref, false).ok:
        errors.append(_error("anchor.target_invalid", "Anchor target_ref必须是合法稳定语义目标。", "target_ref"))
    return {"ok": errors.is_empty(), "code": "anchor.valid" if errors.is_empty() else "anchor.invalid", "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh), "anchor_id": str(anchor_id)}

func to_native() -> Dictionary:
    return {
        "schema": SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "anchor_id": str(anchor_id),
        "anchor_kind": anchor_kind,
        "display_name_zh": display_name_zh,
        "position": _vector3_native(position),
        "rotation_degrees": _vector3_native(rotation_degrees),
        "surface_id": str(surface_id),
        "target_ref": VALUE.duplicate_value(target_ref),
        "required": required,
        "tags": Array(tags),
    }

func fingerprint() -> String:
    return VALUE.digest(to_native())

static func from_native(value: Variant) -> Dictionary:
    if not value is Dictionary:
        return _failure("anchor.native_type_invalid", "Anchor纯值必须是Dictionary。")
    var source: Dictionary = value
    for field in FIELDS:
        if not source.has(field):
            return _failure("anchor.field_missing", "Semantic Anchor缺少字段：%s。" % field)
    for raw_key in source.keys():
        if not FIELDS.has(str(raw_key)):
            return _failure("anchor.field_unknown", "Semantic Anchor包含未知字段：%s。" % raw_key)
    if str(source.get("schema", "")) != SCHEMA or int(source.get("schema_version", 0)) != SCHEMA_VERSION:
        return _failure("anchor.schema_invalid", "Semantic Anchor Schema版本不匹配。")
    var anchor := GMSemanticAnchor3D.new()
    anchor.anchor_id = str(source.get("anchor_id", ""))
    anchor.anchor_kind = str(source.get("anchor_kind", ""))
    anchor.display_name_zh = str(source.get("display_name_zh", ""))
    var position := _parse_vector3(source.get("position", {}))
    var rotation := _parse_vector3(source.get("rotation_degrees", {}))
    if not position.ok or not rotation.ok:
        return _failure("anchor.transform_invalid", "Anchor位置与旋转必须是有限三维值。")
    anchor.position = position.value
    anchor.rotation_degrees = rotation.value
    anchor.surface_id = str(source.get("surface_id", ""))
    anchor.target_ref = source.get("target_ref", {}).duplicate(true)
    anchor.required = bool(source.get("required", false))
    anchor.tags = PackedStringArray(source.get("tags", []))
    var validation := anchor.validate()
    if not validation.ok:
        return validation
    return {"ok": true, "value": anchor, "anchor": anchor, "native": anchor.to_native()}

func _error(code: String, message: String, field: String) -> Dictionary:
    return {"code": code, "error_zh": message, "field": field, "anchor_id": str(anchor_id)}

static func _failure(code: String, message: String) -> Dictionary:
    return {"ok": false, "code": code, "error_zh": message}

static func _parse_vector3(value: Variant) -> Dictionary:
    if not value is Dictionary or not value.has("x") or not value.has("y") or not value.has("z"):
        return _failure("anchor.vector_invalid", "Anchor三维向量必须包含x/y/z。")
    if not is_finite(float(value.get("x"))) or not is_finite(float(value.get("y"))) or not is_finite(float(value.get("z"))):
        return _failure("anchor.vector_invalid", "Anchor三维向量必须是有限值。")
    return {"ok": true, "value": Vector3(float(value.get("x")), float(value.get("y")), float(value.get("z")))}

static func _vector3_native(value: Vector3) -> Dictionary:
    return {"x": value.x, "y": value.y, "z": value.z}

static func _finite_vector(value: Vector3) -> bool:
    return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
