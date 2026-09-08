class_name GMSemanticMaterialMapping
extends RefCounted

## Material Mapping 是唯一的语义到视觉材质解析边界。
## 缺失项只产生可追踪的 warning，并确定性地回退到 fallback_material_id。

const SEMANTIC_KINDS := ["Wood", "Stone", "Cloth", "Skin", "Hair", "Metal", "Ceramic", "Paper", "Plant", "Water"]
var mapping: Dictionary = {}
var fallback_material_id: String = "gm.material.semantic.Wood.neutral"
var mapping_id: String = "gm.material.mapping.neutral"

func _init(initial_mapping: Dictionary = {}) -> void:
	if initial_mapping.is_empty():
		for kind in SEMANTIC_KINDS: mapping[kind] = "gm.material.semantic.%s.neutral" % kind
	else:
		for key in initial_mapping.keys(): mapping[str(key)] = str(initial_mapping[key])

static func default_neutral() -> GMSemanticMaterialMapping:
	return GMSemanticMaterialMapping.new()

func validate() -> Dictionary:
	var errors: Array[String] = []
	if mapping_id.strip_edges().is_empty(): errors.append("material_mapping.id_missing：Material Mapping ID不能为空。")
	if fallback_material_id.strip_edges().is_empty(): errors.append("material_mapping.fallback_missing：缺少确定性fallback材质。")
	for kind in SEMANTIC_KINDS:
		if not mapping.has(kind) or str(mapping[kind]).strip_edges().is_empty(): errors.append("material_mapping.entry_missing：缺少%s语义映射。" % kind)
	return {"ok": errors.is_empty(), "code": "material_mapping.valid" if errors.is_empty() else "material_mapping.invalid", "errors_zh": errors, "error_zh": "Material Mapping校验通过。" if errors.is_empty() else str(errors[0]), "failure_closed": true}

func register(semantic_kind: String, material_id: String) -> Dictionary:
	if semantic_kind not in SEMANTIC_KINDS: return _failure("material_mapping.kind_invalid", "未知语义材质：%s" % semantic_kind)
	if material_id.strip_edges().is_empty(): return _failure("material_mapping.material_id_missing", "材质ID不能为空，映射未提交。")
	mapping[semantic_kind] = material_id
	return {"ok": true, "code": "material_mapping.registered", "semantic_kind": semantic_kind, "material_id": material_id}

func resolve(semantic_kind: String, available_materials: Dictionary = {}) -> Dictionary:
	if semantic_kind not in SEMANTIC_KINDS: return _failure("material_mapping.kind_invalid", "未知语义材质：%s" % semantic_kind)
	var requested_id := str(mapping.get(semantic_kind, ""))
	if requested_id.is_empty(): return _fallback(semantic_kind, "缺少语义映射，已回退到fallback材质。")
	if available_materials.has(requested_id):
		return {"ok": true, "code": "material_mapping.resolved", "semantic_kind": semantic_kind, "material_id": requested_id, "fallback": false, "warning_zh": ""}
	return _fallback(semantic_kind, "语义材质资源不存在，已回退到fallback材质。")

func resolve_material(semantic_kind: String, available_materials: Dictionary = {}) -> Dictionary:
	return resolve(semantic_kind, available_materials)

func to_native() -> Dictionary:
	return {"schema": "gm.presentation.semantic_material_mapping.v1", "mapping_id": mapping_id, "mapping": mapping.duplicate(true), "fallback_material_id": fallback_material_id, "semantic_kinds": SEMANTIC_KINDS.duplicate(), "presentation_only": true}

func _fallback(semantic_kind: String, warning: String) -> Dictionary:
	return {"ok": true, "code": "material_mapping.fallback_warning", "semantic_kind": semantic_kind, "material_id": fallback_material_id, "fallback": true, "warning_zh": warning, "fallback_material_id": fallback_material_id}

static func _failure(code: String, error_zh: String) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": error_zh, "errors_zh": [error_zh], "failure_closed": true}
