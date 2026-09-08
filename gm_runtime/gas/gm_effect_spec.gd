class_name GMEffectSpec
extends RefCounted

## Definition 的一次应用快照。Spec 不持有可变效果状态，状态只在 ActiveEffect。

var definition: GMEffectDefinition
var source: String = ""
var source_id: String = ""
var target: String = ""
var target_id: String = ""
var source_object: Object
var target_object: Object
var level: int = 1
var overrides: Dictionary = {}
var context: Dictionary = {}
var spec_id: String = ""
var created_at_usec: int = 0

func _init(p_definition: GMEffectDefinition = null, p_source: String = "", p_level: int = 1, p_overrides: Dictionary = {}) -> void:
	definition = p_definition
	source = p_source
	source_id = p_source
	level = maxi(p_level, 1)
	overrides = p_overrides.duplicate(true)
	created_at_usec = Time.get_ticks_usec()
	spec_id = "gm.effect.spec.%d" % created_at_usec

func configure_identity(p_source_id: String, p_target_id: String, p_context: Dictionary = {}) -> GMEffectSpec:
	source_id = p_source_id.strip_edges()
	source = source_id
	target_id = p_target_id.strip_edges()
	target = target_id
	context = p_context.duplicate(true)
	return self

func with_objects(p_source: Object = null, p_target: Object = null) -> GMEffectSpec:
	source_object = p_source
	target_object = p_target
	if source_id.is_empty(): source_id = GMEffectSpec.stable_identity(p_source)
	if target_id.is_empty(): target_id = GMEffectSpec.stable_identity(p_target)
	source = source_id
	target = target_id
	return self

func to_summary() -> Dictionary:
	return {
		"spec_id": spec_id,
		"definition": definition.to_summary() if definition != null else {},
		"source": source_id if not source_id.is_empty() else source,
		"source_id": source_id if not source_id.is_empty() else source,
		"target": target_id if not target_id.is_empty() else target,
		"target_id": target_id if not target_id.is_empty() else target,
		"level": level,
		"overrides": overrides.duplicate(true),
		"context": context.duplicate(true),
		"created_at_usec": created_at_usec,
	}

static func stable_identity(value: Variant) -> String:
	if value == null: return ""
	if value is String: return str(value)
	if not value is Object or not is_instance_valid(value): return ""
	var object: Object = value
	if object.has_meta("gm_id"):
		var meta_id := str(object.get_meta("gm_id", ""))
		if not meta_id.is_empty(): return meta_id
	for property_name in ["entity_id", "unit_id", "actor_id", "business_id", "ability_id", "effect_id"]:
		if property_name in object:
			var property_value := str(object.get(property_name))
			if not property_value.is_empty(): return property_value
	if object is Node:
		return (object as Node).name
	return object.get_class()

static func from_summary(value: Dictionary, definitions: Dictionary = {}) -> GMEffectSpec:
	var definition_id := str(value.get("definition", {}).get("effect_id", value.get("effect_id", "")) if value.get("definition", {}) is Dictionary else value.get("effect_id", ""))
	var definition: GMEffectDefinition = definitions.get(definition_id, null)
	var spec := GMEffectSpec.new(definition, str(value.get("source_id", value.get("source", ""))), int(value.get("level", 1)), value.get("overrides", {}) if value.get("overrides", {}) is Dictionary else {})
	spec.target_id = str(value.get("target_id", value.get("target", "")))
	spec.source = spec.source_id
	spec.target = spec.target_id
	spec.context = value.get("context", {}).duplicate(true) if value.get("context", {}) is Dictionary else {}
	spec.spec_id = str(value.get("spec_id", spec.spec_id))
	spec.created_at_usec = int(value.get("created_at_usec", spec.created_at_usec))
	return spec
