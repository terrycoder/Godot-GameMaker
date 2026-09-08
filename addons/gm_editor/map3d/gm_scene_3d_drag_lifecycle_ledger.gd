class_name GMScene3DDragLifecycleLedger
extends RefCounted

## Thin editor adapter for Godot's real drag threshold/payload lifecycle.
## The ledger proves that a drop originated in the formal palette; it is not a
## content or placement authority.

const SCHEMA := "gm.editor.scene3d.drag.v1"
const SOURCE_SCRIPT := "res://addons/gm_editor/map3d/gm_scene_3d_palette.gd"

var _nonce_counter: int = 0
var _active: Dictionary = {}

func issue(item_kind: String, source_instance_id: int) -> Dictionary:
    _nonce_counter += 1
    var nonce := "%s.%d" % [SCHEMA, _nonce_counter]
    var payload := {"type": "gm_scene3d_palette_item", "schema": SCHEMA, "item_kind": item_kind, "source_script": SOURCE_SCRIPT, "source_instance_id": str(source_instance_id), "lifecycle_nonce": nonce}
    _active[nonce] = payload.duplicate(true)
    return payload

func can_accept(payload: Variant, expected_source_instance_id: int = -1) -> Dictionary:
    if not payload is Dictionary:
        return {"ok": false, "code": "editor.scene3d.drag_type_invalid", "error_zh": "3D拖放载荷必须来自正式对象Palette。"}
    var value: Dictionary = payload
    for field in ["type", "schema", "item_kind", "source_script", "source_instance_id", "lifecycle_nonce"]:
        if not value.has(field):
            return {"ok": false, "code": "editor.scene3d.drag_field_missing", "error_zh": "3D拖放载荷缺少生命周期字段：%s。" % field}
    if str(value.get("type")) != "gm_scene3d_palette_item" or str(value.get("schema")) != SCHEMA:
        return {"ok": false, "code": "editor.scene3d.drag_schema_invalid", "error_zh": "3D拖放载荷Schema不匹配。"}
    if str(value.get("source_script")) != SOURCE_SCRIPT:
        return {"ok": false, "code": "editor.scene3d.drag_source_invalid", "error_zh": "3D拖放必须来自正式SceneRecipe3D Palette脚本。"}
    var nonce := str(value.get("lifecycle_nonce"))
    if nonce.is_empty() or not _active.has(nonce):
        return {"ok": false, "code": "editor.scene3d.drag_nonce_invalid", "error_zh": "3D拖放生命周期已失效，请重新从Palette拖出。"}
    if expected_source_instance_id >= 0 and str(value.get("source_instance_id")) != str(expected_source_instance_id):
        return {"ok": false, "code": "editor.scene3d.drag_source_instance_invalid", "error_zh": "3D拖放来源控件不属于当前正式Palette。"}
    if str(value.get("item_kind")).is_empty():
        return {"ok": false, "code": "editor.scene3d.drag_item_invalid", "error_zh": "3D拖放对象类型不能为空。"}
    return {"ok": true, "payload": value.duplicate(true)}

func consume(payload: Variant, expected_source_instance_id: int = -1) -> Dictionary:
    var accepted := can_accept(payload, expected_source_instance_id)
    if not accepted.ok:
        return accepted
    var nonce := str(payload.get("lifecycle_nonce"))
    _active.erase(nonce)
    return {"ok": true, "payload": payload.duplicate(true), "consumed": true}

func reset() -> void:
    _active.clear()
