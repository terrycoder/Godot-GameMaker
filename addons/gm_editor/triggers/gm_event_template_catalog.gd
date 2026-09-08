@tool
class_name GMEventTemplateCatalog
extends RefCounted

## 正式模板目录；编辑、保存后由运行时 registry 重新发现。

const TEMPLATES := {
	"condition": "res://addons/gm_editor/triggers/templates/gm_event_condition_template.gd",
	"handler": "res://addons/gm_editor/triggers/templates/gm_event_handler_template.gd",
	"selector": "res://addons/gm_editor/triggers/templates/gm_target_selector_template.gd"
}

static func all_templates() -> Dictionary:
	return TEMPLATES.duplicate(true)

static func validate_all() -> Dictionary:
	var rows: Array[Dictionary] = []
	for kind in TEMPLATES:
		var path: String = TEMPLATES[kind]
		var check: Dictionary
		match kind:
			"condition": check = GMEventScriptValidator.validate_condition_script(path)
			"handler": check = GMEventScriptValidator.validate_handler_script(path)
			"selector": check = GMEventScriptValidator.validate_selector_script(path)
		rows.append({"kind": kind, "path": path, "validation": check})
	return {"ok": rows.all(func(row): return bool(row.get("validation", {}).get("ok", false))), "templates": rows}
