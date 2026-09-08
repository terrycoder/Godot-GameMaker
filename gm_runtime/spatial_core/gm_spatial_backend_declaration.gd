@tool
class_name GMSpatialBackendDeclaration
extends Resource

const PLANAR_POSITION := preload("res://gm_runtime/spatial_core/gm_planar_position.gd")

## Manifest metadata only.  The implementation object is injected at runtime
## and never becomes content or save data.

@export var backend_id: String = ""
@export var domain_id: String = ""
@export var capabilities: PackedStringArray = []
@export var implementation_path: String = ""

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not PLANAR_POSITION.is_valid_stable_id(backend_id): errors.append("空间后端ID无效：%s" % backend_id)
	var domain := GMSpatialDomain.validate_id(domain_id)
	if not domain.ok: errors.append("空间后端域无效：%s" % domain_id)
	var seen: Dictionary = {}
	for raw_capability in capabilities:
		var capability := str(raw_capability)
		if capability.strip_edges().is_empty() or capability != capability.strip_edges() or not capability.begins_with("gm.spatial.capability."):
			errors.append("空间后端能力ID无效：%s" % capability)
		elif seen.has(capability):
			errors.append("空间后端能力ID重复：%s" % capability)
		else:
			seen[capability] = true
	if not implementation_path.is_empty() and (not implementation_path.begins_with("res://") or not implementation_path.ends_with(".gd")):
		errors.append("空间后端实现路径必须是res://下的GDScript路径。")
	return {"ok": errors.is_empty(), "code": "spatial.backend.declaration_valid" if errors.is_empty() else "spatial.backend.declaration_invalid", "errors_zh": errors}

func to_native() -> Dictionary:
	return {"backend_id": backend_id, "domain_id": domain_id, "capabilities": Array(capabilities), "implementation_path": implementation_path}
