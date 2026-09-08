class_name GMPlayerShellConfiguration
extends Resource

## The one caller-authored composition boundary for the formal P25 shell.
## Domain services, projections, and persistence remain owned by the existing
## shell; this resource only supplies the scenario-specific composition.

const SCHEMA := "gm.player_shell.configuration.v1"
const CONFIGURATION_DIRECTORY := "res://gm_runtime/player_shell/configurations/"
const DEFAULT_CONFIGURATION_PATH := CONFIGURATION_DIRECTORY + "default.tres"
const CAMERA_PROFILE_SCRIPT := preload("res://gm_runtime/player_shell/gm_player_shell_camera_profile.gd")
const IGNORED_ARGUMENTS := ["save", "restore", "negative", "config", "pack"]

@export var configuration_id := "default"
@export var world_id := "gm.world.p25.player_shell"
@export var seed := 25

@export var map_id := "gm.map.p25.shell"
@export var surface_id := "gm.surface.p25.shell"
@export var graph_id := "gm.graph.p25.shell"
@export var map_display_name_zh := "玩家外壳平面3D地图"
@export var map_size := Vector2(1088.0, 640.0)
@export var tile_size := Vector2(32.0, 32.0)

@export var player_id := "gm.actor.p25.player"
@export var player_role_id := "gm.role.p25.player"
@export var player_role_display_name_zh := "玩家外壳执行者"
@export var entry_anchor_id := "gm.anchor.p25.entry"
@export var entry_position := Vector2(160.0, 320.0)
@export var target_anchor_id := "gm.anchor.p25.beacon"
@export var target_position := Vector2(800.0, 320.0)
@export var exit_anchor_id := "gm.anchor.p25.exit"
@export var exit_position := Vector2(960.0, 320.0)

@export var target_id := "gm.object.p25.beacon"
@export var target_definition_id := "gm.content.p25.shell.beacon"
@export var target_display_name_zh := "中性信标"
@export var target_object_kind := "mechanism"

@export var ability_id := "gm.ability.p25.shell.interact"
@export var ability_display_name_zh := "激活中性信标"
@export var ability_description_zh := "通过统一交互请求提交中性信标状态变化。"
@export var interaction_id := "gm.interaction.p25.shell.inspect"
@export var task_interaction_id := "gm.interaction.p25.task.assign"
@export var interaction_recipe_id := "gm.recipe.p25.shell.beacon"
@export var interaction_event_tag := "event.p25.shell.beacon_activated"

@export var task_definition_id := "gm.definition.p25.shell"
@export var task_id := "gm.task.p25.shell"
@export var assignment_id := "gm.assignment.p25.shell"
@export var task_display_name_zh := "检查中性信标"
@export var task_description_zh := "通过正式玩家外壳读取并处理一个中性场景目标。"
@export var objective_id := "gm.objective.p25.shell.interaction"
@export var objective_display_name_zh := "完成一次场景交互"
@export var objective_target := 1

@export var resource_id := "gm.resource.p25.shell"
@export var reservation_rule_id := "gm.reservation.p25.shell"
@export var reservation_id := "gm.reservation.p25.shell.workbench"
@export var duty_provider_id := "gm.duty.p25.shell"
@export var duty_event_type := "gm.fact.duty.p25.shell"

@export var scene_id := "gm.scene.p25.shell"
@export var scene_definition_id := "gm.scene.definition.p25.shell"
@export var scene_recipe_id := "gm.recipe.p25.shell.scene"
@export var scene_skeleton_id := "gm.skeleton.p25.shell"
@export var scene_display_name_zh := "玩家外壳中性场景"
@export var scene_objective_id := "gm.objective.scene.p25.shell"
@export var scene_result_prefix := "gm.result.p25"
@export var scene_reason_prefix := "scene.p25"
@export var facility_id := "gm.facility.p25.shell"
@export var hostile_role_id := "gm.role.p25.none"
@export var region_id := "gm.region.p25.shell"

@export var camera_profile_id := "gm.camera.profile.p25.shell"
@export var camera_display_name_zh := "玩家外壳固定正交相机"
@export var camera_orthographic_size := 1088.0
@export var camera_zoom := 1.0
@export var camera_min_zoom := 0.75
@export var camera_max_zoom := 1.5
@export var camera_fixed_rotation_degrees := Vector3(-55.0, -45.0, 0.0)
@export var camera_bounds := Rect2(0.0, 0.0, 1088.0, 640.0)
@export var camera_look_ahead := Vector2(256.0, 0.0)

@export_file("*.json") var save_path := "user://gm_p25_player_shell.world.json"

func validate() -> Dictionary:
        var required_values := [
                configuration_id, world_id, map_id, surface_id, graph_id, player_id,
                entry_anchor_id, target_anchor_id, exit_anchor_id, target_id,
                target_definition_id, ability_id, interaction_id, task_interaction_id,
                task_definition_id, task_id, assignment_id, objective_id,
                resource_id, reservation_rule_id, reservation_id, duty_provider_id,
                duty_event_type, scene_id, scene_definition_id, scene_recipe_id,
                scene_skeleton_id, scene_objective_id, facility_id, hostile_role_id,
                region_id, camera_profile_id, save_path,
        ]
        for value in required_values:
                if str(value).strip_edges().is_empty():
                        return _failure("shell.configuration_value_missing", "玩家外壳正式配置缺少必填值。")
        if seed < 0:
                return _failure("shell.configuration_seed_invalid", "玩家外壳正式配置的Seed必须是非负整数。")
        if map_size.x <= 0.0 or map_size.y <= 0.0 or tile_size.x <= 0.0 or tile_size.y <= 0.0:
                return _failure("shell.configuration_map_invalid", "玩家外壳正式配置的地图尺寸必须为正。")
        if objective_target <= 0:
                return _failure("shell.configuration_objective_invalid", "玩家外壳正式配置的Task目标必须为正整数。")
        if camera_orthographic_size <= 0.0 or camera_zoom <= 0.0 or camera_min_zoom <= 0.0 or camera_max_zoom < camera_min_zoom or camera_zoom < camera_min_zoom or camera_zoom > camera_max_zoom:
                return _failure("shell.configuration_camera_invalid", "玩家外壳正式配置的相机参数无效。")
        if camera_bounds.size.x <= 0.0 or camera_bounds.size.y <= 0.0:
                return _failure("shell.configuration_camera_bounds_invalid", "玩家外壳正式配置的相机边界必须有面积。")
        if not save_path.begins_with("user://"):
                return _failure("shell.configuration_save_path_invalid", "玩家外壳正式配置的存档入口必须位于user://。")
        return {"ok": true, "code": "shell.configuration.valid", "configuration_id": configuration_id}

func build_camera_profile() -> GMPlayerShellCameraProfile:
        var profile: GMPlayerShellCameraProfile = CAMERA_PROFILE_SCRIPT.new()
        profile.profile_id = camera_profile_id
        profile.display_name_zh = camera_display_name_zh
        profile.orthographic_size = camera_orthographic_size
        profile.zoom = camera_zoom
        profile.min_zoom = camera_min_zoom
        profile.max_zoom = camera_max_zoom
        profile.fixed_rotation_degrees = camera_fixed_rotation_degrees
        profile.bounds = camera_bounds
        profile.look_ahead = camera_look_ahead
        return profile

func to_native() -> Dictionary:
        return {
                "schema": SCHEMA,
                "configuration_id": configuration_id,
                "world_id": world_id,
                "seed": seed,
                "map_id": map_id,
                "surface_id": surface_id,
                "graph_id": graph_id,
                "player_id": player_id,
                "target_id": target_id,
                "task_id": task_id,
                "scene_id": scene_id,
                "entry_position": {"x": entry_position.x, "y": entry_position.y},
                "target_position": {"x": target_position.x, "y": target_position.y},
                "save_path": save_path,
                "camera_profile": build_camera_profile().to_native(),
        }

static func configuration_id_from_args(args: PackedStringArray) -> String:
        for raw_value in args:
                var value := str(raw_value).strip_edges()
                if value.is_empty() or value.begins_with("--") or value in IGNORED_ARGUMENTS:
                        continue
                return value
        return ""

static func load_for_id(requested_id: String) -> Dictionary:
        var normalized := _normalize_id(requested_id)
        var configuration: Variant = null
        if not normalized.is_empty():
                configuration = load(CONFIGURATION_DIRECTORY + normalized + ".tres")
        if not configuration is GMPlayerShellConfiguration:
                configuration = load(DEFAULT_CONFIGURATION_PATH)
        if not configuration is GMPlayerShellConfiguration:
                return _failure("shell.configuration_missing", "玩家外壳默认正式配置不可用。")
        var checked: Dictionary = configuration.validate()
        if not checked.ok:
                return _failure("shell.configuration_invalid", "玩家外壳正式配置校验失败。", checked)
        return {"ok": true, "configuration": configuration, "requested_id": requested_id, "resolved_id": configuration.configuration_id}

static func _normalize_id(value: String) -> String:
        var normalized := value.strip_edges().to_lower()
        if normalized.is_empty() or normalized.contains("/") or normalized.contains("\\") or normalized.contains(".."):
                return ""
        return normalized

static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
        return {"ok": false, "code": code, "reason_zh": reason_zh, "error_zh": reason_zh, "details": details}
