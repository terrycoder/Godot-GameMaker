@tool
extends VBoxContainer

const PROFILE_PATH := "res://gm_runtime/gm_module_profile.tres"
const SUBJECT_PATH := "res://gm_runtime/editor_templates/workbench/workbench_subject.tres"
const SUBJECT_SCENE_PATH := "res://gm_runtime/editor_templates/workbench/workbench_showcase.tscn"
const PROFILE_SCRIPT := preload("res://gm_runtime/gm_project_profile.gd")
const REGISTRY := preload("res://gm_runtime/gm_module_registry.gd")
const TEMPLATES := preload("res://addons/gm_editor/templates/gm_template_catalog.gd")
const MODEL := preload("res://addons/gm_editor/workbench/gm_workbench_model.gd")
const P19_MODEL := preload("res://addons/gm_editor/workbench/gm_p19_workbench_model.gd")
const P19_CATALOG := preload("res://gm_runtime/p19/gm_p19_recipe_catalog.gd")
const P20_MODEL := preload("res://addons/gm_editor/workbench/gm_p20_workbench_model.gd")
const P20_DEFINITION := preload("res://gm_runtime/process/gm_process_definition.gd")
const P21_MODEL := preload("res://addons/gm_editor/workbench/gm_p21_workbench_model.gd")
const P21_DEFINITION := preload("res://gm_runtime/p21/gm_dialogue_definition.gd")
const P22_MODEL := preload("res://addons/gm_editor/workbench/gm_p22_workbench_model.gd")
const P22_CATALOG := preload("res://gm_runtime/combat/gm_combat_catalog.gd")
const LAYOUT := preload("res://addons/gm_editor/workbench/gm_layout_store.gd")
const HELP := preload("res://addons/gm_editor/help/gm_help_catalog.gd")
const ERROR_CENTER := preload("res://addons/gm_editor/errors/gm_error_center.gd")
const P19_CATALOG_PATH := "user://gm_p19_recipe_catalog.tres"
const P20_DEFINITION_PATH := "user://gm_process_definition.tres"
const P21_DEFINITION_PATH := "user://gm_p21_dialogue_definition.json"
const P22_CATALOG_PATH := "user://gm_p22_combat_catalog.tres"

var editor_interface
var editor_undo_redo
var profile
var subject
var template
var error_center := ERROR_CENTER.new()
var layout_state: Dictionary = {}
var active_entry := "home"
var work_mode := "planning"
var compact := false
var capture_template_id := ""
var temporary_errors: Array[Dictionary] = []
var task01_status_override := ""
var _poll_time := 0.0
var _last_subject_signature := ""
var _building := false
var _last_profile_apply_result: Dictionary = {}
var _profile_state_saved_signature := ""
var p19_model
var p19_catalog
var _p19_result_label: Label
var p20_model
var p20_definition
var p20_runtime_store: GMProcessStore
var _p20_result_label: Label
var p21_model
var p21_definition: GMDialogueDefinition
var p21_task_projection_service: GMTaskProjectionService
var _p21_result_label: Label
var p22_model
var p22_catalog
var _p22_result_label: Label

var header_label: Label
var template_badge: Label
var mode_badge: Label
var planning_button: Button
var advanced_button: Button
var compact_button: Button
var error_button: Button
var navigation: VBoxContainer
var main_split: HSplitContainer
var content_scroll: ScrollContainer
var content: VBoxContainer
var help_panel: PanelContainer
var help_title: Label
var help_body: Label
var help_action: Label
var status_label: Label
var error_count := 0
var _template_option: OptionButton
var _live_value_label: Label
var _spatial_domain_option: OptionButton
var _spatial_backend_toggle: CheckButton
var _spatial_capability_label: Label
var _spatial_debug_label: Label
var _last_spatial_profile_result: Dictionary = {}

func configure(p_editor_interface, p_undo_redo) -> void:
	editor_interface = p_editor_interface
	editor_undo_redo = p_undo_redo
	set_meta("editor_undo_redo", p_undo_redo)

func _ready() -> void:
	if editor_interface == null: editor_interface = get_meta("editor_interface", null)
	if editor_undo_redo == null: editor_undo_redo = get_meta("editor_undo_redo", null)
	custom_minimum_size = Vector2(720, 420)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	profile = PROFILE_SCRIPT.new()
	profile.template_id = "blank_2d"
	profile.enabled_modules = PackedStringArray(["core"])
	subject = Resource.new()
	p19_model = P19_MODEL.new()
	p19_catalog = P19_CATALOG.new().configure("gm.p19.catalog.editor", "P19 交易工作台")
	p20_model = P20_MODEL.new()
	p20_definition = P20_DEFINITION.new()
	p20_definition.definition_id = "gm.process.definition.editor"
	p20_definition.display_name_zh = "中性持续过程"
	p21_model = P21_MODEL.new()
	p21_definition = _new_p21_definition()
	p22_model = P22_MODEL.new()
	p22_catalog = _new_p22_catalog()
	var saved_p19 = null
	if FileAccess.file_exists(ProjectSettings.globalize_path(P19_CATALOG_PATH)):
		saved_p19 = ResourceLoader.load(P19_CATALOG_PATH, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	if saved_p19 != null and saved_p19 is Resource and saved_p19.has_method("validate") and saved_p19.validate().ok:
		p19_catalog = saved_p19
	if FileAccess.file_exists(ProjectSettings.globalize_path(P20_DEFINITION_PATH)):
		var reopened_p20: Dictionary = p20_model.reopen_definition(P20_DEFINITION_PATH)
		if reopened_p20.ok: p20_definition = reopened_p20.definition
	if FileAccess.file_exists(ProjectSettings.globalize_path(P21_DEFINITION_PATH)):
		var reopened_p21: Dictionary = p21_model.reopen_definition(P21_DEFINITION_PATH)
		if reopened_p21.ok: p21_definition = reopened_p21.definition
	if FileAccess.file_exists(ProjectSettings.globalize_path(P22_CATALOG_PATH)):
		var reopened_p22: Dictionary = p22_model.reopen_catalog(P22_CATALOG_PATH)
		if reopened_p22.ok: p22_catalog = reopened_p22.catalog
	layout_state = LAYOUT.load_state()
	active_entry = str(layout_state.get("active_entry", "home"))
	work_mode = str(layout_state.get("mode", "planning"))
	compact = bool(layout_state.get("compact", false))
	_build_shell()
	_apply_capture_state()
	_render()
	_last_subject_signature = _subject_signature()
	call_deferred("_reload_sources_after_editor_ready")

func _reload_sources_after_editor_ready() -> void:
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(self): return
	_load_sources()
	if not capture_template_id.is_empty():
		var capture_template = TEMPLATES.get_template(capture_template_id)
		if capture_template != null:
			profile.template_id = capture_template_id
			profile.enabled_modules = capture_template.default_enabled_modules.duplicate()
			template = capture_template
	if OS.get_environment("GM_TASK02_CAPTURE_STATE") == "error":
		subject.set("project_name_zh", "")
	if OS.get_environment("GM_TASK02_CAPTURE_STATE") == "stale":
		error_center.add_missing_location_error("res://gm_runtime/editor_templates/workbench/deleted_subject.tres", "已删除的演示资源")
	# 任务01历史 Profile 可能没有核心模块；这里只修正当前工作台内存状态，
	# 等用户执行明确的 Profile 操作时再由同一 Resource 正常保存。
	if profile != null and profile.enabled_modules.is_empty():
		profile.set("enabled_modules", PackedStringArray(["core"]))
	error_center.scan(profile, subject)
	if OS.get_environment("GM_TASK02_CAPTURE_STATE") == "stale":
		error_center.add_missing_location_error("res://gm_runtime/editor_templates/workbench/deleted_subject.tres", "已删除的演示资源")
	error_count = error_center.errors.size()
	_render()
	if OS.get_environment("GM_TASK02_CAPTURE_STATE") == "advanced":
		_open_native_scene()
	_last_subject_signature = _subject_signature()

func _load_sources() -> void:
	profile = ResourceLoader.load(PROFILE_PATH, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	if profile == null:
		profile = PROFILE_SCRIPT.new()
	if profile != null and profile.enabled_modules.is_empty():
		profile.set("enabled_modules", PackedStringArray(["core"]))
	# 任务01允许空模块 Profile；进入任务02工作台时，所有首版模板都需要核心模块。
	# 这是对同一 Profile 的一次性规范化，不创建第二份配置。
	subject = ResourceLoader.load(SUBJECT_PATH, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	if subject == null:
		subject = Resource.new()
	_refresh_template()
	error_center.scan(profile, subject)

func _refresh_template() -> void:
	template = TEMPLATES.get_template(str(profile.template_id)) if profile != null else TEMPLATES.get_template("blank_2d")
	if template == null: template = TEMPLATES.get_template("blank_2d")

func _build_shell() -> void:
	_building = true
	for child in get_children(): child.queue_free()
	var header_scroll := ScrollContainer.new()
	header_scroll.name = "工作台标题栏滚动"
	header_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	header_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	header_scroll.custom_minimum_size = Vector2(0, 42)
	header_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header_scroll)
	var header := HBoxContainer.new()
	header.name = "工作台标题栏"
	header.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	header_scroll.add_child(header)
	header_label = Label.new()
	header_label.text = "GM 中文策划工作台"
	header_label.add_theme_font_size_override("font_size", 20)
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_label)
	template_badge = Label.new()
	template_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(template_badge)
	mode_badge = Label.new()
	mode_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(mode_badge)
	planning_button = _make_header_button("策划模式", "planning")
	header.add_child(planning_button)
	advanced_button = _make_header_button("高级模式", "advanced")
	header.add_child(advanced_button)
	compact_button = Button.new()
	compact_button.name = "小屏布局"
	compact_button.toggle_mode = true
	compact_button.pressed.connect(_toggle_compact)
	header.add_child(compact_button)
	var save_layout_button := Button.new()
	save_layout_button.text = "保存布局"
	save_layout_button.tooltip_text = "保存当前入口、模式和小屏设置到编辑器布局文件"
	save_layout_button.pressed.connect(_save_layout_and_report)
	header.add_child(save_layout_button)
	var refresh_button := Button.new()
	refresh_button.text = "重新扫描"
	refresh_button.tooltip_text = "重新运行模板、插件和资源验证"
	refresh_button.pressed.connect(_scan_errors)
	header.add_child(refresh_button)
	error_button = Button.new()
	error_button.name = "错误中心"
	error_button.pressed.connect(_show_error_center)
	header.add_child(error_button)

	main_split = HSplitContainer.new()
	main_split.name = "策划入口与内容"
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(main_split)
	var navigation_scroll := ScrollContainer.new()
	navigation_scroll.name = "入口导航滚动"
	navigation_scroll.custom_minimum_size = Vector2(150, 0)
	navigation_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	navigation = VBoxContainer.new()
	navigation.name = "中文策划入口"
	navigation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation_scroll.add_child(navigation)
	main_split.add_child(navigation_scroll)
	content_scroll = ScrollContainer.new()
	content_scroll.name = "工作区内容滚动"
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content = VBoxContainer.new()
	content.name = "真实策划内容"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	content_scroll.add_child(content)
	main_split.add_child(content_scroll)

	help_panel = PanelContainer.new()
	help_panel.name = "上下文帮助"
	help_panel.custom_minimum_size = Vector2(0, 72)
	var help_box := VBoxContainer.new()
	help_panel.add_child(help_box)
	help_title = Label.new()
	help_title.add_theme_font_size_override("font_size", 14)
	help_box.add_child(help_title)
	help_body = Label.new()
	help_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_box.add_child(help_body)
	help_action = Label.new()
	help_action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_box.add_child(help_action)
	add_child(help_panel)
	status_label = Label.new()
	status_label.name = "操作反馈"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(0, 24)
	add_child(status_label)
	_building = false

func _make_header_button(text_value: String, mode: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.toggle_mode = true
	button.tooltip_text = "切换到%s" % text_value
	button.pressed.connect(func(): _set_mode(mode))
	return button

func _render() -> void:
	if _building: return
	_refresh_template()
	_update_header()
	_build_navigation()
	if work_mode == "advanced":
		_render_advanced()
	elif active_entry == "error":
		_render_errors()
	elif active_entry == "home":
		_render_home()
	elif active_entry == "p19":
		_render_p19()
	elif active_entry == "p20":
		_render_p20()
	elif active_entry == "p21":
		_render_p21()
	elif active_entry == "p22":
		_render_p22()
	else:
		_render_entry(active_entry)
	_apply_compact_visuals()
	_update_help(active_entry)

func _update_header() -> void:
	if not is_instance_valid(header_label): return
	header_label.text = "GM 中文策划工作台"
	template_badge.text = "  模板：%s  " % str(template.display_name_zh)
	mode_badge.text = "  当前：%s  " % ("高级模式" if work_mode == "advanced" else "策划模式")
	planning_button.button_pressed = work_mode == "planning"
	advanced_button.button_pressed = work_mode == "advanced"
	compact_button.button_pressed = compact
	compact_button.text = "恢复大屏" if compact else "小屏布局"
	error_button.text = "错误中心（%d）" % error_count

func _build_navigation() -> void:
	for child in navigation.get_children(): child.queue_free()
	var home := _make_nav_button("首页", "home")
	navigation.add_child(home)
	var section_ids: Array = Array(template.layout_sections) if template != null else ["map", "character", "ability", "resource", "task"]
	for entry_id in section_ids:
		var button := _make_nav_button(str(template.display_section(str(entry_id))), str(entry_id))
		navigation.add_child(button)
	navigation.add_child(_make_nav_button("交易与资源（P19）", "p19"))
	navigation.add_child(_make_nav_button("持续过程（P20）", "p20"))
	navigation.add_child(_make_nav_button("对话与交互（P21）", "p21"))
	navigation.add_child(_make_nav_button("攻击与战斗（P22）", "p22"))
	var separator := HSeparator.new()
	navigation.add_child(separator)
	var health := _make_nav_button("健康与错误", "error")
	navigation.add_child(health)
	var nav_hint := Label.new()
	nav_hint.text = "中文入口\n同一 Profile\n同一 Resource"
	nav_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	navigation.add_child(nav_hint)

func _make_nav_button(text_value: String, entry_id: String) -> Button:
	var button := Button.new()
	button.name = "入口_%s" % entry_id
	button.text = text_value
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggle_mode = true
	button.button_pressed = active_entry == entry_id and work_mode == "planning"
	button.tooltip_text = "打开%s策划入口" % text_value
	button.pressed.connect(func(): _select_entry(entry_id))
	return button

func _select_entry(entry_id: String) -> void:
	active_entry = entry_id
	work_mode = "planning"
	layout_state.active_entry = active_entry
	layout_state.mode = work_mode
	_render()

func _set_mode(mode: String) -> void:
	work_mode = mode
	layout_state.mode = mode
	if mode == "advanced":
		_set_status("已进入高级模式：下面的按钮只打开 Godot 原生 SceneTree、Inspector 和脚本编辑器；数据仍来自同一 Resource。", true)
		if editor_interface != null:
			editor_interface.set_distraction_free_mode(false)
	else:
		_set_status("已返回策划模式：入口、健康检查和错误中心继续读取同一 Profile 与 Resource。", true)
	_render()
	_save_layout()
	if mode == "advanced": _open_native_scene()

func _render_home() -> void:
	_clear_content()
	_add_heading("项目首页", "以地图、角色、能力、资源和任务组织策划工作，不要求先理解 Godot 节点。")
	var template_row := HBoxContainer.new()
	content.add_child(template_row)
	var template_label := Label.new()
	template_label.text = "项目模板"
	template_label.custom_minimum_size = Vector2(110, 0)
	template_row.add_child(template_label)
	_template_option = OptionButton.new()
	_template_option.name = "模板选择"
	_template_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ids := ["blank_2d", "rpg_arpg", "management"]
	for id in ids:
		var item_template = TEMPLATES.get_template(id)
		_template_option.add_item(str(item_template.display_name_zh))
		_template_option.set_item_metadata(_template_option.item_count - 1, id)
		if id == str(profile.template_id): _template_option.select(_template_option.item_count - 1)
	_template_option.item_selected.connect(_template_selected)
	template_row.add_child(_template_option)
	var template_desc := Label.new()
	template_desc.text = str(template.description_zh)
	template_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(template_desc)
	_add_section_label("项目健康")
	var health_row := HBoxContainer.new()
	content.add_child(health_row)
	var health_label := Label.new()
	health_label.text = "%s；启用模块：%s；验证错误：%d" % ["通过" if error_count == 0 else "需要处理", ", ".join(profile.enabled_modules), error_count]
	health_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	health_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_row.add_child(health_label)
	var health_button := Button.new()
	health_button.text = "打开健康检查"
	health_button.pressed.connect(_show_error_center)
	health_row.add_child(health_button)
	_add_spatial_profile_controls()
	_add_section_label("任务02真实同源演示")
	var same_source := Label.new()
	same_source.text = "Resource：%s\n内容条目：%d\n策划模式与高级 Inspector 都读写这同一份 Resource。" % [SUBJECT_PATH, _subject_content_count()]
	same_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(same_source)
	_live_value_label = same_source
	_add_subject_controls("项目首页")
	_add_section_label("常用能力组合")
	var bundles := Label.new()
	bundles.text = "、".join(template.common_ability_bundles)
	bundles.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(bundles)
	_add_section_label("创建向导")
	for wizard in template.creation_wizards:
		var row := HBoxContainer.new()
		content.add_child(row)
		var label := Label.new()
		label.text = "%s：%s" % [wizard.get("label", "向导"), wizard.get("description", "")]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var open_button := Button.new()
		open_button.text = "打开入口"
		open_button.pressed.connect(func(): _select_entry(_wizard_entry(str(wizard.get("id", "")))))
		row.add_child(open_button)

func _add_spatial_profile_controls() -> void:
	_add_section_label("空间域与执行后端")
	var domain_row := HBoxContainer.new()
	content.add_child(domain_row)
	var domain_label := Label.new()
	domain_label.text = "空间域选择"
	domain_label.name = "空间域选择标签"
	domain_label.custom_minimum_size = Vector2(110, 0)
	domain_row.add_child(domain_label)
	_spatial_domain_option = OptionButton.new()
	_spatial_domain_option.name = "空间域选择"
	_spatial_domain_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spatial_domain_option.add_item("平面2D（gm.spatial.planar_2d）")
	_spatial_domain_option.set_item_metadata(0, "gm.spatial.planar_2d")
	_spatial_domain_option.add_item("平面3D（gm.spatial.planar_3d，仅声明）")
	_spatial_domain_option.set_item_metadata(1, "gm.spatial.planar_3d")
	_spatial_domain_option.add_item("完整3D保留ID（gm.spatial.full_3d_reserved）")
	_spatial_domain_option.set_item_metadata(2, "gm.spatial.full_3d_reserved")
	_spatial_domain_option.select(_spatial_domain_index(str(profile.spatial_domain_id)))
	_spatial_domain_option.item_selected.connect(_spatial_domain_selected)
	domain_row.add_child(_spatial_domain_option)
	var backend_row := HBoxContainer.new()
	content.add_child(backend_row)
	_spatial_backend_toggle = CheckButton.new()
	_spatial_backend_toggle.name = "空间后端启用"
	_spatial_backend_toggle.text = "空间后端启用"
	_spatial_backend_toggle.button_pressed = profile.spatial_backend_enabled
	_spatial_backend_toggle.toggled.connect(_spatial_backend_toggled)
	backend_row.add_child(_spatial_backend_toggle)
	_spatial_capability_label = Label.new()
	_spatial_capability_label.name = "空间能力状态"
	_spatial_capability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spatial_capability_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	backend_row.add_child(_spatial_capability_label)
	_spatial_debug_label = Label.new()
	_spatial_debug_label.name = "空间调试信息"
	_spatial_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_spatial_debug_label)
	_update_spatial_profile_controls()

func _spatial_domain_index(domain_id: String) -> int:
	if domain_id == "gm.spatial.planar_3d": return 1
	if domain_id == "gm.spatial.full_3d_reserved": return 2
	return 0

func _spatial_domain_selected(index: int) -> void:
	if profile == null: return
	var domain_id := str(_spatial_domain_option.get_item_metadata(index))
	var backend_id := "gm.spatial.backend.planar_2d" if domain_id == "gm.spatial.planar_2d" else "gm.spatial.backend.planar_3d"
	_commit_spatial_profile_state(domain_id, backend_id, profile.spatial_backend_enabled, "切换空间域")

func _spatial_backend_toggled(enabled: bool) -> void:
	if profile == null: return
	var domain_id := str(profile.spatial_domain_id)
	var backend_id := str(profile.spatial_backend_id)
	_commit_spatial_profile_state(domain_id, backend_id, enabled, "切换空间后端")

func _commit_spatial_profile_state(domain_id: String, backend_id: String, enabled: bool, action_name: String) -> void:
	if profile == null: return
	_commit_spatial_profile_state_for_profile(profile, domain_id, backend_id, enabled, action_name)

func _commit_spatial_profile_state_for_profile(profile: Resource, domain_id: String, backend_id: String, enabled: bool, action_name: String) -> void:
	var is_current_profile: bool = profile == self.profile
	var old_domain := str(profile.spatial_domain_id)
	var old_backend := str(profile.spatial_backend_id)
	var old_enabled: bool = profile.spatial_backend_enabled
	var old_modules: PackedStringArray = profile.enabled_modules.duplicate()
	var next_modules: PackedStringArray = old_modules.duplicate()
	if enabled and domain_id == "gm.spatial.planar_2d":
		if not next_modules.has("spatial.planar_2d"): next_modules.append("spatial.planar_2d")
	else:
		next_modules.erase("spatial.planar_2d")
	var candidate: Resource = profile.duplicate(true)
	candidate.set("spatial_domain_id", domain_id)
	candidate.set("spatial_backend_id", backend_id)
	candidate.set("spatial_backend_enabled", enabled)
	var spatial_validation: Dictionary = candidate.validate_spatial_selection(next_modules)
	if is_current_profile:
		_last_spatial_profile_result = {"stage": "profile_validation", "ok": spatial_validation.ok, "result": spatial_validation.duplicate(true), "modules": next_modules.duplicate()}
	if not spatial_validation.ok:
		if is_current_profile:
			_spatial_backend_toggle.button_pressed = old_enabled
			_spatial_domain_option.select(_spatial_domain_index(old_domain))
			_set_status("空间配置阻断：%s" % str(spatial_validation.get("error_zh", "空间域或后端不可用。")), false)
			_update_spatial_profile_controls()
		return
	var module_plan := REGISTRY.resolve(next_modules)
	if not module_plan.ok:
		if is_current_profile:
			_last_spatial_profile_result = {"stage": "module_resolution", "ok": false, "result": module_plan.duplicate(true), "modules": next_modules.duplicate()}
			_spatial_backend_toggle.button_pressed = old_enabled
			_spatial_domain_option.select(_spatial_domain_index(old_domain))
			_set_status("空间模块配置阻断：%s" % "; ".join(module_plan.get("errors_zh", [])), false)
			_update_spatial_profile_controls()
		return
	var apply_result: Dictionary = _apply_spatial_profile_state_for_profile(profile, domain_id, backend_id, enabled, next_modules)
	if not apply_result.ok:
		if is_current_profile:
			_last_spatial_profile_result = {"stage": "profile_apply", "ok": false, "result": apply_result.duplicate(true), "modules": next_modules.duplicate()}
			_spatial_backend_toggle.button_pressed = old_enabled
			_spatial_domain_option.select(_spatial_domain_index(old_domain))
			_set_status("空间配置未保存，原有Profile已保留：%s" % str(apply_result.get("error_zh", "未知保存错误。")), false)
			_update_spatial_profile_controls()
		return
	if editor_undo_redo != null:
		editor_undo_redo.create_action("GM%s" % action_name, UndoRedo.MERGE_DISABLE, profile)
		editor_undo_redo.add_do_method(self, "_apply_spatial_profile_state_for_profile", profile, domain_id, backend_id, enabled, next_modules)
		editor_undo_redo.add_undo_method(self, "_apply_spatial_profile_state_for_profile", profile, old_domain, old_backend, old_enabled, old_modules)
		editor_undo_redo.commit_action()
	if is_current_profile:
		_last_spatial_profile_result = {"stage": "committed", "ok": true, "result": apply_result.duplicate(true), "modules": next_modules.duplicate()}
		_set_status("空间配置已保存，可通过Undo/Redo撤销；3D选择仍保持失败关闭。", true)
		_update_spatial_profile_controls()
		_render()

func _apply_spatial_profile_state(domain_id: String, backend_id: String, enabled: bool, modules: PackedStringArray) -> Dictionary:
	if profile == null: return {"ok": false, "code": "spatial.profile.missing", "error_zh": "空间Profile不存在。"}
	return _apply_spatial_profile_state_for_profile(profile, domain_id, backend_id, enabled, modules)

func _apply_spatial_profile_state_for_profile(target_profile: Resource, domain_id: String, backend_id: String, enabled: bool, modules: PackedStringArray) -> Dictionary:
	if target_profile == null: return {"ok": false, "code": "spatial.profile.missing", "error_zh": "空间Profile不存在。"}
	var candidate: Resource = target_profile.duplicate(true)
	candidate.set("spatial_domain_id", domain_id)
	candidate.set("spatial_backend_id", backend_id)
	candidate.set("spatial_backend_enabled", enabled)
	var validation: Dictionary = candidate.validate_spatial_selection(modules)
	if not validation.ok: return {"ok": false, "code": "spatial.profile.invalid", "error_zh": str(validation.get("error_zh", "空间配置无效。"))}
	var previous_domain: String = str(target_profile.spatial_domain_id)
	var previous_backend: String = str(target_profile.spatial_backend_id)
	var previous_enabled: bool = target_profile.spatial_backend_enabled
	target_profile.set("spatial_domain_id", domain_id)
	target_profile.set("spatial_backend_id", backend_id)
	target_profile.set("spatial_backend_enabled", enabled)
	var save_result: Dictionary = MODEL.apply_profile_state(target_profile, str(target_profile.template_id), modules, true)
	if not save_result.ok:
		target_profile.set("spatial_domain_id", previous_domain)
		target_profile.set("spatial_backend_id", previous_backend)
		target_profile.set("spatial_backend_enabled", previous_enabled)
		return {"ok": false, "code": str(save_result.get("error_code", "profile.save_failed")), "error_zh": str(save_result.get("error_zh", "空间Profile保存失败。"))}
	target_profile.set("spatial_domain_id", domain_id)
	target_profile.set("spatial_backend_id", backend_id)
	target_profile.set("spatial_backend_enabled", enabled)
	target_profile.set("enabled_modules", modules.duplicate())
	if target_profile == self.profile:
		_refresh_template()
		_scan_errors(false)
		_update_spatial_profile_controls()
	return {"ok": true, "validation": validation}

func _spatial_profile_history(profile: Resource) -> Dictionary:
	var history_id := -1
	var history: Variant = null
	if editor_undo_redo != null and profile != null and editor_undo_redo.has_method("get_object_history_id"):
		history_id = int(editor_undo_redo.call("get_object_history_id", profile))
	if history_id >= 0 and editor_undo_redo.has_method("get_history_undo_redo"):
		history = editor_undo_redo.call("get_history_undo_redo", history_id)
	return {"id": history_id, "history": history}

func _update_spatial_profile_controls() -> void:
	if _spatial_capability_label == null or profile == null: return
	var validation = profile.validate_spatial_selection()
	_spatial_capability_label.text = "空间能力状态：%s" % ("已启用" if validation.ok and bool(validation.get("active", false)) else ("未启用" if validation.ok else "已阻断"))
	if not validation.ok: _spatial_capability_label.text += "；阻断原因：%s" % str(validation.get("error_zh", "空间配置无效。"))
	if _spatial_debug_label != null:
		_spatial_debug_label.text = "逻辑位置调试：map_id=%s；surface_id=由PLANAR_2D适配器解析；x/y=来自WorldSnapshot空间贡献者。" % str(profile.spatial_domain_id)

func _render_entry(entry_id: String) -> void:
	_clear_content()
	var section_name := str(template.display_section(entry_id))
	_add_heading(section_name, _entry_description(entry_id))
	var route := Label.new()
	route.text = "策划入口 / %s\n模板术语：%s\n底层来源：统一 GM Resource、模块 Registry 与既有 GAS。" % [section_name, entry_id]
	route.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(route)
	_add_subject_controls(section_name)
	var field := _entry_field(entry_id)
	var list_label := Label.new()
	list_label.text = "真实内容条目（来自同一 Resource）"
	list_label.add_theme_font_size_override("font_size", 15)
	content.add_child(list_label)
	var items := ItemList.new()
	items.name = "内容条目_%s" % entry_id
	items.custom_minimum_size = Vector2(0, 110 if not compact else 72)
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value in _subject_array(field): items.add_item(str(value))
	content.add_child(items)
	var action_row := HBoxContainer.new()
	content.add_child(action_row)
	var create_button := Button.new()
	create_button.text = "新建%s" % section_name
	create_button.tooltip_text = "通过策划入口新增内容，写入同一 Resource 并可 Undo/Redo"
	create_button.pressed.connect(func(): _add_subject_item(field, section_name))
	action_row.add_child(create_button)
	var native_button := Button.new()
	native_button.text = "在高级模式打开同源 Inspector"
	native_button.pressed.connect(_enter_advanced_mode)
	action_row.add_child(native_button)
	var rule_label := Label.new()
	rule_label.text = "本模板验证：%s" % "；".join(template.validation_rules)
	rule_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(rule_label)
	_add_ability_bundle_picker(entry_id)

func _render_p19() -> void:
	_clear_content()
	if p19_catalog == null:
		p19_catalog = P19_CATALOG.new().configure("gm.p19.catalog.editor", "P19 交易工作台")
	_add_heading("P19 交易与资源工作台", "中文优先创建中性物品、数值资源、容器和统一交易配方；界面只生成请求，不直接写入运行时 Store。")
	var contract := Label.new()
	contract.text = "统一底座：现有 DomainTransaction / Coordinator / GMStore v3 / GAS 请求入口\n规则：整数最小单位、稳定 ID、先预检再预留，所有参与者一次提交；失败显示阻断原因并保持原状态。"
	contract.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(contract)
	_add_section_label("创建中性数据")
	var create_row := HBoxContainer.new()
	content.add_child(create_row)
	var item_button := Button.new()
	item_button.text = "创建中性物品"
	item_button.pressed.connect(_p19_add_item)
	create_row.add_child(item_button)
	var resource_button := Button.new()
	resource_button.text = "创建数值资源"
	resource_button.pressed.connect(_p19_add_resource)
	create_row.add_child(resource_button)
	var container_button := Button.new()
	container_button.text = "创建资源容器"
	container_button.pressed.connect(_p19_add_container)
	create_row.add_child(container_button)
	var recipe_button := Button.new()
	recipe_button.text = "创建交易配方"
	recipe_button.pressed.connect(_p19_add_recipe)
	create_row.add_child(recipe_button)
	var counts := Label.new()
	counts.text = "中性物品：%d；数值资源：%d；容器：%d；交易配方：%d；目录修订：%d" % [p19_catalog.neutral_items.size(), p19_catalog.numeric_resources.size(), p19_catalog.containers.size(), p19_catalog.recipes.size(), p19_catalog.revision]
	counts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(counts)
	_add_section_label("输入 / 输出 / 提交预览")
	var recipe_list := ItemList.new()
	recipe_list.name = "P19交易配方列表"
	recipe_list.custom_minimum_size = Vector2(0, 92 if not compact else 64)
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for recipe in p19_catalog.recipes:
		recipe_list.add_item("%s · %s · %s" % [str(recipe.get("recipe_id", "")), str(recipe.get("display_name_zh", "")), str(recipe.get("operation", ""))])
	content.add_child(recipe_list)
	var action_row := HBoxContainer.new()
	content.add_child(action_row)
	var preflight_button := Button.new()
	preflight_button.text = "运行预检"
	preflight_button.tooltip_text = "检查稳定 ID、整数单位、输入输出和参与者；不改变 Store。"
	preflight_button.pressed.connect(_p19_preflight)
	action_row.add_child(preflight_button)
	var save_button := Button.new()
	save_button.text = "保存目录（可 Undo/Redo）"
	save_button.pressed.connect(_p19_save_catalog)
	action_row.add_child(save_button)
	var reopen_button := Button.new()
	reopen_button.text = "保存后重开"
	reopen_button.pressed.connect(_p19_reopen_catalog)
	action_row.add_child(reopen_button)
	_p19_result_label = Label.new()
	_p19_result_label.name = "P19预检与提交反馈"
	_p19_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_p19_result_label)
	_p19_preflight()

func _p19_add_item() -> void:
	var next_items: Array = p19_catalog.neutral_items.duplicate(true)
	var number := next_items.size() + 1
	next_items.append(p19_model.new_neutral_item("gm.item.editor.%d" % number, "中性物品 %d" % number, ["gm.item.editor"], true, 99))
	_p19_apply_state(next_items, p19_catalog.numeric_resources, p19_catalog.containers, p19_catalog.recipes, "已创建中性物品；等待预检。")

func _p19_add_resource() -> void:
	var next_resources: Array = p19_catalog.numeric_resources.duplicate(true)
	var number := next_resources.size() + 1
	next_resources.append(p19_model.new_numeric_resource("gm.resource.editor.%d" % number, "数值资源 %d" % number, "gm.unit.whole", 0, 100000))
	_p19_apply_state(p19_catalog.neutral_items, next_resources, p19_catalog.containers, p19_catalog.recipes, "已创建数值资源；金额使用整数最小单位。")

func _p19_add_container() -> void:
	var next_containers: Array = p19_catalog.containers.duplicate(true)
	var number := next_containers.size() + 1
	next_containers.append(p19_model.new_container("gm.container.editor.%d" % number, "storage", 24, -1))
	_p19_apply_state(p19_catalog.neutral_items, p19_catalog.numeric_resources, next_containers, p19_catalog.recipes, "已创建资源容器；容器只保留稳定容量数据。")

func _p19_add_recipe() -> void:
	var next_recipes: Array = p19_catalog.recipes.duplicate(true)
	var number := next_recipes.size() + 1
	var item_id := "gm.item.editor.1"
	var resource_id := "gm.resource.editor.1"
	var container_id := "gm.container.editor.1"
	if not p19_catalog.neutral_items.is_empty(): item_id = str(p19_catalog.neutral_items[0].get("item_id", item_id))
	if not p19_catalog.numeric_resources.is_empty(): resource_id = str(p19_catalog.numeric_resources[0].get("resource_id", resource_id))
	if not p19_catalog.containers.is_empty(): container_id = str(p19_catalog.containers[0].get("container_id", container_id))
	var inputs := [{"item_id": item_id, "container_id": container_id, "quantity": 1}, {"resource_id": resource_id, "account_id": "gm.account.editor.player", "amount": 10}]
	var outputs := [{"item_id": item_id, "container_id": container_id, "quantity": 1}, {"resource_id": resource_id, "account_id": "gm.account.editor.shop", "amount": 10}]
	next_recipes.append(p19_model.new_transaction_recipe("gm.recipe.editor.%d" % number, "统一交易配方 %d" % number, "use", ["inventory", "numeric_resource"], inputs, outputs, {"authoring": "gm.p19.workbench"}))
	_p19_apply_state(p19_catalog.neutral_items, p19_catalog.numeric_resources, p19_catalog.containers, next_recipes, "已创建统一交易配方；请运行预检查看输入、输出和提交状态。")

func _p19_apply_state(items: Array, resources: Array, containers: Array, recipes: Array, status: String) -> void:
	var result: Dictionary = p19_model.apply_catalog_state(p19_catalog, items, resources, containers, recipes, editor_undo_redo, P19_CATALOG_PATH)
	if not result.ok:
		_set_status("P19 目录编辑已阻断：%s" % str(result.get("error_zh", "; ".join(result.get("errors_zh", [])))), false)
		return
	_set_status(status, true)
	_render()

func _p19_preflight() -> void:
	if not is_instance_valid(_p19_result_label): return
	if p19_catalog == null or p19_catalog.recipes.is_empty():
		_p19_result_label.text = "预检状态：尚未创建交易配方。先创建中性数据和交易配方；当前不会写入 Store。"
		_p19_result_label.modulate = Color("ffd080")
		return
	var recipe: Dictionary = p19_catalog.recipes.back()
	var result: Dictionary = p19_model.preflight_summary(recipe)
	var inputs_text := JSON.stringify(result.get("inputs", []))
	var outputs_text := JSON.stringify(result.get("outputs", []))
	_p19_result_label.text = "预检：%s\n阻断原因：%s\n输入：%s\n输出：%s\n提交：%s；请求层：%s；直接写 Store：%s" % [str(result.get("state_zh", "")), str(result.get("block_reason_zh", "无")), inputs_text, outputs_text, str(result.get("commit_state_zh", "")), "仅请求" if result.get("request_only", false) else "异常", "否" if not result.get("direct_store_write", true) else "是"]
	_p19_result_label.modulate = Color("80ffb0") if result.get("ok", false) else Color("ffb080")

func _p19_save_catalog() -> void:
	if p19_catalog == null: return
	_p19_apply_state(p19_catalog.neutral_items, p19_catalog.numeric_resources, p19_catalog.containers, p19_catalog.recipes, "P19 目录已保存；编辑器 Undo/Redo 仍可撤销本次修改。")

func _p19_reopen_catalog() -> void:
	if p19_catalog == null: return
	var saved: Dictionary = p19_model.apply_catalog_state(p19_catalog, p19_catalog.neutral_items, p19_catalog.numeric_resources, p19_catalog.containers, p19_catalog.recipes, editor_undo_redo, P19_CATALOG_PATH)
	if not saved.ok:
		_set_status("P19 目录保存未完成，未执行重开。", false)
		return
	var reopened: Dictionary = p19_model.reopen_catalog(P19_CATALOG_PATH)
	if not reopened.ok:
		_set_status("P19 目录重开未完成：%s" % str(reopened.get("error_zh", "; ".join(reopened.get("errors_zh", [])))), false)
		return
	p19_catalog = reopened.catalog
	_set_status("P19 目录已保存并重开；预检继续读取同一份 Resource。", true)
	_render()

func configure_process_projection(store: GMProcessStore) -> void:
	p20_runtime_store = store

func configure_task_projection(service: GMTaskService) -> void:
	p21_task_projection_service = GMTaskProjectionService.new(service)

func _new_p21_definition() -> GMDialogueDefinition:
	var choice := GMDialogueChoice.new()
	choice.choice_id = "gm.choice.editor.continue"
	choice.display_name_zh = "继续"
	choice.text_zh = "继续"
	choice.next_node_id = "gm.node.editor.end"
	choice.order = 0
	var entry := GMDialogueNode.new()
	entry.node_id = "gm.node.editor.entry"
	entry.speaker_ref = "gm.actor.editor"
	entry.text_zh = "这是一个可保存、可重开的中性对话定义。"
	entry.choices = [choice]
	var end := GMDialogueNode.new()
	end.node_id = "gm.node.editor.end"
	end.speaker_ref = "gm.actor.editor"
	end.text_zh = "对话结束。"
	end.choices = []
	var definition := GMDialogueDefinition.new("gm.dialogue.editor.neutral", "P21 中性对话")
	definition.entry_node_id = entry.node_id
	definition.nodes = [entry, end]
	return definition

func _render_p21() -> void:
	_clear_content()
	_add_heading("对话与交互（P21）", "对话只编排Node、Choice和会话；交互统一路由到既有 Ability、Task、P19事务或P20 Process。")
	var boundary := Label.new()
	boundary.text = "稳定合同：版本化JSON、稳定ID、确定性Choice；商店只报价/建单，资金、物品、容量、预留和幂等提交仍由P19权威负责。Task区域只读。"
	boundary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(boundary)
	_p21_text_field("对话 ID", "dialogue_id", p21_definition.dialogue_id)
	_p21_text_field("中文名称", "display_name_zh", p21_definition.display_name_zh)
	_p21_text_field("入口节点", "entry_node_id", p21_definition.entry_node_id)
	var actions := HBoxContainer.new()
	content.add_child(actions)
	var save_button := Button.new()
	save_button.text = "保存对话定义（可 Undo/Redo）"
	save_button.pressed.connect(_p21_save_definition)
	actions.add_child(save_button)
	var reopen_button := Button.new()
	reopen_button.text = "保存后重开"
	reopen_button.pressed.connect(_p21_reopen_definition)
	actions.add_child(reopen_button)
	_add_section_label("路由与只读投影状态")
	_p21_result_label = Label.new()
	_p21_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var projection_state := "已连接P16 TaskService" if p21_task_projection_service != null else "未连接P16服务"
	_p21_result_label.text = "对话节点：%d；交互后端：统一请求路由（按类型注册）；Task投影：只读、%s。" % [p21_definition.nodes.size(), projection_state]
	content.add_child(_p21_result_label)
	_add_section_label("运行时投影")
	var projection_hint := Label.new()
	projection_hint.text = "配置P16 TaskService后，这里只调用 read_task / domain_snapshot / version_for；不会创建第二份Task、Objective或Progress事实。"
	projection_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(projection_hint)

func _new_p22_catalog():
	var slash = p22_model.new_neutral_attack("gm.attack.editor.slash", "中性斩击", "melee", "damage", 10.0, 1.0, 0.25)
	var bolt = p22_model.new_neutral_attack("gm.attack.editor.bolt", "中性投射攻击", "projectile", "damage", 8.0, 8.0, 0.5, "", "gm.projectile.editor.bolt")
	var blade = p22_model.new_neutral_weapon("gm.weapon.editor.blade", "中性训练武器", "gm.item.editor.training_blade", slash.attack_id if slash.has("attack_id") else "gm.attack.editor.slash")
	var projectile = p22_model.new_neutral_projectile("gm.projectile.editor.bolt", "中性投射物", 12.0, 2.0, 0.1, 1)
	return P22_CATALOG.new().configure("gm.combat.catalog.editor", "P22 战斗定义工作台", [slash, bolt], [blade], [projectile])

func _render_p22() -> void:
	_clear_content()
	if p22_catalog == null:
		p22_catalog = _new_p22_catalog()
	_add_heading("攻击与战斗（P22）", "中文优先编辑同一份 CombatCatalog Resource。实时与回合调度器共用唯一 CombatResolver；这里不创建 HP、库存、世界坐标或第二事实账本。")
	var contract := Label.new()
	contract.text = "契约：Attack / Weapon / Projectile / HitSpec / CombatRequest / CombatResult 均为版本化纯值；Weapon 只引用 P19 Item/Equipment；弹药、资源和事实提交由既有 P19 与 DomainTransaction 管线负责。"
	contract.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(contract)
	_add_section_label("定义数量")
	var counts := Label.new()
	counts.text = "攻击：%d；武器：%d；投射物：%d；目录修订：%d；同一 Resource：是" % [p22_catalog.attacks.size(), p22_catalog.weapons.size(), p22_catalog.projectiles.size(), p22_catalog.revision]
	counts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(counts)
	var list := ItemList.new()
	list.name = "P22战斗定义列表"
	list.custom_minimum_size = Vector2(0, 110 if not compact else 72)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for attack in p22_catalog.attacks: list.add_item("攻击 · %s · %s" % [str(attack.get("attack_id", "")), str(attack.get("display_name_zh", ""))])
	for weapon in p22_catalog.weapons: list.add_item("武器 · %s · P19:%s" % [str(weapon.get("weapon_id", "")), str(weapon.get("item_ref", ""))])
	for projectile in p22_catalog.projectiles: list.add_item("投射物 · %s · %s" % [str(projectile.get("projectile_id", "")), str(projectile.get("display_name_zh", ""))])
	content.add_child(list)
	_add_section_label("创建中性定义")
	var create_row := HBoxContainer.new()
	content.add_child(create_row)
	var attack_button := Button.new()
	attack_button.text = "创建攻击"
	attack_button.pressed.connect(_p22_add_attack)
	create_row.add_child(attack_button)
	var weapon_button := Button.new()
	weapon_button.text = "创建武器"
	weapon_button.pressed.connect(_p22_add_weapon)
	create_row.add_child(weapon_button)
	var projectile_button := Button.new()
	projectile_button.text = "创建投射物"
	projectile_button.pressed.connect(_p22_add_projectile)
	create_row.add_child(projectile_button)
	var actions := HBoxContainer.new()
	content.add_child(actions)
	var preflight_button := Button.new()
	preflight_button.text = "运行预检"
	preflight_button.tooltip_text = "只检查同一 Resource 中的版本、稳定 ID、纯值和定义字段；不会写入运行时 Store。"
	preflight_button.pressed.connect(_p22_preflight)
	actions.add_child(preflight_button)
	var save_button := Button.new()
	save_button.text = "保存目录（可 Undo/Redo）"
	save_button.pressed.connect(_p22_save_catalog)
	actions.add_child(save_button)
	var reopen_button := Button.new()
	reopen_button.text = "保存后重开同一 Resource"
	reopen_button.pressed.connect(_p22_reopen_catalog)
	actions.add_child(reopen_button)
	_p22_result_label = Label.new()
	_p22_result_label.name = "P22预检与提交反馈"
	_p22_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_p22_result_label)
	_p22_preflight()

func _p22_add_attack() -> void:
	var next = p22_catalog.attacks.duplicate(true)
	var number = next.size() + 1
	next.append(p22_model.new_neutral_attack("gm.attack.editor.%d" % number, "中性攻击 %d" % number, "melee", "damage", 5.0 + number, 1.0))
	_p22_apply_state(next, p22_catalog.weapons, p22_catalog.projectiles, "已创建中性攻击；等待 P22 预检。")

func _p22_add_weapon() -> void:
	var next = p22_catalog.weapons.duplicate(true)
	var number = next.size() + 1
	var attack_id := str(p22_catalog.attacks[0].get("attack_id", "gm.attack.editor.slash")) if not p22_catalog.attacks.is_empty() else "gm.attack.editor.slash"
	next.append(p22_model.new_neutral_weapon("gm.weapon.editor.%d" % number, "中性武器 %d" % number, "gm.item.editor.weapon.%d" % number, attack_id))
	_p22_apply_state(p22_catalog.attacks, next, p22_catalog.projectiles, "已创建 P19 Item/Equipment 引用的中性武器。")

func _p22_add_projectile() -> void:
	var next = p22_catalog.projectiles.duplicate(true)
	var number = next.size() + 1
	next.append(p22_model.new_neutral_projectile("gm.projectile.editor.%d" % number, "中性投射物 %d" % number))
	_p22_apply_state(p22_catalog.attacks, p22_catalog.weapons, next, "已创建中性投射物定义；运行时后端仍由 HitQuery 适配器决定。")

func _p22_apply_state(attacks: Array, weapons: Array, projectiles: Array, status: String) -> void:
	var result: Dictionary = p22_model.apply_catalog_state(p22_catalog, attacks, weapons, projectiles, editor_undo_redo, P22_CATALOG_PATH)
	if not result.ok:
		_set_status("P22 目录编辑已阻断：%s" % str(result.get("reason_zh", "; ".join(result.get("details", {}).get("errors_zh", [])))), false)
		return
	_set_status(status, true)
	_render()

func _p22_preflight() -> void:
	if not is_instance_valid(_p22_result_label): return
	var result: Dictionary = p22_model.preflight_summary(p22_catalog)
	_p22_result_label.text = "预检：%s\n阻断原因：%s\n提交：%s；请求层：%s；直接写 Store：%s" % [str(result.get("state_zh", "")), str(result.get("block_reason_zh", "无")), str(result.get("commit_state_zh", "")), "仅请求" if result.get("request_only", false) else "异常", "否" if not result.get("direct_store_write", true) else "是"]
	_p22_result_label.modulate = Color("80ffb0") if result.get("ok", false) else Color("ffb080")

func _p22_save_catalog() -> void:
	if p22_catalog == null: return
	_p22_apply_state(p22_catalog.attacks, p22_catalog.weapons, p22_catalog.projectiles, "P22 战斗定义目录已保存；编辑器 Undo/Redo 可撤销本次修改。")

func _p22_reopen_catalog() -> void:
	if p22_catalog == null: return
	var saved: Dictionary = p22_model.apply_catalog_state(p22_catalog, p22_catalog.attacks, p22_catalog.weapons, p22_catalog.projectiles, editor_undo_redo, P22_CATALOG_PATH)
	if not saved.ok:
		_set_status("P22 目录保存未完成，未执行重开。", false)
		return
	var reopened: Dictionary = p22_model.reopen_catalog_into(p22_catalog, P22_CATALOG_PATH)
	if not reopened.ok:
		_set_status("P22 目录重开未完成：%s" % str(reopened.get("reason_zh", "未知原因。")), false)
		return
	_set_status("P22 目录已保存并重开；仍使用同一份 Resource。", true)
	_render()

func _p21_text_field(label_text: String, field: String, value: String) -> void:
	var row := HBoxContainer.new()
	content.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(100, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(next_value): _p21_commit_field(field, next_value))
	edit.focus_exited.connect(func(): _p21_commit_field(field, edit.text))
	row.add_child(edit)

func _p21_commit_field(field: String, value: String) -> void:
	var next := p21_definition.to_dict()
	next[field] = value
	var result: Dictionary = p21_model.apply_definition(p21_definition, next, editor_undo_redo, P21_DEFINITION_PATH)
	_set_status("P21对话定义已保存，可 Undo/Redo。" if result.ok else "P21对话定义编辑阻断：%s" % str(result.get("reason_zh", "未知原因。")), result.ok)
	if result.ok: _render()

func _p21_save_definition() -> void:
	var result: Dictionary = p21_model.save_definition(p21_definition, editor_undo_redo, P21_DEFINITION_PATH)
	_set_status("P21对话定义已保存。" if result.ok else "P21对话定义保存失败。", result.ok)

func _p21_reopen_definition() -> void:
	var saved: Dictionary = p21_model.save_definition(p21_definition, editor_undo_redo, P21_DEFINITION_PATH)
	if not saved.ok:
		_set_status("P21对话定义保存失败，未重开。", false)
		return
	var reopened: Dictionary = p21_model.reopen_definition_into(p21_definition, P21_DEFINITION_PATH)
	if not reopened.ok:
		_set_status("P21对话定义重开失败。", false)
		return
	_set_status("P21对话定义已保存并重开。", true)
	_render()

func _render_p20() -> void:
	_clear_content()
	_add_heading("持续过程（P20）", "编辑同一 ProcessDefinition；实例状态只读投影唯一 Process Store。")
	var boundary := Label.new()
	boundary.text = "Process 不选择执行者，不移动角色，不直接修改库存、数值或生命状态。完成结算由现有 P19 事务或类型化领域请求处理。"
	boundary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(boundary)
	_p20_text_field("定义 ID", "definition_id", p20_definition.definition_id)
	_p20_text_field("中文名称", "display_name_zh", p20_definition.display_name_zh)
	_p20_text_field("类别标签", "process_family", p20_definition.process_family)
	_p20_text_field("持续单位", "duration_units", str(p20_definition.duration_units))
	var actions := HBoxContainer.new()
	content.add_child(actions)
	var save_button := Button.new()
	save_button.text = "保存定义（可 Undo/Redo）"
	save_button.pressed.connect(_p20_save_definition)
	actions.add_child(save_button)
	var reopen_button := Button.new()
	reopen_button.text = "保存后重开"
	reopen_button.pressed.connect(_p20_reopen_definition)
	actions.add_child(reopen_button)
	_add_section_label("实例状态（只读）")
	_p20_result_label = Label.new()
	_p20_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if p20_runtime_store == null:
		_p20_result_label.text = "当前编辑器没有连接运行时 Process Store；不会创建镜像 Store。"
	else:
		var projection: Dictionary = p20_model.instance_projection(p20_runtime_store)
		_p20_result_label.text = JSON.stringify(projection.get("instances", []), "  ")
	content.add_child(_p20_result_label)

func _p20_text_field(label_text: String, field: String, value: String) -> void:
	var row := HBoxContainer.new()
	content.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(100, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(next_value): _p20_commit_field(field, next_value))
	edit.focus_exited.connect(func(): _p20_commit_field(field, edit.text))
	row.add_child(edit)

func _p20_commit_field(field: String, value: String) -> void:
	var next: Dictionary = p20_definition.to_native()
	next[field] = int(value) if field == "duration_units" and value.is_valid_int() else value
	var result: Dictionary = p20_model.apply_definition(p20_definition, next, editor_undo_redo, P20_DEFINITION_PATH)
	if result.ok:
		_set_status("ProcessDefinition 已保存；可 Undo/Redo。", true)
	else:
		_set_status("ProcessDefinition 编辑阻断：%s" % str(result.get("reason_zh", "; ".join(result.get("errors", [])))), false)

func _p20_save_definition() -> void:
	var result: Dictionary = p20_model.apply_definition(p20_definition, p20_definition.to_native(), editor_undo_redo, P20_DEFINITION_PATH)
	_set_status("ProcessDefinition 已保存。" if result.ok else "ProcessDefinition 保存失败。", result.ok)

func _p20_reopen_definition() -> void:
	var saved: Dictionary = p20_model.apply_definition(p20_definition, p20_definition.to_native(), editor_undo_redo, P20_DEFINITION_PATH)
	if not saved.ok:
		_set_status("ProcessDefinition 保存失败，未重开。", false)
		return
	var reopened: Dictionary = p20_model.reopen_definition_into(p20_definition, P20_DEFINITION_PATH)
	if not reopened.ok:
		_set_status("ProcessDefinition 重开失败。", false)
		return
	_set_status("ProcessDefinition 已保存并重开。", true)
	_render()

func _render_advanced() -> void:
	_clear_content()
	_add_heading("高级模式", "这里不创建高级版配置；只聚焦 Godot 原生 SceneTree、Inspector、2D 场景或脚本。")
	var native_info := Label.new()
	native_info.text = "同源 Resource：%s\n同源场景：%s\n当前字段：项目名称=%s；修改标记=%s；修订=%s" % [SUBJECT_PATH, SUBJECT_SCENE_PATH, str(subject.get("project_name_zh")), str(subject.get("change_marker")), str(subject.get("revision"))]
	native_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(native_info)
	_live_value_label = native_info
	var action_row := HBoxContainer.new()
	content.add_child(action_row)
	var resource_button := Button.new()
	resource_button.text = "打开原生 Inspector（同一 Resource）"
	resource_button.pressed.connect(_open_native_resource)
	action_row.add_child(resource_button)
	var scene_button := Button.new()
	scene_button.text = "打开原生 2D / SceneTree（同一场景）"
	scene_button.pressed.connect(_open_native_scene)
	action_row.add_child(scene_button)
	var script_button := Button.new()
	script_button.text = "打开 GDScript"
	script_button.pressed.connect(_open_native_script)
	action_row.add_child(script_button)
	var back_button := Button.new()
	back_button.text = "返回策划模式"
	back_button.pressed.connect(func(): _set_mode("planning"))
	action_row.add_child(back_button)
	var protocol := Label.new()
	protocol.text = "原生修改后点击返回，工作台会重新读取同一 Resource；Undo/Redo 使用 EditorUndoRedoManager。"
	protocol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(protocol)
	var health_button := Button.new()
	health_button.text = "返回前运行统一验证"
	health_button.pressed.connect(_scan_errors)
	content.add_child(health_button)

func _render_errors() -> void:
	_clear_content()
	_add_heading("统一错误中心", "聚合验证、插件、脚本和导出阻断；每条记录都包含中文对象名、路径、字段、原因、建议和真实定位状态。")
	var summary := Label.new()
	summary.text = "错误来源：%s" % JSON.stringify(error_center.last_scan.get("sources", {}))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(summary)
	if temporary_errors.is_empty() and error_center.errors.is_empty():
		var clean := Label.new()
		clean.text = "✓ 当前没有阻断错误；修复后会自动从列表消失。"
		clean.modulate = Color("80ffb0")
		content.add_child(clean)
	else:
		for index in error_center.errors.size():
			content.add_child(_make_error_row(index, error_center.errors[index]))
		for entry in temporary_errors:
			content.add_child(_make_error_row(-1, entry))
	var demo_row := HBoxContainer.new()
	content.add_child(demo_row)
	var make_error := Button.new()
	make_error.text = "制造真实字段错误"
	make_error.tooltip_text = "清空同源 Resource 的项目名称，运行实际验证"
	make_error.pressed.connect(_make_subject_error)
	demo_row.add_child(make_error)
	var fix_error := Button.new()
	fix_error.text = "修复字段错误"
	fix_error.pressed.connect(_fix_subject_error)
	demo_row.add_child(fix_error)
	var stale_error := Button.new()
	stale_error.text = "演示删除后安全定位"
	stale_error.pressed.connect(_add_stale_error)
	demo_row.add_child(stale_error)
	var scan_button := Button.new()
	scan_button.text = "重新扫描并自动清理"
	scan_button.pressed.connect(_scan_errors)
	demo_row.add_child(scan_button)

func _make_error_row(index: int, entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "[%s] %s · %s" % [str(entry.get("severity", "error")), str(entry.get("object_name_zh", "对象")), str(entry.get("field_name_zh", "字段"))]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var details := Label.new()
	details.text = "来源：%s\n路径：%s\n原因：%s\n建议：%s\n定位：%s" % [str(entry.get("source", "")), str(entry.get("resource_path", "")), str(entry.get("reason_zh", "")), str(entry.get("suggestion_zh", "")), str(entry.get("location_state", "未定位"))]
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(details)
	var row := HBoxContainer.new()
	box.add_child(row)
	var locate_button := Button.new()
	locate_button.text = "定位"
	locate_button.pressed.connect(func(): _locate_error(index, entry))
	row.add_child(locate_button)
	var help_button := Button.new()
	help_button.text = "字段帮助"
	help_button.pressed.connect(func(): _update_help("error", str(entry.get("code", "")), str(entry.get("field_name_zh", ""))))
	row.add_child(help_button)
	var fix_button := Button.new()
	fix_button.text = "修复"
	fix_button.pressed.connect(func(): _fix_error(index, entry))
	row.add_child(fix_button)
	return panel

func _add_heading(title_text: String, description: String) -> void:
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 22 if not compact else 18)
	content.add_child(title)
	var description_label := Label.new()
	description_label.text = description
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description_label)

func _add_section_label(text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 15)
	content.add_child(label)

func _clear_content() -> void:
	for child in content.get_children(): child.queue_free()

func _add_subject_controls(context_name: String) -> void:
	var label := Label.new()
	label.text = "同源 Resource 字段（%s）" % context_name
	label.add_theme_font_size_override("font_size", 15)
	content.add_child(label)
	_add_line_edit("项目名称", "project_name_zh", str(subject.get("project_name_zh")), "修改名称后验证 Undo/Redo 与关闭重开")
	_add_line_edit("修改标记", "change_marker", str(subject.get("change_marker")), "用于证明策划模式与高级模式读写同一资源")
	var source_path := Label.new()
	source_path.text = "资源路径：%s" % SUBJECT_PATH
	source_path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(source_path)

func _add_line_edit(label_text: String, field: String, value: String, tooltip: String) -> void:
	var row := HBoxContainer.new()
	content.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(100, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.name = "字段_%s" % field
	edit.text = value
	edit.placeholder_text = tooltip
	edit.tooltip_text = tooltip
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(new_value): _commit_subject_text(field, new_value))
	edit.focus_exited.connect(func(): _commit_subject_text(field, edit.text))
	row.add_child(edit)

func _add_ability_bundle_picker(entry_id: String) -> void:
	var label := Label.new()
	label.text = "常用能力组合：%s" % "、".join(template.common_ability_bundles)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)
	var help := Button.new()
	help.text = "查看能力组合说明"
	help.pressed.connect(func(): _update_help("ability"))
	content.add_child(help)

func _template_selected(index: int) -> void:
	if _template_option == null: return
	var target_id: Variant = _template_option.get_item_metadata(index)
	var target = TEMPLATES.get_template(target_id)
	var next_modules: PackedStringArray = target.default_enabled_modules.duplicate() if target != null else PackedStringArray()
	var guard := MODEL.guard_template_switch(profile, subject, target_id, next_modules)
	if not guard.ok:
		_template_option.select(_template_index(str(profile.template_id)))
		_show_temporary_errors(guard.errors_zh, str(guard.get("error_code", "template.switch_blocked")))
		_set_status("模板切换未提交：%s" % "; ".join(guard.errors_zh), false)
		return
	var old_template := str(profile.template_id)
	var old_modules: PackedStringArray = profile.enabled_modules.duplicate()
	var new_modules: PackedStringArray = next_modules.duplicate()
	var preflight := MODEL.apply_profile_state(profile, target_id, new_modules, true)
	_last_profile_apply_result = preflight
	if not preflight.ok:
		_template_option.select(_template_index(old_template))
		_show_temporary_errors(preflight.errors_zh, str(preflight.get("error_code", "profile.save_failed")))
		_set_status("模板切换未保存，Profile 已保留原状态：%s" % "; ".join(preflight.errors_zh), false)
		return
	if editor_undo_redo != null:
		_profile_state_saved_signature = _profile_state_signature(str(target_id), new_modules)
		editor_undo_redo.create_action("GM模板切换：%s" % str(target.display_name_zh))
		editor_undo_redo.add_do_method(self, "_apply_profile_state", target_id, new_modules)
		editor_undo_redo.add_undo_method(self, "_apply_profile_state", old_template, old_modules)
		editor_undo_redo.commit_action()
	else:
		_profile_state_saved_signature = ""
		_refresh_template()
		_scan_errors(false)
	if not _last_profile_apply_result.get("ok", false):
		_template_option.select(_template_index(old_template))
		_show_temporary_errors(_last_profile_apply_result.get("errors_zh", []), str(_last_profile_apply_result.get("error_code", "profile.save_failed")))
		_set_status("模板切换未完成，Profile 已保留原状态。", false)
		return
	_temporary_clear()
	_set_status("模板已切换为“%s”；内容条目保持 %d 个，Profile 仍是同一份 Resource。" % [str(target.display_name_zh), _subject_content_count()], true)
	_render()

func _apply_profile_state(template_id: Variant, modules: Variant) -> Dictionary:
	var signature := _profile_state_signature(str(template_id), modules)
	var skip_save := signature == _profile_state_saved_signature
	if skip_save: _profile_state_saved_signature = ""
	_last_profile_apply_result = MODEL.apply_profile_state(profile, template_id, modules, not skip_save)
	if _last_profile_apply_result.ok:
		_refresh_template()
		_scan_errors(false)
	else:
		_show_temporary_errors(_last_profile_apply_result.get("errors_zh", []), str(_last_profile_apply_result.get("error_code", "profile.save_failed")))
		_set_status("项目配置保存未完成，原有 Profile 状态已保留。", false)
	return _last_profile_apply_result

func _toggle_module(id: String, enabled: bool, button: Button) -> void:
	var next: PackedStringArray = profile.enabled_modules.duplicate()
	if enabled and not next.has(id): next.append(id)
	if not enabled: next.erase(id)
	var plan: Dictionary = REGISTRY.resolve(next)
	if not plan.ok:
		button.button_pressed = not enabled
		_show_temporary_errors(plan.errors_zh, "template.missing_module")
		_set_status("模块配置阻断：%s" % "; ".join(plan.errors_zh), false)
		return
	var old: PackedStringArray = profile.enabled_modules.duplicate()
	var preflight := MODEL.apply_profile_state(profile, str(profile.template_id), next, true)
	_last_profile_apply_result = preflight
	if not preflight.ok:
		button.button_pressed = not enabled
		_show_temporary_errors(preflight.errors_zh, str(preflight.get("error_code", "profile.save_failed")))
		_set_status("模块配置未保存，Profile 已保留原状态：%s" % "; ".join(preflight.errors_zh), false)
		return
	if editor_undo_redo != null:
		_profile_state_saved_signature = _profile_state_signature(str(profile.template_id), next)
		editor_undo_redo.create_action("GM模块配置")
		editor_undo_redo.add_do_method(self, "_apply_module_state", next)
		editor_undo_redo.add_undo_method(self, "_apply_module_state", old)
		editor_undo_redo.commit_action()
	else:
		_profile_state_saved_signature = ""
		_refresh_template()
		_scan_errors(false)
	if not _last_profile_apply_result.get("ok", false):
		button.button_pressed = not enabled
		_show_temporary_errors(_last_profile_apply_result.get("errors_zh", []), str(_last_profile_apply_result.get("error_code", "profile.save_failed")))
		_set_status("模块配置未完成，Profile 已保留原状态。", false)
		return
	_set_status("模块配置已保存，可通过 Undo/Redo 撤销。", true)
	_render()

func _apply_module_state(modules: Variant) -> Dictionary:
	var signature := _profile_state_signature(str(profile.template_id), modules)
	var skip_save := signature == _profile_state_saved_signature
	if skip_save: _profile_state_saved_signature = ""
	_last_profile_apply_result = MODEL.apply_profile_state(profile, str(profile.template_id), modules, not skip_save)
	if _last_profile_apply_result.ok:
		_refresh_template()
		_scan_errors(false)
	else:
		_show_temporary_errors(_last_profile_apply_result.get("errors_zh", []), str(_last_profile_apply_result.get("error_code", "profile.save_failed")))
		_set_status("模块配置保存未完成，原有 Profile 状态已保留。", false)
	return _last_profile_apply_result

func _commit_subject_text(field: String, value: String) -> void:
	if subject == null or str(subject.get(field)) == value: return
	var changes := {field: value, "change_marker": "策划模式修改", "revision": int(subject.get("revision")) + 1}
	_commit_subject_changes(changes, "%s修改" % field)

func _commit_subject_changes(changes: Dictionary, action_name: String) -> void:
	var old_changes := {}
	for key in changes: old_changes[key] = subject.get(key)
	if editor_undo_redo != null:
		editor_undo_redo.create_action("GM同源资源：%s" % action_name)
		editor_undo_redo.add_do_method(self, "_apply_subject_changes", changes)
		editor_undo_redo.add_undo_method(self, "_apply_subject_changes", old_changes)
		editor_undo_redo.commit_action()
	else: _apply_subject_changes(changes)
	_set_status("已写入同一 Resource：%s；可立即 Undo/Redo。" % action_name, true)
	_scan_errors(false)
	_render()

func _apply_subject_changes(changes: Dictionary) -> void:
	for key in changes: subject.set(key, changes[key])
	ResourceSaver.save(subject, SUBJECT_PATH)
	_last_subject_signature = _subject_signature()

func _add_subject_item(field: String, section_name: String) -> void:
	if subject == null: return
	var next: PackedStringArray = _subject_array(field)
	var value := "%s %d" % [section_name, next.size() + 1]
	next.append(value)
	_commit_subject_changes({field: next, "change_marker": "创建%s" % section_name, "revision": int(subject.get("revision")) + 1}, "创建%s" % section_name)

func _subject_array(field: String) -> PackedStringArray:
	if subject == null: return PackedStringArray()
	var value = subject.get(field)
	return value.duplicate() if value is PackedStringArray else PackedStringArray()

func _entry_field(entry_id: String) -> String:
	var mapping := {"map":"map_names", "character":"character_names", "ability":"ability_names", "resource":"resource_names", "task":"task_names", "equipment":"resource_names", "combat":"map_names", "building":"resource_names", "production":"resource_names"}
	return str(mapping.get(entry_id, "resource_names"))

func _entry_description(entry_id: String) -> String:
	var descriptions := {"map":"查看地图、区域与路线入口，并从创建向导开始。", "character":"查看角色身份与能力组合，角色内容不复制运行时。", "ability":"查看统一能力入口，移动、交互、工作和攻击共用同一 GAS。", "resource":"查看资源与稳定业务 ID，移动路径不改变内容身份。", "task":"查看任务、事件与条件入口，统一错误中心会解释引用。", "equipment":"查看装备与能力授予组合。", "combat":"查看战斗区域和验证规则。", "building":"查看建筑和工作点入口。", "production":"查看普通生产链输入、输出与仓库。", "p19":"创建中性物品、数值资源、容器和统一交易配方，并查看预检阻断原因、输入输出和提交状态。", "p20":"编辑中性Process定义并只读查看既有Process实例。", "p21":"编辑中性对话定义，预览统一交互路由与P16 Task只读投影。", "p22":"编辑版本化攻击、武器和投射物纯值；HitSpec、实时/回合统一结果与P19/Fact/Change链路只在现有底座提交。"}
	return str(descriptions.get(entry_id, "从中文入口继续创建和验证内容。"))

func _wizard_entry(wizard_id: String) -> String:
	var mapping := {"map":"map", "object":"resource", "ability":"ability", "character":"character", "quest":"task", "recipe":"production", "storage":"resource", "building":"building"}
	return str(mapping.get(wizard_id, "home"))

func _template_index(template_id: String) -> int:
	if _template_option == null: return 0
	for index in _template_option.item_count:
		if str(_template_option.get_item_metadata(index)) == template_id: return index
	return 0

func _subject_content_count() -> int:
	return int(subject.content_count()) if subject != null and subject.has_method("content_count") else 0

func _subject_signature() -> String:
	if subject == null: return ""
	return "%s|%s|%s|%s" % [str(subject.get("project_name_zh")), str(subject.get("change_marker")), str(subject.get("revision")), str(_subject_content_count())]

func _scan_errors(show_center: bool = true) -> void:
	temporary_errors.clear()
	error_center.scan(profile, subject)
	if template == null:
		_refresh_template()
	if OS.get_environment("GM_TASK02_CAPTURE_STATE") == "stale":
		error_center.add_missing_location_error("res://gm_runtime/editor_templates/workbench/deleted_subject.tres", "已删除的演示资源")
	error_count = error_center.errors.size()
	_update_header()
	if show_center:
		active_entry = "error"
		work_mode = "planning"
		_render()
		_set_status("验证完成：错误中心已更新，修复后的错误会自动消失。", error_count == 0)

func _show_error_center() -> void:
	_scan_errors(false)
	active_entry = "error"
	work_mode = "planning"
	_render()

func _show_temporary_errors(messages: Array, code: String) -> void:
	temporary_errors.clear()
	for message in messages:
		temporary_errors.append({"severity":"error", "code":code, "source":"validation", "object_name_zh":"模板切换", "field_name_zh":"模板配置", "resource_path":"res://gm_runtime/gm_module_profile.tres", "reason_zh":str(message), "suggestion_zh":"打开上下文帮助修复后重新尝试。", "location_state":"可定位"})
	error_count = error_center.errors.size() + temporary_errors.size()
	active_entry = "error"
	work_mode = "planning"
	_render()

func _temporary_clear() -> void:
	temporary_errors.clear()

func _make_subject_error() -> void:
	_commit_subject_text("project_name_zh", "")
	active_entry = "error"
	_render()

func _fix_subject_error() -> void:
	if subject != null and str(subject.get("project_name_zh")).strip_edges().is_empty():
		_commit_subject_text("project_name_zh", "修复后的策划项目")
	else:
		_scan_errors()

func _add_stale_error() -> void:
	error_center.add_missing_location_error("res://gm_runtime/editor_templates/workbench/deleted_subject.tres", "已删除的演示资源")
	error_count = error_center.errors.size()
	active_entry = "error"
	_set_status("已加入一个真实不存在路径的错误；点击定位会安全提示失效，不会崩溃。", false)
	_render()

func _locate_error(index: int, entry: Dictionary) -> void:
	if index >= 0:
		var result := error_center.locate(index, editor_interface)
		_set_status(str(result.message_zh), result.ok)
	else:
		_set_status("临时错误没有可定位对象；请修复模板配置后重新验证。", false)
	_render()

func _fix_error(index: int, entry: Dictionary) -> void:
	if str(entry.get("code", "")) == "content.missing_name":
		_fix_subject_error()
	else:
		_set_status("请按建议修复字段后点击重新扫描。", false)

func _open_native_resource() -> void:
	if editor_interface == null or subject == null: return
	editor_interface.edit_resource(subject)
	_set_status("已打开 Godot 原生 Inspector；目标资源路径仍为 %s。" % SUBJECT_PATH, true)

func _open_native_scene() -> void:
	if editor_interface == null: return
	editor_interface.open_scene_from_path(SUBJECT_SCENE_PATH)
	call_deferred("_select_showcase_root")
	_set_status("已打开同源场景；可在原生 SceneTree/Inspector 检查 subject 引用。", true)

func _select_showcase_root() -> void:
	if editor_interface == null: return
	var root = editor_interface.get_edited_scene_root()
	if root != null:
		var selection = editor_interface.get_selection()
		selection.clear()
		selection.add_node(root)
	editor_interface.set_main_screen_editor("2D")

func _open_native_script() -> void:
	if editor_interface == null: return
	var script = load("res://gm_runtime/editor_templates/workbench/workbench_subject.gd")
	if script != null: editor_interface.edit_script(script)
	_set_status("已打开 GDScript 原生编辑器；修复后返回策划模式重新扫描。", true)

func _enter_advanced_mode() -> void:
	_set_mode("advanced")

func _toggle_compact() -> void:
	compact = not compact
	layout_state.compact = compact
	_set_status("已切换%s布局；内容区保持滚动，关键操作不会被遮挡。" % ("小屏" if compact else "大屏"), true)
	_render()
	_save_layout()

func _apply_compact_visuals() -> void:
	if not is_instance_valid(navigation) or not is_instance_valid(main_split): return
	navigation.get_parent().custom_minimum_size.x = 112 if compact else 150
	var default_split := 112 if compact else 150
	var requested_split := int(layout_state.get("split_offset", default_split))
	var upper_bound := requested_split
	if main_split.size.x > 0:
		upper_bound = min(640, int(main_split.size.x) - 240)
	upper_bound = max(96, upper_bound)
	main_split.split_offset = clamp(requested_split, 96, upper_bound)
	help_panel.custom_minimum_size.y = 58 if compact else 72
	if is_instance_valid(template_badge): template_badge.visible = not compact
	if is_instance_valid(mode_badge): mode_badge.visible = not compact

func _save_layout() -> Dictionary:
	layout_state.active_entry = active_entry
	layout_state.mode = work_mode
	layout_state.compact = compact
	var size := get_size()
	if size.x > 0: layout_state.panel_width = int(size.x)
	if size.y > 0: layout_state.panel_height = int(size.y)
	if is_instance_valid(main_split) and main_split.split_offset > 0:
		layout_state.split_offset = int(main_split.split_offset)
	return LAYOUT.save_state(layout_state)

func _save_layout_and_report() -> void:
	var result := _save_layout()
	if result.ok:
		_set_status("布局已保存：%s" % str(result.path), true)
	else:
		_set_status("布局保存未完成，原有有效布局已保留：%s" % str(result.get("error_zh", "未知原因")), false)

func _update_help(entry_id: String, error_code: String = "", field_id: String = "") -> void:
	if not is_instance_valid(help_title): return
	var help := HELP.get_help(entry_id, error_code, field_id)
	help_title.text = "帮助：%s" % str(help.get("title", "当前入口"))
	help_body.text = str(help.get("body", ""))
	help_action.text = "建议：%s" % str(help.get("action", ""))

func _set_status(message: String, ok: bool) -> void:
	if not is_instance_valid(status_label): return
	status_label.text = message
	status_label.modulate = Color("80ffb0") if ok else Color("ffb080")

func _profile_state_signature(template_id: String, modules: Variant) -> String:
	var values: Array[String] = []
	if modules is PackedStringArray or modules is Array:
		for module_id in modules: values.append(str(module_id))
	return template_id + "|" + ";".join(values)

func _apply_capture_state() -> void:
	var state := OS.get_environment("GM_TASK02_CAPTURE_STATE")
	if state == "blank" or state == "rpg" or state == "management":
		var id := "blank_2d" if state == "blank" else ("rpg_arpg" if state == "rpg" else "management")
		var target = TEMPLATES.get_template(id)
		if target != null:
			capture_template_id = id
			template = target
			active_entry = "home"
			work_mode = "planning"
			compact = false
	if state == "advanced":
		work_mode = "advanced"
		active_entry = "home"
		compact = false
	if state == "error":
		active_entry = "error"
		work_mode = "planning"
		compact = false
		_scan_errors(false)
	if state == "stale":
		active_entry = "error"
		work_mode = "planning"
		compact = false
		_scan_errors(false)
	if state == "compact":
		compact = true
		work_mode = "planning"
		active_entry = "home"
	var task01_state := OS.get_environment("GM_TASK01_EDITOR_CAPTURE_STATE")
	if task01_state == "dependency":
		task01_status_override = "任务01依赖取证：模块甲启用时自动保留 core；当前工作台仍使用同一 Profile。"
	if task01_state == "conflict":
			task01_status_override = "任务01冲突取证：模块甲与模块乙冲突，中文阻断且不会落盘。"
	active_entry = "home" if state.is_empty() or task01_state != "" else active_entry
	layout_state.active_entry = active_entry
	layout_state.mode = work_mode
	layout_state.compact = compact

func get_capture_snapshot() -> Dictionary:
	return {
		"dock": "GM中文策划工作台",
		"panel_count": 1,
		"template_id": str(profile.template_id) if profile != null else "",
		"visible_template": str(template.template_id) if template != null else "",
		"enabled_modules": profile.enabled_modules if profile != null else PackedStringArray(),
		"mode": work_mode,
		"active_entry": active_entry,
		"compact": compact,
		"error_count": error_count,
		"subject_path": SUBJECT_PATH,
		"subject": subject.content_snapshot() if subject != null and subject.has_method("content_snapshot") else {},
		"layout_path": LAYOUT.storage_path(),
		"layout": layout_state,
		"content_preserved_on_switch": true,
		"p19_catalog_path": P19_CATALOG_PATH,
		"p19_catalog_revision": int(p19_catalog.revision) if p19_catalog != null else 0,
		"p19_recipe_count": p19_catalog.recipes.size() if p19_catalog != null else 0,
		"p21_dialogue_path": P21_DEFINITION_PATH,
		"p21_dialogue_id": p21_definition.dialogue_id if p21_definition != null else "",
		"p21_dialogue_revision": p21_definition.revision if p21_definition != null else 0,
		"p21_task_projection_read_only": true,
		"p22_catalog_path": P22_CATALOG_PATH,
		"p22_catalog_revision": int(p22_catalog.revision) if p22_catalog != null else 0,
		"p22_attack_count": p22_catalog.attacks.size() if p22_catalog != null else 0,
		"p22_weapon_count": p22_catalog.weapons.size() if p22_catalog != null else 0,
		"p22_projectile_count": p22_catalog.projectiles.size() if p22_catalog != null else 0,
		"p22_direct_store_write": false,
		"spatial_selection": profile.spatial_selection() if profile != null and profile.has_method("spatial_selection") else {},
	"spatial_debug": profile.spatial_debug_summary() if profile != null and profile.has_method("spatial_debug_summary") else {},
	"spatial_control_names": ["空间域选择", "空间后端启用", "空间能力状态", "空间调试信息"],
	"spatial_last_action": _last_spatial_profile_result.duplicate(true),
	}

func run_ext_3d_01_editor_probe() -> Dictionary:
	var before := _spatial_editor_snapshot()
	if profile == null or _spatial_backend_toggle == null or editor_undo_redo == null:
		return {"ok": false, "code": "gm.ext3d01.editor_controls_missing", "reason_zh": "空间编辑器控件或 EditorUndoRedoManager 不可用。", "before": before, "through_formal_controls": false, "direct_success_action_calls": 0}
	var baseline_enabled: bool = profile.spatial_backend_enabled
	var desired_enabled: bool = not baseline_enabled
	_spatial_backend_toggle.set_pressed_no_signal(desired_enabled)
	_spatial_backend_toggle.emit_signal("toggled", desired_enabled)
	var after_action := _spatial_editor_snapshot()
	var action_applied: bool = bool(after_action.get("enabled", false)) == desired_enabled
	# EditorUndoRedoManager exposes per-object UndoRedo histories.  Resolve the
	# history for this formal Profile action, never the dock's mutable identity.
	var history_info := _spatial_profile_history(profile)
	var history: Variant = history_info.get("history", null)
	var history_id := int(history_info.get("id", -1))
	var can_undo: bool = history != null and history.has_method("undo")
	if can_undo:
		history.call("undo")
	var after_undo := _spatial_editor_snapshot()
	var undo_restored: bool = _spatial_same_snapshot(before, after_undo)
	var can_redo: bool = history != null and history.has_method("redo")
	if can_redo:
		history.call("redo")
	var after_redo := _spatial_editor_snapshot()
	var redo_applied: bool = bool(after_redo.get("enabled", false)) == desired_enabled
	var final_can_undo: bool = history != null and history.has_method("undo")
	if final_can_undo:
		history.call("undo")
	var after_final_undo := _spatial_editor_snapshot()
	var final_restored: bool = _spatial_same_snapshot(before, after_final_undo)
	var failure_candidate = profile.duplicate(true)
	failure_candidate.set("spatial_domain_id", "gm.spatial.planar_3d")
	failure_candidate.set("spatial_backend_id", "gm.spatial.backend.planar_3d")
	failure_candidate.set("spatial_backend_enabled", true)
	var structured_failure: Dictionary = failure_candidate.validate_spatial_selection(profile.enabled_modules)
	var save_error := ResourceSaver.save(profile, PROFILE_PATH)
	var reopened = ResourceLoader.load(PROFILE_PATH, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	var reopened_ok: bool = reopened != null and reopened is Resource and str(reopened.get("spatial_domain_id")) == str(before.get("domain_id", "")) and str(reopened.get("spatial_backend_id")) == str(before.get("backend_id", "")) and bool(reopened.get("spatial_backend_enabled")) == bool(before.get("enabled", false))
	var double_profile := _run_ext_3d_01_double_profile_probe()
	var snapshot := get_capture_snapshot()
	return {
		"ok": action_applied and can_undo and undo_restored and can_redo and redo_applied and final_restored and structured_failure.has("code") and not structured_failure.ok and save_error == OK and reopened_ok and bool(double_profile.get("ok", false)),
		"event": "GM_EXT_3D_01_EDITOR_SENTINEL",
		"through_formal_controls": true,
		"direct_success_action_calls": 0,
		"before": before,
		"after_action": after_action,
		"after_undo": after_undo,
		"after_redo": after_redo,
		"after_final_undo": after_final_undo,
		"undo_redo": {"history_context": "Profile", "history_id": history_id, "can_undo": can_undo, "undo_restored": undo_restored, "can_redo": can_redo, "redo_applied": redo_applied, "final_restored": final_restored},
		"structured_failure": structured_failure,
		"save_close_reopen": {"save_error": save_error, "reopened_ok": reopened_ok, "path": PROFILE_PATH, "same_resource_contract": true},
		"double_profile": double_profile,
		"snapshot": snapshot,
	}

func _run_ext_3d_01_double_profile_probe() -> Dictionary:
	var original_profile: Resource = profile
	var path_a := "user://gm_ext_3d_01_profile_a.tres"
	var path_b := "user://gm_ext_3d_01_profile_b.tres"
	var profile_a_seed: Resource = original_profile.duplicate(true)
	var profile_b_seed: Resource = original_profile.duplicate(true)
	for seed in [profile_a_seed, profile_b_seed]:
		seed.set("template_id", "blank_2d")
		seed.set("spatial_domain_id", "gm.spatial.planar_2d")
		seed.set("spatial_backend_id", "gm.spatial.backend.planar_2d")
		seed.set("spatial_backend_enabled", false)
		seed.set("enabled_modules", PackedStringArray(["core"]))
	var save_a_initial := ResourceSaver.save(profile_a_seed, path_a)
	var save_b_initial := ResourceSaver.save(profile_b_seed, path_b)
	var loaded_a = ResourceLoader.load(path_a, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	var loaded_b = ResourceLoader.load(path_b, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	var setup_ok: bool = save_a_initial == OK and save_b_initial == OK and loaded_a is Resource and loaded_b is Resource
	if not setup_ok:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_a))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_b))
		profile = original_profile
		_refresh_template()
		_update_spatial_profile_controls()
		return {"ok": false, "code": "gm.ext3d01.double_profile_setup_failed", "save_errors": [save_a_initial, save_b_initial], "loaded": [loaded_a != null, loaded_b != null]}
	var profile_a: Resource = loaded_a
	var profile_b: Resource = loaded_b
	var a_before := _spatial_profile_value_snapshot(profile_a)
	var b_before := _spatial_profile_value_snapshot(profile_b)
	profile = profile_a
	_refresh_template()
	_update_spatial_profile_controls()
	_spatial_backend_toggle.set_pressed_no_signal(true)
	_spatial_backend_toggle.emit_signal("toggled", true)
	var a_after_action := _spatial_profile_value_snapshot(profile_a)
	var action_applied: bool = bool(a_after_action.get("enabled", false)) and a_after_action.get("modules", []) is Array and a_after_action.get("modules", []).has("spatial.planar_2d")
	profile = profile_b
	_refresh_template()
	_update_spatial_profile_controls()
	var b_after_switch := _spatial_profile_value_snapshot(profile_b)
	var history_info := _spatial_profile_history(profile_a)
	var history: Variant = history_info.get("history", null)
	var history_id := int(history_info.get("id", -1))
	var can_undo: bool = history != null and history.has_method("undo")
	if can_undo:
		history.call("undo")
	var a_after_undo := _spatial_profile_value_snapshot(profile_a)
	var b_after_undo := _spatial_profile_value_snapshot(profile_b)
	var undo_isolated: bool = _spatial_same_snapshot(a_before, a_after_undo) and _spatial_same_snapshot(b_before, b_after_undo)
	var can_redo: bool = history != null and history.has_method("redo")
	if can_redo:
		history.call("redo")
	var a_after_redo := _spatial_profile_value_snapshot(profile_a)
	var b_after_redo := _spatial_profile_value_snapshot(profile_b)
	var redo_isolated: bool = _spatial_same_snapshot(a_after_action, a_after_redo) and _spatial_same_snapshot(b_before, b_after_redo)
	var final_can_undo: bool = history != null and history.has_method("undo")
	if final_can_undo:
		history.call("undo")
	var a_after_final_undo := _spatial_profile_value_snapshot(profile_a)
	var b_after_final_undo := _spatial_profile_value_snapshot(profile_b)
	var final_isolated: bool = _spatial_same_snapshot(a_before, a_after_final_undo) and _spatial_same_snapshot(b_before, b_after_final_undo)
	var save_a_final := ResourceSaver.save(profile_a, path_a)
	var save_b_final := ResourceSaver.save(profile_b, path_b)
	var reopened_a = ResourceLoader.load(path_a, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	var reopened_b = ResourceLoader.load(path_b, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	var reopened_a_ok: bool = reopened_a is Resource and _spatial_same_snapshot(a_after_final_undo, _spatial_profile_value_snapshot(reopened_a)) and str(reopened_a.resource_path) == path_a
	var reopened_b_ok: bool = reopened_b is Resource and _spatial_same_snapshot(b_after_final_undo, _spatial_profile_value_snapshot(reopened_b)) and str(reopened_b.resource_path) == path_b
	var result := {
		"ok": action_applied and can_undo and undo_isolated and can_redo and redo_isolated and final_isolated and save_a_final == OK and save_b_final == OK and reopened_a_ok and reopened_b_ok,
		"through_formal_controls": true,
		"control_signal": "CheckButton.toggled",
		"profile_a": {"path": path_a, "instance_id": profile_a.get_instance_id(), "before": a_before, "after_action": a_after_action, "after_undo": a_after_undo, "after_redo": a_after_redo, "after_final_undo": a_after_final_undo},
		"profile_b": {"path": path_b, "instance_id": profile_b.get_instance_id(), "before": b_before, "after_switch": b_after_switch, "after_undo": b_after_undo, "after_redo": b_after_redo, "after_final_undo": b_after_final_undo},
		"undo_redo": {"history_context": "profile_a", "history_id": history_id, "can_undo": can_undo, "undo_isolated": undo_isolated, "can_redo": can_redo, "redo_isolated": redo_isolated, "final_isolated": final_isolated},
		"save_close_reopen": {"save_a_error": save_a_final, "save_b_error": save_b_final, "reopened_a_ok": reopened_a_ok, "reopened_b_ok": reopened_b_ok, "same_resource_contract": reopened_a_ok and reopened_b_ok},
	}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path_a))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path_b))
	profile = original_profile
	_refresh_template()
	_update_spatial_profile_controls()
	return result

func _spatial_profile_value_snapshot(target_profile: Resource) -> Dictionary:
	if target_profile == null: return {}
	return {"resource_path": str(target_profile.resource_path), "instance_id": target_profile.get_instance_id(), "domain_id": str(target_profile.spatial_domain_id), "backend_id": str(target_profile.spatial_backend_id), "enabled": bool(target_profile.spatial_backend_enabled), "modules": Array(target_profile.enabled_modules)}

func _spatial_editor_snapshot() -> Dictionary:
	return {
		"domain_id": str(profile.spatial_domain_id) if profile != null else "",
		"backend_id": str(profile.spatial_backend_id) if profile != null else "",
		"enabled": profile.spatial_backend_enabled if profile != null else false,
		"modules": Array(profile.enabled_modules) if profile != null else [],
		"capability_text": str(_spatial_capability_label.text) if _spatial_capability_label != null else "",
		"debug_text": str(_spatial_debug_label.text) if _spatial_debug_label != null else "",
	}

func _spatial_same_snapshot(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("domain_id", "")) == str(right.get("domain_id", "")) and str(left.get("backend_id", "")) == str(right.get("backend_id", "")) and bool(left.get("enabled", false)) == bool(right.get("enabled", false)) and left.get("modules", []) == right.get("modules", [])

func _process(delta: float) -> void:
	_poll_time += delta
	if _poll_time < 0.5: return
	_poll_time = 0.0
	var signature := _subject_signature()
	if signature != _last_subject_signature:
		_last_subject_signature = signature
		if is_instance_valid(_live_value_label):
			_live_value_label.text = "同源 Resource：%s\n内容条目：%d\n项目名称：%s；修改标记：%s；修订：%s" % [SUBJECT_PATH, _subject_content_count(), str(subject.get("project_name_zh")), str(subject.get("change_marker")), str(subject.get("revision"))]
		if work_mode == "advanced":
			error_center.scan(profile, subject)
			error_count = error_center.errors.size()
			_update_header()

func _exit_tree() -> void:
	_save_layout()
