@tool
class_name GMP19RecipeCatalog
extends Resource

## Editor-authored P19 neutral data. This catalog contains definitions and
## recipes only; runtime Store state is never embedded in it.

const SCHEMA_VERSION := "gm.p19.recipe_catalog.v1"
const RECIPE_FIELDS := ["schema_version", "recipe_id", "display_name_zh", "operation", "participants", "inputs", "outputs", "metadata"]
const OPERATIONS := ["transfer", "equip", "use", "consume", "drop", "cost", "reward", "grant", "convert"]

@export var catalog_id: String = "gm.p19.catalog.default"
@export var display_name_zh: String = "P19 交易配方目录"
@export var revision: int = 0
@export var neutral_items: Array[Dictionary] = []
@export var numeric_resources: Array[Dictionary] = []
@export var containers: Array[Dictionary] = []
@export var recipes: Array[Dictionary] = []

func configure(p_catalog_id: String, p_display_name_zh: String = "P19 交易配方目录", p_recipes: Array = [], p_neutral_items: Array = [], p_numeric_resources: Array = [], p_containers: Array = []) -> GMP19RecipeCatalog:
        catalog_id = p_catalog_id.strip_edges()
        display_name_zh = p_display_name_zh
        neutral_items.clear()
        numeric_resources.clear()
        containers.clear()
        recipes.clear()
        for item in p_neutral_items:
                if item is Dictionary: neutral_items.append(item.duplicate(true))
        for resource in p_numeric_resources:
                if resource is Dictionary: numeric_resources.append(resource.duplicate(true))
        for container in p_containers:
                if container is Dictionary: containers.append(container.duplicate(true))
        for recipe in p_recipes:
                if recipe is Dictionary: recipes.append(recipe.duplicate(true))
        revision = 0
        return self

func validate() -> Dictionary:
        var errors: Array[String] = []
        if not _stable_id(catalog_id) or not catalog_id.begins_with("gm.p19.catalog."):
                errors.append("P19 配方目录 ID 必须使用 gm.p19.catalog.* 稳定身份。")
        if display_name_zh.strip_edges().is_empty():
                errors.append("P19 配方目录必须有中文名称。")
        if revision < 0:
                errors.append("P19 配方目录 revision 不能为负数。")
        _validate_definitions(neutral_items, "neutral_items", "item_id", "gm.item.", errors)
        _validate_definitions(numeric_resources, "numeric_resources", "resource_id", "gm.resource.", errors)
        _validate_definitions(containers, "containers", "container_id", "gm.container.", errors)
        var seen := {}
        for recipe in recipes:
                if not recipe is Dictionary:
                        errors.append("P19 配方必须是纯字典数据。")
                        continue
                var checked := validate_recipe(recipe)
                if not checked.ok: errors.append_array(checked.errors)
                var recipe_id := str(recipe.get("recipe_id", ""))
                if seen.has(recipe_id): errors.append("P19 配方 ID 重复：%s" % recipe_id)
                seen[recipe_id] = true
        return {"ok": errors.is_empty(), "code": "p19.recipe_catalog.valid" if errors.is_empty() else "p19.recipe_catalog.invalid", "errors": errors}

func validate_recipe(recipe: Variant) -> Dictionary:
        var errors: Array[String] = []
        if not recipe is Dictionary:
                return {"ok":false,"code":"p19.recipe.invalid_type","errors":["P19 交易配方必须是字典数据。"]}
        var data: Dictionary = recipe
        for raw_key in data.keys():
                if not RECIPE_FIELDS.has(str(raw_key)):
                        errors.append("P19 配方包含未知字段：%s" % str(raw_key))
        var recipe_id := str(data.get("recipe_id", ""))
        if not _stable_id(recipe_id) or not recipe_id.begins_with("gm.recipe."):
                errors.append("P19 配方 ID 必须使用 gm.recipe.* 稳定身份。")
        if str(data.get("display_name_zh", "")).strip_edges().is_empty():
                errors.append("P19 配方必须有中文名称。")
        if not OPERATIONS.has(str(data.get("operation", ""))):
                errors.append("P19 配方 operation 不是受支持的统一事务操作。")
        _validate_string_array(data.get("participants", []), "participants", errors)
        _validate_rows(data.get("inputs", []), "inputs", errors)
        _validate_rows(data.get("outputs", []), "outputs", errors)
        return {"ok": errors.is_empty(), "code": "p19.recipe.valid" if errors.is_empty() else "p19.recipe.invalid", "errors": errors}

func add_or_replace(recipe: Dictionary) -> Dictionary:
        var checked := validate_recipe(recipe)
        if not checked.ok: return {"ok":false,"code":"p19.recipe.invalid","errors":checked.errors}
        var recipe_id := str(recipe.get("recipe_id", ""))
        var replaced := false
        for index in recipes.size():
                if str(recipes[index].get("recipe_id", "")) == recipe_id:
                        recipes[index] = recipe.duplicate(true)
                        replaced = true
                        break
        if not replaced: recipes.append(recipe.duplicate(true))
        revision += 1
        return {"ok":true,"code":"p19.recipe.replaced" if replaced else "p19.recipe.added","recipe_id":recipe_id,"revision":revision}

func remove(recipe_id: String) -> Dictionary:
        for index in recipes.size():
                if str(recipes[index].get("recipe_id", "")) == recipe_id:
                        recipes.remove_at(index)
                        revision += 1
                        return {"ok":true,"code":"p19.recipe.removed","recipe_id":recipe_id,"revision":revision}
        return {"ok":false,"code":"p19.recipe.missing","errors":["找不到要移除的 P19 配方：%s" % recipe_id]}

func to_dict() -> Dictionary:
        var copied: Array = []
        for recipe in recipes: copied.append(recipe.duplicate(true))
        return {
                "schema_version": SCHEMA_VERSION,
                "catalog_id": catalog_id,
                "display_name_zh": display_name_zh,
                "revision": revision,
                "neutral_items": _copy_rows(neutral_items),
                "numeric_resources": _copy_rows(numeric_resources),
                "containers": _copy_rows(containers),
                "recipes": copied,
        }

static func from_dict(value: Dictionary):
        var result = load("res://gm_runtime/p19/gm_p19_recipe_catalog.gd").new()
        result.catalog_id = str(value.get("catalog_id", "gm.p19.catalog.default"))
        result.display_name_zh = str(value.get("display_name_zh", "P19 交易配方目录"))
        result.revision = int(value.get("revision", 0))
        var raw_items = value.get("neutral_items", [])
        if raw_items is Array:
                for item in raw_items:
                        if item is Dictionary: result.neutral_items.append(item.duplicate(true))
        var raw_resources = value.get("numeric_resources", [])
        if raw_resources is Array:
                for resource in raw_resources:
                        if resource is Dictionary: result.numeric_resources.append(resource.duplicate(true))
        var raw_containers = value.get("containers", [])
        if raw_containers is Array:
                for container in raw_containers:
                        if container is Dictionary: result.containers.append(container.duplicate(true))
        var raw_recipes = value.get("recipes", [])
        if raw_recipes is Array:
                for recipe in raw_recipes:
                        if recipe is Dictionary: result.recipes.append(recipe.duplicate(true))
        return result

static func validate_recipe_rows(value: Variant) -> Dictionary:
        var errors: Array[String] = []
        _validate_rows(value, "rows", errors)
        return {"ok": errors.is_empty(), "errors": errors}

static func _validate_definitions(value: Variant, field: String, id_field: String, prefix: String, errors: Array[String]) -> void:
        if not value is Array:
                errors.append("P19 目录 %s 必须是数组。" % field)
                return
        var seen := {}
        for row in value:
                if not row is Dictionary:
                        errors.append("P19 目录 %s 只能包含字典数据。" % field)
                        continue
                var identifier := str(row.get(id_field, ""))
                if not _stable_id(identifier) or not identifier.begins_with(prefix):
                        errors.append("P19 目录 %s 的 %s 必须使用 %s* 稳定身份。" % [field, id_field, prefix])
                if seen.has(identifier): errors.append("P19 目录 %s ID 重复：%s" % [field, identifier])
                seen[identifier] = true

static func _copy_rows(value: Array[Dictionary]) -> Array:
        var result: Array = []
        for row in value: result.append(row.duplicate(true))
        return result

static func _validate_string_array(value: Variant, field: String, errors: Array[String]) -> void:
        if not value is Array:
                errors.append("P19 配方 %s 必须是字符串数组。" % field)
                return
        for item in value:
                if not item is String or str(item).strip_edges().is_empty():
                        errors.append("P19 配方 %s 只能包含非空稳定 ID。" % field)

static func _validate_rows(value: Variant, field: String, errors: Array[String]) -> void:
        if not value is Array:
                errors.append("P19 配方 %s 必须是数组。" % field)
                return
        for row in value:
                if not row is Dictionary:
                        errors.append("P19 配方 %s 只能包含字典行。" % field)
                        continue
                var data: Dictionary = row
                var has_resource := data.has("resource_id") or data.has("account_id") or data.has("amount")
                var has_item := data.has("item_id") or data.has("container_id") or data.has("quantity")
                if not has_resource and not has_item:
                        errors.append("P19 配方 %s 行必须声明 item/container 或 resource/account 稳定身份。" % field)
                if data.has("resource_id") and not _stable_id(str(data.get("resource_id"))) :
                        errors.append("P19 配方 %s 的 resource_id 不是稳定 ID。" % field)
                if data.has("account_id") and not _stable_id(str(data.get("account_id"))) :
                        errors.append("P19 配方 %s 的 account_id 不是稳定 ID。" % field)
                if data.has("item_id") and not _stable_id(str(data.get("item_id"))) :
                        errors.append("P19 配方 %s 的 item_id 不是稳定 ID。" % field)
                if data.has("container_id") and not _stable_id(str(data.get("container_id"))) :
                        errors.append("P19 配方 %s 的 container_id 不是稳定 ID。" % field)
                for amount_field in ["amount", "quantity"]:
                        if data.has(amount_field) and (data.get(amount_field) is bool or not data.get(amount_field) is int or int(data.get(amount_field)) <= 0):
                                errors.append("P19 配方 %s 的 %s 必须是正整数最小单位。" % [field, amount_field])

static func _stable_id(value: String) -> bool:
        return not value.strip_edges().is_empty() and not value.contains(" ") and not value.contains("\t") and not value.contains("res://") and not value.contains("user://") and not value.begins_with("/")
