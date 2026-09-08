extends Node

## P24 中性运行切片。
##
## 入口只装配一组最小的通用对象与生成器，展示 P23 SceneRecipe -> P24
## ObjectRecipe -> 既有 Planar2D adapter 的真实链路。它不引入项目内容或新的
## Task/World/Store/SceneSession 权威。

const DOMAIN := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")
const TARGET := preload("res://gm_runtime/spatial_core/gm_spatial_target_ref.gd")
const CONTEXT := preload("res://gm_runtime/scene/gm_task_execution_context.gd")
const SCENE_RECIPE := preload("res://gm_runtime/scene/gm_scene_recipe.gd")
const SKELETON := preload("res://gm_runtime/scene/gm_scene_skeleton_definition.gd")
const SLOT := preload("res://gm_runtime/scene/gm_semantic_slot_2d.gd")
const POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const DEFINITION := preload("res://gm_runtime/level/gm_level_object_definition.gd")
const ABILITY := preload("res://gm_runtime/level/gm_level_object_ability.gd")
const LEVEL_RECIPE := preload("res://gm_runtime/level/gm_level_object_recipe.gd")
const ASSEMBLER := preload("res://gm_runtime/level/gm_level_object_assembler.gd")
const RESOLVER := preload("res://gm_runtime/level/gm_level_object_resolver.gd")
const FACTS := preload("res://gm_runtime/scene/gm_execution_facts.gd")
const MAP_REGISTRY := preload("res://gm_runtime/map/semantic/gm_map_semantic_registry.gd")
const MAP_RESOURCE := preload("res://gm_runtime/map/gm_map_resource.gd")
const SEMANTIC_MAP := preload("res://gm_runtime/map/semantic/gm_map_semantic_resource.gd")
const ANCHOR := preload("res://gm_runtime/map/semantic/gm_semantic_anchor.gd")
const ADAPTER_2D := preload("res://gm_adapters/spatial/gm_planar_2d_spatial_adapter.gd")

const MAP_ID := "gm.map.p24.export"
const SURFACE_ID := "gm.surface.p24.export"

func _ready() -> void:
	var result := _run_product()
	result["event"] = "P24_LEVEL_OBJECTS_STARTUP_SENTINEL"
	result["godot"] = Engine.get_version_info().get("string", "")
	result["entry"] = "gm_runtime/level/gm_p24_export_entry.tscn"
	print(JSON.stringify(result))
	get_tree().quit(0 if bool(result.get("ok", false)) else 248)

func _run_product() -> Dictionary:
	var registry := MAP_REGISTRY.new()
	var semantic = _semantic_map()
	var registered := registry.register_map(semantic)
	if not registered.ok:
		return _failure("p24.map_registration", registered)
	var entry := _target("gm.anchor.p24.export.entry")
	var exit := _target("gm.anchor.p24.export.exit")
	var slots := _slots(entry, exit)
	var skeleton := SKELETON.new(
		"gm.skeleton.p24.export", "P24中性对象骨架", [DOMAIN.PLANAR_2D, DOMAIN.PLANAR_3D],
		[{"region_id": "gm.region.p24.export", "region_kind": "play_space", "required": true, "tags": ["neutral"]}],
		slots, ["neutral", "alternate"]
	)
	var context := CONTEXT.new(
		"gm.task.p24.export", "gm.assignment.p24.export", "scene", {"type": "task_target", "id": "gm.target.p24.export"},
		[{"type": "actor", "id": "gm.actor.p24.export"}], [], {"allow_hostile_remaining": true}, 23, {}
	)
	var scene := SCENE_RECIPE.new(
		"gm.recipe.p24.export", "P24中性对象SceneRecipe", skeleton.skeleton_id, entry, exit,
		SCENE_RECIPE.REQUIRED_SLOT_KINDS.duplicate(),
		[
			{"object_id": "gm.object.p24.export.door", "object_kind": "door", "required": true, "tags": ["facility"]},
			{"object_id": "gm.object.p24.export.generator", "object_kind": "generator", "required": true, "tags": ["facility"]}
		],
		[{"region_id": "gm.region.p24.export", "region_kind": "play_space", "required": true, "tags": ["neutral"]}],
		slots, context.participants,
		[{"objective_id": "gm.objective.p24.export", "kind": "interact", "target_value": 1, "contribution_field": "door_interactions", "target_ref": {}, "requires_hostile_clear": false}],
		[
			{"result_id": "gm.result.p24.export.success", "status": "success", "required_objective_ids": ["gm.objective.p24.export"], "reason_code": "scene.objectives.completed"},
			{"result_id": "gm.result.p24.export.partial", "status": "partial_success", "required_objective_ids": [], "reason_code": "scene.extraction.partial"},
			{"result_id": "gm.result.p24.export.failed", "status": "failed", "required_objective_ids": [], "reason_code": "scene.execution.failed"},
			{"result_id": "gm.result.p24.export.extracted", "status": "extracted", "required_objective_ids": [], "reason_code": "scene.extraction.voluntary"}
		], ["neutral", "alternate"]
	)
	var scene_checks := [scene.validate(), skeleton.validate(), context.validate()]
	for check in scene_checks:
		if not check.ok:
			return _failure("p24.scene_contract", check)
	var definitions := [
		DEFINITION.new("gm.definition.p24.export.door", "door", "gm.ability.p24.export.door", {"locked": false, "open": false}, {}, {}, {}, {}, "", ["neutral"], {}).to_dict(),
		DEFINITION.new("gm.definition.p24.export.generator", "generator", "gm.ability.p24.export.generator", {"generated_count": 0}, {}, {}, {}, {}, "", ["neutral"], {}).to_dict()
	]
	var object_bindings := [
		{"object_id": "gm.object.p24.export.door", "definition_id": "gm.definition.p24.export.door", "slot_id": "gm.slot.p24.export.door", "initial_state": {"locked": false, "open": false}, "tags": ["facility"]},
		{"object_id": "gm.object.p24.export.generator", "definition_id": "gm.definition.p24.export.generator", "slot_id": "gm.slot.p24.export.generator", "initial_state": {"generated_count": 0}, "tags": ["facility"]}
	]
	var generator_rows := [{
		"generator_id": "gm.object.p24.export.generator", "definition_id": "gm.definition.p24.export.generator", "slot_id": "gm.slot.p24.export.generator",
		"count": 2, "actor_recipe": {"actor_recipe_id": "gm.actor_recipe.p24.export", "archetype": "neutral"},
		"task_budget": {"budget_id": "gm.budget.p24.export", "remaining": 3, "unit": "actors"}, "seed": 23,
		"generated_kind": "actor", "generated_definition_id": "gm.definition.p24.export.actor", "tags": ["generated", "neutral"]
	}]
	var level_check := LEVEL_RECIPE.from_scene_recipe(scene, "gm.recipe.p24.export.objects", definitions, object_bindings, generator_rows, ["neutral", "alternate"])
	if not level_check.ok:
		return _failure("p24.level_recipe", level_check)
	var backend := ADAPTER_2D.new(registry, true)
	var assembly := ASSEMBLER.new().assemble(scene, level_check.value, skeleton, context, backend, {})
	if not assembly.ok:
		return _failure("p24.assembly", assembly)
	var generated := ASSEMBLER.new().generate(level_check.value, "gm.object.p24.export.generator")
	if not generated.ok:
		return _failure("p24.generation", generated)
	var door_definition := DEFINITION.new("gm.definition.p24.export.door", "door", "gm.ability.p24.export.door", {"locked": false, "open": false}, {}, {}, {}, {}, "", ["neutral"], {})
	var door_ability := ABILITY.make("gm.request.p24.export.door", door_definition.ability_id, {"type": "actor", "id": "gm.actor.p24.export"}, {"type": "level_object", "id": "gm.object.p24.export.door"}, "open")
	var resolved := RESOLVER.new().resolve(door_definition, door_ability, {"locked": false, "open": false}, {"session_id": "gm.session.p24.export", "sequence": 1})
	if not resolved.ok:
		return _failure("p24.resolve", resolved)
	var fact_check := FACTS.from_dict(resolved.fact)
	return {
		"ok": fact_check.ok,
		"backend_domain": assembly.value.backend_domain,
		"object_projection_count": assembly.value.objects.size(),
		"generated_object_count": generated.value.generated_objects.size(),
		"fact_id": resolved.fact.fact_id,
		"fact_valid": fact_check.ok,
		"projection_only": assembly.value.objects[0].projection_only if not assembly.value.objects.is_empty() else false,
		"error": "" if fact_check.ok else fact_check
	}

func _semantic_map():
	var terrain := MAP_RESOURCE.new()
	terrain.map_id = MAP_ID
	terrain.map_size = Vector2i(4, 4)
	terrain.tile_size = Vector2i(32, 32)
	for y in range(4):
		for x in range(4):
			terrain.set_logic_cell(Vector2i(x, y), {"ground_type": "floor", "walkable": true, "cost": 1.0})
	var semantic := SEMANTIC_MAP.new()
	semantic.map_id = MAP_ID
	semantic.terrain_map = terrain
	semantic.surface_ids = PackedStringArray([SURFACE_ID])
	for row in [["gm.anchor.p24.export.entry", Vector2(16.0, 16.0)], ["gm.anchor.p24.export.exit", Vector2(48.0, 16.0)]]:
		var anchor := ANCHOR.new()
		anchor.anchor_id = row[0]
		anchor.position = row[1]
		semantic.anchors.append(anchor)
	return semantic

func _target(anchor_id: String) -> Dictionary:
	var checked := TARGET.from_native({"schema_version": 1, "domain_id": DOMAIN.PLANAR_2D, "kind": "anchor", "semantic_id": anchor_id, "map_id": MAP_ID})
	return checked.value if checked.ok else {}

func _slots(entry: Dictionary, exit: Dictionary) -> Array:
	var rows := [
		["gm.slot.p24.export.entry", "entry", entry], ["gm.slot.p24.export.exit", "exit", exit],
		["gm.slot.p24.export.objective", "objective", {"type": "object", "id": "gm.object.p24.export.door"}],
		["gm.slot.p24.export.resource", "resource", {"type": "resource", "id": "gm.resource.p24.export"}],
		["gm.slot.p24.export.hostile", "hostile", {"type": "actor_group", "id": "gm.actor_group.p24.export"}],
		["gm.slot.p24.export.facility", "facility", {"type": "facility", "id": "gm.facility.p24.export"}],
		["gm.slot.p24.export.extraction", "extraction", exit],
		["gm.slot.p24.export.door", "object", {"type": "level_object", "id": "gm.object.p24.export.door"}],
		["gm.slot.p24.export.generator", "object", {"type": "level_object", "id": "gm.object.p24.export.generator"}]
	]
	var result: Array = []
	for row in rows:
		result.append(SLOT.new(str(row[0]), str(row[1]), row[2], true, 1, ["p24"]).to_dict())
	return result

func _failure(stage: String, detail: Dictionary) -> Dictionary:
	return {"ok": false, "code": "product.%s_failed" % stage, "details": detail}
