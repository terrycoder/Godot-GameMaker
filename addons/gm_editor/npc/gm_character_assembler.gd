@tool
class_name GMCharacterAssembler
extends RefCounted

static func validate_inputs(visual_set: GMCharacterVisualSet2D, role: GMRoleProfile, collision: Shape2D, map_id: String, spawn_anchor_id: String) -> Dictionary:
	if visual_set == null: return _fail("character.assemble_visual_missing", "装配被阻止：请选择任务11外观包。")
	if role == null: return _fail("character.assemble_role_missing", "装配被阻止：请选择身份。")
	var role_check := role.validate_profile()
	if not role_check.ok: return role_check
	if collision == null: return _fail("character.assemble_collision_missing", "装配被阻止：请选择碰撞形状。")
	if map_id.strip_edges().is_empty(): return _fail("character.assemble_map_missing", "装配被阻止：缺少地图稳定 ID。")
	if spawn_anchor_id.strip_edges().is_empty(): return _fail("character.assemble_anchor_missing", "装配被阻止：缺少任务09出生锚点。")
	return {"ok":true}

static func assemble(visual_set: GMCharacterVisualSet2D, role: GMRoleProfile, collision: Shape2D, map_id: String, spawn_anchor_id: String, stable_instance_id: String = "") -> Dictionary:
	var check := validate_inputs(visual_set, role, collision, map_id, spawn_anchor_id)
	if not check.ok: return check
	var character := GMCharacterRuntime2D.new()
	character.name = "GMCharacterRuntime2D"
	character.visual_set = visual_set; character.role_profile = role; character.map_id = map_id; character.spawn_anchor_id = spawn_anchor_id
	character.stable_instance_id = stable_instance_id if not stable_instance_id.strip_edges().is_empty() else "gm.character.%s" % ("%s|%s|%d" % [map_id,spawn_anchor_id,Time.get_ticks_usec()]).sha256_text().left(24)
	var shape := CollisionShape2D.new(); shape.name = "CollisionShape2D"; shape.shape = collision; character.add_child(shape); shape.owner = character
	var result := character.ensure_components()
	if not result.ok: character.free(); return result
	for child in character.get_children(): child.owner = character
	return {"ok":true,"character":character,"stable_instance_id":character.stable_instance_id,"reuses":{"semantic_anchor":true,"task10_assembly_pattern":true,"task11_presenter":true,"gas_only":true}}

static func pack_and_save(character: GMCharacterRuntime2D, path: String) -> Dictionary:
	if character == null: return _fail("character.pack_missing", "没有可保存的角色实例。")
	var packed := PackedScene.new(); var packed_err := packed.pack(character)
	if packed_err != OK: return _fail("character.pack_failed", "角色场景打包失败。", {"error":packed_err})
	var save_err := ResourceSaver.save(packed,path)
	return {"ok":save_err == OK,"path":path,"error":save_err,"stable_instance_id":character.stable_instance_id}

static func _fail(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok":false,"code":code,"error_zh":message,"details":details}
