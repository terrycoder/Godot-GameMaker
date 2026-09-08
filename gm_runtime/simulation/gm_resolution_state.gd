class_name GMResolutionState
extends RefCounted

const ACTIVE := "active"
const REDUCED := "reduced"
const DORMANT := "dormant"
const VALUES := [ACTIVE, REDUCED, DORMANT]

static func validate(value: String) -> Dictionary:
	var normalized := value.strip_edges().to_lower()
	return {"ok": VALUES.has(normalized), "code": "resolution.valid" if VALUES.has(normalized) else "resolution.invalid", "resolution": normalized, "reason_zh": "" if VALUES.has(normalized) else "未知分辨率：%s" % value}

static func can_enter(record: Variant, target: String) -> Dictionary:
	var check := validate(target)
	if not check.ok: return check
	if not record is Dictionary:
		return {"ok": false, "code": "resolution.record_shape_invalid", "reason_zh": "实体生命周期记录必须是对象；Active锁投影失败关闭。", "locks": [], "fail_closed": true}
	var current := str(record.get("resolution", ACTIVE))
	if current == target: return {"ok": true, "unchanged": true, "resolution": target}
	var flags_value: Variant = record.get("flags", null)
	if not flags_value is Dictionary:
		return {"ok": false, "code": "resolution.flags_shape_invalid", "reason_zh": "实体flags不是对象；Active锁投影失败关闭。", "locks": [], "fail_closed": true}
	var flags: Dictionary = flags_value
	var projection := GMActiveLockContract.project(flags)
	if not projection.ok:
		return {"ok": false, "code": str(projection.get("code", "resolution.active_lock_projection_failed")), "reason_zh": str(projection.get("reason_zh", "Active锁投影失败。")), "locks": [], "fail_closed": true}
	if target != ACTIVE and bool(projection.get("active_required", false)):
		return {"ok": false, "code": "resolution.active_required", "reason_zh": "实体仍有类型化Active锁，不能降为 %s。" % target, "locks": projection.locks, "lock_contract": projection.contract}
	return {"ok": true, "resolution": target}

static func command_allowed(resolution: String, operation: String, payload: Dictionary = {}) -> Dictionary:
	var check := validate(resolution)
	if not check.ok: return check
	if resolution == ACTIVE:
		return {"ok": true, "allowed": true, "resolution": resolution}
	if operation != "abstract":
		return {"ok": false, "allowed": false, "code": "resolution.abstract_only", "reason_zh": "%s 实体后台只允许提交 abstract 结果。" % resolution}
	var abstract_kind := str(payload.get("abstract_kind", ""))
	var allowed := ["heartbeat", "resource_delta", "timer_due", "maintenance", "wake_request"]
	if not allowed.has(abstract_kind):
		return {"ok": false, "allowed": false, "code": "resolution.abstract_kind_invalid", "reason_zh": "abstract 结果类型未被分辨率合同允许。", "allowed_kinds": allowed}
	if resolution == DORMANT and abstract_kind not in ["maintenance", "wake_request"]:
		return {"ok": false, "allowed": false, "code": "resolution.dormant_kind_blocked", "reason_zh": "Dormant 实体只允许 maintenance 或 wake_request。"}
	return {"ok": true, "allowed": true, "resolution": resolution, "abstract_kind": abstract_kind}
