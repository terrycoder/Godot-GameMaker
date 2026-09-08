@tool
class_name GMPlanarCombat3DDock
extends PanelContainer

## Formal Simplified-Chinese EXT07 editor surface.  The dock edits one
## GMCombatCatalog Resource through EditorUndoRedoManager and uses real
## HitVolume3D/TargetPoint3D nodes only for a disposable preview/query edge.

const CATALOG_SCRIPT := preload("res://gm_runtime/combat/gm_combat_catalog.gd")
const ATTACK_SCRIPT := preload("res://gm_runtime/combat/gm_combat_attack_definition.gd")
const GRAPH_SCRIPT := preload("res://gm_runtime/map/3d/gm_surface_graph.gd")
const SURFACE_SCRIPT := preload("res://gm_runtime/map/3d/gm_surface_definition_3d.gd")
const MAP_BACKEND_SCRIPT := preload("res://gm_runtime/map/3d/gm_map_backend_3d.gd")
const ADAPTER_SCRIPT := preload("res://gm_runtime/combat/3d/gm_planar_combat_adapter_3d.gd")
const VOLUME_SCRIPT := preload("res://gm_runtime/combat/3d/gm_hit_volume_3d.gd")
const TARGET_SCRIPT := preload("res://gm_runtime/combat/3d/gm_target_point_3d.gd")
const HIT_SPEC_SCRIPT := preload("res://gm_runtime/combat/gm_combat_hit_spec.gd")
const PLANAR_POSITION_SCRIPT := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")

const MAP_ID := "gm.map.ext3d07.editor"
const GRAPH_ID := "gm.graph.ext3d07.editor"
const SURFACE_ID := "gm.surface.ext3d07.editor.floor"
const DEFAULT_CATALOG_ID := "gm.combat.catalog.ext3d07.editor"
const DEFAULT_ATTACK_ID := "gm.attack.ext3d07.editor.slash"
const DEFAULT_VOLUME_ID := "gm.hit_volume.ext3d07.editor"
const DEFAULT_SOURCE_ID := "gm.actor.ext3d07.editor"
const DEFAULT_TARGET_ID := "gm.actor.ext3d07.target"
const DEFAULT_TARGET_POINT_ID := "gm.target_point.ext3d07.editor"
const DEFAULT_ANCHOR_ID := "gm.anchor.ext3d07.editor.target"
const DEFAULT_ABILITY_ID := "gm.ability.planar_combat_3d"
const DEFAULT_SEED := "gm.ext3d07.editor.seed.7"
const DEFAULT_SAVE_PATH := "user://gm_ext_3d_07_combat_catalog.tres"
const DEFAULT_ATTACK_MAGNITUDE := 10.0
const DEFAULT_ATTACK_RANGE := 8.0
const DEFAULT_VOLUME_RADIUS := 0.7

var editor_interface
var editor_undo_redo: EditorUndoRedoManager
var catalog: GMCombatCatalog
var map_backend: GMMapBackend3D
var adapter: GMPlanarCombatAdapter3D
var volume: GMHitVolume3D
var target_point: GMTargetPoint3D
var _controls: Dictionary = {}
var _status: Label
var _details: RichTextLabel
var _preview_container: SubViewportContainer
var _preview_viewport: SubViewport
var _preview_world: Node3D
var _catalog_resource: GMCombatCatalog
var _catalog_path := DEFAULT_SAVE_PATH
var _last_candidate: Dictionary = {}
var _last_validation: Dictionary = {}
var _last_operation: Dictionary = {}
var _last_save_restore: Dictionary = {}
var _control_events: Array[String] = []
var _applying_editor_state := false
var _direct_success_action_calls := 0
var _target_y_before_bad_height := 0.0

func _init() -> void:
	name = "GMPlanarCombat3DDock"
	custom_minimum_size = Vector2(1220, 700)
	_setup_runtime_fixture()
	_build_preview()
	_build_formal_ui()

func configure(value_editor_interface, value_editor_undo_redo: EditorUndoRedoManager) -> void:
	editor_interface = value_editor_interface
	editor_undo_redo = value_editor_undo_redo

func _setup_runtime_fixture() -> void:
	map_backend = MAP_BACKEND_SCRIPT.new()
	var graph: GMSurfaceGraph = GRAPH_SCRIPT.new()
	graph.graph_id = GRAPH_ID
	graph.map_id = MAP_ID
	graph.display_name_zh = "EXT07编辑器中性Surface Graph"
	var surface: GMSurfaceDefinition3D = SURFACE_SCRIPT.rectangle(SURFACE_ID, MAP_ID, "floor", Vector3.ZERO, Vector2(20.0, 20.0))
	surface.display_name_zh = "EXT07中性战斗Floor"
	graph.register_surface(surface)
	map_backend.configure_graph(graph)
	adapter = ADAPTER_SCRIPT.new(map_backend, 0.75)
	_catalog_resource = _neutral_catalog()
	catalog = _catalog_resource

func _neutral_catalog() -> GMCombatCatalog:
	var attack = ATTACK_SCRIPT.new().configure(DEFAULT_ATTACK_ID, "编辑器中性斩击", "melee", "damage", DEFAULT_ATTACK_MAGNITUDE, DEFAULT_ATTACK_RANGE)
	return CATALOG_SCRIPT.new().configure(DEFAULT_CATALOG_ID, "EXT07平面战斗3D编辑器目录", [attack.to_native()], [], [])

func _catalog_from_controls() -> GMCombatCatalog:
	var attack = ATTACK_SCRIPT.new().configure(_value("attack_id", DEFAULT_ATTACK_ID), "编辑器中性斩击", "melee", "damage", _number("attack_magnitude", DEFAULT_ATTACK_MAGNITUDE), _number("attack_range", DEFAULT_ATTACK_RANGE))
	return CATALOG_SCRIPT.new().configure(_value("catalog_id", DEFAULT_CATALOG_ID), "EXT07平面战斗3D编辑器目录", [attack.to_native()], [], [])

func _build_preview() -> void:
	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "GMPlanarCombat3DPreviewViewport"
	_preview_viewport.size = Vector2i(640, 420)
	_preview_viewport.transparent_bg = true
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_world = Node3D.new()
	_preview_world.name = "GMPlanarCombat3DPreviewWorld"
	_preview_viewport.add_child(_preview_world)
	var camera := Camera3D.new()
	camera.name = "Combat3DPreviewCamera"
	camera.position = Vector3(10.0, 12.0, 16.0)
	camera.look_at_from_position(camera.position, Vector3(8.0, 0.0, 8.0), Vector3.UP)
	_preview_world.add_child(camera)
	var light := DirectionalLight3D.new()
	light.name = "Combat3DPreviewLight"
	light.rotation_degrees = Vector3(-45.0, -25.0, 0.0)
	light.light_energy = 1.2
	_preview_world.add_child(light)
	volume = VOLUME_SCRIPT.new().configure("gm.hit_volume.ext3d07.editor", "gm.actor.ext3d07.editor", "direct", 0.7, 0.75)
	volume.position = Vector3(4.0, 0.0, 4.0)
	_preview_world.add_child(volume)
	target_point = TARGET_SCRIPT.new().configure("gm.target_point.ext3d07.editor", "gm.actor.ext3d07.target", MAP_ID, SURFACE_ID, 0.75, "gm.anchor.ext3d07.editor.target")
	target_point.position = Vector3(4.0, 0.0, 4.0)
	_preview_world.add_child(target_point)

func _build_formal_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "GMPlanarCombat3DFormalRoot"
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.name = "PlanarCombat3DTitle"
	title.text = "GM 平面战斗与 Cue3D · HitVolume / TargetPoint / Projectile / AoE"
	title.add_theme_font_size_override("font_size", 20)
	title.custom_minimum_size.x = 620
	header.add_child(title)
	var hint := Label.new()
	hint.text = "Area3D/Shape只产候选；最终命中、伤害与效果仍由唯一P22 CombatResolver决定。"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(hint)
	_controls["new"] = _button(header, "按当前控件新建", "NewCombat3D", _new_catalog)
	_controls["apply"] = _button(header, "应用目录定义", "ApplyCombat3D", _apply_catalog_from_controls)
	_controls["candidate"] = _button(header, "建立Hit候选", "BuildHitCandidate", _build_candidate)
	_controls["validate"] = _button(header, "校验3D查询", "ValidateCombat3D", _validate_combat)

	var workspace := HBoxContainer.new()
	workspace.name = "PlanarCombat3DWorkspace"
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(workspace)
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size.x = 650
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.name = "PlanarCombat3DControls"
	left.custom_minimum_size.x = 630
	left_scroll.add_child(left)
	_build_identity_section(left)
	_build_representation_section(left)
	_build_persistence_section(left)
	var right := VBoxContainer.new()
	right.name = "PlanarCombat3DPreviewPane"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(right)
	var preview_title := Label.new()
	preview_title.text = "实时3D查询预览（正式 SubViewport）"
	preview_title.add_theme_font_size_override("font_size", 16)
	right.add_child(preview_title)
	_preview_container = SubViewportContainer.new()
	_preview_container.name = "PlanarCombat3DPreviewContainer"
	_preview_container.custom_minimum_size = Vector2(520, 360)
	_preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_container.stretch = true
	_preview_container.add_child(_preview_viewport)
	right.add_child(_preview_container)
	_details = RichTextLabel.new()
	_details.name = "PlanarCombat3DDetails"
	_details.bbcode_enabled = true
	_details.fit_content = false
	_details.custom_minimum_size.y = 230
	right.add_child(_details)
	_status = Label.new()
	_status.name = "PlanarCombat3DStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	_refresh_details()

func _build_identity_section(parent: VBoxContainer) -> void:
	var section := _section(parent, "战斗定义与稳定身份（P22 CombatCatalog）")
	var grid := GridContainer.new()
	grid.columns = 2
	section.add_child(grid)
	_controls["ability_id"] = _line(grid, "Ability ID（能力稳定ID）", DEFAULT_ABILITY_ID, "Combat3DAbilityId")
	_controls["seed"] = _line(grid, "Seed（回放种子）", DEFAULT_SEED, "Combat3DSeed")
	_controls["catalog_id"] = _line(grid, "CombatCatalog ID（目录）", DEFAULT_CATALOG_ID, "Combat3DCatalogId")
	_controls["attack_id"] = _line(grid, "Attack ID（攻击）", DEFAULT_ATTACK_ID, "Combat3DAttackId")
	_controls["volume_id"] = _line(grid, "HitVolume ID（命中体）", DEFAULT_VOLUME_ID, "Combat3DVolumeId")
	_controls["source_id"] = _line(grid, "Source Actor ID（源）", DEFAULT_SOURCE_ID, "Combat3DSourceId")
	_controls["target_id"] = _line(grid, "Target Actor ID（目标）", DEFAULT_TARGET_ID, "Combat3DTargetId")
	_controls["map_id"] = _line(grid, "Map ID（地图）", MAP_ID, "Combat3DMapId")
	_controls["graph_id"] = _line(grid, "Surface Graph ID（图）", GRAPH_ID, "Combat3DGraphId")
	_controls["surface_id"] = _line(grid, "Surface ID（表面）", SURFACE_ID, "Combat3DSurfaceId")
	_controls["target_point_id"] = _line(grid, "TargetPoint ID（目标点）", DEFAULT_TARGET_POINT_ID, "Combat3DTargetPointId")
	_controls["anchor_id"] = _line(grid, "Anchor ID（锚点）", DEFAULT_ANCHOR_ID, "Combat3DAnchorId")
	_controls["attack_magnitude"] = _line(grid, "Attack伤害量", str(DEFAULT_ATTACK_MAGNITUDE), "Combat3DAttackMagnitude")
	_controls["attack_range"] = _line(grid, "Attack范围", str(DEFAULT_ATTACK_RANGE), "Combat3DAttackRange")
	_controls["height_tolerance"] = _line(grid, "Height容差", "0.75", "Combat3DHeightTolerance")
	_controls["target_y"] = _line(grid, "Target世界Y", "0.0", "Combat3DTargetY")

func _build_representation_section(parent: VBoxContainer) -> void:
	var section := _section(parent, "3D命中表现边界")
	var note := Label.new()
	note.text = "TargetPoint只提供稳定目标点与Surface高度；Projectile/AoE/Cue为可取消、可回收的表现运行时。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 2
	section.add_child(grid)
	_controls["source_x"] = _line(grid, "Source逻辑X", "1.0", "Combat3DSourceX")
	_controls["source_y"] = _line(grid, "Source逻辑Y", "1.0", "Combat3DSourceY")
	_controls["target_x"] = _line(grid, "Target逻辑X", "4.0", "Combat3DTargetX")
	_controls["target_z"] = _line(grid, "Target逻辑Y", "4.0", "Combat3DTargetZ")
	_controls["volume_radius"] = _line(grid, "HitVolume平面半径", str(DEFAULT_VOLUME_RADIUS), "Combat3DVolumeRadius")
	var actions := HBoxContainer.new()
	section.add_child(actions)
	_controls["undo"] = _button(actions, "撤销", "UndoCombat3D", _undo_editor_action)
	_controls["redo"] = _button(actions, "重做", "RedoCombat3D", _redo_editor_action)
	_controls["bad_height"] = _button(actions, "注入高度失败", "InjectBadHeight", _inject_bad_height)
	_controls["restore_height"] = _button(actions, "恢复高度", "RestoreHeight", _restore_height)

func _build_persistence_section(parent: VBoxContainer) -> void:
	var section := _section(parent, "保存、关闭与重新打开")
	var grid := GridContainer.new()
	grid.columns = 2
	section.add_child(grid)
	_controls["save_path"] = _line(grid, "CombatCatalog保存路径", DEFAULT_SAVE_PATH, "Combat3DSavePath")
	var actions := HBoxContainer.new()
	section.add_child(actions)
	_controls["save"] = _button(actions, "保存目录", "SaveCombat3D", _save_catalog)
	_controls["close"] = _button(actions, "关闭预览", "CloseCombat3D", _close_preview)
	_controls["reopen"] = _button(actions, "重新打开", "ReopenCombat3D", _reopen_catalog)

func _section(parent: VBoxContainer, title_text: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = title_text.replace(" / ", "_").replace(" ", "_")
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 16)
	section.add_child(title)
	parent.add_child(section)
	return section

func _line(parent: Container, placeholder: String, default_value: String, node_name: String) -> LineEdit:
	var line := LineEdit.new()
	line.name = node_name
	line.placeholder_text = placeholder
	line.text = default_value
	line.custom_minimum_size.x = 400
	parent.add_child(_label(placeholder))
	parent.add_child(line)
	return line

func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	return label

func _button(parent: Container, label_text: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label_text
	button.tooltip_text = label_text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _new_catalog() -> Dictionary:
	_control_events.append("new")
	var candidate_catalog := _catalog_from_controls()
	var catalog_check := candidate_catalog.validate()
	if not catalog_check.ok:
		return _fail("combat.3d.editor.catalog_invalid", "当前控件中的CombatCatalog定义无效，未新建。", {"validation": catalog_check})
	var fixture := _sync_spatial_fixture_from_controls()
	if not fixture.ok:
		return _fail("combat.3d.editor.spatial_identity_invalid", "当前控件中的地图/Surface身份无效，未新建。", {"fixture": fixture})
	_catalog_resource = candidate_catalog
	catalog = _catalog_resource
	_last_candidate.clear()
	_last_validation.clear()
	_last_operation = {"ok": true, "code": "combat.3d.editor.catalog_new", "identity": _formal_identity(), "parameters": _formal_parameters(), "through_formal_control": true, "failure_closed": true}
	_set_status("已按当前正式控件创建独立CombatCatalog。", true)
	_refresh_details()
	return _last_operation.duplicate(true)

func _apply_catalog_from_controls() -> Dictionary:
	_control_events.append("apply")
	var candidate_catalog := _catalog_from_controls()
	var catalog_check := candidate_catalog.validate()
	if not catalog_check.ok:
		return _fail("combat.3d.editor.catalog_invalid", "当前控件中的CombatCatalog定义无效，未应用。", {"validation": catalog_check})
	var committed := _commit_catalog_state(candidate_catalog.to_native(), "应用EXT07 CombatCatalog定义")
	if committed.ok:
		committed["identity"] = _formal_identity()
		committed["parameters"] = _formal_parameters()
		_last_operation = committed.duplicate(true)
		_set_status("已通过正式控件应用CombatCatalog定义。", true)
		_refresh_details()
	return committed.duplicate(true)

func _sync_spatial_fixture_from_controls() -> Dictionary:
	var map_id := _value("map_id", MAP_ID)
	var graph_id := _value("graph_id", GRAPH_ID)
	var surface_id := _value("surface_id", SURFACE_ID)
	var tolerance := _number("height_tolerance", 0.75)
	var candidate_backend: GMMapBackend3D = MAP_BACKEND_SCRIPT.new()
	var graph: GMSurfaceGraph = GRAPH_SCRIPT.new()
	graph.graph_id = graph_id
	graph.map_id = map_id
	graph.display_name_zh = "EXT07正式控件Surface Graph"
	var surface: GMSurfaceDefinition3D = SURFACE_SCRIPT.rectangle(surface_id, map_id, "floor", Vector3.ZERO, Vector2(20.0, 20.0))
	surface.display_name_zh = "EXT07正式控件战斗Floor"
	var registration := graph.register_surface(surface)
	if not registration.ok:
		return registration
	var configured := candidate_backend.configure_graph(graph)
	if not configured.ok:
		return configured
	map_backend = candidate_backend
	adapter = ADAPTER_SCRIPT.new(map_backend, tolerance)
	return {"ok": true, "code": "combat.3d.editor.spatial_fixture_synced", "map_id": map_id, "graph_id": graph_id, "surface_id": surface_id, "height_tolerance": tolerance}

func _validate_formal_identity() -> Dictionary:
	var identity := _formal_identity()
	var errors: Array[String] = []
	var catalog_id := str(identity.get("catalog_id", ""))
	var attack_id := str(identity.get("attack_id", ""))
	var volume_id := str(identity.get("volume_id", ""))
	var target_point_id := str(identity.get("target_point_id", ""))
	if not CONTRACT.stable_id(catalog_id) or not catalog_id.begins_with("gm.combat.catalog."):
		errors.append("CombatCatalog ID必须使用gm.combat.catalog.*稳定身份。")
	if not CONTRACT.stable_id(attack_id) or not attack_id.begins_with("gm.attack."):
		errors.append("Attack ID必须使用gm.attack.*稳定身份。")
	if not CONTRACT.stable_id(volume_id) or not volume_id.begins_with("gm.hit_volume."):
		errors.append("HitVolume ID必须使用gm.hit_volume.*稳定身份。")
	if not CONTRACT.stable_id(target_point_id) or not target_point_id.begins_with("gm.target_point."):
		errors.append("TargetPoint ID必须使用gm.target_point.*稳定身份。")
	for field in ["ability_id", "seed", "source_id", "target_id", "map_id", "graph_id", "surface_id", "anchor_id"]:
		if not CONTRACT.stable_id(str(identity.get(field, ""))):
			errors.append("%s必须是非空稳定值。" % field)
	var save_path := str(identity.get("save_path", ""))
	if save_path.is_empty() or (not save_path.begins_with("user://") and not save_path.begins_with("res://")):
		errors.append("保存路径必须使用user://或res://入口。")
	if catalog != null:
		if str(catalog.catalog_id) != catalog_id:
			errors.append("目录身份已改变，请先通过正式控件应用目录定义。")
		if catalog.attacks.is_empty() or str(catalog.attacks[0].get("attack_id", "")) != attack_id:
			errors.append("攻击身份已改变，请先通过正式控件应用目录定义。")
	if errors.is_empty():
		return {"ok": true, "code": "combat.3d.editor.identity_valid", "identity": identity}
	return {"ok": false, "code": "combat.3d.editor.identity_invalid", "errors": errors, "identity": identity}

func _value(control_id: String, fallback: String) -> String:
	if not _controls.has(control_id):
		return fallback
	var line := _controls[control_id] as LineEdit
	return line.text.strip_edges() if line != null else fallback

func _formal_identity() -> Dictionary:
	return {
		"ability_id": _value("ability_id", DEFAULT_ABILITY_ID),
		"seed": _value("seed", DEFAULT_SEED),
		"catalog_id": _value("catalog_id", DEFAULT_CATALOG_ID),
		"attack_id": _value("attack_id", DEFAULT_ATTACK_ID),
		"volume_id": _value("volume_id", DEFAULT_VOLUME_ID),
		"source_id": _value("source_id", DEFAULT_SOURCE_ID),
		"target_id": _value("target_id", DEFAULT_TARGET_ID),
		"map_id": _value("map_id", MAP_ID),
		"graph_id": _value("graph_id", GRAPH_ID),
		"surface_id": _value("surface_id", SURFACE_ID),
		"target_point_id": _value("target_point_id", DEFAULT_TARGET_POINT_ID),
		"anchor_id": _value("anchor_id", DEFAULT_ANCHOR_ID),
		"save_path": _value("save_path", DEFAULT_SAVE_PATH),
	}

func _formal_parameters() -> Dictionary:
	return {
		"attack_magnitude": _number("attack_magnitude", DEFAULT_ATTACK_MAGNITUDE),
		"attack_range": _number("attack_range", DEFAULT_ATTACK_RANGE),
		"volume_radius": _number("volume_radius", DEFAULT_VOLUME_RADIUS),
		"height_tolerance": _number("height_tolerance", 0.75),
		"source_x": _number("source_x", 1.0),
		"source_y": _number("source_y", 1.0),
		"target_x": _number("target_x", 4.0),
		"target_y": _number("target_y", 0.0),
		"target_z": _number("target_z", 4.0),
	}

func _formal_control_values() -> Dictionary:
	var values := _formal_identity()
	values.merge(_formal_parameters(), true)
	return values

func _build_candidate() -> Dictionary:
	_control_events.append("candidate")
	if catalog == null:
		return _fail("combat.3d.editor.catalog_missing", "没有可编辑的CombatCatalog。")
	var identity_check := _validate_formal_identity()
	if not identity_check.ok:
		return _fail("combat.3d.editor.identity_invalid", "正式控件中的稳定身份无效，候选生成已关闭。", {"validation": identity_check})
	var fixture := _sync_spatial_fixture_from_controls()
	if not fixture.ok:
		return _fail("combat.3d.editor.spatial_identity_invalid", "正式控件中的地图/Surface身份无效，候选生成已关闭。", {"fixture": fixture})
	var tolerance := _number("height_tolerance", 0.75)
	target_point.configure(_value("target_point_id", DEFAULT_TARGET_POINT_ID), _value("target_id", DEFAULT_TARGET_ID), _value("map_id", MAP_ID), _value("surface_id", SURFACE_ID), tolerance, _value("anchor_id", DEFAULT_ANCHOR_ID))
	target_point.position = Vector3(_number("target_x", 4.0), _number("target_y", 0.0), _number("target_z", 4.0))
	volume.configure(_value("volume_id", DEFAULT_VOLUME_ID), _value("source_id", DEFAULT_SOURCE_ID), "direct", _number("volume_radius", DEFAULT_VOLUME_RADIUS), tolerance)
	var source_position: GMPlanarPosition = PLANAR_POSITION_SCRIPT.new(_value("map_id", MAP_ID), _value("surface_id", SURFACE_ID), _number("source_x", 1.0), _number("source_y", 1.0))
	var candidate_metadata := {"editor_action": "formal_button", "ability_id": _value("ability_id", DEFAULT_ABILITY_ID), "seed": _value("seed", DEFAULT_SEED), "attack_id": _value("attack_id", DEFAULT_ATTACK_ID), "catalog_id": _value("catalog_id", DEFAULT_CATALOG_ID)}
	_last_candidate = volume.candidate_for(source_position, target_point, map_backend, candidate_metadata)
	if not _last_candidate.ok:
		_last_operation = _last_candidate.duplicate(true)
		_set_status("Hit候选生成失败并关闭：%s" % str(_last_candidate.get("reason_zh", "")), false)
		_refresh_details()
		return _last_candidate.duplicate(true)
	_last_operation = {"ok": true, "code": "combat.3d.editor.candidate_built", "identity": _formal_identity(), "parameters": _formal_parameters(), "through_formal_control": true, "failure_closed": true, "hit_id": _last_candidate.hit_spec.hit_id, "representation": "Area3D/Shape3D->HitSpec"}
	_set_status("HitVolume3D 已生成纯值 HitSpec 候选。", true)
	_refresh_details()
	return _last_operation.duplicate(true)

func _validate_combat() -> Dictionary:
	_control_events.append("validate")
	if _last_candidate.is_empty():
		_build_candidate()
	if _last_candidate.is_empty() or not _last_candidate.get("ok", false):
		return _fail("combat.3d.editor.candidate_missing", "没有可校验的HitSpec候选。")
	_last_validation = adapter.query(_last_candidate.hit_spec, _last_candidate.query_context)
	_last_operation = {"ok": bool(_last_validation.get("ok", false)), "code": "combat.3d.editor.query_validated", "query": _last_validation.duplicate(true), "through_formal_control": true, "failure_closed": true}
	_set_status("3D查询通过，结果仍需交给唯一P22 CombatResolver。" if _last_validation.get("ok", false) else "3D查询被结构化阻断。", bool(_last_validation.get("ok", false)))
	_refresh_details()
	return _last_operation.duplicate(true)

func _inject_bad_height() -> Dictionary:
	_control_events.append("bad_height")
	_target_y_before_bad_height = _number("target_y", 0.0)
	(_controls["target_y"] as LineEdit).text = "10.0"
	return _build_candidate()

func _restore_height() -> Dictionary:
	_control_events.append("restore_height")
	(_controls["target_y"] as LineEdit).text = str(_target_y_before_bad_height)
	return _build_candidate()

func _undo_editor_action() -> void:
	_control_events.append("undo")
	if editor_undo_redo == null:
		_fail("combat.3d.editor.undo_missing", "EditorUndoRedoManager不可用，撤销已拒绝。")
		return
	var history := editor_undo_redo.get_history_undo_redo(editor_undo_redo.get_object_history_id(self))
	if history == null or not history.has_undo():
		_fail("combat.3d.editor.history_empty", "当前战斗编辑没有可撤销历史。")
		return
	history.undo()
	_last_operation = {"ok": true, "code": "combat.3d.editor.undone", "through_formal_control": true, "failure_closed": true}
	_set_status("已撤销最近一次CombatCatalog编辑。", true)
	_refresh_details()

func _redo_editor_action() -> void:
	_control_events.append("redo")
	if editor_undo_redo == null:
		_fail("combat.3d.editor.redo_missing", "EditorUndoRedoManager不可用，重做已拒绝。")
		return
	var history := editor_undo_redo.get_history_undo_redo(editor_undo_redo.get_object_history_id(self))
	if history == null or not history.has_redo():
		_fail("combat.3d.editor.history_empty", "当前战斗编辑没有可重做历史。")
		return
	history.redo()
	_last_operation = {"ok": true, "code": "combat.3d.editor.redone", "through_formal_control": true, "failure_closed": true}
	_set_status("已重做CombatCatalog编辑。", true)
	_refresh_details()

func _save_catalog() -> Dictionary:
	if catalog == null:
		return _fail("combat.3d.editor.catalog_missing", "没有可保存的CombatCatalog。")
	var identity_check := _validate_formal_identity()
	if not identity_check.ok:
		return _fail("combat.3d.editor.identity_invalid", "正式控件中的身份尚未应用，未保存。", {"validation": identity_check})
	var path := str((_controls["save_path"] as LineEdit).text).strip_edges()
	if path.is_empty():
		return _fail("combat.3d.editor.save_path_missing", "CombatCatalog保存路径不能为空。")
	var check: Dictionary = catalog.validate()
	if not check.ok:
		return _fail("combat.3d.editor.catalog_invalid", "CombatCatalog校验失败，未保存。", {"validation": check})
	var error := ResourceSaver.save(catalog, path)
	if error != OK:
		return _fail("combat.3d.editor.save_failed", "CombatCatalog保存失败，旧状态保持不变。", {"error": error, "path": path})
	_catalog_path = path
	_last_save_restore["saved"] = {"ok": true, "path": path, "catalog_id": catalog.catalog_id, "identity": _formal_identity(), "parameters": _formal_parameters()}
	_last_operation = {"ok": true, "code": "combat.3d.editor.catalog_saved", "path": path, "catalog_id": catalog.catalog_id, "identity": _formal_identity(), "parameters": _formal_parameters(), "through_formal_control": true, "failure_closed": true}
	_set_status("CombatCatalog已保存。", true)
	_refresh_details()
	return _last_operation.duplicate(true)

func _close_preview() -> Dictionary:
	if target_point != null:
		target_point.hide()
	if volume != null:
		volume.hide()
	_last_save_restore["closed"] = {"ok": true, "preview_cleared": true, "catalog_retained": catalog != null}
	_last_operation = {"ok": true, "code": "combat.3d.editor.preview_closed", "through_formal_control": true, "failure_closed": true}
	_set_status("3D战斗预览已关闭，CombatCatalog仍保留。", true)
	_refresh_details()
	return _last_operation.duplicate(true)

func _reopen_catalog() -> Dictionary:
	var path := str((_controls["save_path"] as LineEdit).text).strip_edges()
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded is GMCombatCatalog:
		return _fail("combat.3d.editor.reopen_failed", "重新打开CombatCatalog失败，当前关闭状态保持不变。", {"path": path})
	var check: Dictionary = loaded.validate()
	if not check.ok:
		return _fail("combat.3d.editor.reopen_invalid", "重新打开的CombatCatalog校验失败。", {"validation": check})
	_catalog_resource = loaded
	catalog = loaded
	if target_point != null:
		target_point.show()
	if volume != null:
		volume.show()
	_catalog_path = path
	_last_save_restore["reopened"] = {"ok": true, "path": path, "catalog_id": catalog.catalog_id, "cache_mode": "CACHE_MODE_IGNORE", "identity": _formal_identity(), "parameters": _formal_parameters()}
	_last_operation = {"ok": true, "code": "combat.3d.editor.catalog_reopened", "path": path, "catalog_id": catalog.catalog_id, "identity": _formal_identity(), "parameters": _formal_parameters(), "through_formal_control": true, "failure_closed": true}
	_set_status("CombatCatalog已关闭后重新打开。", true)
	_refresh_details()
	return _last_operation.duplicate(true)

func _commit_catalog_state(candidate: Dictionary, action_name: String) -> Dictionary:
	var parsed := CATALOG_SCRIPT.from_native(candidate)
	if not parsed.ok:
		return _fail("combat.3d.editor.catalog_candidate_invalid", "CombatCatalog候选未通过严格校验，旧状态保持不变。", {"validation": parsed})
	var before := _catalog_state()
	if before == candidate:
		return {"ok": true, "code": "combat.3d.editor.idempotent", "changed": false, "through_formal_control": true}
	if editor_undo_redo != null and not _applying_editor_state:
		editor_undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, self)
		editor_undo_redo.add_do_method(self, "_apply_catalog_state", candidate.duplicate(true))
		editor_undo_redo.add_undo_method(self, "_apply_catalog_state", before.duplicate(true))
		editor_undo_redo.commit_action()
	else:
		_apply_catalog_state(candidate)
	return {"ok": true, "code": "combat.3d.editor.catalog_committed", "changed": true, "through_formal_control": true, "failure_closed": true}

func _apply_catalog_state(value: Dictionary) -> void:
	_applying_editor_state = true
	var parsed := CATALOG_SCRIPT.from_native(value)
	if parsed.ok:
		if _catalog_resource == null:
			_catalog_resource = CATALOG_SCRIPT.new()
		_catalog_resource.schema_version = parsed.value.schema_version
		_catalog_resource.catalog_id = parsed.value.catalog_id
		_catalog_resource.display_name_zh = parsed.value.display_name_zh
		_catalog_resource.revision = parsed.value.revision
		_catalog_resource.attacks = parsed.value.attacks.duplicate(true)
		_catalog_resource.weapons = parsed.value.weapons.duplicate(true)
		_catalog_resource.projectiles = parsed.value.projectiles.duplicate(true)
		catalog = _catalog_resource
	_last_operation = {"ok": parsed.ok, "code": "combat.3d.editor.state_applied" if parsed.ok else "combat.3d.editor.state_rejected", "through_formal_control": true, "failure_closed": true}
	_applying_editor_state = false
	_refresh_details()

func _catalog_state() -> Dictionary:
	return catalog.to_native().duplicate(true) if catalog != null else {}

func _number(control_id: String, fallback: float) -> float:
	if not _controls.has(control_id):
		return fallback
	var line := _controls[control_id] as LineEdit
	if line == null:
		return fallback
	var raw := str(line.text).strip_edges()
	var parsed := raw.to_float()
	return parsed if is_finite(parsed) else fallback

func _set_status(message: String, ok: bool) -> void:
	if _status == null:
		return
	_status.text = message
	_status.modulate = Color("7dffad") if ok else Color("ff9b7d")

func _refresh_details() -> void:
	if _details == null:
		return
	_details.text = "[b]正式身份[/b]\n%s\n\n[b]正式参数[/b]\n%s\n\n[b]CombatCatalog[/b]\n%s\n\n[b]TargetPoint / HitVolume[/b]\n%s\n%s\n\n[b]最近候选 / 校验[/b]\n%s\n%s\n\n[b]保存恢复[/b]\n%s" % [JSON.stringify(_formal_identity(), "  "), JSON.stringify(_formal_parameters(), "  "), JSON.stringify(_catalog_state(), "  "), JSON.stringify(target_point.to_native() if target_point != null else {}, "  "), JSON.stringify(volume.to_native() if volume != null else {}, "  "), JSON.stringify(_last_candidate, "  "), JSON.stringify(_last_validation, "  "), JSON.stringify(_last_save_restore, "  ")]

func _fail(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	_last_operation = {"ok": false, "code": code, "reason_zh": reason_zh, "details": details.duplicate(true), "failure_closed": true, "through_formal_control": true}
	_set_status("%s [%s]" % [reason_zh, code], false)
	_refresh_details()
	return _last_operation.duplicate(true)

func get_capture_snapshot() -> Dictionary:
	return {
		"ui_source_formal": true,
		"ui_root_script": "res://addons/gm_editor/combat3d/gm_planar_combat_3d_dock.gd",
		"ui_root_class": "GMPlanarCombat3DDock",
		"formal_path": "GM编辑器 → 平面战斗与Cue3D → HitVolume / TargetPoint / Projectile / AoE",
		"formal_controls": _controls.keys(),
		"control_values": _formal_control_values(),
		"control_events": _control_events.duplicate(),
		"formal_identity": _formal_identity(),
		"formal_parameters": _formal_parameters(),
		"through_formal_controls": true,
		"undo_gateway": "EditorUndoRedoManager" if editor_undo_redo != null else "missing",
		"preview": {"subviewport": is_instance_valid(_preview_viewport), "container": is_instance_valid(_preview_container), "world_node": is_instance_valid(_preview_world), "area3d": is_instance_valid(volume), "shape3d": volume != null and volume.get_node_or_null("GMHitVolumeShape3D") is CollisionShape3D, "target_point3d": is_instance_valid(target_point)},
		"catalog": _catalog_state(),
		"candidate": _last_candidate.duplicate(true),
		"validation": _last_validation.duplicate(true),
		"save_close_reopen": _last_save_restore.duplicate(true),
		"single_rule_owner": "gm.resolver.combat",
		"domain_facts_written": false,
		"failure_closed": true,
		"substitute_ui": false,
		"direct_success_action_calls": _direct_success_action_calls,
	}

func _press(control_id: String) -> bool:
	if not _controls.has(control_id) or not _controls[control_id] is Button:
		return false
	(_controls[control_id] as Button).pressed.emit()
	return true

func _set_probe_control(control_id: String, value: String) -> void:
	if not _controls.has(control_id):
		return
	var line := _controls[control_id] as LineEdit
	if line == null:
		return
	line.text = value
	_control_events.append("input:%s" % control_id)

func _configure_directed_probe_controls() -> Dictionary:
	var values := {
		"ability_id": "gm.ability.ext3d07.directed.rework",
		"seed": "gm.ext3d07.directed.seed.13",
		"catalog_id": "gm.combat.catalog.ext3d07.directed.rework",
		"attack_id": "gm.attack.ext3d07.directed.arc",
		"volume_id": "gm.hit_volume.ext3d07.directed.rework",
		"source_id": "gm.actor.ext3d07.directed.source",
		"target_id": "gm.actor.ext3d07.directed.target",
		"map_id": "gm.map.ext3d07.directed",
		"graph_id": "gm.graph.ext3d07.directed",
		"surface_id": "gm.surface.ext3d07.directed.floor",
		"target_point_id": "gm.target_point.ext3d07.directed.target",
		"anchor_id": "gm.anchor.ext3d07.directed.target",
		"save_path": "user://gm_ext_3d_07_directed_rework_catalog.tres",
		"attack_magnitude": "13.0",
		"attack_range": "9.5",
		"volume_radius": "0.85",
		"height_tolerance": "0.60",
		"source_x": "2.0",
		"source_y": "1.5",
		"target_x": "6.0",
		"target_y": "0.35",
		"target_z": "5.0",
	}
	for raw_control_id in values.keys():
		var control_id := str(raw_control_id)
		_set_probe_control(control_id, str(values[raw_control_id]))
	return _formal_control_values()

func run_ext_3d_07_editor_probe() -> Dictionary:
	if editor_undo_redo == null or _controls.is_empty():
		return {"ok": false, "event": "GM_EXT_3D_07_EDITOR_SENTINEL", "code": "combat.3d.editor_controls_missing", "through_formal_controls": false, "direct_success_action_calls": 0, "substitute_ui": false}
	_control_events.clear()
	var configured_identity := _configure_directed_probe_controls()
	var configured_parameters := _formal_parameters()
	_press("new")
	var new_operation := _last_operation.duplicate(true)
	var before_edit := GMStableData.digest(_catalog_state())
	_set_probe_control("catalog_id", "gm.combat.catalog.ext3d07.directed.rework.edit")
	var apply_pressed := _press("apply")
	var committed := _last_operation.duplicate(true) if apply_pressed else {"ok": false, "code": "combat.3d.editor.apply_not_pressed"}
	var after_edit := GMStableData.digest(_catalog_state())
	var undo_pressed := _press("undo")
	var after_undo := GMStableData.digest(_catalog_state())
	var redo_pressed := _press("redo")
	var after_redo := GMStableData.digest(_catalog_state())
	var undo_redo_ok := apply_pressed and undo_pressed and redo_pressed and before_edit != after_edit and before_edit == after_undo and after_edit == after_redo
	var final_identity := _formal_identity()
	var final_parameters := _formal_parameters()
	var execution_sample_identity := {
		"ability_id": DEFAULT_ABILITY_ID,
		"seed": DEFAULT_SEED,
		"catalog_id": "gm.combat.catalog.ext3d07.editor.probe",
		"attack_id": DEFAULT_ATTACK_ID,
		"volume_id": DEFAULT_VOLUME_ID,
		"source_id": DEFAULT_SOURCE_ID,
		"target_id": DEFAULT_TARGET_ID,
		"map_id": MAP_ID,
		"graph_id": GRAPH_ID,
		"surface_id": SURFACE_ID,
		"target_point_id": DEFAULT_TARGET_POINT_ID,
		"anchor_id": DEFAULT_ANCHOR_ID,
		"save_path": DEFAULT_SAVE_PATH,
	}
	var identity_independent := true
	for raw_key in execution_sample_identity.keys():
		var key := str(raw_key)
		if str(final_identity.get(key, "")) == str(execution_sample_identity[raw_key]):
			identity_independent = false
	var execution_sample_parameters := {"attack_magnitude": DEFAULT_ATTACK_MAGNITUDE, "attack_range": DEFAULT_ATTACK_RANGE, "volume_radius": DEFAULT_VOLUME_RADIUS, "height_tolerance": 0.75, "source_x": 1.0, "source_y": 1.0, "target_x": 4.0, "target_y": 0.0, "target_z": 4.0}
	var parameters_independent := true
	for raw_key in execution_sample_parameters.keys():
		var parameter_key := str(raw_key)
		if is_equal_approx(float(final_parameters.get(parameter_key, 0.0)), float(execution_sample_parameters[raw_key])):
			parameters_independent = false
	_press("candidate")
	var candidate := _last_candidate.duplicate(true)
	_press("validate")
	var validation := _last_validation.duplicate(true)
	_press("bad_height")
	var bad_height := _last_operation.duplicate(true)
	var bad_candidate := _last_candidate.duplicate(true)
	var bad_query := adapter.query(bad_candidate.get("hit_spec", null), bad_candidate.get("query_context", {})) if bad_candidate.get("ok", false) else {"ok": false, "code": "combat.3d.editor.candidate_missing"}
	_press("restore_height")
	_press("candidate")
	var restored_candidate := _last_candidate.duplicate(true)
	var missing_target := adapter.query(restored_candidate.get("hit_spec", null), {"source_position": restored_candidate.get("query_context", {}).get("source_position", {}), "target_position": restored_candidate.get("query_context", {}).get("target_position", {})}) if restored_candidate.get("ok", false) else {"ok": false, "code": "combat.3d.editor.candidate_missing"}
	_press("save")
	var saved := _last_operation.duplicate(true)
	_press("close")
	var closed := _last_operation.duplicate(true)
	_press("reopen")
	var reopened := _last_operation.duplicate(true)
	var save_close_reopen_ok := bool(saved.get("ok", false)) and bool(closed.get("ok", false)) and bool(reopened.get("ok", false)) and catalog != null
	var result := {
		"ok": bool(committed.get("ok", false)) and undo_redo_ok and bool(candidate.get("ok", false)) and bool(validation.get("ok", false)) and not bool(bad_query.get("ok", false)) and str(bad_query.get("code", "")) == "combat.3d.height_tolerance_exceeded" and not bool(missing_target.get("ok", false)) and str(missing_target.get("code", "")) == "combat.3d.target_point_missing" and save_close_reopen_ok,
		"event": "GM_EXT_3D_07_EDITOR_SENTINEL",
		"through_formal_controls": true,
		"direct_success_action_calls": _direct_success_action_calls,
		"formal_path": "GM编辑器 → 平面战斗与Cue3D → HitVolume / TargetPoint / Projectile / AoE",
		"probe_input": {"identity": final_identity, "parameters": final_parameters, "configured_identity": configured_identity, "configured_parameters": configured_parameters, "different_from_execution_sample": identity_independent and parameters_independent, "identity_different_from_execution_sample": identity_independent, "parameters_different_from_execution_sample": parameters_independent, "execution_sample_identity": execution_sample_identity, "execution_sample_parameters": execution_sample_parameters, "source": "正式Dock LineEdit控件与Button pressed信号"},
		"operations": {"new": new_operation, "apply": committed, "candidate": candidate, "validation": validation, "bad_height": bad_height, "bad_candidate": bad_candidate, "bad_query": bad_query, "missing_target": missing_target, "restored_candidate": restored_candidate},
		"undo_redo": {"ok": undo_redo_ok, "before": before_edit, "after_edit": after_edit, "after_undo": after_undo, "after_redo": after_redo, "gateway": "EditorUndoRedoManager"},
		"save_close_reopen": {"ok": save_close_reopen_ok, "saved": saved, "closed": closed, "reopened": reopened, "identity": final_identity, "save_path": str(final_identity.get("save_path", ""))},
		"snapshot": get_capture_snapshot(),
		"single_rule_owner": "gm.resolver.combat",
		"domain_facts_written": false,
		"substitute_ui": false,
	}
	_last_operation["probe"] = result
	_refresh_details()
	return result
