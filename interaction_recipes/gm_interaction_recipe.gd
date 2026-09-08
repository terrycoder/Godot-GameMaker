@tool
class_name GMInteractionRecipe
extends Resource

## 配方只声明能力、前置条件与成功状态；真实动作一律由 GMAbilitySystemHost 激活。

const SCHEMA := "gm.interaction.recipe.v1"
const KINDS := ["door", "chest", "pickup", "mechanism", "destructible"]

@export var recipe_id: String = ""
@export_enum("door", "chest", "pickup", "mechanism", "destructible") var interaction_kind: String = "chest"
@export var ability_id: String = ""
@export var required_item_id: String = ""
@export var required_state: Dictionary = {}
@export var blocked_state: Dictionary = {}
@export var success_state_patch: Dictionary = {}
@export var required_payload_keys: PackedStringArray = PackedStringArray()
@export var missing_content_fields: PackedStringArray = PackedStringArray()
@export var event_tag: String = "event.object.interacted"
@export var cue_id: String = ""
@export var schema_version: String = SCHEMA

func validate_recipe() -> Dictionary:
	if recipe_id.strip_edges().is_empty(): return _failure("recipe.id_missing", "交互配方缺少稳定ID。")
	if interaction_kind not in KINDS: return _failure("recipe.kind_invalid", "交互配方类型不受支持。")
	if ability_id.strip_edges().is_empty(): return _failure("recipe.ability_missing", "交互配方缺少统一GAS能力ID。")
	if success_state_patch.is_empty(): return _failure("recipe.state_patch_missing", "交互配方缺少成功状态定义。")
	return {"ok": true}

func preflight(object_state: Dictionary, context: Dictionary) -> Dictionary:
	var recipe_check := validate_recipe()
	if not recipe_check.ok: return recipe_check
	for field in missing_content_fields:
		if not context.has(str(field)) or str(context.get(str(field), "")).strip_edges().is_empty():
			return _failure("interaction.content_missing", "交互所需内容缺失：%s" % field, {"field": str(field)})
	for key in required_payload_keys:
		if not context.has(str(key)): return _failure("interaction.payload_missing", "交互参数缺失：%s" % key, {"field": str(key)})
	for key in required_state:
		if object_state.get(key, null) != required_state[key]: return _failure("interaction.required_state_missing", "对象状态不满足交互条件：%s" % key, {"field": str(key)})
	for key in blocked_state:
		if object_state.get(key, null) == blocked_state[key]: return _failure("interaction.already_completed", "对象已经处于不可重复交互状态：%s" % key, {"field": str(key)})
	if not required_item_id.is_empty():
		var items: Array = context.get("item_ids", [])
		if not items.has(required_item_id): return _failure("interaction.key_missing", "缺少交互所需物品：%s" % required_item_id, {"required_item_id": required_item_id})
	return {"ok": true}

func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": message, "details": details}
