@tool
class_name GMCharacter3DContract
extends RefCounted

## Shared, serializable validation helpers for the 3D character content family.
## This class is deliberately stateless: GMContentLibrary remains the only
## content index and no runtime Node/NodePath/RID is accepted by these helpers.

const CONTENT_VALIDATOR := preload("res://gm_runtime/content/gm_content_validator.gd")

## EXT06 keeps the runtime tree bounded so an outfit remains one large visual
## module and optional features cannot silently grow a character into a scene.
const MAX_CHARACTER_NODES := 48
const MAX_SKINNED_MESHES := 4
const MAX_FEATURE_MODULES := 4
const MAX_ACCESSORY_SLOTS := 4
const MAX_LOCAL_SKELETONS := 2

static func validate_id(value: String, field_name: String, allow_empty: bool = false) -> Dictionary:
	if allow_empty and value.strip_edges().is_empty(): return {"ok": true}
	if value.strip_edges().is_empty(): return failure("character.%s_missing" % field_name, "缺少%s稳定标识。" % field_name)
	var result := CONTENT_VALIDATOR.validate_business_id(value, true)
	if result.ok: return {"ok": true}
	return failure("character.%s_invalid" % field_name, "%s稳定标识格式无效。" % field_name, {"errors": result.errors_zh})

static func validate_positive(value: float, field_name: String, label_zh: String) -> Dictionary:
	if not is_finite(value) or value <= 0.0:
		return failure("character.%s_invalid" % field_name, "%s必须是大于零的有限数。" % label_zh)
	return {"ok": true}

static func validate_nonnegative(value: float, field_name: String, label_zh: String) -> Dictionary:
	if not is_finite(value) or value < 0.0:
		return failure("character.%s_invalid" % field_name, "%s必须是非负有限数。" % label_zh)
	return {"ok": true}

static func unique_strings(values: PackedStringArray, code: String, message: String) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var seen := {}
	for value in values:
		var normalized := str(value).strip_edges()
		if normalized.is_empty():
			issues.append(failure(code + "_empty", message))
		elif seen.has(normalized):
			issues.append(failure(code + "_duplicate", message, {"value": normalized}))
		else:
			seen[normalized] = true
	return issues

static func failure(code: String, error_zh: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "error_zh": error_zh, "details": details.duplicate(true)}

static func issue(code: String, error_zh: String, details: Dictionary = {}) -> Dictionary:
	return failure(code, error_zh, details)

static func digest(value: Variant) -> String:
	return JSON.stringify(value, "", true, true).sha256_text()
