@tool
class_name GMSemanticMaterial
extends GMContent

## 中性语义材质。它描述材质语义与可替换的视觉参数，不保存运行时材质实例。

const CONTENT_TYPE_ID := "gm.presentation.semantic_material"
const SCHEMA_VERSION := "gm.presentation.semantic_material.v1"
const SEMANTIC_KINDS := ["Wood", "Stone", "Cloth", "Skin", "Hair", "Metal", "Ceramic", "Paper", "Plant", "Water"]

@export_group("Semantic Material")
@export var semantic_kind: String = "Wood"
@export var material_id: String = ""
@export var fallback_kind: String = "Wood"
@export var albedo_color: Color = Color(0.65, 0.48, 0.31, 1.0)
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.75
@export_range(0.0, 1.0, 0.01) var metallic: float = 0.0
@export var texture_content_id: String = ""

func _init() -> void:
	content_type_id = CONTENT_TYPE_ID

func validate_semantic_material() -> Dictionary:
	var issues: Array[Dictionary] = []
	if semantic_kind not in SEMANTIC_KINDS: issues.append(_issue("semantic_material.kind_invalid", "semantic_kind", "语义材质种类", "semantic_material.kind_invalid：语义材质种类不受支持。"))
	if material_id.strip_edges().is_empty(): issues.append(_issue("semantic_material.id_missing", "material_id", "材质ID", "semantic_material.id_missing：材质ID不能为空。"))
	if fallback_kind not in SEMANTIC_KINDS: issues.append(_issue("semantic_material.fallback_invalid", "fallback_kind", "降级语义", "semantic_material.fallback_invalid：降级语义不受支持。"))
	if not is_finite(roughness) or roughness < 0.0 or roughness > 1.0: issues.append(_issue("semantic_material.roughness_invalid", "roughness", "粗糙度", "semantic_material.roughness_invalid：粗糙度必须在0到1之间。"))
	if not is_finite(metallic) or metallic < 0.0 or metallic > 1.0: issues.append(_issue("semantic_material.metallic_invalid", "metallic", "金属度", "semantic_material.metallic_invalid：金属度必须在0到1之间。"))
	var identity_errors := GMContentValidator.validate_content(self, resource_path, {}, true)
	if not bool(identity_errors.get("ok", false)):
		for message in identity_errors.get("errors_zh", []): issues.append(_issue("semantic_material.content_identity_invalid", "content_id", "内容身份", str(message)))
	var errors_zh: Array[String] = []
	for issue in issues: errors_zh.append(str(issue.error_zh))
	return {"ok": issues.is_empty(), "code": "semantic_material.valid" if issues.is_empty() else "semantic_material.invalid", "issues": issues, "errors_zh": errors_zh, "error_zh": "语义材质校验通过。" if issues.is_empty() else str(issues[0].error_zh), "failure_closed": true}

static func _issue(code: String, field: String, field_name_zh: String, message: String) -> Dictionary:
	return {"code": code, "field": field, "field_name_zh": field_name_zh, "error_zh": message}

func validate() -> Dictionary:
	return validate_semantic_material()

func to_native() -> Dictionary:
	return {"schema": SCHEMA_VERSION, "content_id": content_id, "content_type_id": content_type_id, "semantic_kind": semantic_kind, "material_id": material_id, "fallback_kind": fallback_kind, "albedo": {"r": albedo_color.r, "g": albedo_color.g, "b": albedo_color.b, "a": albedo_color.a}, "roughness": roughness, "metallic": metallic, "texture_content_id": texture_content_id, "presentation_only": true}
