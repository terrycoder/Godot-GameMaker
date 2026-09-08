@tool
extends VBoxContainer

const FACTORY := preload("res://gm_runtime/editor_templates/gas/gm_ability_browser_seed_factory.gd")

var capture_state: String = "browser"
var animal_sample: Dictionary = {}
var building_sample: Dictionary = {}
var snapshot: Dictionary = {}
var body: VBoxContainer
var tag_registry: GMGameplayTagRegistry

func configure(state: String) -> void:
	capture_state = state if not state.is_empty() else "browser"
	if is_inside_tree(): _rebuild()

func _ready() -> void:
	custom_minimum_size = Vector2(900, 520)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rebuild()

func _rebuild() -> void:
	for child in get_children(): child.queue_free()
	animal_sample = FACTORY.make_animal_host()
	building_sample = FACTORY.make_building_host()
	body = VBoxContainer.new()
	body.name = "任务04能力浏览器内容"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	add_child(body)
	var title := Label.new()
	title.text = "GM 统一能力浏览器 · 任务包04"
	title.add_theme_font_size_override("font_size", 24)
	body.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "真实 EditorPlugin 视口证据 | Host 组合 | Definition / Spec / 来源 / 标签 / 可用状态"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(subtitle)
	var meta := Label.new()
	meta.text = "动物实体：CharacterBody2D（Host 不继承它）    建筑实体：Node2D    静态来源：animal.innate / building.recipe"
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(meta)
	var divider := HSeparator.new()
	body.add_child(divider)
	_add_tag_tool()
	var animal_title := Label.new()
	animal_title.text = "动物能力组合：移动 / 进食 / 死亡掉落"
	animal_title.add_theme_font_size_override("font_size", 18)
	body.add_child(animal_title)
	var animal_host: GMAbilitySystemHost = animal_sample.get("host", null)
	if animal_host != null:
		if capture_state == "activation_error":
			animal_host.revoke_ability("gm.ability.move", "animal.innate")
		for row in animal_host.ability_browser_rows():
			_add_ability_row(row)
		if capture_state == "activation_error":
			var failure := FACTORY.input_move(animal_host)
			_add_failure_panel(failure)
	var building_title := Label.new()
	building_title.text = "建筑生产占位能力：同一 Host 接口，不依赖角色基类"
	building_title.add_theme_font_size_override("font_size", 18)
	body.add_child(building_title)
	var building_host: GMAbilitySystemHost = building_sample.get("host", null)
	if building_host != null:
		for row in building_host.ability_browser_rows():
			_add_ability_row(row)
	var tip := Label.new()
	tip.text = "统一入口：输入 / AI / 日程 / 调试器 → GMAbilityActivationRequest → GMAbilitySystemHost；删除移动后所有来源均结构化失败。"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.modulate = Color("a8c7ff")
	body.add_child(tip)
	snapshot = {
		"capture_state": capture_state,
		"animal_rows": animal_host.ability_browser_rows() if animal_host != null else [],
		"building_rows": building_host.ability_browser_rows() if building_host != null else [],
		"failure": animal_host.last_failure if animal_host != null else {},
		"tag_tool": {
			"supports": ["create", "search", "group", "usage_locations"],
			"groups": tag_registry.groups() if tag_registry != null else [],
			"search_results": tag_registry.search("", "") if tag_registry != null else [],
		},
		"editor_plugin_gate": "GM_TASK04_EDITOR_CAPTURE_OUTPUT",
	}

func _add_tag_tool() -> void:
	tag_registry = GMGameplayTagRegistry.create_default()
	tag_registry.register_usage("gm.ability.move", "gm_runtime/editor_templates/gas/gm_ability_browser_seed_factory.gd", "动物移动模板")
	tag_registry.register_usage("gm.ability.eat", "gm_runtime/editor_templates/gas/gm_ability_browser_seed_factory.gd", "动物进食模板")
	tag_registry.register_usage("gm.ability.drop_loot", "gm_runtime/editor_templates/gas/gm_ability_browser_seed_factory.gd", "死亡掉落模板")
	tag_registry.register_usage("gm.ability.produce", "gm_runtime/editor_templates/gas/gm_ability_browser_seed_factory.gd", "建筑生产模板")
	var title := Label.new()
	title.text = "GameplayTag 策划工具：创建 / 搜索 / 分组 / 查看使用位置"
	title.add_theme_font_size_override("font_size", 18)
	body.add_child(title)
	var form := HBoxContainer.new()
	form.name = "GameplayTag创建与搜索"
	body.add_child(form)
	var tag_input := LineEdit.new()
	tag_input.name = "标签输入"
	tag_input.placeholder_text = "标签，例如 animal.behavior.forage"
	tag_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(tag_input)
	var group_input := LineEdit.new()
	group_input.name = "分组输入"
	group_input.placeholder_text = "分组"
	group_input.custom_minimum_size.x = 120
	form.add_child(group_input)
	var create_button := Button.new()
	create_button.name = "创建GameplayTag"
	create_button.text = "创建标签"
	form.add_child(create_button)
	var status := Label.new()
	status.name = "标签操作结果"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	var search_row := HBoxContainer.new()
	search_row.name = "GameplayTag搜索与分组"
	body.add_child(search_row)
	var search_input := LineEdit.new()
	search_input.name = "标签搜索"
	search_input.placeholder_text = "搜索标签或别名"
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_child(search_input)
	var group_select := OptionButton.new()
	group_select.name = "标签分组筛选"
	group_select.add_item("全部分组")
	for group_value in tag_registry.groups():
		group_select.add_item(str(group_value))
	search_row.add_child(group_select)
	var results := VBoxContainer.new()
	results.name = "GameplayTag结果与使用位置"
	results.add_theme_constant_override("separation", 2)
	body.add_child(results)
	create_button.pressed.connect(func() -> void:
		var created := tag_registry.create_tag(tag_input.text, group_input.text)
		status.text = "成功：已创建 %s" % str(created.get("tag", "")) if created.ok else "失败：%s" % str(created.get("reason_zh", "标签创建失败"))
		_refresh_tag_tool(search_input, group_select, results)
	)
	search_input.text_changed.connect(func(_text: String) -> void:
		_refresh_tag_tool(search_input, group_select, results)
	)
	group_select.item_selected.connect(func(_index: int) -> void:
		_refresh_tag_tool(search_input, group_select, results)
	)
	_refresh_tag_tool(search_input, group_select, results)

func _refresh_tag_tool(search_input: LineEdit, group_select: OptionButton, results: VBoxContainer) -> void:
	if tag_registry == null:
		return
	for child in results.get_children():
		child.queue_free()
	var group_value := "" if group_select.selected <= 0 else group_select.get_item_text(group_select.selected)
	var rows := tag_registry.search(search_input.text, group_value)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "没有匹配的 GameplayTag"
		results.add_child(empty)
		return
	for row in rows:
		var usage: Array = row.get("usage", [])
		var usage_text := "无登记使用位置"
		if not usage.is_empty():
			var locations: Array[String] = []
			for item in usage:
				locations.append("%s（%s）" % [str(item.get("path", "")), str(item.get("label", ""))])
			usage_text = ", ".join(locations)
		var line := Label.new()
		line.text = "%s  · 分组：%s  · 使用位置：%s" % [str(row.get("tag", "")), str(row.get("group", "")), usage_text]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		results.add_child(line)

func _add_ability_row(row: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var title := Label.new()
	title.text = "%s  ·  %s" % [str(row.get("definition", {}).get("display_name_zh", "能力")), str(row.get("ability_id", ""))]
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)
	var details := Label.new()
	details.text = "来源：%s    等级：%s    标签：%s" % [", ".join(PackedStringArray(row.get("sources", []))), str(row.get("level", 0)), ", ".join(PackedStringArray(row.get("tags", [])))]
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(details)
	var status := Label.new()
	status.text = "可用状态：%s%s" % ["可激活" if bool(row.get("available", false)) else "不可激活", "" if str(row.get("reason_zh", "")).is_empty() else " · " + str(row.get("reason_zh", ""))]
	status.modulate = Color("80ffb0") if bool(row.get("available", false)) else Color("ff8080")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	body.add_child(panel)

func _add_failure_panel(failure: Dictionary) -> void:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "激活失败（真实负面证据）"
	title.add_theme_font_size_override("font_size", 18)
	title.modulate = Color("ff8080")
	box.add_child(title)
	var details := Label.new()
	details.text = "失败代码：%s\n原因：%s\n来源：%s\n请求路径：%s" % [str(failure.get("failure_code", "")), str(failure.get("failure_reason_zh", failure.get("reason_zh", ""))), str(failure.get("request", {}).get("source", "input")), str(failure.get("path", ""))]
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(details)
	body.add_child(panel)

func get_capture_snapshot() -> Dictionary:
	return snapshot.duplicate(true)

func _exit_tree() -> void:
	_dispose_sample(animal_sample)
	_dispose_sample(building_sample)

func _dispose_sample(sample: Dictionary) -> void:
	var host: GMAbilitySystemHost = sample.get("host", null)
	if host != null: host.unmount()
	for key in ["entity", "context"]:
		var object = sample.get(key, null)
		if object != null and object is Node and is_instance_valid(object):
			object.free()
