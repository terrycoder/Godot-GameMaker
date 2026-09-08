@tool
class_name GMCharacterAssembler3D
extends RefCounted

## Single assembler for player and NPC visuals.  Actor control, RoleProfile and
## AbilityHost remain P12/P14 concerns; this class only owns derived appearance.

const VISUAL_SCRIPT := preload("res://gm_runtime/characters/visual_3d/gm_character_visual_3d_runtime.gd")
const CACHE_SCRIPT := preload("res://gm_runtime/characters/visual_3d/gm_character_visual_compile_cache.gd")
const API_METHODS := ["set_body_profile", "set_head", "set_hair", "set_outfit", "add_feature", "remove_feature", "set_palette"]

var visual: GMCharacterVisual3D
var resolver: GMCharacterVisual3DResolver
var compile_cache: GMCharacterVisualCompileCache
var actor_kind: String = ""
var actor_id: String = ""

func _init(p_cache: GMCharacterVisualCompileCache = null) -> void:
	compile_cache = p_cache if p_cache != null else CACHE_SCRIPT.new()

func assemble(parent: Node3D, recipe: GMCharacterVisualRecipe, p_resolver: GMCharacterVisual3DResolver, p_actor_kind: String = "npc", p_actor_id: String = "") -> Dictionary:
	if parent == null or not is_instance_valid(parent): return _failure("character.assembler_parent_missing", "3D 角色装配缺少有效 Node3D 父节点。")
	if recipe == null or p_resolver == null: return _failure("character.assembler_input_missing", "3D 角色装配缺少 VisualRecipe 或解析器。")
	if p_actor_kind.strip_edges().is_empty(): return _failure("character.assembler_actor_kind_missing", "角色装配需要稳定 actor kind。")
	var candidate := VISUAL_SCRIPT.new() as GMCharacterVisual3D
	var configured := candidate.configure(recipe, p_resolver)
	if not configured.ok:
		candidate.free()
		return _failure("character.assembler_candidate_rejected", "角色候选装配失败，旧角色状态保持不变。", {"configure": configured, "failure_state_unchanged": true})
	var old_visual := visual
	parent.add_child(candidate)
	candidate.name = "GMCharacterVisual3D_%s" % (p_actor_id if not p_actor_id.is_empty() else p_actor_kind)
	candidate.set_meta("gm_actor_kind", p_actor_kind)
	candidate.set_meta("gm_actor_id", p_actor_id)
	if old_visual != null and is_instance_valid(old_visual): old_visual.queue_free()
	visual = candidate
	resolver = p_resolver
	actor_kind = p_actor_kind
	actor_id = p_actor_id
	return {"ok": true, "actor_kind": actor_kind, "actor_id": actor_id, "visual": visual, "recipe_id": recipe.content_id, "api_methods": API_METHODS.duplicate(), "shared_assembler": true, "failure_state_unchanged": true, "budget": visual.budget_report()}

func configure(visual_node: GMCharacterVisual3D, recipe: GMCharacterVisualRecipe, p_resolver: GMCharacterVisual3DResolver, p_actor_kind: String = "npc", p_actor_id: String = "") -> Dictionary:
	if visual_node == null or not is_instance_valid(visual_node): return _failure("character.assembler_visual_missing", "3D 角色装配缺少有效 GMCharacterVisual3D。")
	var configured := visual_node.configure(recipe, p_resolver)
	if not configured.ok: return configured
	visual = visual_node
	resolver = p_resolver
	actor_kind = p_actor_kind
	actor_id = p_actor_id
	visual.set_meta("gm_actor_kind", actor_kind)
	visual.set_meta("gm_actor_id", actor_id)
	return {"ok": true, "actor_kind": actor_kind, "actor_id": actor_id, "recipe_id": recipe.content_id, "api_methods": API_METHODS.duplicate(), "shared_assembler": true}

func set_body_profile(value: Variant) -> Dictionary:
	return _call_visual("set_body_profile", [value])

func set_head(value: Variant) -> Dictionary:
	return _call_visual("set_head", [value])

func set_hair(value: Variant) -> Dictionary:
	return _call_visual("set_hair", [value])

func set_outfit(value: Variant) -> Dictionary:
	return _call_visual("set_outfit", [value])

func add_feature(value: Variant) -> Dictionary:
	return _call_visual("add_feature", [value])

func remove_feature(value: Variant) -> Dictionary:
	return _call_visual("remove_feature", [value])

func set_palette(value: Variant) -> Dictionary:
	return _call_visual("set_palette", [value])

func set_body_hide(region_id: String, hidden: bool = true) -> Dictionary:
	return _call_visual("set_body_hide", [region_id, hidden])

func compile_current() -> Dictionary:
	if visual == null or resolver == null: return _failure("character.assembler_not_configured", "角色装配器尚未配置。")
	return compile_cache.get_or_compile(visual.recipe, resolver)

func rebuild_cache() -> Dictionary:
	if visual == null or resolver == null: return _failure("character.assembler_not_configured", "角色装配器尚未配置。")
	return compile_cache.rebuild(visual.recipe, resolver)

func delete_cache() -> Dictionary:
	if visual == null: return _failure("character.assembler_not_configured", "角色装配器尚未配置。")
	return compile_cache.delete(visual.recipe.content_id)

func snapshot() -> Dictionary:
	return {"schema": "gm.character.assembler3d.v1", "actor_kind": actor_kind, "actor_id": actor_id, "shared_assembler": true, "api_methods": API_METHODS.duplicate(), "visual": visual.snapshot() if visual != null and is_instance_valid(visual) else {"recipe_id": ""}, "cache": compile_cache.snapshot() if compile_cache != null else {}}

func persistence_record() -> Dictionary:
	if visual == null or not is_instance_valid(visual): return {"schema": "gm.character.visual_contributor.v1", "actor_id": actor_id, "visual_recipe_id": "", "configured": false}
	var result := visual.to_persistence_record()
	result["contributor_schema"] = "gm.character.visual_contributor.v1"
	result["actor_id"] = actor_id
	result["actor_kind"] = actor_kind
	result["domain_facts_written"] = false
	return result

func restore_from_snapshot(snapshot: GMWorldSnapshot, record_key: String = "") -> Dictionary:
	if snapshot == null: return _failure("character.assembler_snapshot_missing", "外观恢复缺少既有 WorldSnapshot。")
	var integrity := snapshot.verify_integrity()
	if not integrity.ok: return _failure("character.assembler_snapshot_invalid", "WorldSnapshot 完整性校验失败，外观不会恢复。", {"integrity": integrity})
	var state := snapshot.world_state
	var record: Variant = state.get(record_key if not record_key.is_empty() else actor_id, null)
	if record == null and state.has("character_visual") : record = state.character_visual
	if not record is Dictionary: return _failure("character.assembler_visual_record_missing", "WorldSnapshot 中没有当前角色外观贡献。")
	return _call_visual("restore_appearance_record", [record])

func unload() -> Dictionary:
	if visual == null: return {"ok": true, "already_unloaded": true}
	var result := visual.unload()
	if result.ok: visual = null
	return result

func _call_visual(method_name: String, args: Array) -> Dictionary:
	if visual == null or not is_instance_valid(visual): return _failure("character.assembler_not_configured", "角色装配器尚未配置。")
	if not visual.has_method(method_name): return _failure("character.assembler_api_missing", "统一外观 API 不可用。", {"method": method_name})
	return visual.callv(method_name, args)

func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "reason_zh": reason_zh, "details": details, "failure_closed": true}
