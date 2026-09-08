extends Control

## Minimal P21 export entry: validates the neutral dialogue/shop envelopes and
## leaves all live writes to the injected P16/P19/P20 backends.

var runtime := GMP21Runtime.new()

func _ready() -> void:
	_build_ui()
	var facts := _smoke()
	print(JSON.stringify(facts))
	if OS.get_cmdline_args().has("--headless") or DisplayServer.get_name() == "headless":
		call_deferred("_finish", 0 if bool(facts.get("ok", false)) else 166)

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("101927")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_bottom", 36)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "P21 对话、交互、商店与 Task 投影"
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)
	var body := Label.new()
	body.text = "统一交互请求路由；对话只保存会话编排；商店报价/订单交给既有 P19 事务；Task 页面只读读取 P16。"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)

func _smoke() -> Dictionary:
	var choice := GMDialogueChoice.new()
	choice.choice_id = "gm.choice.export.neutral"
	choice.display_name_zh = "继续"
	choice.text_zh = "继续"
	choice.next_node_id = ""
	choice.order = 0
	var node := GMDialogueNode.new()
	node.node_id = "gm.node.export.entry"
	node.speaker_ref = "gm.actor.export"
	node.text_zh = "导出启动检查"
	node.choices = [choice]
	var definition := GMDialogueDefinition.new()
	definition.dialogue_id = "gm.dialogue.export.neutral"
	definition.display_name_zh = "导出启动检查"
	definition.entry_node_id = node.node_id
	definition.nodes = [node]
	var dialogue_check := definition.validate()
	var shop_definition := GMShopDefinition.new().configure("gm.shop.export.neutral", 1, "gm.resource.export.gold", [{"offer_id": "gm.offer.export.apple", "item_kind": "lot", "item_id": "gm.item.export.apple", "buy_unit_price": 1, "sell_unit_price": 1}])
	var shop_check := shop_definition.validate()
	return {"event": "P21_EXPORT_SENTINEL", "ok": dialogue_check.ok and shop_check.ok, "dialogue_schema": GMP21Contract.DIALOGUE_SCHEMA_VERSION, "shop_schema": GMP21Contract.SHOP_DEFINITION_SCHEMA_VERSION, "single_router": runtime.router != null, "task_projection_read_only": true}

func _finish(code: int) -> void:
	get_tree().quit(code)
