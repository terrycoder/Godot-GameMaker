class_name GMGameplayTagRegistry
extends RefCounted

## 标签的唯一注册与别名解析点。容器不私自接受未知标签，避免拼写错误静默进入运行时。

var definitions: Dictionary = {}
var aliases: Dictionary = {}
var errors: Array[Dictionary] = []
var _usage_index: Dictionary = {}

static func create_default() -> GMGameplayTagRegistry:
	var registry := GMGameplayTagRegistry.new()
	for tag in [
		"gm.ability.move", "gm.ability.eat", "gm.ability.drop_loot", "gm.ability.produce",
		"gm.ability.run", "gm.ability.attack", "gm.ability.die", "gm.ability.respawn",
		"gm.cue.move.start", "gm.cue.move.complete", "gm.cue.entity.death", "gm.cue.work.complete",
		"gm.event.tag.changed", "gm.event.ability.activated", "gm.event.entity.death",
		"state.dead", "state.stunned", "state.busy", "action.moving", "action.eating",
		"action.working", "action.producing"
	]:
		registry.register(tag, [], tag.begins_with("gm."))
	return registry

func register(tag_value: String, tag_aliases: Array = [], platform_owned: bool = false) -> Dictionary:
	var validation := GMGameplayTag.validate(tag_value, platform_owned)
	if not validation.ok:
		errors.append(validation)
		return validation
	var canonical := str(validation.value)
	if definitions.has(canonical) or aliases.has(canonical):
		var duplicate := {"ok": false, "code": "tag.duplicate", "reason_zh": "GameplayTag 重复定义：%s" % canonical}
		errors.append(duplicate)
		return duplicate

	# Composite registration is a single transaction. Validate every alias
	# against the pre-commit registry first so a later failure cannot leave the
	# canonical definition or an earlier alias behind.
	var candidate_aliases: Array[String] = []
	var seen_aliases: Dictionary = {}
	for raw_alias in tag_aliases:
		var alias := GMGameplayTag.normalize(str(raw_alias))
		var alias_validation := GMGameplayTag.validate(alias, true)
		if not alias_validation.ok:
			errors.append(alias_validation)
			return alias_validation
		if alias == canonical or definitions.has(alias) or aliases.has(alias) or seen_aliases.has(alias):
			var alias_duplicate := {"ok": false, "code": "tag.alias_duplicate", "reason_zh": "GameplayTag 别名重复定义：%s" % alias}
			errors.append(alias_duplicate)
			return alias_duplicate
		seen_aliases[alias] = true
		candidate_aliases.append(alias)
	candidate_aliases.sort()

	var candidate_definition := {"tag": canonical, "platform_owned": platform_owned, "aliases": candidate_aliases.duplicate(), "group": canonical.get_slice(".", 0)}
	for alias in candidate_aliases:
		aliases[alias] = canonical
	definitions[canonical] = candidate_definition
	return {"ok": true, "tag": canonical}

func create_tag(tag_value: String, group: String = "", tag_aliases: Array = [], platform_owned: bool = false) -> Dictionary:
	var result := register(tag_value, tag_aliases, platform_owned)
	if not result.ok:
		return result
	var canonical := str(result.get("tag", ""))
	if definitions.has(canonical) and not group.strip_edges().is_empty():
		definitions[canonical]["group"] = group.strip_edges()
	return {"ok": true, "tag": canonical, "group": str(definitions[canonical].get("group", ""))}

func register_usage(tag_value: String, path: String, usage_label: String = "") -> Dictionary:
	var resolved := resolve(tag_value)
	if not resolved.ok:
		return resolved
	var canonical := str(resolved.get("canonical", ""))
	var entries: Array = _usage_index.get(canonical, [])
	var entry := {"path": path, "label": usage_label}
	if not entries.has(entry):
		entries.append(entry)
	_usage_index[canonical] = entries
	return {"ok": true, "tag": canonical, "usage": entry}

func search(query: String = "", group: String = "") -> Array[Dictionary]:
	var needle := GMGameplayTag.normalize(query)
	var group_filter := group.strip_edges()
	var result: Array[Dictionary] = []
	for tag_value in definitions.keys():
		var definition: Dictionary = definitions[tag_value]
		if not group_filter.is_empty() and str(definition.get("group", "")) != group_filter:
			continue
		var aliases_for_tag: Array = definition.get("aliases", [])
		var matches := needle.is_empty() or str(tag_value).contains(needle)
		if not matches:
			for alias_value in aliases_for_tag:
				if str(alias_value).contains(needle):
					matches = true
					break
		if matches:
			var row := definition.duplicate(true)
			row["usage"] = usage_locations(str(tag_value))
			result.append(row)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("tag", "")) < str(b.get("tag", ""))
	)
	return result

func groups() -> Array[String]:
	var values: Array[String] = []
	for definition in definitions.values():
		var group_value := str(definition.get("group", ""))
		if not group_value.is_empty() and not values.has(group_value):
			values.append(group_value)
	values.sort()
	return values

func usage_locations(tag_value: String) -> Array:
	var resolved := resolve(tag_value)
	if not resolved.ok:
		return []
	return ( _usage_index.get(str(resolved.get("canonical", "")), []) as Array).duplicate(true)

func register_alias(alias_value: String, target_value: String) -> Dictionary:
	var alias := GMGameplayTag.normalize(alias_value)
	var target := GMGameplayTag.normalize(target_value)
	var alias_validation := GMGameplayTag.validate(alias, true)
	if not alias_validation.ok:
		return alias_validation
	if not definitions.has(target):
		var missing := {"ok": false, "code": "tag.alias_target_unknown", "reason_zh": "GameplayTag 别名目标未知：%s" % target}
		errors.append(missing)
		return missing
	if definitions.has(alias) or aliases.has(alias):
		var duplicate := {"ok": false, "code": "tag.alias_duplicate", "reason_zh": "GameplayTag 别名重复定义：%s" % alias}
		errors.append(duplicate)
		return duplicate
	aliases[alias] = target
	definitions[target].aliases.append(alias)
	var cycle := validate_aliases()
	if not cycle.ok:
		aliases.erase(alias)
		definitions[target].aliases.erase(alias)
		errors.append(cycle)
		return cycle
	return {"ok": true, "alias": alias, "target": target}

func resolve(tag_value: String) -> Dictionary:
	var input := GMGameplayTag.normalize(tag_value)
	if definitions.has(input):
		return {"ok": true, "input": input, "canonical": input, "definition": definitions[input]}
	if not aliases.has(input):
		return {"ok": false, "code": "tag.unknown", "reason_zh": "未知 GameplayTag：%s；请先注册标签。" % input}
	var visited: Array[String] = []
	var current := input
	while aliases.has(current):
		if visited.has(current):
			return {"ok": false, "code": "tag.alias_cycle", "reason_zh": "GameplayTag 别名存在循环：%s" % " -> ".join(visited + [current])}
		visited.append(current)
		current = str(aliases[current])
	if not definitions.has(current):
		return {"ok": false, "code": "tag.alias_target_unknown", "reason_zh": "GameplayTag 别名目标未知：%s" % current}
	return {"ok": true, "input": input, "canonical": current, "definition": definitions[current], "alias_chain": visited}

func validate_aliases() -> Dictionary:
	for alias_value in aliases:
		var visited: Array[String] = []
		var current := str(alias_value)
		while aliases.has(current):
			if visited.has(current):
				return {"ok": false, "code": "tag.alias_cycle", "reason_zh": "GameplayTag 别名存在循环：%s" % " -> ".join(visited + [current])}
			visited.append(current)
			current = str(aliases[current])
		if not definitions.has(current):
			return {"ok": false, "code": "tag.alias_target_unknown", "reason_zh": "GameplayTag 别名目标未知：%s" % current}
	return {"ok": true}

func is_known(tag_value: String) -> bool:
	return bool(resolve(tag_value).get("ok", false))

func summary() -> Dictionary:
	return {"definitions": definitions.duplicate(true), "aliases": aliases.duplicate(true), "errors": errors.duplicate(true), "groups": groups(), "usage_index": _usage_index.duplicate(true)}
