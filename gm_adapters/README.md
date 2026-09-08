# GM适配器骨架

任务00只保留插件适配边界。第三方源码不复制进本项目；TileMapDual和GUT是冻结矩阵要求的正式接入依赖，唯一检测/锁定点为 `GMPlatform.plugin_report()`。候选插件的裁定见 `reports/gm/plugin_decision_matrix.md`。

- `gm_tile_map_dual_adapter.gd`：只负责正式依赖存在/版本验证，不把第三方API散落到GM运行时。
- `gm_gut_adapter.gd`：只负责正式GUT CLI入口和结果语义，导出路径不引用GUT。
