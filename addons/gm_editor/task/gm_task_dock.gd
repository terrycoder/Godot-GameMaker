class_name GMTaskDock
extends VBoxContainer

var editor_plugin: EditorPlugin
var undo_redo: EditorUndoRedoManager
var definition: GMTaskDefinition
var resource_path := "res://samples/p16_task/task_definition.tres"
var fields: Dictionary = {}
var status_label: Label
var task_service := GMTaskService.new()
var task_host := GMAbilitySystemHost.new()

func configure(plugin: EditorPlugin) -> void:
	editor_plugin = plugin
	undo_redo = plugin.get_undo_redo()
	name = "GMTaskDock"
	custom_minimum_size = Vector2(0, 350)
	_build_ui()
	set_capture_definition(GMTaskDefinition.new(), resource_path)

func _build_ui() -> void:
	var title := Label.new(); title.text = "P16 统一Task工作台"; title.add_theme_font_size_override("font_size", 22); add_child(title)
	var intro := Label.new(); intro.text = "同一事实域管理 Task、Objective、Assignment、DutyProvider 与 Reservation；执行统一进入 Ability → Resolver → Transaction。"; intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(intro)
	var grid := GridContainer.new(); grid.columns = 4; grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; add_child(grid)
	_add_line(grid, "Task定义ID", "definition_id", "稳定英文ID，例如 gm.task.definition.sample_transport")
	_add_line(grid, "中文显示名", "display_name_zh", "策划可见名称")
	_add_line(grid, "中文说明", "description_zh", "任务意图与边界")
	_add_line(grid, "Objective ID", "objective_id", "稳定英文ID")
	_add_line(grid, "目标中文名", "objective_name_zh", "目标的策划可见名称")
	var signal_box:=HBoxContainer.new();var signal_kind := OptionButton.new(); signal_kind.name = "SignalKind"
	for pair in [["事实 Fact","fact"],["变更 Change","change"],["提示 Cue","cue"]]: signal_kind.add_item(pair[0]); signal_kind.set_item_metadata(signal_kind.item_count-1,pair[1])
	var signal_type:=LineEdit.new();signal_type.name="SignalType";signal_type.placeholder_text="gm.fact.* / gm.change.* / gm.cue.*";signal_type.size_flags_horizontal=Control.SIZE_EXPAND_FILL;signal_box.add_child(signal_kind);signal_box.add_child(signal_type)
	_add_control(grid,"推进信号",signal_box,"中文选择类别；稳定英文类型必须与类别一致"); fields.signal_kind=signal_kind;fields.signal_type=signal_type
	_add_line(grid, "目标值", "target_value", "正整数")
	_add_line(grid, "匹配资源ID", "resource_id", "目标匹配条件；稳定英文ID")
	var source := OptionButton.new(); source.name = "SourceType"
	for pair in [["玩家","player"],["AI","ai"],["组织","organization"],["世界事件","world_event"],["脚本","script"],["职责Provider","duty_provider"]]:
		source.add_item(pair[0]); source.set_item_metadata(source.item_count - 1, pair[1])
	_add_control(grid,"发布来源",source,"显示中文，持久值保持英文"); fields.source_type = source
	var context := OptionButton.new(); context.name = "ContextMode"
	for pair in [["本地执行","local"],["摘要执行","summary"],["场景上下文声明","scene"]]:
		context.add_item(pair[0]); context.set_item_metadata(context.item_count - 1,pair[1])
	_add_control(grid,"执行上下文",context,"仅声明上下文，不创建SceneSession"); fields.context_mode = context
	_add_line(grid, "Task实例ID", "task_id", "发布到统一Task事实域的稳定ID")
	_add_line(grid, "父Task ID（可空）", "parent_task_id", "子Task只引用统一Task事实")
	_add_line(grid, "Assignment ID", "assignment_id", "统一Assignment事实的稳定ID")
	var assignment_kind := OptionButton.new(); assignment_kind.name = "AssignmentKind"
	for pair in [["角色","actor"],["群组","group"],["职责角色","role"],["部门","department"]]: assignment_kind.add_item(pair[0]); assignment_kind.set_item_metadata(assignment_kind.item_count-1,pair[1])
	_add_control(grid,"受派类型",assignment_kind,"显示中文，持久值保持英文");fields.assignment_kind=assignment_kind
	_add_line(grid, "受派对象类型", "assignee_type", "例如 gm.actor")
	_add_line(grid, "受派对象ID", "assignee_id", "稳定英文ID")
	_add_line(grid, "Reservation规则ID", "reservation_rule_id", "Definition中的稳定权威规则")
	_add_line(grid, "Reservation主体类型", "reservation_subject_type", "例如 resource")
	_add_line(grid, "Reservation主体ID", "reservation_subject_id", "稳定资源ID")
	var mode := OptionButton.new(); mode.name = "ReservationMode"
	for pair in [["独占","exclusive"],["容量","capacity"]]:
		mode.add_item(pair[0]); mode.set_item_metadata(mode.item_count - 1,pair[1])
	_add_control(grid,"Reservation模式",mode,"统一Reservation事实源"); fields.reservation_mode = mode
	_add_line(grid, "Reservation容量", "reservation_capacity", "容量模式总量；独占模式使用1")
	_add_line(grid, "Reservation实例ID", "reservation_id", "取得占用的稳定ID")
	_add_line(grid, "Reservation数量", "reservation_amount", "独占为1，容量模式为正整数")
	_add_line(grid, "到期逻辑tick", "reservation_expires", "显式逻辑时钟；不使用墙钟")
	_add_line(grid, "DutyProvider ID", "provider_id", "职责Provider稳定ID")
	_add_line(grid, "Duty事件类型", "provider_event_type", "显式gm.fact.*事件类型")
	_add_line(grid, "Duty幂等键字段", "provider_key_field", "事件data中的稳定键字段")
	_add_line(grid, "Duty主体类型", "provider_subject_type", "职责主体稳定类型")
	_add_line(grid, "Duty主体ID", "provider_subject_id", "职责主体稳定ID")
	var actions := HBoxContainer.new(); add_child(actions)
	for spec in [["应用修改","ApplyButton","_on_apply"],["撤销","UndoButton","_on_undo"],["重做","RedoButton","_on_redo"],["保存资源","SaveButton","_on_save"],["注册定义","RegisterButton","_on_register"],["发布Task","PublishButton","_on_publish"],["建立分配","AssignButton","_on_assign"],["注册职责Provider","ProviderButton","_on_provider"],["取得Reservation","ReservationButton","_on_reservation"]]:
		var button := Button.new(); button.text = spec[0]; button.name = spec[1]; button.pressed.connect(Callable(self,spec[2])); actions.add_child(button)
	status_label = Label.new(); status_label.name = "StatusLabel"; status_label.text = "就绪：请填写中文名称与稳定英文ID。"; status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(status_label)

func _add_line(grid: GridContainer, label_text: String, key: String, tooltip: String) -> void:
	var edit := LineEdit.new(); edit.name = key.to_pascal_case(); edit.tooltip_text = tooltip; _add_control(grid,label_text,edit,tooltip); fields[key] = edit

func _add_control(grid: GridContainer, label_text: String, control: Control, tooltip: String) -> void:
	var label := Label.new(); label.text = label_text; label.tooltip_text = tooltip; grid.add_child(label); control.size_flags_horizontal = Control.SIZE_EXPAND_FILL; control.tooltip_text = tooltip; grid.add_child(control)

func set_capture_definition(value: GMTaskDefinition, path: String) -> void:
	definition = value
	resource_path = path
	_load_controls()

func _load_controls() -> void:
	if definition == null: return
	fields.definition_id.text = definition.definition_id
	fields.display_name_zh.text = definition.display_name_zh
	fields.description_zh.text = definition.description_zh
	var objective: Dictionary = definition.objectives[0] if not definition.objectives.is_empty() else {}
	fields.objective_id.text = str(objective.get("objective_id","")); fields.objective_name_zh.text = str(objective.get("display_name_zh","")); _select_metadata(fields.signal_kind,str(objective.get("signal_kind","fact"))); fields.signal_type.text = str(objective.get("signal_type","")); fields.target_value.text = str(objective.get("target_value",1)); fields.resource_id.text = str(objective.get("target_match",{}).get("resource_id",""))
	_select_metadata(fields.context_mode, definition.default_context_mode)
	var profile:Dictionary=definition.workbench_profile
	_select_metadata(fields.source_type,str(profile.get("source_type","player")));fields.task_id.text=str(profile.get("task_id",""));fields.parent_task_id.text=str(profile.get("parent_task_id",""));fields.assignment_id.text=str(profile.get("assignment_id",""));_select_metadata(fields.assignment_kind,str(profile.get("assignment_kind","actor")))
	var assignee:Dictionary=profile.get("assignee",{});fields.assignee_type.text=str(assignee.get("type","actor"));fields.assignee_id.text=str(assignee.get("id",""))
	var rule:Dictionary=definition.reservation_rules[0] if not definition.reservation_rules.is_empty() else {};fields.reservation_rule_id.text=str(rule.get("rule_id",""));var subject:Dictionary=rule.get("subject",{});fields.reservation_subject_type.text=str(subject.get("type","resource"));fields.reservation_subject_id.text=str(subject.get("id",""));_select_metadata(fields.reservation_mode,str(rule.get("mode","exclusive")));fields.reservation_capacity.text=str(rule.get("capacity",1))
	var reservation:Dictionary=profile.get("reservation",{});fields.reservation_id.text=str(reservation.get("reservation_id",""));fields.reservation_amount.text=str(reservation.get("amount",1));fields.reservation_expires.text=str(reservation.get("expires_at_tick",10))
	var provider:Dictionary=profile.get("provider",{});fields.provider_id.text=str(provider.get("provider_id",""));fields.provider_event_type.text=str(provider.get("event_type",""));fields.provider_key_field.text=str(provider.get("key_field",""));var provider_subject:Dictionary=provider.get("subject",{});fields.provider_subject_type.text=str(provider_subject.get("type","resource"));fields.provider_subject_id.text=str(provider_subject.get("id",""))

func _candidate() -> Dictionary:
	var rule:={"rule_id":fields.reservation_rule_id.text,"subject":{"type":fields.reservation_subject_type.text,"id":fields.reservation_subject_id.text},"mode":str(fields.reservation_mode.get_selected_metadata()),"capacity":maxi(1,int(fields.reservation_capacity.text))}
	var profile:={"source_type":str(fields.source_type.get_selected_metadata()),"task_id":fields.task_id.text,"parent_task_id":fields.parent_task_id.text,"assignment_id":fields.assignment_id.text,"assignment_kind":str(fields.assignment_kind.get_selected_metadata()),"assignee":{"type":fields.assignee_type.text,"id":fields.assignee_id.text},"provider":{"provider_id":fields.provider_id.text,"event_type":fields.provider_event_type.text,"key_field":fields.provider_key_field.text,"subject":{"type":fields.provider_subject_type.text,"id":fields.provider_subject_id.text}},"reservation":{"reservation_id":fields.reservation_id.text,"rule_id":fields.reservation_rule_id.text,"amount":int(fields.reservation_amount.text),"expires_at_tick":int(fields.reservation_expires.text)}}
	return {"schema_version":GMTaskDefinition.SCHEMA_VERSION,"definition_id":fields.definition_id.text,"display_name_zh":fields.display_name_zh.text,"description_zh":fields.description_zh.text,"objectives":[{"objective_id":fields.objective_id.text,"display_name_zh":fields.objective_name_zh.text,"signal_kind":str(fields.signal_kind.get_selected_metadata()),"signal_type":fields.signal_type.text,"target_value":int(fields.target_value.text),"contribution_field":"amount","target_match":{"resource_id":fields.resource_id.text}}],"allowed_source_types":["player","ai","organization","world_event","script","duty_provider"],"default_context_mode":str(fields.context_mode.get_selected_metadata()),"reservation_rules":[rule],"workbench_profile":profile}

func _on_apply() -> void:
	var probe := GMTaskDefinition.new(); var applied := probe.apply_dict(_candidate())
	if not applied.get("ok",false): status_label.text = "校验失败：%s" % "；".join(applied.get("errors",[applied.get("reason_zh","")])); return
	var before := definition.to_dict(); var after := probe.to_dict()
	undo_redo.create_action("更新统一Task定义"); undo_redo.add_do_method(definition,"apply_dict",after); undo_redo.add_undo_method(definition,"apply_dict",before); undo_redo.commit_action()
	status_label.text = "已应用：Task定义通过严格校验，可撤销/重做。"

func _on_undo() -> void:
	var history := _history(); if history != null and history.has_undo(): history.undo(); _load_controls(); status_label.text = "已撤销上一项Task定义修改。"

func _on_redo() -> void:
	var history := _history(); if history != null and history.has_redo(): history.redo(); _load_controls(); status_label.text = "已重做Task定义修改。"

func _on_save() -> void:
	var check := definition.validate_definition()
	if not check.ok: status_label.text = "保存失败：当前定义未通过严格校验。"; return
	var absolute := ProjectSettings.globalize_path(resource_path); DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var temp_path := "%s/.%s.p16_candidate_%d.tres" % [resource_path.get_base_dir(),resource_path.get_file().get_basename(),Time.get_ticks_usec()]; var temp_absolute:=ProjectSettings.globalize_path(temp_path); var err := ResourceSaver.save(definition,temp_path)
	if err == OK:
		var reopened:=ResourceLoader.load(temp_path,"",ResourceLoader.CACHE_MODE_IGNORE) as GMTaskDefinition
		if reopened == null or not reopened.validate_definition().ok: err=ERR_FILE_CORRUPT
	if err == OK:
		if FileAccess.file_exists(absolute): DirAccess.remove_absolute(absolute)
		err = DirAccess.rename_absolute(temp_absolute,absolute)
	if err != OK and FileAccess.file_exists(temp_absolute): DirAccess.remove_absolute(temp_absolute)
	status_label.text = "保存成功：%s" % resource_path if err == OK else "保存失败：错误码 %d，原目标未被部分写入。" % err

func _on_register() -> void:
	_show_transaction("注册定义",task_service.submit_operation(task_host,"register_definition",definition.to_dict(),"script","gm.script.task_workbench",_operation_key("register_definition",definition.to_dict())))

func _on_publish() -> void:
	var profile:Dictionary=definition.workbench_profile;var payload:={"task_id":profile.task_id,"definition_id":definition.definition_id,"parent_task_id":profile.parent_task_id,"group_id":"","execution_context":{"mode":definition.default_context_mode,"stable_context":{}}}
	_show_transaction("发布Task",task_service.submit_operation(task_host,"publish_task",payload,profile.source_type,_source_id(profile.source_type),_operation_key("publish_task",payload)))

func _on_assign() -> void:
	var profile:Dictionary=definition.workbench_profile;var payload:={"assignment_id":profile.assignment_id,"task_id":profile.task_id,"assignee":profile.assignee.duplicate(true),"kind":profile.assignment_kind}
	_show_transaction("建立分配",task_service.submit_operation(task_host,"assign",payload,"script","gm.script.task_workbench",_operation_key("assign",payload)))

func _on_provider() -> void:
	var profile:Dictionary=definition.workbench_profile;var provider:Dictionary=profile.provider;var payload:={"provider_id":provider.provider_id,"definition_id":definition.definition_id,"event_type":provider.event_type,"key_field":provider.key_field,"subject":provider.subject.duplicate(true)}
	_show_transaction("注册职责Provider",task_service.submit_operation(task_host,"register_duty_provider",payload,"script","gm.script.task_workbench",_operation_key("register_duty_provider",payload)))

func _on_reservation() -> void:
	var profile:Dictionary=definition.workbench_profile;var reservation:Dictionary=profile.reservation;var rule:Dictionary=_reservation_rule(str(reservation.rule_id))
	if rule.is_empty():status_label.text="Reservation失败：Definition中找不到权威规则。";return
	var payload:={"reservation_id":reservation.reservation_id,"task_id":profile.task_id,"assignment_id":profile.assignment_id,"owner":profile.assignee.duplicate(true),"subject":rule.subject.duplicate(true),"rule_id":rule.rule_id,"amount":reservation.amount,"expires_at_tick":reservation.expires_at_tick}
	_show_transaction("取得Reservation",task_service.submit_operation(task_host,"acquire_reservation",payload,"script","gm.script.task_workbench",_operation_key("acquire_reservation",payload)))

func _reservation_rule(rule_id:String)->Dictionary:
	for value:Dictionary in definition.reservation_rules:
		if str(value.get("rule_id",""))==rule_id:return value.duplicate(true)
	return {}

func _show_transaction(label:String,value:Variant)->void:
	if value is GMCommittedFactResult:status_label.text="%s成功：已提交统一Fact/Change/Cue。"%label
	elif value is GMBlockedResult:status_label.text="%s失败：%s（%s）"%[label,value.reason_zh,value.error_code]
	else:status_label.text="%s失败：未返回可审计事务结果。"%label

func _operation_key(operation:String,payload:Dictionary)->String:
	return "p16.workbench.%s.%s"%[operation,JSON.stringify(GMStableData.persistence_canonical(payload),"",true,true).sha256_text()]

func _source_id(source_type:String)->String:
	return "gm.source.task_workbench.%s"%source_type

func _history() -> UndoRedo:
	if undo_redo == null or definition == null: return null
	return undo_redo.get_history_undo_redo(undo_redo.get_object_history_id(definition))

func get_capture_snapshot() -> Dictionary:
	return {"panel_title":"P16 统一Task工作台","chinese_first":true,"uses_editor_undo_redo":undo_redo != null,"resource_path":resource_path,"definition":definition.to_dict(),"candidate":_candidate(),"task_domain":task_service.domain_snapshot(),"fact_count":task_service.fact_store.get_record_count(),"source_internal":fields.source_type.get_selected_metadata(),"context_internal":fields.context_mode.get_selected_metadata(),"reservation_internal":fields.reservation_mode.get_selected_metadata(),"status_zh":status_label.text,"boundaries_zh":["执行不直写角色、地图或物品","Objective只消费权威存储中的已提交事件","Scene上下文仅声明，不实现SceneSession"]}

func _select_metadata(option: OptionButton, value: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value: option.select(index); return
