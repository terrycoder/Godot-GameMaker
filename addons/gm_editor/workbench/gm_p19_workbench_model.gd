@tool
class_name GMP19WorkbenchModel
extends RefCounted

## Chinese-first editor model for P19. It authors neutral data and requests;
## it deliberately has no Store reference and cannot mutate runtime state.

const CATALOG := preload("res://gm_runtime/p19/gm_p19_recipe_catalog.gd")
const REQUEST_ADAPTER := preload("res://gm_runtime/p19/gm_p19_request_adapter.gd")
const RESULT_SCHEMA := "gm.p19.workbench_operation.v1"
const PREFLIGHT_SCHEMA := "gm.p19.workbench_preflight.v1"

func new_neutral_item(item_id: String, display_name_zh: String, tags: Array = [], stackable: bool = true, max_stack: int = 99) -> Dictionary:
        return {
                "kind": "item",
                "item_id": item_id.strip_edges(),
                "display_name_zh": display_name_zh,
                "tags": tags.duplicate(true),
                "stackable": stackable,
                "max_stack": max_stack,
        }

func new_numeric_resource(resource_id: String, display_name_zh: String, unit_id: String = "gm.unit.whole", minimum_value: int = 0, maximum_capacity: int = -1) -> Dictionary:
        return {
                "kind": "numeric_resource",
                "resource_id": resource_id.strip_edges(),
                "display_name_zh": display_name_zh,
                "unit_id": unit_id.strip_edges(),
                "minimum_value": minimum_value,
                "maximum_capacity": maximum_capacity,
        }

func new_container(container_id: String, container_kind: String = "storage", slot_limit: int = -1, weight_limit: int = -1) -> Dictionary:
        return {
                "kind": "container",
                "container_id": container_id.strip_edges(),
                "container_kind": container_kind,
                "slot_limit": slot_limit,
                "weight_limit": weight_limit,
        }

func new_transaction_recipe(recipe_id: String, display_name_zh: String, operation: String, participants: Array = [], inputs: Array = [], outputs: Array = [], metadata: Dictionary = {}) -> Dictionary:
        return {
                "schema_version": CATALOG.SCHEMA_VERSION,
                "recipe_id": recipe_id.strip_edges(),
                "display_name_zh": display_name_zh,
                "operation": operation,
                "participants": participants.duplicate(true),
                "inputs": inputs.duplicate(true),
                "outputs": outputs.duplicate(true),
                "metadata": metadata.duplicate(true),
        }

func preflight_summary(recipe: Variant) -> Dictionary:
        var errors: Array[String] = []
        var data: Dictionary = recipe if recipe is Dictionary else {}
        if not recipe is Dictionary: errors.append("预检阻断：交易配方必须是字典数据。")
        var validation := CATALOG.new().validate_recipe(data)
        if not validation.ok: errors.append_array(validation.errors)
        var participants: Array = data.get("participants", []) if data.get("participants", []) is Array else []
        if participants.is_empty(): errors.append("预检阻断：交易必须声明至少一个参与者。")
        var inputs: Array = data.get("inputs", []) if data.get("inputs", []) is Array else []
        var outputs: Array = data.get("outputs", []) if data.get("outputs", []) is Array else []
        var ok := errors.is_empty()
        return {
                "schema_version": PREFLIGHT_SCHEMA,
                "ok": ok,
                "state_zh": "可提交" if ok else "已阻断",
                "block_reason_zh": "" if ok else "; ".join(errors),
                "errors_zh": errors,
                "participants": participants.duplicate(true),
                "inputs": inputs.duplicate(true),
                "outputs": outputs.duplicate(true),
                "commit_state_zh": "等待现有事务协调器提交" if ok else "不可提交",
                "request_only": true,
                "direct_store_write": false,
        }

func build_request_result(host: GMAbilitySystemHost, recipe: Variant, source_id: String, idempotency_key: String) -> Dictionary:
        var preflight := preflight_summary(recipe)
        if not preflight.ok:
                return {"schema_version":RESULT_SCHEMA,"ok":false,"code":"p19.workbench.preflight_blocked","preflight":preflight,"request":null}
        var data: Dictionary = recipe.duplicate(true)
        var request := REQUEST_ADAPTER.build(host, str(data.get("operation", "")), data, source_id, idempotency_key)
        return {"schema_version":RESULT_SCHEMA,"ok":true,"code":"p19.workbench.request_ready","preflight":preflight,"request":request}

func apply_recipe_catalog(catalog: Variant, next_recipes: Array, editor_undo_redo: Object = null, save_path: String = "") -> Dictionary:
        if catalog == null:
                return {"schema_version":RESULT_SCHEMA,"ok":false,"code":"p19.workbench.catalog_missing","error_zh":"P19 配方目录不存在。"}
        return apply_catalog_state(catalog, catalog.neutral_items.duplicate(true), catalog.numeric_resources.duplicate(true), catalog.containers.duplicate(true), next_recipes, editor_undo_redo, save_path)

func apply_catalog_state(catalog: Variant, next_items: Array, next_resources: Array, next_containers: Array, next_recipes: Array, editor_undo_redo: Object = null, save_path: String = "") -> Dictionary:
        if catalog == null:
                return {"schema_version":RESULT_SCHEMA,"ok":false,"code":"p19.workbench.catalog_missing","error_zh":"P19 配方目录不存在。"}
        var candidate = CATALOG.new().configure(catalog.catalog_id, catalog.display_name_zh, next_recipes, next_items, next_resources, next_containers)
        candidate.revision = catalog.revision + 1
        var validation := candidate.validate()
        if not validation.ok:
                return {"schema_version":RESULT_SCHEMA,"ok":false,"code":"p19.workbench.validation_blocked","errors_zh":validation.errors,"catalog":catalog.to_dict()}
        var before: Dictionary = catalog.to_dict()
        var after := candidate.to_dict()
        if editor_undo_redo != null:
                editor_undo_redo.create_action("P19配方目录：保存编辑")
                editor_undo_redo.add_do_method(Callable(self, "_apply_catalog_snapshot").bind(catalog, after, save_path))
                editor_undo_redo.add_undo_method(Callable(self, "_apply_catalog_snapshot").bind(catalog, before, save_path))
                editor_undo_redo.commit_action()
        else:
                _apply_catalog_snapshot(catalog, after, save_path)
        return {"schema_version":RESULT_SCHEMA,"ok":true,"code":"p19.workbench.catalog_saved","before":before,"after":after,"save_path":save_path,"undo_redo":editor_undo_redo != null,"direct_store_write":false}

func reopen_catalog(path: String) -> Dictionary:
        if path.strip_edges().is_empty():
                return {"schema_version":RESULT_SCHEMA,"ok":false,"code":"p19.workbench.catalog_path_missing","error_zh":"P19 配方目录重开路径为空。"}
        var loaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
        if loaded == null or not loaded is Resource or not loaded.has_method("validate"):
                return {"schema_version":RESULT_SCHEMA,"ok":false,"code":"p19.workbench.catalog_reopen_failed","error_zh":"P19 配方目录重开失败，资源类型不匹配。"}
        var catalog: Variant = loaded
        var validation: Dictionary = catalog.validate()
        if not validation.ok:
                return {"schema_version":RESULT_SCHEMA,"ok":false,"code":"p19.workbench.catalog_invalid","errors_zh":validation.errors}
        return {"schema_version":RESULT_SCHEMA,"ok":true,"code":"p19.workbench.catalog_reopened","catalog":catalog,"catalog_data":catalog.to_dict()}

func _apply_catalog_snapshot(catalog: Variant, snapshot: Dictionary, save_path: String = "") -> void:
        catalog.catalog_id = str(snapshot.get("catalog_id", catalog.catalog_id))
        catalog.display_name_zh = str(snapshot.get("display_name_zh", catalog.display_name_zh))
        catalog.revision = int(snapshot.get("revision", catalog.revision))
        catalog.neutral_items.clear()
        var raw_items = snapshot.get("neutral_items", [])
        if raw_items is Array:
                for item in raw_items:
                        if item is Dictionary: catalog.neutral_items.append(item.duplicate(true))
        catalog.numeric_resources.clear()
        var raw_resources = snapshot.get("numeric_resources", [])
        if raw_resources is Array:
                for resource in raw_resources:
                        if resource is Dictionary: catalog.numeric_resources.append(resource.duplicate(true))
        catalog.containers.clear()
        var raw_containers = snapshot.get("containers", [])
        if raw_containers is Array:
                for container in raw_containers:
                        if container is Dictionary: catalog.containers.append(container.duplicate(true))
        catalog.recipes.clear()
        var raw_recipes = snapshot.get("recipes", [])
        if raw_recipes is Array:
                for recipe in raw_recipes:
                        if recipe is Dictionary: catalog.recipes.append(recipe.duplicate(true))
        if not save_path.is_empty(): ResourceSaver.save(catalog, save_path)
