@tool
class_name GMEffectDefinition
extends Resource

## Gameplay Effect 的静态定义。瞬时、持续、无限、周期都由同一运行时解释。

const SCHEMA_VERSION := "gm.effect_definition.v2"
const KINDS := ["instant", "duration", "infinite", "periodic"]
const STACK_POLICIES := ["independent", "add_stacks", "refresh", "replace", "strongest", "ignore"]

@export var effect_id: String = ""
@export var display_name_zh: String = ""
@export_enum("瞬时", "持续", "无限", "周期") var effect_kind: String = "instant"
@export var granted_tags: PackedStringArray = PackedStringArray()
@export var immunity_tags: PackedStringArray = PackedStringArray()
@export var modifiers: Dictionary = {}
@export var periodic_modifiers: Dictionary = {}
@export var duration_seconds: float = 0.0
@export var duration_unit: String = "seconds"
@export var period_seconds: float = 0.0
@export var period_unit: String = "seconds"
@export var max_stacks: int = 1
@export_enum("独立", "叠层", "刷新", "覆盖", "最强", "忽略") var stack_policy: String = "independent"
@export var persist: bool = false
@export var remove_on_source_lost: bool = false
@export var remove_on_target_death: bool = false
@export var content_version: String = "gm.content.v1"
@export var execute_cue_id: String = ""
@export var add_cue_id: String = ""
@export var remove_cue_id: String = ""
@export var execute_cue_required: bool = false
@export var add_cue_required: bool = false
@export var remove_cue_required: bool = false
@export var metadata: Dictionary = {}

func validate() -> Dictionary:
	var errors: Array[String] = []
	if effect_id.strip_edges().is_empty(): errors.append("GameplayEffect 缺少稳定 effect_id。")
	if not KINDS.has(_normalized_kind()): errors.append("GameplayEffect 类型不受支持：%s。" % effect_kind)
	if duration_seconds < 0.0 or is_nan(duration_seconds) or is_inf(duration_seconds): errors.append("GameplayEffect 持续时间必须是有限非负数。")
	if period_seconds < 0.0 or is_nan(period_seconds) or is_inf(period_seconds): errors.append("GameplayEffect 周期必须是有限非负数。")
	if max_stacks < 1: errors.append("GameplayEffect 最大层数必须大于0。")
	if not STACK_POLICIES.has(_normalized_stack_policy()): errors.append("GameplayEffect 叠层策略不受支持：%s。" % stack_policy)
	if _normalized_kind() == "periodic" and period_seconds <= 0.0: errors.append("周期GameplayEffect必须声明大于0的周期。")
	if not _stable_strings(granted_tags): errors.append("GameplayEffect 授予标签不能重复或为空。")
	if not _stable_strings(immunity_tags): errors.append("GameplayEffect 免疫标签不能重复或为空。")
	return {"ok": errors.is_empty(), "code": "effect_definition.valid" if errors.is_empty() else "effect_definition.invalid", "errors": errors}

func is_instant() -> bool:
	return _normalized_kind() == "instant"

func is_duration_like() -> bool:
	return _normalized_kind() in ["duration", "infinite", "periodic"]

func normalized_modifiers(periodic: bool = false) -> Array[Dictionary]:
	var source: Variant = periodic_modifiers if periodic else modifiers
	var result: Array[Dictionary] = []
	if source is Array:
		for value in source:
			if value is Dictionary: result.append(value.duplicate(true))
		return result
	if not source is Dictionary: return result
	for attribute_id in source:
		var raw: Variant = source[attribute_id]
		if raw is Array:
			for item in raw:
				if item is Dictionary:
					var row: Dictionary = item.duplicate(true)
					if not row.has("attribute_id"): row["attribute_id"] = str(attribute_id)
					result.append(row)
		elif raw is Dictionary:
			var row: Dictionary = raw.duplicate(true)
			if not row.has("attribute_id"): row["attribute_id"] = str(attribute_id)
			result.append(row)
		elif typeof(raw) in [TYPE_INT, TYPE_FLOAT]:
			result.append({"attribute_id": str(attribute_id), "type": "add", "value": float(raw)})
	return result

func duration_for(_scheduler_mode: String = "realtime") -> float:
	return maxf(duration_seconds, 0.0)

func period_for(_scheduler_mode: String = "realtime") -> float:
	return maxf(period_seconds, 0.0)

func to_summary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"effect_id": effect_id,
		"display_name_zh": display_name_zh,
		"effect_kind": _normalized_kind(),
		"granted_tags": Array(granted_tags),
		"immunity_tags": Array(immunity_tags),
		"modifiers": modifiers.duplicate(true),
		"periodic_modifiers": periodic_modifiers.duplicate(true),
		"duration_seconds": duration_seconds,
		"duration_unit": duration_unit,
		"period_seconds": period_seconds,
		"period_unit": period_unit,
		"max_stacks": max_stacks,
		"stack_policy": _normalized_stack_policy(),
		"persist": persist,
		"remove_on_source_lost": remove_on_source_lost,
		"remove_on_target_death": remove_on_target_death,
		"content_version": content_version,
		"execute_cue_id": execute_cue_id,
		"add_cue_id": add_cue_id,
		"remove_cue_id": remove_cue_id,
		"execute_cue_required": execute_cue_required,
		"add_cue_required": add_cue_required,
		"remove_cue_required": remove_cue_required,
		"metadata": metadata.duplicate(true),
	}

func _normalized_kind() -> String:
	match effect_kind:
		"瞬时": return "instant"
		"持续": return "duration"
		"无限": return "infinite"
		"周期": return "periodic"
	return effect_kind.strip_edges().to_lower()

func _normalized_stack_policy() -> String:
	match stack_policy:
		"独立": return "independent"
		"叠层": return "add_stacks"
		"刷新": return "refresh"
		"覆盖": return "replace"
		"最强": return "strongest"
		"忽略": return "ignore"
	return stack_policy.strip_edges().to_lower()

func _stable_strings(value: PackedStringArray) -> bool:
	var seen: Dictionary = {}
	for item in value:
		var text := str(item).strip_edges()
		if text.is_empty() or seen.has(text): return false
		seen[text] = true
	return true
