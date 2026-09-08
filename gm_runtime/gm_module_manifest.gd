@tool
class_name GMModuleManifest
extends Resource

const VERSION_PATTERN := "^[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\\+[0-9A-Za-z.-]+)?$"
const SPATIAL_BACKEND_SCRIPT := preload("res://gm_runtime/spatial_core/gm_spatial_backend_declaration.gd")

@export var module_id: String = ""
@export var version: String = "1.0.0"
@export var display_name_zh: String = ""
@export var description_zh: String = ""
@export var runtime_root: String = ""
@export var editor_root: String = ""
@export var required_modules: PackedStringArray = []
@export var optional_modules: PackedStringArray = []
@export var conflicts: PackedStringArray = []
@export var content_types: PackedStringArray = []
@export var abilities: PackedStringArray = []
@export var effects: PackedStringArray = []
@export var events: PackedStringArray = []
@export var cues: PackedStringArray = []
@export var tags: PackedStringArray = []
@export var runtime_services: PackedStringArray = []
@export var runtime_service_implementations: PackedStringArray = []
@export var service_specs: Array[GMServiceSpec] = []
@export var spatial_backends: Array[Resource] = []
@export var editor_entries: PackedStringArray = []
@export var export_required_paths: PackedStringArray = []
@export var export_excluded_paths: PackedStringArray = []
@export var validation_rules: PackedStringArray = []
@export var migrations: PackedStringArray = []
@export var license_notes: String = ""
@export var release_security_profile: String = "base"
@export var native_runtime_dependencies: PackedStringArray = []
@export var private_build_artifacts: PackedStringArray = []

func schema_errors(known_module_ids: PackedStringArray = PackedStringArray(), validate_references: bool = true) -> Array[String]:
	var errors: Array[String] = []
	var normalized_id := module_id.strip_edges()
	if normalized_id.is_empty():
		errors.append("Manifest模块ID不能为空")
	elif normalized_id != module_id:
		errors.append("Manifest模块ID不得包含首尾空白：%s" % module_id)
	var id_pattern := RegEx.new()
	if id_pattern.compile("^[A-Za-z0-9][A-Za-z0-9._-]*$") != OK or id_pattern.search(normalized_id) == null:
		errors.append("Manifest模块ID格式无效：%s" % module_id)
	var version_pattern := RegEx.new()
	if version.strip_edges().is_empty() or version_pattern.compile(VERSION_PATTERN) != OK or version_pattern.search(version) == null:
		errors.append("Manifest版本无效：%s" % version)
	_validate_unique_nonempty(required_modules, "必需依赖", errors)
	_validate_unique_nonempty(optional_modules, "可选依赖", errors)
	_validate_unique_nonempty(conflicts, "冲突声明", errors)
	_validate_unique_nonempty(runtime_services, "运行时服务", errors)
	if normalized_id in required_modules:
		errors.append("模块不得依赖自身：%s" % normalized_id)
	if normalized_id in optional_modules:
		errors.append("模块不得可选依赖自身：%s" % normalized_id)
	if normalized_id in conflicts:
		errors.append("模块不得与自身冲突：%s" % normalized_id)
	if validate_references:
		for dependency in required_modules:
			if not known_module_ids.is_empty() and not known_module_ids.has(dependency):
				errors.append("模块%s依赖未知模块%s" % [normalized_id, dependency])
		for dependency in optional_modules:
			if not known_module_ids.is_empty() and not known_module_ids.has(dependency):
				errors.append("模块%s声明未知可选模块%s" % [normalized_id, dependency])
		for conflict in conflicts:
			if not known_module_ids.is_empty() and not known_module_ids.has(conflict):
				errors.append("模块%s声明未知冲突模块%s" % [normalized_id, conflict])
	var spec_ids: Array[String] = []
	for index in service_specs.size():
		var spec = service_specs[index]
		if spec == null:
			errors.append("模块%s的ServiceSpec[%d]为空" % [normalized_id, index])
			continue
		var raw_service_id = spec.get("service_id")
		var service_id := "" if raw_service_id == null else str(raw_service_id).strip_edges()
		if service_id.is_empty():
			errors.append("模块%s的ServiceSpec[%d]缺少服务ID" % [normalized_id, index])
		elif service_id != str(raw_service_id):
			errors.append("模块%s的服务ID不得包含首尾空白：%s" % [normalized_id, service_id])
		elif spec_ids.has(service_id):
			errors.append("模块%s重复声明服务ID：%s" % [normalized_id, service_id])
		else:
			spec_ids.append(service_id)
		var raw_spec_module_id = spec.get("module_id")
		var spec_module_id := "" if raw_spec_module_id == null else str(raw_spec_module_id)
		if not spec_module_id.is_empty() and spec_module_id != normalized_id:
			errors.append("ServiceSpec%s归属模块%s与Manifest%s不一致" % [service_id, spec_module_id, normalized_id])
	var backend_ids: Array[String] = []
	for index in spatial_backends.size():
		var backend = spatial_backends[index]
		if backend == null:
			errors.append("模块%s的SpatialBackend[%d]为空" % [normalized_id, index])
			continue
		if not backend is Resource or backend.get_script() != SPATIAL_BACKEND_SCRIPT:
			errors.append("模块%s的空间后端声明类型无效" % normalized_id)
			continue
		var backend_check: Dictionary = backend.call("validate")
		if not backend_check.ok:
			for backend_error in backend_check.errors_zh: errors.append("模块%s的空间后端：%s" % [normalized_id, backend_error])
		var backend_id := str(backend.get("backend_id"))
		if backend_ids.has(backend_id): errors.append("模块%s重复声明空间后端ID：%s" % [normalized_id, backend_id])
		else: backend_ids.append(backend_id)
	return errors

static func _validate_unique_nonempty(values: PackedStringArray, label: String, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	for value in values:
		var normalized := str(value).strip_edges()
		if normalized.is_empty():
			errors.append("Manifest%s不得包含空ID" % label)
		elif normalized != str(value):
			errors.append("Manifest%s不得包含首尾空白：%s" % [label, value])
		elif seen.has(normalized):
			errors.append("Manifest%s重复：%s" % [label, normalized])
		else:
			seen[normalized] = true
