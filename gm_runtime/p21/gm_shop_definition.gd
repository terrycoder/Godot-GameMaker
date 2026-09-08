class_name GMShopDefinition
extends RefCounted

const SCHEMA_VERSION := GMP21Contract.SHOP_DEFINITION_SCHEMA_VERSION
const FIELDS := ["schema_version", "shop_id", "revision", "display_name_zh", "currency_resource_id", "offers"]
const OFFER_FIELDS := ["offer_id", "item_kind", "item_id", "buy_unit_price", "sell_unit_price"]

var schema_version := SCHEMA_VERSION
var shop_id := ""
var revision := 1
var display_name_zh := ""
var currency_resource_id := ""
var offers: Array[Dictionary] = []

func _init(p_shop_id: String = "", p_display_name_zh: String = "", p_currency_resource_id: String = "") -> void:
	shop_id = p_shop_id
	display_name_zh = p_display_name_zh
	currency_resource_id = p_currency_resource_id

func configure(p_shop_id: String, p_revision: int, p_currency_resource_id: String, p_offers: Array, p_display_name_zh: String = "P21商店") -> GMShopDefinition:
	shop_id = p_shop_id
	revision = p_revision
	display_name_zh = p_display_name_zh
	currency_resource_id = p_currency_resource_id
	offers.clear()
	for offer in p_offers:
		if offer is Dictionary:
			offers.append(offer.duplicate(true))
	return self

func validate() -> Dictionary:
	var value := to_dict()
	if not GMP21Contract.exact(value, FIELDS):
		return GMP21Contract.failure("shop.definition_shape_invalid", "ShopDefinition字段集合必须精确匹配。")
	if schema_version != SCHEMA_VERSION or not GMP21Contract.stable_id(shop_id) or not GMP21Contract.positive_integer(revision) or display_name_zh.strip_edges().is_empty() or not GMP21Contract.stable_id(currency_resource_id):
		return GMP21Contract.failure("shop.definition_identity_invalid", "ShopDefinition的版本、身份、修订号、中文名或货币资源无效。")
	if offers.is_empty():
		return GMP21Contract.failure("shop.definition_offers_missing", "ShopDefinition至少需要一个Offer。")
	var ids: Dictionary = {}
	for offer in offers:
		var checked := _validate_offer(offer)
		if not checked.ok:
			return checked
		if ids.has(offer.offer_id):
			return GMP21Contract.failure("shop.offer_duplicate", "ShopDefinition中的Offer ID不得重复。", {"offer_id": offer.offer_id})
		ids[offer.offer_id] = true
	return {"ok": true, "code": "shop.definition_valid", "value": value, "digest": digest()}

func get_offer(offer_id: String) -> Dictionary:
	for offer in offers:
		if str(offer.get("offer_id", "")) == offer_id:
			return offer.duplicate(true)
	return {}

func digest() -> String:
	return GMP21Contract.digest(to_dict())

func to_dict() -> Dictionary:
	var ordered: Array = []
	for offer in offers:
		ordered.append(offer.duplicate(true))
	ordered.sort_custom(func(left: Dictionary, right: Dictionary): return str(left.get("offer_id", "")) < str(right.get("offer_id", "")))
	return {"schema_version": schema_version, "shop_id": shop_id, "revision": revision, "display_name_zh": display_name_zh, "currency_resource_id": currency_resource_id, "offers": ordered}

func to_json() -> String:
	return JSON.stringify(GMStableData.persistence_canonical(to_dict()), "", false, true)

static func from_dict(value: Variant, json_boundary: bool = false) -> GMShopDefinition:
	if not value is Dictionary or not GMP21Contract.exact(value, FIELDS):
		return null
	if typeof(value.get("schema_version")) != TYPE_STRING or typeof(value.get("shop_id")) != TYPE_STRING or not _integer_value(value.get("revision"), json_boundary) or typeof(value.get("display_name_zh")) != TYPE_STRING or typeof(value.get("currency_resource_id")) != TYPE_STRING or not value.get("offers") is Array:
		return null
	var result := GMShopDefinition.new()
	result.schema_version = str(value.schema_version)
	result.shop_id = str(value.shop_id)
	result.revision = int(value.revision)
	result.display_name_zh = str(value.display_name_zh)
	result.currency_resource_id = str(value.currency_resource_id)
	for raw_offer in value.offers:
		if not raw_offer is Dictionary or not GMP21Contract.exact(raw_offer, OFFER_FIELDS):
			return null
		var offer: Dictionary = raw_offer.duplicate(true)
		if json_boundary:
			for field in ["buy_unit_price", "sell_unit_price"]:
				if typeof(offer.get(field)) == TYPE_FLOAT and is_finite(float(offer[field])) and float(offer[field]) == floor(float(offer[field])): offer[field] = int(offer[field])
		result.offers.append(offer)
	return result if result.validate().ok else null

static func from_json(text: String) -> Dictionary:
	var parsed := GMP21Contract.normalize_json(text, "shop.definition_json_invalid")
	if not parsed.ok: return parsed
	var definition := from_dict(parsed.value, true)
	return {"ok": true, "code": "shop.definition_decoded", "definition": definition} if definition != null else GMP21Contract.failure("shop.definition_json_invalid", "ShopDefinition JSON未通过严格合同校验。")

static func _validate_offer(value: Variant) -> Dictionary:
	if not value is Dictionary or not GMP21Contract.exact(value, OFFER_FIELDS):
		return GMP21Contract.failure("shop.offer_shape_invalid", "Shop Offer字段集合必须精确匹配。")
	if typeof(value.offer_id) != TYPE_STRING or not GMP21Contract.stable_id(value.offer_id) or typeof(value.item_kind) != TYPE_STRING or value.item_kind not in ["lot", "instance"] or typeof(value.item_id) != TYPE_STRING or not GMP21Contract.stable_id(value.item_id) or not GMP21Contract.nonnegative_integer(value.buy_unit_price) or not GMP21Contract.nonnegative_integer(value.sell_unit_price):
		return GMP21Contract.failure("shop.offer_invalid", "Shop Offer身份、物品类型或整数价格无效。")
	return GMP21Contract.pure(value, "$.offer")

static func _integer_value(value: Variant, json_boundary: bool) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) > 0 and int(value) <= GMStableData.JSON_SAFE_INTEGER_MAX
	return json_boundary and typeof(value) == TYPE_FLOAT and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) > 0.0 and float(value) <= float(GMStableData.JSON_SAFE_INTEGER_MAX)
