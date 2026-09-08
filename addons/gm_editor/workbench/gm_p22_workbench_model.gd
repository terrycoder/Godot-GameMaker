class_name GMP22WorkbenchModel
extends RefCounted

## Chinese-first P22 authoring model. It edits one CombatCatalog Resource and
## only produces typed requests/preview values; it has no runtime Store access.

const CATALOG := preload("res://gm_runtime/combat/gm_combat_catalog.gd")
const ATTACK := preload("res://gm_runtime/combat/gm_combat_attack_definition.gd")
const WEAPON := preload("res://gm_runtime/combat/gm_combat_weapon_definition.gd")
const PROJECTILE := preload("res://gm_runtime/combat/gm_combat_projectile_definition.gd")
const HIT_SPEC := preload("res://gm_runtime/combat/gm_combat_hit_spec.gd")
const REQUEST := preload("res://gm_runtime/combat/gm_combat_request.gd")
const RESULT := preload("res://gm_runtime/combat/gm_combat_result.gd")
const RESULT_SCHEMA := "gm.p22.workbench_operation.v1"
const PREFLIGHT_SCHEMA := "gm.p22.workbench_preflight.v1"

func new_neutral_attack(attack_id: String, display_name_zh: String, attack_kind: String = "melee", operation: String = "damage", magnitude: float = 10.0, range: float = 1.0, cooldown_seconds: float = 0.0, weapon_ref: String = "", projectile_ref: String = "", effect_ref: String = "", tags: Array = [], metadata: Dictionary = {}) -> Dictionary:
        return ATTACK.new().configure(attack_id, display_name_zh, attack_kind, operation, magnitude, range, cooldown_seconds, weapon_ref, projectile_ref, effect_ref, tags, metadata).to_native()

func new_neutral_weapon(weapon_id: String, display_name_zh: String, item_ref: String, attack_ref: String, projectile_ref: String = "", ammo_item_ref: String = "", resource_costs: Array = [], tags: Array = [], metadata: Dictionary = {}) -> Dictionary:
        return WEAPON.new().configure(weapon_id, display_name_zh, item_ref, attack_ref, projectile_ref, ammo_item_ref, resource_costs, tags, metadata).to_native()

func new_neutral_projectile(projectile_id: String, display_name_zh: String, speed: float = 12.0, lifetime_seconds: float = 2.0, hit_radius: float = 0.1, max_hits: int = 1, tags: Array = [], metadata: Dictionary = {}) -> Dictionary:
        return PROJECTILE.new().configure(projectile_id, display_name_zh, speed, lifetime_seconds, hit_radius, max_hits, tags, metadata).to_native()

func new_hit_spec(hit_id: String, source_id: String, target_id: String, query_kind: String = "direct", direction: Variant = {"x": 1.0, "y": 0.0}, distance: float = 0.0, max_distance: float = 0.0, shape_radius: float = 0.0, metadata: Dictionary = {}) -> Dictionary:
        return HIT_SPEC.new().configure(hit_id, query_kind, source_id, target_id, direction, distance, max_distance, shape_radius, metadata).to_native()

func new_combat_request(request_id: String, idempotency_key: String, mode: String, source_id: String, target_id: String, ability_id: String, attack_id: String, hit_spec: Dictionary, weapon_id: String = "", projectile_id: String = "", p19_intent: Dictionary = {}, metadata: Dictionary = {}) -> Dictionary:
        var hit_result := HIT_SPEC.from_native(hit_spec)
        if not hit_result.ok: return {"schema_version": RESULT_SCHEMA, "ok": false, "code": "p22.workbench.hit_invalid", "reason_zh": str(hit_result.get("reason_zh", "HitSpec 无效。")), "direct_store_write": false}
        return REQUEST.new().configure(request_id, idempotency_key, mode, source_id, target_id, ability_id, attack_id, hit_result.value, weapon_id, projectile_id, p19_intent, metadata).to_native()

func preflight_summary(catalog: Variant) -> Dictionary:
        var errors: Array[String] = []
        if catalog == null or not catalog is Resource:
                errors.append("P22 目录必须是同一份 Resource。")
        else:
                var checked: Dictionary = catalog.validate() if catalog.has_method("validate") else {"ok": false, "errors": ["P22 目录缺少 validate 接口。"]}
                if not checked.ok: errors.append_array(checked.get("errors", []))
        return {"schema_version": PREFLIGHT_SCHEMA, "ok": errors.is_empty(), "state_zh": "可提交" if errors.is_empty() else "已阻断", "block_reason_zh": "" if errors.is_empty() else "; ".join(errors), "errors_zh": errors, "commit_state_zh": "等待现有 DomainTransaction 提交" if errors.is_empty() else "不可提交", "request_only": true, "direct_store_write": false}

func build_preview(resolver, request_data: Variant, query_context: Dictionary = {}) -> Dictionary:
        var preflight := _parse_request(request_data)
        if not preflight.ok: return _failure("p22.workbench.request_invalid", str(preflight.get("reason_zh", "CombatRequest 无效。")), {"request": request_data})
        if resolver == null: return _failure("p22.workbench.resolver_missing", "P22 CombatResolver 尚未连接。")
        var result = resolver.resolve(preflight.value, query_context)
        return {"schema_version": RESULT_SCHEMA, "ok": result.status == "committed", "code": result.code, "reason_zh": result.reason_zh, "result": result.to_native(), "request_only": true, "direct_store_write": false}

func apply_catalog_state(catalog: Variant, next_attacks: Array, next_weapons: Array, next_projectiles: Array, editor_undo_redo: Object = null, save_path: String = "") -> Dictionary:
        if catalog == null or not catalog is Resource:
                return _failure("p22.workbench.catalog_missing", "P22 战斗定义目录 Resource 不存在。")
        var candidate = CATALOG.new().configure(str(catalog.catalog_id), str(catalog.display_name_zh), next_attacks, next_weapons, next_projectiles)
        candidate.revision = int(catalog.revision) + 1
        var validation: Dictionary = candidate.validate()
        if not validation.ok:
                return _failure("p22.workbench.validation_blocked", "P22 定义编辑已阻断，原 Resource 未改变。", {"errors_zh": validation.errors, "catalog": catalog.to_native()})
        var before: Dictionary = catalog.to_native()
        var after: Dictionary = candidate.to_native()
        if editor_undo_redo != null:
                if str(editor_undo_redo.get_class()) == "EditorUndoRedoManager":
                        editor_undo_redo.create_action("P22战斗定义目录：保存编辑", UndoRedo.MERGE_DISABLE, catalog)
                else:
                        editor_undo_redo.create_action("P22战斗定义目录：保存编辑")
                _add_editor_action_methods(editor_undo_redo, catalog, after, before, save_path)
                editor_undo_redo.commit_action()
        else:
                var applied := _apply_catalog_snapshot(catalog, after, save_path)
                if not applied.ok: return applied
        return {"schema_version": RESULT_SCHEMA, "ok": true, "code": "p22.workbench.catalog_saved", "before": before, "after": after, "save_path": save_path, "same_resource": true, "undo_redo": editor_undo_redo != null, "direct_store_write": false}

func _add_editor_action_methods(editor_undo_redo: Object, catalog: Resource, after: Dictionary, before: Dictionary, save_path: String) -> void:
        # EditorUndoRedoManager intentionally exposes the editor-style
        # (object, method, args...) gateway; plain UndoRedo also accepts the
        # Callable form used by non-editor callers.  Keep both paths pointed
        # at the same snapshot function and the same Resource.
        if str(editor_undo_redo.get_class()) == "EditorUndoRedoManager":
                editor_undo_redo.add_do_method(self, "_apply_catalog_snapshot", catalog, after, save_path)
                editor_undo_redo.add_undo_method(self, "_apply_catalog_snapshot", catalog, before, save_path)
        else:
                editor_undo_redo.add_do_method(Callable(self, "_apply_catalog_snapshot").bind(catalog, after, save_path))
                editor_undo_redo.add_undo_method(Callable(self, "_apply_catalog_snapshot").bind(catalog, before, save_path))

func reopen_catalog(path: String) -> Dictionary:
        if path.strip_edges().is_empty(): return _failure("p22.workbench.catalog_path_missing", "P22 目录重开路径为空。")
        var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
        if loaded == null or not loaded is Resource or not loaded.has_method("validate"):
                return _failure("p22.workbench.catalog_reopen_failed", "P22 目录重开失败，资源类型不匹配。", {"path": path})
        var checked: Dictionary = loaded.validate()
        if not checked.ok: return _failure("p22.workbench.catalog_invalid", "P22 目录重开后未通过严格校验。", {"errors_zh": checked.errors})
        return {"schema_version": RESULT_SCHEMA, "ok": true, "code": "p22.workbench.catalog_reopened", "catalog": loaded, "catalog_data": loaded.to_native(), "direct_store_write": false}

func reopen_catalog_into(catalog, path: String) -> Dictionary:
        if catalog == null: return _failure("p22.workbench.catalog_missing", "P22 目录 Resource 不存在。")
        var reopened := reopen_catalog(path)
        if not reopened.ok: return reopened
        var applied := _apply_catalog_snapshot(catalog, reopened.catalog.to_native(), "")
        if not applied.ok: return applied
        return {"schema_version": RESULT_SCHEMA, "ok": true, "code": "p22.workbench.catalog_reopened_same_resource", "catalog": catalog, "catalog_data": catalog.to_native(), "same_resource": true, "direct_store_write": false}

func _apply_catalog_snapshot(catalog, snapshot: Dictionary, save_path: String = "") -> Dictionary:
        var parsed := CATALOG.from_native(snapshot)
        if not parsed.ok: return _failure("p22.workbench.catalog_invalid", "P22 目录快照未通过严格校验。", parsed)
        var source = parsed.value
        catalog.catalog_id = source.catalog_id
        catalog.display_name_zh = source.display_name_zh
        catalog.revision = source.revision
        catalog.attacks = source.attacks.duplicate(true)
        catalog.weapons = source.weapons.duplicate(true)
        catalog.projectiles = source.projectiles.duplicate(true)
        if not save_path.is_empty():
                var error := ResourceSaver.save(catalog, save_path)
                if error != OK: return _failure("p22.workbench.catalog_save_failed", "P22 目录保存失败，当前 Resource 已保留候选状态。", {"save_path": save_path, "save_error": error})
        return {"ok": true, "direct_store_write": false}

func _parse_request(value: Variant) -> Dictionary:
        return REQUEST.from_native(value)

static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
        var result := {"schema_version": RESULT_SCHEMA, "ok": false, "code": code, "reason_zh": reason_zh, "direct_store_write": false}
        if not details.is_empty(): result["details"] = details.duplicate(true)
        return result
