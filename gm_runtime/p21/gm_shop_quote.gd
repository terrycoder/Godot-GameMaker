class_name GMShopQuote
extends RefCounted

const SCHEMA_VERSION := GMP21Contract.SHOP_QUOTE_SCHEMA_VERSION
const FIELDS := ["schema_version", "quote_id", "shop_id", "shop_revision", "offer_id", "item_kind", "item_id", "side", "quantity", "unit_price", "total_price", "currency_resource_id", "buyer_ref", "seller_ref"]

var schema_version := SCHEMA_VERSION
var quote_id := ""
var shop_id := ""
var shop_revision := 0
var offer_id := ""
var item_kind := ""
var item_id := ""
var side := ""
var quantity := 0
var unit_price := 0
var total_price := 0
var currency_resource_id := ""
var buyer_ref: Variant = ""
var seller_ref: Variant = ""

func validate() -> Dictionary:
	var value := to_dict()
	if not GMP21Contract.exact(value, FIELDS):
		return GMP21Contract.failure("shop.quote_shape_invalid", "ShopQuote字段集合必须精确匹配。")
	if schema_version != SCHEMA_VERSION or not GMP21Contract.stable_id(quote_id) or not GMP21Contract.stable_id(shop_id) or not GMP21Contract.positive_integer(shop_revision) or not GMP21Contract.stable_id(offer_id) or item_kind not in ["lot", "instance"] or not GMP21Contract.stable_id(item_id) or side not in GMP21Contract.SHOP_SIDES or not GMP21Contract.positive_integer(quantity) or not GMP21Contract.nonnegative_integer(unit_price) or not GMP21Contract.nonnegative_integer(total_price) or not GMP21Contract.stable_id(currency_resource_id):
		return GMP21Contract.failure("shop.quote_identity_invalid", "ShopQuote版本、身份、方向、数量或整数价格无效。")
	if total_price != unit_price * quantity:
		return GMP21Contract.failure("shop.quote_total_invalid", "ShopQuote总价必须由单价与数量确定性计算。")
	var buyer := GMP21Contract.target_ref(buyer_ref)
	if not buyer.ok:
		return buyer
	var seller := GMP21Contract.target_ref(seller_ref)
	if not seller.ok:
		return seller
	if quote_id != derive_quote_id():
		return GMP21Contract.failure("shop.quote_identity_mismatch", "ShopQuote的quote_id不是由报价内容确定性派生。")
	return {"ok": true, "code": "shop.quote_valid", "value": value}

func derive_quote_id() -> String:
	return "gm.shop.quote.%s" % GMP21Contract.digest({"shop_id": shop_id, "shop_revision": shop_revision, "offer_id": offer_id, "item_kind": item_kind, "item_id": item_id, "side": side, "quantity": quantity, "unit_price": unit_price, "total_price": total_price, "currency_resource_id": currency_resource_id, "buyer_ref": buyer_ref, "seller_ref": seller_ref})

func to_dict() -> Dictionary:
	return {"schema_version": schema_version, "quote_id": quote_id, "shop_id": shop_id, "shop_revision": shop_revision, "offer_id": offer_id, "item_kind": item_kind, "item_id": item_id, "side": side, "quantity": quantity, "unit_price": unit_price, "total_price": total_price, "currency_resource_id": currency_resource_id, "buyer_ref": GMStableData.clone(buyer_ref), "seller_ref": GMStableData.clone(seller_ref)}

func to_json() -> String:
	return JSON.stringify(GMStableData.persistence_canonical(to_dict()), "", false, true)

static func create(p_shop_id: String, p_shop_revision: int, p_offer_id: String, p_item_kind: String, p_item_id: String, p_side: String, p_quantity: int, p_unit_price: int, p_currency_resource_id: String, p_buyer_ref: Variant, p_seller_ref: Variant) -> GMShopQuote:
	var result := GMShopQuote.new()
	result.shop_id = p_shop_id
	result.shop_revision = p_shop_revision
	result.offer_id = p_offer_id
	result.item_kind = p_item_kind
	result.item_id = p_item_id
	result.side = p_side
	result.quantity = p_quantity
	result.unit_price = p_unit_price
	result.total_price = p_unit_price * p_quantity
	result.currency_resource_id = p_currency_resource_id
	var buyer := GMP21Contract.target_ref(p_buyer_ref)
	var seller := GMP21Contract.target_ref(p_seller_ref)
	result.buyer_ref = buyer.value if buyer.ok else p_buyer_ref
	result.seller_ref = seller.value if seller.ok else p_seller_ref
	result.quote_id = result.derive_quote_id()
	return result

static func from_dict(value: Variant, json_boundary: bool = false) -> GMShopQuote:
	if not value is Dictionary or not GMP21Contract.exact(value, FIELDS):
		return null
	var source: Dictionary = value.duplicate(true)
	for field in ["schema_version", "quote_id", "shop_id", "offer_id", "item_kind", "item_id", "side", "currency_resource_id", "buyer_ref", "seller_ref"]:
		if field in ["buyer_ref", "seller_ref"]:
			if not source.get(field) is String and not source.get(field) is Dictionary: return null
		elif typeof(source.get(field)) != TYPE_STRING:
			return null
	if json_boundary:
		for field in ["shop_revision", "quantity", "unit_price", "total_price"]:
			if typeof(source.get(field)) == TYPE_FLOAT and is_finite(float(source[field])) and float(source[field]) == floor(float(source[field])): source[field] = int(source[field])
	for field in ["shop_revision", "quantity", "unit_price", "total_price"]:
		if typeof(source.get(field)) != TYPE_INT: return null
	var result := GMShopQuote.new()
	result.schema_version = str(source.schema_version)
	result.quote_id = str(source.quote_id)
	result.shop_id = str(source.shop_id)
	result.shop_revision = int(source.shop_revision)
	result.offer_id = str(source.offer_id)
	result.item_kind = str(source.item_kind)
	result.item_id = str(source.item_id)
	result.side = str(source.side)
	result.quantity = int(source.quantity)
	result.unit_price = int(source.unit_price)
	result.total_price = int(source.total_price)
	result.currency_resource_id = str(source.currency_resource_id)
	result.buyer_ref = GMStableData.clone(source.buyer_ref)
	result.seller_ref = GMStableData.clone(source.seller_ref)
	return result if result.validate().ok else null

static func from_json(text: String) -> Dictionary:
	var parsed := GMP21Contract.normalize_json(text, "shop.quote_json_invalid")
	if not parsed.ok: return parsed
	var quote := from_dict(parsed.value, true)
	return {"ok": true, "code": "shop.quote_decoded", "quote": quote} if quote != null else GMP21Contract.failure("shop.quote_json_invalid", "ShopQuote JSON未通过严格合同校验。")
