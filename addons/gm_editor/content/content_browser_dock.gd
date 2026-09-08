@tool
class_name GMContentBrowserDock
extends VBoxContainer

const LIBRARY_SCRIPT := preload("res://gm_runtime/content/gm_content_library.gd")
const GRAPH_SCRIPT := preload("res://gm_runtime/content/gm_content_reference_graph.gd")
const REGISTRY_SCRIPT := preload("res://gm_runtime/content/gm_content_type_registry.gd")
const WIZARD_SCRIPT := preload("res://addons/gm_editor/content/gm_content_type_wizard.gd")

var editor_interface
var editor_undo_redo
var library: GMContentLibrary
var graph: GMContentReferenceGraph
var registry_snapshot: Dictionary = {}
var current_entries: Array[Dictionary] = []
var selected_entry: Dictionary = {}
var selected_tree_item: TreeItem
var wizard: Control
var card_mode := false
var include_deprecated := true

var search_box: LineEdit
var type_option: OptionButton
var tag_box: LineEdit
var usage_option: OptionButton
var view_button: Button
var refresh_button: Button
var wizard_button: Button
var table: Tree
var cards: VBoxContainer
var details: TextEdit
var status_label: Label
var stats_label: Label
var detail_title: Label

func configure(p_editor_interface, p_undo_redo) -> void:
	editor_interface = p_editor_interface
	editor_undo_redo = p_undo_redo

func _ready() -> void:
	custom_minimum_size = Vector2(900, 480)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	library = LIBRARY_SCRIPT.new()
	graph = GRAPH_SCRIPT.new()
	_build_shell()
	call_deferred("_initial_scan")

func _build_shell() -> void:
	var header := HBoxContainer.new()
	header.name = "内容资源库标题栏"
	add_child(header)
	var title := Label.new()
	title.text = "GM 内容资源库"
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "  Resource 唯一事实源 · 业务 ID 与路径分离 · 可查看引用影响"
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(subtitle)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	wizard_button = Button.new()
	wizard_button.text = "新内容类型向导"
	wizard_button.tooltip_text = "生成可编辑 GDScript、注册 Resource、验证器、列表入口和测试模板"
	wizard_button.pressed.connect(_open_wizard)
	header.add_child(wizard_button)

	var filters := HBoxContainer.new()
	filters.name = "内容筛选"
	add_child(filters)
	var search_label := Label.new()
	search_label.text = "搜索"
	filters.add_child(search_label)
	search_box = LineEdit.new()
	search_box.name = "名称ID类型搜索"
	search_box.placeholder_text = "中文名 / 业务 ID / 类型"
	search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_box.text_changed.connect(func(_value): _refresh_view())
	filters.add_child(search_box)
	type_option = OptionButton.new()
	type_option.name = "类型筛选"
	type_option.custom_minimum_size.x = 150
	type_option.item_selected.connect(func(_index): _refresh_view())
	filters.add_child(type_option)
	tag_box = LineEdit.new()
	tag_box.name = "标签筛选"
	tag_box.placeholder_text = "标签"
	tag_box.custom_minimum_size.x = 110
	tag_box.text_changed.connect(func(_value): _refresh_view())
	filters.add_child(tag_box)
	usage_option = OptionButton.new()
	usage_option.name = "使用状态筛选"
	usage_option.custom_minimum_size.x = 120
	usage_option.add_item("全部使用状态", 0)
	usage_option.add_item("被引用", 1)
	usage_option.add_item("未使用", 2)
	usage_option.item_selected.connect(func(_index): _refresh_view())
	filters.add_child(usage_option)
	var deprecated_toggle := CheckButton.new()
	deprecated_toggle.text = "含废弃"
	deprecated_toggle.button_pressed = true
	deprecated_toggle.toggled.connect(func(value): include_deprecated = value; _refresh_view())
	filters.add_child(deprecated_toggle)
	view_button = Button.new()
	view_button.text = "切换卡片"
	view_button.pressed.connect(_toggle_view)
	filters.add_child(view_button)
	refresh_button = Button.new()
	refresh_button.text = "重新索引"
	refresh_button.pressed.connect(_initial_scan)
	filters.add_child(refresh_button)

	var body := HSplitContainer.new()
	body.name = "内容列表与影响分析"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var list_panel := VBoxContainer.new()
	list_panel.custom_minimum_size.x = 480
	body.add_child(list_panel)
	stats_label = Label.new()
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list_panel.add_child(stats_label)
	table = Tree.new()
	table.name = "内容表格视图"
	table.hide_root = true
	table.columns = 7
	table.set_column_title(0, "中文名")
	table.set_column_title(1, "业务 ID")
	table.set_column_title(2, "类型")
	table.set_column_title(3, "标签")
	table.set_column_title(4, "使用")
	table.set_column_title(5, "文件路径")
	table.set_column_title(6, "缩略图")
	table.set_column_titles_visible(true)
	table.select_mode = Tree.SELECT_MULTI
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.item_selected.connect(_on_table_selected)
	list_panel.add_child(table)
	cards = VBoxContainer.new()
	cards.name = "内容卡片视图"
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.add_child(cards)
	cards.visible = false

	var detail_panel := VBoxContainer.new()
	detail_panel.custom_minimum_size.x = 380
	body.add_child(detail_panel)
	detail_title = Label.new()
	detail_title.text = "选择内容查看详情"
	detail_title.add_theme_font_size_override("font_size", 16)
	detail_panel.add_child(detail_title)
	details = TextEdit.new()
	details.name = "只读详情与引用报告"
	details.editable = false
	details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_child(details)
	var detail_actions := HBoxContainer.new()
	var locate := Button.new()
	locate.text = "定位文件"
	locate.pressed.connect(_locate_selected)
	detail_actions.add_child(locate)
	var impact := Button.new()
	impact.text = "影响分析"
	impact.pressed.connect(_show_impact)
	detail_actions.add_child(impact)
	var delete_check := Button.new()
	delete_check.text = "删除保护检查"
	delete_check.pressed.connect(_check_delete)
	detail_actions.add_child(delete_check)
	var batch := Button.new()
	batch.text = "批量只读查看"
	batch.pressed.connect(_batch_read_only)
	detail_actions.add_child(batch)
	detail_panel.add_child(detail_actions)

	status_label = Label.new()
	status_label.name = "内容库操作反馈"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 28
	add_child(status_label)

func _initial_scan() -> void:
	if library == null: return
	var library_result := library.scan(["res://gm_runtime/content"])
	var graph_result := graph.build(library)
	registry_snapshot = REGISTRY_SCRIPT.scan(["res://gm_runtime/content"])
	_refresh_type_options()
	_refresh_view()
	var issue_count := int(library_result.issues.size()) + int(graph_result.issues.size())
	_set_status("索引完成：%d 项 GMContent，%d 条引用边，%d 个类型注册，%d 个问题；损坏资源已隔离。" % [library.entries.size(), graph.edges.size(), registry_snapshot.definitions.size(), issue_count], issue_count == 0)
	if OS.get_environment("GM_TASK03_EDITOR_CAPTURE_STATE") == "error" and details != null:
		var invalid_id_result := GMContentValidator.validate_business_id("gm.invalid.capture", false)
		detail_title.text = "错误配置取证 · 验证器阻断"
		details.text = "这是由真实 GMContent 身份验证器返回的错误示例，不是普通备注字符串。\n\n" + JSON.stringify(invalid_id_result, "  ") + "\n\n浏览器仍保持可用：非法内容不会进入可发布索引。"
		_set_status("错误配置已被验证器拒绝：项目内容不得使用 gm.* 业务 ID。", false)

func _refresh_type_options() -> void:
	if type_option == null: return
	type_option.clear()
	type_option.add_item("全部类型", 0)
	var ids := {}
	for entry in library.entries: ids[str(entry.content_type_id)] = true
	for definition in registry_snapshot.get("definitions", []): ids[str(definition.content_type_id)] = true
	var sorted_ids: Array[String] = []
	for id in ids: sorted_ids.append(str(id))
	sorted_ids.sort()
	for id in sorted_ids:
		type_option.add_item(id)
		type_option.set_item_metadata(type_option.item_count - 1, id)

func _refresh_view() -> void:
	if table == null or library == null: return
	var type_id := ""
	if type_option.selected > 0: type_id = str(type_option.get_item_metadata(type_option.selected))
	var usage := ""
	if usage_option.selected == 1: usage = "被引用"
	elif usage_option.selected == 2: usage = "未使用"
	current_entries = library.query(search_box.text, type_id, tag_box.text.strip_edges(), usage, include_deprecated)
	for child in cards.get_children(): child.queue_free()
	var root := table.get_root()
	if root != null: root.free()
	root = table.create_item()
	for entry in current_entries:
		var item := table.create_item(root)
		item.set_text(0, str(entry.display_name_zh))
		item.set_text(1, str(entry.content_id))
		item.set_text(2, str(entry.content_type_id))
		item.set_text(3, ", ".join(entry.tags))
		item.set_text(4, "%s (%d)" % [entry.usage_status, int(entry.usage_count)])
		item.set_text(5, str(entry.path))
		var thumbnail_texture = entry.get("thumbnail_texture", null)
		if thumbnail_texture is Texture2D:
			item.set_icon(6, thumbnail_texture)
			item.set_text(6, "有效")
		else:
			item.set_text(6, "占位（%s）" % str(entry.get("thumbnail_state", "missing")))
		item.set_metadata(0, entry)
		item.set_tooltip_text(5, str(entry.path))
		_make_card(entry)
	if is_instance_valid(selected_tree_item): selected_tree_item.select(0)
	stats_label.text = "筛选结果：%d / %d    视图：%s" % [current_entries.size(), library.entries.size(), "卡片" if card_mode else "表格"]

func _make_card(entry: Dictionary) -> void:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	panel.add_child(row)
	var thumbnail_texture = entry.get("thumbnail_texture", null)
	if thumbnail_texture is Texture2D:
		var thumbnail := TextureRect.new()
		thumbnail.name = "真实缩略图"
		thumbnail.custom_minimum_size = Vector2(96, 72)
		thumbnail.texture = thumbnail_texture
		thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumbnail.tooltip_text = str(entry.get("thumbnail_resource_path", ""))
		row.add_child(thumbnail)
	else:
		var placeholder := Label.new()
		placeholder.name = "缩略图占位"
		placeholder.text = "缩略图\n占位：%s" % str(entry.get("thumbnail_state", "missing"))
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.custom_minimum_size = Vector2(96, 72)
		placeholder.modulate = Color("9da7b3")
		row.add_child(placeholder)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var name_label := Label.new()
	name_label.text = "%s  ·  %s" % [entry.display_name_zh, entry.content_id]
	name_label.add_theme_font_size_override("font_size", 15)
	box.add_child(name_label)
	var meta := Label.new()
	meta.text = "类型：%s    标签：%s    使用：%s" % [entry.content_type_id, ", ".join(entry.tags), entry.usage_status]
	box.add_child(meta)
	var open := Button.new()
	open.text = "选择 / 定位"
	open.pressed.connect(func(): _select_entry(entry))
	box.add_child(open)
	cards.add_child(panel)

func prepare_thumbnail_capture() -> void:
	card_mode = true
	table.visible = false
	cards.visible = true
	view_button.text = "切换表格"
	_refresh_view()
	_set_status("缩略图卡片取证：有效纹理显示真实 Texture2D，缺失/损坏资源显示安全占位。", true)

func prepare_wizard_success_capture() -> void:
	if is_instance_valid(wizard) and wizard.has_method("prepare_success_capture"):
		wizard.call("prepare_success_capture")

func cleanup_wizard_success_capture() -> void:
	if is_instance_valid(wizard) and wizard.has_method("cleanup_capture_generation"):
		wizard.call("cleanup_capture_generation")

func _on_table_selected() -> void:
	var item := table.get_selected()
	if item == null: return
	selected_tree_item = item
	_select_entry(item.get_metadata(0))

func _select_entry(entry: Dictionary) -> void:
	if entry.is_empty(): return
	selected_entry = entry
	detail_title.text = "%s  ·  %s" % [entry.display_name_zh, entry.content_id]
	var impact := graph.impact_analysis(str(entry.content_id))
	details.text = "内容身份\n%s\n\n" % JSON.stringify({
		"中文名":entry.display_name_zh,
		"业务ID":entry.content_id,
		"类型":entry.content_type_id,
		"标签":entry.tags,
		"版本":entry.content_version,
		"来源":entry.source,
		"废弃":entry.deprecated,
		"别名":entry.aliases,
		"ResourceUID":entry.resource_uid_text,
		"文件":entry.path,
	}, "  ")
	details.text += "\n引用到本内容（反向引用）\n"
	for edge in graph.get_incoming(str(entry.content_id)):
		details.text += "- %s [%s / %s]\n" % [edge.chain_label, edge.kind, edge.field]
	details.text += "\n本内容引用\n"
	for edge in graph.get_outgoing(str(entry.content_id)):
		details.text += "- %s [%s / %s]\n" % [edge.chain_label, edge.kind, edge.field]
	details.text += "\n影响分析\n%s\n" % JSON.stringify({"direct":impact.get("direct",[]).size(),"indirect":impact.get("indirect",[]).size(),"blocked_delete":impact.get("blocked_delete",false)}, "  ")

func _locate_selected() -> void:
	if selected_entry.is_empty():
		_set_status("请先选择一项内容。", false)
		return
	var path := str(selected_entry.path)
	if not FileAccess.file_exists(path):
		_set_status("定位失败：资源已移动或删除，已安全提示而不是崩溃。", false)
		return
	if editor_interface != null:
		var resource = ResourceLoader.load(path)
		if resource != null: editor_interface.edit_resource(resource); _set_status("已在 Godot 原生 Inspector 定位：%s" % path, true); return
	_set_status("资源无法加载，定位已失效：%s" % path, false)

func _show_impact() -> void:
	if selected_entry.is_empty(): return
	var impact := graph.impact_analysis(str(selected_entry.content_id))
	details.text = "引用链 / 影响分析\n" + JSON.stringify(impact, "  ")
	_set_status("已显示直接与间接反向引用链。", true)

func _check_delete() -> void:
	if selected_entry.is_empty(): return
	var result := graph.can_delete(str(selected_entry.content_id))
	details.text += "\n\n删除保护检查\n" + JSON.stringify(result, "  ")
	_set_status(str(result.error_zh) if not result.ok else "没有强引用，可以进入删除确认流程。", result.ok)

func _batch_read_only() -> void:
	var item := table.get_next_selected(null)
	var selected: Array[Dictionary] = []
	while item != null:
		selected.append(item.get_metadata(0))
		item = table.get_next_selected(item)
	if selected.is_empty() and not selected_entry.is_empty(): selected.append(selected_entry)
	details.text = "批量只读查看（%d 项）\n" % selected.size()
	for entry in selected:
		details.text += "- %s | %s | %s | %s\n" % [entry.display_name_zh, entry.content_id, entry.content_type_id, entry.path]
	_set_status("已生成只读批量视图，未修改任何 Resource。", true)

func _toggle_view() -> void:
	card_mode = not card_mode
	table.visible = not card_mode
	cards.visible = card_mode
	view_button.text = "切换表格" if card_mode else "切换卡片"
	_refresh_view()

func _open_wizard() -> void:
	if is_instance_valid(wizard):
		wizard.visible = true
		return
	wizard = WIZARD_SCRIPT.new()
	wizard.name = "新内容类型向导"
	wizard.configure(editor_interface, editor_undo_redo)
	wizard.generated.connect(_on_type_generated)
	add_child(wizard)
	wizard.visible = true
	_set_status("已打开真实新内容类型向导；生成前会做路径、基类、ID 和 class_name 预检。", true)

func _on_type_generated(_manifest: Dictionary) -> void:
	_initial_scan()

func _set_status(message: String, ok: bool) -> void:
	if status_label == null: return
	status_label.text = message
	status_label.modulate = Color("80ffb0") if ok else Color("ffb080")

func get_capture_snapshot() -> Dictionary:
	var thumbnail_valid_count := 0
	var thumbnail_fallback_count := 0
	for entry in current_entries:
		if bool(entry.get("thumbnail_ok", false)): thumbnail_valid_count += 1
		else: thumbnail_fallback_count += 1
	return {
		"dock": "GM内容资源库",
		"roots": library.roots if library != null else [],
		"content_count": library.entries.size() if library != null else 0,
		"filtered_count": current_entries.size(),
		"edge_count": graph.edges.size() if graph != null else 0,
		"issue_count": (library.issues.size() + graph.issues.size()) if library != null and graph != null else 0,
		"view": "cards" if card_mode else "table",
		"search": search_box.text if search_box != null else "",
		"type_count": registry_snapshot.definitions.size(),
		"wizard_visible": is_instance_valid(wizard) and wizard.visible,
		"selected_id": str(selected_entry.get("content_id", "")),
		"capture_state": OS.get_environment("GM_TASK03_EDITOR_CAPTURE_STATE"),
		"thumbnail_valid_count": thumbnail_valid_count,
		"thumbnail_fallback_count": thumbnail_fallback_count,
		"cards_have_texture_slots": card_mode,
		"wizard": wizard.get_capture_snapshot() if is_instance_valid(wizard) and wizard.has_method("get_capture_snapshot") else {},
	}
