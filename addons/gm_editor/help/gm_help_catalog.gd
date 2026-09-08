@tool
class_name GMHelpCatalog
extends RefCounted

const HELP := {
	"home": {"title":"项目首页", "body":"从这里查看当前模板、启用模块和健康状态。模板只改变策划入口，不会复制或删除底层内容。", "action":"先检查项目健康，再选择地图、角色、能力、资源或任务入口。"},
	"map": {"title":"地图入口", "body":"地图入口承载地图、区域、路线和语义锚点的策划工作流。底层地图后端仍由既有适配层负责。", "action":"使用创建向导建立入口，然后在高级模式检查原生场景。"},
	"character": {"title":"角色入口", "body":"角色入口组织角色身份、控制来源和能力组合。角色不复制运行时行为，行动仍通过统一能力请求。", "action":"先选择能力组合，再通过高级模式检查同一场景与 Resource。"},
	"ability": {"title":"能力入口", "body":"能力入口描述触发、条件、执行步骤、效果和表现提示；移动、交互、工作和攻击共用统一 GAS。", "action":"遇到执行器或标签错误时，打开错误中心定位到定义和字段。"},
	"resource": {"title":"资源入口", "body":"资源入口展示稳定业务 ID、引用和分类。业务 ID 与文件路径分离，移动文件不能改变规则身份。", "action":"删除前先检查反向引用，移动后重新运行健康检查。"},
	"task": {"title":"任务入口", "body":"任务入口组织目标、事件、条件与完成状态。任务只提交游戏事件或能力请求，不绕过领域服务。", "action":"用创建向导建立目标，再从错误中心检查事件与引用。"},
	"equipment": {"title":"装备入口", "body":"装备入口通过内容资源与能力授予组合工作，不建立第二套战斗能力。", "action":"检查装备引用和能力组合后再进入原生 Inspector。"},
	"combat": {"title":"战斗区域", "body":"战斗区域是地图与能力验证的策划入口，运行时仍使用同一地图与 GAS 服务。", "action":"先定位区域资源，再检查能力阻断与表现提示。"},
	"building": {"title":"建筑入口", "body":"建筑入口组织建筑、工作点和生产能力；首版经营模板只覆盖普通生产链。", "action":"使用创建向导建立建筑，再配置工作点和生产能力。"},
	"production": {"title":"生产链入口", "body":"生产链使用统一能力组合调用领域生产服务，输入、输出和仓库事务必须可验证。", "action":"先配置资源容器，再检查配方输入输出。"},
	"error": {"title":"统一错误中心", "body":"错误中心聚合项目验证、插件、脚本和导出阻断。每条错误都显示对象、路径、字段、原因、建议和定位状态。", "action":"先定位再修复；资源删除或移动后，定位会安全提示失效而不会崩溃。"},
	"field.template_id": {"title":"模板字段", "body":"模板字段只保存稳定模板 ID。切换前会验证模块、术语和内容保护规则，失败时不会写入 Profile。", "action":"确认健康状态为通过后再保存模板切换。"},
	"field.project_name_zh": {"title":"项目名称字段", "body":"这是任务02演示 Resource 的真实字段，策划模式和高级 Inspector 读写同一资源。", "action":"修改后验证 Undo/Redo，并关闭重开检查保存结果。"},
	"error.template.missing_module": {"title":"模板依赖缺失", "body":"当前模板需要的模块未被 Profile 启用或 Registry 无法解析。", "action":"启用依赖模块或选择满足依赖的模板；阻断期间不会落盘。"},
	"error.template.missing_terminology": {"title":"术语键缺失", "body":"模板引用了不存在或为空的中文术语键，继续切换会产生无法理解的入口。", "action":"补齐术语资源后重新验证。"},
	"error.content.delete": {"title":"内容保护阻断", "body":"模板切换可能删除或丢失已有内容，因此操作被阻断。", "action":"先迁移或保留内容，再重新执行模板切换。"},
	"error.resource.invalid_location": {"title":"定位已失效", "body":"错误仍被记录，但资源路径已删除、移动或插件已关闭。", "action":"重新扫描引用图或从资源库选择新的位置。"},
	"error.plugin.failure": {"title":"插件验证失败", "body":"插件锁定信息或启停状态不满足当前平台基线。", "action":"修复 plugin.cfg 或重新启用插件后重载项目。"},
	"error.script.parse": {"title":"脚本错误", "body":"脚本无法被 Godot 解析或基类不符合约定。", "action":"进入高级模式打开脚本编辑器，修复后重新扫描。"},
	"error.export.blocked": {"title":"导出被阻断", "body":"统一导出 Planner 发现非法依赖、未启用模块或开发资源引用。", "action":"按错误中的 source→target 原因链修复引用，再重新导出。"},
}

static func get_help(entry_id: String, error_code: String = "", field_id: String = "") -> Dictionary:
	if not error_code.is_empty() and HELP.has("error." + error_code):
		return HELP["error." + error_code].duplicate(true)
	if not field_id.is_empty() and HELP.has("field." + field_id):
		return HELP["field." + field_id].duplicate(true)
	return HELP.get(entry_id, HELP.get("home", {})).duplicate(true)
