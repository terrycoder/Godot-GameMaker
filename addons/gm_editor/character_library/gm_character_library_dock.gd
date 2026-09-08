@tool
class_name GMCharacterLibraryDock
extends VBoxContainer

const INDEX_SCRIPT := preload("res://addons/gm_editor/character_library/gm_character_library_index.gd")
const SEMANTICS := ["idle", "move", "attack", "hurt", "death"]
const DIRECTIONS := ["down", "left", "right", "up", "down_left", "down_right", "up_left", "up_right"]
const ANCHOR_KINDS := ["weapon", "effect", "hit", "sound", "dialogue", "overhead_ui"]

var editor_interface
var undo_redo: EditorUndoRedoManager
var index: GMCharacterLibraryIndex
var current_entries: Array[Dictionary] = []
var selected_entry: Dictionary = {}
var current_definition: GMCharacterDefinition
var current_visual_set: GMCharacterVisualSet2D
var definition_path := ""
var visual_set_path := ""
var last_operation: Dictionary = {}
var character_history_ids: Array[int] = []
var presenter: GMCharacterPresenter2D
var overlay: GMCharacterPreviewOverlay2D
var tabs: TabContainer
var search_box: LineEdit
var stable_id_box: LineEdit
var style_box: LineEdit
var category_box: LineEdit
var tag_box: LineEdit
var completeness: OptionButton
var cards: ItemList
var details: RichTextLabel
var status_label: Label
var definition_id_box: LineEdit
var definition_name_box: LineEdit
var visual_id_box: LineEdit
var visual_name_box: LineEdit
var source_path_box: LineEdit
var definition_path_box: LineEdit
var visual_path_box: LineEdit
var action_mode_boxes := {}
var action_mirror_boxes := {}
var action_mapping_boxes := {}
var anchor_kind_box: OptionButton
var anchor_semantic_box: OptionButton
var anchor_direction_box: OptionButton
var anchor_frame_box: SpinBox
var anchor_x_box: SpinBox
var anchor_y_box: SpinBox
var event_semantic_box: OptionButton
var event_kind_box: OptionButton
var event_name_box: LineEdit
var event_frame_box: SpinBox
var edit_log: RichTextLabel
var action_option: OptionButton
var direction_option: OptionButton
var frame_slider: HSlider
var preview_viewport: SubViewport

func configure(value, p_undo_redo: EditorUndoRedoManager = null) -> void:
	editor_interface = value
	undo_redo = p_undo_redo

func _ready() -> void:
	name = "GM角色资产库"
	custom_minimum_size = Vector2(1100, 620)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	index = INDEX_SCRIPT.new()
	_build_ui()
	if editor_interface != null:
		var editor_filesystem = editor_interface.get_resource_filesystem()
		if editor_filesystem != null and not editor_filesystem.filesystem_changed.is_connected(_on_character_filesystem_changed):
			editor_filesystem.filesystem_changed.connect(_on_character_filesystem_changed)
	call_deferred("refresh_library")

func _on_character_filesystem_changed() -> void:
	call_deferred("refresh_library")

func _build_ui() -> void:
	var title := Label.new()
	title.text = "GM 角色资产库 · 正式外观/动作/锚点生产线"
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)
	tabs = TabContainer.new()
	tabs.name = "CharacterProductionTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	_build_library_tab()
	_build_import_tab()
	_build_actions_tab()
	_build_anchor_event_tab()
	_build_preview_tab()
	status_label = Label.new()
	status_label.name = "Status"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)

func _build_library_tab() -> void:
	var page := VBoxContainer.new(); page.name = "角色库"; tabs.add_child(page)
	var filters := HBoxContainer.new(); page.add_child(filters)
	search_box = _line(filters, "名称", 130, "FilterName")
	stable_id_box = _line(filters, "稳定ID", 150, "FilterStableId")
	style_box = _line(filters, "画风", 90, "FilterStyle")
	category_box = _line(filters, "类别", 90, "FilterCategory")
	tag_box = _line(filters, "标签", 90, "FilterTag")
	completeness = OptionButton.new(); completeness.name = "FilterCompleteness"
	for label in ["全部完整度", "完整", "缺动作"]: completeness.add_item(label)
	completeness.item_selected.connect(func(_i): _refresh_cards()); filters.add_child(completeness)
	_button(filters, "扫描/校验", "ScanValidate", refresh_library)
	_button(filters, "1500角色有界夹具", "BoundedFixture", run_bounded_fixture)
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; page.add_child(split)
	cards = ItemList.new(); cards.name = "CharacterCards"; cards.custom_minimum_size.x = 430; cards.fixed_icon_size = Vector2i(64, 64); cards.item_selected.connect(_select_index); split.add_child(cards)
	details = RichTextLabel.new(); details.name = "LibraryDetails"; details.fit_content = false; split.add_child(details)

func _build_import_tab() -> void:
	var page := VBoxContainer.new(); page.name = "导入与保存"; tabs.add_child(page)
	var identity := GridContainer.new(); identity.columns = 2; page.add_child(identity)
	_label(identity, "Definition 稳定ID"); definition_id_box = _line(identity, "gm.character.hero", 520, "DefinitionId")
	_label(identity, "显示名称"); definition_name_box = _line(identity, "角色名称", 520, "DefinitionName")
	_label(identity, "VisualSet 稳定ID"); visual_id_box = _line(identity, "hero.default", 520, "VisualSetId")
	_label(identity, "VisualSet 显示名称"); visual_name_box = _line(identity, "外观名称", 520, "VisualSetName")
	_label(identity, "导入源（帧目录 / SpriteFrames / VisualSet / Definition）"); source_path_box = _line(identity, "res://...", 520, "ImportSourcePath")
	_label(identity, "Definition 保存路径"); definition_path_box = _line(identity, "res://...definition.tres", 520, "DefinitionSavePath")
	_label(identity, "VisualSet 保存路径"); visual_path_box = _line(identity, "res://...visual.tres", 520, "VisualSetSavePath")
	var row := HBoxContainer.new(); page.add_child(row)
	_button(row, "新建", "NewDefinition", _new_definition_from_controls)
	_button(row, "打开 Definition", "OpenDefinition", _open_definition_from_controls)
	_button(row, "关闭/清空", "CloseDefinition", _close_definition)
	_button(row, "导入四/八向帧或 Godot 资源", "ImportSource", _import_source_from_controls)
	_button(row, "应用外观名称", "ApplyVisualMetadata", _apply_visual_metadata)
	_button(row, "保存", "SaveResources", _save_resources)
	_button(row, "另存为", "SaveResourcesAs", _save_resources_as)
	var note := Label.new(); note.text = "帧目录命名：semantic_direction_000.png（idle/move/attack/hurt/death；四向或八向）。Aseprite 为可选 Adapter，未安装不影响本页。"; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; page.add_child(note)

func _build_actions_tab() -> void:
	var page := VBoxContainer.new(); page.name = "动作与方向"; tabs.add_child(page)
	var header := Label.new(); header.text = "五语义动作批量映射（direction=animation，以逗号分隔）；提交前在副本中完整校验。"; page.add_child(header)
	var grid := GridContainer.new(); grid.columns = 4; page.add_child(grid)
	for value in ["语义", "方向规则", "镜像", "方向→动画"]: _label(grid, value)
	for semantic in SEMANTICS:
		_label(grid, semantic)
		var mode := OptionButton.new(); mode.name = "ActionMode_%s" % semantic
		for mode_name in ["one", "four", "eight", "four_mirrored"]: mode.add_item(mode_name)
		mode.select(1); grid.add_child(mode); action_mode_boxes[semantic] = mode
		var mirror := CheckBox.new(); mirror.name = "ActionMirror_%s" % semantic; mirror.text = "允许"; grid.add_child(mirror); action_mirror_boxes[semantic] = mirror
		var mapping := LineEdit.new(); mapping.name = "ActionMapping_%s" % semantic; mapping.custom_minimum_size.x = 620; mapping.placeholder_text = "down=%s_down,left=%s_left,right=%s_right,up=%s_up" % [semantic, semantic, semantic, semantic]; grid.add_child(mapping); action_mapping_boxes[semantic] = mapping
	var action_buttons := HBoxContainer.new(); page.add_child(action_buttons)
	_button(action_buttons, "通过 EditorUndoRedoManager 提交全部动作", "ApplyAllActions", _apply_all_actions)
	_button(action_buttons, "撤销角色编辑", "UndoCharacterEdit", _undo_character_edit)
	_button(action_buttons, "重做角色编辑", "RedoCharacterEdit", _redo_character_edit)

func _build_anchor_event_tab() -> void:
	var page := VBoxContainer.new(); page.name = "锚点与事件帧"; tabs.add_child(page)
	var anchor_title := Label.new(); anchor_title.text = "六类锚点逐动作 / 方向 / 帧位置（重复、越界、帧数变化均结构化失败且不提交）"; page.add_child(anchor_title)
	var anchors := HBoxContainer.new(); page.add_child(anchors)
	anchor_kind_box = _options(anchors, ANCHOR_KINDS, "AnchorKind")
	anchor_semantic_box = _options(anchors, SEMANTICS, "AnchorSemantic")
	anchor_direction_box = _options(anchors, DIRECTIONS, "AnchorDirection")
	anchor_frame_box = _spin(anchors, 0, 4096, "AnchorFrame")
	anchor_x_box = _spin(anchors, -4096, 4096, "AnchorX")
	anchor_y_box = _spin(anchors, -4096, 4096, "AnchorY")
	_button(anchors, "设置锚点帧", "SetAnchorPoint", _set_anchor_point)
	_button(anchors, "删除锚点类型", "RemoveAnchor", _remove_anchor)
	var event_title := Label.new(); event_title.text = "事件帧：动作 / 类型 / 名称 / 帧"; page.add_child(event_title)
	var events := HBoxContainer.new(); page.add_child(events)
	event_semantic_box = _options(events, SEMANTICS, "EventSemantic")
	event_kind_box = _options(events, ANCHOR_KINDS, "EventKind")
	event_name_box = _line(events, "事件名", 220, "EventName")
	event_frame_box = _spin(events, 0, 4096, "EventFrame")
	_button(events, "添加/替换事件", "SetFrameEvent", _set_frame_event)
	_button(events, "删除事件", "RemoveFrameEvent", _remove_frame_event)
	edit_log = RichTextLabel.new(); edit_log.name = "AnchorEventFacts"; edit_log.custom_minimum_size.y = 230; page.add_child(edit_log)
	_refresh_edit_log()

func _build_preview_tab() -> void:
	var page := VBoxContainer.new(); page.name = "验证与预览"; tabs.add_child(page)
	var controls := HBoxContainer.new(); page.add_child(controls)
	action_option = _options(controls, SEMANTICS, "PreviewAction")
	direction_option = _options(controls, DIRECTIONS, "PreviewDirection")
	action_option.item_selected.connect(_preview_changed); direction_option.item_selected.connect(_preview_changed)
	frame_slider = HSlider.new(); frame_slider.name = "PreviewFrame"; frame_slider.min_value = 0; frame_slider.max_value = 63; frame_slider.step = 1; frame_slider.custom_minimum_size.x = 240; frame_slider.value_changed.connect(_frame_changed); controls.add_child(frame_slider)
	_button(controls, "验证 Definition / VisualSet", "ValidateCurrent", _validate_current)
	var viewport_container := SubViewportContainer.new(); viewport_container.stretch = true; viewport_container.custom_minimum_size = Vector2(900, 350); viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL; page.add_child(viewport_container)
	preview_viewport = SubViewport.new(); preview_viewport.size = Vector2i(900, 350); preview_viewport.transparent_bg = false; preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; viewport_container.add_child(preview_viewport)
	var bg := ColorRect.new(); bg.color = Color("172033"); bg.size = Vector2(900, 350); preview_viewport.add_child(bg)
	presenter = GMCharacterPresenter2D.new(); presenter.position = Vector2(450, 170); preview_viewport.add_child(presenter)
	overlay = GMCharacterPreviewOverlay2D.new(); overlay.position = presenter.position; overlay.configure(presenter); preview_viewport.add_child(overlay)

func _line(parent: Control, placeholder: String, width: float, node_name: String = "") -> LineEdit:
	var line := LineEdit.new(); line.name = node_name if not node_name.is_empty() else placeholder; line.placeholder_text = placeholder; line.custom_minimum_size.x = width; parent.add_child(line); return line

func _label(parent: Control, value: String) -> void:
	var label := Label.new(); label.text = value; parent.add_child(label)

func _button(parent: Control, label: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new(); button.name = node_name; button.text = label; button.pressed.connect(callback); parent.add_child(button); return button

func _options(parent: Control, values: Array, node_name: String) -> OptionButton:
	var option := OptionButton.new(); option.name = node_name
	for value in values: option.add_item(str(value))
	parent.add_child(option); return option

func _spin(parent: Control, minimum: float, maximum: float, node_name: String) -> SpinBox:
	var spin := SpinBox.new(); spin.name = node_name; spin.min_value = minimum; spin.max_value = maximum; spin.step = 1; parent.add_child(spin); return spin

func refresh_library() -> void:
	var result := index.scan(PackedStringArray(["res://samples/task11_characters", "res://gm_runtime/characters"]))
	_refresh_cards()
	_set_status("扫描完成：%d 个角色；%d 个结构化问题。损坏资源已隔离，可继续操作。" % [result.count, result.issues.size()], result.issues.is_empty())

func run_bounded_fixture() -> Dictionary:
	var started := Time.get_ticks_msec(); var fixture := index.generate_bounded_fixture(1500); index.build_from_definitions(fixture)
	var filtered := index.query("夹具角色", "fixture.character.1", "pixel", "enemy", "batch", "complete")
	_refresh_cards()
	var result := {"ok": index.entries.size() == 1500 and not filtered.is_empty(), "indexed": index.entries.size(), "filtered": filtered.size(), "elapsed_ms": Time.get_ticks_msec() - started, "bounded_max": 5000}
	_set_status("有界夹具：索引 %d，组合筛选 %d，%dms。" % [result.indexed, result.filtered, result.elapsed_ms], result.ok); return result

func _refresh_cards() -> void:
	if cards == null or index == null: return
	var completeness_filter: String = ["all", "complete", "incomplete"][completeness.selected]
	current_entries = index.query(search_box.text, stable_id_box.text, style_box.text, category_box.text, tag_box.text, completeness_filter)
	cards.clear()
	for entry in current_entries:
		var label := "%s\n%s · %s/%s · %d%%\n使用：%s" % [entry.display_name_zh, entry.content_id, entry.art_style, entry.category, roundi(float(entry.completeness_ratio) * 100.0), ", ".join(entry.usage_locations)]
		cards.add_item(label, entry.thumbnail if entry.thumbnail is Texture2D else null); cards.set_item_metadata(cards.item_count - 1, entry)
	if not current_entries.is_empty(): cards.select(0); _select_index(0)

func _select_index(item_index: int) -> void:
	selected_entry = cards.get_item_metadata(item_index)
	var definition := selected_entry.get("definition", null) as GMCharacterDefinition
	if definition != null: _set_current_definition(definition, definition.resource_path)
	else:
		current_visual_set = selected_entry.get("visual_set", null)
		presenter.configure(current_visual_set)
	details.text = "[b]%s[/b]  %s\n身份配置：%s\n使用位置：%s\n动作完整度：%d%%\n缩略图：%s\n问题：\n%s" % [selected_entry.display_name_zh, selected_entry.content_id, selected_entry.identity_configuration_label, ", ".join(selected_entry.usage_locations), roundi(float(selected_entry.completeness_ratio) * 100.0), selected_entry.thumbnail_state, JSON.stringify(selected_entry.issues, "  ")]

func _new_definition_from_controls() -> void:
	var content_id := definition_id_box.text.strip_edges(); var visual_id := visual_id_box.text.strip_edges()
	if content_id.is_empty() or visual_id.is_empty(): _fail_operation("character.create_identity_missing", "新建失败：Definition 与 VisualSet 稳定ID不能为空。"); return
	var definition := GMCharacterDefinition.new(); definition.content_id = content_id; definition.content_type_id = "gm.character.definition"; definition.display_name_zh = definition_name_box.text; definition.identity_configuration_label = "视觉身份独立；不承载玩法身份"
	var visual := GMCharacterVisualSet2D.new(); visual.visual_set_id = visual_id; visual.display_name_zh = definition_name_box.text
	definition.visual_sets = [visual]; definition.default_visual_set_id = visual_id
	_set_current_definition(definition)
	_record_success("character.definition_created", {"content_id":content_id, "visual_set_id":visual_id})

func _close_definition() -> void:
	current_definition = null; current_visual_set = null; definition_path = ""; visual_set_path = ""
	definition_path_box.text = ""; visual_path_box.text = ""
	if presenter != null: presenter.clear_configuration()
	_record_success("character.definition_closed", {"cleared":true})

func _apply_visual_metadata() -> void:
	if current_visual_set == null: _fail_operation("character.edit_target_missing", "没有活动 VisualSet。"); return
	var value := visual_name_box.text.strip_edges()
	if value.is_empty(): _fail_operation("character.visual_name_missing", "外观名称不能为空，原资源未修改。"); return
	if not _commit_properties(current_visual_set, {&"display_name_zh":value}, "角色外观名称编辑"): return
	_record_success("character.visual_metadata_committed", {"display_name_zh":value,"undo_gateway":"EditorUndoRedoManager"})

func _open_definition_from_controls() -> void:
	var path := definition_path_box.text.strip_edges()
	if not ResourceLoader.exists(path): _fail_operation("character.definition_open_missing", "打开失败：Definition 路径不存在。", {"path":path}); return
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded is GMCharacterDefinition: _fail_operation("character.definition_open_failed", "打开失败：路径不是 GMCharacterDefinition。", {"path":path}); return
	_set_current_definition(loaded, path)
	_record_success("character.definition_opened", {"path":path, "cache_mode":"CACHE_MODE_IGNORE"})

func _import_source_from_controls() -> void:
	if current_visual_set == null: _fail_operation("character.edit_target_missing", "请先新建或打开 Definition。"); return
	var path := source_path_box.text.strip_edges(); var candidate := current_visual_set.duplicate(true) as GMCharacterVisualSet2D
	var imported := _import_into_candidate(candidate, path)
	if not imported.ok: _fail_operation(imported.code, imported.error_zh, imported.get("details", {})); return
	var checked := candidate.validate_visual_set()
	if not checked.ok:
		_fail_operation("character.import_candidate_invalid", "导入候选未通过公共 VisualSet 校验，活动资源、预览、撤销历史与磁盘均未修改。", {"source_kind":imported.get("source_kind","unknown"),"path":path,"issues":checked.issues,"validation_boundaries":checked.get("validation_boundaries",{})})
		return
	var imported_values := {
		&"sprite_frames":candidate.sprite_frames, &"main_image":candidate.main_image,
		&"avatar":candidate.avatar, &"portrait":candidate.portrait, &"shadow":candidate.shadow,
		&"animation_player_scene":candidate.animation_player_scene, &"custom_presenter_scene":candidate.custom_presenter_scene,
		&"actions":candidate.actions, &"anchors":candidate.anchors, &"visual_bounds":candidate.visual_bounds,
		&"art_style":candidate.art_style, &"category":candidate.category, &"tags":candidate.tags,
	}
	if not _commit_properties(current_visual_set, imported_values, "角色导入表现资源"): return
	_record_success("character.source_imported", imported)
	presenter.configure(current_visual_set)

func _import_into_candidate(candidate: GMCharacterVisualSet2D, path: String) -> Dictionary:
	if path.is_empty(): return _failure("character.import_path_missing", "导入路径不能为空。")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)): return _import_frame_directory(candidate, path)
	if not ResourceLoader.exists(path): return _failure("character.import_resource_missing", "导入资源不存在或无法识别，原资源未修改。", {"path":path})
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded is SpriteFrames:
		candidate.sprite_frames = loaded; return {"ok":true, "source_kind":"SpriteFrames", "path":path}
	if loaded is GMCharacterVisualSet2D:
		_copy_visual_payload(candidate, loaded); return {"ok":true, "source_kind":"GMCharacterVisualSet2D", "path":path}
	if loaded is GMCharacterDefinition:
		var resolved: Dictionary = loaded.resolve_visual_set()
		if not resolved.ok: return resolved
		_copy_visual_payload(candidate, resolved.visual_set); return {"ok":true, "source_kind":"GMCharacterDefinition", "path":path}
	return _failure("character.import_resource_unsupported", "导入源不是帧目录、SpriteFrames、VisualSet 或 Definition。", {"path":path})

func _copy_visual_payload(target: GMCharacterVisualSet2D, source: GMCharacterVisualSet2D) -> void:
	target.sprite_frames = source.sprite_frames; target.main_image = source.main_image; target.avatar = source.avatar; target.portrait = source.portrait; target.shadow = source.shadow
	target.animation_player_scene = source.animation_player_scene; target.custom_presenter_scene = source.custom_presenter_scene
	target.actions = source.actions.duplicate(true); target.anchors = source.anchors.duplicate(true); target.visual_bounds = source.visual_bounds
	target.art_style = source.art_style; target.category = source.category; target.tags = source.tags

func _import_frame_directory(candidate: GMCharacterVisualSet2D, path: String) -> Dictionary:
	var dir := DirAccess.open(path)
	if dir == null: return _failure("character.import_directory_open_failed", "无法打开帧目录。", {"path":path})
	var regex := RegEx.new(); regex.compile("^(idle|move|attack|hurt|death)_(down|left|right|up|down_left|down_right|up_left|up_right)_([0-9]+)\\.(png|jpg|jpeg|webp|svg)$")
	var grouped := {}; var indices := {}; var invalid_names: Array[String] = []; var names := dir.get_files(); names.sort()
	for file_name in names:
		var matched := regex.search(file_name.to_lower())
		if matched == null:
			if file_name.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "svg"]: invalid_names.append(file_name)
			continue
		var animation := "%s_%s" % [matched.get_string(1), matched.get_string(2)]
		if not grouped.has(animation): grouped[animation] = []; indices[animation] = []
		grouped[animation].append(path.path_join(file_name))
		indices[animation].append(int(matched.get_string(3)))
	if not invalid_names.is_empty(): return _failure("character.import_frame_name_invalid", "帧目录包含无效命名，导入未提交。", {"path":path,"files":invalid_names})
	if grouped.is_empty(): return _failure("character.import_frames_not_found", "目录没有符合 semantic_direction_frame 命名的帧。", {"path":path})
	for animation in indices:
		var sequence: Array = indices[animation]; sequence.sort()
		for expected in sequence.size():
			if int(sequence[expected]) != expected: return _failure("character.import_frame_sequence_gap", "动作帧编号不连续，导入未提交。", {"animation":animation,"expected":expected,"actual":sequence[expected]})
	var complete_cardinal := false; var has_eight := false
	for semantic in SEMANTICS:
		var cardinal := true; var eight := true
		for direction in ["down", "left", "right", "up"]: cardinal = cardinal and grouped.has("%s_%s" % [semantic, direction])
		for direction in DIRECTIONS: eight = eight and grouped.has("%s_%s" % [semantic, direction])
		complete_cardinal = complete_cardinal or cardinal; has_eight = has_eight or eight
	if not complete_cardinal: return _failure("character.import_cardinal_frames_missing", "帧目录至少需要一个完整四向语义动作，导入未提交。", {"path":path,"animations":grouped.keys()})
	var frames := SpriteFrames.new(); frames.remove_animation(&"default")
	for animation in grouped:
		frames.add_animation(animation)
		for frame_path in grouped[animation]:
			var texture := _load_import_frame_texture(frame_path)
			if texture == null: return _failure("character.import_frame_load_failed", "帧图片加载失败，导入未提交。", {"path":frame_path})
			frames.add_frame(animation, texture)
	candidate.sprite_frames = frames
	return {"ok":true, "source_kind":"semantic_direction_frame", "path":path, "animations":grouped.size(), "four_direction":complete_cardinal, "eight_direction":has_eight, "mirror_mapping_supported":true}

func _load_import_frame_texture(path: String) -> Texture2D:
	var imported: Texture2D
	if ResourceLoader.exists(path, "Texture2D"):
		imported = ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	if imported != null: return imported
	# A newly chosen frame directory may precede the editor importer. Decode the
	# local source into the isolated candidate; malformed bytes still fail closed.
	var absolute := ProjectSettings.globalize_path(path); var image := Image.new(); var error := ERR_FILE_UNRECOGNIZED
	if path.get_extension().to_lower() == "svg": error = image.load_svg_from_string(FileAccess.get_file_as_string(absolute))
	else: error = image.load(absolute)
	if error != OK or image.is_empty(): return null
	return ImageTexture.create_from_image(image)

func _apply_all_actions() -> void:
	if current_visual_set == null or current_visual_set.sprite_frames == null: _fail_operation("character.action_source_missing", "动作提交失败：请先导入表现资源。"); return
	var candidate := current_visual_set.duplicate(true) as GMCharacterVisualSet2D
	var actions: Array[GMCharacterActionSlot2D] = []
	for semantic in SEMANTICS:
		var mappings := _parse_mapping((action_mapping_boxes[semantic] as LineEdit).text)
		if not mappings.ok: _fail_operation(mappings.code, mappings.error_zh, {"semantic":semantic}); return
		var action := GMCharacterActionSlot2D.new(); action.semantic = semantic
		var mode_box := action_mode_boxes[semantic] as OptionButton; action.direction_mode = mode_box.get_item_text(mode_box.selected)
		action.allow_mirror = (action_mirror_boxes[semantic] as CheckBox).button_pressed; action.animation_by_direction = mappings.mapping
		action.loop = semantic in ["idle", "move"]; action.frame_rate = 8.0; actions.append(action)
	candidate.actions = actions
	var checked := candidate.validate_visual_set()
	if not checked.ok: _fail_operation("character.action_batch_invalid", "动作批次校验失败，原资源未修改。", {"issues":checked.issues}); return
	if not _commit_properties(current_visual_set, {&"actions":actions}, "角色五语义动作映射"): return
	_record_success("character.actions_committed", {"semantic_count":actions.size(), "undo_gateway":"EditorUndoRedoManager"}); presenter.configure(current_visual_set); _refresh_edit_log()

func _parse_mapping(text: String) -> Dictionary:
	var result := {}
	for raw in text.split(",", false):
		var pair := raw.split("=", false, 1)
		if pair.size() != 2 or pair[0].strip_edges().is_empty() or pair[1].strip_edges().is_empty(): return _failure("character.mapping_parse_failed", "方向映射格式应为 direction=animation。", {"token":raw})
		var direction := StringName(pair[0].strip_edges()); var animation := StringName(pair[1].strip_edges())
		if result.has(direction): return _failure("character.mapping_duplicate", "方向映射重复，批次未提交。", {"direction":direction})
		result[direction] = animation
	return {"ok":true, "mapping":result}

func _set_anchor_point() -> void:
	if current_visual_set == null: _fail_operation("character.edit_target_missing", "没有活动 VisualSet。"); return
	var kind := anchor_kind_box.get_item_text(anchor_kind_box.selected); var semantic := anchor_semantic_box.get_item_text(anchor_semantic_box.selected); var direction := anchor_direction_box.get_item_text(anchor_direction_box.selected); var frame := int(anchor_frame_box.value)
	var candidate := current_visual_set.duplicate(true) as GMCharacterVisualSet2D; var anchors := candidate.anchors; var target: GMCharacterAnchorTrack2D
	for anchor in anchors:
		if anchor != null and anchor.anchor_name == StringName(kind): target = anchor; break
	if target == null:
		target = GMCharacterAnchorTrack2D.new(); target.anchor_name = kind; target.anchor_kind = kind; anchors.append(target)
	var action := candidate.action_for(semantic)
	if action == null: _fail_operation("character.anchor_action_missing", "锚点引用的动作不存在。", {"semantic":semantic}); return
	var resolved: Dictionary = action.resolve_direction(direction)
	if not resolved.ok: _fail_operation(resolved.code, resolved.error_zh, resolved.details); return
	var frame_count := candidate._frame_count(resolved.animation)
	if frame < 0 or frame >= frame_count: _fail_operation("character.anchor_frame_invalid", "锚点帧超出动作帧数，原资源未修改。", {"semantic":semantic,"direction":direction,"frame":frame,"frame_count":frame_count}); return
	var point := Vector2(anchor_x_box.value, anchor_y_box.value)
	if not candidate.visual_bounds.has_point(point): _fail_operation("character.anchor_out_of_bounds", "锚点越界，原资源未修改。", {"position":point}); return
	var key := "%s/%s" % [semantic, direction]; var track: Array = target.positions.get(key, [])
	if track.size() != frame_count: track.resize(frame_count); track.fill(Vector2.ZERO)
	track[frame] = point; target.positions[key] = track; candidate.anchors = anchors
	var checked := candidate.validate_visual_set()
	if not checked.ok: _fail_operation("character.anchor_batch_invalid", "锚点提交后完整校验失败，原资源未修改。", {"issues":checked.issues}); return
	if not _commit_properties(current_visual_set, {&"anchors":candidate.anchors}, "角色锚点帧编辑"): return
	_record_success("character.anchor_point_committed", {"kind":kind,"semantic":semantic,"direction":direction,"frame":frame,"position":point,"undo_gateway":"EditorUndoRedoManager"}); _refresh_edit_log()

func _remove_anchor() -> void:
	if current_visual_set == null: return
	var kind := anchor_kind_box.get_item_text(anchor_kind_box.selected); var candidate := current_visual_set.duplicate(true) as GMCharacterVisualSet2D
	candidate.anchors = candidate.anchors.filter(func(anchor): return anchor != null and anchor.anchor_name != StringName(kind))
	if not _commit_properties(current_visual_set, {&"anchors":candidate.anchors}, "删除角色锚点"): return
	_record_success("character.anchor_removed", {"kind":kind}); _refresh_edit_log()

func _set_frame_event() -> void:
	if current_visual_set == null: _fail_operation("character.edit_target_missing", "没有活动 VisualSet。"); return
	var semantic := event_semantic_box.get_item_text(event_semantic_box.selected); var kind := event_kind_box.get_item_text(event_kind_box.selected); var event_name := event_name_box.text.strip_edges(); var frame := int(event_frame_box.value)
	if event_name.is_empty(): _fail_operation("character.event_name_missing", "事件名称不能为空。"); return
	var candidate := current_visual_set.duplicate(true) as GMCharacterVisualSet2D; var action := candidate.action_for(semantic)
	if action == null: _fail_operation("character.event_action_missing", "事件引用的动作不存在。", {"semantic":semantic}); return
	var max_count := 0
	for animation in action.animation_by_direction.values(): max_count = maxi(max_count, candidate._frame_count(StringName(animation)))
	if frame < 0 or frame >= max_count: _fail_operation("character.event_frame_invalid", "事件帧超出动作帧数，原资源未修改。", {"semantic":semantic,"frame":frame,"frame_count":max_count}); return
	var kept: Array[GMCharacterFrameEvent] = []
	for existing in action.events:
		if existing != null and not (existing.event_name == StringName(event_name) and existing.event_kind == kind): kept.append(existing)
	var event := GMCharacterFrameEvent.new(); event.event_name = event_name; event.event_kind = kind; event.frame_index = frame; event.payload = {"anchor":kind,"source":"GM角色资产库"}; kept.append(event); action.events = kept
	var checked := candidate.validate_visual_set()
	if not checked.ok: _fail_operation("character.event_batch_invalid", "事件批次校验失败，原资源未修改。", {"issues":checked.issues}); return
	if not _commit_properties(current_visual_set, {&"actions":candidate.actions}, "角色事件帧编辑"): return
	_record_success("character.frame_event_committed", {"semantic":semantic,"kind":kind,"event_name":event_name,"frame":frame,"undo_gateway":"EditorUndoRedoManager"}); _refresh_edit_log()

func _remove_frame_event() -> void:
	if current_visual_set == null: return
	var semantic := event_semantic_box.get_item_text(event_semantic_box.selected); var kind := event_kind_box.get_item_text(event_kind_box.selected); var event_name := event_name_box.text.strip_edges(); var candidate := current_visual_set.duplicate(true) as GMCharacterVisualSet2D; var action := candidate.action_for(semantic)
	if action == null: return
	action.events = action.events.filter(func(event): return event != null and not (event.event_kind == kind and str(event.event_name) == event_name))
	if not _commit_properties(current_visual_set, {&"actions":candidate.actions}, "删除角色事件帧"): return
	_record_success("character.frame_event_removed", {"semantic":semantic,"kind":kind,"event_name":event_name}); _refresh_edit_log()

func _save_resources() -> void:
	if definition_path.is_empty() or visual_set_path.is_empty() or current_visual_set == null or _canonical_res_path(current_visual_set.resource_path) != visual_set_path:
		_fail_operation("character.external_paths_required", "普通保存要求已打开的 Definition 真实引用外部 VisualSet；请先另存为。", {"definition_path":definition_path,"visual_set_path":visual_set_path}); return
	_save_to_paths(definition_path, visual_set_path)

func _save_resources_as() -> void:
	_save_to_paths(definition_path_box.text.strip_edges(), visual_path_box.text.strip_edges())

func _save_to_paths(def_path: String, visual_path: String) -> void:
	if current_definition == null or current_visual_set == null: _fail_operation("character.save_target_missing", "保存失败：没有活动 Definition/VisualSet。"); return
	def_path = _canonical_res_path(def_path); visual_path = _canonical_res_path(visual_path)
	if def_path.is_empty() or visual_path.is_empty() or def_path == visual_path: _fail_operation("character.save_path_conflict", "保存路径为空、非 res:// 或发生 Definition/VisualSet 冲突，磁盘未写入。"); return
	var checked := current_definition.validate_definition()
	if not checked.ok: _fail_operation("character.save_validation_failed", "保存前验证失败，磁盘未写入。", {"issues":checked.issues}); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(def_path).get_base_dir()); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(visual_path).get_base_dir())
	var visual_error := ResourceSaver.save(current_visual_set, visual_path)
	if visual_error != OK: _fail_operation("character.visual_save_failed", "VisualSet 保存失败，Definition 未写入。", {"error":visual_error,"path":visual_path}); return
	var external_visual := ResourceLoader.load(visual_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GMCharacterVisualSet2D
	if external_visual == null or _canonical_res_path(external_visual.resource_path) != visual_path:
		_fail_operation("character.external_visual_reload_failed", "外部 VisualSet 重载失败，Definition 未写入。", {"path":visual_path}); return
	var definition_to_save := current_definition.duplicate(true) as GMCharacterDefinition
	definition_to_save.visual_sets = [external_visual]; definition_to_save.default_visual_set_id = external_visual.visual_set_id
	var def_error := ResourceSaver.save(definition_to_save, def_path)
	if def_error != OK: _fail_operation("character.definition_save_failed", "Definition 保存失败。", {"error":def_error,"path":def_path}); return
	var reopened := ResourceLoader.load(def_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GMCharacterDefinition
	var resolved := reopened.resolve_visual_set() if reopened != null else {"ok":false}
	var resolved_visual := resolved.get("visual_set", null) as GMCharacterVisualSet2D
	if reopened == null or resolved_visual == null or _canonical_res_path(resolved_visual.resource_path) != visual_path:
		_fail_operation("character.definition_external_reference_failed", "Definition 未解析到指定外部 VisualSet，当前内存状态未切换。", {"definition_path":def_path,"expected_visual_path":visual_path,"actual_visual_path":resolved_visual.resource_path if resolved_visual != null else ""}); return
	_set_current_definition(reopened, def_path)
	_record_success("character.resources_saved", {"definition_path":def_path,"visual_set_path":visual_path,"resolved_visual_path":resolved_visual.resource_path,"external_unique_source":true,"cache_reopen":"CACHE_MODE_IGNORE"})

func _set_current_definition(definition: GMCharacterDefinition, path: String = "") -> void:
	current_definition = definition; definition_path = path
	var resolved: Dictionary = definition.resolve_visual_set(); current_visual_set = resolved.visual_set if resolved.ok else (definition.visual_sets[0] if not definition.visual_sets.is_empty() else null)
	definition_id_box.text = definition.content_id; definition_name_box.text = definition.display_name_zh
	if current_visual_set != null:
		visual_id_box.text = current_visual_set.visual_set_id; visual_name_box.text = current_visual_set.display_name_zh; visual_set_path = _canonical_res_path(current_visual_set.resource_path)
		_load_action_controls(); presenter.configure(current_visual_set)
	if not path.is_empty(): definition_path_box.text = path
	if not visual_set_path.is_empty(): visual_path_box.text = visual_set_path
	_refresh_edit_log()

func _canonical_res_path(path: String) -> String:
	var value := path.strip_edges().replace("\\", "/")
	if not value.begins_with("res://"): return ""
	return ProjectSettings.localize_path(ProjectSettings.globalize_path(value)).simplify_path()

func _load_action_controls() -> void:
	for semantic in SEMANTICS:
		var action := current_visual_set.action_for(semantic)
		if action == null: continue
		var mode := action_mode_boxes[semantic] as OptionButton
		for i in mode.item_count:
			if mode.get_item_text(i) == action.direction_mode: mode.select(i); break
		(action_mirror_boxes[semantic] as CheckBox).button_pressed = action.allow_mirror
		var tokens: Array[String] = []
		for direction in action.animation_by_direction: tokens.append("%s=%s" % [direction, action.animation_by_direction[direction]])
		(action_mapping_boxes[semantic] as LineEdit).text = ",".join(tokens)

func _validate_current() -> Dictionary:
	if current_definition == null:
		var missing := _failure("character.definition_missing", "没有活动角色定义."); _fail_operation(missing.code, missing.error_zh); return missing
	var checked := current_definition.validate_definition(); last_operation = {"ok":checked.ok,"code":"character.validation_complete","issues":checked.issues,"failure_closed":not checked.ok}
	_set_status("验证通过：五动作与锚点/事件引用完整。" if checked.ok else "验证失败且关闭：%s" % JSON.stringify(checked.issues), checked.ok); _refresh_edit_log(); return checked

func _preview_changed(_index: int = 0) -> void:
	if current_visual_set == null: return
	var result := presenter.play_semantic_action(StringName(action_option.get_item_text(action_option.selected)), StringName(direction_option.get_item_text(direction_option.selected)))
	if result.ok: presenter.seek_frame(int(frame_slider.value)); overlay.queue_redraw(); _set_status("预览与运行时共用 GMCharacterPresenter2D：%s/%s" % [result.semantic, result.direction], true)
	else: _set_status("%s [%s]" % [result.error_zh, result.code], false)

func _frame_changed(value: float) -> void:
	if presenter == null: return
	var result := presenter.seek_frame(int(value)); overlay.queue_redraw()
	if not result.ok: _set_status(str(result.error_zh), false)

func _commit_properties(target: Object, values: Dictionary, action_name: String) -> bool:
	if undo_redo == null:
		_fail_operation("character.undo_redo_missing", "EditorUndoRedoManager 不可用，修改已拒绝且资源未污染。"); return false
	undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, target)
	for property in values:
		undo_redo.add_do_property(target, property, values[property]); undo_redo.add_undo_property(target, property, target.get(property))
	undo_redo.commit_action(true)
	var history_id := undo_redo.get_object_history_id(target)
	if not character_history_ids.has(history_id): character_history_ids.append(history_id)
	return true

func _undo_character_edit() -> void:
	if undo_redo == null or current_visual_set == null: _fail_operation("character.undo_unavailable", "没有可用的角色编辑历史。"); return
	var history_id := undo_redo.get_object_history_id(current_visual_set); var history := undo_redo.get_history_undo_redo(history_id)
	if history == null or not history.has_undo(): _fail_operation("character.undo_empty", "角色编辑历史没有可撤销操作。"); return
	history.undo(); _load_action_controls(); presenter.configure(current_visual_set)
	_record_success("character.undo_completed", {"history_id":history_id,"gateway":"EditorUndoRedoManager","through_control":true})

func _redo_character_edit() -> void:
	if undo_redo == null or current_visual_set == null: _fail_operation("character.redo_unavailable", "没有可用的角色编辑历史。"); return
	var history_id := undo_redo.get_object_history_id(current_visual_set); var history := undo_redo.get_history_undo_redo(history_id)
	if history == null or not history.has_redo(): _fail_operation("character.redo_empty", "角色编辑历史没有可重做操作。"); return
	history.redo(); _load_action_controls(); presenter.configure(current_visual_set)
	_record_success("character.redo_completed", {"history_id":history_id,"gateway":"EditorUndoRedoManager","through_control":true})

func _exit_tree() -> void:
	# Release only histories owned by task11 Resource targets.  Other editor
	# histories are untouched, while reload/exit cannot retain our deep copies.
	if undo_redo != null:
		for history_id in character_history_ids:
			var history := undo_redo.get_history_undo_redo(history_id)
			if history != null: history.clear_history(false)
	character_history_ids.clear()
	current_definition = null; current_visual_set = null; selected_entry.clear(); current_entries.clear()
	if index != null: index.entries.clear(); index.issues.clear()

func _refresh_edit_log() -> void:
	if edit_log == null: return
	var anchors: Array[String] = []; var events: Array[String] = []
	if current_visual_set != null:
		for anchor in current_visual_set.anchors:
			if anchor != null: anchors.append("%s(%s): %s" % [anchor.anchor_name, anchor.anchor_kind, ", ".join(anchor.positions.keys())])
		for action in current_visual_set.actions:
			if action != null:
				for event in action.events:
					if event != null: events.append("%s/%s:%s@F%d" % [action.semantic, event.event_kind, event.event_name, event.frame_index])
	edit_log.text = "[b]锚点[/b]\n%s\n\n[b]事件帧[/b]\n%s\n\n[b]最近操作[/b]\n%s" % ["\n".join(anchors), "\n".join(events), JSON.stringify(last_operation, "  ")]

func get_public_facts() -> Dictionary:
	return {"dock":name,"definition_path":definition_path,"visual_set_path":visual_set_path,"definition_id":current_definition.content_id if current_definition != null else "","visual_set_id":current_visual_set.visual_set_id if current_visual_set != null else "","definition_visual_reference":_canonical_res_path(current_visual_set.resource_path) if current_visual_set != null else "","visual_fingerprint":_current_visual_fingerprint(),"actions":current_visual_set.actions.size() if current_visual_set != null else 0,"anchors":current_visual_set.anchors.size() if current_visual_set != null else 0,"last_operation":last_operation,"presenter":presenter.snapshot() if presenter != null else {},"undo_gateway":"EditorUndoRedoManager" if undo_redo != null else "missing"}

func _current_visual_fingerprint() -> String:
	if current_visual_set == null: return ""
	var action_rows: Array = []
	for action in current_visual_set.actions:
		if action == null: action_rows.append(null); continue
		action_rows.append({"semantic":action.semantic,"mode":action.direction_mode,"mirror":action.allow_mirror,"mapping":action.animation_by_direction,"frame_rate":action.frame_rate,"loop":action.loop,"events":action.events.map(func(event): return null if event == null else {"name":event.event_name,"kind":event.event_kind,"frame":event.frame_index,"payload":event.payload})})
	var anchor_rows: Array = []
	for anchor in current_visual_set.anchors:
		anchor_rows.append(null if anchor == null else {"name":anchor.anchor_name,"kind":anchor.anchor_kind,"positions":anchor.positions})
	var frame_rows: Array = []
	if current_visual_set.sprite_frames != null:
		var names := current_visual_set.sprite_frames.get_animation_names(); names.sort()
		for animation in names:
			var sizes: Array = []
			for frame in current_visual_set.sprite_frames.get_frame_count(animation):
				var texture := current_visual_set.sprite_frames.get_frame_texture(animation, frame)
				sizes.append(null if texture == null else Vector2i(texture.get_size()))
			frame_rows.append({"animation":animation,"count":current_visual_set.sprite_frames.get_frame_count(animation),"sizes":sizes})
	return JSON.stringify({"id":current_visual_set.visual_set_id,"name":current_visual_set.display_name_zh,"style":current_visual_set.art_style,"category":current_visual_set.category,"tags":current_visual_set.tags,"bounds":current_visual_set.visual_bounds,"actions":action_rows,"anchors":anchor_rows,"frames":frame_rows},"",true,true).sha256_text()

func _record_success(code: String, details_value: Dictionary = {}) -> void:
	last_operation = {"ok":true,"code":code,"details":details_value}; _set_status("操作完成：%s" % code, true); _refresh_edit_log()

func _fail_operation(code: String, message: String, details_value: Dictionary = {}) -> void:
	last_operation = {"ok":false,"code":code,"error_zh":message,"details":details_value,"failure_closed":true}; _set_status("%s [%s]" % [message, code], false); _refresh_edit_log()

func _set_status(message: String, ok: bool) -> void:
	if status_label == null: return
	status_label.text = message; status_label.modulate = Color("7dffad") if ok else Color("ff9b7d")

func _failure(code: String, message: String, details_value: Dictionary = {}) -> Dictionary:
	return {"ok":false,"code":code,"error_zh":message,"details":details_value}
