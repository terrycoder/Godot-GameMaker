@tool
class_name GMRoleProfile
extends Resource

const SCHEMA := "gm.role.profile.v1"
const CONTROL_SOURCES := ["player", "ai", "story", "debug"]

@export var role_id: String = ""
@export var display_name_zh: String = ""
@export var ability_bundles: Array[GMAbilityBundle] = []
@export var enabled_control_sources: PackedStringArray = PackedStringArray(["ai"])
@export var interaction_config: Dictionary = {}
@export var ui_config: Dictionary = {}
@export var schema_version: String = SCHEMA

func validate_profile() -> Dictionary:
	if role_id.strip_edges().is_empty(): return _fail("role.id_missing", "角色身份缺少稳定 role_id。")
	var seen := {}
	for source in enabled_control_sources:
		if source not in CONTROL_SOURCES: return _fail("role.control_source_unknown", "身份包含未知控制源。", {"source":source})
		if seen.has(source): return _fail("role.control_source_duplicate", "身份控制源重复。", {"source":source})
		seen[source] = true
	for bundle in ability_bundles:
		if bundle == null or bundle.bundle_id.strip_edges().is_empty(): return _fail("role.bundle_invalid", "身份能力包为空或缺少稳定 ID。")
	return {"ok":true,"role_id":role_id}

func stable_profile_id() -> String:
	# P14 keeps RoleProfile identity deliberately small. Task/Assignment, schedule
	# and planner identity belong to later authoritative domains.
	return role_id

func grant_to(host: GMAbilitySystemHost, definitions: Dictionary) -> Dictionary:
	var check := validate_profile()
	if not check.ok: return check
	var source := "role:%s" % role_id
	var snapshot := host._snapshot_ability_grant_state()
	var results: Array[Dictionary] = []
	for bundle in ability_bundles:
		var result := bundle.grant_to(host, source, definitions)
		results.append(result)
		if not result.ok:
			host._restore_ability_grant_state(snapshot)
			return _fail("role.bundle_grant_failed", "身份能力组合授予失败，已回滚。", {"results":results,"rolled_back":true})
	return {"ok":true,"source":source,"results":results}

func revoke_from(host: GMAbilitySystemHost) -> Dictionary:
	var results: Array[Dictionary] = []
	for bundle in ability_bundles: results.append(bundle.revoke_from(host, "role:%s" % role_id))
	return {"ok":results.all(func(row): return bool(row.get("ok",false))),"results":results}

func _fail(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok":false,"code":code,"error_zh":message,"details":details}
