extends Node

## Task04-only release sentinel. This scene is intentionally self-contained so
## the exported artifact exercises the repaired GAS paths instead of merely
## proving that an empty project can boot.

const TAG_REGISTRY_SCRIPT = preload("res://gm_runtime/gas/gm_gameplay_tag_registry.gd")
const HOST_SCRIPT = preload("res://gm_runtime/gas/gm_ability_system_host.gd")
const DEFINITION_SCRIPT = preload("res://gm_runtime/gas/gm_ability_definition.gd")
const BUNDLE_SCRIPT = preload("res://gm_runtime/gas/gm_ability_bundle.gd")

func _ready() -> void:
	var failures: Array[String] = []
	var registry: GMGameplayTagRegistry = TAG_REGISTRY_SCRIPT.new()
	var tag_result: Dictionary = registry.register(
		"release.task04.registry",
		["release.task04.alias.z", "release.task04.alias.a"]
	)
	var alias_result: Dictionary = registry.resolve("release.task04.alias.a")
	_check(bool(tag_result.get("ok", false)), "tag_composite_register", failures)
	_check(bool(alias_result.get("ok", false)), "tag_alias_resolution", failures)
	_check(str(alias_result.get("canonical", "")) == "release.task04.registry", "tag_alias_canonical", failures)
	_check(registry.definitions.size() == 1 and registry.aliases.size() == 2, "tag_registry_counts", failures)

	var entity := Node.new()
	var runtime_context := Node.new()
	var host: GMAbilitySystemHost = HOST_SCRIPT.new()
	var mount_result: Dictionary = host.mount(entity, runtime_context)
	_check(bool(mount_result.get("ok", false)), "host_mount", failures)

	var direct_definition: GMAbilityDefinition = _new_definition("release.task04.direct", "release.task04.direct")
	var direct_grant: Dictionary = host.grant_ability(direct_definition, "release.task04.sentinel", 2, {"sentinel": true})
	_check(bool(direct_grant.get("ok", false)), "host_legal_grant", failures)
	_check(host.definitions.get(direct_definition.ability_id, null) == direct_definition, "host_definition_published", failures)
	_check(host.specs.has(direct_definition.ability_id), "host_spec_published", failures)
	var direct_spec: GMAbilitySpec = host.specs.get(direct_definition.ability_id, null)
	_check(direct_spec != null and direct_spec.source_records.has("release.task04.sentinel"), "host_source_published", failures)

	var bundle_alpha: GMAbilityDefinition = _new_definition("release.task04.bundle.alpha", "release.task04.bundle.alpha")
	var bundle_beta: GMAbilityDefinition = _new_definition("release.task04.bundle.beta", "release.task04.bundle.beta")
	var bundle: GMAbilityBundle = BUNDLE_SCRIPT.new()
	bundle.bundle_id = "release.task04.bundle"
	# Deliberately add the entries in reverse order; grant_to must canonicalize
	# the commit while preserving a deterministic successful batch.
	bundle.add_ability(bundle_beta.ability_id, 1, {"batch": "release"})
	bundle.add_ability(bundle_alpha.ability_id, 1, {"batch": "release"})
	var bundle_definitions: Dictionary = {
		bundle_alpha.ability_id: bundle_alpha,
		bundle_beta.ability_id: bundle_beta,
	}
	var bundle_result: Dictionary = bundle.grant_to(host, "release.task04.bundle.sentinel", bundle_definitions)
	_check(bool(bundle_result.get("ok", false)), "bundle_success", failures)
	_check(int(bundle_result.get("committed_count", 0)) == 2, "bundle_commit_count", failures)
	_check(host.has_ability(bundle_alpha.ability_id) and host.has_ability(bundle_beta.ability_id), "bundle_specs_published", failures)
	var alpha_spec: GMAbilitySpec = host.specs.get(bundle_alpha.ability_id, null)
	var beta_spec: GMAbilitySpec = host.specs.get(bundle_beta.ability_id, null)
	_check(alpha_spec != null and beta_spec != null, "bundle_spec_objects", failures)
	_check(alpha_spec.source_records.has("release.task04.bundle.sentinel") and beta_spec.source_records.has("release.task04.bundle.sentinel"), "bundle_sources_published", failures)

	var unmount_result: Dictionary = host.unmount()
	var entity_key := str(entity.get_instance_id())
	var terminal_ok := bool(unmount_result.get("ok", false)) and not host.mounted and not GMAbilitySystemHost.mounted_entities.has(entity_key)
	_check(terminal_ok, "host_release_terminal_state", failures)

	var pck_entries: Array[String] = []
	_collect_pck_entries("res://", pck_entries)
	pck_entries.sort()
	var required_pck_bases := [
		"gm_runtime/gas/gm_gameplay_tag_registry",
		"gm_runtime/gas/gm_ability_spec",
		"gm_runtime/gas/gm_ability_system_host",
		"gm_runtime/gas/gm_ability_bundle",
		"gm_runtime/gas/gm_task04_release_entry",
	]
	var required_pck_present: Array[String] = []
	for required_base in required_pck_bases:
		if _pck_entry_has_base(pck_entries, required_base): required_pck_present.append(required_base)
	var forbidden_pck_entries: Array[String] = []
	for raw_entry in pck_entries:
		var normalized_entry := str(raw_entry).trim_prefix("res://").replace("\\", "/").to_lower()
		for forbidden_prefix in ["addons/gm_editor/", "tests/", "reports/", "docs/", "dev_samples/"]:
			if normalized_entry.begins_with(forbidden_prefix):
				forbidden_pck_entries.append(str(raw_entry))
				break
	var pck_ok := not pck_entries.is_empty() and required_pck_present.size() == required_pck_bases.size() and forbidden_pck_entries.is_empty()
	_check(pck_ok, "pck_runtime_enumeration", failures)
	print("GM_TASK04_RELEASE_PCK_ENUM_%s %s" % ["OK" if pck_ok else "FAIL", JSON.stringify({
		"source": "runtime DirAccess res:// enumeration from embedded PCK",
		"entry_count": pck_entries.size(),
		"entries": pck_entries,
		"required_bases": required_pck_bases,
		"required_present": required_pck_present,
		"forbidden_entries": forbidden_pck_entries,
	})])

	var payload := {
		"schema_version": "gm.task04.release_runtime.v1",
		"tag_registry": {
			"result": tag_result,
			"alias_resolution": alias_result,
			"definition_count": registry.definitions.size(),
			"alias_count": registry.aliases.size(),
		},
		"host_grant": {
			"result": direct_grant,
			"definition_ids": host.definitions.keys(),
			"spec_ids": host.specs.keys(),
			"source_ids": Array(direct_spec.sources()) if direct_spec != null else [],
		},
		"bundle": {
			"result": bundle_result,
			"entry_order": [bundle_beta.ability_id, bundle_alpha.ability_id],
			"committed_count": int(bundle_result.get("committed_count", 0)),
		},
		"release": {
			"unmount_result": unmount_result,
			"mounted": host.mounted,
			"mounted_entity_present": GMAbilitySystemHost.mounted_entities.has(entity_key),
		},
		"pck": {
			"entry_count": pck_entries.size(),
			"required_present": required_pck_present,
			"forbidden_entries": forbidden_pck_entries,
		},
		"failures": failures,
	}
	var marker := "OK" if failures.is_empty() else "FAIL"
	print("GM_TASK04_RELEASE_SENTINEL_%s %s" % [marker, JSON.stringify(payload)])
	if is_instance_valid(entity): entity.free()
	if is_instance_valid(runtime_context): runtime_context.free()
	get_tree().quit(0 if failures.is_empty() else 1)

func _new_definition(ability_id: String, ability_tag: String) -> GMAbilityDefinition:
	var definition: GMAbilityDefinition = DEFINITION_SCRIPT.new()
	definition.ability_id = ability_id
	definition.display_name_zh = ability_id
	definition.ability_tags = PackedStringArray([ability_tag])
	return definition

func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(label)

func _collect_pck_entries(base_path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(base_path)
	if directory == null: return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty(): break
		if name == "." or name == "..": continue
		var child_path := base_path.path_join(name)
		if directory.current_is_dir():
			_collect_pck_entries(child_path, output)
		else:
			output.append(child_path.trim_prefix("res://"))
	directory.list_dir_end()

func _pck_entry_has_base(entries: Array[String], required_base: String) -> bool:
	for raw_entry in entries:
		var normalized := str(raw_entry).trim_prefix("res://").replace("\\", "/").to_lower()
		while normalized.ends_with(".remap"): normalized = normalized.trim_suffix(".remap")
		if normalized.ends_with(".gdc"): normalized = normalized.trim_suffix(".gdc")
		if normalized == required_base.to_lower(): return true
	return false
