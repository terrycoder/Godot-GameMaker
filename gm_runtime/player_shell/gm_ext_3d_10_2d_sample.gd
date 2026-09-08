class_name GMExt3D10TwoDSample
extends GMPlayerShell

const WORKFLOW := preload("res://gm_runtime/player_shell/gm_ext_3d_10_workflow.gd")

@export var sample_profile: GMNeutralVerticalSampleProfile
var workflow_result: Dictionary = {}
var ext10_ready := false

func _should_restore_on_start() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--gm-ext-3d-10-contract") or args.has("--gm-ext-3d-10-2d-contract") or args.has("--gm-ext-3d-10-list-pack"):
		return false
	return super._should_restore_on_start()

func _ready() -> void:
	var selected := GMNeutralVerticalSampleProfile.resolve_configured(sample_profile, OS.get_cmdline_user_args())
	if not selected.ok:
		_startup_error = selected
		return
	sample_profile = selected.profile
	var configured := sample_profile.apply_shell_configuration(shell_configuration)
	if not configured.ok:
		_startup_error = configured
		return
	super._ready()
	if _startup_error.is_empty():
		var anchors:=sample_profile.configure_semantic_anchors(semantic_registry, shell_configuration.tile_size)
		if not anchors.ok:
			_startup_error=anchors
		else:
			workflow_result = WORKFLOW.new().execute(self, sample_profile, "2d")
		ext10_ready = bool(workflow_result.get("ok", false))
	var args := OS.get_cmdline_user_args()
	if args.has("--gm-ext-3d-10-contract") or args.has("--gm-ext-3d-10-2d-contract"): await _run_ext10_2d_contract()
	elif args.has("--gm-ext-3d-10-list-pack"): await _run_ext10_pack_inventory()

func _schedule_command_mode() -> void:
	# EXT10 owns this exported composition's command modes. P25 modes remain
	# available from the original P25 delivery scene.
	pass

func _run_ext10_2d_contract() -> void:
	await get_tree().process_frame
	var projection: Dictionary = workflow_result.get("projection", {})
	var three_d_loaded := map_backend_3d != null or surface_graph_3d != null or adapter_3d != null or world_3d != null
	var three_d_sources_cropped := DirAccess.open("res://gm_runtime/map/3d") == null and DirAccess.open("res://gm_adapters/spatial3d") == null and DirAccess.open("res://gm_runtime/content/3d") == null and DirAccess.open("res://addons/gm_editor") == null
	var crop_required := OS.has_feature("gm_ext_3d_10_disabled")
	var all_gated := true
	for row in workflow_result.get("rows", []):
		all_gated = all_gated and bool(row.get("arrival_verified", false)) and str(row.get("reservation_state_at_process", "")) == "active" and bool(row.get("process_started_after_gate", false))
	var report := {
		"schema": "gm.ext3d10.2d_contract.v1",
		"event": "GM_EXT_3D_10_2D_SENTINEL",
		"ok": ext10_ready and int(projection.get("task_count", 0)) == sample_profile.actor_specs.size() and int(projection.get("process_count", 0)) == sample_profile.actor_specs.size() and all_gated and not three_d_loaded and (not crop_required or three_d_sources_cropped),
		"dimension": "2d",
		"projection": projection,
		"all_processes_after_authoritative_arrival_and_reservation": all_gated,
		"three_d_modules_loaded": three_d_loaded,
		"three_d_sources_cropped": three_d_sources_cropped,
		"crop_required": crop_required,
		"editor_module_present": DirAccess.open("res://addons/gm_editor") != null,
		"workflow_error": workflow_result if not ext10_ready else {},
		"blocked_events": workflow_result.get("blocked_events", []),
		"retry_summary": workflow_result.get("retry_summary", {}),
	}
	var evidence := WORKFLOW.write_json_if_requested(report)
	report["evidence_write"] = evidence
	print("GM_EXT_3D_10_2D_RESULT " + JSON.stringify(report))
	get_tree().quit(0 if bool(report.ok) and bool(evidence.get("ok", false)) else 1)

func _run_ext10_pack_inventory() -> void:
	await get_tree().process_frame
	var files := WORKFLOW.pack_file_inventory()
	var report := {"schema": "gm.ext3d10.pack_inventory.v1", "event": "GM_EXT_3D_10_PACK_INVENTORY_SENTINEL", "ok": true, "delivery": "disabled_2d", "entry_scene": "res://gm_runtime/vertical_sample/gm_ext_3d_10_2d_entry.tscn", "file_count": files.size(), "files": files}
	var written := WORKFLOW.write_json_if_requested(report)
	print("GM_EXT_3D_10_PACK_INVENTORY_RESULT " + JSON.stringify({"ok": bool(written.get("ok", false)), "delivery": "disabled_2d", "file_count": files.size(), "written": written}))
	get_tree().quit(0 if bool(written.get("ok", false)) else 1)
