@tool
class_name GMContentTypeWizard
extends PanelContainer

const SPEC_SCRIPT := preload("res://addons/gm_editor/content/gm_content_type_generation_spec.gd")
const GENERATOR_SCRIPT := preload("res://addons/gm_editor/content/gm_content_type_generator.gd")

signal generated(manifest: Dictionary)

var editor_interface
var editor_undo_redo
var generator: GMContentTypeGenerator
var display_name_box: LineEdit
var type_id_box: LineEdit
var class_name_box: LineEdit
var base_box: LineEdit
var directory_box: LineEdit
var icon_box: LineEdit
var description_box: TextEdit
var fields_box: LineEdit
var result_label: Label
var files_view: TextEdit
var generate_button: Button
var instance_button: Button
var form_panel: Control
var actions_panel: Control
var last_manifest: Dictionary = {}
var capture_instance_path := ""
var capture_layout_hidden := false

func configure(p_editor_interface, p_undo_redo) -> void:
	editor_interface = p_editor_interface
	editor_undo_redo = p_undo_redo

func _ready() -> void:
	generator = GENERATOR_SCRIPT.new()
	custom_minimum_size = Vector2(0, 330)
	_build_ui()

func _build_ui() -> void:
	var panel := VBoxContainer.new()
	add_child(panel)
	var title_row := HBoxContainer.new()
	panel.add_child(title_row)
	var title := Label.new()
	title.text = "新内容类型向导（真实文件生成）"
	title.add_theme_font_size_override("font_size", 17)
	title_row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func(): visible = false)
	title_row.add_child(close)
	var form := GridContainer.new()
	form_panel = form
	form.columns = 2
	panel.add_child(form)
	display_name_box = _field(form, "中文名称", "门派制度")
	type_id_box = _field(form, "内容类型 ID", "demo.generated_faction")
	class_name_box = _field(form, "GDScript 类名", "GMGeneratedFactionContent")
	base_box = _field(form, "基础类型", "GMContent")
	directory_box = _field(form, "默认目录", "res://gm_runtime/content/generated")
	icon_box = _field(form, "图标路径（可空）", "")
	fields_box = _field(form, "可编辑字段（属性=中文名|帮助）", "notes_zh=设计说明|填写该类型的设计说明,design_rule_zh=设计规则|填写该类型的设计规则")
	var desc_label := Label.new()
	desc_label.text = "类型说明"
	form.add_child(desc_label)
	description_box = TextEdit.new()
	description_box.custom_minimum_size.y = 45
	description_box.text = "由 GM 向导生成的可编辑内容类型。"
	form.add_child(description_box)
	var actions := HBoxContainer.new()
	actions_panel = actions
	panel.add_child(actions)
	generate_button = Button.new()
	generate_button.text = "预检并生成完整文件"
	generate_button.pressed.connect(_generate)
	actions.add_child(generate_button)
	instance_button = Button.new()
	instance_button.text = "创建第二个实例"
	instance_button.disabled = true
	instance_button.pressed.connect(_create_instance)
	actions.add_child(instance_button)
	result_label = Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(result_label)
	files_view = TextEdit.new()
	files_view.name = "完整文件清单"
	files_view.editable = false
	files_view.custom_minimum_size.y = 95
	panel.add_child(files_view)

func _field(form: GridContainer, label_text: String, value: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	form.add_child(label)
	var field := LineEdit.new()
	field.text = value
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(field)
	return field

func _generate() -> void:
	var spec: GMContentTypeGenerationSpec = SPEC_SCRIPT.new()
	spec.display_name_zh = display_name_box.text
	spec.content_type_id = type_id_box.text.strip_edges()
	spec.generated_class_name = class_name_box.text.strip_edges()
	spec.base_class_name = base_box.text.strip_edges()
	spec.base_script_path = "res://gm_runtime/content/gm_content.gd" if spec.base_class_name == "GMContent" else ""
	spec.default_directory = directory_box.text.strip_edges().trim_suffix("/")
	spec.icon_path = icon_box.text.strip_edges()
	spec.description_zh = description_box.text
	var field_metadata := _parse_field_metadata(fields_box.text)
	spec.editable_fields = field_metadata.names
	spec.editable_field_labels_zh = field_metadata.labels
	spec.editable_field_help_zh = field_metadata.helps
	var manifest := generator.generate(spec)
	if not manifest.ok:
		last_manifest = {}
		instance_button.disabled = true
		result_label.text = "生成被阻断：%s\n回滚：%s" % [str(manifest.get("error_zh", "预检失败")), JSON.stringify(manifest.get("rollback", {}))]
		result_label.modulate = Color("ffb080")
		files_view.text = "未提交任何文件。\n" + "\n".join(manifest.get("errors_zh", []))
		return
	last_manifest = manifest
	_register_undo(manifest)
	instance_button.disabled = false
	result_label.text = "生成成功：已提交 %d 个文件；可继续编辑 GDScript，Resource 仍是唯一事实源。" % manifest.files.size()
	result_label.modulate = Color("80ffb0")
	files_view.text = "完整文件清单：\n" + "\n".join(manifest.paths)
	emit_signal("generated", manifest)

func _register_undo(manifest: Dictionary) -> void:
	if editor_undo_redo == null: return
	editor_undo_redo.create_action("GM 新内容类型：%s" % str(manifest.display_name_zh))
	editor_undo_redo.add_do_method(self, "_redo_manifest", manifest)
	editor_undo_redo.add_undo_method(self, "_undo_manifest", manifest)
	editor_undo_redo.commit_action()

func _redo_manifest(manifest: Dictionary) -> void:
	var result := generator.apply_manifest(manifest)
	result_label.text = "重做：%s" % ("已恢复完整文件。" if result.ok else str(result.error_zh))
	result_label.modulate = Color("80ffb0") if result.ok else Color("ffb080")
	if result.ok: emit_signal("generated", manifest)

func _undo_manifest(manifest: Dictionary) -> void:
	var result := generator.remove_manifest(manifest)
	result_label.text = "撤销：%s" % ("已删除本次生成的完整文件。" if result.ok else "; ".join(result.failures))
	result_label.modulate = Color("80ffb0") if result.ok else Color("ffb080")
	if result.ok: emit_signal("generated", {})

func _create_instance() -> void:
	if last_manifest.is_empty(): return
	var destination := str(last_manifest.default_directory).path_join("%s_example2.tres" % _safe_stem(str(last_manifest.generated_class_name)))
	var result := generator.create_instance(last_manifest, destination)
	capture_instance_path = destination if result.ok else ""
	result_label.text = "实例创建：%s" % (destination if result.ok else str(result.error_zh))
	result_label.modulate = Color("80ffb0") if result.ok else Color("ffb080")

func prepare_success_capture() -> void:
	_generate()
	if not last_manifest.is_empty(): _create_instance()
	if not last_manifest.is_empty():
		capture_layout_hidden = true
		if form_panel != null: form_panel.visible = false
		if actions_panel != null: actions_panel.visible = false
		files_view.custom_minimum_size.y = 170
		files_view.add_theme_font_size_override("font_size", 11)

func cleanup_capture_generation() -> void:
	if capture_layout_hidden:
		if form_panel != null: form_panel.visible = true
		if actions_panel != null: actions_panel.visible = true
		if files_view != null: files_view.remove_theme_font_size_override("font_size")
		capture_layout_hidden = false
	if not capture_instance_path.is_empty() and FileAccess.file_exists(capture_instance_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(capture_instance_path))
	if not last_manifest.is_empty(): generator.remove_manifest(last_manifest)

func _parse_field_metadata(value: String) -> Dictionary:
	var names: PackedStringArray = []
	var labels: PackedStringArray = []
	var helps: PackedStringArray = []
	for raw_value in value.split(","):
		var raw := str(raw_value).strip_edges()
		if raw.is_empty(): continue
		var definition := raw.split("=", true, 1)
		var name := str(definition[0]).strip_edges()
		var label_and_help := str(definition[1]).split("|", true, 1) if definition.size() > 1 else PackedStringArray()
		names.append(name)
		labels.append(str(label_and_help[0]).strip_edges() if label_and_help.size() > 0 else "")
		helps.append(str(label_and_help[1]).strip_edges() if label_and_help.size() > 1 else "")
	return {"names":names,"labels":labels,"helps":helps}

func _safe_stem(value: String) -> String:
	var result := ""
	for index in value.length():
		var character := value[index]
		if character.to_upper() == character and not character.to_lower() == character and index > 0: result += "_"
		result += character.to_lower()
	return result

func get_capture_snapshot() -> Dictionary:
	return {"visible":visible,"last_generation_ok":not last_manifest.is_empty(),"files":last_manifest.get("paths",[]),"instance_path":capture_instance_path,"result_text":result_label.text if result_label != null else "","form":{"display_name_zh":display_name_box.text if display_name_box != null else "","content_type_id":type_id_box.text if type_id_box != null else "","class_name":class_name_box.text if class_name_box != null else "","default_directory":directory_box.text if directory_box != null else "","editable_field_spec":fields_box.text if fields_box != null else ""}}
