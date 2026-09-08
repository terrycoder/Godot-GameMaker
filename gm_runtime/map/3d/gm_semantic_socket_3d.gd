@tool
class_name GMSemanticSocket3D
extends Resource

## Profile-local 3D presentation socket.  A socket carries a stable semantic
## label and optional stable target reference; it never owns interaction,
## process, inventory, navigation or save facts.

const SCHEMA := "gm.scene.semantic_socket_3d.v1"
const SCHEMA_VERSION := 1
const KINDS := ["interaction", "workspot", "input", "output", "vfx", "audio", "semantic_slot"]
const FIELDS := ["schema", "schema_version", "socket_id", "socket_kind", "display_name_zh", "position", "rotation_degrees", "surface_id", "target_ref", "required", "capacity", "tags"]
const VECTOR_FIELDS := ["x", "y", "z"]

const VALUE := preload("res://gm_runtime/scene/gm_scene_value_contract.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

@export var socket_id: StringName = &""
@export_enum("interaction", "workspot", "input", "output", "vfx", "audio", "semantic_slot") var socket_kind: String = "semantic_slot"
@export var display_name_zh: String = ""
@export var position: Vector3 = Vector3.ZERO
@export var rotation_degrees: Vector3 = Vector3.ZERO
@export var surface_id: StringName = &""
@export var target_ref: Dictionary = {}
@export var required: bool = false
@export_range(1, 1024, 1) var capacity: int = 1
@export var tags: PackedStringArray = PackedStringArray()

func validate() -> Dictionary:
    var errors: Array[Dictionary] = []
    if not PLANAR_POSITION.is_valid_stable_id(str(socket_id)) or str(socket_id).is_empty():
        errors.append(_error("socket.id_invalid", "Socket必须是非空稳定ID。", "socket_id"))
    if not KINDS.has(socket_kind):
        errors.append(_error("socket.kind_invalid", "Socket类型不受支持。", "socket_kind"))
    if not _finite_vector(position) or not _finite_vector(rotation_degrees):
        errors.append(_error("socket.transform_invalid", "Socket位置与旋转必须是有限三维值。", "position"))
    if not str(surface_id).is_empty() and not PLANAR_POSITION.is_valid_stable_id(str(surface_id)):
        errors.append(_error("socket.surface_invalid", "Socket Surface ID必须是稳定ID。", "surface_id"))
    if typeof(target_ref) != TYPE_DICTIONARY:
        errors.append(_error("socket.target_type_invalid", "Socket target_ref必须是稳定字典值。", "target_ref"))
    elif not target_ref.is_empty() and not VALUE.semantic_ref(target_ref, false).ok:
        errors.append(_error("socket.target_invalid", "Socket target_ref必须是合法稳定语义目标。", "target_ref"))
    if typeof(required) != TYPE_BOOL:
        errors.append(_error("socket.required_invalid", "Socket required必须是布尔值。", "required"))
    if capacity < 1:
        errors.append(_error("socket.capacity_invalid", "Socket容量必须至少为1。", "capacity"))
    var seen: Dictionary = {}
    for tag in tags:
        var tag_text := str(tag)
        if tag_text.is_empty() or not PLANAR_POSITION.is_valid_stable_id(tag_text):
            errors.append(_error("socket.tag_invalid", "Socket tags必须是稳定ID数组。", "tags"))
        elif seen.has(tag_text):
            errors.append(_error("socket.tag_duplicate", "Socket tags不能重复。", "tags"))
        else:
            seen[tag_text] = true
    return {"ok": errors.is_empty(), "code": "socket.valid" if errors.is_empty() else "socket.invalid", "errors": errors, "errors_zh": errors.map(func(row): return row.error_zh), "socket_id": str(socket_id)}

func to_native() -> Dictionary:
    return {
        "schema": SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "socket_id": str(socket_id),
        "socket_kind": socket_kind,
        "display_name_zh": display_name_zh,
        "position": _vector3_native(position),
        "rotation_degrees": _vector3_native(rotation_degrees),
        "surface_id": str(surface_id),
        "target_ref": VALUE.duplicate_value(target_ref),
        "required": required,
        "capacity": capacity,
        "tags": Array(tags),
    }

func fingerprint() -> String:
    return VALUE.digest(to_native())

static func from_native(value: Variant) -> Dictionary:
    if not value is Dictionary:
        return _failure("socket.native_type_invalid", "Socket纯值必须是Dictionary。")
    var source: Dictionary = value
    var shape := _validate_fields(source)
    if not shape.ok:
        return shape
    if str(source.get("schema", "")) != SCHEMA or int(source.get("schema_version", 0)) != SCHEMA_VERSION:
        return _failure("socket.schema_invalid", "Semantic Socket Schema版本不匹配。")
    var socket := GMSemanticSocket3D.new()
    socket.socket_id = str(source.get("socket_id", ""))
    socket.socket_kind = str(source.get("socket_kind", ""))
    socket.display_name_zh = str(source.get("display_name_zh", ""))
    var position_check := _parse_vector3(source.get("position", {}))
    var rotation_check := _parse_vector3(source.get("rotation_degrees", {}))
    if not position_check.ok or not rotation_check.ok:
        return _failure("socket.transform_invalid", "Socket位置与旋转必须是有限三维值。")
    socket.position = position_check.value
    socket.rotation_degrees = rotation_check.value
    socket.surface_id = str(source.get("surface_id", ""))
    socket.target_ref = source.get("target_ref", {}).duplicate(true)
    socket.required = bool(source.get("required", false))
    socket.capacity = int(source.get("capacity", 1))
    socket.tags = PackedStringArray(source.get("tags", []))
    var validation := socket.validate()
    if not validation.ok:
        return validation
    return {"ok": true, "value": socket, "socket": socket, "native": socket.to_native()}

func _error(code: String, message: String, field: String) -> Dictionary:
    return {"code": code, "error_zh": message, "field": field, "socket_id": str(socket_id)}

static func _failure(code: String, message: String) -> Dictionary:
    return {"ok": false, "code": code, "error_zh": message}

static func _validate_fields(source: Dictionary) -> Dictionary:
    for field in FIELDS:
        if not source.has(field):
            return _failure("socket.field_missing", "Semantic Socket缺少字段：%s。" % field)
    for raw_key in source.keys():
        if not FIELDS.has(str(raw_key)):
            return _failure("socket.field_unknown", "Semantic Socket包含未知字段：%s。" % raw_key)
    return {"ok": true}

static func _parse_vector3(value: Variant) -> Dictionary:
    if not value is Dictionary:
        return _failure("socket.vector_invalid", "Socket三维向量必须是Dictionary。")
    for field in VECTOR_FIELDS:
        if not value.has(field) or not is_finite(float(value.get(field))):
            return _failure("socket.vector_invalid", "Socket三维向量必须包含有限x/y/z。")
    return {"ok": true, "value": Vector3(float(value.get("x")), float(value.get("y")), float(value.get("z")))}

static func _vector3_native(value: Vector3) -> Dictionary:
    return {"x": value.x, "y": value.y, "z": value.z}

static func _finite_vector(value: Vector3) -> bool:
    return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
