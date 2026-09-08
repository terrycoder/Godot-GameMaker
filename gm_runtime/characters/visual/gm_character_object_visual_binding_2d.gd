@tool
class_name GMCharacterObjectVisualBinding2D
extends Node2D

@export var visual_set: GMCharacterVisualSet2D
var presenter: GMCharacterPresenter2D

func _ready() -> void:
	if visual_set != null: call_deferred("_restore_presenter")

func swap_visual_set(candidate: GMCharacterVisualSet2D) -> Dictionary:
	if candidate == null: return _failure("character.object_visual_missing", "对象外观替换缺少 VisualSet。")
	var validation := candidate.validate_visual_set()
	if not validation.ok: return _failure("character.object_visual_invalid", "对象外观替换验证失败，旧外观保持。", {"issues":validation.issues})
	var staged := GMCharacterPresenter2D.new()
	var configured := staged.configure(candidate)
	if not configured.ok:
		staged.free()
		return _failure("character.object_visual_presenter_rejected", "Presenter 拒绝新外观，旧外观保持。", {"cause":configured})
	if presenter != null and is_instance_valid(presenter): presenter.free()
	presenter = staged; presenter.name = "CharacterVisualPresenter"; add_child(presenter)
	visual_set = candidate
	return {"ok":true,"visual_set_id":candidate.visual_set_id,"presenter_class":"GMCharacterPresenter2D","failure_closed":true}

func _restore_presenter() -> void:
	if presenter == null or not is_instance_valid(presenter): swap_visual_set(visual_set)

func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok":false,"code":code,"error_zh":message,"details":details,"failure_closed":true}
