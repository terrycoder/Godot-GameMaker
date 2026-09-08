class_name GMShopOrder
extends RefCounted

const SCHEMA_VERSION := GMP21Contract.SHOP_ORDER_SCHEMA_VERSION
const FIELDS := ["schema_version", "order_id", "quote_id", "shop_id", "shop_revision", "offer_id", "item_kind", "item_id", "side", "quantity", "total_price", "buyer_ref", "seller_ref", "source_container_id", "target_container_id", "source_account_id", "target_account_id", "idempotency_key"]

var schema_version := SCHEMA_VERSION
var order_id := ""
var quote_id := ""
var shop_id := ""
var shop_revision := 0
var offer_id := ""
var item_kind := ""
var item_id := ""
var side := ""
var quantity := 0
var total_price := 0
var buyer_ref: Variant = ""
var seller_ref: Variant = ""
var source_container_id := ""
var target_container_id := ""
var source_account_id := ""
var target_account_id := ""
var idempotency_key := ""

func validate() -> Dictionary:
	var value := to_dict()
	if not GMP21Contract.exact(value, FIELDS):
		return GMP21Contract.failure("shop.order_shape_invalid", "ShopOrder字段集合必须精确匹配。")
	if schema_version != SCHEMA_VERSION or not GMP21Contract.stable_id(order_id) or not GMP21Contract.stable_id(quote_id) or not GMP21Contract.stable_id(shop_id) or not GMP21Contract.positive_integer(shop_revision) or not GMP21Contract.stable_id(offer_id) or item_kind not in ["lot", "instance"] or not GMP21Contract.stable_id(item_id) or side not in GMP21Contract.SHOP_SIDES or not GMP21Contract.positive_integer(quantity) or not GMP21Contract.nonnegative_integer(total_price) or not GMP21Contract.stable_id(source_container_id) or not GMP21Contract.stable_id(target_container_id) or not GMP21Contract.stable_id(source_account_id) or not GMP21Contract.stable_id(target_account_id) or not GMP21Contract.stable_id(idempotency_key):
		return GMP21Contract.failure("shop.order_identity_invalid", "ShopOrder身份、方向、数量、容器、账户或幂等键无效。")
	var buyer := GMP21Contract.target_ref(buyer_ref)
	if not buyer.ok: return buyer
	var seller := GMP21Contract.target_ref(seller_ref)
	if not seller.ok: return seller
	if order_id != derive_order_id():
		return GMP21Contract.failure("shop.order_identity_mismatch", "ShopOrder的order_id不是由quote和提交上下文确定性派生。")
	return {"ok": true, "code": "shop.order_valid", "value": value}

func derive_order_id() -> String:
	return "gm.shop.order.%s" % GMP21Contract.digest({"quote_id": quote_id, "shop_id": shop_id, "shop_revision": shop_revision, "offer_id": offer_id, "item_kind": item_kind, "item_id": item_id, "side": side, "quantity": quantity, "total_price": total_price, "buyer_ref": buyer_ref, "seller_ref": seller_ref, "source_container_id": source_container_id, "target_container_id": target_container_id, "source_account_id": source_account_id, "target_account_id": target_account_id, "idempotency_key": idempotency_key})

func p19_payload(currency_resource_id: String) -> Dictionary:
	var buyer_id := _ref_id(buyer_ref)
	var seller_id := _ref_id(seller_ref)
	var source_id := seller_id
	var target_id := buyer_id
	var input_account := source_account_id if side == "buy" else source_account_id
	var output_account := target_account_id if side == "buy" else target_account_id
	return {"p19_operation": "trade", "inventory_operation": "transfer", "numeric_operation": "transfer", "item_kind": item_kind, "item_id": item_id, "trade_offer_id": offer_id, "source_container_id": source_container_id, "target_container_id": target_container_id, "quantity": quantity, "resource_inputs": [{"account_id": input_account, "resource_id": currency_resource_id, "amount": total_price}], "resource_outputs": [{"account_id": output_account, "resource_id": currency_resource_id, "amount": total_price}], "source_id": source_id, "target_id": target_id, "shop_id": shop_id, "shop_quote_id": quote_id, "shop_order_id": order_id, "buyer_id": buyer_id, "seller_id": seller_id}

func set_total_price(value: int) -> void:
	total_price = value

func _ref_id(value: Variant) -> String:
	if value is String: return str(value)
	if value is Dictionary:
		if value.has("id"): return str(value.get("id", ""))
		if value.has("semantic_id"): return str(value.get("semantic_id", ""))
	return ""

func to_dict() -> Dictionary:
	return {"schema_version": schema_version, "order_id": order_id, "quote_id": quote_id, "shop_id": shop_id, "shop_revision": shop_revision, "offer_id": offer_id, "item_kind": item_kind, "item_id": item_id, "side": side, "quantity": quantity, "total_price": total_price, "buyer_ref": GMStableData.clone(buyer_ref), "seller_ref": GMStableData.clone(seller_ref), "source_container_id": source_container_id, "target_container_id": target_container_id, "source_account_id": source_account_id, "target_account_id": target_account_id, "idempotency_key": idempotency_key}

func to_json() -> String:
	return JSON.stringify(GMStableData.persistence_canonical(to_dict()), "", false, true)

static func create(quote: GMShopQuote, p_idempotency_key: String, p_source_container_id: String, p_target_container_id: String, p_source_account_id: String, p_target_account_id: String) -> GMShopOrder:
	var result := GMShopOrder.new()
	result.quote_id = quote.quote_id
	result.shop_id = quote.shop_id
	result.shop_revision = quote.shop_revision
	result.offer_id = quote.offer_id
	result.item_kind = quote.item_kind
	result.item_id = quote.item_id
	result.side = quote.side
	result.quantity = quote.quantity
	result.total_price = quote.total_price
	result.buyer_ref = GMStableData.clone(quote.buyer_ref)
	result.seller_ref = GMStableData.clone(quote.seller_ref)
	result.idempotency_key = p_idempotency_key
	result.source_container_id = p_source_container_id
	result.target_container_id = p_target_container_id
	result.source_account_id = p_source_account_id
	result.target_account_id = p_target_account_id
	result.order_id = result.derive_order_id()
	return result

static func from_dict(value: Variant, json_boundary: bool = false) -> GMShopOrder:
	if not value is Dictionary or not GMP21Contract.exact(value, FIELDS): return null
	var source: Dictionary = value.duplicate(true)
	for field in ["schema_version", "order_id", "quote_id", "shop_id", "offer_id", "item_kind", "item_id", "side", "buyer_ref", "seller_ref", "source_container_id", "target_container_id", "source_account_id", "target_account_id", "idempotency_key"]:
		if field in ["buyer_ref", "seller_ref"]:
			if not source.get(field) is String and not source.get(field) is Dictionary: return null
		elif typeof(source.get(field)) != TYPE_STRING:
			return null
	if json_boundary:
		for field in ["shop_revision", "quantity", "total_price"]:
			if typeof(source.get(field)) == TYPE_FLOAT and is_finite(float(source[field])) and float(source[field]) == floor(float(source[field])): source[field] = int(source[field])
	if typeof(source.get("shop_revision")) != TYPE_INT or typeof(source.get("quantity")) != TYPE_INT or typeof(source.get("total_price")) != TYPE_INT: return null
	var result := GMShopOrder.new()
	for field in FIELDS:
		if field == "schema_version": result.schema_version = str(source[field])
		elif field in ["shop_revision", "quantity", "total_price"]: result[field] = int(source[field])
		elif field in ["buyer_ref", "seller_ref"]: result[field] = GMStableData.clone(source[field])
		else: result[field] = str(source[field])
	return result if result.validate().ok else null

static func from_json(text: String) -> Dictionary:
	var parsed := GMP21Contract.normalize_json(text, "shop.order_json_invalid")
	if not parsed.ok: return parsed
	var order := from_dict(parsed.value, true)
	return {"ok": true, "code": "shop.order_decoded", "order": order} if order != null else GMP21Contract.failure("shop.order_json_invalid", "ShopOrder JSON未通过严格合同校验。")
