# Godot GameMaker（GM）平台

GM 是面向 Godot 4.6 的模块化游戏开发平台源码，提供内容定义、运行时服务、编辑器工具、2D/Planar3D 空间适配、角色与任务、交互、生产流程、保存恢复和发布裁剪能力。

## 从这里开始

- [说明文档总览](DOCS/gm/platform_manual/说明文档总览.md)
- [GM 平台技术手册](DOCS/gm/platform_manual/GM平台技术手册.md)
- [游戏开发者快速入门](DOCS/gm/platform_manual/游戏开发者快速入门.md)
- [构建发布与验收手册](DOCS/gm/platform_manual/构建发布与验收手册.md)
- [源码与扩展点地图](DOCS/gm/platform_manual/源码与扩展点地图.md)

## 环境边界

- 已验证引擎：Godot `4.6.2-stable`。
- `4.7.2` 只是未来兼容目标，当前未验证。
- 默认主场景是平台最小入口；`project.godot` 另保留 Planar3D 与 2D 正式入口键供集成脚本选择。
- 本仓库是清洁源码副本，不包含可执行测试、实验工程、运行证据、缓存、用户数据和构建产物；中文说明体系中的研究稿与文档审查稿作为设计资料保留。
- `samples/` 中的正向资源是生产 Dock 与正式入口的依赖，会随源码提交；负向、缺失、测试与实验样板不在发布包中。

## 打开与运行

1. 使用 Godot 4.6.2 导入仓库根目录的 `project.godot`。
2. 等待首次资源导入完成。
3. 运行项目以启动 `res://gm_runtime/gm_minimal_entry.tscn`。
4. 构建具体游戏前，按快速入门建立自己的 ProjectProfile、模块组合、正式入口和独立存档命名空间。

完整的复制范围与排除规则见 [清洁导出清单](CLEAN_EXPORT_MANIFEST.md)。

## 可选依赖边界

TileMapDual、GUT 和其他仅测试或许可证未随包交付的第三方插件均未包含、未启用。相关适配接口仅提供关闭式能力检测；需要这些能力时，请由具体游戏项目自行完成许可证审查、安装与兼容验证。

发布版 `gm_cli.gd` 只提供 `help`、`environment`、`compatibility`、`validate` 和 `modules` 五个只读命令；历史测试、fixture、GUT、证据生成与旧导出命令均明确不随发布包提供。

## GitHub 清洁发布版边界

本仓库只提供生产源码、运行时必要资源、生产插件、项目配置与完整中文说明体系。源仓库内部测试、GUT、fixture、runner、审查证据、缓存、用户数据和构建产物均不随本清洁版提供。发布版 CLI 仅支持 `help`、`environment`、`compatibility`、`validate`、`modules`；详细包含与排除范围见 [清洁导出清单](CLEAN_EXPORT_MANIFEST.md)。

