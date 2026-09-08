extends Node

const HOST = preload("res://gm_runtime/gas/gm_ability_system_host.gd")
const EFFECT = preload("res://gm_runtime/gas/gm_effect_definition.gd")
const SPEC = preload("res://gm_runtime/gas/gm_effect_spec.gd")

func _ready() -> void:
	var host = HOST.new()
	var attribute_result: Dictionary = host.attribute_set.define_attribute("stamina", "float", 100.0, 0.0, 200.0)
	var definition = EFFECT.new()
	definition.effect_id = "gm.effect.task06.export_probe"
	definition.display_name_zh = "任务06导出探针"
	definition.effect_kind = "instant"
	definition.modifiers = {"stamina": {"type": "add", "value": 7.0}}
	var registration: Dictionary = host.register_effect_definition(definition)
	var spec = SPEC.new(definition, "gm.export.source")
	spec.configure_identity("gm.export.source", "gm.export.target", {"probe": "task06"})
	var applied: Dictionary = host.apply_effect(definition, spec)
	var value: Variant = host.attribute_set.get_value("stamina", null)
	var ok: bool = bool(attribute_result.get("ok", false)) and bool(registration.get("ok", false)) and bool(applied.get("ok", false)) and is_equal_approx(float(value), 107.0)
	var payload := {
		"schema_version": "gm.task06.export_runtime.v1",
		"attribute_defined": attribute_result.ok,
		"definition_registered": registration.ok,
		"effect_applied": applied.ok,
		"stamina": value,
		"effect_id": definition.effect_id
	}
	print("GM_TASK06_EXPORT_RUNTIME_%s %s" % ["OK" if ok else "FAIL", JSON.stringify(payload)])
	get_tree().quit(0 if ok else 1)
