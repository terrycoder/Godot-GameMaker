class_name GMExt3D11TwoDOnly
extends GMPlayerShell

const CONTRACT := preload("res://gm_runtime/vertical_sample/gm_planar2d_release_contract.gd")
const WORKFLOW := preload("res://gm_runtime/player_shell/gm_ext_3d_10_workflow.gd")

@export var sample_profile: GMNeutralVerticalSampleProfile
var workflow_result: Dictionary = {}
var release_ready := false

func _should_restore_on_start() -> bool:
	# DELIVERY_2D_ONLY normally disables the shared shell restore hook.
	# This formal EXT11 entry still uses that same PlayerShell/World
	# authority, but its Profile must finish registering all authored
	# Surfaces before SceneSession rebuild validation runs. _ready() below
	# schedules the same restore after that composition step.
	return false

func _ready() -> void:
	OS.set_environment("GM_MODULE_INDEX_PATH", "res://gm_runtime/manifests/gm_ext_3d_11_2d_manifest_index.tres")
	var selected := sample_profile
	if selected == null:
		selected = load("res://gm_runtime/vertical_sample/gm_ext_3d_11_profile.tres") as GMNeutralVerticalSampleProfile
	if selected == null:
		_startup_error = {"ok": false, "code": "release.2d_profile_missing", "reason_zh": "EXT11 2D-only入口缺少Profile。"}
		return
	sample_profile = selected
	var configured := sample_profile.apply_shell_configuration(shell_configuration)
	if not configured.ok:
		_startup_error = configured
		return
	super._ready()
	if not _startup_error.is_empty(): return
	var anchors := sample_profile.configure_semantic_anchors(semantic_registry, shell_configuration.tile_size)
	if not anchors.ok:
		_startup_error = anchors
		return
	workflow_result = WORKFLOW.new().execute(self, sample_profile, "2d")
	release_ready = bool(workflow_result.get("ok", false))
	var args := OS.get_cmdline_user_args()
	var restore_after_profile := true
	for command in ["--gm-ext-3d-11-formal-product", "--gm-ext-3d-11-2d-contract", "--gm-ext-3d-11-2d-only-check", "--gm-ext-3d-11-list-pack", "--p25-save-exit", "--p25-contract", "--p25-smoke", "--p25-2d-only-check"]:
		if args.has(command):
			restore_after_profile = false
			break
	if restore_after_profile or args.has("--p25-restore-check"):
		call_deferred("_restore_after_profile")
	if args.has("--p25-restore-check"):
		call_deferred("_run_restore_check_mode")
	if args.has("--gm-ext-3d-11-formal-product") or args.has("--gm-ext-3d-11-list-pack"):
		call_deferred("_run_2d_product")
	elif args.has("--gm-ext-3d-11-2d-contract") or args.has("--gm-ext-3d-11-2d-only-check"):
		call_deferred("_run_2d_contract")

func _schedule_command_mode() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--p25-save-exit"): call_deferred("_run_save_exit_mode")

func _restore_after_profile() -> void:
	if not _startup_error.is_empty(): return
	var restored := restore_world_snapshot()
	if not restored.ok and str(restored.get("code", "")) != "world.save_missing":
		persistence_restore_error = restored
		_startup_error = restored
	_refresh_ui()

func _run_2d_product() -> void:
	await get_tree().process_frame
	var report := {"schema": "gm.ext3d11.2d_product.v2", "event": "GM_EXT_3D_11_2D_SENTINEL", "ok": true, "checks": []}
	var profile_check := CONTRACT.validate_profile(sample_profile)
	var export_2d := CONTRACT.export_contract(sample_profile)
	var save_drill := CONTRACT.save_restore_drill(sample_profile)
	var actual_reopen := save_and_reopen_projection()
	var workflow_projection: Dictionary = workflow_result.get("projection", {})
	var workflow_summary := {
		"ok": bool(workflow_result.get("ok", false)),
		"dimension": str(workflow_result.get("dimension", "")),
		"definition_id": str(workflow_result.get("definition_id", "")),
		"character_count": Array(workflow_result.get("characters", [])).size(),
		"task_count": int(workflow_projection.get("task_count", 0)),
		"fact_count": int(workflow_projection.get("fact_count", 0)),
		"process_count": int(workflow_projection.get("process_count", 0)),
		"blocked_event_count": Array(workflow_result.get("blocked_events", [])).size()
	}
	var actual_reopen_summary := {
		"ok": bool(actual_reopen.get("ok", false)),
		"closed_reopened": bool(actual_reopen.get("closed_reopened", false)),
		"world_load_ok": bool(actual_reopen.get("world_load", {}).get("ok", false)),
		"task_projection_present": actual_reopen.has("task_projection"),
		"actor_snapshot_present": actual_reopen.has("actor"),
		"scene_session_present": actual_reopen.has("scene_session"),
		"object_snapshot_present": actual_reopen.has("object")
	}
	var forbidden := CONTRACT.forbidden_area_scan()
	var blocked_3d := set_dimension("3d")
	var query := query_active_target()
	var three_d_loaded := map_backend_3d != null or surface_graph_3d != null or adapter_3d != null or interaction_query_3d != null or world_3d != null or player_proxy_3d != null or target_3d != null or camera_rig_3d != null
	var entry_scene := "res://gm_runtime/vertical_sample/gm_ext_3d_11_2d_entry.tscn"
	var required := [
		entry_scene,
		"res://gm_runtime/vertical_sample/gm_ext_3d_11_2d_only.gd",
		"res://gm_runtime/vertical_sample/gm_ext_3d_11_profile.tres",
		"res://gm_runtime/vertical_sample/gm_planar2d_release_contract.gd",
		"res://gm_runtime/player_shell/gm_player_shell.gd",
		"res://gm_runtime/player_shell/gm_ext_3d_10_workflow.gd"
	]
	var inventory := CONTRACT.pack_file_inventory(entry_scene, required, release_ready)
	var formal_product := OS.get_cmdline_user_args().has("--gm-ext-3d-11-formal-product")
	_check(report, "2d_workflow_ready", release_ready and int(workflow_result.get("projection", {}).get("task_count", 0)) == sample_profile.actor_specs.size())
	_check(report, "2d_profile_valid", bool(profile_check.get("ok", false)))
	_check(report, "2d_export_has_no_3d_leak", bool(export_2d.get("ok", false)) and Array(export_2d.get("leaks", [])).is_empty())
	_check(report, "2d_runtime_does_not_load_3d", not three_d_loaded)
	_check(report, "2d_runtime_rejects_3d_switch", not blocked_3d.ok and str(blocked_3d.get("code", "")) == "delivery.3d_module_excluded")
	_check(report, "2d_query_remains_playable", bool(query.get("ok", false)))
	_check(report, "save_contract_reused", bool(save_drill.get("ok", false)) and bool(save_drill.get("single_save_root", false)) and bool(actual_reopen.get("ok", false)) and bool(actual_reopen.get("closed_reopened", false)))
	_check(report, "forbidden_area_clean", bool(forbidden.get("ok", false)))
	_check(report, "formal_pack_inventory", formal_product and bool(inventory.get("ok", false)) and Array(inventory.get("forbidden_hits", [])).is_empty() and Array(inventory.get("recursive_forbidden_hits", [])).is_empty())
	report["profile"] = profile_check
	report["workflow"] = workflow_summary
	report["export"] = export_2d
	report["save_restore"] = save_drill
	report["actual_player_shell_save_reopen"] = actual_reopen_summary
	report["forbidden_area_scan"] = forbidden
	report["three_d_loaded"] = three_d_loaded
	report["blocked_3d"] = blocked_3d
	report["query"] = query
	report["inventory"] = inventory
	report["actual_pack"] = true
	report["formal_product"] = formal_product
	report["entry_started"] = release_ready
	report["formal_entry_scene"] = entry_scene
	var evidence := _write_evidence(report)
	report["evidence_write"] = evidence
	var result := {"ok": bool(report.get("ok", false)) and bool(evidence.get("ok", false)), "checks": report.get("checks", []), "file_count": int(inventory.get("file_count", 0)), "forbidden_hits": inventory.get("forbidden_hits", []), "recursive_forbidden_hits": inventory.get("recursive_forbidden_hits", []), "evidence": evidence}
	print("GM_EXT_3D_11_2D_RESULT " + JSON.stringify(result))
	print("GM_EXT_3D_11_2D_PACK_RESULT " + JSON.stringify(result))
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)

func _run_2d_contract() -> void:
	await get_tree().process_frame
	var report := {"schema": "gm.ext3d11.2d_contract.v1", "event": "GM_EXT_3D_11_2D_SENTINEL", "ok": true, "checks": []}
	var profile_check := CONTRACT.validate_profile(sample_profile)
	var export_2d := CONTRACT.export_contract(sample_profile)
	var save_drill := CONTRACT.save_restore_drill(sample_profile)
	var forbidden := CONTRACT.forbidden_area_scan()
	var blocked_3d := set_dimension("3d")
	var query := query_active_target()
	var three_d_loaded := map_backend_3d != null or surface_graph_3d != null or adapter_3d != null or interaction_query_3d != null or world_3d != null or player_proxy_3d != null or target_3d != null or camera_rig_3d != null
	_check(report, "2d_workflow_ready", release_ready and int(workflow_result.get("projection", {}).get("task_count", 0)) == sample_profile.actor_specs.size())
	_check(report, "2d_profile_valid", bool(profile_check.get("ok", false)))
	_check(report, "2d_export_has_no_3d_leak", bool(export_2d.get("ok", false)) and Array(export_2d.get("leaks", [])).is_empty())
	_check(report, "2d_runtime_does_not_load_3d", not three_d_loaded)
	_check(report, "2d_runtime_rejects_3d_switch", not blocked_3d.ok and str(blocked_3d.get("code", "")) == "delivery.3d_module_excluded")
	_check(report, "2d_query_remains_playable", bool(query.get("ok", false)))
	_check(report, "save_contract_reused", bool(save_drill.get("ok", false)) and bool(save_drill.get("single_save_root", false)))
	_check(report, "forbidden_area_clean", bool(forbidden.get("ok", false)))
	report["profile"] = profile_check
	report["workflow"] = workflow_result
	report["export"] = export_2d
	report["save_restore"] = save_drill
	report["forbidden_area_scan"] = forbidden
	report["three_d_loaded"] = three_d_loaded
	report["blocked_3d"] = blocked_3d
	report["query"] = query
	report["formal_entry_scene"] = "res://gm_runtime/vertical_sample/gm_ext_3d_11_2d_entry.tscn"
	var evidence := _write_evidence(report)
	report["evidence_write"] = evidence
	print("GM_EXT_3D_11_2D_RESULT " + JSON.stringify({"ok": bool(report.get("ok", false)) and bool(evidence.get("ok", false)), "checks": report.get("checks", []), "evidence": evidence}))
	get_tree().quit(0 if bool(report.ok) and bool(evidence.get("ok", false)) else 1)

func _run_2d_pack_inventory() -> void:
	await get_tree().process_frame
	var entry_scene := "res://gm_runtime/vertical_sample/gm_ext_3d_11_2d_entry.tscn"
	var required := [
		entry_scene,
		"res://gm_runtime/vertical_sample/gm_ext_3d_11_profile.tres",
		"res://gm_runtime/vertical_sample/gm_planar2d_release_contract.gd",
		"res://gm_runtime/player_shell/gm_player_shell.gd"
	]
	var inventory := CONTRACT.pack_file_inventory(entry_scene, required, release_ready)
	var formal_product := false
	for argument in OS.get_cmdline_user_args():
		if str(argument) == "--gm-ext-3d-11-formal-product": formal_product = true
	var report := {"schema": "gm.ext3d11.2d_pack_inventory.v1", "ok": bool(inventory.get("ok", false)), "inventory": inventory, "actual_pack": true, "entry_started": release_ready, "formal_product": formal_product, "three_d_dependency_roots_absent": Array(inventory.get("forbidden_hits", [])).is_empty() and Array(inventory.get("recursive_forbidden_hits", [])).is_empty()}
	var evidence := _write_evidence(report)
	report["evidence_write"] = evidence
	print("GM_EXT_3D_11_2D_PACK_RESULT " + JSON.stringify({"ok": bool(report.get("ok", false)) and bool(evidence.get("ok", false)), "file_count": int(inventory.get("file_count", 0)), "forbidden_hits": inventory.get("forbidden_hits", []), "recursive_forbidden_hits": inventory.get("recursive_forbidden_hits", []), "evidence": evidence}))
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
