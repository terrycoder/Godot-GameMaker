@tool
class_name GMChineseEditorProperty
extends EditorProperty

## 通用中文 EditorProperty：只编辑 Inspector 当前绑定的同一 Resource，不建立影子配置。
var _kind := "string"
var _control: Control
var _updating := false

func configure(kind: String, help_text: String = "") -> void:
	_kind = kind
	if not help_text.strip_edges().is_empty(): tooltip_text = help_text
	if _kind == "bool":
		var check := CheckButton.new()
		check.text = "启用"
		check.toggled.connect(func(value: bool): _emit_value(value))
		_control = check
	elif _kind == "multiline":
		var text_edit := TextEdit.new()
		text_edit.custom_minimum_size = Vector2(0, 64)
		text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		text_edit.text_changed.connect(func(): _emit_value(text_edit.text))
		_control = text_edit
	elif _kind == "string_array":
		var array_edit := LineEdit.new()
		array_edit.placeholder_text = "多个值用逗号分隔"
		array_edit.text_changed.connect(func(value: String): _emit_value(PackedStringArray(value.split(",", false))))
		_control = array_edit
	elif _kind == "resource" or _kind == "texture":
		var picker := EditorResourcePicker.new()
		picker.base_type = "Texture2D" if _kind == "texture" else "Resource"
		picker.resource_changed.connect(func(value: Resource): _emit_value(value))
		_control = picker
	else:
		var line := LineEdit.new()
		line.text_changed.connect(func(value: String): _emit_value(value))
		_control = line
	_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_control)
	add_focusable(_control)

func _update_property() -> void:
	if _control == null or get_edited_object() == null: return
	var value = get_edited_object().get(get_edited_property())
	_updating = true
	if _kind == "bool":
		(_control as CheckButton).button_pressed = bool(value)
	elif _kind == "multiline":
		(_control as TextEdit).text = str(value)
	elif _kind == "string_array":
		(_control as LineEdit).text = ", ".join(Array(value))
	elif _kind == "resource" or _kind == "texture":
		var resource_value: Resource = value if value is Resource else null
		(_control as EditorResourcePicker).edited_resource = resource_value
	else:
		(_control as LineEdit).text = str(value)
	_updating = false

func _emit_value(value: Variant) -> void:
	if _updating: return
	emit_changed(get_edited_property(), value)
