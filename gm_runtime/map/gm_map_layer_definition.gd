@tool
class_name GMMapLayerDefinition
extends Resource

enum LayerKind { GROUND, ROAD, WATER, DECORATION, LOGIC }

@export var layer_id: StringName
@export var display_name_zh: String
@export var kind: LayerKind = LayerKind.GROUND
@export var draw_order: int = 0
@export var locked: bool = false
@export var visible: bool = true
@export var editable: bool = true
@export var terrain_config: Dictionary = {}

func validate() -> Dictionary:
	var errors: Array[String] = []
	if str(layer_id).strip_edges().is_empty(): errors.append("图层ID不能为空")
	if display_name_zh.strip_edges().is_empty(): errors.append("图层中文名称不能为空")
	if locked and editable: errors.append("锁定图层不能标记为可编辑")
	return {"ok": errors.is_empty(), "errors_zh": errors}

func can_edit() -> Dictionary:
	if locked: return {"ok": false, "code": "map.layer_locked", "error_zh": "图层已锁定，拒绝绘制：%s" % layer_id}
	if not editable: return {"ok": false, "code": "map.layer_not_editable", "error_zh": "图层不允许编辑：%s" % layer_id}
	return {"ok": true}
