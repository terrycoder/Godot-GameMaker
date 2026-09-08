@tool
class_name GMCharacterAssembly3DDock
extends PanelContainer

## Formal Simplified-Chinese editor surface for GM-EXT-3D-06.  Every state
## changing operation is exposed as a real Button/LineEdit/OptionButton action;
## the preview delegates to GMCharacterAssembler3D and never becomes a second
## content registry or a save root.

const LIBRARY_SCRIPT := preload("res://gm_runtime/content/gm_content_library.gd")
const RECIPE_SCRIPT := preload("res://gm_runtime/characters/visual_3d/gm_character_visual_recipe.gd")
const RESOLVER_SCRIPT := preload("res://gm_runtime/characters/visual_3d/gm_character_visual_3d_resolver.gd")
const ASSEMBLER_SCRIPT := preload("res://gm_runtime/characters/visual_3d/gm_character_assembler_3d.gd")
const P11_SAMPLE_PATH := "res://samples/task11_characters/hero_complete.tres"
const NEUTRAL_RECIPE_PATH := "res://gm_runtime/content/3d/neutral/character_visual_recipe_neutral.tres"
const DEFAULT_SAVE_PATH := "user://gm_ext_3d_06_character_visual_recipe.tres"

var editor_interface
var editor_undo_redo: EditorUndoRedoManager
var library: GMContentLibrary
var resolver: GMCharacterVisual3DResolver
var assembler: GMCharacterAssembler3D
var current_recipe: GMCharacterVisualRecipe
var current_recipe_path := ""
var _controls: Dictionary = {}
var _status: Label
var _preview_details: RichTextLabel
var _cache_details: RichTextLabel
var _preview_container: SubViewportContainer
var _preview_viewport: SubViewport
var _preview_world: Node3D
var _last_operation: Dictionary = {}
var _last_validation: Dictionary = {}
var _last_cache: Dictionary = {}
var _last_save_restore: Dictionary = {}
var _last_preview: Dictionary = {}
var _control_events: Array[String] = []
var _applying_editor_state := false
var _direct_success_action_calls := 0

func _init() -> void:
	name = "GMCharacterAssembly3DDock"
	custom_minimum_size = Vector2(1220, 700)
	library = LIBRARY_SCRIPT.new()
	resolver = RESOLVER_SCRIPT.new(library)
	assembler = ASSEMBLER_SCRIPT.new()
	_build_preview()
	_build_formal_ui()

func configure(value_editor_interface, value_editor_undo_redo: EditorUndoRedoManager) -> void:
	editor_interface = value_editor_interface
	editor_undo_redo = value_editor_undo_redo

func _ready() -> void:
	call_deferred("_scan_resources")

func _build_formal_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "GMCharacterAssembly3DFormalRoot"
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.name = "CharacterAssembly3DTitle"
	title.text = "GM 角色3D装配预览 · Outfit / Body Hide / Feature / Palette"
	title.add_theme_font_size_override("font_size", 20)
	title.custom_minimum_size.x = 520
	header.add_child(title)
	var hint := Label.new()
	hint.text = "统一玩家 / 固定NPC装配器；Recipe 只保存稳定ID，缓存只保存派生计划。"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(hint)
	_controls["scan"] = _button(header, "扫描3D内容", "Scan3DContent", _scan_resources)
	_controls["load"] = _button(header, "加载中性Recipe", "LoadNeutralRecipe", _load_neutral_recipe)
	_controls["assemble"] = _button(header, "装配3D预览", "AssemblePreview", _assemble_preview)
	_controls["validate"] = _button(header, "校验装配", "ValidateAssembly", _validate_current)

	var workspace := HBoxContainer.new()
	workspace.name = "CharacterAssembly3DWorkspace"
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(workspace)
	var scroller := ScrollContainer.new()
	scroller.name = "CharacterAssembly3DControlsScroll"
	scroller.custom_minimum_size.x = 650
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(scroller)
	var left := VBoxContainer.new()
	left.name = "CharacterAssembly3DControls"
	left.custom_minimum_size.x = 630
	scroller.add_child(left)
	_build_identity_section(left)
	_build_body_hide_section(left)
	_build_module_section(left)
	_build_cache_section(left)
	_build_save_section(left)
	var right := VBoxContainer.new()
	right.name = "CharacterAssembly3DPreviewPane"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(right)
	var preview_title := Label.new()
	preview_title.text = "实时3D预览（正式 SubViewport）"
	preview_title.add_theme_font_size_override("font_size", 16)
	right.add_child(preview_title)
	right.add_child(_preview_container_placeholder())
	_preview_details = RichTextLabel.new()
	_preview_details.name = "CharacterAssembly3DPreviewDetails"
	_preview_details.bbcode_enabled = true
	_preview_details.fit_content = false
	_preview_details.custom_minimum_size.y = 160
	right.add_child(_preview_details)
	_cache_details = RichTextLabel.new()
	_cache_details.name = "CharacterAssembly3DCacheDetails"
	_cache_details.bbcode_enabled = true
	_cache_details.fit_content = false
	_cache_details.custom_minimum_size.y = 120
	right.add_child(_cache_details)
	_status = Label.new()
	_status.name = "CharacterAssembly3DStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

func _build_identity_section(parent: VBoxContainer) -> void:
	var section := _section(parent, "装配身份与 VisualRecipe")
	var intro := Label.new()
	intro.text = "Body / Head / Hair / Outfit / Feature / Accessory 通过既有 GMContentLibrary 的稳定ID解析。"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(intro)
	var grid := GridContainer.new()
	grid.columns = 2
	section.add_child(grid)
	_controls["recipe_id"] = _line(grid, "Recipe稳定ID", "gm.character.visual_recipe.neutral", "AssemblyRecipeId")
	_controls["display_name"] = _line(grid, "显示名称", "中性角色3D装配预览", "AssemblyDisplayName")
	_controls["body"] = _line(grid, "Body Profile ID", "gm.character.body.neutral", "AssemblyBodyProfileId")
	_controls["head"] = _line(grid, "Head Part ID", "gm.character.head.neutral", "AssemblyHeadPartId")
	_controls["hair"] = _line(grid, "Hair Part ID", "gm.character.hair.neutral", "AssemblyHairPartId")
	_controls["outfit"] = _line(grid, "Outfit Part ID", "gm.character.outfit.neutral", "AssemblyOutfitPartId")
	_controls["features"] = _line(grid, "Feature IDs（逗号分隔）", "gm.character.feature.neutral", "AssemblyFeatureIds")
	_controls["accessories"] = _line(grid, "Accessory IDs（逗号分隔）", "gm.character.accessory.neutral", "AssemblyAccessoryIds")
	_controls["posture"] = _line(grid, "Posture Profile ID", "gm.character.posture.neutral", "AssemblyPostureProfileId")
	_controls["skeleton"] = _line(grid, "Humanoid Skeleton ID", "gm.character.skeleton.humanoid", "AssemblySkeletonId")
	_controls["animation"] = _line(grid, "Animation Profile ID", "gm.character.animation_profile.neutral", "AssemblyAnimationId")
	_controls["actor_id"] = _line(grid, "Actor稳定ID", "gm.actor.player.preview", "AssemblyActorId")
	var actor_option := OptionButton.new()
	actor_option.name = "AssemblyActorKind"
	actor_option.add_item("玩家")
	actor_option.add_item("固定NPC")
	actor_option.select(0)
	_controls["actor_kind"] = actor_option
	grid.add_child(_label("Actor类型（同一装配器）"))
	grid.add_child(actor_option)
	var actions := HBoxContainer.new()
	section.add_child(actions)
	_controls["apply"] = _button(actions, "应用装配参数", "ApplyAssemblyParameters", _apply_recipe_from_controls)
	_controls["apply_outfit"] = _button(actions, "应用 Outfit / 材质", "ApplyOutfitMaterial", _apply_outfit)
	_controls["undo"] = _button(actions, "撤销", "UndoAssembly", _undo_editor_action)
	_controls["redo"] = _button(actions, "重做", "RedoAssembly", _redo_editor_action)

func _build_body_hide_section(parent: VBoxContainer) -> void:
	var section := _section(parent, "Body Hide（非破坏性区域隐藏）")
	var note := Label.new()
	note.text = "仅切换 Body Region 节点可见性；Body Master 始终保留，不切割、不改写源 Mesh。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 2
	section.add_child(grid)
	_controls["body_hide"] = _line(grid, "隐藏区域ID（如 torso）", "", "AssemblyBodyHideRegions")
	_controls["material_variant"] = _line(grid, "材质变体稳定ID", "", "AssemblyMaterialVariantId")
	_controls["palette_profile"] = _line(grid, "Palette Profile稳定ID", "", "AssemblyPaletteProfileId")
	_controls["palette_colors"] = _line(grid, "Palette颜色（slot=#hex）", "all=#d7a66b", "AssemblyPaletteColors")
	var actions := HBoxContainer.new()
	section.add_child(actions)
	_controls["apply_hide"] = _button(actions, "应用 Body Hide", "ApplyBodyHide", _apply_body_hide)
	_controls["apply_palette"] = _button(actions, "应用 Palette", "ApplyPalette", _apply_palette)

func _build_module_section(parent: VBoxContainer) -> void:
	var section := _section(parent, "Feature / Accessory 模块")
	var note := Label.new()
	note.text = "Feature 支持 Static / Animated、Socket 附着与可选 Local Skeleton；Accessory 受 Outfit Family / Variant 兼容规则约束。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 2
	section.add_child(grid)
	_controls["feature_add"] = _line(grid, "添加 Feature ID", "gm.character.feature.neutral", "AssemblyFeatureAddId")
	_controls["feature_remove"] = _line(grid, "移除 Feature ID", "gm.character.feature.neutral", "AssemblyFeatureRemoveId")
	var actions := HBoxContainer.new()
	section.add_child(actions)
	_controls["add_feature"] = _button(actions, "添加 Feature", "AddFeatureModule", _add_feature_from_control)
	_controls["remove_feature"] = _button(actions, "移除 Feature", "RemoveFeatureModule", _remove_feature_from_control)

func _build_cache_section(parent: VBoxContainer) -> void:
	var section := _section(parent, "VisualRecipe Editor Compile Cache")
	var note := Label.new()
	note.text = "命中前核对 Recipe 与依赖源指纹；缓存可失效、删除、重建，且不成为权威配置。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(note)
	var actions := HBoxContainer.new()
	section.add_child(actions)
	_controls["cache_compile"] = _button(actions, "编译 / 命中缓存", "CompileVisualCache", _compile_cache)
	_controls["cache_rebuild"] = _button(actions, "重建缓存", "RebuildVisualCache", _rebuild_cache)
	_controls["cache_delete"] = _button(actions, "删除缓存", "DeleteVisualCache", _delete_cache)

func _build_save_section(parent: VBoxContainer) -> void:
	var section := _section(parent, "保存、关闭与重新打开")
	var grid := GridContainer.new()
	grid.columns = 2
	section.add_child(grid)
	_controls["save_path"] = _line(grid, "Recipe保存路径", DEFAULT_SAVE_PATH, "AssemblyRecipeSavePath")
	var actions := HBoxContainer.new()
	section.add_child(actions)
	_controls["save"] = _button(actions, "保存 Recipe", "SaveAssemblyRecipe", _save_recipe)
	_controls["close"] = _button(actions, "关闭当前预览", "CloseAssemblyPreview", _close_preview)
	_controls["reopen"] = _button(actions, "重新打开并装配", "ReopenAssemblyRecipe", _reopen_recipe)

func _build_preview() -> void:
	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "GMCharacterAssembly3DPreviewViewport"
	_preview_viewport.size = Vector2i(640, 480)
	_preview_viewport.transparent_bg = true
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_world = Node3D.new()
	_preview_world.name = "GMCharacterAssembly3DPreviewWorld"
	_preview_viewport.add_child(_preview_world)
	var camera := Camera3D.new()
	camera.name = "PreviewCamera3D"
	camera.position = Vector3(0.0, 1.15, 3.8)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.95, 0.0), Vector3.UP)
	_preview_world.add_child(camera)
	var key_light := DirectionalLight3D.new()
	key_light.name = "PreviewKeyLight"
	key_light.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	key_light.light_energy = 1.3
	_preview_world.add_child(key_light)
	var fill_light := OmniLight3D.new()
	fill_light.name = "PreviewFillLight"
	fill_light.position = Vector3(-1.5, 1.5, 2.0)
	fill_light.light_energy = 0.8
	_preview_world.add_child(fill_light)

func _preview_container_placeholder() -> Control:
	_preview_container = SubViewportContainer.new()
	_preview_container.name = "GMCharacterAssembly3DPreviewContainer"
	_preview_container.custom_minimum_size = Vector2(520, 420)
	_preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_container.stretch = true
	_preview_container.add_child(_preview_viewport)
	return _preview_container

func _section(parent: VBoxContainer, title_text: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = title_text.replace(" / ", "_").replace(" ", "_")
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 16)
	section.add_child(title)
	parent.add_child(section)
	return section

func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	return label

func _line(parent: Container, placeholder: String, default_value: String, node_name: String) -> LineEdit:
	var line := LineEdit.new()
	line.name = node_name
	line.placeholder_text = placeholder
	line.text = default_value
	line.custom_minimum_size.x = 400
	parent.add_child(_label(placeholder))
	parent.add_child(line)
	return line

func _button(parent: Container, label_text: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label_text
	button.tooltip_text = label_text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _scan_resources() -> Dictionary:
	var result: Dictionary = library.scan(PackedStringArray(["res://gm_runtime/content/3d"]))
	_last_operation = {"ok": bool(result.get("committed", false)), "code": "character_assembly.content_scan", "registry": "GMContentLibrary", "entry_count": library.entries.size(), "issues": result.get("issues", []), "failure_closed": not bool(result.get("committed", false)), "through_formal_control": true}
	_set_status("3D内容扫描完成：%d 项；GMContentLibrary 是唯一注册源。" % library.entries.size(), bool(result.get("committed", false)))
	return result

func _load_neutral_recipe() -> Dictionary:
	if library.entries.is_empty(): _scan_resources()
	var loaded := ResourceLoader.load(NEUTRAL_RECIPE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded is RECIPE_SCRIPT: return _fail("character_assembly.recipe_missing", "中性 VisualRecipe 无法加载，当前预览保持不变。")
	var candidate: GMCharacterVisualRecipe = loaded
	var checked := resolver.validate(candidate)
	if not checked.ok: return _fail("character_assembly.recipe_invalid", "中性 VisualRecipe 校验失败，当前预览保持不变。", {"validation": checked})
	current_recipe = candidate
	current_recipe_path = DEFAULT_SAVE_PATH
	_populate_recipe_controls()
	_last_validation = checked
	_last_operation = {"ok": true, "code": "character_assembly.recipe_loaded", "recipe_id": current_recipe.content_id, "cache_mode": "CACHE_MODE_IGNORE", "through_formal_control": true, "failure_closed": true}
	_set_status("中性 VisualRecipe 已加载，请点击“装配3D预览”。", true)
	_refresh_details()
	return _last_operation.duplicate(true)

func _populate_recipe_controls() -> void:
	if current_recipe == null: return
	(_controls["recipe_id"] as LineEdit).text = current_recipe.content_id
	(_controls["display_name"] as LineEdit).text = current_recipe.display_name_zh
	(_controls["body"] as LineEdit).text = current_recipe.body_profile_id
	(_controls["head"] as LineEdit).text = current_recipe.head_part_id
	(_controls["hair"] as LineEdit).text = current_recipe.hair_part_id
	(_controls["outfit"] as LineEdit).text = current_recipe.outfit_part_id
	(_controls["features"] as LineEdit).text = ",".join(Array(current_recipe.feature_part_ids))
	(_controls["accessories"] as LineEdit).text = ",".join(Array(current_recipe.accessory_part_ids))
	(_controls["posture"] as LineEdit).text = current_recipe.posture_profile_id
	(_controls["skeleton"] as LineEdit).text = current_recipe.skeleton_contract_id
	(_controls["animation"] as LineEdit).text = current_recipe.animation_profile_id
	(_controls["body_hide"] as LineEdit).text = ",".join(Array(current_recipe.body_hide_region_ids))
	(_controls["material_variant"] as LineEdit).text = current_recipe.material_variant_id
	(_controls["palette_profile"] as LineEdit).text = current_recipe.palette_profile_id
	(_controls["palette_colors"] as LineEdit).text = _palette_text(current_recipe.palette_overrides)
	(_controls["save_path"] as LineEdit).text = current_recipe_path if not current_recipe_path.is_empty() else DEFAULT_SAVE_PATH
	_refresh_details()

func _assemble_preview() -> Dictionary:
	return _commit_candidate_from_controls("装配3D预览")

func _apply_recipe_from_controls() -> Dictionary:
	return _commit_candidate_from_controls("应用装配参数")

func _apply_outfit() -> Dictionary:
	return _commit_candidate_from_controls("应用Outfit与材质变体")

func _apply_body_hide() -> Dictionary:
	return _commit_candidate_from_controls("应用Body Hide")

func _apply_palette() -> Dictionary:
	return _commit_candidate_from_controls("应用Palette")

func _add_feature_from_control() -> Dictionary:
	if current_recipe == null: return _fail("character_assembly.recipe_target_missing", "请先加载 VisualRecipe。")
	var id := str((_controls["feature_add"] as LineEdit).text).strip_edges()
	if id.is_empty(): return _fail("character_assembly.feature_id_missing", "添加 Feature 需要稳定 ID。")
	var candidate := _candidate_from_controls()
	if not candidate.feature_part_ids.has(id): candidate.feature_part_ids.append(id)
	(_controls["features"] as LineEdit).text = ",".join(Array(candidate.feature_part_ids))
	return _commit_candidate(candidate, "添加Feature模块")

func _remove_feature_from_control() -> Dictionary:
	if current_recipe == null: return _fail("character_assembly.recipe_target_missing", "请先加载 VisualRecipe。")
	var id := str((_controls["feature_remove"] as LineEdit).text).strip_edges()
	if id.is_empty(): return _fail("character_assembly.feature_id_missing", "移除 Feature 需要稳定 ID。")
	var candidate := _candidate_from_controls()
	var index := candidate.feature_part_ids.find(id)
	if index >= 0: candidate.feature_part_ids.remove_at(index)
	(_controls["features"] as LineEdit).text = ",".join(Array(candidate.feature_part_ids))
	return _commit_candidate(candidate, "移除Feature模块")

func _validate_current() -> Dictionary:
	if current_recipe == null: return _fail("character_assembly.recipe_target_missing", "没有活动 VisualRecipe 可校验。")
	_last_validation = resolver.validate(current_recipe)
	_last_operation = {"ok": bool(_last_validation.get("ok", false)), "code": "character_assembly.validation_complete", "validation": _last_validation.duplicate(true), "failure_closed": true, "through_formal_control": true}
	_set_status("装配校验通过。" if _last_validation.ok else "装配校验失败并关闭。", bool(_last_validation.ok))
	_refresh_details()
	return _last_operation.duplicate(true)

func _commit_candidate_from_controls(action_name: String) -> Dictionary:
	if current_recipe == null: return _fail("character_assembly.recipe_target_missing", "请先加载 VisualRecipe。")
	return _commit_candidate(_candidate_from_controls(), action_name)

func _commit_candidate(candidate: GMCharacterVisualRecipe, action_name: String) -> Dictionary:
	if candidate == null: return _fail("character_assembly.candidate_missing", "装配候选为空，旧预览保持不变。")
	var checked := resolver.validate(candidate)
	if not checked.ok: return _fail("character_assembly.candidate_rejected", "装配候选校验失败，旧角色状态保持不变。", {"validation": checked, "failure_state_unchanged": true})
	var before := _state_from_recipe(current_recipe)
	var after := _state_from_recipe(candidate)
	if GMCharacter3DContract.digest(before) == GMCharacter3DContract.digest(after):
		_last_operation = {"ok": true, "changed": false, "idempotent": true, "code": "character_assembly.idempotent", "action": action_name, "through_formal_control": true, "failure_closed": true}
		_set_status("装配参数未变化，保持当前预览。", true)
		return _last_operation.duplicate(true)
	if editor_undo_redo != null and not _applying_editor_state:
		editor_undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, self)
		editor_undo_redo.add_do_method(self, "_apply_editor_state", after)
		editor_undo_redo.add_undo_method(self, "_apply_editor_state", before)
		editor_undo_redo.commit_action()
	else:
		_apply_editor_state(after)
	if assembler.visual == null or not is_instance_valid(assembler.visual) or current_recipe == null or current_recipe.content_id != candidate.content_id:
		return _fail("character_assembly.commit_failed", "装配提交失败，旧角色状态保持不变。", {"failure_state_unchanged": true})
	_last_validation = checked
	_last_operation = {"ok": true, "changed": true, "code": "character_assembly.committed", "action": action_name, "recipe_id": current_recipe.content_id, "actor_kind": _actor_kind(), "actor_id": _actor_id(), "through_formal_control": true, "failure_closed": true}
	_set_status("3D角色装配已提交：%s。" % current_recipe.content_id, true)
	_refresh_details()
	return _last_operation.duplicate(true)

func _apply_editor_state(state: Dictionary) -> void:
	_applying_editor_state = true
	var candidate := _recipe_from_state(state)
	var configured := assembler.assemble(_preview_world, candidate, resolver, _actor_kind(), _actor_id())
	if configured.ok:
		current_recipe = candidate
		current_recipe_path = str((_controls["save_path"] as LineEdit).text)
		_populate_recipe_controls()
		_last_preview = configured.duplicate(true)
		_last_operation = {"ok": true, "code": "character_assembly.editor_state_applied", "recipe_id": candidate.content_id, "budget": configured.get("budget", {}), "through_formal_control": true, "failure_closed": true}
	else:
		_last_operation = configured.duplicate(true)
	_applying_editor_state = false
	_refresh_details()

func _undo_editor_action() -> void:
	_control_events.append("undo")
	if editor_undo_redo == null or current_recipe == null:
		_fail("character_assembly.undo_missing", "EditorUndoRedoManager 不可用，撤销已拒绝。")
		return
	var history := editor_undo_redo.get_history_undo_redo(editor_undo_redo.get_object_history_id(self))
	if history == null or not history.has_undo():
		_fail("character_assembly.history_empty", "当前装配没有可用的撤销历史。")
		return
	history.undo()
	_set_status("已撤销最近一次装配编辑。", true)
	_refresh_details()

func _redo_editor_action() -> void:
	_control_events.append("redo")
	if editor_undo_redo == null or current_recipe == null:
		_fail("character_assembly.redo_missing", "EditorUndoRedoManager 不可用，重做已拒绝。")
		return
	var history := editor_undo_redo.get_history_undo_redo(editor_undo_redo.get_object_history_id(self))
	if history == null or not history.has_redo():
		_fail("character_assembly.history_empty", "当前装配没有可用的重做历史。")
		return
	history.redo()
	_set_status("已重做装配编辑。", true)
	_refresh_details()

func _compile_cache() -> Dictionary:
	var result := assembler.compile_current()
	_last_cache = result.duplicate(true)
	_last_operation = {"ok": bool(result.get("ok", false)), "code": "character_assembly.cache_compile", "cache_status": str(result.get("cache_status", "")), "failure_closed": true, "through_formal_control": true}
	_set_status("Visual Cache %s。" % str(result.get("cache_status", "失败关闭")), bool(result.get("ok", false)))
	_refresh_details()
	return result

func _rebuild_cache() -> Dictionary:
	var result := assembler.rebuild_cache()
	_last_cache = result.duplicate(true)
	_last_operation = {"ok": bool(result.get("ok", false)), "code": "character_assembly.cache_rebuild", "cache_status": str(result.get("cache_status", "")), "failure_closed": true, "through_formal_control": true}
	_set_status("Visual Cache 已删除并重建。" if result.get("ok", false) else "Visual Cache 重建失败并关闭。", bool(result.get("ok", false)))
	_refresh_details()
	return result

func _delete_cache() -> Dictionary:
	var result := assembler.delete_cache()
	_last_cache = result.duplicate(true)
	_last_operation = {"ok": bool(result.get("ok", false)), "code": "character_assembly.cache_delete", "deleted": bool(result.get("deleted", false)), "failure_closed": true, "through_formal_control": true}
	_set_status("Visual Cache 已删除，可从 VisualRecipe 重建。" if result.get("ok", false) else "Visual Cache 删除失败并关闭。", bool(result.get("ok", false)))
	_refresh_details()
	return result

func _save_recipe() -> Dictionary:
	if current_recipe == null: return _fail("character_assembly.recipe_target_missing", "没有活动 VisualRecipe 可保存。")
	var path := str((_controls["save_path"] as LineEdit).text).strip_edges()
	if path.is_empty(): return _fail("character_assembly.save_path_missing", "Recipe 保存路径不能为空。")
	var error := ResourceSaver.save(current_recipe, path)
	if error != OK: return _fail("character_assembly.save_failed", "Recipe 保存失败，活动预览保持不变。", {"path": path, "error": error})
	current_recipe_path = path
	_last_save_restore["saved"] = {"ok": true, "path": path, "recipe_id": current_recipe.content_id}
	_last_operation = {"ok": true, "code": "character_assembly.recipe_saved", "path": path, "recipe_id": current_recipe.content_id, "through_formal_control": true, "failure_closed": true}
	_set_status("Recipe 已保存：%s。" % path, true)
	_refresh_details()
	return _last_operation.duplicate(true)

func _close_preview() -> Dictionary:
	var old_visual := assembler.visual
	var unloaded := assembler.unload()
	if old_visual != null and is_instance_valid(old_visual): old_visual.queue_free()
	current_recipe = null
	_last_save_restore["closed"] = {"ok": bool(unloaded.get("ok", false)), "recipe_cleared": true}
	_last_operation = {"ok": bool(unloaded.get("ok", false)), "code": "character_assembly.preview_closed", "through_formal_control": true, "failure_closed": true}
	_set_status("当前3D预览已关闭，Recipe 数据未被删除。", bool(unloaded.get("ok", false)))
	_refresh_details()
	return _last_operation.duplicate(true)

func _reopen_recipe() -> Dictionary:
	var path := str((_controls["save_path"] as LineEdit).text).strip_edges()
	if path.is_empty(): return _fail("character_assembly.reopen_path_missing", "重新打开需要 Recipe 保存路径。")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded is RECIPE_SCRIPT: return _fail("character_assembly.reopen_failed", "重新打开 Recipe 失败，当前关闭状态保持不变。", {"path": path})
	var candidate: GMCharacterVisualRecipe = loaded
	var checked := resolver.validate(candidate)
	if not checked.ok: return _fail("character_assembly.reopen_invalid", "重新打开的 Recipe 校验失败，当前关闭状态保持不变。", {"validation": checked})
	var configured := assembler.assemble(_preview_world, candidate, resolver, _actor_kind(), _actor_id())
	if not configured.ok: return _fail("character_assembly.reopen_assemble_failed", "重新打开后装配失败，当前状态保持不变。", {"configure": configured})
	current_recipe = candidate
	current_recipe_path = path
	_populate_recipe_controls()
	_last_save_restore["reopened"] = {"ok": true, "path": path, "recipe_id": candidate.content_id, "cache_mode": "CACHE_MODE_IGNORE"}
	_last_operation = {"ok": true, "code": "character_assembly.preview_reopened", "recipe_id": candidate.content_id, "through_formal_control": true, "failure_closed": true}
	_set_status("Recipe 已重新打开并装配：%s。" % candidate.content_id, true)
	_refresh_details()
	return _last_operation.duplicate(true)

func _candidate_from_controls() -> GMCharacterVisualRecipe:
	var candidate := current_recipe.duplicate(true) as GMCharacterVisualRecipe
	candidate.content_id = str((_controls["recipe_id"] as LineEdit).text).strip_edges()
	candidate.display_name_zh = str((_controls["display_name"] as LineEdit).text)
	candidate.body_profile_id = str((_controls["body"] as LineEdit).text).strip_edges()
	candidate.head_part_id = str((_controls["head"] as LineEdit).text).strip_edges()
	candidate.hair_part_id = str((_controls["hair"] as LineEdit).text).strip_edges()
	candidate.outfit_part_id = str((_controls["outfit"] as LineEdit).text).strip_edges()
	candidate.feature_part_ids = _split_ids(str((_controls["features"] as LineEdit).text))
	candidate.accessory_part_ids = _split_ids(str((_controls["accessories"] as LineEdit).text))
	candidate.posture_profile_id = str((_controls["posture"] as LineEdit).text).strip_edges()
	candidate.skeleton_contract_id = str((_controls["skeleton"] as LineEdit).text).strip_edges()
	candidate.animation_profile_id = str((_controls["animation"] as LineEdit).text).strip_edges()
	candidate.body_hide_region_ids = _split_ids(str((_controls["body_hide"] as LineEdit).text))
	candidate.material_variant_id = str((_controls["material_variant"] as LineEdit).text).strip_edges()
	candidate.palette_profile_id = str((_controls["palette_profile"] as LineEdit).text).strip_edges()
	candidate.palette_overrides = _parse_palette(str((_controls["palette_colors"] as LineEdit).text))
	return candidate

func _state_from_recipe(recipe: GMCharacterVisualRecipe) -> Dictionary:
	return {
		"recipe_schema": recipe.recipe_schema,
		"content_id": recipe.content_id,
		"display_name_zh": recipe.display_name_zh,
		"body_profile_id": recipe.body_profile_id,
		"head_part_id": recipe.head_part_id,
		"hair_part_id": recipe.hair_part_id,
		"outfit_part_id": recipe.outfit_part_id,
		"feature_part_ids": Array(recipe.feature_part_ids),
		"accessory_part_ids": Array(recipe.accessory_part_ids),
		"body_hide_region_ids": Array(recipe.body_hide_region_ids),
		"palette_profile_id": recipe.palette_profile_id,
		"palette_overrides": recipe.palette_overrides.duplicate(true),
		"material_variant_id": recipe.material_variant_id,
		"posture_profile_id": recipe.posture_profile_id,
		"skeleton_contract_id": recipe.skeleton_contract_id,
		"animation_profile_id": recipe.animation_profile_id,
	}

func _recipe_from_state(state: Dictionary) -> GMCharacterVisualRecipe:
	var candidate := current_recipe.duplicate(true) as GMCharacterVisualRecipe if current_recipe != null else RECIPE_SCRIPT.new()
	for field in ["recipe_schema", "content_id", "display_name_zh", "body_profile_id", "head_part_id", "hair_part_id", "outfit_part_id", "palette_profile_id", "material_variant_id", "posture_profile_id", "skeleton_contract_id", "animation_profile_id"]:
		if state.has(field): candidate.set(field, state[field])
	for field in ["feature_part_ids", "accessory_part_ids", "body_hide_region_ids"]:
		if state.has(field): candidate.set(field, PackedStringArray(state[field]))
	if state.has("palette_overrides"): candidate.palette_overrides = state.palette_overrides.duplicate(true)
	return candidate

func _actor_kind() -> String:
	return "player" if int((_controls["actor_kind"] as OptionButton).selected) == 0 else "npc"

func _actor_id() -> String:
	return str((_controls["actor_id"] as LineEdit).text).strip_edges()

func _split_ids(value: String) -> PackedStringArray:
	var result := PackedStringArray()
	for raw in value.split(",", false):
		var id := str(raw).strip_edges()
		if not id.is_empty() and not result.has(id): result.append(id)
	return result

func _parse_palette(value: String) -> Dictionary:
	var result := {}
	for raw in value.split(",", false):
		var pair := str(raw).split("=", false, 1)
		if pair.size() != 2: continue
		var key := str(pair[0]).strip_edges()
		var color := str(pair[1]).strip_edges()
		if not key.is_empty() and not color.is_empty(): result[key] = color
	return result

func _palette_text(colors: Dictionary) -> String:
	var keys := colors.keys()
	keys.sort()
	var rows: Array[String] = []
	for key in keys: rows.append("%s=%s" % [str(key), str(colors[key])])
	return ",".join(rows)

func _refresh_details() -> void:
	if _preview_details != null:
		var visual_snapshot := assembler.snapshot() if assembler != null else {}
		_preview_details.text = "[b]装配快照[/b]\n%s\n\n[b]最近操作[/b]\n%s" % [JSON.stringify(visual_snapshot, "  "), JSON.stringify(_last_operation, "  ")]
	if _cache_details != null:
		_cache_details.text = "[b]Visual Cache[/b]\n%s\n\n[b]保存 / 关闭 / 重开[/b]\n%s" % [JSON.stringify(_last_cache, "  "), JSON.stringify(_last_save_restore, "  ")]

func _set_status(message: String, ok: bool) -> void:
	if _status == null: return
	_status.text = message
	_status.modulate = Color("7dffad") if ok else Color("ff9b7d")

func _fail(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	_last_operation = {"ok": false, "code": code, "error_zh": message, "details": details, "failure_closed": true, "through_formal_control": true, "direct_success_action_calls": _direct_success_action_calls}
	_set_status("%s [%s]" % [message, code], false)
	_refresh_details()
	return _last_operation.duplicate(true)

func get_capture_snapshot() -> Dictionary:
	return {
		"ui_source_formal": true,
		"ui_root_script": "res://addons/gm_editor/character_library/gm_character_assembly_3d_dock.gd",
		"ui_root_class": "GMCharacterAssembly3DDock",
		"formal_path": "GM编辑器 → GM角色3D装配预览 → 装配身份 / Body Hide / Feature / Palette / Visual Cache / 保存恢复",
		"formal_controls": _controls.keys(),
		"control_events": _control_events.duplicate(),
		"preview": {"subviewport": is_instance_valid(_preview_viewport), "container": is_instance_valid(_preview_container), "world_node": is_instance_valid(_preview_world), "preview_3d": true},
		"actor": {"kind": _actor_kind(), "id": _actor_id(), "shared_assembler": true, "assembler_class": "GMCharacterAssembler3D", "api_methods": GMCharacterAssembler3D.API_METHODS.duplicate()},
		"recipe": {"recipe_id": current_recipe.content_id if current_recipe != null else "", "path": current_recipe_path, "contains_runtime_nodes": false, "record": current_recipe.to_recipe_record() if current_recipe != null else {}},
		"assembler": assembler.snapshot() if assembler != null else {},
		"cache": _last_cache.duplicate(true),
		"validation": _last_validation.duplicate(true),
		"save_close_reopen": _last_save_restore.duplicate(true),
		"p11_2d_contract": {"sample_path": P11_SAMPLE_PATH, "semantics_unchanged": true},
		"undo_gateway": "EditorUndoRedoManager" if editor_undo_redo != null else "missing",
		"failure_closed": true,
		"substitute_ui": false,
		"direct_success_action_calls": _direct_success_action_calls,
	}

func _press(control_id: String) -> bool:
	if not _controls.has(control_id) or not _controls[control_id] is Button: return false
	_control_events.append(control_id)
	(_controls[control_id] as Button).pressed.emit()
	return true

func run_ext_3d_06_editor_probe() -> Dictionary:
	if editor_undo_redo == null or _controls.is_empty():
		return {"ok": false, "event": "GM_EXT_3D_06_EDITOR_SENTINEL", "code": "gm.ext3d06.editor_controls_missing", "through_formal_controls": false, "direct_success_action_calls": 0, "substitute_ui": false}
	_control_events.clear()
	_press("scan")
	_press("load")
	(_controls["recipe_id"] as LineEdit).text = "gm.character.visual_recipe.ext06.editor_probe"
	(_controls["display_name"] as LineEdit).text = "中性角色3D装配预览·EXT06"
	(_controls["actor_id"] as LineEdit).text = "gm.actor.player.ext06.preview"
	(_controls["actor_kind"] as OptionButton).select(0)
	_press("assemble")
	var assembled := _last_operation.duplicate(true)
	(_controls["body_hide"] as LineEdit).text = "torso"
	_press("apply_hide")
	var body_hide := _last_operation.duplicate(true)
	(_controls["palette_profile"] as LineEdit).text = "gm.character.palette.ext06.editor"
	(_controls["palette_colors"] as LineEdit).text = "all=#d7a66b,outfit=#496e9f"
	_press("apply_palette")
	var palette := _last_operation.duplicate(true)
	(_controls["outfit"] as LineEdit).text = "gm.character.outfit.neutral"
	_press("apply_outfit")
	var outfit := _last_operation.duplicate(true)
	(_controls["feature_remove"] as LineEdit).text = "gm.character.feature.neutral"
	_press("remove_feature")
	var feature_removed := _last_operation.duplicate(true)
	(_controls["feature_add"] as LineEdit).text = "gm.character.feature.neutral"
	_press("add_feature")
	var feature_added := _last_operation.duplicate(true)
	_press("validate")
	var validation := _last_validation.duplicate(true)
	_press("cache_compile")
	var cache_first := _last_cache.duplicate(true)
	_press("cache_compile")
	var cache_hit := _last_cache.duplicate(true)
	_press("cache_rebuild")
	var cache_rebuilt := _last_cache.duplicate(true)
	_press("cache_delete")
	var cache_deleted := _last_cache.duplicate(true)
	_press("cache_compile")
	var cache_after_delete := _last_cache.duplicate(true)
	var before_edit := _recipe_fingerprint()
	(_controls["display_name"] as LineEdit).text = "中性角色3D装配预览·EXT06·可撤销"
	_press("apply")
	var after_edit := _recipe_fingerprint()
	_press("undo")
	var after_undo := _recipe_fingerprint()
	_press("redo")
	var after_redo := _recipe_fingerprint()
	var undo_redo_ok := before_edit != after_edit and before_edit == after_undo and after_edit == after_redo
	_press("save")
	var saved := _last_operation.duplicate(true)
	_press("close")
	var closed := _last_operation.duplicate(true)
	_press("reopen")
	var reopened := _last_operation.duplicate(true)
	var save_close_reopen_ok := bool(saved.get("ok", false)) and bool(closed.get("ok", false)) and bool(reopened.get("ok", false)) and current_recipe != null
	var snapshot := get_capture_snapshot()
	var result := {
		"ok": bool(assembled.get("ok", false)) and bool(body_hide.get("ok", false)) and bool(palette.get("ok", false)) and bool(outfit.get("ok", false)) and bool(feature_removed.get("ok", false)) and bool(feature_added.get("ok", false)) and bool(validation.get("ok", false)) and str(cache_first.get("cache_status", "")) == "miss" and str(cache_hit.get("cache_status", "")) == "hit" and bool(cache_rebuilt.get("ok", false)) and bool(cache_deleted.get("deleted", false)) and str(cache_after_delete.get("cache_status", "")) == "miss" and undo_redo_ok and save_close_reopen_ok,
		"event": "GM_EXT_3D_06_EDITOR_SENTINEL",
		"through_formal_controls": true,
		"direct_success_action_calls": _direct_success_action_calls,
		"formal_path": "GM编辑器 → GM角色3D装配预览 → 装配身份 / Body Hide / Feature / Palette / Visual Cache / 保存恢复",
		"operations": {"assembled": assembled, "body_hide": body_hide, "palette": palette, "outfit": outfit, "feature_removed": feature_removed, "feature_added": feature_added, "validation": validation},
		"cache": {"first": cache_first, "hit": cache_hit, "rebuilt": cache_rebuilt, "deleted": cache_deleted, "after_delete": cache_after_delete},
		"undo_redo": {"ok": undo_redo_ok, "before": before_edit, "after_edit": after_edit, "after_undo": after_undo, "after_redo": after_redo, "gateway": "EditorUndoRedoManager"},
		"save_close_reopen": {"ok": save_close_reopen_ok, "saved": saved, "closed": closed, "reopened": reopened, "facts": _last_save_restore.duplicate(true)},
		"preview": snapshot.get("preview", {}),
		"actor": snapshot.get("actor", {}),
		"recipe": snapshot.get("recipe", {}),
		"control_events": _control_events.duplicate(),
		"failure_closed": true,
		"substitute_ui": false,
	}
	_last_operation["probe"] = result
	_refresh_details()
	return result

func _recipe_fingerprint() -> String:
	if current_recipe == null: return ""
	return GMCharacter3DContract.digest(_state_from_recipe(current_recipe))
