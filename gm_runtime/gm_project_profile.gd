@tool
class_name GMProjectProfile
extends Resource

const SPATIAL_DOMAIN := preload("res://gm_runtime/spatial_core/gm_spatial_domain.gd")
const MODULE_REGISTRY := preload("res://gm_runtime/gm_module_registry.gd")
const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

@export var template_id: String = "blank_2d"
@export var enabled_modules: PackedStringArray = []
@export var spatial_domain_id: String = "gm.spatial.planar_2d"
@export var spatial_backend_id: String = "gm.spatial.backend.planar_2d"
@export var spatial_backend_enabled: bool = false

func spatial_selection() -> Dictionary:
	return {
		"domain_id": spatial_domain_id,
		"backend_id": spatial_backend_id,
		"enabled": spatial_backend_enabled,
	}

func validate_spatial_selection(selected: PackedStringArray = PackedStringArray()) -> Dictionary:
	var domain := SPATIAL_DOMAIN.validate_id(spatial_domain_id)
	if not domain.ok:
		return _spatial_failure("spatial.profile.domain_invalid", "Profile空间域无效：%s" % spatial_domain_id)
	# Persisted backend IDs are part of the pure Profile value even when the
	# backend is disabled.  Disabled must not become a bypass around the shared
	# stable-ID/object-identity boundary.
	if not PLANAR_POSITION.is_valid_stable_id(spatial_backend_id):
		return _spatial_failure("spatial.profile.backend_invalid", "Profile空间后端ID无效：%s" % spatial_backend_id)
	if not spatial_backend_enabled:
		return {"ok": true, "active": false, "domain_id": spatial_domain_id, "backend_id": spatial_backend_id, "capabilities": []}
	var requested := selected
	if requested.is_empty(): requested = enabled_modules.duplicate()
	# EXT01 deliberately exposed PLANAR_3D as declared-but-unavailable.  Keep
	# that compatibility result for profiles which have not selected the
	# official EXT02 module; selecting the module is the execution gate.
	if spatial_domain_id == SPATIAL_DOMAIN.PLANAR_3D and not requested.has("spatial.planar_3d"):
		return _spatial_failure("spatial.profile.domain_unavailable", "Profile选择的空间域尚无可用执行后端：%s" % spatial_domain_id)
	if not domain.get("execution_available", false):
		return _spatial_failure("spatial.profile.domain_unavailable", "Profile选择的空间域尚无可用执行后端：%s" % spatial_domain_id)
	var resolution := MODULE_REGISTRY.resolve(requested)
	if not resolution.ok:
		return _spatial_failure("spatial.profile.modules_invalid", "Profile空间后端依赖解析失败：%s" % "; ".join(resolution.get("errors_zh", [])))
	var contract := MODULE_REGISTRY.spatial_backend_contract(PackedStringArray(resolution.selected))
	if not contract.ok:
		return _spatial_failure("spatial.profile.backend_contract_invalid", "Manifest空间后端合同不可用：%s" % "; ".join(contract.get("errors_zh", [])))
	for backend in contract.get("backends", []):
		if str(backend.get("backend_id", "")) != spatial_backend_id: continue
		if str(backend.get("domain_id", "")) != spatial_domain_id:
			return _spatial_failure("spatial.profile.backend_domain_mismatch", "Profile空间后端与空间域不匹配。")
		return {"ok": true, "active": true, "domain_id": spatial_domain_id, "backend_id": spatial_backend_id, "capabilities": backend.get("capabilities", []).duplicate(true), "module_id": str(backend.get("module_id", "")), "selected_modules": resolution.selected}
	return _spatial_failure("spatial.profile.backend_missing", "启用空间后端但所选Manifest未注册该后端：%s" % spatial_backend_id)

func configure_spatial_selection(domain_id: String, backend_id: String, enabled: bool) -> Dictionary:
	var candidate := duplicate()
	candidate.spatial_domain_id = domain_id
	candidate.spatial_backend_id = backend_id
	candidate.spatial_backend_enabled = enabled
	return candidate.validate_spatial_selection()

func spatial_debug_summary() -> Dictionary:
	var validation := validate_spatial_selection()
	return {
		"domain_id": spatial_domain_id,
		"backend_id": spatial_backend_id,
		"enabled": spatial_backend_enabled,
		"valid": validation.ok,
		"active": validation.get("active", false),
		"capabilities": validation.get("capabilities", []).duplicate(true),
		"error_zh": "" if validation.ok else str(validation.get("error_zh", "空间Profile校验失败。")),
	}

static func _spatial_failure(code: String, error_zh: String) -> Dictionary:
	return {"ok": false, "active": false, "code": code, "error_zh": error_zh, "capabilities": []}
