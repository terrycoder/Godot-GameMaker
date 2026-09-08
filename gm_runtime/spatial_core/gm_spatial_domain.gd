class_name GMSpatialDomain
extends RefCounted

const PLANAR_2D := "gm.spatial.planar_2d"
const PLANAR_3D := "gm.spatial.planar_3d"
const FULL_3D_RESERVED := "gm.spatial.full_3d_reserved"

static func declared_ids() -> PackedStringArray:
	return PackedStringArray([PLANAR_2D, PLANAR_3D, FULL_3D_RESERVED])

static func default_available_ids() -> PackedStringArray:
	return PackedStringArray([PLANAR_2D])

## EXT01 keeps `available` as the public declaration flag so the reserved
## PLANAR_3D ID remains visibly fail-closed to old profile probes.  An
## installed EXT02 manifest is the additional execution gate for PLANAR_3D;
## capability/runtime code uses this narrower execution list after that
## manifest gate has passed.
static func execution_available_ids() -> PackedStringArray:
	return PackedStringArray([PLANAR_2D, PLANAR_3D])

static func is_execution_available(value: Variant) -> bool:
	return execution_available_ids().has(str(value))

static func validate_id(value: Variant) -> Dictionary:
	if not value is String and not value is StringName:
		return {"ok": false, "code": "spatial.domain_type_invalid", "error_zh": "空间域必须使用稳定字符串ID。"}
	var domain_id := str(value)
	if not declared_ids().has(domain_id):
		return {"ok": false, "code": "spatial.domain_unknown", "error_zh": "未知空间域：%s" % domain_id, "domain_id": domain_id}
	return {"ok": true, "domain_id": domain_id, "available": default_available_ids().has(domain_id), "execution_available": is_execution_available(domain_id)}
