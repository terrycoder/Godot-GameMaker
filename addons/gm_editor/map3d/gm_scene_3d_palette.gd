class_name GMScene3DPalette
extends ItemList

signal formal_drag_issued(payload: Dictionary)

const LIFECYCLE_SCRIPT := preload("res://addons/gm_editor/map3d/gm_scene_3d_drag_lifecycle_ledger.gd")

var lifecycle: GMScene3DDragLifecycleLedger

func configure(value_lifecycle: GMScene3DDragLifecycleLedger) -> void:
    lifecycle = value_lifecycle
    clear()
    for row in [
        ["中性建筑", "building"],
        ["中性设施", "facility"],
        ["非玩家角色点位", "npc_point"],
        ["入口", "entrance"],
        ["工作位", "workspot"],
        ["语义槽", "semantic_slot"],
        ["导航锚点", "navigation_anchor"],
    ]:
        add_item(str(row[0]))
        set_item_metadata(item_count - 1, str(row[1]))
    set_meta("formal_drag_source_script", LIFECYCLE_SCRIPT.SOURCE_SCRIPT)

func make_formal_payload(item_kind: String) -> Dictionary:
    for index in item_count:
        if str(get_item_metadata(index)) == item_kind:
            return _issue(index)
    return {}

func _get_drag_data(at_position: Vector2):
    var index := get_item_at_position(at_position, true)
    if index < 0:
        return null
    return _issue(index)

func _issue(index: int) -> Dictionary:
    if lifecycle == null:
        return {}
    var payload := lifecycle.issue(str(get_item_metadata(index)), get_instance_id())
    var preview := Label.new()
    preview.text = get_item_text(index)
    preview.add_theme_color_override("font_color", Color("8be9bd"))
    if get_viewport() != null and get_viewport().gui_is_dragging():
        set_drag_preview(preview)
    else:
        preview.free()
    formal_drag_issued.emit(payload)
    return payload
