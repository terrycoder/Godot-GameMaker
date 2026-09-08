class_name GMDependencyPolicy
extends RefCounted

const DECLARED_METADATA: Dictionary = {
    "res://gm_runtime/gm_platform.gd": ["res://addons/gm_editor", "res://gm_runtime", "res://gm_adapters"],
    "res://gm_runtime/manifests/core.tres": ["res://addons/gm_editor"],
    "res://gm_runtime/gm_dependency_scanner.gd": ["res://addons/gm_editor"],
    "res://gm_runtime/gm_dependency_policy.gd": ["res://addons/gm_editor", "res://DOCS"],
    "res://gm_runtime/gm_export_planner.gd": ["res://addons/gm_editor", "res://DOCS"],
}

static func allows(source: String, target: String) -> bool:
    for declared in DECLARED_METADATA.get(source, []):
        var normalized_target := str(target).replace("\\", "/").trim_suffix("/")
        var normalized_declared := str(declared).replace("\\", "/").trim_suffix("/")
        if normalized_target == normalized_declared or normalized_target.begins_with(normalized_declared + "/"): return true
    return false

static func allows_editor_literals(source: String) -> bool:
    return source == "res://gm_runtime/gm_dependency_scanner.gd"
