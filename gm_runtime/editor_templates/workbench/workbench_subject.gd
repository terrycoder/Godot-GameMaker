@tool
class_name GMWorkbenchSubject
extends Resource

## 任务02的真实编辑器演示 Resource。它位于 dev_samples，不进入正式游戏导出。
@export var project_name_zh: String = "策划工作台示例"
@export var scene_note_zh: String = "策划模式与高级 Inspector 共同编辑这份 Resource"
@export var map_names: PackedStringArray = PackedStringArray(["起始地图"])
@export var character_names: PackedStringArray = PackedStringArray(["示例角色"])
@export var ability_names: PackedStringArray = PackedStringArray(["移动", "交互"])
@export var resource_names: PackedStringArray = PackedStringArray(["基础资源"])
@export var task_names: PackedStringArray = PackedStringArray(["欢迎任务"])
@export var change_marker: String = "初始值"
@export var revision: int = 1

func content_count() -> int:
	return map_names.size() + character_names.size() + ability_names.size() + resource_names.size() + task_names.size()

func content_snapshot() -> Dictionary:
	return {
		"project_name_zh": project_name_zh,
		"scene_note_zh": scene_note_zh,
		"map_names": Array(map_names),
		"character_names": Array(character_names),
		"ability_names": Array(ability_names),
		"resource_names": Array(resource_names),
		"task_names": Array(task_names),
		"change_marker": change_marker,
		"revision": revision,
	}
