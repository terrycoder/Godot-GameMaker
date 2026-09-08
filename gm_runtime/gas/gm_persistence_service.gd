class_name GMPersistenceService
extends RefCounted

## GAS 运行态持久化。
## 只写 JSON 数据，不写协程、SceneTreeTimer 或 Object 实例；重开进程后由注册好的
## Definition/Resolver 重新建出运行时状态。缺内容、删效果和版本变化都显式报迁移错误。

const SCHEMA_VERSION := "gm.gas.persistence.v2"

func save_host(host: GMAbilitySystemHost, path: String, content_version: String = "gm.content.v1") -> Dictionary:
	if host == null: return _failure("persistence.host_missing", "保存 GAS 运行态缺少能力宿主。")
	if path.strip_edges().is_empty(): return _failure("persistence.path_missing", "GAS 运行态保存路径不能为空。")
	var preparation := host.prepare_for_save()
	if not preparation.ok: return preparation
	var data := _snapshot_host(host, content_version, preparation)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return _failure("persistence.open_failed", "无法打开 GAS 运行态保存文件：%s。" % path, {"path": path, "error": FileAccess.get_open_error()})
	file.store_string(JSON.stringify(data) + "\n")
	file.close()
	return {"ok": true, "path": path, "schema_version": SCHEMA_VERSION, "content_version": content_version, "bytes": FileAccess.get_file_as_bytes(path).size(), "snapshot": data, "preparation": preparation}

func load_host(host: GMAbilitySystemHost, path: String, expected_content_version: String = "gm.content.v1", migration_table: Dictionary = {}) -> Dictionary:
	if host == null: return _failure("persistence.host_missing", "加载 GAS 运行态缺少能力宿主。")
	if not FileAccess.file_exists(path): return _failure("persistence.file_missing", "GAS 运行态保存文件不存在：%s。" % path, {"path": path})
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary: return _failure("persistence.json_invalid", "GAS 运行态保存文件不是有效 JSON。", {"path": path})
	var data: Dictionary = parsed
	if str(data.get("schema_version", "")) not in [SCHEMA_VERSION, "gm.gas.persistence.v1"]:
		return _failure("persistence.schema_invalid", "GAS 运行态存档版本不受支持。", {"schema_version": data.get("schema_version", "")})
	var saved_content := str(data.get("content_version", ""))
	if saved_content != expected_content_version and not migration_table.has(saved_content):
		return _migration_error("persistence.content_version_mismatch", "内容版本发生变化，缺少显式迁移规则：%s → %s。" % [saved_content, expected_content_version], {"from": saved_content, "to": expected_content_version})
	var validation := _validate_dependencies(host, data)
	if not validation.ok: return validation
	var staged_result := _stage_host_restore(host, data, migration_table)
	if not staged_result.ok: return staged_result
	var staged: GMAbilitySystemHost = staged_result.host
	# All fallible work has completed in isolation.  The assignments below are
	# the sole commit point and cannot expose a partially restored live Host.
	host.attribute_set = staged.attribute_set
	host.tags = staged.tags
	host.tag_container = staged.tags
	host.scheduler = staged.scheduler
	host.specs = staged.specs
	host.active_effects = staged.active_effects
	host.effect_runtime = staged.effect_runtime
	host.effect_runtime.host = host
	var live_store := _inventory_store(host)
	var staged_store := _inventory_store(staged)
	if live_store != null and staged_store != null:
		host.inventory_resolver.set("inventory_store", staged_store)
		if host.inventory_resolver.get("plans") is Dictionary: host.inventory_resolver.set("plans", {})
	var tag_callback := Callable(host, "_on_tag_event")
	if not host.tags.gameplay_event.is_connected(tag_callback): host.tags.gameplay_event.connect(tag_callback)
	return {"ok": true, "path": path, "schema_version": SCHEMA_VERSION, "content_version": expected_content_version, "attributes": staged_result.attributes, "tags": staged_result.tags, "scheduler": staged_result.scheduler, "inventory": staged_result.inventory, "abilities": staged_result.abilities, "effects": staged_result.effects, "reopened": true, "atomic_two_phase": true, "no_coroutines_serialized": true}

func _stage_host_restore(host: GMAbilitySystemHost, data: Dictionary, migration_table: Dictionary) -> Dictionary:
	var staged := GMAbilitySystemHost.new()
	staged.entity = host.entity
	staged.runtime_context = host.runtime_context
	staged.registry = host.registry
	staged.tags = GMGameplayTagContainer.new(host.registry)
	staged.tag_container = staged.tags
	staged.attribute_set = GMAttributeSet.new()
	var scheduler_script: Script = host.scheduler.get_script() if host.scheduler != null else null
	staged.scheduler = scheduler_script.new() if scheduler_script != null else GMAbilityScheduler.new()
	staged.definitions = host.definitions.duplicate()
	staged.effect_definitions = host.effect_definitions.duplicate()
	staged.effect_runtime = GMEffectRuntime.new(staged)
	var attr_state: Dictionary = data.get("attributes", {}) if data.get("attributes", {}) is Dictionary else {}
	var attr_result := staged.attribute_set.restore_state(attr_state)
	if not attr_result.ok: return attr_result
	var tag_state: Dictionary = data.get("tags", {}) if data.get("tags", {}) is Dictionary else {}
	var tag_result := staged.tags.restore_snapshot(tag_state)
	if not tag_result.ok: return tag_result
	var scheduler_state: Dictionary = data.get("scheduler", {}) if data.get("scheduler", {}) is Dictionary else {}
	var scheduler_result := staged.scheduler.restore_snapshot(scheduler_state)
	if not scheduler_result.ok: return scheduler_result
	var inventory_result := {"ok": true, "skipped": true}
	var inventory_state: Dictionary = data.get("inventory", {}) if data.get("inventory", {}) is Dictionary else {}
	var live_store := _inventory_store(host)
	if live_store != null and not inventory_state.is_empty():
		var store_script: Script = live_store.get_script()
		var staged_store: Object = store_script.new() if store_script != null else GMInventoryStore.new()
		if staged_store == null or not staged_store.has_method("restore_snapshot"): return _failure("persistence.inventory_stage_unavailable", "库存Store不支持隔离恢复验证。")
		inventory_result = staged_store.restore_snapshot(inventory_state)
		if not inventory_result.ok: return inventory_result
		var live_flags: Variant = host.inventory_resolver.get("feature_flags")
		staged.inventory_resolver = GMInventoryResolver.new(staged_store, live_flags if live_flags is GMInventoryFeatureFlags else null)
	var specs_result := _restore_specs(staged, data.get("abilities", []))
	if not specs_result.ok: return specs_result
	var effects_state: Dictionary = data.get("effects", {}) if data.get("effects", {}) is Dictionary else {}
	var effect_result := staged.effect_runtime.restore_snapshot(effects_state, migration_table)
	if not effect_result.ok: return effect_result
	return {"ok": true, "host": staged, "attributes": attr_result, "tags": tag_result, "scheduler": scheduler_result, "inventory": inventory_result, "abilities": specs_result, "effects": effect_result}

func _snapshot_host(host: GMAbilitySystemHost, content_version: String, preparation: Dictionary) -> Dictionary:
	var ability_rows: Array[Dictionary] = []
	var definition_rows: Dictionary = {}
	for raw_id in host.specs:
		var id := str(raw_id)
		var spec: GMAbilitySpec = host.specs[raw_id]
		if spec == null: continue
		ability_rows.append(spec.to_summary())
		var definition: GMAbilityDefinition = host.definitions.get(id, null)
		if definition != null: definition_rows[id] = {"ability_id": id, "content_version": definition.content_version, "definition": definition.to_summary()}
	ability_rows.sort_custom(func(left: Dictionary, right: Dictionary): return str(left.get("ability_id", "")) < str(right.get("ability_id", "")))
	var inventory_state := {}
	var store := _inventory_store(host)
	if store != null and store.has_method("snapshot"): inventory_state = store.snapshot()
	return {
		"schema_version": SCHEMA_VERSION,
		"content_version": content_version,
		"entity_id": GMEffectSpec.stable_identity(host.entity),
		"saved_at_usec": Time.get_ticks_usec(),
		"attributes": host.attribute_set.snapshot_state(),
		"tags": host.tags.snapshot(),
		"scheduler": host.scheduler.snapshot(),
		"effects": host.effect_runtime.snapshot(false) if host.effect_runtime != null else {"schema_version": "gm.effect_runtime.v2", "effects": []},
		"abilities": ability_rows,
		"ability_definitions": definition_rows,
		"inventory": inventory_state,
		"fact_pipeline": {"fact_count": host.fact_event_store.get_record_count() if host.fact_event_store != null else 0, "change_count": host.change_record_store.get_record_count() if host.change_record_store != null else 0},
		"preparation": preparation.duplicate(true),
		"no_coroutines_serialized": true,
	}

func _validate_dependencies(host: GMAbilitySystemHost, data: Dictionary) -> Dictionary:
	var definition_rows: Variant = data.get("ability_definitions", {})
	if not definition_rows is Dictionary: return _failure("persistence.ability_definitions_invalid", "能力定义存档不是对象。")
	for raw_id in definition_rows:
		var id := str(raw_id)
		var saved: Dictionary = definition_rows[raw_id] if definition_rows[raw_id] is Dictionary else {}
		var definition: GMAbilityDefinition = host.definitions.get(id, null)
		if definition == null:
			return _migration_error("persistence.ability_definition_missing", "存档引用的能力定义已缺失：%s。" % id, {"ability_id": id})
		var saved_version := str(saved.get("content_version", ""))
		if saved_version != definition.content_version:
			return _migration_error("persistence.ability_content_version_mismatch", "能力内容版本发生变化，缺少显式迁移规则：%s（%s→%s）。" % [id, saved_version, definition.content_version], {"ability_id": id, "from": saved_version, "to": definition.content_version})
	return {"ok": true}

func _restore_specs(host: GMAbilitySystemHost, value: Variant) -> Dictionary:
	if not value is Array: return _failure("persistence.abilities_invalid", "能力 Spec 存档不是数组。")
	var next: Dictionary = {}
	for raw in value:
		if not raw is Dictionary: return _failure("persistence.ability_record_invalid", "能力 Spec 存档包含非对象记录。")
		var id := str(raw.get("ability_id", ""))
		var definition: GMAbilityDefinition = host.definitions.get(id, null)
		if definition == null: return _migration_error("persistence.ability_definition_missing", "恢复能力 Spec 时定义缺失：%s。" % id, {"ability_id": id})
		var spec := GMAbilitySpec.new(definition)
		var records: Variant = raw.get("source_records", {})
		if not records is Dictionary: return _failure("persistence.ability_sources_invalid", "能力 Spec 来源记录格式无效：%s。" % id)
		spec.source_records = records.duplicate(true)
		var dynamic_tags: Variant = raw.get("dynamic_tags", {})
		if dynamic_tags is Dictionary:
			var tag_result := spec.dynamic_tags.restore_snapshot(dynamic_tags)
			if not tag_result.ok: return tag_result
		next[id] = spec
	host.specs = next
	return {"ok": true, "restored": next.size(), "ability_ids": next.keys()}

func _inventory_store(host: GMAbilitySystemHost) -> Object:
	if host.inventory_resolver == null: return null
	var value: Variant = host.inventory_resolver.get("inventory_store")
	return value if value is Object else null

func _migration_error(code: String, reason_zh: String, details: Dictionary) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "migration_required": true, "details": details.duplicate(true)}

func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	result.merge(details, true)
	return result
