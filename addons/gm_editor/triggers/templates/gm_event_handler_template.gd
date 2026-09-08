extends GMEventHandler

## 任务包07处理器模板：只返回声明式后续数据，不直接写领域事实。

func _handle_event(event: GMGameplayEvent, context: Dictionary) -> Dictionary:
	return {"ok": true, "handled": true, "event_tag": event.event_tag if event != null else "", "context_keys": context.keys()}
