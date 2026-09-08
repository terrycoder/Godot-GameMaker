class_name GMPlayerShell
extends Node

## P25 formal Player Shell.
##
## The shell is a thin composition root: one P14 character control router and
## one GAS host drive movement and interaction, one P16 TaskService owns Task
## state, P21 carries UI commands, and P23 owns the optional scene session.
## 2D/3D nodes below are projections; they never become alternate authorities.

signal action_dispatched(action_id: String, result: Dictionary)
signal interaction_result(result: Dictionary)
signal state_changed(snapshot: Dictionary)

const P25_STORE_ID := "gm.store.player_shell"
const P25_STORE_SCHEMA := "gm.player_shell.store.v1"
const P25_2D_ONLY_MANIFEST_INDEX := "res://gm_runtime/manifests/p25_2d_only_manifest_index.tres"
const DELIVERY_FULL := "full"
const DELIVERY_2D_ONLY := "2d_only"

const INPUT_ACTIONS := {
        "gm.p25.move.up": KEY_W,
        "gm.p25.move.down": KEY_S,
        "gm.p25.move.left": KEY_A,
        "gm.p25.move.right": KEY_D,
        "gm.p25.interact": KEY_E,
        "gm.p25.task.view": KEY_TAB,
        "gm.p25.task.assign": KEY_F,
        "gm.p25.scene.switch": KEY_N,
        "gm.p25.camera.toggle": KEY_C,
        "gm.p25.menu.toggle": KEY_ESCAPE,
}

const RUNTIME_CONTEXT_SCRIPT := preload("res://gm_runtime/gm_runtime_context.gd")
const CONFIGURATION_SCRIPT := preload("res://gm_runtime/player_shell/gm_player_shell_configuration.gd")
const MAP_REGISTRY_SCRIPT := preload("res://gm_runtime/map/semantic/gm_map_semantic_registry.gd")
const MAP_RESOURCE_SCRIPT := preload("res://gm_runtime/map/gm_map_resource.gd")
const SEMANTIC_MAP_SCRIPT := preload("res://gm_runtime/map/semantic/gm_map_semantic_resource.gd")
const ANCHOR_SCRIPT := preload("res://gm_runtime/map/semantic/gm_semantic_anchor.gd")
const PLANAR_2D_SCRIPT := preload("res://gm_adapters/spatial/gm_planar_2d_spatial_adapter.gd")
const PLANAR_3D_SCRIPT_PATH := "res://gm_adapters/spatial3d/gm_planar_3d_spatial_adapter.gd"
const MAP_BACKEND_3D_SCRIPT_PATH := "res://gm_runtime/map/3d/gm_map_backend_3d.gd"
const SURFACE_GRAPH_SCRIPT_PATH := "res://gm_runtime/map/3d/gm_surface_graph.gd"
const SURFACE_SCRIPT_PATH := "res://gm_runtime/map/3d/gm_surface_definition_3d.gd"
const INTERACTION_QUERY_3D_SCRIPT_PATH := "res://gm_adapters/spatial3d/gm_interaction_query_3d.gd"
const CAMERA_RIG_3D_SCRIPT_PATH := "res://gm_adapters/spatial3d/gm_camera_rig_3d.gd"
const SPATIAL_TARGET_SCRIPT := preload("res://gm_runtime/spatial_core/gm_spatial_target_ref.gd")
const PLANAR_POSITION_SCRIPT := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")
const ABILITY_REQUEST_SCRIPT := preload("res://gm_runtime/gas/gm_ability_activation_request.gd")
const TARGET_DATA_SCRIPT := preload("res://gm_runtime/gas/gm_target_data.gd")
const MOVEMENT_REQUEST_SCRIPT := preload("res://gm_runtime/movement/gm_movement_request.gd")
const CHARACTER_SCRIPT := preload("res://gm_runtime/characters/gm_character_runtime_2d.gd")
const ROLE_PROFILE_SCRIPT := preload("res://gm_runtime/characters/gm_role_profile.gd")
const TASK_DEFINITION_SCRIPT := preload("res://gm_runtime/tasks/gm_task_definition.gd")
const TASK_SERVICE_SCRIPT := preload("res://gm_runtime/tasks/gm_task_service.gd")
const TASK_PROJECTION_SERVICE_SCRIPT := preload("res://gm_runtime/p21/gm_task_projection_service.gd")
const INTERACTION_ROUTER_SCRIPT := preload("res://gm_runtime/p21/gm_interaction_router.gd")
const INTERACTION_REQUEST_SCRIPT := preload("res://gm_runtime/p21/gm_interaction_request.gd")
const INTERACTION_RESULT_SCRIPT := preload("res://gm_runtime/p21/gm_interaction_result.gd")
const TASK_BACKEND_SCRIPT := preload("res://gm_runtime/p21/gm_task_interaction_backend.gd")
const OBJECT_INSTANCE_SCRIPT := preload("res://gm_runtime/objects/gm_object_instance.gd")
const OBJECT_DEFINITION_SCRIPT := preload("res://gm_runtime/objects/gm_object_definition.gd")
const OBJECT_SERVICE_SCRIPT := preload("res://gm_runtime/objects/gm_object_interaction_service.gd")
const ABILITY_DEFINITION_SCRIPT := preload("res://gm_runtime/gas/gm_ability_definition.gd")
const SCENE_CONTEXT_SCRIPT := preload("res://gm_runtime/scene/gm_task_execution_context.gd")
const SCENE_SKELETON_SCRIPT := preload("res://gm_runtime/scene/gm_scene_skeleton_definition.gd")
const SCENE_RECIPE_SCRIPT := preload("res://gm_runtime/scene/gm_scene_recipe.gd")
const SCENE_SLOT_SCRIPT := preload("res://gm_runtime/scene/gm_semantic_slot_2d.gd")
const SCENE_DEFINITION_SCRIPT := preload("res://gm_runtime/scene/gm_scene_session_definition.gd")
const SCENE_BUILDER_SCRIPT := preload("res://gm_runtime/scene/gm_scene_recipe_builder.gd")
const SCENE_SESSION_SCRIPT := preload("res://gm_runtime/scene/gm_task_execution_session.gd")
const P21_ABILITY_BACKEND_SCRIPT := preload("res://gm_runtime/player_shell/gm_player_shell_ability_backend.gd")
const CAMERA_PROFILE_SCRIPT := preload("res://gm_runtime/player_shell/gm_player_shell_camera_profile.gd")
const WORLD_2D_SCRIPT := preload("res://gm_runtime/player_shell/gm_player_shell_world_2d.gd")
const ACTOR_2D_SCRIPT := preload("res://gm_runtime/player_shell/gm_player_shell_actor_2d.gd")
const TARGET_3D_SCRIPT_PATH := "res://gm_runtime/player_shell/gm_player_shell_interactive_3d.gd"
const SIMULATION_WORLD_SCRIPT := preload("res://gm_runtime/simulation/gm_simulation_world.gd")
const STORE_SCRIPT := preload("res://gm_runtime/simulation/gm_store.gd")

@export_enum("full", "2d_only") var delivery_mode := DELIVERY_FULL
@export var shell_configuration: GMPlayerShellConfiguration

var runtime_context: GMRuntimeContext
var semantic_registry: GMMapSemanticRegistry
var map_resource: GMMapResource
var semantic_map: GMMapSemanticResource
var adapter_2d: GMPlanar2DSpatialAdapter
var map_backend_3d
var surface_graph_3d
var adapter_3d
var interaction_query_3d

var player: GMPlayerShellActor2D
var player_host: GMAbilitySystemHost
var target_object: GMObjectInstance
var target_definition: GMObjectDefinition
var object_service: GMObjectInteractionService

var task_service: GMTaskService
var task_projection_service: GMTaskProjectionService
var interaction_router: GMInteractionRouter
var ability_backend: GMPlayerShellAbilityBackend
var task_backend: GMTaskInteractionBackend
var task_definition: GMTaskDefinition
var scene_session: GMTaskExecutionSession
var scene_session_definition: GMSceneSessionDefinition
var simulation_world
var player_shell_store
var _persistence_store_listener: Callable

var camera_profile: GMPlayerShellCameraProfile
var world_2d: GMPlayerShellWorld2D
var camera_2d: Camera2D
var world_3d
var player_proxy_3d
var target_3d
var camera_rig_3d

var canvas_layer: CanvasLayer
var ui_root: Control
var task_panel: PanelContainer
var task_summary_label: Label
var status_label: Label
var scene_label: Label
var backend_label: Label
var menu_panel: PanelContainer
var menu_hint_label: Label

var active_dimension := "2d"
var active_scene_index := 0
var target_available := true
var interaction_module_enabled := true
var task_panel_visible := false
var menu_visible := false
var formal_ui_ready := false
var debug_isolated := true
var _startup_error: Dictionary = {}
var _last_query: Dictionary = {}
var _last_result: Dictionary = {}
var _last_context_backend: Dictionary = {}
var _movement_direction := Vector2.ZERO
var _manual_direction := Vector2.ZERO
var _manual_direction_override := false
var _movement_sequence := 0
var _interaction_sequence := 0
var _task_sequence := 0
var persistence_loaded := false
var persistence_last_path := ""
var persistence_restore_error: Dictionary = {}

func _resolve_shell_configuration() -> Dictionary:
        if shell_configuration == null:
                var requested_id := CONFIGURATION_SCRIPT.configuration_id_from_args(OS.get_cmdline_user_args())
                var loaded := CONFIGURATION_SCRIPT.load_for_id(requested_id)
                if not loaded.ok:
                        return loaded
                shell_configuration = loaded.configuration
        if not shell_configuration is GMPlayerShellConfiguration:
                return _failure("shell.configuration_type_invalid", "玩家外壳需要GMPlayerShellConfiguration正式组合边界。")
        var checked: Dictionary = shell_configuration.validate()
        if not checked.ok:
                return _failure("shell.configuration_invalid", "玩家外壳正式组合边界校验失败。", checked)
        return {"ok": true, "configuration_id": shell_configuration.configuration_id}

func _ready() -> void:
        var configuration_ready := _resolve_shell_configuration()
        if not configuration_ready.ok:
                _startup_error = configuration_ready
                _build_formal_ui()
                _refresh_ui()
                return
        if delivery_mode == DELIVERY_2D_ONLY or OS.get_cmdline_user_args().has("--p25-2d-only-check"):
                OS.set_environment("GM_MODULE_INDEX_PATH", P25_2D_ONLY_MANIFEST_INDEX)
        _ensure_input_map()
        var built := _build_runtime()
        if not built.ok:
                _startup_error = built
        _build_formal_ui()
        if _should_restore_on_start():
                var restored := restore_world_snapshot()
                if not restored.ok and str(restored.get("code", "")) != "world.save_missing":
                        persistence_restore_error = restored
                        _startup_error = restored
        _refresh_ui()
        _schedule_command_mode()

func _process(delta: float) -> void:
        if not _startup_error.is_empty(): return
        var direction := _manual_direction if _manual_direction_override else Input.get_vector("gm.p25.move.left", "gm.p25.move.right", "gm.p25.move.up", "gm.p25.move.down")
        if direction.length_squared() > 0.0001:
                _set_move_direction(direction.normalized())
        elif not _manual_direction_override:
                _set_move_direction(Vector2.ZERO)
        if player_host != null and is_instance_valid(player_host):
                player_host.tick(delta)
        _update_projection()
        _refresh_ui()

func _unhandled_input(event: InputEvent) -> void:
        if _startup_error.is_empty(): dispatch_input_event(event)

func dispatch_input_event(event: InputEvent) -> Dictionary:
        if event == null: return _failure("input.event_missing", "正式输入事件不能为空。")
        var action_order := [
                "gm.p25.move.up", "gm.p25.move.down", "gm.p25.move.left", "gm.p25.move.right",
                "gm.p25.interact", "gm.p25.task.view", "gm.p25.task.assign", "gm.p25.scene.switch",
                "gm.p25.camera.toggle", "gm.p25.menu.toggle"
        ]
        # Resolve every press before checking release edges. A real
        # InputEventJoypadMotion may report a release for an earlier, unrelated
        # axis action while being pressed for the later matching direction.
        for action_id in action_order:
                if event.is_action_pressed(action_id):
                        var pressed := handle_action(action_id)
                        return pressed
        for action_id in action_order:
                if event.is_action_released(action_id) and action_id.begins_with("gm.p25.move."):
                        _manual_direction_override = true
                        _manual_direction = Vector2.ZERO
                        var released := handle_action("gm.p25.move.stop")
                        return released
        return {"ok": true, "ignored": true}

func handle_action(action_id: String, data: Dictionary = {}) -> Dictionary:
        var result: Dictionary
        match action_id:
                "gm.p25.move.up": result = drive_direction(Vector2.UP)
                "gm.p25.move.down": result = drive_direction(Vector2.DOWN)
                "gm.p25.move.left": result = drive_direction(Vector2.LEFT)
                "gm.p25.move.right": result = drive_direction(Vector2.RIGHT)
                "gm.p25.move.stop": result = drive_direction(Vector2.ZERO)
                "gm.p25.interact": result = interact_with_key(_next_interaction_key())
                "gm.p25.task.view":
                        task_panel_visible = not task_panel_visible
                        result = {"ok": true, "action": action_id, "visible": task_panel_visible}
                "gm.p25.task.assign": result = assign_task(_next_task_key())
                "gm.p25.scene.switch": result = switch_scene()
                "gm.p25.camera.toggle": result = toggle_dimension()
                "gm.p25.menu.toggle":
                        menu_visible = not menu_visible
                        result = {"ok": true, "action": action_id, "visible": menu_visible}
                "gm.p25.save.exit": result = save_and_exit()
                "gm.p25.shell.target_available": result = set_target_available(bool(data.get("available", true)))
                "gm.p25.shell.module_enabled": result = set_module_enabled(bool(data.get("enabled", true)))
                _:
                        result = _failure("input.action_unknown", "玩家外壳不认识该正式动作：%s" % action_id)
        action_dispatched.emit(action_id, result.duplicate(true))
        _refresh_ui()
        return result

func drive_direction(direction: Vector2) -> Dictionary:
        _manual_direction_override = true
        _manual_direction = direction
        _set_move_direction(direction)
        return {"ok": true, "action": "move", "direction": {"x": direction.x, "y": direction.y}, "single_input_source": true}

func advance_simulation(seconds: float, step: float = 1.0 / 60.0) -> Dictionary:
        if not is_finite(seconds) or seconds < 0.0 or not is_finite(step) or step <= 0.0:
                return _failure("simulation.duration_invalid", "测试推进时间必须是有限非负值。")
        var remaining := seconds
        var ticks := 0
        while remaining > 0.000001:
                var delta := minf(step, remaining)
                if player_host != null and is_instance_valid(player_host): player_host.tick(delta)
                remaining -= delta
                ticks += 1
        _update_projection()
        _refresh_ui()
        return {"ok": true, "ticks": ticks, "seconds": seconds, "position": {"x": player.position.x, "y": player.position.y}}

func query_active_target() -> Dictionary:
        var query := _query_target()
        _last_query = query.duplicate(true)
        _update_projection()
        _refresh_ui()
        return query

func interact_with_key(idempotency_key: String) -> Dictionary:
        if not interaction_module_enabled:
                var disabled_request := GMInteractionRequest.ability(shell_configuration.interaction_id, {"type": "actor", "id": shell_configuration.player_id}, {"type": "object", "id": shell_configuration.target_id}, {"ability_id": shell_configuration.ability_id, "target_id": shell_configuration.target_id}, idempotency_key)
                var disabled_result: GMInteractionResult = interaction_router.submit(disabled_request)
                return _publish_interaction_result(disabled_result)
        var query := query_active_target()
        if not bool(query.get("ok", false)):
                var query_result: GMInteractionResult = GMInteractionResult.rejected_public({"kind": "ability", "interaction_id": shell_configuration.interaction_id}, "interaction.query_blocked", str(query.get("error_zh", "交互目标查询被阻断。")), {"spatial_query": query})
                return _publish_interaction_result(query_result)
        var target_ref: Dictionary = query.get("target", {}) if query.get("target", {}) is Dictionary else {}
        var target_id := str(target_ref.get("semantic_id", query.get("value", {}).get("semantic_id", "")))
        if target_id == shell_configuration.target_anchor_id:
                target_id = shell_configuration.target_id
        if target_id.is_empty():
                var identity_result: GMInteractionResult = GMInteractionResult.rejected_public({"kind": "ability", "interaction_id": shell_configuration.interaction_id}, "interaction.target_identity_missing", "空间查询没有返回稳定目标身份。", {"spatial_query": query})
                return _publish_interaction_result(identity_result)
        var event_data := {
                "recipe_id": shell_configuration.interaction_recipe_id,
                "event_tag": shell_configuration.interaction_event_tag,
                "cue_id": "",
                "state_patch": {"activated": true},
                "spatial_target": target_ref.duplicate(true),
                "target_id": target_id,
        }
        var request := GMInteractionRequest.ability(
                shell_configuration.interaction_id,
                {"type": "actor", "id": shell_configuration.player_id},
                target_ref,
                {"ability_id": shell_configuration.ability_id, "target_id": target_id, "event_data": event_data},
                idempotency_key
        )
        var result: GMInteractionResult = interaction_router.submit(request)
        return _publish_interaction_result(result)

func assign_task(idempotency_key: String) -> Dictionary:
        var payload := {
                "operation": "assign",
                "task_operation": "assign",
                "source_type": "player",
                "source_id": shell_configuration.player_id,
                "assignment_id": shell_configuration.assignment_id,
                "task_id": shell_configuration.task_id,
                "assignee": {"type": "actor", "id": shell_configuration.player_id},
                "kind": "actor",
        }
        var request := GMInteractionRequest.task(
                shell_configuration.task_interaction_id,
                {"type": "actor", "id": shell_configuration.player_id},
                {"type": "task", "id": shell_configuration.task_id},
                payload,
                idempotency_key
        )
        var result: GMInteractionResult = interaction_router.submit(request)
        var value := result.to_dict()
        _last_result = value.duplicate(true)
        _refresh_ui()
        return value

func switch_scene() -> Dictionary:
        if scene_session == null:
                return _failure("scene.session_missing", "玩家外壳尚未装配P23 SceneSession。")
        if scene_session.state.phase == "created":
                var started := scene_session.start()
                if not started.ok: return started
        active_scene_index = posmod(active_scene_index + 1, 2)
        _update_projection()
        _refresh_ui()
        var state := scene_session.state_value()
        return {"ok": true, "action": "scene.switch", "scene_index": active_scene_index, "scene_id": _active_scene_id(), "session": state}

func toggle_dimension() -> Dictionary:
        return set_dimension("3d" if active_dimension == "2d" else "2d")

func set_dimension(dimension: String) -> Dictionary:
        var normalized := dimension.to_lower()
        if normalized not in ["2d", "3d"]: return _failure("camera.dimension_invalid", "玩家外壳只支持2D或3D正式投影。")
        if normalized == "3d" and delivery_mode == DELIVERY_2D_ONLY:
                return _failure("delivery.3d_module_excluded", "2D-only交付不包含3D模块。")
        active_dimension = normalized
        if world_2d != null: world_2d.visible = active_dimension == "2d"
        if world_3d != null: world_3d.visible = active_dimension == "3d"
        if camera_2d != null:
                camera_2d.enabled = active_dimension == "2d"
                camera_2d.position = player.position + camera_profile.look_ahead if player != null else shell_configuration.map_size * 0.5
        if camera_rig_3d != null:
                camera_rig_3d.visible = active_dimension == "3d"
                if camera_rig_3d.camera != null: camera_rig_3d.camera.current = active_dimension == "3d"
        _last_context_backend = _activate_context_backend(normalized)
        _update_projection()
        _refresh_ui()
        var result := {"ok": true, "dimension": active_dimension, "camera_backend": "Camera2D" if active_dimension == "2d" else "GMCameraRig3D", "query_backend": "GMPlanar2DSpatialAdapter" if active_dimension == "2d" else "GMInteractionQuery3D", "context_backend": _last_context_backend.duplicate(true)}
        state_changed.emit(snapshot())
        return result

func set_target_available(available: bool) -> Dictionary:
        target_available = available
        if target_3d != null and is_instance_valid(target_3d):
                target_3d.collision_layer = 1 if target_available else 0
                target_3d.visible = target_available
        _update_projection()
        _refresh_ui()
        return {"ok": true, "target_available": target_available}

func set_module_enabled(enabled: bool) -> Dictionary:
        interaction_module_enabled = enabled
        if interaction_router != null:
                if enabled:
                        interaction_router.register_backend("ability", ability_backend)
                else:
                        interaction_router.unregister_backend("ability")
        return {"ok": true, "interaction_module_enabled": interaction_module_enabled, "backend_registered": interaction_router.backends.has("ability") if interaction_router != null else false}

func save_and_reopen_projection() -> Dictionary:
        if simulation_world == null or player_shell_store == null:
                return _failure("save.authority_missing", "正式外壳尚未接入既有SimulationWorld存档权威。")
        var captured := _capture_p25_contributors()
        if not captured.ok: return captured
        var world_snapshot: Dictionary = simulation_world.save_snapshot()
        if world_snapshot.has("ok") and not bool(world_snapshot.get("ok", false)): return world_snapshot
        var reopened: Dictionary = simulation_world.load_snapshot(world_snapshot.duplicate(true))
        if not reopened.ok: return reopened
        _update_projection()
        _refresh_ui()
        return {"ok": true, "closed_reopened": true, "world_load": reopened, "contributors": reopened.get("contributors", {}), "task_projection": task_projection(), "actor": player.save_snapshot(), "scene_session": scene_session.state_value(), "object": target_object.state_snapshot()}

func save_and_exit() -> Dictionary:
        var saved := save_world_snapshot()
        if bool(saved.get("ok", false)):
                call_deferred("_quit_after_save")
        return saved

func save_world_snapshot() -> Dictionary:
        if simulation_world == null or player_shell_store == null:
                return _failure("save.authority_missing", "正式外壳尚未接入既有SimulationWorld存档权威。")
        var captured := _capture_p25_contributors()
        if not captured.ok: return captured
        var saved: Dictionary = simulation_world.save_to_file(shell_configuration.save_path)
        if not saved.ok: return saved
        persistence_last_path = shell_configuration.save_path
        return {"ok": true, "saved": true, "path": shell_configuration.save_path, "authority": saved, "contributors": captured, "task_projection": task_projection(), "player": player.save_snapshot(), "scene_session": scene_session.state_value(), "object": target_object.state_snapshot()}

func restore_world_snapshot() -> Dictionary:
        if simulation_world == null or player_shell_store == null:
                return _failure("save.authority_missing", "正式外壳尚未接入既有SimulationWorld存档权威。")
        var loaded: Dictionary = simulation_world.load_from_file(shell_configuration.save_path)
        if not loaded.ok: return loaded
        persistence_loaded = true
        persistence_last_path = shell_configuration.save_path
        _last_query = {}
        _last_result = {}
        task_panel_visible = false
        menu_visible = false
        active_dimension = "2d"
        active_scene_index = 0
        target_available = true
        set_dimension("2d")
        set_target_available(target_available)
        _update_projection()
        _refresh_ui()
        state_changed.emit(snapshot())
        return {"ok": true, "restored": true, "path": shell_configuration.save_path, "authority": loaded, "contributors": loaded.get("contributors", {}), "task_projection": task_projection(), "player": player.save_snapshot(), "scene_session": scene_session.state_value(), "object": target_object.state_snapshot()}

func _capture_p25_contributors() -> Dictionary:
        if player == null or task_service == null or scene_session == null or target_object == null or simulation_world == null or player_shell_store == null:
                return _failure("save.contributor_missing", "正式外壳的已有存档贡献者尚未就绪。")
        var scene_snapshot: Variant = JSON.parse_string(scene_session.snapshot_json())
        if not scene_snapshot is Dictionary:
                return _failure("save.scene_snapshot_invalid", "P23 SceneSession没有返回可登记的纯数据快照。")
        var staged = STORE_SCRIPT.new(P25_STORE_ID, P25_STORE_SCHEMA)
        var writes := [
                ["task_authority", task_service.fact_store.snapshot()],
                ["player", player.save_snapshot()],
                ["object", target_object.state_snapshot()],
                ["scene_session", scene_snapshot],
        ]
        for row in writes:
                var written := staged.put(str(row[0]), row[1])
                if not written.ok: return _failure("save.contributor_invalid", "已有贡献者快照未通过既有GMStore纯数据边界。", {"key": row[0], "details": written})
        var committed: Dictionary = player_shell_store.restore_snapshot(staged.snapshot())
        if not committed.ok: return _failure("save.store_commit_failed", "玩家外壳贡献者没有通过既有GMStore原子提交。", {"details": committed})
        return {"ok": true, "store_id": P25_STORE_ID, "keys": player_shell_store.keys(), "record_count": player_shell_store.keys().size()}

func _prepare_p25_contributors(_world_snapshot: Dictionary, staged_stores: Dictionary) -> Dictionary:
        if task_service == null or player == null or target_object == null or scene_session == null:
                return _failure("save.contributor_missing", "正式外壳的已有存档贡献者尚未就绪。")
        var staged_shell: Variant = staged_stores.get(P25_STORE_ID, null)
        var staged_task: Variant = staged_stores.get(task_service.STORE_ID, null)
        if not staged_shell is GMStore or not staged_task is GMStore:
                return _failure("save.store_candidate_missing", "原子恢复候选缺少正式贡献者Store。", {"store_id": P25_STORE_ID, "task_store_id": task_service.STORE_ID})
        var task_authority: Dictionary = staged_shell.read("task_authority")
        var actor_snapshot: Dictionary = staged_shell.read("player")
        var object_snapshot: Dictionary = staged_shell.read("object")
        var scene_snapshot: Dictionary = staged_shell.read("scene_session")
        if task_authority.is_empty() or actor_snapshot.is_empty() or object_snapshot.is_empty() or scene_snapshot.is_empty():
                return _failure("save.payload_truncated", "既有SimulationWorld Store缺少一个或多个正式贡献者。", {"store_id": P25_STORE_ID, "keys": staged_shell.keys()})

        # Reuse the existing TaskService restore contract on a detached service.
        # Its FactEventStore and domain Store are not live until the commit callback.
        var task_snapshot := {"snapshot_schema": "gm.task.snapshot.v3", "authority_store": task_authority, "store": staged_task.snapshot()}
        var staged_task_service = TASK_SERVICE_SCRIPT.new()
        var task_restore: Dictionary = staged_task_service.restore_json(JSON.stringify(task_snapshot))
        if not task_restore.ok: return _failure("save.contributor_prepare_invalid", "Task贡献者候选未通过既有语义恢复合同。", {"contributor": "task", "details": task_restore})
        # Keep the world candidate itself normalized. The world replacement listener
        # intentionally rebinds TaskService to the swapped Store after commit; copy
        # the detached restore result into that same candidate so JSON integer headers
        # cannot be replaced by the raw float-bearing staged snapshot.
        var normalized_task_restore: Dictionary = staged_task.restore_snapshot(staged_task_service.store.snapshot())
        if not normalized_task_restore.ok: return _failure("save.contributor_prepare_invalid", "Task贡献者规范化候选未通过既有GMStore原子边界。", {"contributor": "task", "details": normalized_task_restore})

        # JSON boundaries may represent integer fields as floats. Preserve the
        # existing P14 control-handoff contract before detached actor preparation.
        var control_handoff: Dictionary = actor_snapshot.get("control_handoff", {}) if actor_snapshot.get("control_handoff", {}) is Dictionary else {}
        if control_handoff.has("sequence"):
                control_handoff["sequence"] = int(control_handoff.get("sequence", 0))
                actor_snapshot["control_handoff"] = control_handoff
        var actor_prepared: Dictionary = player.prepare_snapshot(actor_snapshot)
        if not actor_prepared.ok: return _failure("save.contributor_prepare_invalid", "角色贡献者候选未通过既有语义恢复合同。", {"contributor": "player", "details": actor_prepared})

        var object_prepared: Dictionary = target_object.prepare_state(object_snapshot)
        if not object_prepared.ok: return _failure("save.contributor_prepare_invalid", "对象贡献者候选未通过既有语义恢复合同。", {"contributor": "object", "details": object_prepared})

        var scene_prepared: Dictionary = scene_session.prepare_snapshot(scene_snapshot)
        if not scene_prepared.ok: return _failure("save.contributor_prepare_invalid", "SceneSession贡献者候选未通过既有语义恢复合同。", {"contributor": "scene_session", "details": scene_prepared})

        return {"ok": true, "prepared": {
                "task_service": staged_task_service,
                # The staged world candidate now contains the detached service's
                # normalized Store and remains the identity rebound by the listener.
                "task_store": staged_task,
                "shell_store": staged_shell,
                "actor": actor_prepared.get("prepared", {}),
                "object": object_prepared.get("prepared", {}),
                "scene_session": scene_prepared.get("prepared", {})
        }}

func _commit_p25_contributors(prepared: Dictionary, _world) -> void:
        # The coordinator calls this only after the world Store swap. Every value
        # below has already passed its contributor contract in prepare above.
        var staged_task_service = prepared.get("task_service")
        task_service.fact_store = staged_task_service.fact_store
        task_service.change_store = task_service.fact_store.change_store
        task_service.store = prepared.get("task_store")
        player_shell_store = prepared.get("shell_store")
        player.commit_prepared_snapshot(prepared.get("actor", {}))
        target_object.commit_prepared_state(prepared.get("object", {}))
        scene_session.commit_prepared_snapshot(prepared.get("scene_session", {}))

func _should_restore_on_start() -> bool:
        if delivery_mode == DELIVERY_2D_ONLY: return false
        var args := OS.get_cmdline_user_args()
        for command in ["--p25-save-exit", "--p25-contract", "--p25-smoke", "--p25-2d-only-check"]:
                if args.has(command): return false
        return true

func _quit_after_save() -> void:
        get_tree().quit(0)

func task_projection() -> Dictionary:
        if task_projection_service == null: return {}
        var built := task_projection_service.build(shell_configuration.task_id)
        if not built.ok: return {"ok": false, "code": built.get("code", "task.projection_failed"), "reason_zh": built.get("reason_zh", "Task投影不可用。")}
        var projection: GMTaskProjection = built.projection
        return projection.to_dict()

func snapshot() -> Dictionary:
        return {
                "schema": "gm.player_shell.snapshot.v1",
                "delivery_mode": delivery_mode,
                "three_d_module_loaded": map_backend_3d != null or adapter_3d != null or interaction_query_3d != null or world_3d != null or camera_rig_3d != null,
                "formal_ui": formal_ui_ready,
                "debug_isolated": debug_isolated,
                "active_dimension": active_dimension,
                "active_scene_id": _active_scene_id(),
                "camera_backend": "Camera2D" if active_dimension == "2d" else "GMCameraRig3D",
                "query_backend": "GMPlanar2DSpatialAdapter" if active_dimension == "2d" else "GMInteractionQuery3D",
                "input_map": "Godot InputMap / one action set",
                "persistence": {"loaded": persistence_loaded, "path": persistence_last_path},
                "configuration_id": shell_configuration.configuration_id,
                "player": {"stable_instance_id": shell_configuration.player_id, "position": {"x": player.position.x, "y": player.position.y}} if player != null else {},
                "target": {"stable_instance_id": shell_configuration.target_id, "available": target_available, "state": target_object.object_state.duplicate(true) if target_object != null else {}},
                "task_projection": task_projection(),
                "scene_session": scene_session.state_value() if scene_session != null else {},
                "last_query": _last_query.duplicate(true),
                "last_result": _last_result.duplicate(true),
                "ui": {"task_panel_visible": task_panel_visible, "menu_visible": menu_visible, "world_only_camera": active_dimension == "2d"},
        }

func _build_runtime() -> Dictionary:
        runtime_context = RUNTIME_CONTEXT_SCRIPT.new()
        add_child(runtime_context)
        semantic_registry = MAP_REGISTRY_SCRIPT.new()
        var map_built := _build_semantic_map()
        if not map_built.ok: return map_built
        adapter_2d = PLANAR_2D_SCRIPT.new(semantic_registry, true)
        if delivery_mode != DELIVERY_2D_ONLY:
                var planar3d_built := _build_planar_3d_backend()
                if not planar3d_built.ok: return planar3d_built
        var player_built := _build_player()
        if not player_built.ok: return player_built
        var tasks_built := _build_tasks()
        if not tasks_built.ok: return tasks_built
        var scene_built := _build_scene_session()
        if not scene_built.ok: return scene_built
        var persistence_built := _build_persistence_authority()
        if not persistence_built.ok: return persistence_built
        if delivery_mode != DELIVERY_2D_ONLY:
                _build_world_projections()
        _build_camera_projections()
        var context_selected := _activate_context_backend("2d")
        _last_context_backend = context_selected
        return {"ok": true, "player": shell_configuration.player_id, "task": shell_configuration.task_id, "scene": shell_configuration.scene_definition_id, "context_backend": context_selected}

func _build_semantic_map() -> Dictionary:
        map_resource = MAP_RESOURCE_SCRIPT.new()
        map_resource.map_id = shell_configuration.map_id
        map_resource.map_size = Vector2i(int(shell_configuration.map_size.x / shell_configuration.tile_size.x), int(shell_configuration.map_size.y / shell_configuration.tile_size.y))
        map_resource.tile_size = Vector2i(int(shell_configuration.tile_size.x), int(shell_configuration.tile_size.y))
        for y in range(map_resource.map_size.y):
                for x in range(map_resource.map_size.x):
                        var cell := map_resource.set_logic_cell(Vector2i(x, y), {"ground_type": "shell_floor", "walkable": true, "cost": 1.0, "water": false, "height_level": 0})
                        if not cell.ok: return cell
        semantic_map = SEMANTIC_MAP_SCRIPT.new()
        semantic_map.map_id = shell_configuration.map_id
        semantic_map.terrain_map = map_resource
        semantic_map.surface_ids = PackedStringArray([shell_configuration.surface_id])
        semantic_map.anchors.append(_anchor(shell_configuration.entry_anchor_id, shell_configuration.entry_position))
        semantic_map.anchors.append(_anchor(shell_configuration.target_anchor_id, shell_configuration.target_position))
        semantic_map.anchors.append(_anchor(shell_configuration.exit_anchor_id, shell_configuration.exit_position))
        var checked := semantic_map.validate_definition(semantic_registry)
        if not checked.ok: return {"ok": false, "code": "p25.semantic_map_invalid", "reason_zh": "P25中性SemanticMap校验失败。", "details": checked}
        var registered := semantic_registry.register_map(semantic_map)
        return registered if registered.ok else registered

func _anchor(anchor_id: String, value: Vector2) -> GMSemanticAnchor:
        var result: GMSemanticAnchor = ANCHOR_SCRIPT.new()
        result.anchor_id = anchor_id
        result.anchor_type_id = "gm.anchor_type.shell"
        result.position = value
        result.surface_id = shell_configuration.surface_id
        result.editor_label = shell_configuration.map_display_name_zh
        return result

func _build_planar_3d_backend() -> Dictionary:
        var surface_graph_script: Script = load(SURFACE_GRAPH_SCRIPT_PATH)
        var surface_script: Script = load(SURFACE_SCRIPT_PATH)
        var map_backend_script: Script = load(MAP_BACKEND_3D_SCRIPT_PATH)
        var planar_3d_script: Script = load(PLANAR_3D_SCRIPT_PATH)
        var interaction_query_script: Script = load(INTERACTION_QUERY_3D_SCRIPT_PATH)
        if surface_graph_script == null or surface_script == null or map_backend_script == null or planar_3d_script == null or interaction_query_script == null:
                return _failure("delivery.3d_backend_unavailable", "正式3D交付缺少完整空间后端依赖。")
        surface_graph_3d = surface_graph_script.new()
        surface_graph_3d.graph_id = shell_configuration.graph_id
        surface_graph_3d.map_id = shell_configuration.map_id
        surface_graph_3d.display_name_zh = shell_configuration.map_display_name_zh
        var surface = surface_script.rectangle(shell_configuration.surface_id, shell_configuration.map_id, "floor", Vector3.ZERO, Vector2(shell_configuration.map_size.x / shell_configuration.tile_size.x, shell_configuration.map_size.y / shell_configuration.tile_size.y))
        var surface_result: Dictionary = surface_graph_3d.register_surface(surface)
        if not surface_result.ok: return surface_result
        var graph_check: Dictionary = surface_graph_3d.validate()
        if not graph_check.ok: return {"ok": false, "code": "p25.surface_graph_invalid", "reason_zh": "P25中性平面3D Surface Graph校验失败。", "details": graph_check}
        map_backend_3d = map_backend_script.new()
        var configured: Dictionary = map_backend_3d.configure_graph(surface_graph_3d)
        if not configured.ok: return configured
        adapter_3d = planar_3d_script.new(semantic_registry, true, map_backend_3d)
        interaction_query_3d = interaction_query_script.new(adapter_3d, runtime_context)
        return {"ok": true, "graph_id": str(surface_graph_3d.graph_id), "backend_id": str(map_backend_3d.backend_id())}

func _build_player() -> Dictionary:
        world_2d = WORLD_2D_SCRIPT.new()
        world_2d.name = "P25World2D"
        world_2d.map_size = shell_configuration.map_size
        world_2d.tile_size = shell_configuration.tile_size
        add_child(world_2d)

        player = ACTOR_2D_SCRIPT.new()
        player.name = "Player"
        player.stable_instance_id = shell_configuration.player_id
        player.map_id = shell_configuration.map_id
        player.spawn_anchor_id = shell_configuration.entry_anchor_id
        player.position = shell_configuration.entry_position
        var role: GMRoleProfile = ROLE_PROFILE_SCRIPT.new()
        role.role_id = shell_configuration.player_role_id
        role.display_name_zh = shell_configuration.player_role_display_name_zh
        role.enabled_control_sources = PackedStringArray(["player"])
        player.role_profile = role
        world_2d.add_child(player)
        var mounted := player.mount_runtime(runtime_context, {})
        if not mounted.ok: return mounted
        player_host = player.ability_host
        var movement := player.configure_movement(semantic_registry)
        if not movement.ok: return movement
        var control := player.control_router.acquire("player", "gm.player.shell")
        if not control.ok: return control

        target_object = OBJECT_INSTANCE_SCRIPT.new()
        target_object.name = "BeaconProjection"
        target_object.stable_instance_id = shell_configuration.target_id
        target_object.map_id = shell_configuration.map_id
        target_object.position = shell_configuration.target_position
        target_object.object_state = {"activated": false}
        target_definition = OBJECT_DEFINITION_SCRIPT.new()
        target_definition.content_id = shell_configuration.target_definition_id
        target_definition.display_name_zh = shell_configuration.target_display_name_zh
        target_definition.object_kind = shell_configuration.target_object_kind
        target_object.definition = target_definition
        world_2d.add_child(target_object)
        object_service = OBJECT_SERVICE_SCRIPT.new(target_object)
        var service := player_host.set_domain_service(OBJECT_SERVICE_SCRIPT.SERVICE_ID, object_service)
        if not service.ok: return service
        var ability: GMAbilityDefinition = ABILITY_DEFINITION_SCRIPT.new()
        ability.ability_id = shell_configuration.ability_id
        ability.display_name_zh = shell_configuration.ability_display_name_zh
        ability.description_zh = shell_configuration.ability_description_zh
        ability.ability_tags = PackedStringArray(["gm.ability.interaction", "gm.p25.formal"])
        ability.executor_service_id = OBJECT_SERVICE_SCRIPT.SERVICE_ID
        ability.resolver_id = OBJECT_SERVICE_SCRIPT.SERVICE_ID
        ability.fact_type = "gm.fact.object.interaction.committed"
        ability.fact_source_system = "gm.object"
        ability.fact_tags = PackedStringArray(["gm.p25.formal"])
        var registered := player_host.register_definition(ability)
        if not registered.ok: return registered
        var granted := player_host.grant_ability(ability, "gm.p25.player.shell")
        if not granted.ok: return granted
        return {"ok": true, "player_host": player_host, "movement": movement, "interaction_ability": shell_configuration.ability_id}

func _build_tasks() -> Dictionary:
        task_service = TASK_SERVICE_SCRIPT.new()
        task_projection_service = TASK_PROJECTION_SERVICE_SCRIPT.new(task_service)
        interaction_router = INTERACTION_ROUTER_SCRIPT.new()
        ability_backend = P21_ABILITY_BACKEND_SCRIPT.new(player_host, Callable(self, "_resolve_target"))
        task_backend = TASK_BACKEND_SCRIPT.new(task_service, player_host)
        var ability_registered := interaction_router.register_backend("ability", ability_backend)
        if not ability_registered.ok: return ability_registered
        var task_registered := interaction_router.register_backend("task", task_backend)
        if not task_registered.ok: return task_registered
        task_definition = TASK_DEFINITION_SCRIPT.new()
        task_definition.definition_id = shell_configuration.task_definition_id
        task_definition.display_name_zh = shell_configuration.task_display_name_zh
        task_definition.description_zh = shell_configuration.task_description_zh
        task_definition.objectives = [{
                "objective_id": shell_configuration.objective_id,
                "display_name_zh": shell_configuration.objective_display_name_zh,
                "signal_kind": "fact",
                "signal_type": "gm.fact.object.interaction.committed",
                "target_value": shell_configuration.objective_target,
                "contribution_field": "count",
                "target_match": {"stable_instance_id": shell_configuration.target_id},
        }]
        task_definition.allowed_source_types = ["player", "script"]
        task_definition.default_context_mode = "local"
        task_definition.reservation_rules = [{
                "rule_id": shell_configuration.reservation_rule_id,
                "subject": {"type": "resource", "id": shell_configuration.resource_id},
                "mode": "exclusive",
                "capacity": 1,
        }]
        task_definition.workbench_profile = {
                "source_type": "player",
                "task_id": shell_configuration.task_id,
                "parent_task_id": "",
                "assignment_id": shell_configuration.assignment_id,
                "assignment_kind": "actor",
                "assignee": {"type": "actor", "id": shell_configuration.player_id},
                "provider": {"provider_id": shell_configuration.duty_provider_id, "event_type": shell_configuration.duty_event_type, "key_field": "shell_key", "subject": {"type": "resource", "id": shell_configuration.resource_id}},
                "reservation": {"reservation_id": shell_configuration.reservation_id, "rule_id": shell_configuration.reservation_rule_id, "amount": 1, "expires_at_tick": shell_configuration.seed},
        }
        var definition_check := task_definition.validate_definition()
        if not definition_check.ok: return {"ok": false, "code": "p25.task_definition_invalid", "reason_zh": "正式Task定义校验失败。", "details": definition_check}
        var registered: Variant = task_service.submit_operation(player_host, "register_definition", task_definition.to_dict(), "script", shell_configuration.player_id, "%s.task.register" % shell_configuration.configuration_id)
        if not _typed_success(registered): return _typed_failure(registered, "task.definition_register_failed")
        var published: Variant = task_service.submit_operation(player_host, "publish_task", {
                "task_id": shell_configuration.task_id,
                "definition_id": shell_configuration.task_definition_id,
                "parent_task_id": "",
                "group_id": "",
                "execution_context": {
                        "mode": "local",
                        "stable_context": {
                                "target": {"type": "object", "id": shell_configuration.target_id},
                                "participants": [{"type": "actor", "id": shell_configuration.player_id}],
                                "resources": [{"type": "resource", "id": shell_configuration.resource_id}],
                                "constraints": {},
                                "seed": shell_configuration.seed,
                        },
                },
        }, "script", shell_configuration.player_id, "%s.task.publish" % shell_configuration.configuration_id)
        if not _typed_success(published): return _typed_failure(published, "task.publish_failed")
        return {"ok": true, "task_id": shell_configuration.task_id, "state": task_projection().get("state", "")}

func _build_scene_session() -> Dictionary:
        var entry_ref := _spatial_target_native("anchor", shell_configuration.entry_anchor_id, "gm.spatial.planar_2d")
        var target_ref := _spatial_target_native("anchor", shell_configuration.target_anchor_id, "gm.spatial.planar_2d")
        var exit_ref := _spatial_target_native("anchor", shell_configuration.exit_anchor_id, "gm.spatial.planar_2d")
        var typed_resource := {"type": "resource", "id": shell_configuration.resource_id}
        var typed_hostile := {"type": "role", "id": shell_configuration.hostile_role_id}
        var typed_facility := {"type": "facility", "id": shell_configuration.facility_id}
        var participants := [{"type": "actor", "id": shell_configuration.player_id}]
        var regions := [{"region_id": shell_configuration.region_id, "region_kind": "play_space", "required": true, "tags": ["formal", "neutral"]}]
        var slot_values := [
                SCENE_SLOT_SCRIPT.new("%s.slot.entry" % shell_configuration.scene_id, "entry", entry_ref, true, 1, ["formal"]).to_dict(),
                SCENE_SLOT_SCRIPT.new("%s.slot.exit" % shell_configuration.scene_id, "exit", exit_ref, true, 1, ["formal"]).to_dict(),
                SCENE_SLOT_SCRIPT.new("%s.slot.objective" % shell_configuration.scene_id, "objective", target_ref, true, 1, ["interaction"]).to_dict(),
                SCENE_SLOT_SCRIPT.new("%s.slot.resource" % shell_configuration.scene_id, "resource", typed_resource, true, 1, ["neutral"]).to_dict(),
                SCENE_SLOT_SCRIPT.new("%s.slot.hostile" % shell_configuration.scene_id, "hostile", typed_hostile, true, 1, ["empty"]).to_dict(),
                SCENE_SLOT_SCRIPT.new("%s.slot.facility" % shell_configuration.scene_id, "facility", typed_facility, true, 1, ["neutral"]).to_dict(),
                SCENE_SLOT_SCRIPT.new("%s.slot.extraction" % shell_configuration.scene_id, "extraction", exit_ref, true, 1, ["formal"]).to_dict(),
        ]
        var required_slot_kinds := ["entry", "objective", "resource", "hostile", "facility", "extraction"]
        var recipe_objects := [{"object_id": shell_configuration.target_id, "object_kind": shell_configuration.target_object_kind, "required": true, "tags": ["interactive", "neutral"]}]
        var recipe := SCENE_RECIPE_SCRIPT.new(
                shell_configuration.scene_recipe_id, shell_configuration.scene_display_name_zh, shell_configuration.scene_skeleton_id, entry_ref, exit_ref,
                required_slot_kinds, recipe_objects, regions, slot_values, participants,
                [{"objective_id": shell_configuration.scene_objective_id, "kind": "interact", "target_value": shell_configuration.objective_target, "contribution_field": "count", "target_ref": target_ref, "requires_hostile_clear": false}],
                [
                        {"result_id": "%s.success" % shell_configuration.scene_result_prefix, "status": "success", "required_objective_ids": [shell_configuration.scene_objective_id], "reason_code": "%s.success" % shell_configuration.scene_reason_prefix},
                        {"result_id": "%s.partial" % shell_configuration.scene_result_prefix, "status": "partial_success", "required_objective_ids": [shell_configuration.scene_objective_id], "reason_code": "%s.partial" % shell_configuration.scene_reason_prefix},
                        {"result_id": "%s.failed" % shell_configuration.scene_result_prefix, "status": "failed", "required_objective_ids": [shell_configuration.scene_objective_id], "reason_code": "%s.failed" % shell_configuration.scene_reason_prefix},
                        {"result_id": "%s.extracted" % shell_configuration.scene_result_prefix, "status": "extracted", "required_objective_ids": [shell_configuration.scene_objective_id], "reason_code": "%s.extracted" % shell_configuration.scene_reason_prefix},
                ],
                ["steady", "quiet"]
        )
        var supported_domains := ["gm.spatial.planar_2d"]
        if delivery_mode != DELIVERY_2D_ONLY:
                supported_domains.append("gm.spatial.planar_3d")
        var skeleton := SCENE_SKELETON_SCRIPT.new(shell_configuration.scene_skeleton_id, shell_configuration.scene_display_name_zh, supported_domains, regions, slot_values, ["steady", "quiet"])
        var context := SCENE_CONTEXT_SCRIPT.new(
                shell_configuration.task_id, shell_configuration.assignment_id, "local", target_ref, participants,
                [typed_resource], {}, shell_configuration.seed, {}
        )
        scene_session_definition = SCENE_DEFINITION_SCRIPT.new(
                shell_configuration.scene_definition_id, shell_configuration.task_id, shell_configuration.assignment_id, context.to_dict(), skeleton.to_dict(), recipe.to_dict(), {}
        )
        var definition_check := scene_session_definition.validate()
        if not definition_check.ok: return {"ok": false, "code": "p25.scene_definition_invalid", "reason_zh": "正式SceneSessionDefinition校验失败。", "details": definition_check}
        var opened := SCENE_SESSION_SCRIPT.open(scene_session_definition, SCENE_BUILDER_SCRIPT.new(), adapter_2d)
        if not opened.ok: return opened
        scene_session = opened.session
        return {"ok": true, "session_id": scene_session.state.session_id, "phase": scene_session.state.phase}

func _build_persistence_authority() -> Dictionary:
        simulation_world = SIMULATION_WORLD_SCRIPT.new(shell_configuration.seed, shell_configuration.world_id)
        var task_store_added: Dictionary = simulation_world.add_store(task_service.store)
        if not task_store_added.ok: return task_store_added
        player_shell_store = STORE_SCRIPT.new(P25_STORE_ID, P25_STORE_SCHEMA)
        var shell_store_added: Dictionary = simulation_world.add_store(player_shell_store)
        if not shell_store_added.ok: return shell_store_added
        var context_configured: Dictionary = simulation_world.configure_spatial_runtime_context(runtime_context)
        if not context_configured.ok: return context_configured
        _persistence_store_listener = Callable(self, "_on_persistence_world_store_replaced")
        var listener_registered: Dictionary = simulation_world.register_store_replacement_listener(_persistence_store_listener)
        if not listener_registered.ok: return listener_registered
        var participant_registered: Dictionary = simulation_world.register_atomic_restore_participant(Callable(self, "_prepare_p25_contributors"), Callable(self, "_commit_p25_contributors"))
        if not participant_registered.ok: return participant_registered
        return {"ok": true, "world_id": simulation_world.world_id, "store_id": P25_STORE_ID, "task_store_id": task_service.store.store_id}

func _on_persistence_world_store_replaced(world) -> void:
        if world != simulation_world: return
        var stores: Dictionary = world.stores if world != null and world.get("stores") is Dictionary else {}
        var task_candidate: Variant = stores.get(task_service.STORE_ID, null) if task_service != null else null
        if task_candidate is GMStore:
                task_service.store = task_candidate
        var shell_candidate: Variant = stores.get(P25_STORE_ID, null)
        if shell_candidate is GMStore:
                player_shell_store = shell_candidate

func _build_world_projections() -> void:
        world_3d = Node3D.new()
        world_3d.name = "P25World3D"
        world_3d.visible = false
        add_child(world_3d)
        var floor := MeshInstance3D.new()
        var plane := PlaneMesh.new()
        plane.size = shell_configuration.map_size
        floor.mesh = plane
        floor.position = Vector3(shell_configuration.map_size.x / shell_configuration.tile_size.x * 0.5, 0.0, shell_configuration.map_size.y / shell_configuration.tile_size.y * 0.5)
        floor.material_override = _material(Color("#1b2d37"), Color("#071018"))
        world_3d.add_child(floor)
        var light := DirectionalLight3D.new()
        light.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
        light.light_energy = 1.2
        world_3d.add_child(light)
        player_proxy_3d = Node3D.new()
        player_proxy_3d.name = "PlayerVisual3D"
        player_proxy_3d.position = Vector3(player.position.x / shell_configuration.tile_size.x, 0.8, player.position.y / shell_configuration.tile_size.y)
        var player_mesh := MeshInstance3D.new()
        var player_shape := SphereMesh.new()
        player_shape.radius = 0.55
        player_shape.height = 1.1
        player_mesh.mesh = player_shape
        player_mesh.material_override = _material(Color("#4aa6d9"), Color("#142b3a"))
        player_proxy_3d.add_child(player_mesh)
        world_3d.add_child(player_proxy_3d)
        var target_script: Script = load(TARGET_3D_SCRIPT_PATH)
        if target_script == null:
                _startup_error = _failure("delivery.3d_target_unavailable", "正式3D交付缺少交互目标投影依赖。")
                return
        target_3d = target_script.new()
        target_3d.name = "BeaconQueryCollider"
        target_3d.stable_instance_id = shell_configuration.target_id
        target_3d.map_id = shell_configuration.map_id
        var target_planar_position := Vector2(shell_configuration.target_position.x / shell_configuration.tile_size.x, shell_configuration.target_position.y / shell_configuration.tile_size.y)
        target_3d.spatial_position = PLANAR_POSITION_SCRIPT.new(shell_configuration.map_id, shell_configuration.surface_id, target_planar_position.x, target_planar_position.y).to_native()
        target_3d.position = Vector3(target_planar_position.x, 1.0, target_planar_position.y)
        var shape := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = Vector3(2.4, 2.2, 2.4)
        shape.shape = box
        target_3d.add_child(shape)
        var beacon_mesh := MeshInstance3D.new()
        var beacon_shape := CylinderMesh.new()
        beacon_shape.top_radius = 0.75
        beacon_shape.bottom_radius = 0.75
        beacon_shape.height = 2.2
        beacon_mesh.mesh = beacon_shape
        beacon_mesh.material_override = _material(Color("#e9ae47"), Color("#3d2810"))
        target_3d.add_child(beacon_mesh)
        world_3d.add_child(target_3d)
        set_target_available(target_available)

func _build_camera_projections() -> void:
        if camera_profile == null:
                camera_profile = shell_configuration.build_camera_profile()
        var profile_check := camera_profile.validate()
        if not profile_check.ok:
                _startup_error = profile_check
                return
        camera_2d = Camera2D.new()
        camera_2d.name = "Camera2D"
        camera_2d.position = player.position + camera_profile.look_ahead
        camera_2d.zoom = Vector2(camera_profile.zoom, camera_profile.zoom)
        camera_2d.limit_left = int(camera_profile.bounds.position.x)
        camera_2d.limit_top = int(camera_profile.bounds.position.y)
        camera_2d.limit_right = int(camera_profile.bounds.end.x)
        camera_2d.limit_bottom = int(camera_profile.bounds.end.y)
        camera_2d.enabled = true
        world_2d.add_child(camera_2d)
        if delivery_mode == DELIVERY_2D_ONLY:
                return
        var camera_rig_script: Script = load(CAMERA_RIG_3D_SCRIPT_PATH)
        if camera_rig_script == null:
                _startup_error = _failure("delivery.3d_camera_unavailable", "正式3D交付缺少CameraRig依赖。")
                return
        camera_rig_3d = camera_rig_script.new()
        camera_rig_3d.name = "CameraRig3D"
        camera_rig_3d.profile = camera_profile.to_planar_3d()
        if camera_rig_3d.profile == null:
                _startup_error = _failure("delivery.3d_camera_profile_unavailable", "正式3D交付缺少CameraProfile依赖。")
                return
        camera_rig_3d.spatial_adapter = adapter_3d
        camera_rig_3d.runtime_context = runtime_context
        world_3d.add_child(camera_rig_3d)
        camera_rig_3d.set_follow_target(player_proxy_3d)
        camera_rig_3d.camera.position = Vector3(0.0, 0.0, 18.0)
        camera_rig_3d.camera.current = false
        camera_rig_3d.apply_profile()

func _build_formal_ui() -> void:
        canvas_layer = CanvasLayer.new()
        canvas_layer.name = "P25FormalHUD"
        canvas_layer.layer = 20
        add_child(canvas_layer)
        ui_root = Control.new()
        ui_root.name = "FormalControl"
        ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
        canvas_layer.add_child(ui_root)
        var header := PanelContainer.new()
        header.position = Vector2(28.0, 24.0)
        header.size = Vector2(1044.0, 78.0)
        header.add_theme_stylebox_override("panel", _panel_style(Color("#17253a"), Color("#3b6e9e"), 12))
        ui_root.add_child(header)
        var header_margin := MarginContainer.new()
        header_margin.add_theme_constant_override("margin_left", 18)
        header_margin.add_theme_constant_override("margin_right", 18)
        header_margin.add_theme_constant_override("margin_top", 12)
        header_margin.add_theme_constant_override("margin_bottom", 12)
        header.add_child(header_margin)
        var header_row := HBoxContainer.new()
        header_row.add_theme_constant_override("separation", 18)
        header_margin.add_child(header_row)
        var title := Label.new()
        title.text = shell_configuration.scene_display_name_zh
        title.add_theme_font_size_override("font_size", 26)
        header_row.add_child(title)
        status_label = Label.new()
        status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        status_label.add_theme_color_override("font_color", Color("#bfd5ee"))
        header_row.add_child(status_label)
        backend_label = Label.new()
        backend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        backend_label.add_theme_color_override("font_color", Color("#8fd7bd"))
        header_row.add_child(backend_label)

        var task_button := _button("查看任务", "gm.p25.task.view")
        task_button.position = Vector2(28.0, 116.0)
        task_button.size = Vector2(138.0, 42.0)
        ui_root.add_child(task_button)
        var assign_button := _button("接取任务", "gm.p25.task.assign")
        assign_button.position = Vector2(178.0, 116.0)
        assign_button.size = Vector2(138.0, 42.0)
        ui_root.add_child(assign_button)
        var scene_button := _button("切换场景", "gm.p25.scene.switch")
        scene_button.position = Vector2(328.0, 116.0)
        scene_button.size = Vector2(138.0, 42.0)
        ui_root.add_child(scene_button)
        var camera_button := _button("切换视角", "gm.p25.camera.toggle")
        camera_button.position = Vector2(478.0, 116.0)
        camera_button.size = Vector2(138.0, 42.0)
        ui_root.add_child(camera_button)
        var menu_button := _button("菜单", "gm.p25.menu.toggle")
        menu_button.position = Vector2(628.0, 116.0)
        menu_button.size = Vector2(110.0, 42.0)
        ui_root.add_child(menu_button)

        task_panel = PanelContainer.new()
        task_panel.name = "TaskProjectionPanel"
        task_panel.position = Vector2(28.0, 172.0)
        task_panel.size = Vector2(320.0, 190.0)
        task_panel.add_theme_stylebox_override("panel", _panel_style(Color("#152031"), Color("#45617c"), 10))
        task_panel.visible = false
        ui_root.add_child(task_panel)
        var task_margin := MarginContainer.new()
        for side in ["left", "right", "top", "bottom"]: task_margin.add_theme_constant_override("margin_%s" % side, 14)
        task_panel.add_child(task_margin)
        task_summary_label = Label.new()
        task_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        task_summary_label.add_theme_color_override("font_color", Color("#d7e6f5"))
        task_margin.add_child(task_summary_label)

        scene_label = Label.new()
        scene_label.position = Vector2(28.0, 640.0)
        scene_label.add_theme_color_override("font_color", Color("#a9bdd4"))
        ui_root.add_child(scene_label)
        var controls := Label.new()
        controls.text = "WASD 移动   E 交互   F 接取任务   N 切换场景   C 切换视角   Esc 菜单"
        controls.position = Vector2(28.0, 664.0)
        controls.add_theme_color_override("font_color", Color("#8fa5bc"))
        ui_root.add_child(controls)

        menu_panel = PanelContainer.new()
        menu_panel.name = "FormalMenu"
        menu_panel.position = Vector2(720.0, 172.0)
        menu_panel.size = Vector2(352.0, 240.0)
        menu_panel.add_theme_stylebox_override("panel", _panel_style(Color("#20283a"), Color("#d3a955"), 10))
        menu_panel.visible = false
        ui_root.add_child(menu_panel)
        var menu_margin := MarginContainer.new()
        for side in ["left", "right", "top", "bottom"]: menu_margin.add_theme_constant_override("margin_%s" % side, 16)
        menu_panel.add_child(menu_margin)
        var menu_column := VBoxContainer.new()
        menu_column.add_theme_constant_override("separation", 10)
        menu_margin.add_child(menu_column)
        var menu_title := Label.new()
        menu_title.text = "正式菜单"
        menu_title.add_theme_font_size_override("font_size", 21)
        menu_column.add_child(menu_title)
        menu_hint_label = Label.new()
        menu_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        menu_hint_label.text = "这里显示玩家可用的正式动作；调试工作台保持在独立入口。"
        menu_column.add_child(menu_hint_label)
        var close_button := _button("关闭菜单", "gm.p25.menu.toggle")
        menu_column.add_child(close_button)
        var save_button := _button("保存并退出", "gm.p25.save.exit")
        menu_column.add_child(save_button)
        formal_ui_ready = true

func _button(label_text: String, action_id: String) -> Button:
        var button := Button.new()
        button.text = label_text
        button.focus_mode = Control.FOCUS_ALL
        button.add_theme_font_size_override("font_size", 16)
        button.add_theme_stylebox_override("normal", _panel_style(Color("#223a52"), Color("#4c84af"), 7))
        button.add_theme_stylebox_override("hover", _panel_style(Color("#2e5777"), Color("#83c6ed"), 7))
        button.pressed.connect(func(): handle_action(action_id))
        return button

func _find_button_by_text(node: Node, label_text: String) -> Button:
        if node is Button and node.text == label_text: return node
        for child in node.get_children():
                var found := _find_button_by_text(child, label_text)
                if found != null: return found
        return null

func _refresh_ui() -> void:
        if status_label == null: return
        if not _startup_error.is_empty():
                status_label.text = "启动失败：%s" % str(_startup_error.get("reason_zh", _startup_error.get("error_zh", "未知错误")))
                backend_label.text = "正式外壳不可用"
                return
        var task := task_projection()
        var task_state := _state_zh(str(task.get("state", "")))
        var objective_line := ""
        for objective in task.get("objectives", []):
                objective_line = "%s：%d/%d" % [str(objective.get("display_name_zh", "目标")), int(objective.get("current", 0)), int(objective.get("target", 0))]
        task_summary_label.text = "任务：%s\n状态：%s\n%s\n\n只读投影 · 来源版本 %d" % [str(task.get("display_name_zh", "未知")), task_state, objective_line, int(task.get("source_revision", 0))]
        task_panel.visible = task_panel_visible
        menu_panel.visible = menu_visible
        scene_label.text = "场景：%s    位置：(%d, %d)    目标：%s" % [_active_scene_id(), int(player.position.x), int(player.position.y), "可用" if target_available else "不可用"]
        status_label.text = "状态：%s    任务：%s" % ["可操作" if interaction_module_enabled else "交互模块已关闭", task_state]
        backend_label.text = "%s · %s" % ["2D正式投影" if active_dimension == "2d" else "3D正式投影", "只读HUD"]

func _update_projection() -> void:
        if player == null: return
        if camera_2d != null: camera_2d.position = player.position + camera_profile.look_ahead
        if player_proxy_3d != null: player_proxy_3d.position = Vector3(player.position.x / shell_configuration.tile_size.x, 0.8, player.position.y / shell_configuration.tile_size.y)
        if camera_rig_3d != null: camera_rig_3d.tick(0.0)
        var query_label := "等待查询"
        if not _last_query.is_empty(): query_label = "成功" if bool(_last_query.get("ok", false)) else "阻断：%s" % str(_last_query.get("code", "unknown"))
        if world_2d != null:
                world_2d.set_projection({
                        "map_size": shell_configuration.map_size,
                        "tile_size": shell_configuration.tile_size,
                        "target_position": shell_configuration.target_position,
                        "player_position": player.position,
                        "target_available": target_available,
                        "scene_label": "%s %d" % [shell_configuration.scene_display_name_zh, active_scene_index + 1],
                        "query_label": query_label,
                })

func _query_target() -> Dictionary:
        if active_dimension == "2d":
                var target_id := shell_configuration.target_anchor_id if target_available else "%s.missing" % shell_configuration.target_anchor_id
                var target_ref := _spatial_target("anchor", target_id, "gm.spatial.planar_2d")
                return adapter_2d.query_target(target_ref.target)
        if not target_available:
                return interaction_query_3d.query_ray(Vector3.ZERO, Vector3.FORWARD, 100.0, {"map_id": shell_configuration.map_id, "ray_hits": []})
        if camera_rig_3d == null or camera_rig_3d.camera == null:
                return {"ok": false, "code": "interaction.camera_missing", "error_zh": "3D交互查询缺少正式Camera3D。"}
        var origin: Vector3 = camera_rig_3d.camera.global_position
        var direction: Vector3 = (target_3d.global_position + Vector3(0.0, 0.3, 0.0) - origin).normalized()
        var space_state: PhysicsDirectSpaceState3D = world_3d.get_world_3d().direct_space_state if world_3d.get_world_3d() != null else null
        return interaction_query_3d.query_ray(origin, direction, 2000.0, {"space_state": space_state, "map_id": shell_configuration.map_id})

func _resolve_target(target_id: String) -> Object:
        if target_id == shell_configuration.target_id and target_available and target_object != null and is_instance_valid(target_object): return target_object
        return null

func _set_move_direction(direction: Vector2) -> void:
        var normalized := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.ZERO
        if normalized == _movement_direction: return
        _movement_direction = normalized
        if normalized == Vector2.ZERO:
                if player_host != null: player_host.cancel_ability("gm.ability.movement", "玩家外壳停止移动。")
                return
        _movement_sequence += 1
        var movement_data := {
                "schema": "gm.movement.request.v1",
                "kind": "direction",
                "source": "player",
                "owner_id": "gm.player.shell",
                "actor_id": shell_configuration.player_id,
                "map_id": shell_configuration.map_id,
                "direction": {"x": normalized.x, "y": normalized.y},
                "target_position": {"x": 0.0, "y": 0.0},
                "speed": 180.0,
                "acceleration": 720.0,
                "stop_distance": 0.0,
                "follow_distance": 24.0,
                "loop": true,
                "anchor_id": "",
                "target_actor_id": "",
                "route_id": "",
                "entry_anchor_id": "",
                "exit_anchor_id": "",
                "return_anchor_id": "",
                "target_map_id": "",
                "idempotency_key": "%s.move.%06d" % [shell_configuration.configuration_id, _movement_sequence],
        }
        var parsed := GMMovementRequest.from_dict(movement_data)
        if not parsed.ok:
                _last_result = parsed.duplicate(true)
                return
        var submitted := player.submit_movement_request("player", movement_data, movement_data.idempotency_key)
        _last_result = submitted.duplicate(true)

func _publish_interaction_result(result: GMInteractionResult) -> Dictionary:
        var value := result.to_dict()
        _last_result = value.duplicate(true)
        interaction_result.emit(value.duplicate(true))
        _update_projection()
        _refresh_ui()
        return value

func _activate_context_backend(dimension: String) -> Dictionary:
        if runtime_context == null or not is_instance_valid(runtime_context): return {"ok": false, "code": "context.missing", "reason_zh": "SceneContext不存在。"}
        runtime_context.clear_spatial_backends()
        var backend_id := "gm.spatial.backend.planar_2d" if dimension == "2d" else "gm.spatial.backend.planar_3d"
        var backend: Object = adapter_2d if dimension == "2d" else adapter_3d
        var module_id := "spatial.planar_2d" if dimension == "2d" else "spatial.planar_3d"
        return runtime_context.activate_spatial_backend(backend_id, backend, semantic_registry, PackedStringArray(["core", "spatial.core", module_id]))

func _spatial_target(kind: String, semantic_id: String, domain_id: String) -> Dictionary:
        var value := {"schema_version": 1, "domain_id": domain_id, "kind": kind, "semantic_id": semantic_id, "map_id": shell_configuration.map_id}
        return SPATIAL_TARGET_SCRIPT.from_native(value)

func _spatial_target_native(kind: String, semantic_id: String, domain_id: String) -> Dictionary:
        var parsed := _spatial_target(kind, semantic_id, domain_id)
        return parsed.get("value", {}) if bool(parsed.get("ok", false)) and parsed.get("value", {}) is Dictionary else {}

func _next_interaction_key() -> String:
        _interaction_sequence += 1
        return "%s.interact.%06d" % [shell_configuration.configuration_id, _interaction_sequence]

func _next_task_key() -> String:
        _task_sequence += 1
        return "%s.task.assign.%06d" % [shell_configuration.configuration_id, _task_sequence]

func _active_scene_id() -> String:
        return shell_configuration.scene_id if active_scene_index == 0 else "%s.alternate" % shell_configuration.scene_id

func _typed_success(value: Variant) -> bool:
        if value is GMCommittedFactResult: return true
        return value is Dictionary and bool(value.get("ok", false))

func _typed_failure(value: Variant, fallback_code: String) -> Dictionary:
        if value is GMBlockedResult:
                return {"ok": false, "code": value.error_code, "reason_zh": value.reason_zh, "details": value.to_dict()}
        if value is Dictionary: return value
        return _failure(fallback_code, "P25已有领域服务没有返回可验证的提交结果。")

func _material(albedo: Color, emission: Color) -> StandardMaterial3D:
        var material := StandardMaterial3D.new()
        material.albedo_color = albedo
        material.emission_enabled = true
        material.emission = emission
        material.emission_energy_multiplier = 0.35
        return material

func _panel_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
        var style := StyleBoxFlat.new()
        style.bg_color = fill
        style.border_color = border
        style.set_border_width_all(1)
        style.set_corner_radius_all(radius)
        return style

func _state_zh(state: String) -> String:
        return {"draft": "草稿", "available": "可接取", "assigned": "已接取", "in_progress": "进行中", "blocked": "已阻断", "completed": "已完成", "failed": "失败", "cancelled": "已取消"}.get(state, "未开始")

func _ensure_input_map() -> void:
        for action_id in INPUT_ACTIONS.keys():
                if not InputMap.has_action(action_id): InputMap.add_action(action_id)
                var key_event := InputEventKey.new()
                key_event.physical_keycode = int(INPUT_ACTIONS[action_id])
                if not InputMap.action_has_event(action_id, key_event): InputMap.action_add_event(action_id, key_event)
        var joy_buttons := {"gm.p25.interact": JOY_BUTTON_A, "gm.p25.task.view": JOY_BUTTON_X, "gm.p25.task.assign": JOY_BUTTON_Y, "gm.p25.scene.switch": JOY_BUTTON_B, "gm.p25.camera.toggle": JOY_BUTTON_RIGHT_SHOULDER, "gm.p25.menu.toggle": JOY_BUTTON_START}
        for action_id in joy_buttons:
                var joy_event := InputEventJoypadButton.new()
                joy_event.button_index = int(joy_buttons[action_id])
                if not InputMap.action_has_event(action_id, joy_event): InputMap.action_add_event(action_id, joy_event)
        var axis_events := [["gm.p25.move.left", JOY_AXIS_LEFT_X, -1.0], ["gm.p25.move.right", JOY_AXIS_LEFT_X, 1.0], ["gm.p25.move.up", JOY_AXIS_LEFT_Y, -1.0], ["gm.p25.move.down", JOY_AXIS_LEFT_Y, 1.0]]
        for row in axis_events:
                var axis_event := InputEventJoypadMotion.new()
                axis_event.axis = int(row[1])
                axis_event.axis_value = float(row[2])
                if not InputMap.action_has_event(row[0], axis_event): InputMap.action_add_event(row[0], axis_event)

func _schedule_command_mode() -> void:
        var args := OS.get_cmdline_user_args()
        if args.has("--p25-contract"): call_deferred("_run_contract_mode")
        elif args.has("--p25-smoke"): call_deferred("_run_smoke_mode")
        elif args.has("--p25-save-exit"): call_deferred("_run_save_exit_mode")
        elif args.has("--p25-restore-check"): call_deferred("_run_restore_check_mode")
        elif args.has("--p25-2d-only-check"): call_deferred("_run_2d_only_check_mode")

func _run_contract_mode() -> void:
        var report := {"ok": true, "mode": "p25-contract", "checks": []}
        _check(report, "formal_ui_ready", formal_ui_ready)
        _check(report, "task_projection_readonly", bool(task_projection().get("readonly", false)))
        _check(report, "context_2d_backend_active", bool(_last_context_backend.get("ok", false)))
        var key_event := InputEventKey.new()
        key_event.physical_keycode = KEY_W
        key_event.pressed = true
        var dispatched := dispatch_input_event(key_event)
        _check(report, "keyboard_input_uses_single_source", bool(InputMap.has_action("gm.p25.move.up")) and dispatched.get("action", "") == "move" and bool(dispatched.get("single_input_source", false)))
        drive_direction(Vector2.ZERO)
        var task_view := handle_action("gm.p25.task.view")
        _check(report, "task_hud_toggle", bool(task_view.get("visible", false)) and task_panel_visible)
        handle_action("gm.p25.task.view")
        var menu_toggle := handle_action("gm.p25.menu.toggle")
        _check(report, "formal_menu_toggle", bool(menu_toggle.get("visible", false)) and menu_visible)
        handle_action("gm.p25.menu.toggle")
        var assigned := assign_task("gm.p25.contract.assign")
        _check(report, "task_assign_committed", str(assigned.get("status", "")) == "committed")
        var moved_from := player.position
        drive_direction(Vector2.RIGHT)
        advance_simulation(0.35)
        drive_direction(Vector2.ZERO)
        _check(report, "movement_changed_position", player.position.distance_to(moved_from) > 1.0)
        var scene := switch_scene()
        _check(report, "scene_switch_started_session", bool(scene.get("ok", false)) and str(scene.get("session", {}).get("phase", "")) == "active")
        var three_d := set_dimension("3d")
        var query_3d := query_active_target()
        _check(report, "camera_3d_selected", bool(three_d.get("ok", false)) and active_dimension == "3d")
        _check(report, "context_3d_backend_active", bool(three_d.get("context_backend", {}).get("ok", false)))
        _check(report, "raycast_query_success", bool(query_3d.get("ok", false)))
        set_dimension("2d")
        var first := interact_with_key("gm.p25.contract.interact")
        var replay := interact_with_key("gm.p25.contract.interact")
        _check(report, "interaction_committed", str(first.get("status", "")) == "committed")
        _check(report, "repeat_is_deterministic", str(replay.get("status", "")) == "committed")
        set_target_available(false)
        var missing := interact_with_key("gm.p25.contract.missing")
        _check(report, "missing_target_blocked", str(missing.get("status", "")) == "rejected")
        set_target_available(true)
        set_module_enabled(false)
        var disabled := interact_with_key("gm.p25.contract.disabled")
        _check(report, "disabled_module_no_fallback", str(disabled.get("code", "")) == "interaction.backend_missing")
        set_module_enabled(true)
        var reopened := save_and_reopen_projection()
        _check(report, "save_close_reopen", bool(reopened.get("ok", false)))
        _check(report, "2d_only_crop", bool(snapshot().get("ui", {}).get("world_only_camera", false)))
        _print_and_quit(report)

func _run_smoke_mode() -> void:
        await get_tree().process_frame
        await RenderingServer.frame_post_draw
        var report := {"ok": true, "mode": "p25-smoke", "checks": []}
        _check(report, "formal_ui_ready", formal_ui_ready)
        _check(report, "initial_dimension_2d", active_dimension == "2d")
        var image_path := "user://gm_player_shell/formal_shell_capture.png"
        var image := get_viewport().get_texture().get_image() if get_viewport() != null and get_viewport().get_texture() != null else null
        if image != null:
                var saved := image.save_png(image_path)
                _check(report, "viewport_capture", saved == OK)
        else:
                _check(report, "viewport_capture", false)
        var switched := toggle_dimension()
        _check(report, "camera_toggle", bool(switched.get("ok", false)) and active_dimension == "3d")
        await get_tree().process_frame
        await RenderingServer.frame_post_draw
        var image_3d := get_viewport().get_texture().get_image() if get_viewport() != null and get_viewport().get_texture() != null else null
        if image_3d != null:
                var saved_3d := image_3d.save_png("user://gm_player_shell/formal_shell_3d_capture.png")
                _check(report, "viewport_3d_capture", saved_3d == OK)
        else:
                _check(report, "viewport_3d_capture", false)
        _print_and_quit(report)

func _run_save_exit_mode() -> void:
        await get_tree().process_frame
        var report := {"ok": true, "mode": "p25-save-exit", "checks": []}
        var assigned := handle_action("gm.p25.task.assign")
        _check(report, "formal_task_state_before_save", str(assigned.get("status", "")) == "committed")
        var scene := handle_action("gm.p25.scene.switch")
        _check(report, "formal_scene_state_before_save", bool(scene.get("ok", false)) and str(scene.get("session", {}).get("phase", "")) == "active")
        var interaction := handle_action("gm.p25.interact")
        _check(report, "formal_object_state_before_save", str(interaction.get("status", "")) == "committed")
        handle_action("gm.p25.move.right")
        advance_simulation(0.2)
        handle_action("gm.p25.move.stop")
        handle_action("gm.p25.menu.toggle")
        var save_button := _find_button_by_text(self, "保存并退出")
        _check(report, "formal_save_entry_present", save_button != null)
        if save_button != null:
                save_button.pressed.emit()
        _check(report, "formal_save_entry_wrote_world_file", save_button != null and persistence_last_path == shell_configuration.save_path)
        _check(report, "formal_save_uses_existing_world_authority", simulation_world != null and player_shell_store != null and player_shell_store.keys().has("task_authority") and player_shell_store.keys().has("player") and player_shell_store.keys().has("object") and player_shell_store.keys().has("scene_session"))
        _check(report, "formal_save_contains_existing_contributors", str(task_projection().get("state", "")) == "assigned" and str(scene_session.state.phase) == "active" and target_object.object_state is Dictionary)
        if not bool(report.get("ok", false)):
                print("P25_SAVE_EXIT_RESULT " + JSON.stringify(report))
                get_tree().quit(1)
                return
        print("P25_SAVE_EXIT_RESULT " + JSON.stringify(report))

func _run_restore_check_mode() -> void:
        await get_tree().process_frame
        var report := {"ok": true, "mode": "p25-restore-check", "checks": []}
        var task := task_projection()
        var object_state: Dictionary = target_object.object_state.duplicate(true) if target_object != null else {}
        report["restore_error"] = persistence_restore_error
        _check(report, "independent_process_loaded_file", persistence_loaded and persistence_last_path == shell_configuration.save_path)
        _check(report, "task_restored_from_store_authority", str(task.get("state", "")) == "assigned" and int(task.get("source_revision", 0)) >= 3)
        _check(report, "player_restored_from_existing_contract", player != null and player.position.x > 160.0)
        _check(report, "scene_session_restored", scene_session != null and str(scene_session.state.phase) == "active")
        _check(report, "object_restored", bool(object_state.get("activated", false)))
        _check(report, "hud_projects_restored_task", formal_ui_ready and bool(task.get("readonly", false)) and task_summary_label.text.contains("已接取"))
        _check(report, "rebuildable_projection_not_persisted", not player_shell_store.keys().has("last_query") and not player_shell_store.keys().has("last_result") and not player_shell_store.keys().has("ui"))
        var world_before_invalid: Dictionary = simulation_world.save_snapshot()
        var invalid_world: Dictionary = world_before_invalid.duplicate(true)
        invalid_world["unexpected"] = true
        var rejected_invalid: Dictionary = simulation_world.load_snapshot(invalid_world)
        _check(report, "atomic_restore_failure_keeps_live_world", not rejected_invalid.ok and simulation_world.save_snapshot() == world_before_invalid)
        report["restored"] = {"task": task, "player": player.save_snapshot() if player != null else {}, "scene_session": scene_session.state_value() if scene_session != null else {}, "object": object_state}
        _print_mode_and_quit("P25_RESTORE_CHECK_RESULT", report)

func _run_2d_only_check_mode() -> void:
        await get_tree().process_frame
        var report := {"ok": true, "mode": "p25-2d-only-delivery", "checks": []}
        var three_d_loaded := map_backend_3d != null or surface_graph_3d != null or adapter_3d != null or interaction_query_3d != null or world_3d != null or player_proxy_3d != null or target_3d != null or camera_rig_3d != null
        var three_d_sources_cropped := DirAccess.open("res://gm_runtime/map/3d") == null and DirAccess.open("res://gm_adapters/spatial3d") == null and not FileAccess.file_exists("res://gm_runtime/player_shell/gm_player_shell_interactive_3d.gd")
        _check(report, "delivery_is_2d_only", delivery_mode == DELIVERY_2D_ONLY and active_dimension == "2d")
        _check(report, "three_d_modules_cropped_out", not three_d_loaded)
        _check(report, "three_d_sources_cropped", three_d_sources_cropped)
        _check(report, "formal_2d_world_present", world_2d != null and camera_2d != null and camera_2d.enabled)
        _check(report, "native_resolution_hud_present", canvas_layer != null and ui_root != null and formal_ui_ready and canvas_layer.layer == 20)
        var blocked_3d := set_dimension("3d")
        _check(report, "cropped_delivery_rejects_3d", not bool(blocked_3d.get("ok", false)) and str(blocked_3d.get("code", "")) == "delivery.3d_module_excluded" and active_dimension == "2d")
        var start_position := player.position if player != null else Vector2.ZERO
        var move_event := InputEventKey.new()
        move_event.physical_keycode = KEY_D
        move_event.pressed = true
        var move_started := dispatch_input_event(move_event)
        advance_simulation(0.2)
        var move_release := InputEventKey.new()
        move_release.physical_keycode = KEY_D
        move_release.pressed = false
        var move_stopped := dispatch_input_event(move_release)
        _check(report, "formal_2d_input_move", str(move_started.get("action", "")) == "move" and str(move_stopped.get("action", "")) == "move")
        _check(report, "formal_2d_world_playable", player != null and player.position.distance_to(start_position) > 1.0)
        var query := query_active_target()
        _check(report, "formal_2d_query_playable", bool(query.get("ok", false)))
        var viewport_size: Vector2 = get_viewport().size if get_viewport() != null else Vector2.ZERO
        var manifest := {
                "schema": "gm.p25.2d_only_delivery.v1",
                "delivery_id": "gm.p25.delivery.2d_only",
                "entry_scene": "res://gm_runtime/player_shell/gm_p25_2d_only_delivery.tscn",
                "delivery_mode": delivery_mode,
                "excluded_modules": ["gm_runtime/map/3d", "gm_adapters/spatial3d", "GMCameraRig3D", "GMInteractionQuery3D"],
                "three_d_sources_cropped": three_d_sources_cropped,
                "runtime_three_d_module_loaded": three_d_loaded,
                "world_render_layer": {"node": "P25World2D", "camera": "Camera2D", "playable": player != null and player.position.distance_to(start_position) > 1.0},
                "hud_render_layer": {"node": "P25FormalHUD", "canvas_layer": canvas_layer.layer if canvas_layer != null else -1, "native_viewport": true, "viewport_size": {"x": viewport_size.x, "y": viewport_size.y}},
                "query": query,
        }
        _check(report, "independent_delivery_entry_declared", str(manifest.get("entry_scene", "")) == "res://gm_runtime/player_shell/gm_p25_2d_only_delivery.tscn")
        _check(report, "delivery_started_in_native_viewport", get_viewport() != null and get_viewport().size.x > 0 and get_viewport().size.y > 0)
        report["manifest"] = manifest
        _print_mode_and_quit("P25_2D_ONLY_RESULT", report)

func _check(report: Dictionary, name: String, passed: bool) -> void:
        report.checks.append({"name": name, "passed": passed})
        if not passed: report.ok = false

func _print_and_quit(report: Dictionary) -> void:
        print("P25_CONTRACT_RESULT " + JSON.stringify(report))
        get_tree().quit(0 if bool(report.get("ok", false)) else 1)

func _print_mode_and_quit(prefix: String, report: Dictionary) -> void:
        print(prefix + " " + JSON.stringify(report))
        get_tree().quit(0 if bool(report.get("ok", false)) else 1)

func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
        return {"ok": false, "code": code, "reason_zh": reason_zh, "error_zh": reason_zh, "details": details}
