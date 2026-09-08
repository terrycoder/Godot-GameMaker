class_name GMInventoryFeatureFlags
extends RefCounted

const SCHEMA_VERSION := "gm.inventory.features.v1"

var detailed_provenance: bool = true
var unique_instances_enabled: bool = true
var source_merge_policy: String = "same_provenance_only"

func configure(p_detailed_provenance: bool = true, p_unique_instances_enabled: bool = true, p_source_merge_policy: String = "same_provenance_only") -> GMInventoryFeatureFlags:
	detailed_provenance = p_detailed_provenance
	unique_instances_enabled = p_unique_instances_enabled
	source_merge_policy = p_source_merge_policy
	return self

func validate() -> Dictionary:
	var errors: Array[String] = []
	if not ["same_provenance_only", "allow_different_preserve"].has(source_merge_policy): errors.append("未知来源合并策略：%s" % source_merge_policy)
	return {"ok": errors.is_empty(), "code": "inventory_features.valid" if errors.is_empty() else "inventory_features.invalid", "errors": errors}

func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "detailed_provenance": detailed_provenance, "unique_instances_enabled": unique_instances_enabled, "source_merge_policy": source_merge_policy}

static func from_dict(value: Dictionary) -> GMInventoryFeatureFlags:
	return GMInventoryFeatureFlags.new().configure(bool(value.get("detailed_provenance", true)), bool(value.get("unique_instances_enabled", true)), str(value.get("source_merge_policy", "same_provenance_only")))
