@tool
class_name GMContentReference
extends Resource

## 可编辑的声明式业务 ID 引用。它不是运行时对象指针，移动文件不会改变身份。
@export var target_id: String = ""
@export var expected_type_id: String = ""
@export var relation_kind: String = "content"
@export var field_name_zh: String = "内容引用"
@export var optional: bool = false
