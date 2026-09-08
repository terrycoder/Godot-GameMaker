# GM 平台权威技术说明

## 1. 文档目标与适用范围

本文面向负责在 GM 平台上搭建具体游戏的程序、技术策划和工具开发者。目标是回答每项主要能力的七个问题：用途是什么、谁持有权威、在哪里配置、运行链怎样、如何开发、怎样验证、最常见错误是什么。

当前验证基线为 Godot `4.6.2-stable official`。`4.7.2-stable` 尚未验证。本文所称“已支持”指存在当前源码和程序化合同证据，不代表八组真人 GUI/体验验收已经完成。

## 2. 核心术语

| 术语 | 含义 |
|---|---|
| Profile | 泛称；本平台有四种不同 Resource：ProjectProfile、ShellConfiguration、NeutralSampleProfile、ReleaseProfile，字段与稳定性不能混用。 |
| Module Manifest | 单个模块的身份、依赖、服务、空间后端、导出和迁移声明权威。 |
| Manifest Index | 一个发行组合明确允许加载的 Manifest 路径列表。 |
| Registry | 校验 Manifest 并解析依赖、冲突、服务和安装顺序的提交快照。 |
| RuntimeContext | 按 Registry 拓扑安装/释放服务，并激活唯一空间后端。 |
| Stable ID | 与节点名、路径和实例号无关，可跨存档和进程引用的业务身份。 |
| Projection | 从权威状态计算出的 UI/场景/查询显示值；不可反向充当权威。 |
| Ability | 玩家、AI、日程、事件和调试操作的统一执行入口。 |
| Resolver/Transaction | 领域写入的预检、预留、提交、回滚与恢复协议。 |
| Fact/Change/Cue | 已提交事实、审计变更和表现语义；三者边界不同。 |
| SimulationWorld | 后台世界聚合根，负责系统调度、命令合并和统一存档。 |
| Store | 保存领域纯数据的命名版本化记录集。 |
| Contributor | 将扩展状态接入统一世界存档/原子恢复的参与者。 |
| Planar3D | 逻辑仍在平面和 Surface Graph 上，表现使用 3D；不是 Full3D。 |
| Fixture/Sample | 验证或示范资源；必须换身份和内容后才能进入具体游戏。 |

## 3. 总体架构与单一权威

GM 的主数据流是：

```text
Profile + Manifest Index
  -> ModuleRegistry resolve/topological order
  -> RuntimeContext install + one spatial backend
  -> Player/AI/Schedule/Event 构造 AbilityActivationRequest
  -> AbilitySystemHost
  -> DomainResolver + TransactionCoordinator
  -> committed FactEvent + ChangeRecord + Cue
  -> Task/Process/Object/Inventory 等领域 Store
  -> SimulationWorld 统一快照和原子恢复
  -> SceneBridge/HUD/Visual/Cache 只读投影
```

### 3.1 权威速查

| 领域 | 唯一权威 | 可派生内容 | 禁止成为第二权威 |
|---|---|---|---|
| 模块 | Manifest + Registry committed snapshot | 模块列表、导出计划 | 扫目录结果、手写 service map |
| 世界 | `GMSimulationWorld` / EntityRegistry | 场景桥、HUD | 节点树、相机、导航对象 |
| Task | `GMTaskService` + Task Store/Fact | TaskProjection | Dock 字段、Planner 显示 |
| 能力事实 | Resolver commit + FactEventStore | Change、Cue | GameplayEvent、动画回调 |
| Process | Process Store + Clock + Settlement | 进度条、反馈 | Timer/节点进度 |
| 空间 | `GMPlanarPosition` + authored map/graph | 2D/3D 坐标 | Transform、NodePath、NavigationAgent |
| 角色视觉 | VisualRecipe + ContentLibrary | CompileCache、节点、LOD | Mesh/缓存状态 |
| 保存 | SimulationWorld world file + named Stores | staged candidate | 第二 JSON 根、UI/cache 快照 |

### 3.2 运行启动顺序

`GMPlayerShell._ready()` 的关键顺序是：解析 Shell 配置 → 选择模块索引 → 输入映射 → 构建 Runtime/语义地图/服务/Store → 构建 HUD → 可选恢复 → 刷新投影。恢复不可提前到 contributor 尚未装配时。

当前可执行组合入口是 P25 Shell 与 EXT11 样板，不是模块中立 ABI。Planar3D 唯一已有独立实例验收的参考是 CAW-owned 冻结适配：项目脚本在调用 `GMExt3D11Release._ready()` 前同时赋 `release_profile`/`sample_profile`，场景绑定项目 Shell；但父类仍强制使用冻结 EXT11 Index。只赋 `sample_profile` 或试图预设项目 Index 都会被父类覆盖。2D 父类和 P25 Shell 也会重绑 2D Index；项目自有 Index/通用 2D 必须有不调用这些样板 `_ready()` 的自有 composition root。固定配置目录/default fallback、`handle_action()`、actions 和 probes 均非稳定 API。

## 4. 模块、Profile、Manifest 与服务

### 4.1 模块系统

| 项 | 说明 |
|---|---|
| 用途 | 显式决定一个项目具备哪些能力、服务、空间后端和导出文件。 |
| 权威数据 | `GMModuleManifest`、`GMModuleManifestIndex`、Registry committed snapshot。 |
| 配置/入口 | 项目 Profile 的 `enabled_modules`；Manifest Index 的 `manifest_paths`；环境变量 `GM_MODULE_INDEX_PATH`。 |
| 运行链 | `refresh_result()` → `resolve()` → `topological_order()` → `GMRuntimeContext.install()`。 |
| 开发步骤 | 每模块建稳定 ID Manifest；声明 required/optional/conflicts、services、backend、required/excluded paths；加入项目 Index；解析并安装。 |
| 验证方法 | `schema_errors()`、`validate_explicit()`、`manifest_contract()`、`spatial_backend_contract()`、导出规划和 actual-pack inventory。 |
| 常见错误 | 重复 service ID、自依赖、只删目录不改依赖、运行时热换 Registry 代际、未声明模块被动态加载。 |

Manifest 可声明 content types、abilities、effects、events、cues、tags、服务实现、空间后端、编辑器入口、验证规则、迁移、许可证、原生依赖和私有构建物。Registry 解析失败时应停止启动，而不是降级为不完整组合。

### 4.2 Project/Profile

“Profile”必须按类型解释，不能把字段混写：

| 类型 | 当前职责 | 稳定性边界 |
|---|---|---|
| `GMProjectProfile` | `enabled_modules`、`spatial_domain_id`、`spatial_backend_id/enabled` | 项目模块选择 Resource；不含地图、玩家、入口或保存 |
| `GMPlayerShellConfiguration` | world/map/player/content/camera/save 与 P25 Shell 组合字段 | P25 配置接缝；下游需完整覆盖并阻止默认 fallback |
| `GMNeutralVerticalSampleProfile` | actor/facility/workspot/surface 等 EXT10 中性内容编排 | 样板 schema，不是通用项目 Profile |
| `GMPlanar3DReleaseProfile` | 继承中性样板并增加 release ID、Manifest Index、入口、cache/budget | EXT11/P27 发布样板，不是通用发布 ABI |

| 项 | 说明 |
|---|---|
| 用途 | 把模块组合、空间模式、业务身份、正式入口、存档和预算固定成可验证配置。 |
| 权威数据 | 项目自己的 Profile Resource；发布层再由 release contract 冻结。 |
| 配置/入口 | 项目自有 `GMProjectProfile`、完整覆盖的 `GMPlayerShellConfiguration`；EXT10/EXT11 Profile 仅作字段与适配参考。 |
| 运行链 | 入口加载 Profile → `validate()` → Registry/Context → PlayerShell/World。 |
| 开发步骤 | 复制结构而非身份；整体替换 profile/map/graph/surface/actor/entity/facility/task/process/save ID；绑定对应 Manifest Index。 |
| 验证方法 | Profile `validate()`；非默认 Profile 完整编辑器退出后独立进程读取；正式入口证据打印 active Profile。 |
| 常见错误 | 只新增 identity JSON、正式入口仍加载 GM 默认 Profile；复制样板保留 `ext3d10`；显式路径失败后回退默认资源。 |

稳定 ID 的“类型前缀”与“项目命名空间”是两个维度。以占位命名空间 `studio_game` 为例：实体 `gm.entity.studio_game.*`、角色 `gm.actor.studio_game.*`、流程定义 `gm.process.studio_game.*`、事实 `gm.fact.studio_game.*`。同理使用对应 schema/验证器要求的 `gm.task.*`、`gm.ability.*` 等前缀；`gm.studio_game.entity.*` 是错误顺序。项目 ID、Profile ID、release ID 不是实体类型 ID，分别按其所属 Resource 验证器创建。

项目内容必须保留 schema 要求的 `gm.<type>.` 前缀，并在其后加入项目拥有的命名空间段，例如 `gm.actor.studio_game.*`。不得复用平台/样板已经占用的具体身份（如 EXT、P25/P27、CAW），也不得省略项目段；中文显示名和文件路径不能充当业务 ID。

## 5. 空间、地图与场景

### 5.1 2D 与 Planar3D 模式

`2D-only` 只有 `core/spatial.core/spatial.planar_2d`。`Planar3D-enabled` 再启用 `spatial.planar_3d/character.visual_3d/scene.execution/presentation.render_style_3d/sample.neutral_vertical`。同一候选不得隐式并集；Full3D 保留域不允许发布。

### 5.2 逻辑位置与空间查询

| 项 | 说明 |
|---|---|
| 用途 | 让 2D 和 Planar3D 共享稳定、可保存的逻辑位置与语义目标。 |
| 权威数据 | `GMPlanarPosition`、地图/Surface Graph、`GMSpatialTargetRef`。 |
| 配置/入口 | `map_id`、`surface_id`、x/y；target kind 为 entity/anchor/route/facility_slot/logical_position。 |
| 运行链 | Context 激活唯一 backend → `query_spatial()` → backend 返回 `GMSpatialQueryResult` → 场景投影。 |
| 开发步骤 | 先创作 map/surface/anchor/route/facility ID，再由 backend 映射世界坐标；跨地图使用 travel handoff。 |
| 验证方法 | backend/domain/capabilities 合同；目标解析、可达性、寻路、坐标转换；保存只含纯逻辑值。 |
| 常见错误 | 保存 Transform/NodePath/NavigationAgent；稳定目标同时夹自由坐标；同一 Context 激活两个 backend。 |

### 5.3 2D 地图工作台

| 项 | 说明 |
|---|---|
| 用途 | 制作方格/等距地图的表现层和逻辑层。 |
| 权威数据 | `GMMapResource.layers` 及地图 Resource。 |
| 配置/入口 | 编辑器底部“GM地图工作台”；`gm_map_workbench_dock.gd`。 |
| 运行链 | 选择地图/画笔 → controller 校验 → UndoRedo action → Resource 更新 → 画布投影。 |
| 开发步骤 | 新建方格或等距样板；配置层顺序、锁定、可见性；画笔绘制；撤销/重做；保存重开。 |
| 验证方法 | Resource 值、Undo/Redo、保存后 `CACHE_MODE_IGNORE` 重读；TileMapDual 缺失时确认只读。 |
| 常见错误 | 后端不可用仍直改内部状态；只看颜色预览不查 Resource；把 TileMap 节点当业务地图身份。 |

### 5.4 语义地图

| 项 | 说明 |
|---|---|
| 用途 | 建立 Region、Route、Anchor、Portal、Camera2D zone 等玩法语义。 |
| 权威数据 | 语义地图 Resource 中的稳定对象声明。 |
| 配置/入口 | “GM语义地图”；地图 ID、各对象表单和保存路径。 |
| 运行链 | 表单/画布编辑 → validate → UndoRedo → Resource → 空间查询/事件/相机投影。 |
| 开发步骤 | 建地图 ID；逐类新增；应用编辑；一键验证；保存；关闭并按路径重开。 |
| 验证方法 | 点串/引用/重叠规则校验；Portal 两端存在；从 Anchor 测试；确认 ephemeral 参数未写入正式资源。 |
| 常见错误 | Anchor 显示名当 ID；Portal 悬空；测试启动参数污染存档；相机 zone 直接改业务状态。 |

### 5.5 Planar3D Surface Graph

| 项 | 说明 |
|---|---|
| 用途 | 为平面化三维地图声明 Surface、坡度和跨 Surface Connection。 |
| 权威数据 | `GMSurfaceGraph`、Surface definition、Connection Resource。 |
| 配置/入口 | “GM平面3D地图”；Graph 路径、Surface/Connection CRUD。 |
| 运行链 | Dock action → UndoRedo → Graph validate → Planar3D adapter 查询 → Node3D/Gizmo 投影。 |
| 开发步骤 | 定义 surface 边界、原点、坡度、agent profile；再定义 stairs/ramp/bridge/portal/door/lift_reserved connection。 |
| 验证方法 | 非法 ID/点串/悬空引用失败不变；保存关闭重开；目标解析、吸附、可达性和寻路。 |
| 常见错误 | Gizmo/颜色当数据；用世界坐标代替逻辑位置；Connection 指向不存在 Surface。 |

### 5.6 SceneRecipe3D 与设施摆放

| 项 | 说明 |
|---|---|
| 用途 | 把世界对象、设施、入口、WorkSpot 和语义槽位装配为 3D 场景表现。 |
| 权威数据 | SceneRecipe/Skeleton/placements 与 Surface Graph 引用。 |
| 配置/入口 | “GM 三维场景配方策划”；`gm_scene_3d_placement_dock.gd`。 |
| 运行链 | Recipe + Context + Graph → `GMSceneRecipeBuilder` / `GMSceneBuilder3D` → build artifact → 场景节点。 |
| 开发步骤 | 新建项目 Recipe；拖入声明对象；设置 surface/socket/semantic reference、transform；校验；保存重开。 |
| 验证方法 | 稳定 ID 唯一；引用存在；缓存删除后可重建；非默认 document namespace 测试。 |
| 常见错误 | 所有项目共享样板前缀；把 placement 节点当世界事实；缓存失败后手改 artifact。 |

## 6. 内容和资源系统

### 6.1 Content Library

| 项 | 说明 |
|---|---|
| 用途 | 扫描、索引、查找和影响分析 GMContent Resource。 |
| 权威数据 | `GMContent` Resource 和 `GMContentTypeRegistry`。 |
| 配置/入口 | “GM内容资源库”；项目内容根和类型注册资源。 |
| 运行链 | `scan()`/`reload()` → validate/index → `query()` 或 `entry_for_id()`/`entry_for_path()` →调用方使用 Resource。`GMContentLibrary` 当前没有通用 `resolve()` 方法。 |
| 开发步骤 | 用项目 namespace 创建内容；注册类型；填中文显示和稳定 ID；重新索引；查反向引用后保存。 |
| 验证方法 | ID 唯一、类型验证、正/反向引用、删除保护、移动路径后身份不变。 |
| 常见错误 | ResourceUID/路径当业务 ID；删除被引用资源；将 dev_samples 扫描结果打入正式包。 |

新内容类型向导可生成脚本、类型注册 Resource、验证器、列表入口和测试模板，但生成物仍需代码审查；向导不是自动稳定 API 发布器。

### 6.2 对象装配

| 项 | 说明 |
|---|---|
| 用途 | 把对象 Definition、交互能力、Owner、保存身份和语义锚点装配进地图。 |
| 权威数据 | Object Definition、领域 Store/Fact、稳定实例 ID。 |
| 配置/入口 | “GM对象装配”；从内容库拖入定义并绑定地图/Anchor。 |
| 运行链 | Definition → InteractionRecipe → Ability request → ObjectInteractionService；声明领域写入且 `fact_type` 非空时再进入 Transaction → Fact/Change/Cue，否则由 executor-only 路径返回结果。 |
| 开发步骤 | 创建 Definition/Recipe；装配；生成唯一实例 ID；预览修复；显式应用；运行正式交互。 |
| 验证方法 | Undo/Redo、Owner/保存身份、事务 committed result、失败状态不变、保存重开。 |
| 常见错误 | 按钮文字当提交证据；预览修复直接写权威；复制对象不换实例 ID。 |

## 7. 角色、NPC 与视觉

### 7.1 2D Character Definition/VisualSet

| 项 | 说明 |
|---|---|
| 用途 | 定义 2D 角色身份、语义动作、方向、锚点和事件帧。 |
| 权威数据 | Character Definition 与外部唯一 VisualSet Resource。 |
| 配置/入口 | “GM角色资产库”；导入源、两个不同 `res://*.tres` 路径。 |
| 运行链 | 帧/SpriteFrames → VisualSet → Definition → runtime visual projection。 |
| 开发步骤 | 建 Definition/VisualSet ID；导入帧；配置 idle/move/attack/hurt/death 和 one/four/eight/four_mirrored；填 anchors/events；分别保存。 |
| 验证方法 | 动作/方向完整、帧号有效、Definition 重读仍引用同一外部 VisualSet。 |
| 常见错误 | 两资源保存到同一路径；越界帧；Aseprite adapter 当运行时依赖；1500 角色夹具当内容生成器。 |

### 7.2 2D NPC 装配

| 项 | 说明 |
|---|---|
| 用途 | 将 Character、RoleProfile、碰撞和地图 Anchor 组成可保存 NPC 场景。 |
| 权威数据 | Character/Role Resource、Shape2D、地图稳定 ID/Anchor、实体身份。 |
| 配置/入口 | “GM角色NPC装配”；当前 2D 编辑场景与 `res://*.tscn` 输出。 |
| 运行链 | 校验输入 → 创建 runtime character → 设置 Owner/身份 → UndoRedo → PackedScene。 |
| 开发步骤 | 打开目标地图；选择三类输入；填写地图/Anchor/保存路径；装配；撤销重做；保存。 |
| 验证方法 | Owner、可见性、稳定 ID、场景保存重读；移动/Task/Planner 分层验证。 |
| 常见错误 | 没有当前编辑场景；把 NPC 节点当前坐标当空间权威；装配同时私建行为状态。 |

### 7.3 3D VisualRecipe 与装配

| 项 | 说明 |
|---|---|
| 用途 | 组合 Body/Head/Hair/Outfit/Feature/Accessory/Posture/Skeleton/Animation/Palette。 |
| 权威数据 | `GMCharacterVisualRecipe` + `GMContentLibrary`；schema `gm.character.visual_recipe.v1`。 |
| 配置/入口 | “GM角色3D视觉”“GM角色3D装配”。 |
| 运行链 | Content scan → resolver → Recipe validate → compile cache → assembler/runtime node。 |
| 开发步骤 | 创建 Recipe ID；绑定内容 ID、canonical bones、sockets、FitClass、动作和导入元数据；校验；保存重开；装配 Actor。 |
| 验证方法 | 依赖指纹变化使缓存失效；删除缓存后重建一致；Recipe 不含 Node/RID/PackedScene。 |
| 常见错误 | MeshInstance/AnimationPlayer 成为权威；改缓存不改 Recipe；socket/骨骼名未经 canonical 映射。 |

## 8. Ability、事件、事务和反馈

### 8.1 Ability System

| 项 | 说明 |
|---|---|
| 用途 | 将玩家、AI、日程、事件和调试操作统一成可幂等执行请求。 |
| 权威数据 | Ability Definition/Grant、Host 生命周期、显式 request/idempotency/causal identity。 |
| 配置/入口 | `GMAbilityActivationRequest`、`GMAbilitySystemHost`；“GM能力浏览器”。 |
| 运行链 | source → request → host checks/prepare → executor 或 domain transaction → result。 |
| 开发步骤 | 建稳定 ability/tag；声明 resolver/service/fact type；构造纯 TargetData 和显式幂等键；通过 Host 激活。 |
| 验证方法 | grant/revoke、重复键同材料返回既有结果、不同材料复用键拒绝、mount/unmount/dispose。 |
| 常见错误 | 输入/AI 各自调用业务服务；幂等键包含路径或实例号；动画结束回调自报领域成功。 |

### 8.2 Event Trigger

| 项 | 说明 |
|---|---|
| 用途 | 审计 Godot 局部 Signal，或把 GameplayEvent 条件路由到 Ability/handler。 |
| 权威数据 | Signal connection 关系；GameplayEvent trigger Resource 和 committed event。 |
| 配置/入口 | “GM事件触发器”；event tag/schema、condition、target selector。 |
| 运行链 | event → trigger/condition/selector → `GMAbilityActivationRequest` → Host；仅声明领域写入且 `fact_type` 非空的请求进入 Resolver/Transaction，executor-only/无领域写入请求在执行器路径完成。 |
| 开发步骤 | 明确选择 GodotLocalSignal 或 GameplayEvent；配置连接；Undo/Redo；运行真实事件。 |
| 验证方法 | 连接身份、签名、条件返回、目标选择、重复事件幂等；定位真实 Inspector/Selection。 |
| 常见错误 | 把本地 signal 当已提交 Fact；坏 condition 静默通过；断开/连接未进入 UndoRedo。 |

### 8.3 Transaction、Fact、Change、Cue

| 项 | 说明 |
|---|---|
| 用途 | 保证领域写入预检、预留、提交、失败恢复和审计的一致性。 |
| 权威数据 | Resolver 状态、TransactionCoordinator、FactEventStore committed package。 |
| 配置/入口 | Resolver 实现；Ability Definition 的 resolver/service/fact 声明。 |
| 运行链 | validate → dedupe → causal prefix → capture → preflight → reserve → commit → Fact/Change/Cue append → finalize。 |
| 开发步骤 | 实现 preflight/reserve/commit/rollback/capture/restore/release/isolate；可选 finalize/version/build_candidate。 |
| 验证方法 | 每个阶段故障注入；rollback 失败后强制 restore；重复幂等；Fact/Change/Cue 因果一致。 |
| 常见错误 | commit 后才补校验；rollback 失败仍继续服务；Cue 修改规则事实；Change 变成第二世界。 |

Cue 是 UI/音画表现语义，只有 Fact 是已提交领域事实。Feedback/UI 应消费 committed result 或 Projection，不能从提示文本反向改变 Store。

## 9. Task、Planner 与 Movement

### 9.1 Task

| 项 | 说明 |
|---|---|
| 用途 | 管理 TaskDefinition、Objective、Assignment、DutyProvider、Reservation 和状态机。 |
| 权威数据 | `GMTaskService`、`gm.store.task_domain`、Fact/receipt。 |
| 配置/入口 | “GM任务工作台”；TaskDefinition v2 和相关 Resource。 |
| 运行链 | `submit_operation()` → Ability/Transaction → Store/Fact → Objective 消费 committed signal → Projection。 |
| 开发步骤 | 定义 objective 信号和目标值；注册/发布 Task；建立分配；注册 DutyProvider；取得 Reservation。 |
| 验证方法 | 状态迁移、分配/撤销/拒绝、容量/到期、parent、幂等、跨进程恢复。 |
| 常见错误 | UI 自报 Objective 完成；v1 无歧义迁移被假定成功；Planner 显示当 Task 权威。 |

Task 状态包含 draft、available、assigned、in_progress/blocked、completed/failed/cancelled。Objective 只消费权威提交信号。

### 9.2 Planner

| 项 | 说明 |
|---|---|
| 用途 | 从 Task/FreeAction 候选生成确定性 Agent 决策与执行计划。 |
| 权威数据 | 严格 agent context、Task/Reservation 读取、decision receipt；Planner 不是领域写入者。 |
| 配置/入口 | `GMAgentPlanner`、`GMAgentPlannerRuntime`、`gm_agent_planner` 插件。 |
| 运行链 | context → 候选 → hard priority → fixed score → kind → ID 排序 → plan → behavior adapter → Ability/Movement。 |
| 开发步骤 | 提供 mounted/context_valid；定义候选和十项 score contribution；设置 policy/takeover。 |
| 验证方法 | 相同 context/seed 得到相同结果；Task 优先 tie-break；恢复后重读权威；玩家接管生命周期。 |
| 常见错误 | 浮点随机评分；Planner 直接移动节点或写 Task；恢复沿用陈旧候选。 |

### 9.3 Movement

| 项 | 说明 |
|---|---|
| 用途 | 处理 direction/direct/anchor/follow/patrol/face/cancel/travel。 |
| 权威数据 | Movement request/command、Actor/空间语义、控制权和世界位置。 |
| 配置/入口 | “GM移动能力”；`GMMovementProfile`、`GMMovementAbilityExecutor`。 |
| 运行链 | register actor → preflight → start → tick command → success/cancel/blocked；travel 生成 handoff。 |
| 开发步骤 | 配 speed/acceleration/distance；使用 map/anchor/route/follow actor；跨图声明 entry/exit/return。 |
| 验证方法 | 有限数值、地图可走、版本、控制权、取消、恢复快照、travel handoff 打开 SceneSession。 |
| 常见错误 | 动画节点持有位置权威；travel 自建场景会话；自由坐标替代稳定设施目标。 |

## 10. Facility、WorkSpot 与 Process

### 10.1 Facility/WorkSpot

| 项 | 说明 |
|---|---|
| 用途 | 声明设施容量、语义工作位、资源账户、Reservation 和 Process 入口。 |
| 权威数据 | Profile/Facility Resource 中的 facility/workspot 声明及领域账户 Store。 |
| 配置/入口 | 中性纵向 Profile/Resource 提供声明样板；当前没有 Facility/WorkSpot/Process 专用 Dock，使用 Inspector/项目工具编辑权威 Resource，SceneRecipe Dock 只放置表现。 |
| 运行链 | Actor 目标 → WorkSpot/Reservation → Process request → Settlement → Fact/资源变更。 |
| 开发步骤 | 为每项设置唯一 facility/workspot/anchor/surface/reservation/process/resource/account ID、容量和余额。 |
| 验证方法 | Surface/Anchor 存在；capacity≥1；余额非负；ID 唯一；Actor 只引用已声明 WorkSpot。 |
| 常见错误 | 场景节点槽位代替 WorkSpot；共享资源账户 ID；恢复余额不足仍通过。 |

### 10.2 Process

| 项 | 说明 |
|---|---|
| 用途 | 表达生产、工作、交互等跨 tick 持续行为。 |
| 权威数据 | `GMProcessDefinition`、Process Store、`GMProcessClock`、Settlement receipt。 |
| 配置/入口 | definition ID/revision/family/duration/capabilities/facility target/completion/task/duty。 |
| 运行链 | request start/participate/pause/resume/cancel → advance units → settlement gateway → committed result。 |
| 开发步骤 | 建稳定定义；声明设施目标和 completion kind；通过 ability process 请求；保存 Store+Clock。 |
| 验证方法 | created/ready/running/paused/blocked/completed/failed/cancelled 状态；retry/recover；跨进程恢复。 |
| 常见错误 | Timer 实时时间当逻辑进度；Process 内核直接伪造 Fact；blocked 自动重试无显式动作。 |

completion kind 当前允许 `none`、`p19_transaction`、`typed_domain_request`。

## 11. SceneSession、PlayerShell 与 UI 反馈

### 11.1 Scene/Task Execution Session

| 项 | 说明 |
|---|---|
| 用途 | 将 Task、SceneRecipe、空间 backend、领域请求和返回/撤离组织为可恢复会话。 |
| 权威数据 | `GMTaskExecutionSession` state，schema `gm.scene.session_snapshot.v1`。 |
| 配置/入口 | `GMSceneSessionDefinition`、SceneRecipe、TaskExecutionContext。 |
| 运行链 | build → open → start → record request → settle → record fact → return/extract/fail/close。 |
| 开发步骤 | 建 Definition/Recipe 指纹；从 travel handoff 或 Task 打开；只接受 committed/blocked result。 |
| 验证方法 | Definition 指纹、Fact/Request 关系、目标完成度、pause/resume、prepare/commit restore。 |
| 常见错误 | 切场丢 Task 身份；场景关闭即自报完成；恢复跳过 Definition 指纹。 |

### 11.2 PlayerShell

| 项 | 说明 |
|---|---|
| 用途 | 组合输入、HUD、维度投影、交互、Task、SceneSession 和保存入口。 |
| 权威数据 | 各领域服务/World/Store；Shell 自身只持组合状态和投影。 |
| 配置/入口 | `GMPlayerShellConfiguration`；P25/EXT11 的 2D/Planar3D entry 是受限样板。项目必须拥有入口适配脚本并断言 active project/profile/world/save。 |
| 运行链 | P25 样板为 input → `dispatch_input_event()` → `handle_action()` → Interaction/Ability/Movement；`handle_action()` 和 action 集不是通用 ABI，下游应通过自己的适配层构造公共 request/command。 |
| 开发步骤 | 为项目建 Shell 配置；绑定玩家、地图、任务、交互、save path；映射动作；构建 HUD。 |
| 验证方法 | 键鼠/手柄动作汇入同入口；切维度不改业务事实；save/restore 走 SimulationWorld。 |
| 常见错误 | HUD 直接写 Task；2D-only 调 3D 时偷偷 fallback；Shell 另建保存 JSON。 |

### 11.3 UI、Feedback 与 Cue

| 项 | 说明 |
|---|---|
| 用途 | 展示状态、错误、动作结果和可感知音画反馈。 |
| 权威数据 | Projection/Snapshot/CommittedResult/Cue；UI 节点不是权威。 |
| 配置/入口 | 正式 HUD、`gm_feedback`、Cue router、Error Center。 |
| 运行链 | committed package → Cue/Projection → HUD/visual/audio；用户操作再产生新 request。 |
| 开发步骤 | 为错误和 blocked reason 提供中文显示；为 Cue 配表现；支持取消/重试但不篡改原结果。 |
| 验证方法 | 状态和 Store 对应；失败提示不造成写入；2D/3D HUD 连续性；真人可理解性验收。 |
| 常见错误 | 按钮显示“成功”但权威没变；Cue 回写事实；吞掉结构化错误只显示通用失败。 |

## 12. Visual Recipe、缓存与预算

### 12.1 派生缓存

角色和 SceneRecipe compile cache 都不是权威。缓存键来自源 Recipe 和依赖指纹；支持 invalidate/delete/clear/rebuild。删除缓存后必须能从 Content + Recipe 重建。`.godot` 也是导入缓存，不进入复制归档或内容权威。

### 12.2 视觉预算

| 项 | 说明 |
|---|---|
| 用途 | 限制 Planar3D 可见动画、完整质量、SkinnedMesh、更新频率和帧时间。 |
| 权威数据 | 项目 `GMCharacterVisualBudgetProfile`；管理器状态只是运行投影。 |
| 配置/入口 | “GM三维预算与验证”；release Profile 的 `budget_profile_path`。 |
| 运行链 | camera/visibility/distance → BudgetManager → Near/Mid/Far/Offscreen → LOD/update scheduling。 |
| 开发步骤 | 从中性预算复制；按项目视口/角色复杂度设置；用代表性 10/30/60 或更大矩阵测试。 |
| 验证方法 | 实际视觉对象、多帧 update、deferred update、frame warning、缓存重建。 |
| 常见错误 | 静默抬阈值消除失败；用中性场景测量替代最终游戏；表现预算改变世界逻辑。 |

当前中性冻结值：near 12、far 32、hysteresis 1、可见动画 30、完整质量 10、SkinnedMesh 60、`animation_update_budget=20` 是每帧动画更新数，`feature_module_budget=20` 是分配给 Near 角色的 Feature 模块总量（不是每帧更新数），动画预算 4ms、frame warning 33.4ms、视口 640×360。

## 13. SimulationWorld、Store 与保存恢复

### 13.1 Simulation Tick

| 项 | 说明 |
|---|---|
| 用途 | 让后台系统只读快照、提交意图并确定性合并。 |
| 权威数据 | `GMSimulationWorld`、EntityRegistry、named Stores、receipts/journal。 |
| 配置/入口 | `GMSimulationSystem`、`GMCommandBuffer`、stage/priority/system ID。 |
| 运行链 | snapshot → sorted systems → isolated buffers → merge/conflict/budget → commit → receipt。 |
| 开发步骤 | 系统只读 `GMWorldSnapshot`；命令声明 snapshot/entity/resolution/version/write_keys/idempotency。 |
| 验证方法 | 顺序确定性、写冲突、预算、单系统失败隔离、重复键、post-receipt journal。 |
| 常见错误 | System 直接改 Store/节点；命令无 expected version；读取快照后试图原地写回。 |

### 13.2 GMStore

| 项 | 说明 |
|---|---|
| 用途 | 保存版本化领域纯数据和派生索引。 |
| 权威数据 | records；schema `gm.store_snapshot.v3`。 |
| 配置/入口 | 稳定 store ID/schema；`put/erase/read/snapshot/restore_snapshot`。 |
| 运行链 | validate persistence → expected version → write → rebuild index → snapshot。 |
| 开发步骤 | 使用稳定业务 key；写纯 Dictionary/Array/数值/字符串；显式并发版本。 |
| 验证方法 | index 与 records 精确一致；损坏索引拒绝；读取副本；跨进程 snapshot。 |
| 常见错误 | key 使用路径；存 Node/RID；恢复时静默修坏索引；多个 Store 表示同一事实。 |

### 13.3 世界文件、迁移与原子恢复

| 项 | 说明 |
|---|---|
| 用途 | 保存完整世界并保证坏输入不会部分改变 live state。 |
| 权威数据 | world file `gm.simulation_world.v6` + named Stores；snapshot `gm.world_snapshot.v2`。 |
| 配置/入口 | Profile `save_path`；`save_world_snapshot/restore_world_snapshot`；AtomicWorldLoadCoordinator。 |
| 运行链 | 读文件 → schema/identity/purity → detached Registry/Stores/graph/contributors → 全部通过 → 最后交换。 |
| 开发步骤 | 扩展状态注册 prepare/commit contributor；prepare 只构造 detached 候选；commit 只能无失败交换。 |
| 验证方法 | 无存档首启；保存退出后独立新进程恢复；坏 schema/缺字段/异项目存档原子拒绝；单一保存根。 |
| 常见错误 | 第二 JSON 根；恢复一半后再校验；缺字段自动补默认；运行时导入旧项目存档。 |

当前迁移只声明 world v6→v6、Store v3→v3，`migration_required=false`。不承诺全历史自动迁移，也不重建缺失的 `visual_recipe_id/facing`。旧版本需要由对应兼容版本离线重导，并单独审查迁移工具。

## 14. 编辑器插件与 Dock 操作

### 14.1 启动与共同规则

Godot 4.6.2 打开工程后，在“项目设置 → 插件”确认 `GM平台编辑器`。插件注册成功会输出 `workbench_enter`，默认显示“GM策划工作台”。所有正式写操作应经过 `EditorUndoRedoManager`：先校验、再提交、支持 Undo/Redo、失败保持旧值、保存后关闭重开。

| Dock | 主要用途 | 最短使用步骤 | 验证重点 |
|---|---|---|---|
| GM策划工作台 | 综合入口、状态与错误中心 | 先检查环境/插件/错误，再进入领域 Dock | `workbench_enter`、结构化错误 |
| GM内容资源库 | 扫描、搜索、影响分析 | 重新索引→筛选→引用分析→Inspector | ID/类型/引用/删除保护 |
| GM地图工作台 | 2D 方格/等距地图 | 新建→图层→画笔→Undo/Redo→保存 | Resource 值、后端健康 |
| GM语义地图 | Region/Route/Anchor/Portal/Camera | 新增→应用→一键验证→保存重开 | 点串、引用、ephemeral 清理 |
| GM对象装配 | Object Definition 入图 | 拖定义→绑定 ID/Anchor→预览修复→应用 | Owner、实例 ID、事务结果 |
| GM角色资产库 | 2D Definition/VisualSet | 导入→动作方向→锚点事件→分别保存 | 外部唯一 VisualSet、帧范围 |
| GM角色NPC装配 | 2D NPC PackedScene | 选 Character/Role/Shape→Anchor→装配→保存 | 当前场景、Owner、稳定身份 |
| GM移动能力 | MovementProfile | 配模式/参数/语义目标→应用→保存 | 数值、目标、travel handoff |
| GM任务工作台 | Task/Objective/Assignment/Reservation | 定义→保存注册→发布→分配/预留 | committed signal、状态机 |
| GM能力浏览器 | Ability/Tag 浏览 | 搜索/分组→创建稳定 tag→打开资源 | tag/ID、Definition 合同 |
| GM事件触发器 | Signal/Event 图 | 选择关系类型→连接/条件/目标→UndoRedo | Signal 与 Fact 分界 |
| GM平面3D地图 | Surface Graph | Graph→Surface→Connection→中文校验→保存 | 悬空引用、UndoRedo |
| GM 三维场景配方策划 | SceneRecipe placements | 新建→拖放→吸附/语义引用→校验→保存 | document namespace、缓存可重建 |
| GM角色3D视觉 | Recipe/Skeleton/Socket | 扫描→引用→骨骼/动作校验→保存 | 稳定 Content ID |
| GM角色3D装配 | 3D actor visual | Actor→Outfit/Palette/Feature→compile | cache 非权威 |
| GM平面战斗与Cue3D | Attack/HitVolume/Cue | 定义攻击→目标/高度容差→命中查询 | 逻辑平面命中、Cue 不写事实 |
| GM渲染风格与材质 | World/UI/Lighting/Dither/Shadow | 选择风格→应用→预算/可读性检查 | 原生 UI 与低分辨率世界分层 |
| Planar 3D中性纵向样板 | 编辑样板 Profile | 指定 Profile→名称/NPC声明→UndoRedo→保存重开 | `actor_specs` 唯一权威、非默认路径 |
| GM三维预算与验证 | 预算和缓存诊断 | 运行预算→定位错误→删/重建缓存 | 实际对象、阈值未静默修改 |

独立插件 `gm_agent_planner`、`gm_feedback`、`gm_p26_vertical_sample` 是专用工具入口，不取代正式领域 Resource 或服务。

### 14.2 Dock 常见故障

- 面板不出现：先查 parse/preload/plugin 注册，不要继续录入。
- 点击成功但值不变：确认 UndoRedo action 真正 commit，并重读 Resource。
- NPC 数量：只能增删 `actor_specs`；`actor_specs.size()` 是投影。
- 非默认 Profile：显式路径缺失/类型错误必须 fail closed，不得回退写默认文件。
- 保存验证：编辑器完整退出后启动第二个 Godot 进程重读；同进程 reload 不等价。

## 15. 调试、诊断与验证

GitHub 清洁发布版包含 `gm_cli.cmd`、`gm_cli_launcher.py` 与 `gm_cli.gd`。launcher 优先读取 `%GODOT_EXE%`，未设置时再从 `PATH` 查找 `godot` 或 `godot4`，并以脚本所在目录作为 `--path` 和工作目录。发布版 CLI 只提供下列五个只读命令：

```cmd
gm_cli.cmd help
gm_cli.cmd environment
gm_cli.cmd compatibility
gm_cli.cmd validate
gm_cli.cmd modules
```

源仓库内部另有测试、插件冒烟、导出冒烟和模块专项验收能力；这些能力依赖已排除的测试树、GUT 或审查产物，不随 GitHub 清洁发布版提供，也不是上述 CLI 的可执行命令。

```cmd
set "PROJECT_ROOT=<absolute project directory>"
set "GODOT_EXE=<absolute path to Godot 4.6.2 console executable>"
"%GODOT_EXE%" --headless --path "%PROJECT_ROOT%" --script "%PROJECT_ROOT%\gm_cli.gd" -- environment
if errorlevel 1 exit /b %errorlevel%
```

诊断顺序：环境/版本 → 插件解析 → Profile/Manifest → dependency scan → 正式入口 → 领域合同 → 保存恢复 → 导出包。不要先清缓存掩盖错误；缓存仅在权威输入确认正确后删除重建。

结构化失败必须包含稳定 code/reason/details，调用方按 code 分支，不解析中文文本。测试证据保留原始失败；修复后追加新的通过记录。

## 16. 扩展规范

新增功能的推荐顺序：

1. 指定唯一权威和稳定 ID/schema。
2. 建 Resource/Definition 和验证器。
3. 所有来源统一构造 Ability request；若改变领域事实且声明非空 `fact_type`，接 Resolver/Transaction；executor-only 行为保留执行器路径；若是表现，建 Cue/Projection。
4. 新建/升级 Module Manifest，声明服务、依赖、路径和迁移。
5. 由项目 Profile/Index 显式启用。
6. 如需 UI，Dock 只编辑权威 Resource 或提交命令，并接入 UndoRedo。
7. 接入 SimulationWorld contributor，而不是另建保存根。
8. 添加正向、负向、幂等、跨进程和非默认 Profile 测试。
9. 分别验证 2D/Planar3D 受影响面和 actual package。
10. 通用修复先回到 GM 中性样板发布新版本；具体游戏再升级锁定依赖。

## 17. 禁止模式

- 场景节点、UI 字段、缓存或 Planner 显示成为领域权威。
- 业务 ID 使用 NodePath、绝对路径、`res://`、`user://`、RID 或实例号。
- 绕过 Host/Transaction 直接写领域 Store。
- 用 GameplayEvent、Cue 或动画完成回调冒充 committed Fact。
- 一个 Context 激活多个空间 backend，或运行时隐藏未裁剪模块。
- 保存 Node/RID/导航/缓存路径，或建立第二存档根。
- 恢复 live state 后再校验，或失败后留下部分修改。
- 显式目标失败时回退默认 Profile/Resource。
- Dock 直接写派生字段、绕过 UndoRedo、以按钮文本证明成功。
- 从活动 GM 工作区散拷平台；复制 tests/reports/.godot/userdata/旧存档。
- 下游游戏直接修改 frozen GM core，或把题材内容反哺平台。
- 用测试入口、同进程 reload 或程序化控件代替正式入口、跨进程和真人 GUI 验收。

## 18. 已知限制

- 仅 Godot 4.6.2 正式验证；4.7.2 未验证。
- Planar3D 不是 Full3D。
- DN-01：附加记录外/内 surface 一致性仍是诊断风险。
- DN-02：退出期 ObjectDB/resources-in-use 诊断仍开放。
- TN-01：历史夹具/运行编排修正，不能用旧证据替代当前入口。
- HX1=`HX1_RETIRED_PLATFORM_INCOMPATIBLE`，不是 PASS。
- 八组人工 GUI 验收仍开放：首用/空状态；视觉裁切缩放；输入焦点拖放；2D/3D 相机/HUD；Definition/中文错误/UndoRedo；保存重开/引用/批量；连续玩家流程反馈；误操作/取消/重试恢复。

具体构建和验收步骤见 [构建发布与验收手册.md](构建发布与验收手册.md)，源码分类见 [源码与扩展点地图.md](源码与扩展点地图.md)。

## GitHub 清洁发布版边界

本文件保留平台功能、架构与研究价值；涉及历史测试环境的内容不代表本发布树可直接执行。GitHub 清洁发布版的 CLI 以当前 `gm_cli.gd` 帮助为准，只提供 `help`、`environment`、`compatibility`、`validate`、`modules` 五个只读命令。源仓库内部的测试、插件冒烟、导出冒烟、模块专项验收、GUT、测试目录、fixture、runner 与审查证据均不随本清洁版提供；接收方应在自己的游戏仓库建立测试与发布流水线。

