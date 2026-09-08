class_name GMShopService
extends RefCounted

## Catalog and quote orchestration only. Live money, item quantity, capacity,
## reservation and idempotent commit remain in P19.

var definitions: Dictionary = {}
var interaction_router: GMInteractionRouter

func _init(p_router: GMInteractionRouter = null) -> void:
	interaction_router = p_router

func register_definition(definition: GMShopDefinition) -> Dictionary:
	if definition == null:
		return GMP21Contract.failure("shop.definition_missing", "不能注册空ShopDefinition。")
	var checked := definition.validate()
	if not checked.ok: return checked
	if definitions.has(definition.shop_id):
		var existing: GMShopDefinition = definitions[definition.shop_id]
		if existing.to_dict() == definition.to_dict(): return {"ok": true, "code": "shop.definition_unchanged", "duplicate": true}
		if definition.revision <= existing.revision:
			return GMP21Contract.failure("shop.definition_conflict", "ShopDefinition修订号未递增或内容冲突。")
	definitions[definition.shop_id] = definition
	return {"ok": true, "code": "shop.definition_registered", "shop_id": definition.shop_id, "revision": definition.revision}

func quote(shop_id: String, offer_id: String, side: String, quantity: int, buyer_ref: Variant, seller_ref: Variant) -> Dictionary:
	var definition: GMShopDefinition = definitions.get(shop_id, null)
	if definition == null: return GMP21Contract.failure("shop.missing", "ShopDefinition不存在。", {"shop_id": shop_id})
	var definition_check := definition.validate()
	if not definition_check.ok: return definition_check
	if side not in GMP21Contract.SHOP_SIDES or not GMP21Contract.positive_integer(quantity): return GMP21Contract.failure("shop.quote_input_invalid", "报价方向和数量必须是受支持的正整数。")
	var offer := definition.get_offer(offer_id)
	if offer.is_empty(): return GMP21Contract.failure("shop.offer_missing", "Shop Offer不存在。", {"offer_id": offer_id})
	var buyer := GMP21Contract.target_ref(buyer_ref)
	if not buyer.ok: return buyer
	var seller := GMP21Contract.target_ref(seller_ref)
	if not seller.ok: return seller
	var unit_price := int(offer.get("buy_unit_price", 0)) if side == "buy" else int(offer.get("sell_unit_price", 0))
	if unit_price > int(GMStableData.JSON_SAFE_INTEGER_MAX) / quantity: return GMP21Contract.failure("shop.quote_overflow", "报价总价超出JSON安全整数范围。")
	var result := GMShopQuote.create(shop_id, definition.revision, offer_id, str(offer.get("item_kind", "lot")), str(offer.get("item_id", "")), side, quantity, unit_price, definition.currency_resource_id, buyer.value, seller.value)
	return {"ok": true, "code": "shop.quote_built", "quote": result, "quote_data": result.to_dict()}

func build_order(quote_value: Variant, idempotency_key: String, source_container_id: String, target_container_id: String, source_account_id: String, target_account_id: String) -> Dictionary:
	var quote: GMShopQuote = quote_value if quote_value is GMShopQuote else GMShopQuote.from_dict(quote_value, true) if quote_value is Dictionary else null
	if quote == null or not quote.validate().ok: return GMP21Contract.failure("shop.quote_invalid", "提交订单需要有效ShopQuote。")
	if not GMP21Contract.stable_id(idempotency_key) or not GMP21Contract.stable_id(source_container_id) or not GMP21Contract.stable_id(target_container_id) or not GMP21Contract.stable_id(source_account_id) or not GMP21Contract.stable_id(target_account_id): return GMP21Contract.failure("shop.order_input_invalid", "订单幂等键、容器或账户身份无效。")
	var definition: GMShopDefinition = definitions.get(quote.shop_id, null)
	if definition == null: return GMP21Contract.failure("shop.missing", "ShopDefinition不存在。")
	if definition.revision != quote.shop_revision: return GMP21Contract.failure("shop.quote_expired", "ShopDefinition已修订，旧Quote已过期。")
	var offer := definition.get_offer(quote.offer_id)
	if offer.is_empty(): return GMP21Contract.failure("shop.offer_missing", "Quote引用的Offer不存在。")
	var order := GMShopOrder.create(quote, idempotency_key, source_container_id, target_container_id, source_account_id, target_account_id)
	order.set_total_price(quote.total_price)
	var checked := order.validate()
	if not checked.ok: return checked
	return {"ok": true, "code": "shop.order_built", "order": order, "order_data": order.to_dict()}

func submit_order(order_value: Variant) -> GMInteractionResult:
	var order: GMShopOrder = order_value if order_value is GMShopOrder else GMShopOrder.from_dict(order_value, true) if order_value is Dictionary else null
	var public_order: Variant = order.to_dict() if order != null else order_value
	if order == null:
		return GMInteractionResult.rejected_public(public_order, "shop.order_invalid", "提交订单需要有效ShopOrder。", {}, "transaction", "gm.interaction.shop.order")
	var checked := order.validate()
	if not checked.ok:
		return GMInteractionResult.rejected_public(public_order, str(checked.get("code", "shop.order_invalid")), str(checked.get("reason_zh", "ShopOrder无效。")), checked, "transaction", "gm.interaction.shop.order")
	var definition: GMShopDefinition = definitions.get(order.shop_id, null)
	if definition == null:
		return GMInteractionResult.rejected_public(public_order, "shop.missing", "ShopDefinition不存在。", {}, "transaction", "gm.interaction.shop.order")
	if definition.revision != order.shop_revision:
		return _order_result_without_request(order, "shop.quote_expired", "ShopDefinition已修订，旧订单被拒绝。")
	var offer := definition.get_offer(order.offer_id)
	if offer.is_empty():
		return _order_result_without_request(order, "shop.offer_missing", "订单引用的Offer不存在。")
	var expected_unit_price := int(offer.get("buy_unit_price", 0)) if order.side == "buy" else int(offer.get("sell_unit_price", 0))
	var expected_quote := GMShopQuote.create(definition.shop_id, definition.revision, order.offer_id, str(offer.get("item_kind", "")), str(offer.get("item_id", "")), order.side, order.quantity, expected_unit_price, definition.currency_resource_id, order.buyer_ref, order.seller_ref)
	if expected_quote.quote_id != order.quote_id or expected_quote.total_price != order.total_price:
		return _order_result_without_request(order, "shop.order_quote_mismatch", "订单未能证明来自当前ShopDefinition的确定性报价。")
	var payload := order.p19_payload(definition.currency_resource_id)
	var request := GMInteractionRequest.transaction("gm.interaction.shop.%s" % order.side, order.buyer_ref, order.seller_ref, payload, order.idempotency_key)
	if interaction_router == null:
		return GMInteractionResult.rejected(request, "interaction.backend_missing", "商店事务没有安装可用P19 Backend。")
	return interaction_router.submit(request)

func buy(shop_id: String, offer_id: String, quantity: int, buyer_ref: Variant, seller_ref: Variant, idempotency_key: String, source_container_id: String, target_container_id: String, source_account_id: String, target_account_id: String) -> GMInteractionResult:
	var quoted := quote(shop_id, offer_id, "buy", quantity, buyer_ref, seller_ref)
	var public_input := _shop_public_input("buy", shop_id, offer_id, quantity, buyer_ref, seller_ref, idempotency_key, source_container_id, target_container_id, source_account_id, target_account_id)
	if not quoted.ok: return GMInteractionResult.rejected_public(public_input, str(quoted.get("code", "shop.quote_invalid")), str(quoted.get("reason_zh", "无法报价。")), quoted, "transaction", "gm.interaction.shop.buy")
	var ordered := build_order(quoted.quote, idempotency_key, source_container_id, target_container_id, source_account_id, target_account_id)
	if not ordered.ok: return GMInteractionResult.rejected_public(public_input, str(ordered.get("code", "shop.order_invalid")), str(ordered.get("reason_zh", "无法建立订单。")), ordered, "transaction", "gm.interaction.shop.buy")
	return submit_order(ordered.order)

func sell(shop_id: String, offer_id: String, quantity: int, buyer_ref: Variant, seller_ref: Variant, idempotency_key: String, source_container_id: String, target_container_id: String, source_account_id: String, target_account_id: String) -> GMInteractionResult:
	var quoted := quote(shop_id, offer_id, "sell", quantity, buyer_ref, seller_ref)
	var public_input := _shop_public_input("sell", shop_id, offer_id, quantity, buyer_ref, seller_ref, idempotency_key, source_container_id, target_container_id, source_account_id, target_account_id)
	if not quoted.ok: return GMInteractionResult.rejected_public(public_input, str(quoted.get("code", "shop.quote_invalid")), str(quoted.get("reason_zh", "无法报价。")), quoted, "transaction", "gm.interaction.shop.sell")
	var ordered := build_order(quoted.quote, idempotency_key, source_container_id, target_container_id, source_account_id, target_account_id)
	if not ordered.ok: return GMInteractionResult.rejected_public(public_input, str(ordered.get("code", "shop.order_invalid")), str(ordered.get("reason_zh", "无法建立订单。")), ordered, "transaction", "gm.interaction.shop.sell")
	return submit_order(ordered.order)

func snapshot() -> Dictionary:
	var rows: Array = []
	for shop_id in definitions:
		var definition: GMShopDefinition = definitions[shop_id]
		rows.append(definition.to_dict())
	rows.sort_custom(func(left: Dictionary, right: Dictionary): return str(left.get("shop_id", "")) < str(right.get("shop_id", "")))
	return {"schema_version": "gm.p21.shop.catalog.v1", "definitions": rows}

func _shop_public_input(side: String, shop_id: String, offer_id: String, quantity: int, buyer_ref: Variant, seller_ref: Variant, idempotency_key: String, source_container_id: String, target_container_id: String, source_account_id: String, target_account_id: String) -> Dictionary:
	return {"kind": "transaction", "interaction_id": "gm.interaction.shop.%s" % side, "side": side, "shop_id": shop_id, "offer_id": offer_id, "quantity": quantity, "buyer_ref": GMP21Contract.public_identity(buyer_ref), "seller_ref": GMP21Contract.public_identity(seller_ref), "idempotency_key": idempotency_key, "source_container_id": source_container_id, "target_container_id": target_container_id, "source_account_id": source_account_id, "target_account_id": target_account_id}

func _order_result_without_request(order: GMShopOrder, code: String, reason: String) -> GMInteractionResult:
	var request := GMInteractionRequest.transaction("gm.interaction.shop.%s" % order.side, order.buyer_ref, order.seller_ref, {"shop_order_id": order.order_id}, order.idempotency_key)
	return GMInteractionResult.rejected(request, code, reason, {"order_id": order.order_id, "quote_id": order.quote_id})
