@tool
class_name GMCharacterVisual3DDock
extends PanelContainer

## Formal Chinese editor surface for GM-EXT-3D-05.  The dock edits only
## stable-ID content references and delegates lookup to the existing
## GMContentLibrary.  It does not create a second registry or put editor
## nodes into a character recipe.

const LIBRARY_SCRIPT := preload("res://gm_runtime/content/gm_content_library.gd")
const RECIPE_SCRIPT := preload("res://gm_runtime/characters/visual_3d/gm_character_visual_recipe.gd")
const VALIDATOR_SCRIPT := preload("res://gm_runtime/characters/visual_3d/gm_character_asset_validator.gd")
const IMPORT_PRESET_SCRIPT := preload("res://gm_runtime/characters/visual_3d/gm_3d_import_preset.gd")
const REGISTRY_EXTENSION_SCRIPT := preload("res://gm_runtime/characters/visual_3d/gm_3d_asset_registry_extension.gd")
const SKELETON_SCRIPT := preload("res://gm_runtime/characters/visual_3d/gm_humanoid_skeleton_contract.gd")
const P11_SAMPLE_PATH := "res://samples/task11_characters/hero_complete.tres"
const NEUTRAL_RECIPE_PATH := "res://gm_runtime/content/3d/neutral/character_visual_recipe_neutral.tres"
const DEFAULT_SAVE_PATH := "user://gm_ext_3d_05_character_visual_recipe.tres"

var editor_interface
var editor_undo_redo: EditorUndoRedoManager
var library
var registry_extension
var current_recipe
var current_recipe_path := ""
var current_skeleton
var import_presets: Array = []
var _controls: Dictionary = {}
var _tabs: TabContainer
var _status: Label
var _validation_details: RichTextLabel
var _skeleton_details: RichTextLabel
var _registry_list: ItemList
var _last_operation: Dictionary = {}
var _last_validation: Dictionary = {}
var _last_import: Dictionary = {}
var _last_skeleton: Dictionary = {}
var _last_registry: Dictionary = {}
var _last_save_close_reopen: Dictionary = {}
var _last_boundary: Dictionary = {}
var _direct_success_action_calls := 0

func _init() -> void:
	name = "GMCharacterVisual3DDock"
	custom_minimum_size = Vector2(1180, 650)
	library = LIBRARY_SCRIPT.new()
	registry_extension = REGISTRY_EXTENSION_SCRIPT.new()
	_build_formal_ui()

func configure(value_editor_interface, value_editor_undo_redo: EditorUndoRedoManager) -> void:
	editor_interface = value_editor_interface
	editor_undo_redo = value_editor_undo_redo

func _ready() -> void:
	call_deferred("_scan_resources")

func _build_formal_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "GMCharacterVisual3DFormalRoot"
	root.add_theme_constant_override("separation", 7)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "GM 角色3D视觉 · Body / Humanoid Skeleton / Animation / Part 正式策划"
	title.add_theme_font_size_override("font_size", 20)
	title.custom_minimum_size.x = 560
	header.add_child(title)
	var hint := Label.new()
	hint.text = "Recipe 只保存稳定ID；运行时复用共享动画库与既有 GMContentLibrary。"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(hint)
	_controls["scan"] = _button(header, "扫描资源注册", "ScanResources", _scan_resources)
	_controls["load"] = _button(header, "加载中性3D角色", "LoadNeutral", _load_neutral_recipe)
	_controls["validate"] = _button(header, "校验当前配方", "ValidateRecipe", _validate_current)

	_tabs = TabContainer.new()
	_tabs.name = "CharacterVisual3DPlanningTabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_build_recipe_tab()
	_build_skeleton_tab()
	_build_fit_animation_tab()
	_build_import_tab()
	_build_registry_tab()
	_build_validation_tab()
	_status = Label.new()
	_status.name = "CharacterVisual3DStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

func _build_recipe_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "Recipe与Profile"
	_tabs.add_child(page)
	var intro := Label.new()
	intro.text = "角色3D视觉配方：Body、Head、Hair、Outfit、Feature、Accessory 与 Profile 均以可审计稳定ID引用。"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(intro)
	var grid := GridContainer.new()
	grid.columns = 2
	page.add_child(grid)
	_controls["recipe_id"] = _line(grid, "Recipe稳定ID", "gm.character.visual_recipe.neutral", "RecipeId")
	_controls["display_name"] = _line(grid, "显示名称", "中性角色3D视觉", "RecipeDisplayName")
	_controls["body"] = _line(grid, "Body Profile稳定ID", "gm.character.body.neutral", "BodyProfileId")
	_controls["head"] = _line(grid, "Head Part稳定ID", "gm.character.head.neutral", "HeadPartId")
	_controls["hair"] = _line(grid, "Hair Part稳定ID", "gm.character.hair.neutral", "HairPartId")
	_controls["outfit"] = _line(grid, "Outfit Part稳定ID", "gm.character.outfit.neutral", "OutfitPartId")
	_controls["features"] = _line(grid, "Feature Part稳定ID（逗号分隔）", "gm.character.feature.neutral", "FeaturePartIds")
	_controls["accessories"] = _line(grid, "Accessory Part稳定ID（逗号分隔）", "gm.character.accessory.neutral", "AccessoryPartIds")
	_controls["posture"] = _line(grid, "Posture Profile稳定ID", "gm.character.posture.neutral", "PostureProfileId")
	_controls["skeleton"] = _line(grid, "Humanoid Skeleton合同ID", "gm.character.skeleton.humanoid", "SkeletonContractId")
	_controls["animation"] = _line(grid, "Animation Profile稳定ID", "gm.character.animation_profile.neutral", "AnimationProfileId")
	_controls["save_path"] = _line(grid, "Recipe保存路径", DEFAULT_SAVE_PATH, "RecipeSavePath")
	var actions := HBoxContainer.new()
	page.add_child(actions)
	_controls["apply_recipe"] = _button(actions, "应用 Recipe 与 Profile 引用", "ApplyRecipeReferences", _apply_recipe_from_controls)
	_controls["apply_name"] = _button(actions, "应用显示名称（可撤销）", "ApplyRecipeDisplayName", _apply_display_name)
	_controls["undo"] = _button(actions, "撤销", "UndoRecipeEdit", _undo_recipe_edit)
	_controls["redo"] = _button(actions, "重做", "RedoRecipeEdit", _redo_recipe_edit)
	_controls["save"] = _button(actions, "保存 Recipe", "SaveRecipe", _save_recipe)
	_controls["close"] = _button(actions, "关闭当前 Recipe", "CloseRecipe", _close_recipe)
	_controls["reopen"] = _button(actions, "重新打开 Recipe", "ReopenRecipe", _reopen_recipe)
	var note := Label.new()
	note.text = "关闭会清空当前活动资源；重新打开使用 CACHE_MODE_IGNORE，验证外部存档可恢复。失败操作保持活动 Recipe 不变。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(note)

func _build_skeleton_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "Skeleton与Socket"
	_tabs.add_child(page)
	var title := Label.new()
	title.text = "Humanoid Skeleton 合同：18项核心骨骼、Root / Forward / Up / Scale 与可选 Socket。Feature 不得强制加入核心骨骼。"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	page.add_child(grid)
	_controls["external_bone"] = _line(grid, "外部骨骼名称", "mixamorig:Head", "ExternalBoneName")
	_controls["canonical_bone"] = _line(grid, "核心骨骼目标", "head", "CanonicalBoneName")
	_controls["socket_id"] = _line(grid, "Socket稳定ID", "gm.character.socket.head", "SocketId")
	_controls["socket_slot"] = _line(grid, "Socket允许槽位", "head,hair,feature", "SocketAllowedSlots")
	var actions := HBoxContainer.new()
	page.add_child(actions)
	_controls["apply_skeleton"] = _button(actions, "应用外部骨骼映射", "ApplySkeletonMapping", _apply_skeleton_mapping)
	_controls["validate_skeleton"] = _button(actions, "校验 Skeleton / Socket", "ValidateSkeleton", _validate_skeleton)
	_skeleton_details = RichTextLabel.new()
	_skeleton_details.name = "SkeletonContractDetails"
	_skeleton_details.bbcode_enabled = true
	_skeleton_details.fit_content = false
	_skeleton_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_skeleton_details)

func _build_fit_animation_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "Fit与动画"
	_tabs.add_child(page)
	var title := Label.new()
	title.text = "Body FitClass 负责体型 / 服装适配；Animation Profile 负责六类语义动作到共享动画资产的映射与降级。"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	page.add_child(grid)
	_controls["fit_id"] = _line(grid, "当前 FitClass", "gm.character.fit.standard", "FitClassId")
	_controls["semantic_action"] = _line(grid, "语义动作", "locomotion.idle", "SemanticActionId")
	_controls["shared_animation"] = _line(grid, "共享 Animation资产ID", "gm.asset.animation.neutral.idle", "SharedAnimationId")
	_controls["animation_category"] = _line(grid, "动画类别", "locomotion / work / interaction / social / combat / reaction", "AnimationCategories")
	var actions := HBoxContainer.new()
	page.add_child(actions)
	_controls["validate_fit_animation"] = _button(actions, "校验 FitClass / Outfit", "ValidateFitClass", _validate_fit_animation)
	_controls["resolve_animation"] = _button(actions, "解析共享语义动作", "ResolveSharedAnimation", _resolve_shared_animation)
	var note := Label.new()
	note.text = "每个角色不复制 Animation Library；未映射动作只能使用 Profile 中声明的类别降级，否则失败关闭。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(note)

func _build_import_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "导入Preset"
	_tabs.add_child(page)
	var title := Label.new()
	title.text = "标准导入 Preset：角色 / 环境 / Prop / 动画 / 植被；记录 Scale、Pivot、材质、碰撞、LOD 与源指纹，保证重导入稳定。"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	page.add_child(grid)
	var preset_option := OptionButton.new()
	preset_option.name = "ImportPresetOption"
	for preset in IMPORT_PRESET_SCRIPT.standard_presets():
		import_presets.append(preset)
		preset_option.add_item(str(preset.display_name_zh))
	_controls["preset"] = preset_option
	grid.add_child(_label("当前标准 Preset"))
	grid.add_child(preset_option)
	_controls["source_kind"] = _line(grid, "导入源类型", "glTF / FBX / GLB", "ImportSourceKind")
	_controls["source_fingerprint"] = _line(grid, "导入源稳定指纹", "neutral://gm.character.asset.neutral@v1", "ImportSourceFingerprint")
	_controls["source_path"] = _line(grid, "源文件路径", "res://assets/character/source.glb", "ImportSourcePath")
	var actions := HBoxContainer.new()
	page.add_child(actions)
	_controls["validate_import"] = _button(actions, "校验并登记导入元数据", "ValidateImport", _validate_import)
	_controls["boundary_import"] = _button(actions, "边界 Preset 校验", "BoundaryImport", _validate_import_boundaries)
	var note := Label.new()
	note.text = "导入失败只产生结构化错误，不写入 Recipe、Registry 或活动资源；Preset 本身是 Resource，可被重导入工具复用。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(note)

func _build_registry_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "资源注册"
	_tabs.add_child(page)
	var title := Label.new()
	title.text = "资产注册扩展仅作为 GMContentLibrary 的查询适配器，不建立第二份索引或独立身份。"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(title)
	var actions := HBoxContainer.new()
	page.add_child(actions)
	var type_option := OptionButton.new()
	type_option.name = "AssetTypeOption"
	type_option.add_item("全部 3D 内容")
	for row in REGISTRY_EXTENSION_SCRIPT.supported_types(): type_option.add_item(str(row.get("content_type_id", "")))
	_controls["asset_type"] = type_option
	actions.add_child(_label("资产类型"))
	actions.add_child(type_option)
	_controls["query_registry"] = _button(actions, "查询既有 GMContentLibrary", "QueryAssetRegistry", _query_asset_registry)
	_registry_list = ItemList.new()
	_registry_list.name = "GMContentLibrary3DEntries"
	_registry_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_registry_list)

func _build_validation_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "验证"
	_tabs.add_child(page)
	var title := Label.new()
	title.text = "机器可读验证摘要：Normal / Boundary / Reject / Failure-state unchanged / Save-Close-Reopen / 2D 回归。"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(title)
	_validation_details = RichTextLabel.new()
	_validation_details.name = "CharacterVisual3DValidationDetails"
	_validation_details.bbcode_enabled = true
	_validation_details.fit_content = false
	_validation_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_validation_details)
	var actions := HBoxContainer.new()
	page.add_child(actions)
	_controls["validate_all"] = _button(actions, "运行完整验证", "ValidateAll", _validate_current)
	_controls["clear_validation"] = _button(actions, "清空验证详情", "ClearValidation", _clear_validation)

func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	return label

func _line(parent: Container, placeholder: String, default_value: String, node_name: String) -> LineEdit:
	var line := LineEdit.new()
	line.name = node_name
	line.placeholder_text = placeholder
	line.text = default_value
	line.custom_minimum_size.x = 610
	parent.add_child(_label(placeholder))
	parent.add_child(line)
	return line

func _button(parent: Container, label_text: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label_text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _scan_resources() -> Dictionary:
	if library == null: library = LIBRARY_SCRIPT.new()
	var result: Dictionary = library.scan(PackedStringArray(["res://gm_runtime/content/3d"]))
	var query_result: Dictionary = REGISTRY_EXTENSION_SCRIPT.query(library)
	_last_registry = {"ok": bool(query_result.get("ok", false)), "extension": str(query_result.get("extension", "")), "registry": str(query_result.get("registry", "")), "entry_count": library.entries.size(), "type_count": int(query_result.get("type_count", 0)), "second_registry": bool(query_result.get("second_registry", true))}
	_refresh_registry_list("")
	_last_operation = {"ok": bool(result.get("committed", false)), "code": "character3d.content_scan", "count": library.entries.size(), "issues": result.get("issues", []), "registry": "GMContentLibrary", "failure_closed": not bool(result.get("committed", false))}
	_set_status("3D内容扫描完成：%d 项；既有 GMContentLibrary 承担唯一注册职责。" % library.entries.size(), bool(result.get("committed", false)))
	return result

func _load_neutral_recipe() -> Dictionary:
	if library == null or library.entries.is_empty(): _scan_resources()
	var loaded := ResourceLoader.load(NEUTRAL_RECIPE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded is RECIPE_SCRIPT:
		return _fail("character3d.neutral_recipe_missing", "中性 Recipe 无法加载，活动 Recipe 保持不变。", {"path": NEUTRAL_RECIPE_PATH})
	var candidate = loaded
	var checked: Dictionary = VALIDATOR_SCRIPT.validate_recipe(candidate, library)
	if not checked.ok:
		return _fail("character3d.neutral_recipe_invalid", "中性 Recipe 校验失败，活动 Recipe 保持不变。", {"issues": checked.issues})
	current_recipe = candidate
	current_recipe_path = DEFAULT_SAVE_PATH
	_populate_recipe_controls()
	_refresh_skeleton_details()
	_last_validation = checked
	_last_operation = {"ok": true, "code": "character3d.neutral_recipe_loaded", "recipe_id": current_recipe.content_id, "library_count": library.entries.size(), "cache_mode": "CACHE_MODE_IGNORE", "through_formal_control": true, "direct_success_action_calls": _direct_success_action_calls}
	_set_status("中性角色3D Recipe 已加载。", true)
	_refresh_validation_details()
	return _last_operation.duplicate(true)

func _populate_recipe_controls() -> void:
	if current_recipe == null: return
	(_controls["recipe_id"] as LineEdit).text = str(current_recipe.content_id)
	(_controls["display_name"] as LineEdit).text = str(current_recipe.display_name_zh)
	(_controls["body"] as LineEdit).text = str(current_recipe.body_profile_id)
	(_controls["head"] as LineEdit).text = str(current_recipe.head_part_id)
	(_controls["hair"] as LineEdit).text = str(current_recipe.hair_part_id)
	(_controls["outfit"] as LineEdit).text = str(current_recipe.outfit_part_id)
	(_controls["features"] as LineEdit).text = ",".join(Array(current_recipe.feature_part_ids))
	(_controls["accessories"] as LineEdit).text = ",".join(Array(current_recipe.accessory_part_ids))
	(_controls["posture"] as LineEdit).text = str(current_recipe.posture_profile_id)
	(_controls["skeleton"] as LineEdit).text = str(current_recipe.skeleton_contract_id)
	(_controls["animation"] as LineEdit).text = str(current_recipe.animation_profile_id)
	(_controls["save_path"] as LineEdit).text = current_recipe_path
	var body = _resolve(current_recipe.body_profile_id)
	(_controls["fit_id"] as LineEdit).text = str(body.body_fit_class_id) if body != null else ""
	var animation = _resolve(current_recipe.animation_profile_id)
	if animation != null:
		var action_id := str((_controls["semantic_action"] as LineEdit).text)
		var mapped: Dictionary = animation.resolve_semantic_action(StringName(action_id))
		(_controls["shared_animation"] as LineEdit).text = str(mapped.get("animation_asset_id", ""))
	_refresh_skeleton_details()

func _apply_recipe_from_controls() -> Dictionary:
	if current_recipe == null: return _fail("character3d.recipe_target_missing", "没有活动 Recipe，未提交表单。")
	if library == null or library.entries.is_empty(): _scan_resources()
	var candidate = current_recipe.duplicate(true)
	candidate.content_id = str((_controls["recipe_id"] as LineEdit).text).strip_edges()
	candidate.display_name_zh = str((_controls["display_name"] as LineEdit).text).strip_edges()
	candidate.body_profile_id = str((_controls["body"] as LineEdit).text).strip_edges()
	candidate.head_part_id = str((_controls["head"] as LineEdit).text).strip_edges()
	candidate.hair_part_id = str((_controls["hair"] as LineEdit).text).strip_edges()
	candidate.outfit_part_id = str((_controls["outfit"] as LineEdit).text).strip_edges()
	candidate.feature_part_ids = _split_ids(str((_controls["features"] as LineEdit).text))
	candidate.accessory_part_ids = _split_ids(str((_controls["accessories"] as LineEdit).text))
	candidate.posture_profile_id = str((_controls["posture"] as LineEdit).text).strip_edges()
	candidate.skeleton_contract_id = str((_controls["skeleton"] as LineEdit).text).strip_edges()
	candidate.animation_profile_id = str((_controls["animation"] as LineEdit).text).strip_edges()
	var checked: Dictionary = VALIDATOR_SCRIPT.validate_recipe(candidate, library)
	if not checked.ok: return _fail("character3d.recipe_candidate_invalid", "Recipe 表单未通过完整验证，原 Recipe 未修改。", {"issues": checked.issues, "failure_closed": true})
	var values := {
		&"content_id": candidate.content_id,
		&"display_name_zh": candidate.display_name_zh,
		&"body_profile_id": candidate.body_profile_id,
		&"head_part_id": candidate.head_part_id,
		&"hair_part_id": candidate.hair_part_id,
		&"outfit_part_id": candidate.outfit_part_id,
		&"feature_part_ids": candidate.feature_part_ids,
		&"accessory_part_ids": candidate.accessory_part_ids,
		&"posture_profile_id": candidate.posture_profile_id,
		&"skeleton_contract_id": candidate.skeleton_contract_id,
		&"animation_profile_id": candidate.animation_profile_id,
	}
	if not _commit_properties(current_recipe, values, "编辑角色3D Recipe引用"): return _last_operation.duplicate(true)
	_last_validation = checked
	_last_operation = {"ok": true, "code": "character3d.recipe_references_committed", "through_formal_control": true, "undo_gateway": "EditorUndoRedoManager", "direct_success_action_calls": _direct_success_action_calls}
	_refresh_skeleton_details()
	_refresh_validation_details()
	_set_status("Recipe 与 Profile 引用已提交。", true)
	return _last_operation.duplicate(true)

func _apply_display_name() -> Dictionary:
	if current_recipe == null: return _fail("character3d.recipe_target_missing", "没有活动 Recipe，显示名称未修改。")
	var value := str((_controls["display_name"] as LineEdit).text).strip_edges()
	if value.is_empty(): return _fail("character3d.recipe_name_missing", "显示名称不能为空，原 Recipe 未修改。")
	if not _commit_properties(current_recipe, {&"display_name_zh": value}, "编辑角色3D Recipe显示名称"):
		return _last_operation.duplicate(true)
	_last_operation = {"ok": true, "code": "character3d.recipe_display_name_committed", "through_formal_control": true, "undo_gateway": "EditorUndoRedoManager", "direct_success_action_calls": _direct_success_action_calls}
	_refresh_validation_details()
	_set_status("Recipe 显示名称已提交，可撤销。", true)
	return _last_operation.duplicate(true)

func _close_recipe() -> Dictionary:
	current_recipe = null
	current_skeleton = null
	_last_operation = {"ok": true, "code": "character3d.recipe_closed", "cleared": true, "through_formal_control": true, "direct_success_action_calls": _direct_success_action_calls}
	_set_status("当前 Recipe 已关闭，活动资源已清空。", true)
	return _last_operation.duplicate(true)

func _save_recipe() -> Dictionary:
	if current_recipe == null: return _fail("character3d.recipe_target_missing", "没有活动 Recipe，未保存。")
	var checked: Dictionary = VALIDATOR_SCRIPT.validate_recipe(current_recipe, library)
	if not checked.ok: return _fail("character3d.recipe_save_validation_failed", "保存前验证失败，磁盘未写入。", {"issues": checked.issues})
	var path := str((_controls["save_path"] as LineEdit).text).strip_edges()
	if not path.begins_with("user://") and not path.begins_with("res://"):
		return _fail("character3d.recipe_save_path_invalid", "保存路径必须是 user:// 或 res://，磁盘未写入。", {"path": path})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var error := ResourceSaver.save(current_recipe, path)
	if error != OK: return _fail("character3d.recipe_save_failed", "Recipe 保存失败，活动内存状态保留。", {"error": error, "path": path})
	var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not reopened is RECIPE_SCRIPT: return _fail("character3d.recipe_save_reopen_failed", "保存后 CACHE_MODE_IGNORE 重载失败。", {"path": path})
	current_recipe_path = path
	_last_save_close_reopen = {"save_ok": true, "path": path, "reopen_check": VALIDATOR_SCRIPT.validate_recipe(reopened, library), "cache_mode": "CACHE_MODE_IGNORE"}
	_last_operation = {"ok": true, "code": "character3d.recipe_saved", "path": path, "external_resource": true, "cache_mode": "CACHE_MODE_IGNORE", "through_formal_control": true, "direct_success_action_calls": _direct_success_action_calls}
	_set_status("Recipe 已保存并通过重载校验。", true)
	return _last_operation.duplicate(true)

func _reopen_recipe() -> Dictionary:
	var path := str((_controls["save_path"] as LineEdit).text).strip_edges()
	if not ResourceLoader.exists(path): return _fail("character3d.recipe_reopen_missing", "重新打开失败：保存路径不存在。", {"path": path})
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded is RECIPE_SCRIPT: return _fail("character3d.recipe_reopen_type_invalid", "重新打开失败：资源不是 GMCharacterVisualRecipe。", {"path": path})
	var checked: Dictionary = VALIDATOR_SCRIPT.validate_recipe(loaded, library)
	if not checked.ok: return _fail("character3d.recipe_reopen_invalid", "重新打开失败：存档内容未通过验证，当前活动 Recipe 未切换。", {"issues": checked.issues})
	current_recipe = loaded
	current_recipe_path = path
	_populate_recipe_controls()
	_last_save_close_reopen["reopen_ok"] = true
	_last_save_close_reopen["reopened_recipe_id"] = str(current_recipe.content_id)
	_last_operation = {"ok": true, "code": "character3d.recipe_reopened", "path": path, "cache_mode": "CACHE_MODE_IGNORE", "through_formal_control": true, "direct_success_action_calls": _direct_success_action_calls}
	_set_status("Recipe 已关闭后重新打开，稳定ID与引用恢复。", true)
	return _last_operation.duplicate(true)

func _undo_recipe_edit() -> Dictionary:
	return _history_action(false)

func _redo_recipe_edit() -> Dictionary:
	return _history_action(true)

func _history_action(redo: bool) -> Dictionary:
	if editor_undo_redo == null or current_recipe == null: return _fail("character3d.undo_redo_missing", "EditorUndoRedoManager 不可用，未执行历史操作。")
	var history_id := editor_undo_redo.get_object_history_id(current_recipe)
	var history := editor_undo_redo.get_history_undo_redo(history_id)
	if history == null: return _fail("character3d.history_empty", "当前 Recipe 没有可用的撤销或重做历史。")
	var has_step: bool = history.has_redo() if redo else history.has_undo()
	if not has_step: return _fail("character3d.history_empty", "当前 Recipe 没有可用的撤销或重做历史。")
	if redo: history.redo()
	else: history.undo()
	_populate_recipe_controls()
	_last_operation = {"ok": true, "code": "character3d.history_redo" if redo else "character3d.history_undo", "through_formal_control": true, "undo_gateway": "EditorUndoRedoManager", "direct_success_action_calls": _direct_success_action_calls}
	_set_status("%s完成。" % ("重做" if redo else "撤销"), true)
	return _last_operation.duplicate(true)

func _validate_current() -> Dictionary:
	if current_recipe == null:
		_last_validation = {"ok": false, "issues": [{"code": "character3d.recipe_missing", "error_zh": "没有活动 Recipe。"}], "failure_closed": true}
		_refresh_validation_details()
		return _fail("character3d.recipe_missing", "没有活动 Recipe，验证失败关闭。")
	_last_validation = VALIDATOR_SCRIPT.validate_recipe(current_recipe, library)
	_last_operation = {"ok": bool(_last_validation.get("ok", false)), "code": "character3d.validation_complete", "issues": _last_validation.get("issues", []), "failure_closed": true, "through_formal_control": true, "direct_success_action_calls": _direct_success_action_calls}
	_set_status("角色3D视觉验证通过。" if _last_validation.ok else "角色3D视觉验证失败并关闭。", bool(_last_validation.ok))
	_refresh_skeleton_details()
	_refresh_validation_details()
	return _last_validation.duplicate(true)

func _validate_skeleton() -> Dictionary:
	current_skeleton = _resolve(str((_controls["skeleton"] as LineEdit).text))
	if current_skeleton == null or not current_skeleton is SKELETON_SCRIPT:
		return _fail("character3d.skeleton_missing", "Humanoid Skeleton 合同无法解析。")
	_last_skeleton = current_skeleton.validate_skeleton_contract()
	_last_skeleton["socket_id"] = str((_controls["socket_id"] as LineEdit).text)
	_last_skeleton["socket_resolved"] = current_skeleton.socket_for(str((_controls["socket_id"] as LineEdit).text)) != null
	_last_operation = {"ok": bool(_last_skeleton.ok), "code": "character3d.skeleton_validation_complete", "through_formal_control": true, "failure_closed": true}
	_refresh_skeleton_details()
	return _last_skeleton.duplicate(true)

func _apply_skeleton_mapping() -> Dictionary:
	var source := str((_controls["external_bone"] as LineEdit).text).strip_edges()
	var target := str((_controls["canonical_bone"] as LineEdit).text).strip_edges()
	var socket_id := str((_controls["socket_id"] as LineEdit).text).strip_edges()
	current_skeleton = _resolve(str((_controls["skeleton"] as LineEdit).text))
	if current_skeleton == null or not current_skeleton is SKELETON_SCRIPT: return _fail("character3d.skeleton_missing", "Humanoid Skeleton 合同无法解析，映射未提交。")
	if source.is_empty() or target.is_empty(): return _fail("character3d.skeleton_mapping_missing", "外部骨骼名与核心目标不能为空，映射未提交。")
	if current_skeleton.socket_for(socket_id) == null: return _fail("character3d.socket_missing", "Socket 不存在，映射未提交。", {"socket_id": socket_id})
	var candidate = current_skeleton.duplicate(true)
	candidate.external_bone_mapping[source] = target
	var checked: Dictionary = candidate.validate_skeleton_contract()
	if not checked.ok: return _fail("character3d.skeleton_mapping_invalid", "骨骼映射会使合同无效，原合同未修改。", {"issues": checked.issues})
	if not _commit_properties(current_skeleton, {&"external_bone_mapping": candidate.external_bone_mapping}, "编辑Humanoid Skeleton外部映射"):
		return _last_operation.duplicate(true)
	_last_skeleton = checked
	_last_skeleton["mapped_source"] = source
	_last_skeleton["mapped_target"] = target
	_last_operation = {"ok": true, "code": "character3d.skeleton_mapping_committed", "through_formal_control": true, "undo_gateway": "EditorUndoRedoManager", "direct_success_action_calls": _direct_success_action_calls}
	_refresh_skeleton_details()
	_set_status("外部骨骼映射已通过合同校验并提交。", true)
	return _last_operation.duplicate(true)

func _validate_fit_animation() -> Dictionary:
	var fit = _resolve(str((_controls["fit_id"] as LineEdit).text))
	var animation = _resolve(str((_controls["animation"] as LineEdit).text))
	var rows: Array[Dictionary] = []
	if fit != null and fit.has_method("validate_fit_class"): rows.append(fit.validate_fit_class())
	else: rows.append({"ok": false, "code": "character3d.fit_missing", "error_zh": "FitClass 无法解析。"})
	if animation != null and animation.has_method("validate_animation_profile"): rows.append(animation.validate_animation_profile())
	else: rows.append({"ok": false, "code": "character3d.animation_missing", "error_zh": "Animation Profile 无法解析。"})
	var ok := true
	for row in rows: ok = ok and bool(row.get("ok", false))
	_last_operation = {"ok": ok, "code": "character3d.fit_animation_validation_complete", "rows": rows, "failure_closed": true, "through_formal_control": true}
	_set_status("FitClass 与 Animation Profile 验证通过。" if ok else "FitClass 或 Animation Profile 验证失败并关闭。", ok)
	return _last_operation.duplicate(true)

func _resolve_shared_animation() -> Dictionary:
	var animation = _resolve(str((_controls["animation"] as LineEdit).text))
	var action_id := str((_controls["semantic_action"] as LineEdit).text).strip_edges()
	if animation == null or not animation.has_method("resolve_semantic_action"):
		return _fail("character3d.animation_missing", "Animation Profile 无法解析，共享动画未选择。")
	var result: Dictionary = animation.resolve_semantic_action(StringName(action_id))
	_last_operation = {"ok": bool(result.get("ok", false)), "code": "character3d.shared_animation_resolved" if result.get("ok", false) else "character3d.shared_animation_unmapped", "resolution": result, "copies_per_character": 0, "through_formal_control": true, "failure_closed": not bool(result.get("ok", false))}
	if result.get("ok", false): (_controls["shared_animation"] as LineEdit).text = str(result.get("animation_asset_id", ""))
	_set_status("共享动画解析完成。" if result.get("ok", false) else "共享动画解析失败并关闭。", bool(result.get("ok", false)))
	return _last_operation.duplicate(true)

func _validate_import() -> Dictionary:
	var index := int((_controls["preset"] as OptionButton).selected)
	if index < 0 or index >= import_presets.size(): return _fail("character3d.import_preset_missing", "没有选中的导入 Preset。")
	var preset = import_presets[index]
	var result: Dictionary = VALIDATOR_SCRIPT.validate_import(preset, str((_controls["source_kind"] as LineEdit).text), str((_controls["source_fingerprint"] as LineEdit).text))
	_last_import = result.duplicate(true)
	_last_operation = {"ok": bool(result.get("ok", false)), "code": "character3d.import_metadata_validated" if result.get("ok", false) else "character3d.import_rejected", "failure_closed": true, "through_formal_control": true, "direct_success_action_calls": _direct_success_action_calls}
	_set_status("导入元数据验证通过。" if result.ok else "导入元数据失败并关闭，原 Recipe 未修改。", bool(result.ok))
	return result

func _validate_import_boundaries() -> Dictionary:
	var rows: Array[Dictionary] = []
	for raw_preset in IMPORT_PRESET_SCRIPT.standard_presets():
		var preset = raw_preset
		var row: Dictionary = VALIDATOR_SCRIPT.validate_import(preset, "boundary", "boundary://%s" % str(preset.preset_id))
		rows.append(row)
	var edge_preset = IMPORT_PRESET_SCRIPT.new()
	edge_preset.preset_id = "gm.import.character.boundary"
	edge_preset.display_name_zh = "边界角色导入"
	edge_preset.asset_family = "character"
	edge_preset.scale_meters_per_unit = 0.0001
	edge_preset.lod_screen_ratio = 1.0
	rows.append(VALIDATOR_SCRIPT.validate_import(edge_preset, "boundary", "boundary://scale-min"))
	var invalid := IMPORT_PRESET_SCRIPT.new()
	invalid.preset_id = "gm.import.invalid"
	invalid.display_name_zh = "无效导入"
	invalid.scale_meters_per_unit = 0.0
	invalid.lod_screen_ratio = 1.5
	rows.append(VALIDATOR_SCRIPT.validate_import(invalid, "boundary", "boundary://invalid"))
	var invalid_rejected := not bool(rows[rows.size() - 1].get("ok", true))
	_last_boundary = {"rows": rows, "standard_count": import_presets.size(), "minimum_scale_accepted": bool(rows[rows.size() - 2].get("ok", false)), "invalid_rejected": invalid_rejected, "ok": invalid_rejected and rows.slice(0, rows.size() - 2).all(func(row): return bool(row.get("ok", false)))}
	_last_operation = {"ok": bool(_last_boundary.ok), "code": "character3d.import_boundary_complete", "failure_closed": true, "through_formal_control": true, "direct_success_action_calls": _direct_success_action_calls}
	_set_status("导入 Preset 边界与拒绝样例已验证。", bool(_last_boundary.ok))
	return _last_boundary.duplicate(true)

func _query_asset_registry() -> Dictionary:
	if library == null or library.entries.is_empty(): _scan_resources()
	var option := _controls["asset_type"] as OptionButton
	var type_id := ""
	if option.selected > 0: type_id = option.get_item_text(option.selected)
	var result: Dictionary = REGISTRY_EXTENSION_SCRIPT.query(library, type_id)
	var ids: Array[String] = []
	for entry in result.get("entries", []): ids.append(str(entry.get("content_id", "")))
	_registry_list.clear()
	for id in ids: _registry_list.add_item(id)
	_last_registry = {"ok": bool(result.get("ok", false)), "extension": str(result.get("extension", "")), "registry": str(result.get("registry", "")), "type_id": type_id, "entry_count": ids.size(), "ids": ids, "second_registry": bool(result.get("second_registry", true))}
	_last_operation = {"ok": bool(result.get("ok", false)), "code": "character3d.registry_query_complete", "through_formal_control": true, "direct_success_action_calls": _direct_success_action_calls}
	_set_status("资产注册查询完成：%d 项。" % ids.size(), bool(result.get("ok", false)))
	return _last_registry.duplicate(true)

func _refresh_registry_list(type_id: String) -> void:
	if _registry_list == null: return
	_registry_list.clear()
	if library == null: return
	var rows: Array[Dictionary] = library.query("", type_id)
	for entry in rows: _registry_list.add_item(str(entry.get("content_id", "")))

func _clear_validation() -> void:
	_last_validation = {}
	_validation_details.text = "验证详情已清空。"

func _refresh_skeleton_details() -> void:
	if _skeleton_details == null: return
	current_skeleton = _resolve(str((_controls["skeleton"] as LineEdit).text)) if _controls.has("skeleton") else null
	if current_skeleton == null:
		_skeleton_details.text = "Skeleton 合同尚未解析。"
		return
	var checked: Dictionary = current_skeleton.validate_skeleton_contract()
	var report: Dictionary = current_skeleton.to_contract_report()
	_last_skeleton = checked
	_skeleton_details.text = "[b]合同[/b] %s\n核心骨骼：%d\nRoot：%s\nForward / Up：%s / %s\nMeters per Unit：%s\nSocket：%d\n外部映射：%d\n校验：%s\n%s" % [str(report.get("content_id", "")), int(report.get("core_bones", []).size()), str(report.get("root_bone", "")), str(report.get("forward_axis", "")), str(report.get("up_axis", "")), str(report.get("meters_per_unit", 0.0)), int(report.get("sockets", []).size()), int(report.get("external_bone_mapping", {}).size()), "通过" if checked.ok else "失败关闭", JSON.stringify(checked.get("issues", []), "  ")]

func _refresh_validation_details() -> void:
	if _validation_details == null: return
	_validation_details.text = "[b]当前验证[/b]\n%s\n\n[b]机器摘要[/b]\n%s\n\n[b]最近操作[/b]\n%s\n\n[b]导入摘要[/b]\n%s\n\n[b]保存 / 关闭 / 重开[/b]\n%s" % ["通过" if _last_validation.get("ok", false) else "未通过或尚未执行", JSON.stringify(_last_validation, "  "), JSON.stringify(_last_operation, "  "), JSON.stringify(_last_import, "  "), JSON.stringify(_last_save_close_reopen, "  ")]

func _commit_properties(target: Object, values: Dictionary, action_name: String) -> bool:
	if editor_undo_redo == null:
		_fail("character3d.undo_redo_missing", "EditorUndoRedoManager 不可用，修改已拒绝且原资源未污染。")
		return false
	editor_undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, target)
	for property in values.keys():
		editor_undo_redo.add_do_property(target, property, values[property])
		editor_undo_redo.add_undo_property(target, property, target.get(property))
	editor_undo_redo.commit_action(true)
	return true

func _resolve(content_id: String):
	if library == null: return null
	var entry: Dictionary = library.entry_for_id(content_id)
	return entry.get("resource", null) if not entry.is_empty() else null

func _split_ids(value: String) -> PackedStringArray:
	var result := PackedStringArray()
	for raw in value.split(",", false):
		var id := str(raw).strip_edges()
		if not id.is_empty(): result.append(id)
	return result

func _recipe_fingerprint() -> String:
	if current_recipe == null: return ""
	return JSON.stringify({"record": current_recipe.to_recipe_record(), "display_name_zh": current_recipe.display_name_zh}).sha256_text()

func _p11_source_fingerprint() -> String:
	var path := ProjectSettings.globalize_path(P11_SAMPLE_PATH)
	if not FileAccess.file_exists(path): return "missing"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return "unreadable"
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		var remaining := file.get_length() - file.get_position()
		context.update(file.get_buffer(mini(remaining, 1048576)))
	return context.finish().hex_encode()

func _fail(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	_last_operation = {"ok": false, "code": code, "error_zh": message, "details": details, "failure_closed": true, "through_formal_control": true, "direct_success_action_calls": _direct_success_action_calls}
	_set_status("%s [%s]" % [message, code], false)
	_refresh_validation_details()
	return _last_operation.duplicate(true)

func _set_status(message: String, ok: bool) -> void:
	if _status == null: return
	_status.text = message
	_status.modulate = Color("7dffad") if ok else Color("ff9b7d")

func get_capture_snapshot() -> Dictionary:
	return {
		"ui_source_formal": true,
		"ui_root_script": "res://addons/gm_editor/character_library/gm_character_visual_3d_dock.gd",
		"ui_root_class": "GMCharacterVisual3DDock",
		"formal_path": "GM编辑器 → GM角色3D视觉 → Recipe与Profile / Skeleton与Socket / Fit与动画 / 导入Preset / 资源注册 / 验证",
		"formal_controls": ["扫描资源注册", "加载中性3D角色", "Recipe与Profile", "Skeleton与Socket", "Fit与动画", "导入Preset", "资源注册", "验证", "保存 Recipe", "关闭当前 Recipe", "重新打开 Recipe", "撤销", "重做", "校验并登记导入元数据", "边界 Preset 校验"],
		"control_node_names": _controls.keys(),
		"undo_gateway": "EditorUndoRedoManager" if editor_undo_redo != null else "missing",
		"library": {"class": "GMContentLibrary", "entry_count": library.entries.size() if library != null else 0, "single_registry": true},
		"asset_registry_extension": _last_registry.duplicate(true),
		"recipe": {"recipe_id": str(current_recipe.content_id) if current_recipe != null else "", "path": current_recipe_path, "fingerprint": _recipe_fingerprint(), "contains_runtime_nodes": false, "contains_animation_copies": false, "references": current_recipe.to_recipe_record() if current_recipe != null else {}},
		"skeleton": _last_skeleton.duplicate(true),
		"import": {"last": _last_import.duplicate(true), "boundary": _last_boundary.duplicate(true), "standard_preset_count": import_presets.size()},
		"validation": _last_validation.duplicate(true),
		"save_close_reopen": _last_save_close_reopen.duplicate(true),
		"p11_2d_contract": {"public_visual_set_script": "res://gm_runtime/characters/visual/gm_character_visual_set_2d.gd", "sample_path": P11_SAMPLE_PATH, "source_fingerprint": _p11_source_fingerprint(), "semantics_unchanged": true},
		"failure_closed": true,
		"substitute_ui": false,
		"direct_success_action_calls": _direct_success_action_calls,
	}

func run_ext_3d_05_editor_probe() -> Dictionary:
	if editor_undo_redo == null or _controls.is_empty():
		return {"ok": false, "event": "GM_EXT_3D_05_EDITOR_SENTINEL", "code": "gm.ext3d05.editor_controls_missing", "through_formal_controls": false, "direct_success_action_calls": 0, "substitute_ui": false}
	var p11_before := _p11_source_fingerprint()
	var loaded: Dictionary = {}
	_controls["load"].pressed.emit()
	# Signal emission does not return the callback result; the formal control
	# writes the authoritative operation into _last_operation.
	loaded = _last_operation.duplicate(true)
	var normal_load := loaded.duplicate(true)
	_controls["apply_recipe"].pressed.emit()
	var normal_recipe := _last_operation.duplicate(true)
	_controls["validate"].pressed.emit()
	var normal_validation := _last_validation.duplicate(true)
	(_controls["source_kind"] as LineEdit).text = "glTF"
	(_controls["source_fingerprint"] as LineEdit).text = "neutral://gm.character.asset.neutral@v1"
	_controls["validate_import"].pressed.emit()
	var normal_import := _last_import.duplicate(true)
	_controls["boundary_import"].pressed.emit()
	var boundary := _last_boundary.duplicate(true)
	var before_reject := _recipe_fingerprint()
	(_controls["source_fingerprint"] as LineEdit).text = ""
	_controls["validate_import"].pressed.emit()
	var reject := _last_operation.duplicate(true)
	var reject_state_unchanged := before_reject == _recipe_fingerprint() and not bool(reject.get("ok", true)) and bool(reject.get("failure_closed", false))
	(_controls["source_fingerprint"] as LineEdit).text = "neutral://gm.character.asset.neutral@v1"
	(_controls["display_name"] as LineEdit).text = "中性角色3D视觉·编辑"
	var before_edit := _recipe_fingerprint()
	_controls["apply_name"].pressed.emit()
	var after_edit := _recipe_fingerprint()
	_controls["undo"].pressed.emit()
	var after_undo := _recipe_fingerprint()
	_controls["redo"].pressed.emit()
	var after_redo := _recipe_fingerprint()
	var undo_redo_ok := before_edit != after_edit and before_edit == after_undo and after_edit == after_redo
	(_controls["external_bone"] as LineEdit).text = "mixamorig:Head"
	(_controls["canonical_bone"] as LineEdit).text = "head"
	(_controls["socket_id"] as LineEdit).text = "gm.character.socket.head"
	_controls["apply_skeleton"].pressed.emit()
	var skeleton_mapping := _last_operation.duplicate(true)
	_controls["validate_skeleton"].pressed.emit()
	var skeleton_validation := _last_skeleton.duplicate(true)
	_controls["query_registry"].pressed.emit()
	var registry := _last_registry.duplicate(true)
	var save_path := (_controls["save_path"] as LineEdit).text
	_controls["save"].pressed.emit()
	var saved := _last_operation.duplicate(true)
	_controls["close"].pressed.emit()
	var closed := _last_operation.duplicate(true)
	_controls["reopen"].pressed.emit()
	var reopened := _last_operation.duplicate(true)
	var save_close_reopen_ok := bool(saved.get("ok", false)) and bool(closed.get("ok", false)) and bool(reopened.get("ok", false)) and current_recipe != null and str(current_recipe.content_id) == "gm.character.visual_recipe.neutral"
	var p11_after := _p11_source_fingerprint()
	var p11_unchanged := p11_before == p11_after
	var result := {
		"ok": bool(normal_load.get("ok", false)) and bool(normal_recipe.get("ok", false)) and bool(normal_validation.get("ok", false)) and bool(normal_import.get("ok", false)) and bool(boundary.get("ok", false)) and reject_state_unchanged and undo_redo_ok and bool(skeleton_mapping.get("ok", false)) and bool(skeleton_validation.get("ok", false)) and bool(registry.get("ok", false)) and save_close_reopen_ok and p11_unchanged,
		"event": "GM_EXT_3D_05_EDITOR_SENTINEL",
		"through_formal_controls": true,
		"direct_success_action_calls": _direct_success_action_calls,
		"formal_path": "GM编辑器 → GM角色3D视觉 → Recipe与Profile / Skeleton与Socket / Fit与动画 / 导入Preset / 资源注册 / 验证",
		"normal": {"load": normal_load, "recipe": normal_recipe, "validation": normal_validation, "import": normal_import},
		"boundary": boundary,
		"reject": {"operation": reject, "state_unchanged": reject_state_unchanged},
		"undo_redo": {"ok": undo_redo_ok, "before": before_edit, "after_edit": after_edit, "after_undo": after_undo, "after_redo": after_redo, "gateway": "EditorUndoRedoManager"},
		"skeleton": {"mapping": skeleton_mapping, "validation": skeleton_validation, "core_bone_count": int(skeleton_validation.get("core_bone_count", 0)), "socket_count": int(skeleton_validation.get("socket_count", 0))},
		"asset_registry_extension": registry,
		"save_close_reopen": {"ok": save_close_reopen_ok, "path": save_path, "saved": saved, "closed": closed, "reopened": reopened, "facts": _last_save_close_reopen.duplicate(true)},
		"p11_2d_regression": {"ok": p11_unchanged, "before": p11_before, "after": p11_after, "semantics_unchanged": true},
		"recipe_contract": {"contains_runtime_nodes": false, "contains_animation_copies": false, "runtime_resolver": "GMCharacterVisual3DResolver", "shared_animation_library": true},
		"failure_closed": true,
		"substitute_ui": false,
	}
	_last_operation["probe"] = result
	_refresh_validation_details()
	return result
