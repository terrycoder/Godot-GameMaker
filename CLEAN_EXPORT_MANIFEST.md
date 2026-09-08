# GM 平台 GitHub 清洁导出清单

## 导出定位

此目录是为私有 GitHub 仓库准备的源码暂存副本。它不是原开发工作区的镜像，也不携带历史测试与自动审查环境。

## 包含内容

- `gm_runtime/`：平台运行时、模块声明、正式 2D/Planar3D 入口及运行所需资源。
- `gm_adapters/`：生产适配器；已排除仅用于 GUT 的适配器。
- `interaction_recipes/`：正式交互配方资源。
- `samples/`：被生产 Dock、正式入口和开发者示例引用的正向样例资源；仅排除其中明确的负向、缺失、测试或实验样板。
- `addons/gm_editor/`、`addons/gm_agent_planner/`、`addons/gm_feedback/`、`addons/gm_p26_vertical_sample/`：平台编辑器与专项生产工具。
- `gm_cli.*`、`gm_cli_launcher.py`：只读平台检查命令行入口。
- `DOCS/gm/platform_manual/`：完整中文平台技术说明体系，包含设计研究稿与文档审查稿；其中提到但未随包提供的内部证据均按“发布包不含”理解。
- `project.godot`、`.gitignore`、根 `README.md`。
- 反馈工作台使用 `gm_runtime/feedback/gm_feedback_workbench_config.tres` 作为生产默认配置，不依赖已排除的开发样例。

## 排除内容

- 所有 `tests/`、`test/`、`dev_samples/` 目录，以及 `samples/` 内明确的负向、缺失、测试或实验样板。
- 名称为 fixture、probe、experiment 的测试或实验资产。
- TileMapDual、GUT、GUT 适配器、`third_party_optional/` 与 AsepriteWizard 参考副本。
- `gm_gas_audit.gd`、历史任务 CLI、测试 runner 与负面测试 Manifest。
- `reports/`、`evidence/`、`reviewer_handoffs/` 及自动审查运行产物。
- `.godot/`、缓存、临时目录、日志、用户数据和编辑器状态。
- EXE、PCK、ZIP、TAR、7Z、RAR 等构建或归档产物。
- Codex/Agent 内部文件、机器绝对路径、凭据与令牌。
- 原工作区中由命令转义失误形成的零字节杂项文件。

## `project.godot` 清理

- 删除历史 P15-P26 任务入口设置。
- 保留平台最小入口和当前正式 Planar3D/2D 入口。
- 禁用并移除 GUT 与无随包许可证的 TileMapDual；保留四个自有生产/编辑器插件。
- 历史编辑器 QA 驱动和测试命令已从发布入口删除；正常导入不依赖被排除的测试树。
- Alpha/Beta 测试模块、ServiceSpec、Manifest、Task01 场景和编辑器开关均已移除；正式 Manifest Index 只注册生产模块。

## 兼容性与风险边界

- 有界验证使用 Godot `4.6.2-stable`。
- 未对 Godot 4.7.2 作兼容承诺。
- 测试套件与审查证据被有意排除；接收方应在自己的游戏仓库建立独立测试工程与发布流水线。
- TileMapDual 适配接口按缺失插件关闭式返回只读状态；第三方插件本体不在此发布包中。

## 文档与命令同步边界

- 11 份中文说明均保留，并统一标注 GitHub 清洁发布版边界。
- 发布版 CLI 只公开 `help`、`environment`、`compatibility`、`validate`、`modules` 五个已验证只读命令。
- 源仓库内部测试、GUT、测试目录、fixture、runner、冒烟验收和审查证据不随本清洁版提供；文档不提供依赖这些已排除内容的可执行步骤或链接。
- launcher 随包提供，优先读取 `GODOT_EXE`，否则从 `PATH` 查找 `godot` 或 `godot4`。

