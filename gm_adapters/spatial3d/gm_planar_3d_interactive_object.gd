class_name GMPlanar3DInteractiveObject
extends Node3D

## Reusable presentation target.  Domain interaction is still routed by the
## selected GMAbilityActivationRequest; content/Profile data supplies identity.

@export var stable_instance_id: String = ""
@export var map_id: String = ""
@export var spatial_position: Dictionary = {}
@export var interaction_ability_id: String = ""
var highlighted: bool = false

func validate_configuration() -> Dictionary:
	if stable_instance_id.strip_edges().is_empty():
		return {"ok": false, "code": "interaction.3d.object_identity_missing", "reason_zh": "3D交互对象必须由内容/Profile配置稳定对象ID。", "atomic": true}
	if map_id.strip_edges().is_empty() or interaction_ability_id.strip_edges().is_empty():
		return {"ok": false, "code": "interaction.3d.object_configuration_missing", "reason_zh": "3D交互对象缺少显式地图或交互能力配置。", "atomic": true}
	var parsed := GMPlanarPosition.from_native(spatial_position)
	if not parsed.ok:
		return {"ok": false, "code": "interaction.3d.object_position_invalid", "reason_zh": "3D交互对象的PlanarPosition配置无效。", "details": parsed, "atomic": true}
	if parsed.position.map_id != map_id.strip_edges():
		return {"ok": false, "code": "interaction.3d.object_map_mismatch", "reason_zh": "3D交互对象地图配置与PlanarPosition不一致。", "atomic": true}
	return {"ok": true, "stable_instance_id": stable_instance_id.strip_edges(), "map_id": map_id.strip_edges(), "interaction_ability_id": interaction_ability_id.strip_edges(), "position": parsed.position.to_native()}

func set_highlight(enabled: bool) -> void:
	highlighted = enabled
