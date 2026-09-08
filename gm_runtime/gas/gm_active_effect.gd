class_name GMActiveEffect
extends RefCounted

## GameplayEffect 的唯一活动实例。任何调度器都只推进 remaining/period。

const SCHEMA_VERSION := "gm.active_effect.v2"

var active_effect_id: String = ""
var effect_spec: GMEffectSpec
var effect_definition_id: String = ""
var source_id: String = ""
var target_id: String = ""
var remaining_seconds: float = 0.0
var remaining_units: float = 0.0
var period_remaining: float = 0.0
var stack_count: int = 1
var state: String = "ACTIVE"
var paused: bool = false
var persisted: bool = false
var applied_modifier_handles: Array[String] = []
var granted_tag_source: String = ""
var tick_index: int = 0
var created_scheduler: Dictionary = {}
var remove_reason_zh: String = ""
var source_alive: bool = true

func _init(p_spec: GMEffectSpec = null) -> void:
	effect_spec = p_spec
	effect_definition_id = p_spec.definition.effect_id if p_spec != null and p_spec.definition != null else ""
	source_id = p_spec.source_id if p_spec != null else ""
	target_id = p_spec.target_id if p_spec != null else ""
	active_effect_id = "gm.effect.active.%s.%d" % [_slug(effect_definition_id if not effect_definition_id.is_empty() else "unknown"), Time.get_ticks_usec()]
	remaining_seconds = p_spec.definition.duration_seconds if p_spec != null and p_spec.definition != null else 0.0
	remaining_units = remaining_seconds
	period_remaining = p_spec.definition.period_seconds if p_spec != null and p_spec.definition != null else 0.0
	persisted = p_spec.definition.persist if p_spec != null and p_spec.definition != null else false
	granted_tag_source = active_effect_id

func is_active() -> bool:
	return state == "ACTIVE"

func is_infinite() -> bool:
	return effect_spec != null and effect_spec.definition != null and effect_spec.definition._normalized_kind() == "infinite"

func is_expired() -> bool:
	if is_infinite(): return false
	if effect_spec == null or effect_spec.definition == null: return true
	return effect_spec.definition._normalized_kind() != "instant" and remaining_units <= 0.0

func to_summary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"active_effect_id": active_effect_id,
		"effect_id": effect_definition_id,
		"effect": effect_spec.to_summary() if effect_spec != null else {},
		"source_id": source_id,
		"target_id": target_id,
		"remaining_seconds": remaining_seconds,
		"remaining_units": remaining_units,
		"period_remaining": period_remaining,
		"stack_count": stack_count,
		"state": state,
		"paused": paused,
		"persisted": persisted,
		"applied_modifier_handles": applied_modifier_handles.duplicate(),
		"granted_tag_source": granted_tag_source,
		"tick_index": tick_index,
		"created_scheduler": created_scheduler.duplicate(true),
		"source_alive": source_alive,
		"remove_reason_zh": remove_reason_zh,
	}

static func from_summary(value: Dictionary, definitions: Dictionary) -> GMActiveEffect:
	var spec_value: Dictionary = value.get("effect", {}) if value.get("effect", {}) is Dictionary else {}
	var effect_id := str(value.get("effect_id", spec_value.get("definition", {}).get("effect_id", "") if spec_value.get("definition", {}) is Dictionary else ""))
	var definition: GMEffectDefinition = definitions.get(effect_id, null)
	var spec := GMEffectSpec.from_summary(spec_value, definitions)
	if spec.definition == null: spec.definition = definition
	var result := GMActiveEffect.new(spec)
	result.active_effect_id = str(value.get("active_effect_id", result.active_effect_id))
	result.effect_definition_id = effect_id
	result.source_id = str(value.get("source_id", spec.source_id))
	result.target_id = str(value.get("target_id", spec.target_id))
	result.remaining_seconds = float(value.get("remaining_seconds", result.remaining_seconds))
	result.remaining_units = float(value.get("remaining_units", result.remaining_seconds))
	result.period_remaining = float(value.get("period_remaining", result.period_remaining))
	result.stack_count = maxi(int(value.get("stack_count", 1)), 1)
	result.state = str(value.get("state", "ACTIVE"))
	result.paused = bool(value.get("paused", false))
	result.persisted = bool(value.get("persisted", result.persisted))
	result.granted_tag_source = str(value.get("granted_tag_source", result.active_effect_id))
	result.tick_index = int(value.get("tick_index", 0))
	result.created_scheduler = value.get("created_scheduler", {}).duplicate(true) if value.get("created_scheduler", {}) is Dictionary else {}
	result.source_alive = bool(value.get("source_alive", true))
	result.remove_reason_zh = str(value.get("remove_reason_zh", ""))
	result.applied_modifier_handles = []
	for handle in value.get("applied_modifier_handles", []): result.applied_modifier_handles.append(str(handle))
	return result

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in range(raw.length()):
		var code := raw.unicode_at(index)
		result += raw.substr(index, 1) if ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45) else "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_") if not result.is_empty() else "effect"
