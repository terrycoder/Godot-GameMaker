class_name GMScene3DDropSurface
extends PanelContainer

signal formal_drop(payload: Dictionary, viewport_position: Vector2)
signal formal_drop_rejected(result: Dictionary)

var lifecycle: GMScene3DDragLifecycleLedger
var expected_source_instance_id: int = -1

func configure(value_lifecycle: GMScene3DDragLifecycleLedger, source_instance_id: int) -> void:
    lifecycle = value_lifecycle
    expected_source_instance_id = source_instance_id
    set_meta("formal_drop_surface", true)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
    if lifecycle == null:
        return false
    return lifecycle.can_accept(data, expected_source_instance_id).ok

func _drop_data(at_position: Vector2, data: Variant) -> void:
    if lifecycle == null:
        return
    var consumed := lifecycle.consume(data, expected_source_instance_id)
    if not consumed.ok:
        formal_drop_rejected.emit(consumed)
        return
    formal_drop.emit(consumed.payload, at_position)
