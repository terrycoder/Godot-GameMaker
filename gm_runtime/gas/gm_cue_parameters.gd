class_name GMCueParameters
extends RefCounted

## Cue 只描述表现语义；路由器可以记录/通知，但不能改规则事实。

var cue_id: String = ""
var stage: String = "execute"
var source: Object
var target: Object
var source_id: String = ""
var target_id: String = ""
var position: Vector2 = Vector2.ZERO
var value: float = 0.0
var tags: PackedStringArray = PackedStringArray()
var context: Dictionary = {}
var parameters: Dictionary = {}

func _init(p_cue_id: String = "", p_target: Object = null, p_parameters: Dictionary = {}) -> void:
	cue_id = p_cue_id.strip_edges()
	target = p_target
	parameters = p_parameters.duplicate(true)
	stage = str(parameters.get("stage", parameters.get("phase", "execute"))).to_lower()
	source = parameters.get("source", null) if parameters.get("source", null) is Object else null
	source_id = str(parameters.get("source_id", GMEffectSpec.stable_identity(source)))
	target_id = str(parameters.get("target_id", GMEffectSpec.stable_identity(target)))
	if parameters.get("position", null) is Vector2: position = parameters.position
	var raw_value: Variant = parameters.get("value", parameters.get("amount", 0.0))
	value = float(raw_value) if typeof(raw_value) in [TYPE_INT, TYPE_FLOAT] else 0.0
	var raw_tags: Variant = parameters.get("tags", [])
	if raw_tags is Array or raw_tags is PackedStringArray:
		for tag in raw_tags: tags.append(str(tag))
	context = parameters.get("context", {}).duplicate(true) if parameters.get("context", {}) is Dictionary else {}

func configure_identity(p_source_id: String, p_target_id: String, p_position: Vector2 = Vector2.ZERO, p_value: float = 0.0, p_tags: PackedStringArray = PackedStringArray(), p_context: Dictionary = {}) -> GMCueParameters:
	source_id = p_source_id.strip_edges()
	target_id = p_target_id.strip_edges()
	position = p_position
	value = p_value
	tags = p_tags.duplicate()
	context = p_context.duplicate(true)
	return self

func to_dict() -> Dictionary:
	return {
		"cue_id": cue_id,
		"stage": stage,
		"source_id": source_id if not source_id.is_empty() else GMEffectSpec.stable_identity(source),
		"target_id": target_id if not target_id.is_empty() else GMEffectSpec.stable_identity(target),
		"position": {"x": position.x, "y": position.y},
		"value": value,
		"tags": Array(tags),
		"context": context.duplicate(true),
		"parameters": parameters.duplicate(true),
	}
