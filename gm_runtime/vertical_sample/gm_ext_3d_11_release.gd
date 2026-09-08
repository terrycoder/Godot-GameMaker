class_name GMExt3D11Release
extends GMNeutralVerticalSample

const RELEASE_PROFILE_PATH := "res://gm_runtime/vertical_sample/gm_ext_3d_11_profile.tres"
const CONTRACT := preload("res://gm_runtime/vertical_sample/gm_planar3d_release_contract.gd")

var release_profile: GMPlanar3DReleaseProfile

func _should_restore_on_start() -> bool:
	var args := OS.get_cmdline_user_args()
	for command in ["--gm-ext-3d-11-contract", "--gm-ext-3d-11-save", "--gm-ext-3d-11-restore", "--gm-ext-3d-11-atomic-negative", "--gm-ext-3d-11-list-pack"]:
		if args.has(command): return false
	return super._should_restore_on_start()

func _ready() -> void:
	OS.set_environment("GM_MODULE_INDEX_PATH", "res://gm_runtime/manifests/gm_ext_3d_11_manifest_index.tres")
	if release_profile == null:
		release_profile = load(RELEASE_PROFILE_PATH) as GMPlanar3DReleaseProfile
	if release_profile != null:
		sample_profile = release_profile
	super._ready()
	if not _startup_error.is_empty() or not vertical_error.is_empty():
		if OS.get_cmdline_user_args().has("--gm-ext-3d-11-contract") or OS.get_cmdline_user_args().has("--gm-ext-3d-11-save") or OS.get_cmdline_user_args().has("--gm-ext-3d-11-restore") or OS.get_cmdline_user_args().has("--gm-ext-3d-11-atomic-negative") or OS.get_cmdline_user_args().has("--gm-ext-3d-11-list-pack"):
			print("GM_EXT_3D_11_STARTUP_ERROR " + JSON.stringify({"startup": _startup_error, "vertical": vertical_error}))
			get_tree().quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.has("--gm-ext-3d-11-contract"): call_deferred("_run_ext11_contract")
	elif args.has("--gm-ext-3d-11-save"): call_deferred("_run_ext11_save")
	elif args.has("--gm-ext-3d-11-restore"): call_deferred("_run_ext11_restore")
	elif args.has("--gm-ext-3d-11-atomic-negative"): call_deferred("_run_ext11_atomic_negative")
	elif args.has("--gm-ext-3d-11-list-pack"): call_deferred("_run_ext11_pack_inventory")

func _capture_p25_contributors() -> Dictionary:
	var captured: Dictionary = super._capture_p25_contributors()
	if not captured.ok: return captured
	var payload := CONTRACT.build_save_record(sample_profile)
	var checked := CONTRACT.validate_save_payload(payload)
	if not checked.ok: return checked
	var written: Dictionary = player_shell_store.put("ext3d11_release", payload)
	if not written.ok: return {"ok": false, "code": "release.save_record_commit_failed", "reason_zh": "EXT11保存增量未通过既有PlayerShell Store原子提交。", "details": written}
	return {"ok": true, "store_id": P25_STORE_ID, "keys": player_shell_store.keys(), "record_count": player_shell_store.keys().size(), "release_record": checked}

func _prepare_p25_contributors(world_snapshot: Dictionary, staged_stores: Dictionary) -> Dictionary:
	# Keep the ordinary P25/EXT10 restore participant in the shared PlayerShell
	# baseline.  EXT11 validates its optional record only in this enabled release
	# participant, while all values are still detached and before any swap.
	var prepared: Dictionary = super._prepare_p25_contributors(world_snapshot, staged_stores)
	if not prepared.ok:
		return prepared
	var staged_shell: Variant = staged_stores.get(P25_STORE_ID, null)
	if not staged_shell is GMStore:
		return prepared
	var ext3d11_check := _validate_ext3d11_restore_record(staged_shell)
	if not ext3d11_check.ok:
		return ext3d11_check
	var prepared_values: Dictionary = prepared.get("prepared", {}) if prepared.get("prepared", {}) is Dictionary else {}
	prepared_values["ext3d11"] = ext3d11_check
	prepared["prepared"] = prepared_values
	return prepared

func _validate_ext3d11_restore_record(staged_shell: GMStore) -> Dictionary:
	if not staged_shell.has("ext3d11_release"):
		return {"ok": true, "present": false, "validated": false}
	var checked: Dictionary = CONTRACT.validate_save_payload(staged_shell.read("ext3d11_release"))
	if not checked.ok:
		return {
			"ok": false,
			"code": "save.ext3d11_record_invalid",
			"reason_zh": "EXT11增量记录在原子恢复准备阶段未通过稳定字段校验。",
			"failure_state_unchanged": true,
			"details": {
				"stable_code": str(checked.get("code", "release.save_payload_invalid")),
				"validator": checked
			}
		}
	return {"ok": true, "present": true, "validated": true, "validator": checked}

func _run_ext11_contract() -> void:
	await get_tree().process_frame
	var report := {"schema": "gm.ext3d11.contract_summary.v1", "event": "GM_EXT_3D_11_CONTRACT_SENTINEL", "ok": true, "checks": []}
	_check(report, "vertical_sample_ready", vertical_ready and process_service != null and npc_rows.size() == sample_profile.actor_specs.size())
	var profile_check := CONTRACT.validate_profile(sample_profile)
	_check(report, "release_profile_valid", bool(profile_check.get("ok", false)))
	var freeze_enabled := CONTRACT.freeze_manifest(sample_profile, true)
	_check(report, "enabled_freeze_manifest", bool(freeze_enabled.get("ok", false)) and freeze_enabled.get("module_versions", {}).size() > 0)
	var export_enabled := CONTRACT.export_contract(sample_profile, true)
	_check(report, "enabled_export_plan", bool(export_enabled.get("ok", false)) and export_enabled.get("has_runtime_3d", false))
	var export_2d := CONTRACT.export_contract(sample_profile, false)
	_check(report, "disabled_2d_export_crop", bool(export_2d.get("ok", false)) and Array(export_2d.get("leaks", [])).is_empty())
	var save_drill := CONTRACT.save_restore_drill(sample_profile)
	_check(report, "save_schema_and_atomic_recovery", bool(save_drill.get("ok", false)) and bool(save_drill.get("single_save_root", false)))
	var cache_drill := CONTRACT.visual_cache_recovery()
	_check(report, "visual_recipe_cache_rebuild", bool(cache_drill.get("ok", false)) and bool(cache_drill.get("recipe_authority", false)))
	var performance := CONTRACT.performance_budget_matrix(sample_profile, self)
	var performance_rows: Array = performance.get("rows", []) if performance.get("rows", []) is Array else []
	var performance_60: Dictionary = performance_rows[2] if performance_rows.size() >= 3 and performance_rows[2] is Dictionary else {}
	_check(report, "performance_budget_10_30_60", bool(performance.get("ok", false)) and performance_rows.size() == 3 and int(performance_60.get("deferred_updates", 0)) > 0 and performance_60.has("manager_snapshot"))
	var forbidden := CONTRACT.forbidden_area_scan()
	_check(report, "forbidden_area_clean", bool(forbidden.get("ok", false)))
	var negative := CONTRACT.missing_dependency_negative()
	_check(report, "negative_missing_dependency_and_profile", bool(negative.get("ok", false)))
	var caw_gate := CONTRACT.caw_gate_checklist(sample_profile)
	_check(report, "incremental_gate_stays_downstream", not bool(caw_gate.get("eligible_for_copy_ready", true)))
	var reopened := save_and_reopen_projection()
	_check(report, "actual_player_shell_save_reopen", bool(reopened.get("ok", false)) and player_shell_store.has("ext3d11_release"))
	var release_record: Dictionary = player_shell_store.read("ext3d11_release")
	_check(report, "actual_release_record_valid", bool(CONTRACT.validate_save_payload(release_record).get("ok", false)))
	report["profile"] = profile_check
	report["freeze_manifest"] = freeze_enabled
	report["enabled_export"] = export_enabled
	report["disabled_2d_export"] = export_2d
	report["save_restore"] = save_drill
	report["cache_restore"] = cache_drill
	report["performance"] = performance
	report["forbidden_area_scan"] = forbidden
	report["negative_cases"] = negative
	report["incremental_gate"] = caw_gate
	report["actual_reopen"] = reopened
	report["single_save_root"] = true
	report["second_authorities"] = false
	var evidence := _write_evidence(report)
	report["evidence_write"] = evidence
	print("GM_EXT_3D_11_CONTRACT_RESULT " + JSON.stringify({"ok": bool(report.get("ok", false)) and bool(evidence.get("ok", false)), "checks": report.get("checks", []), "evidence": evidence}))
	get_tree().quit(0 if bool(report.ok) and bool(evidence.get("ok", false)) else 1)

func _run_ext11_atomic_negative() -> void:
	await get_tree().process_frame
	var captured := _capture_p25_contributors()
	var report := {"schema": "gm.ext3d11.atomic_restore_negative.v1", "ok": false}
	if not captured.ok:
		report["capture"] = captured
	else:
		var before_world: Dictionary = simulation_world.save_snapshot()
		var before_store: Dictionary = player_shell_store.snapshot()
		var before_projection := {"task": task_projection(), "domain": simulation_world.call("_receipt_state_projection")}
		var before_shell_ref = player_shell_store
		var before_task_ref = task_service.store
		var before_world_summary := _atomic_world_summary(before_world)
		var before_store_summary := _atomic_store_summary(before_store)
		var before_projection_summary := _atomic_projection_bundle_summary(before_projection)
		var candidate := before_world.duplicate(true)
		var stores: Dictionary = candidate.get("stores", {})
		var shell_snapshot: Dictionary = stores.get(P25_STORE_ID, {})
		var records: Dictionary = shell_snapshot.get("records", {})
		var corrupt_record: Dictionary = records.get("ext3d11_release", {}).duplicate(true)
		corrupt_record.erase("surface_id")
		records["ext3d11_release"] = corrupt_record
		shell_snapshot["records"] = records
		stores[P25_STORE_ID] = shell_snapshot
		candidate["stores"] = stores
		var rejected: Dictionary = simulation_world.load_snapshot(candidate)
		var after_world: Dictionary = simulation_world.save_snapshot()
		var after_store: Dictionary = player_shell_store.snapshot()
		var after_projection := {"task": task_projection(), "domain": simulation_world.call("_receipt_state_projection")}
		var after_world_summary := _atomic_world_summary(after_world)
		var after_store_summary := _atomic_store_summary(after_store)
		var after_projection_summary := _atomic_projection_bundle_summary(after_projection)
		var details: Dictionary = rejected.get("details", {}) if rejected.get("details", {}) is Dictionary else {}
		var nested: Dictionary = details.get("details", {}) if details.get("details", {}) is Dictionary else {}
		var stable_code := str(nested.get("stable_code", details.get("stable_code", "")))
		report = {
			"ok": not bool(rejected.get("ok", false)) and str(rejected.get("code", "")) == "world.restore_contributor_invalid" and str(details.get("code", "")) == "save.ext3d11_record_invalid" and stable_code == "release.save_field_missing" and before_world_summary == after_world_summary and before_store_summary == after_store_summary and before_projection_summary == after_projection_summary and simulation_world.stores.get(P25_STORE_ID) == before_shell_ref and task_service.store == before_task_ref,
			"candidate_corrupt_field": "surface_id",
			"rejected": rejected,
			"nested_stable_code": stable_code,
			"before_world_summary": before_world_summary,
			"after_world_summary": after_world_summary,
			"world_digest_before": _atomic_summary_digest(before_world_summary),
			"world_digest_after": _atomic_summary_digest(after_world_summary),
			"world_unchanged": before_world_summary == after_world_summary,
			"before_store_summary": before_store_summary,
			"after_store_summary": after_store_summary,
			"store_digest_before": _atomic_summary_digest(before_store_summary),
			"store_digest_after": _atomic_summary_digest(after_store_summary),
			"store_unchanged": before_store_summary == after_store_summary,
			"before_projection_summary": before_projection_summary,
			"after_projection_summary": after_projection_summary,
			"projection_digest_before": _atomic_summary_digest(before_projection_summary),
			"projection_digest_after": _atomic_summary_digest(after_projection_summary),
			"projection_unchanged": before_projection_summary == after_projection_summary,
			"live_store_identity_before": _atomic_object_identity(before_shell_ref),
			"live_store_identity_after": _atomic_object_identity(simulation_world.stores.get(P25_STORE_ID)),
			"live_store_identity_unchanged": simulation_world.stores.get(P25_STORE_ID) == before_shell_ref,
			"task_store_identity_before": _atomic_object_identity(before_task_ref),
			"task_store_identity_after": _atomic_object_identity(task_service.store),
			"task_store_identity_unchanged": task_service.store == before_task_ref,
			"targeted_difference": {"path": "stores.%s.records.ext3d11_release.surface_id" % P25_STORE_ID, "candidate_operation": "erase", "expected_before": "present", "expected_candidate": "missing"},
			"capture_summary": {"ok": bool(captured.get("ok", false)), "store_id": str(captured.get("store_id", "")), "keys": _atomic_sorted_keys(captured.get("release_record", {}) if captured.get("release_record", {}) is Dictionary else {}), "record_count": int(captured.get("record_count", 0))},
			"single_save_root": true,
			"second_authorities": false
		}
	var evidence := _write_evidence(report)
	report["evidence_write"] = evidence
	print("GM_EXT_3D_11_ATOMIC_NEGATIVE_RESULT " + JSON.stringify({"ok": bool(report.get("ok", false)) and bool(evidence.get("ok", false)), "nested_stable_code": report.get("nested_stable_code", ""), "world_unchanged": report.get("world_unchanged", false), "store_unchanged": report.get("store_unchanged", false), "projection_unchanged": report.get("projection_unchanged", false), "evidence": evidence}))
	get_tree().quit(0 if bool(report.ok) and bool(evidence.get("ok", false)) else 1)

func _atomic_sorted_keys(value: Dictionary) -> Array:
	var result: Array = []
	for key in value.keys():
		result.append(str(key))
	result.sort()
	return result

func _atomic_collection_count(value: Variant) -> int:
	if value is Dictionary or value is Array:
		return value.size()
	return -1

func _atomic_object_identity(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Object:
		return "%s:%s" % [value.get_class(), str(value.get_instance_id())]
	return str(typeof(value))

func _atomic_world_summary(snapshot: Dictionary) -> Dictionary:
	var stores: Dictionary = snapshot.get("stores", {}) if snapshot.get("stores", {}) is Dictionary else {}
	var shell_snapshot: Dictionary = stores.get(P25_STORE_ID, {}) if stores.get(P25_STORE_ID, {}) is Dictionary else {}
	var records: Dictionary = shell_snapshot.get("records", {}) if shell_snapshot.get("records", {}) is Dictionary else {}
	var release_record: Dictionary = records.get("ext3d11_release", {}) if records.get("ext3d11_release", {}) is Dictionary else {}
	return {
		"snapshot_schema": str(snapshot.get("snapshot_schema", snapshot.get("schema", ""))),
		"world_id": str(snapshot.get("world_id", "")),
		"version": int(snapshot.get("version", -1)),
		"tick": int(snapshot.get("tick", -1)),
		"store_ids": _atomic_sorted_keys(stores),
		"store_count": stores.size(),
		"shell_record_keys": _atomic_sorted_keys(records),
		"release_record_fields": _atomic_sorted_keys(release_record),
		"entity_count": _atomic_collection_count(snapshot.get("entities", {}))
	}

func _atomic_store_summary(snapshot: Dictionary) -> Dictionary:
	var records: Dictionary = snapshot.get("records", {}) if snapshot.get("records", {}) is Dictionary else {}
	var release_record: Dictionary = records.get("ext3d11_release", {}) if records.get("ext3d11_release", {}) is Dictionary else {}
	return {
		"store_id": str(snapshot.get("store_id", "")),
		"schema": str(snapshot.get("schema", snapshot.get("store_schema", ""))),
		"record_keys": _atomic_sorted_keys(records),
		"record_count": records.size(),
		"release_record_fields": _atomic_sorted_keys(release_record)
	}

func _atomic_projection_summary(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"type": typeof(value), "digest": str(value)}
	var projection: Dictionary = value
	var collection_counts: Dictionary = {}
	for key in projection.keys():
		var count := _atomic_collection_count(projection.get(key))
		if count >= 0:
			collection_counts[str(key)] = count
	return {"type": "Dictionary", "keys": _atomic_sorted_keys(projection), "collection_counts": collection_counts}

func _atomic_projection_bundle_summary(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in value.keys():
		result[str(key)] = _atomic_projection_summary(value.get(key))
	return result

func _atomic_summary_digest(value: Dictionary) -> String:
	return JSON.stringify(value)

func _run_ext11_save() -> void:
	await get_tree().process_frame
	assign_task("gm.ext3d11.save.assign")
	interact_with_key("gm.ext3d11.save.interact")
	shell_configuration.save_path = sample_profile.save_path
	var saved := save_world_snapshot()
	var record: Dictionary = player_shell_store.read("ext3d11_release") if bool(saved.get("ok", false)) else {}
	var report := {"schema": "gm.ext3d11.save.v1", "ok": bool(saved.get("ok", false)) and bool(CONTRACT.validate_save_payload(record).get("ok", false)), "saved": saved, "record": record, "single_save_root": true}
	var evidence := _write_evidence(report)
	print("GM_EXT_3D_11_SAVE_RESULT " + JSON.stringify({"ok": bool(report.get("ok", false)) and bool(evidence.get("ok", false)), "path": sample_profile.save_path, "evidence": evidence}))
	get_tree().quit(0 if bool(report.ok) and bool(evidence.get("ok", false)) else 1)

func _run_ext11_restore() -> void:
	await get_tree().process_frame
	shell_configuration.save_path = sample_profile.save_path
	var restored := restore_world_snapshot()
	var record: Dictionary = player_shell_store.read("ext3d11_release") if bool(restored.get("ok", false)) else {}
	var report := {"schema": "gm.ext3d11.restore.v1", "ok": bool(restored.get("ok", false)) and bool(CONTRACT.validate_save_payload(record).get("ok", false)), "restored": restored, "record": record, "single_save_root": true, "no_second_root": not FileAccess.file_exists("user://gm_ext3d11_neutral_yard.save.json")}
	var evidence := _write_evidence(report)
	print("GM_EXT_3D_11_RESTORE_RESULT " + JSON.stringify({"ok": bool(report.get("ok", false)) and bool(evidence.get("ok", false)), "path": sample_profile.save_path, "evidence": evidence}))
	get_tree().quit(0 if bool(report.ok) and bool(evidence.get("ok", false)) else 1)

func _run_ext11_pack_inventory() -> void:
	await get_tree().process_frame
	var freeze := CONTRACT.freeze_manifest(sample_profile, true)
	var enabled := CONTRACT.export_contract(sample_profile, true)
	var disabled := CONTRACT.export_contract(sample_profile, false)
	var entry_scene := "res://gm_runtime/vertical_sample/gm_ext_3d_11_entry.tscn"
	var required := [entry_scene, "res://gm_runtime/vertical_sample/gm_ext_3d_11_profile.tres", "res://gm_runtime/vertical_sample/gm_ext_3d_11_budget_profile.tres", "res://gm_runtime/characters/visual_3d/gm_character_visual_3d_runtime.gd", "res://gm_runtime/presentation/planar3d/gm_visual_budget_manager_3d.gd"]
	var inventory := CONTRACT.pack_file_inventory(entry_scene, required, vertical_ready)
	var formal_product := false
	for argument in OS.get_cmdline_args():
		if str(argument) == "--main-pack": formal_product = true
	for argument in OS.get_cmdline_user_args():
		if str(argument) == "--gm-ext-3d-11-formal-product": formal_product = true
	var report := {"schema": "gm.ext3d11.pack_inventory.v2", "ok": bool(freeze.get("ok", false)) and bool(enabled.get("ok", false)) and bool(disabled.get("ok", false)) and bool(inventory.get("ok", false)), "enabled": enabled, "disabled_2d": disabled, "freeze": freeze, "inventory": inventory, "actual_pack": true, "entry_started": vertical_ready, "formal_paths_only": formal_product}
	var evidence := _write_evidence(report)
	print("GM_EXT_3D_11_PACK_RESULT " + JSON.stringify({"ok": bool(report.get("ok", false)) and bool(evidence.get("ok", false)), "evidence": evidence}))
	get_tree().quit(0 if bool(report.ok) and bool(evidence.get("ok", false)) else 1)

func _check(report: Dictionary, name: String, passed: bool) -> void:
	report.checks.append({"name": name, "passed": passed})
	if not passed: report.ok = false

func _write_evidence(value: Dictionary) -> Dictionary:
	var path := OS.get_environment("GM_EXT_3D_11_RUN_EVIDENCE").strip_edges()
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--gm-ext-3d-11-evidence="):
			path = str(argument).trim_prefix("--gm-ext-3d-11-evidence=")
	if path.is_empty(): return {"ok": true, "written": false}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return {"ok": false, "path": path, "code": "release.evidence_open_failed"}
	file.store_string(JSON.stringify(value, "  ") + "\n")
	file.close()
	return {"ok": true, "written": true, "path": path}
