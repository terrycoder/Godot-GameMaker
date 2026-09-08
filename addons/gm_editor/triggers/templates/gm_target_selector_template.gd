extends GMTargetSelector

## 任务包07目标选择器模板：返回 GMTargetData，不保存裸 NodePath 业务身份。

func _select(event: GMGameplayEvent, context: Dictionary) -> Dictionary:
	if event != null and event.target != null and is_instance_valid(event.target):
		return {"ok": true, "targets": [GMTargetData.from_entity(event.target)], "source": "template.event_target", "context_keys": context.keys()}
	return {"ok": false, "code": "target.missing", "reason_zh": "模板目标选择器没有收到有效事件目标。"}
