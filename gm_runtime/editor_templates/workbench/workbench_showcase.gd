@tool
extends Node2D

@export var subject: Resource

func _process(_delta: float) -> void:
	var label := get_node_or_null("Summary") as Label
	if label == null or subject == null: return
	label.text = "%s\n%s\n资源修订：%s" % [str(subject.get("project_name_zh")), str(subject.get("scene_note_zh")), str(subject.get("revision"))]
