class_name GMVisualBudgetManager3D
extends Node

@export var budget_profile: GMCharacterVisualBudgetProfile
@export var camera: Camera3D
@export var world_viewport: SubViewport
var _profile: GMCharacterVisualBudgetProfile
var _entries: Dictionary = {}
var _clock: float = 0.0
var _report: Dictionary = {}

func _ready() -> void:
	if budget_profile != null: configure(budget_profile)

func configure(candidate: GMCharacterVisualBudgetProfile) -> Dictionary:
	if candidate == null: return {"ok": false, "code": "visual_budget.missing", "error_zh": "请选择角色视觉预算资源。"}
	var checked := candidate.validate()
	if not checked.ok: return checked
	_profile = candidate.duplicate(true)
	if is_instance_valid(world_viewport): world_viewport.size = _profile.world_viewport_resolution
	return {"ok": true}

func register_character(id: String, visual: GMCharacterVisual3D, actor: Node3D = null) -> Dictionary:
	if id.is_empty() or not is_instance_valid(visual) or _entries.has(id):
		return {"ok": false, "code": "visual_budget.character_invalid", "error_zh": "角色标识重复、为空或表现节点已释放。"}
	if visual.has_meta("gm_visual_budget_owner"):
		return {"ok": false, "code": "visual_budget.owner_conflict", "error_zh": "此角色已由另一个视觉预算管理器调度。"}
	_entries[id] = {"visual": weakref(visual), "actor": weakref(actor) if actor != null else null, "distance_lod": "Near", "lod": "Near", "last_sample": -1.0, "updates": 0, "original_process": visual.is_processing()}
	visual.set_meta("gm_visual_budget_owner", get_instance_id())
	visual.set_process(false)
	return {"ok": true}

func unregister_character(id: String) -> void:
	if not _entries.has(id): return
	var row: Dictionary = _entries[id]
	var visual = row.visual.get_ref()
	if is_instance_valid(visual):
		visual.set_visual_quality("Near", true, true)
		visual.set_process(row.original_process)
		visual.remove_meta("gm_visual_budget_owner")
	_entries.erase(id)

func _process(delta: float) -> void:
	if is_instance_valid(camera): update_visuals(delta, camera)

func update_visuals(delta: float, view: Camera3D) -> Dictionary:
	if _profile == null or not is_instance_valid(view) or not is_finite(delta) or delta < 0.0:
		return {"ok": false, "code": "visual_budget.input_invalid", "error_zh": "视觉预算未配置、相机已释放或时间步无效。"}
	var rows: Array = []
	for id in _entries.keys():
		var visual = _entries[id].visual.get_ref()
		if not is_instance_valid(visual):
			_entries.erase(id)
			continue
		var validation: Dictionary = visual.validate_lod_meshes()
		if not validation.ok: return validation
		rows.append({"id": id, "visual": visual, "distance": view.global_position.distance_to(visual.global_position), "visible": view.is_position_in_frustum(visual.global_position)})
	rows.sort_custom(func(a, b): return a.distance < b.distance if a.distance != b.distance else a.id < b.id)
	_clock += delta
	var full := 0
	var animated := 0
	var skins := 0
	var features := 0
	var updates := 0
	var cost_usec := 0
	var warnings: Array[String] = []
	var counts := {"Near": 0, "Mid": 0, "Far": 0, "Offscreen": 0}
	var due: Array = []
	for item in rows:
		var row: Dictionary = _entries[item.id]
		var lod := _distance_lod(item.distance, row.distance_lod)
		row.distance_lod = lod
		if not item.visible: lod = "Offscreen"
		if lod == "Near":
			if full >= _profile.max_full_quality_characters:
				lod = "Mid"
				warnings.append("完整质量预算不足，部分角色使用中景。")
			else: full += 1
		var demand: Dictionary = item.visual.budget_report()
		var allow_skin := lod != "Offscreen" and skins + int(demand.skinned_mesh_count) <= _profile.max_skinned_meshes
		var allow_feature := lod == "Near" and features + int(demand.feature_module_count) <= _profile.feature_module_budget
		if allow_skin: skins += int(demand.skinned_mesh_count)
		elif lod != "Offscreen" and int(demand.skinned_mesh_count) > 0: warnings.append("蒙皮网格预算不足，相关网格暂停显示。")
		if allow_feature: features += int(demand.feature_module_count)
		elif lod == "Near" and int(demand.feature_module_count) > 0: warnings.append("附加模块预算不足，相关模块暂停显示。")
		var hz := 0.0 if lod == "Near" else _profile.mid_sampling_hz if lod == "Mid" else _profile.far_sampling_hz
		var can_animate := lod != "Offscreen" and animated < _profile.max_visible_animated_characters
		if can_animate: animated += 1
		elif lod != "Offscreen": warnings.append("可动画角色预算不足，部分角色保持最后姿态。")
		item.visual.set_visual_quality(lod, allow_feature, allow_skin)
		row.lod = lod
		row.sampling_hz = hz if can_animate else -1.0
		row.distance = item.distance
		counts[lod] += 1
		if can_animate and (hz == 0.0 or _clock - float(row.last_sample) >= 1.0 / hz):
			due.append(item)
	# Oldest actual sample first: an animation count cap must not starve tail rows.
	due.sort_custom(func(a, b): return _entries[a.id].last_sample < _entries[b.id].last_sample if _entries[a.id].last_sample != _entries[b.id].last_sample else a.id < b.id)
	for item in due:
		if updates >= _profile.animation_update_budget or cost_usec >= _profile.animation_budget_ms * 1000.0: break
		var start := Time.get_ticks_usec()
		var sampling := GMAnimationSamplingProfile.new()
		var hz := float(_entries[item.id].sampling_hz)
		sampling.sampling_mode = "Smooth" if hz == 0.0 else str(int(hz))
		sampling.samples_per_cycle = int(hz)
		var timing := sampling.sample_time(_clock)
		item.visual.sample_visual_pose(float(timing.sampled_time))
		cost_usec += Time.get_ticks_usec() - start
		_entries[item.id].last_sample = _clock
		_entries[item.id].updates += 1
		updates += 1
	if updates < due.size(): warnings.append("动画更新预算不足，本帧未采样角色保留最后姿态。")
	var unique: Array[String] = []
	for warning in warnings:
		if not unique.has(warning): unique.append(warning)
	_report = {"ok": true, "characters": rows.size(), "lod_counts": counts, "full_quality": full, "animated_characters": animated, "skinned_meshes": skins, "feature_modules": features, "animation_updates": updates, "animation_cost_ms": cost_usec / 1000.0, "deferred_updates": due.size() - updates, "warnings_zh": unique, "frame_warning": delta * 1000.0 > _profile.frame_warning_ms, "world_viewport_resolution": _profile.world_viewport_resolution}
	return _report.duplicate(true)

func _distance_lod(distance: float, previous: String) -> String:
	var h := _profile.hysteresis
	if previous == "Near" and distance <= _profile.near_distance + h: return "Near"
	if previous == "Far" and distance >= _profile.far_distance - h: return "Far"
	if distance < _profile.near_distance - h: return "Near"
	if distance > _profile.far_distance + h: return "Far"
	return "Mid"

func snapshot() -> Dictionary:
	return _report.duplicate(true)

func character_snapshot(id: String) -> Dictionary:
	if not _entries.has(id): return {}
	var row: Dictionary = _entries[id]
	var visual = row.visual.get_ref()
	if not is_instance_valid(visual): return {}
	var actor = row.actor.get_ref() if row.actor != null else null
	var sockets: Array = []
	if visual.recipe != null and visual.resolver != null:
		var skeleton = visual.resolver.resolve(visual.recipe.skeleton_contract_id)
		if skeleton is GMHumanoidSkeletonContract: sockets = skeleton.to_contract_report().sockets
	return {"id": id, "lod": row.lod, "sampling_hz": row.get("sampling_hz", -1), "sample_count": row.updates, "last_sample": row.last_sample, "visual": visual.snapshot(), "sockets": sockets, "spatial": actor.call("spatial_visual_snapshot") if is_instance_valid(actor) and actor.has_method("spatial_visual_snapshot") else {}, "movement": actor.call("movement_snapshot") if is_instance_valid(actor) and actor.has_method("movement_snapshot") else {}}

func unload() -> void:
	for id in _entries.keys(): unregister_character(id)
	_report.clear()
	_clock = 0.0

func _exit_tree() -> void:
	unload()
