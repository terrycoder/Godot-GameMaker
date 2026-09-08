extends GMEventCondition

## 任务包07条件模板：编辑脚本后由 GMEventScriptRegistry 重载并重新发现。

func _evaluate_custom(context: Dictionary) -> Dictionary:
	return {"ok": true, "matched": bool(context.get("template_condition", true)), "template": "GMEventCondition"}
