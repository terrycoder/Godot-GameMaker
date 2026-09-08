class_name GMInventoryContainer
extends RefCounted

## Shared container model for characters, buildings, warehouses and world drops.

const SCHEMA_VERSION := "gm.inventory_container.v1"

var container_id: String = ""
var container_kind: String = "generic"
var slot_limit: int = -1
var weight_limit: float = -1.0
var entries: Array[Dictionary] = []

func configure(p_container_id: String, p_container_kind: String, p_slot_limit: int = -1, p_weight_limit: float = -1.0) -> GMInventoryContainer:
	container_id = p_container_id.strip_edges()
	container_kind = p_container_kind.strip_edges()
	slot_limit = p_slot_limit
	weight_limit = p_weight_limit
	entries = []
	return self

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not container_id.begins_with("gm.container."): errors.append("InventoryContainer ID 必须使用 gm.container.*。")
	if container_kind.is_empty(): errors.append("InventoryContainer 必须声明通用容器类型。")
	if slot_limit == 0 or slot_limit < -1: errors.append("容器槽位上限必须为-1或正数。")
	if weight_limit == 0.0 or weight_limit < -1.0: errors.append("容器重量上限必须为-1或正数。")
	var seen: Dictionary = {}
	for entry in entries:
		if not entry is Dictionary: errors.append("InventoryContainer entry 必须是对象。"); continue
		var kind := str(entry.get("item_kind", ""))
		var item_id := str(entry.get("item_id", ""))
		var quantity := int(entry.get("quantity", 0))
		var key := _entry_key(kind, item_id)
		if not ["lot", "instance"].has(kind) or item_id.is_empty(): errors.append("InventoryContainer entry 物品引用无效：%s" % key)
		if quantity <= 0: errors.append("InventoryContainer entry 数量必须大于0：%s" % key)
		if seen.has(key): errors.append("InventoryContainer 不得重复记录物品引用：%s" % key)
		seen[key] = true
	var stable := GMStableData.validate(to_dict())
	if not stable.ok: errors.append_array(stable.errors)
	return {"ok": errors.is_empty(), "code": "inventory_container.valid" if errors.is_empty() else "inventory_container.invalid", "errors": errors}

func quantity_for(item_kind: String, item_id: String) -> int:
	var key := _entry_key(item_kind, item_id)
	for entry in entries:
		if _entry_key(str(entry.get("item_kind", "")), str(entry.get("item_id", ""))) == key: return int(entry.get("quantity", 0))
	return 0

func has_item(item_kind: String, item_id: String) -> bool:
	return quantity_for(item_kind, item_id) > 0

func slot_count() -> int:
	return entries.size()

func add_quantity(item_kind: String, item_id: String, quantity: int, entry_id: String = "") -> Dictionary:
	if quantity <= 0: return {"ok": false, "code": "inventory_container.quantity_invalid", "reason_zh": "加入容器的数量必须大于0。"}
	var key := _entry_key(item_kind, item_id)
	for entry in entries:
		if _entry_key(str(entry.get("item_kind", "")), str(entry.get("item_id", ""))) == key:
			entry["quantity"] = int(entry.get("quantity", 0)) + quantity
			return {"ok": true, "slot_delta": 0, "quantity": int(entry["quantity"])}
	if slot_limit >= 0 and entries.size() >= slot_limit:
		return {"ok": false, "code": "inventory.capacity_full", "reason_zh": "目标容器槽位已满。", "slot_limit": slot_limit}
	entries.append({"entry_id": entry_id if not entry_id.is_empty() else "gm.entry.%s" % _slug(key), "item_kind": item_kind, "item_id": item_id, "quantity": quantity})
	_sort_entries()
	return {"ok": true, "slot_delta": 1, "quantity": quantity}

func remove_quantity(item_kind: String, item_id: String, quantity: int) -> Dictionary:
	if quantity <= 0: return {"ok": false, "code": "inventory_container.quantity_invalid", "reason_zh": "移出容器的数量必须大于0。"}
	var key := _entry_key(item_kind, item_id)
	for index in entries.size():
		var entry := entries[index]
		if _entry_key(str(entry.get("item_kind", "")), str(entry.get("item_id", ""))) != key: continue
		var current := int(entry.get("quantity", 0))
		if current < quantity: return {"ok": false, "code": "inventory.source_insufficient", "reason_zh": "源容器数量不足。", "available": current, "requested": quantity}
		if current == quantity: entries.remove_at(index)
		else: entry["quantity"] = current - quantity
		return {"ok": true, "slot_delta": -1 if current == quantity else 0, "quantity": current - quantity}
	return {"ok": false, "code": "inventory.item_missing", "reason_zh": "源容器找不到该物品。", "item_kind": item_kind, "item_id": item_id}

func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "container_id": container_id, "container_kind": container_kind, "slot_limit": slot_limit, "weight_limit": weight_limit, "entries": entries.duplicate(true)}

static func from_dict(value: Dictionary) -> GMInventoryContainer:
	var result := GMInventoryContainer.new()
	result.container_id = str(value.get("container_id", value.get("id", "")))
	result.container_kind = str(value.get("container_kind", value.get("inventory_type", "generic")))
	var capacity: Dictionary = value.get("capacity", {}) if value.get("capacity", {}) is Dictionary else {}
	result.slot_limit = int(value.get("slot_limit", capacity.get("slot_limit", -1)))
	result.weight_limit = float(value.get("weight_limit", capacity.get("weight_limit", -1.0) if capacity.get("weight_limit", -1.0) != null else -1.0))
	result.entries = []
	var raw_entries: Array = value.get("entries", []) if value.get("entries", []) is Array else []
	for raw in raw_entries:
		if not raw is Dictionary: continue
		result.entries.append({"entry_id": str(raw.get("entry_id", "")), "item_kind": str(raw.get("item_kind", raw.get("kind", ""))), "item_id": str(raw.get("item_id", raw.get("ref", ""))), "quantity": int(raw.get("quantity", 0))})
	result._sort_entries()
	return result

static func _entry_key(item_kind: String, item_id: String) -> String:
	return "%s:%s" % [item_kind, item_id]

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var result := ""
	for index in raw.length():
		var code := raw.unicode_at(index)
		result += raw.substr(index, 1) if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95 or code == 45 else "_"
	return result

func _sort_entries() -> void:
	entries.sort_custom(func(left: Dictionary, right: Dictionary):
		return "%s:%s" % [str(left.get("item_kind", "")), str(left.get("item_id", ""))] < "%s:%s" % [str(right.get("item_kind", "")), str(right.get("item_id", ""))]
	)
