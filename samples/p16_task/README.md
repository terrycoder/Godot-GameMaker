# P16 统一Task中性样板

- 正式运行入口：`res://gm_runtime/tasks/gm_p16_export_entry.tscn`
- 策划资源：`res://samples/p16_task/task_definition.tres`
- 中文显示值与英文稳定 API/ID/schema/error code 分离。
- 样板只构造 Ability 请求并显示 Task 事实，不直写角色、地图、物品。
- Planner、库存、生产、SceneSession 分别延后到 P17、P19、P20、P23。
