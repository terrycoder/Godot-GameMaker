@tool
extends VBoxContainer

const SAVE_PATH := "res://samples/agent_planner/p17/planner_profile.json"
const PROFILE_SCHEMA := "gm.agent_planner.workbench.v1"
const PROFILE_FIELDS := ["schema","agent_id","free_action_id","ability_id","schedule_id","role_id","department_id","attention_capacity","retry_trigger"]
var undo_redo:EditorUndoRedoManager
var profile:Dictionary={"schema":PROFILE_SCHEMA,"agent_id":"gm.agent.sample.worker_a","free_action_id":"gm.free_action.sample.rest","ability_id":"gm.ability.movement","schedule_id":"gm.schedule.sample.day","role_id":"gm.role.sample.generalist","department_id":"gm.department.sample.operations","attention_capacity":2,"retry_trigger":"task_changed"}
var agent_edit:LineEdit
var free_edit:LineEdit
var ability_edit:LineEdit
var schedule_edit:LineEdit
var role_edit:LineEdit
var department_edit:LineEdit
var capacity:SpinBox
var retry_edit:LineEdit
var status:RichTextLabel

func configure(manager:EditorUndoRedoManager)->void:undo_redo=manager

func _ready()->void:
	name="P17 Agent决策工作台"
	add_child(_title("Agent决策工作台"));add_child(_hint("配置AgentContext、Task/FreeAction评分、只读日程/职位上下文、ActivationPolicy、事件重试与Attention预算。"))
	agent_edit=_field("Agent稳定ID",profile.agent_id);free_edit=_field("无Task时的FreeAction ID",profile.free_action_id);ability_edit=_field("Ability ID（只提交请求）",profile.ability_id)
	add_child(_title("日程与职位上下文（只读）"));schedule_edit=_field("Schedule ID",profile.schedule_id);role_edit=_field("职位/Role ID",profile.role_id);department_edit=_field("部门 ID",profile.department_id)
	add_child(_title("阻断与显式事件重试"));retry_edit=_field("RetryTrigger",profile.retry_trigger)
	var row:=HBoxContainer.new();var label:=Label.new();label.text="Attention可见预算";row.add_child(label);capacity=SpinBox.new();capacity.min_value=0;capacity.max_value=64;capacity.value=profile.attention_capacity;row.add_child(capacity);add_child(row)
	var buttons:=HBoxContainer.new()
	for spec in [["校验配置",_validate],["保存",_save],["重新打开",_reopen],["撤销",_undo],["重做",_redo]]:
		var button:=Button.new();button.text=spec[0];button.pressed.connect(spec[1]);buttons.add_child(button)
	add_child(buttons);status=RichTextLabel.new();status.fit_content=true;status.custom_minimum_size=Vector2(260,90);status.text="就绪：Planner只读取上下文，动作经AbilityHost提交。";add_child(status)

func _field(label_text:String,value:String)->LineEdit:
	var row:=VBoxContainer.new();var label:=Label.new();label.text=label_text;row.add_child(label);var edit:=LineEdit.new();edit.text=value;edit.placeholder_text="请输入稳定英文ID";row.add_child(edit);add_child(row);return edit

func _candidate_from_controls()->Dictionary:
	return {"schema":PROFILE_SCHEMA,"agent_id":agent_edit.text,"free_action_id":free_edit.text,"ability_id":ability_edit.text,"schedule_id":schedule_edit.text,"role_id":role_edit.text,"department_id":department_edit.text,"attention_capacity":int(capacity.value),"retry_trigger":retry_edit.text}

func _validate_profile(value:Variant)->Dictionary:
	if typeof(value)!=TYPE_DICTIONARY:return _invalid("planner.workbench.profile_type_invalid","配置必须是Dictionary。")
	var candidate:Dictionary=value
	if not _exact(candidate,PROFILE_FIELDS) or typeof(candidate.schema)!=TYPE_STRING or candidate.schema!=PROFILE_SCHEMA:return _invalid("planner.workbench.schema_invalid","配置schema或字段集合无效。")
	for key in ["agent_id","free_action_id","ability_id","schedule_id","role_id","department_id","retry_trigger"]:
		if typeof(candidate[key])!=TYPE_STRING or not GMTaskDefinition._stable_id(candidate[key]):return _invalid("planner.workbench.id_invalid","%s必须是稳定英文ID。"%key)
	if typeof(candidate.attention_capacity)!=TYPE_INT or candidate.attention_capacity<0 or candidate.attention_capacity>64:return _invalid("planner.workbench.capacity_invalid","Attention预算必须是0—64整数。")
	return {"ok":true,"value":candidate.duplicate(true)}

func _validate()->void:
	var live_check:=_validate_profile(profile)
	if not live_check.ok:status.text="配置失败：%s（%s）"%[live_check.reason_zh,live_check.code];return
	var checked:=_validate_profile(_candidate_from_controls())
	if not checked.ok:status.text="配置失败：%s（%s）"%[checked.reason_zh,checked.code];return
	status.text="配置有效：当前Controls已验证；Task与FreeAction互斥；Attention预算不会改变Planner选择。"

func _save()->void:
	var live_check:=_validate_profile(profile)
	if not live_check.ok:status.text="保存失败：%s；live、磁盘和撤销历史未改变（%s）"%[live_check.reason_zh,live_check.code];return
	var checked:=_validate_profile(_candidate_from_controls())
	if not checked.ok:status.text="保存失败：%s；live、磁盘和撤销历史未改变（%s）"%[checked.reason_zh,checked.code];return
	var stored:=_store_atomic(checked.value)
	if not stored.ok:status.text="保存失败：磁盘事务未提交，live和撤销历史未改变（%s）"%stored.code;return
	_commit_profile("保存Agent Planner配置",checked.value)
	status.text="保存成功：Controls、live profile与磁盘事务已提交，可重新打开验证。"

func _store_atomic(candidate:Dictionary)->Dictionary:
	var temporary:=SAVE_PATH+".tmp";var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return {"ok":false,"code":"planner.workbench.temp_open_failed"}
	file.store_string(JSON.stringify(candidate,"  ",true,true));file.close()
	var verify_file:=FileAccess.open(temporary,FileAccess.READ)
	if verify_file==null:DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary));return {"ok":false,"code":"planner.workbench.temp_reopen_failed"}
	var parsed:Variant=JSON.parse_string(verify_file.get_as_text());verify_file.close();var normalized:=_profile_from_json(parsed);var verified:=_validate_profile(normalized.get("value",{}))
	if not verified.ok or verified.value!=candidate:DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary));return {"ok":false,"code":"planner.workbench.temp_verify_failed"}
	var destination:=ProjectSettings.globalize_path(SAVE_PATH);var temp_absolute:=ProjectSettings.globalize_path(temporary);var previous:=""
	if FileAccess.file_exists(SAVE_PATH):var old:=FileAccess.open(SAVE_PATH,FileAccess.READ);if old!=null:previous=old.get_as_text();old.close();DirAccess.remove_absolute(destination)
	var renamed:=DirAccess.rename_absolute(temp_absolute,destination)
	if renamed!=OK:
		if not previous.is_empty():var restore_file:=FileAccess.open(SAVE_PATH,FileAccess.WRITE);if restore_file!=null:restore_file.store_string(previous);restore_file.close()
		return {"ok":false,"code":"planner.workbench.atomic_rename_failed"}
	return {"ok":true}

func _reopen()->void:
	var file:=FileAccess.open(SAVE_PATH,FileAccess.READ)
	if file==null:status.text="重新打开失败：尚无已保存配置（planner.workbench.file_missing）";return
	var parsed:Variant=JSON.parse_string(file.get_as_text());file.close();var normalized:=_profile_from_json(parsed)
	if not normalized.ok:status.text="重新打开失败：磁盘配置不合法，当前Controls与live保持不变（%s）"%normalized.code;return
	var checked:=_validate_profile(normalized.value)
	if not checked.ok:status.text="重新打开失败：磁盘配置不合法，当前Controls与live保持不变（%s）"%checked.code;return
	_set_profile(checked.value);status.text="重新打开成功：磁盘配置与正式Controls已同步。"

func _commit_profile(action_name:String,value:Dictionary)->void:
	var next:=value.duplicate(true);var old:=profile.duplicate(true)
	if undo_redo==null:_set_profile(next);return
	undo_redo.create_action(action_name);undo_redo.add_do_method(self,"_set_profile",next);undo_redo.add_undo_method(self,"_set_profile",old);undo_redo.commit_action()

func _profile_from_json(value:Variant)->Dictionary:
	if typeof(value)!=TYPE_DICTIONARY or not _exact(value,PROFILE_FIELDS):return _invalid("planner.workbench.json_fields_invalid","JSON字段集合无效。")
	var number:Variant=value.get("attention_capacity")
	if typeof(number)!=TYPE_FLOAT or not is_finite(number) or number!=floor(number) or number<0 or number>64:return _invalid("planner.workbench.capacity_invalid","JSON Attention预算无效。")
	var result:Dictionary={"schema":value.get("schema"),"agent_id":value.get("agent_id"),"free_action_id":value.get("free_action_id"),"ability_id":value.get("ability_id"),"schedule_id":value.get("schedule_id"),"role_id":value.get("role_id"),"department_id":value.get("department_id"),"attention_capacity":int(number),"retry_trigger":value.get("retry_trigger")}
	return {"ok":true,"value":result}

# Kept as a narrow automation hook for the formal editor capture. UI edits do
# not call this; buttons always transact a complete isolated candidate.
func _commit(action_name:String,key:String,value:Variant)->void:
	var candidate:=profile.duplicate(true);candidate[key]=value;var checked:=_validate_profile(candidate)
	if checked.ok:_commit_profile(action_name,checked.value)

func _set_profile(value:Dictionary)->void:profile=value.duplicate(true);_sync()
func _sync()->void:
	if agent_edit==null:return
	agent_edit.text=profile.agent_id;free_edit.text=profile.free_action_id;ability_edit.text=profile.ability_id;schedule_edit.text=profile.schedule_id;role_edit.text=profile.role_id;department_edit.text=profile.department_id;retry_edit.text=profile.retry_trigger;capacity.value=profile.attention_capacity

func _undo()->void:
	var history:=_history();if history!=null and history.has_undo():history.undo();status.text="已撤销上一项合法配置事务。"
func _redo()->void:
	var history:=_history();if history!=null and history.has_redo():history.redo();status.text="已重做上一项合法配置事务。"
func _history()->UndoRedo:return undo_redo.get_history_undo_redo(0) if undo_redo!=null else null
func _exact(value:Dictionary,fields:Array)->bool:
	if value.size()!=fields.size():return false
	for field in fields:
		if not value.has(field):return false
	return true
func _invalid(code:String,reason:String)->Dictionary:return {"ok":false,"code":code,"reason_zh":reason}
func _title(text:String)->Label:var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",18);return label
func _hint(text:String)->Label:var label:=Label.new();label.text=text;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;return label
