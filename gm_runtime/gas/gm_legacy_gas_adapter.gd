class_name GMLegacyGASAdapter
extends RefCounted

## 冻结接口兼容桥。它把旧模拟 GAS 的命名映射到唯一 GM 能力底座，不保存另一套运行时状态。

const FROZEN_INTERFACES := [
	"TagContainer",
	"AttributeSet",
	"AbilityDef/System",
	"EffectDef/Instance",
	"CombatResolver",
	"Cue/Event",
]

static func adapt_tag_container(legacy_value = null, registry: GMGameplayTagRegistry = null) -> GMGameplayTagContainer:
	var container := GMGameplayTagContainer.new(registry if registry != null else GMGameplayTagRegistry.create_default())
	if legacy_value is Dictionary:
		for tag_value in legacy_value:
			var source_values = legacy_value[tag_value]
			if source_values is Dictionary:
				for source in source_values:
					container.add_tag(str(tag_value), str(source), int(source_values[source]))
			else:
				container.add_tag(str(tag_value), "legacy", int(source_values))
	return container

static func adapt_ability_definition(legacy_value: Variant) -> GMAbilityDefinition:
	var legacy: Dictionary = legacy_value.duplicate(true) if legacy_value is Dictionary else {}
	var definition := GMAbilityDefinition.new()
	definition.ability_id = str(legacy.get("ability_id", legacy.get("id", "")))
	definition.display_name_zh = str(legacy.get("display_name_zh", legacy.get("name_zh", definition.ability_id)))
	definition.ability_tags = PackedStringArray(legacy.get("ability_tags", legacy.get("tags", [])))
	definition.required_tags = PackedStringArray(legacy.get("required_tags", []))
	definition.blocked_tags = PackedStringArray(legacy.get("blocked_tags", []))
	definition.executor_service_id = str(legacy.get("executor_service_id", legacy.get("executor", "")))
	definition.static_parameters = legacy.get("parameters", {}).duplicate(true) if legacy.get("parameters", {}) is Dictionary else {}
	return definition

static func adapt_effect_definition(legacy_value: Variant) -> GMEffectDefinition:
	var legacy: Dictionary = legacy_value.duplicate(true) if legacy_value is Dictionary else {}
	var definition := GMEffectDefinition.new()
	definition.effect_id = str(legacy.get("effect_id", legacy.get("id", "")))
	definition.display_name_zh = str(legacy.get("display_name_zh", legacy.get("name_zh", definition.effect_id)))
	definition.granted_tags = PackedStringArray(legacy.get("granted_tags", legacy.get("tags", [])))
	definition.modifiers = legacy.get("modifiers", {}).duplicate(true) if legacy.get("modifiers", {}) is Dictionary else {}
	definition.duration_seconds = float(legacy.get("duration_seconds", legacy.get("duration", 0.0)))
	return definition

static func adapt_real_mom_resource_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "code": "legacy.resource_missing", "reason_zh": "真实 MOM 资源无法读取：%s" % path, "source_path": path}
	var text := file.get_as_text()
	file.close()
	var parsed := _parse_tres(text)
	if not parsed.ok:
		parsed["source_path"] = path
		return parsed
	var fields: Dictionary = parsed.get("fields", {})
	var script_path := str(parsed.get("script_path", ""))
	var hash := _sha256(path)
	if script_path.ends_with("mom_ability_config.gd"):
		var definition := adapt_ability_definition({
			"ability_id": str(fields.get("ability_id", "")),
			"display_name_zh": str(fields.get("display_name", fields.get("ability_id", ""))),
			"ability_tags": [str(fields.get("ability_tag", ""))] if not str(fields.get("ability_tag", "")).is_empty() else [],
			"parameters": {
				"legacy_type": "MOMAbilityDefinition",
				"ability_type": str(fields.get("ability_type", "")),
				"skill_level": int(fields.get("skill_level", 1)),
				"costs": fields.get("costs", ""),
				"cooldown": fields.get("cooldown", ""),
				"target_query": fields.get("target_query", ""),
				"timeline": fields.get("timeline", ""),
				"description_blocks": fields.get("description_blocks", ""),
				"raw_properties": fields.duplicate(true),
			}
		})
		return {
			"ok": true,
			"source_path": path,
			"source_sha256": hash,
			"legacy_type": "MOMAbilityDefinition",
			"legacy_script": script_path,
			"legacy_fields": fields.duplicate(true),
			"gm_definition": definition.to_summary(),
			"preserved_parameters": definition.static_parameters.duplicate(true),
			"deferred_to_task06_or_15": ["MOM costs/cooldown Resource execution", "MOM target query/timeline execution", "MOM description Resource graph"],
			"behavior_contract": "ID/tag/display/skill_level preserved; activation remains through the single GM request path.",
		}
	if script_path.ends_with("mom_effect_spec.gd"):
		var effect := adapt_effect_definition({
			"effect_id": str(fields.get("effect_id", "")),
			"display_name_zh": str(fields.get("display_name", fields.get("effect_id", ""))),
			"modifiers": {
				"legacy_type": "MOMEffectSpec",
				"effect_type": str(fields.get("effect_type", "")),
				"amount": float(fields.get("amount", 0.0)),
				"amount_formula": fields.get("amount_formula", ""),
				"damage_tag": str(fields.get("damage_tag", "")),
				"can_crit": bool(fields.get("can_crit", false)),
				"raw_properties": fields.duplicate(true),
			}
		})
		return {
			"ok": true,
			"source_path": path,
			"source_sha256": hash,
			"legacy_type": "MOMEffectSpec",
			"legacy_script": script_path,
			"legacy_fields": fields.duplicate(true),
			"gm_definition": effect.to_summary(),
			"preserved_parameters": effect.modifiers.duplicate(true),
			"deferred_to_task06_or_15": ["MOMCombatSubmitter/MOMCombatResolver 完整伤害提交与解析"],
			"behavior_contract": "effect_id/type/amount/formula/damage_tag/crit 保留；完整战斗解析不在任务04接管。",
		}
	return {"ok": false, "code": "legacy.resource_unsupported", "reason_zh": "真实 MOM 资源类型未被任务04适配器支持：%s" % script_path, "source_path": path, "source_sha256": hash, "legacy_fields": fields}

static func adapt_activation_request(host: GMAbilitySystemHost, legacy_value: Dictionary) -> GMAbilityActivationRequest:
	var target_data: GMTargetData = legacy_value.get("target_data", null)
	if target_data == null and legacy_value.get("target", null) is Object:
		target_data = GMTargetData.new(legacy_value.target)
	return GMAbilityActivationRequest.new(host, str(legacy_value.get("ability_id", "")), str(legacy_value.get("ability_tag", "")), target_data, legacy_value.get("event_data", {}), str(legacy_value.get("source", "legacy")), legacy_value.get("schedule_context", {}))

static func adapt_event(legacy_value: Dictionary) -> GMGameplayEvent:
	return GMGameplayEvent.new(str(legacy_value.get("event_tag", legacy_value.get("tag", ""))), legacy_value.get("instigator", null), legacy_value.get("target", null), legacy_value.get("payload", {}), str(legacy_value.get("source", "legacy")))

static func audit_contract() -> Dictionary:
	return {
		"unique_runtime_root": "res://gm_runtime/gas",
		"frozen_interfaces": FROZEN_INTERFACES.duplicate(),
		"old_names_preserved_as": {
			"TagContainer": "GMGameplayTagContainer（add/remove/has 兼容方法）",
			"AttributeSet": "GMAttributeSet",
			"AbilityDef/System": "GMAbilityDefinition + GMAbilitySystemHost",
			"EffectDef/Instance": "GMEffectDefinition + GMEffectSpec + GMActiveEffect",
			"CombatResolver": "GMAbilityDefinition.executor_service_id → 领域执行器",
			"Cue/Event": "GMCueDefinition/GMCueParameters + GMGameplayEvent",
		},
		"behavior_contract": [
			"标签来源计数与精确/层级查询保留。",
			"能力 Definition 静态、Spec 记录等级/来源/覆盖，Instance 管理激活阶段。",
			"领域执行器仍拥有移动、库存、掉落、生产正确性，GAS 只编排。",
			"实时与回合调度器复用同一能力类型。",
		],
		"real_resource_bridge": {
			"entry": "GMLegacyGASAdapter.adapt_real_mom_resource_file(path)",
			"accepted_types": ["MOMAbilityDefinition", "MOMEffectSpec"],
			"preservation": "保留真实 .tres 的原始属性字典、源路径与 SHA256；未接管的 Resource 图保留为 deferred 字段。",
		},
	}

static func _parse_tres(text: String) -> Dictionary:
	var ext_paths: Dictionary = {}
	var in_resource := false
	var fields: Dictionary = {}
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("[ext_resource"):
			var ext_id := _attribute_value(line, "id")
			var ext_path := _attribute_value(line, "path")
			if not ext_id.is_empty() and not ext_path.is_empty():
				ext_paths[ext_id] = ext_path
			continue
		if line == "[resource]":
			in_resource = true
			continue
		if not in_resource or not line.contains("=") or line.begins_with(";"):
			continue
		var separator := line.find("=")
		var key := line.substr(0, separator).strip_edges()
		var raw_value := line.substr(separator + 1).strip_edges()
		fields[key] = _parse_value(raw_value)
	var script_ref := str(fields.get("script", ""))
	var script_id := script_ref
	if script_ref.begins_with("ExtResource("):
		script_id = script_ref.trim_prefix("ExtResource(").trim_suffix(")").replace("\"", "")
	return {"ok": true, "fields": fields, "script_path": str(ext_paths.get(script_id, ""))}

static func _attribute_value(line: String, attribute: String) -> String:
	var marker := attribute + "="
	var start := line.find(marker)
	if start < 0:
		return ""
	start += marker.length()
	if start < line.length() and line.substr(start, 1) == "\"":
		var end := line.find("\"", start + 1)
		return line.substr(start + 1, end - start - 1) if end > start else ""
	var end_unquoted := line.find(" ", start)
	return line.substr(start, end_unquoted - start) if end_unquoted > start else line.substr(start)

static func _parse_value(raw_value: String) -> Variant:
	var value := raw_value.strip_edges()
	if value.begins_with("&"):
		value = value.substr(1).strip_edges()
	if value.begins_with("\"") and value.ends_with("\""):
		var parsed: Variant = JSON.parse_string(value)
		return parsed if parsed != null else value.substr(1, value.length() - 2)
	if value == "true": return true
	if value == "false": return false
	if value.is_valid_int(): return int(value)
	if value.is_valid_float(): return float(value)
	return value

static func _sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(file.get_buffer(file.get_length()))
	file.close()
	return context.finish().hex_encode()
