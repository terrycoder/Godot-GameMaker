@tool
class_name GMContentTypeGenerator
extends RefCounted

const RUNTIME_GENERATED_ROOT := "res://gm_runtime/content/generated"
const EDITOR_GENERATED_ROOT := "res://addons/gm_editor/content/generated"
const TEST_GENERATED_ROOT := "user://gm_content_generator_validation"
const TYPE_DEFINITION_SCRIPT := "res://gm_runtime/content/gm_content_type_definition.gd"
const CONTENT_SCRIPT := "res://gm_runtime/content/gm_content.gd"
const OWNERSHIP_CONTRACT_SCHEMA := "gm.content_type_generation.ownership.v1"

func validate_spec(spec: GMContentTypeGenerationSpec) -> Dictionary:
	var errors: Array[Dictionary] = []
	if spec == null:
		return _failure("wizard.missing_spec", "新内容类型向导没有收到配置。", "填写完整表单后重试。")
	if spec.display_name_zh.strip_edges().is_empty(): _add(errors, "wizard.empty_name", "中文名称不能为空。", "填写例如门派制度。")
	var id_result := GMContentValidator.validate_business_id(spec.content_type_id, false)
	GMContentValidator._append_errors(errors, id_result.errors, "")
	var class_result := GMContentValidator.validate_class_name(spec.generated_class_name)
	GMContentValidator._append_errors(errors, class_result.errors, "")
	var path_result := GMContentValidator.validate_path(spec.default_directory)
	GMContentValidator._append_errors(errors, path_result.errors, "")
	if not _allowed_generation_root(spec.default_directory):
		_add(errors, "wizard.default_directory_forbidden", "默认目录必须位于 res://gm_runtime/content。", "生成内容必须写入项目正式内容目录。")
	if spec.base_class_name != "GMContent":
		_add(errors, "wizard.base_not_content", "新内容类型必须继承 GMContent，不能绕开统一内容身份。", "把基础类型设置为 GMContent。")
	if not FileAccess.file_exists(spec.base_script_path):
		_add(errors, "wizard.base_missing", "基类脚本不存在：%s" % spec.base_script_path, "恢复基类脚本或修正路径。")
	if spec.icon_path.strip_edges() != "" and not FileAccess.file_exists(spec.icon_path):
		_add(errors, "wizard.icon_missing", "图标路径不存在：%s" % spec.icon_path, "选择存在的图片或清空图标字段。")
	if spec.editable_fields.size() != spec.editable_field_labels_zh.size() or spec.editable_fields.size() != spec.editable_field_help_zh.size():
		_add(errors, "wizard.field_metadata_count", "每个可编辑字段都必须有稳定属性名、中文显示名和中文帮助文本。", "使用 属性名=中文显示名|帮助文本 的格式完整填写字段。")
	for index in spec.editable_fields.size():
		var raw_name := str(spec.editable_fields[index]).strip_edges()
		if _property_name(raw_name) != raw_name:
			_add(errors, "wizard.field_invalid_name", "可编辑字段属性名非法：%s" % raw_name, "使用小写 ASCII 属性名，例如 notes_zh。")
		if index >= spec.editable_field_labels_zh.size() or str(spec.editable_field_labels_zh[index]).strip_edges().is_empty():
			_add(errors, "wizard.field_label_empty", "可编辑字段中文显示名不能为空：%s" % raw_name, "为字段填写稳定的中文 Inspector 标签。")
		if index >= spec.editable_field_help_zh.size() or str(spec.editable_field_help_zh[index]).strip_edges().is_empty():
			_add(errors, "wizard.field_help_empty", "可编辑字段中文帮助文本不能为空：%s" % raw_name, "为字段填写 Inspector 帮助说明。")
	var names := GMContentValidator.scan_class_names(["res://gm_runtime/content", "res://addons/gm_editor"])
	for class_name_value in [spec.generated_class_name, "%sValidator" % spec.generated_class_name, "%sListEntry" % spec.generated_class_name]:
		if names.has(class_name_value):
			_add(errors, "script.duplicate_class_name", "class_name 已存在：%s（%s）。" % [class_name_value, "; ".join(names[class_name_value])], "更换类名，生成器不会覆盖现有脚本。")
	var registry := GMContentTypeRegistry.scan(["res://gm_runtime/content"])
	if registry.by_id.has(spec.content_type_id):
		_add(errors, "type.duplicate_id", "内容类型 ID 已存在：%s。" % spec.content_type_id, "使用新的类型 ID 或编辑现有类型。")
	var targets := target_paths(spec)
	for path in targets:
		if FileAccess.file_exists(path): _add(errors, "wizard.target_exists", "生成目标已存在：%s" % path, "删除测试夹具或使用新的类名/默认目录。")
	return {"ok":errors.is_empty(),"errors":errors,"errors_zh":_messages(errors),"targets":targets}

func target_paths(spec: GMContentTypeGenerationSpec) -> Array[String]:
	var stem := _snake_case(spec.generated_class_name)
	return [
		RUNTIME_GENERATED_ROOT.path_join("%s.gd" % stem),
		RUNTIME_GENERATED_ROOT.path_join("%s_validator.gd" % stem),
		EDITOR_GENERATED_ROOT.path_join("%s_list_entry.gd" % stem),
		TEST_GENERATED_ROOT.path_join("test_%s.gd" % stem),
		spec.default_directory.path_join("%s_type.tres" % stem),
		spec.default_directory.path_join("%s_example.tres" % stem),
	]

func generate(spec: GMContentTypeGenerationSpec, fail_after_step: int = -1) -> Dictionary:
	var preflight := validate_spec(spec)
	if not preflight.ok: return {"ok":false,"phase":"preflight","errors":preflight.errors,"errors_zh":preflight.errors_zh,"rollback":{"ok":true,"removed":[]},"error_zh":"新类型生成预检被阻断：%s" % "; ".join(preflight.errors_zh)}
	var target_list: Array[String] = preflight.targets
	var files := _build_files(spec)
	var created: Array[String] = []
	var step := 0
	for file_info in files:
		var write_result := _write_atomic(str(file_info.path), str(file_info.content), created)
		if not write_result.ok:
			return _generation_failure(spec, write_result.error_zh, created, "write")
		step += 1
		if fail_after_step >= 0 and step >= fail_after_step:
			return _generation_failure(spec, "注入的中途失败：第 %d 步后停止。" % step, created, "injected_failure")
	var manifest := {
		"ok":true,
		"display_name_zh":spec.display_name_zh,
		"content_type_id":spec.content_type_id,
		"generated_class_name":spec.generated_class_name,
		"default_directory":spec.default_directory,
		"files":files,
		"paths":target_list,
		"ownership_contract":_build_ownership_contract(files),
		"sample_resource_path":spec.default_directory.path_join("%s_example.tres" % _snake_case(spec.generated_class_name)),
		"registration_path":spec.default_directory.path_join("%s_type.tres" % _snake_case(spec.generated_class_name)),
		"created":created.duplicate(),
		"phase":"complete",
	}
	return manifest

func apply_manifest(manifest: Dictionary) -> Dictionary:
	var contract := _validate_ownership_contract(manifest)
	if not contract.ok: return contract
	var conflicts: Array[Dictionary] = []
	for target in contract.targets:
		var path := str(target.get("path", ""))
		if FileAccess.file_exists(path):
			conflicts.append(_file_observation(path, str(target.get("expected_content_sha256", "")), "occupied"))
	if not conflicts.is_empty():
		return {
			"ok":false,
			"phase":"preflight",
			"code":"wizard.redo_target_conflict",
			"conflicts":conflicts,
			"rollback":{"ok":true,"removed":[]},
			"error_zh":"重做目标在写入前已被占用，已拒绝整批重做并保留现有内容。",
		}
	var created: Array[String] = []
	for file_info in manifest.get("files", []):
		var result := _write_atomic(str(file_info.path), str(file_info.content), created)
		if not result.ok:
			var rollback := rollback_paths(created)
			return {"ok":false,"phase":"write","code":"wizard.redo_write_failed","error_zh":result.error_zh,"rollback":rollback}
	return {"ok":true,"paths":created}

func rollback_paths(paths: Array) -> Dictionary:
	var removed: Array[String] = []
	var failures: Array[String] = []
	for path in paths:
		var absolute := ProjectSettings.globalize_path(str(path))
		if not FileAccess.file_exists(str(path)): continue
		var error := DirAccess.remove_absolute(absolute)
		if error == OK: removed.append(str(path))
		else: failures.append("%s（错误码 %d）" % [str(path), error])
	return {"ok":failures.is_empty(),"removed":removed,"failures":failures}

func remove_manifest(manifest: Dictionary) -> Dictionary:
	var contract := _validate_ownership_contract(manifest)
	if not contract.ok: return contract
	var removed: Array[String] = []
	var failures: Array[String] = []
	var conflicts: Array[Dictionary] = []
	var paths_to_remove: Array[String] = []
	var already_absent: Array[String] = []
	var files: Array = manifest.get("files", [])
	for index in contract.targets.size():
		var target: Dictionary = contract.targets[index]
		var path := str(target.get("path", ""))
		if not FileAccess.file_exists(path):
			already_absent.append(path)
			continue
		var expected := str(files[index].get("content", ""))
		var actual := FileAccess.get_file_as_string(path)
		if actual != expected or actual.sha256_text() != str(target.get("expected_content_sha256", "")):
			conflicts.append(_file_observation(path, str(target.get("expected_content_sha256", "")), "mutated"))
			continue
		paths_to_remove.append(path)
	if not conflicts.is_empty():
		return {
			"ok":false,
			"phase":"preflight",
			"code":"wizard.undo_target_conflict",
			"conflicts":conflicts,
			"removed":[],
			"already_absent":already_absent,
			"rollback":{"ok":true,"removed":[]},
			"error_zh":"撤销目标内容已被编辑或替换，已拒绝整批撤销并保留所有现有内容。",
		}
	for path in paths_to_remove:
		var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if error == OK: removed.append(path)
		else: failures.append("%s（错误码 %d）" % [path, error])
	return {"ok":failures.is_empty(),"removed":removed,"already_absent":already_absent,"failures":failures}

func create_instance(manifest: Dictionary, destination: String, content_id_value: String = "") -> Dictionary:
	if not destination.begins_with(str(manifest.default_directory).trim_suffix("/") + "/"):
		return _failure("wizard.instance_outside_directory", "实例路径超出新类型默认目录。", "在向导指定的默认目录下创建内容实例。")
	if FileAccess.file_exists(destination): return _failure("wizard.instance_exists", "内容实例已存在：%s" % destination, "选择新的实例路径。")
	var id_value := content_id_value if not content_id_value.is_empty() else "%s.example2" % str(manifest.content_type_id)
	var id_result := GMContentValidator.validate_business_id(id_value, false)
	if not id_result.ok: return {"ok":false,"errors":id_result.errors,"errors_zh":id_result.errors_zh,"error_zh":"实例业务 ID 非法。"}
	var script_path := ""
	for file_info in manifest.files:
		if str(file_info.path).ends_with(".gd") and str(file_info.path).contains("/generated/") and not str(file_info.path).contains("validator"):
			script_path = str(file_info.path); break
	if script_path.is_empty(): return _failure("wizard.instance_script_missing", "生成清单缺少内容脚本。", "重新生成完整类型。")
	var instance_uid := ResourceUID.create_id()
	ResourceUID.add_id(instance_uid, destination)
	var text := _sample_text(manifest.generated_class_name, script_path, manifest.display_name_zh, manifest.content_type_id, id_value, "generated-instance", ResourceUID.id_to_text(instance_uid))
	var created: Array[String] = []
	var result := _write_atomic(destination, text, created)
	if not result.ok: return {"ok":false,"error_zh":result.error_zh,"rollback":rollback_paths(created)}
	return {"ok":true,"path":destination,"content_id":id_value,"created":created}

func validate_generated_manifest(manifest: Dictionary) -> Dictionary:
	var errors: Array[Dictionary] = []
	for file_info in manifest.get("files", []):
		var path := str(file_info.path)
		if not FileAccess.file_exists(path):
			_add(errors, "generated.missing_file", "生成文件缺失：%s" % path, "重新生成或从撤销历史恢复完整类型。")
	var class_path := RUNTIME_GENERATED_ROOT.path_join("%s.gd" % _snake_case(str(manifest.generated_class_name)))
	var script_validation := GMContentValidator.validate_script(class_path, str(manifest.generated_class_name), str("GMContent"))
	GMContentValidator._append_errors(errors, script_validation.errors, class_path)
	return {"ok":errors.is_empty(),"errors":errors,"errors_zh":_messages(errors)}

func _build_files(spec: GMContentTypeGenerationSpec) -> Array[Dictionary]:
	var stem := _snake_case(spec.generated_class_name)
	var runtime_path := RUNTIME_GENERATED_ROOT.path_join("%s.gd" % stem)
	var validator_path := RUNTIME_GENERATED_ROOT.path_join("%s_validator.gd" % stem)
	var list_path := EDITOR_GENERATED_ROOT.path_join("%s_list_entry.gd" % stem)
	var test_path := TEST_GENERATED_ROOT.path_join("test_%s.gd" % stem)
	var type_path := spec.default_directory.path_join("%s_type.tres" % stem)
	var sample_path := spec.default_directory.path_join("%s_example.tres" % stem)
	var type_uid := ResourceUID.create_id()
	var sample_uid := ResourceUID.create_id()
	ResourceUID.add_id(type_uid, type_path)
	ResourceUID.add_id(sample_uid, sample_path)
	return [
		{"path":runtime_path,"kind":"editable_gdscript","content":_content_script(spec)},
		{"path":validator_path,"kind":"validator","content":_validator_script(spec, runtime_path)},
		{"path":list_path,"kind":"editor_list_entry","content":_list_entry_script(spec, runtime_path)},
		{"path":test_path,"kind":"test_template","content":_test_template(spec, runtime_path)},
		{"path":type_path,"kind":"type_registration_resource","content":_definition_text(spec, runtime_path, validator_path, list_path, test_path, sample_path, ResourceUID.id_to_text(type_uid))},
		{"path":sample_path,"kind":"sample_resource","content":_sample_text(spec.generated_class_name, runtime_path, spec.display_name_zh, spec.content_type_id, "%s.example" % spec.content_type_id, "generated-sample", ResourceUID.id_to_text(sample_uid))},
	]

func _content_script(spec: GMContentTypeGenerationSpec) -> String:
	var lines: Array[String] = ["@tool", "class_name %s" % spec.generated_class_name, "extends %s" % spec.base_class_name, "", "## 可继续编辑的 GM 内容类型骨架。", "## 业务 ID、ResourceUID 和声明式引用仍由 GMContent 提供。"]
	for field in spec.editable_fields:
		var safe := _property_name(str(field))
		if safe.is_empty(): continue
		lines.append("@export var %s: String = \"\"" % safe)
	lines.append("")
	lines.append("func content_type_summary() -> Dictionary:")
	lines.append("\treturn {\"content_type_id\": content_type_id, \"class_name\": \"%s\", \"editable\": true}" % spec.generated_class_name)
	return "\n".join(lines) + "\n"

func _validator_script(spec: GMContentTypeGenerationSpec, runtime_path: String) -> String:
	return "@tool\nclass_name %sValidator\nextends RefCounted\n\nconst TYPE_SCRIPT := preload(\"%s\")\nconst CONTENT_VALIDATOR := preload(\"res://gm_runtime/content/gm_content_validator.gd\")\n\nstatic func validate(resource: Resource) -> Dictionary:\n\tif resource == null or not resource is TYPE_SCRIPT:\n\t\treturn {\"ok\":false,\"errors_zh\":[\"资源不是 %s 类型。\"],\"error_zh\":\"类型检查失败。\"}\n\treturn CONTENT_VALIDATOR.validate_content(resource, resource.resource_path, {})\n" % [spec.generated_class_name, runtime_path, spec.generated_class_name]

func _list_entry_script(spec: GMContentTypeGenerationSpec, runtime_path: String) -> String:
	return "@tool\nclass_name %sListEntry\nextends RefCounted\n\nconst TYPE_SCRIPT := preload(\"%s\")\n\nstatic func build(resource: Resource) -> Dictionary:\n\tif resource == null or not resource is TYPE_SCRIPT: return {}\n\treturn {\"display_name_zh\":resource.display_name_zh,\"content_id\":resource.content_id,\"content_type_id\":resource.content_type_id,\"tags\":Array(resource.tags),\"path\":resource.resource_path}\n" % [spec.generated_class_name, runtime_path]

func _test_template(spec: GMContentTypeGenerationSpec, runtime_path: String) -> String:
	return "extends GutTest\n\nconst TYPE_SCRIPT := preload(\"%s\")\n\nfunc test_generated_content_type_is_editable_and_stable() -> void:\n\tvar content: Resource = TYPE_SCRIPT.new()\n\tcontent.display_name_zh = \"生成类型测试\"\n\tcontent.content_id = \"%s.test\"\n\tcontent.content_type_id = \"%s\"\n\tassert_true(content.content_id != \"\")\n\tassert_true(content.content_type_id == \"%s\")\n" % [runtime_path, spec.content_type_id, spec.content_type_id, spec.content_type_id]

func _definition_text(spec: GMContentTypeGenerationSpec, runtime_path: String, validator_path: String, list_path: String, test_path: String, sample_path: String, uid_text: String = "") -> String:
	var lines: Array[String] = [
		"[gd_resource type=\"Resource\" script_class=\"GMContentTypeDefinition\" load_steps=2 format=3%s]" % (" uid=\"%s\"" % uid_text if not uid_text.is_empty() else ""),
		"",
		"[ext_resource type=\"Script\" path=\"%s\" id=\"1\"]" % TYPE_DEFINITION_SCRIPT,
		"",
		"[resource]",
		"script = ExtResource(\"1\")",
		"content_type_id = \"%s\"" % _escape(spec.content_type_id),
		"display_name_zh = \"%s\"" % _escape(spec.display_name_zh),
		"generated_class_name = \"%s\"" % _escape(spec.generated_class_name),
		"base_class_name = \"%s\"" % _escape(spec.base_class_name),
		"base_script_path = \"%s\"" % _escape(spec.base_script_path),
		"default_directory = \"%s\"" % _escape(spec.default_directory),
		"icon_path = \"%s\"" % _escape(spec.icon_path),
		"generated_script_path = \"%s\"" % _escape(runtime_path),
		"validator_script_path = \"%s\"" % _escape(validator_path),
		"list_entry_script_path = \"%s\"" % _escape(list_path),
		"test_template_path = \"%s\"" % _escape(test_path),
		"sample_resource_path = \"%s\"" % _escape(sample_path),
		"editable_fields = PackedStringArray(%s)" % _packed_strings(spec.editable_fields),
		"editable_field_labels_zh = PackedStringArray(%s)" % _packed_strings(spec.editable_field_labels_zh),
		"editable_field_help_zh = PackedStringArray(%s)" % _packed_strings(spec.editable_field_help_zh),
		"registration_version = \"1.0.0\"",
		"description_zh = \"%s\"" % _escape(spec.description_zh),
	]
	return "\n".join(lines) + "\n"

func _sample_text(class_name_value: String, runtime_path: String, display_name: String, type_id: String, content_id_value: String, source_value: String, uid_text: String = "") -> String:
	var uid_part := " uid=\"%s\"" % uid_text if not uid_text.is_empty() else ""
	return "[gd_resource type=\"Resource\" script_class=\"%s\" load_steps=2 format=3%s]\n\n[ext_resource type=\"Script\" path=\"%s\" id=\"1\"]\n\n[resource]\nscript = ExtResource(\"1\")\ndisplay_name_zh = \"%s\"\ncontent_id = \"%s\"\ncontent_type_id = \"%s\"\ntags = PackedStringArray(\"generated\", \"sample\")\ncontent_version = \"1.0.0\"\nsource = \"%s\"\n" % [class_name_value, uid_part, runtime_path, _escape(display_name), _escape(content_id_value), _escape(type_id), _escape(source_value)]

func _write_atomic(path: String, content: String, created: Array[String]) -> Dictionary:
	if FileAccess.file_exists(path): return _failure("wizard.target_exists", "生成目标已存在：%s" % path, "选择新的生成位置。")
	var dir_result := _ensure_directory(path.get_base_dir())
	if not dir_result.ok: return dir_result
	var temp := "%s.gm_tmp" % path
	if FileAccess.file_exists(temp): DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return _failure("wizard.write_failed", "无法写入临时文件：%s" % temp, "检查目录权限后重试。")
	file.store_string(content)
	file.close()
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path))
	if rename_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		return _failure("wizard.rename_failed", "无法原子提交生成文件：%s（错误码 %d）" % [path, rename_error], "检查文件是否被占用后重试。")
	if not created.has(path): created.append(path)
	return {"ok":true,"path":path}

func _ensure_directory(path: String) -> Dictionary:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)): return {"ok":true}
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	return {"ok":error == OK,"error_zh":"无法创建生成目录：%s（错误码 %d）" % [path, error] if error != OK else ""}

func _generation_failure(spec: GMContentTypeGenerationSpec, reason: String, created: Array[String], phase: String) -> Dictionary:
	var rollback := rollback_paths(created)
	return {"ok":false,"phase":phase,"error_zh":reason,"errors_zh":[reason],"created_before_rollback":created.duplicate(),"rollback":rollback,"spec":spec.to_dictionary()}

func _build_ownership_contract(files: Array) -> Dictionary:
	var targets: Array[Dictionary] = []
	for file_info in files:
		var content := str(file_info.get("content", ""))
		targets.append({
			"path":str(file_info.get("path", "")),
			"kind":str(file_info.get("kind", "")),
			"expected_before_generate":"absent",
			"expected_after_generate":"present",
			"expected_after_undo":"absent",
			"expected_content_sha256":content.sha256_text(),
			"expected_bytes":content.to_utf8_buffer().size(),
		})
	return {"schema":OWNERSHIP_CONTRACT_SCHEMA,"mode":"exclusive_create","targets":targets}

func _validate_ownership_contract(manifest: Dictionary) -> Dictionary:
	var contract = manifest.get("ownership_contract", null)
	if not contract is Dictionary:
		return {"ok":false,"phase":"preflight","code":"wizard.manifest_contract_missing","errors_zh":["生成清单缺少目标所有权合同。"],"error_zh":"生成清单缺少目标所有权合同，已拒绝状态变更。"}
	if str(contract.get("schema", "")) != OWNERSHIP_CONTRACT_SCHEMA or str(contract.get("mode", "")) != "exclusive_create":
		return {"ok":false,"phase":"preflight","code":"wizard.manifest_contract_invalid","errors_zh":["生成清单目标所有权合同版本或模式无效。"],"error_zh":"生成清单目标所有权合同无效，已拒绝状态变更。"}
	var files: Array = manifest.get("files", [])
	var paths: Array = manifest.get("paths", [])
	var targets: Array = contract.get("targets", [])
	var errors: Array[String] = []
	if files.is_empty() or targets.size() != files.size() or paths.size() != files.size():
		errors.append("生成清单的 files、paths 与所有权目标数量不一致。")
	var seen_paths := {}
	for index in files.size():
		if index >= targets.size(): break
		var file_info = files[index]
		var target = targets[index]
		if not file_info is Dictionary or not target is Dictionary:
			errors.append("生成清单第 %d 项不是有效目标字典。" % index)
			continue
		var path := str(file_info.get("path", ""))
		var content := str(file_info.get("content", ""))
		if path.is_empty() or seen_paths.has(path): errors.append("生成清单目标路径为空或重复：%s" % path)
		seen_paths[path] = true
		if index >= paths.size() or str(paths[index]) != path: errors.append("生成清单 paths 与 files 不一致：%s" % path)
		if str(target.get("path", "")) != path: errors.append("所有权合同与 files 路径不一致：%s" % path)
		if str(target.get("kind", "")) != str(file_info.get("kind", "")): errors.append("所有权合同与 files 类型不一致：%s" % path)
		if str(target.get("expected_before_generate", "")) != "absent" or str(target.get("expected_after_generate", "")) != "present" or str(target.get("expected_after_undo", "")) != "absent":
			errors.append("所有权合同状态不完整：%s" % path)
		if str(target.get("expected_content_sha256", "")) != content.sha256_text(): errors.append("所有权合同内容指纹不一致：%s" % path)
		if int(target.get("expected_bytes", -1)) != content.to_utf8_buffer().size(): errors.append("所有权合同字节数不一致：%s" % path)
	if not errors.is_empty():
		return {"ok":false,"phase":"preflight","code":"wizard.manifest_contract_invalid","errors_zh":errors,"error_zh":"生成清单目标所有权合同校验失败，已拒绝状态变更。"}
	return {"ok":true,"targets":targets}

func _file_observation(path: String, expected_sha256: String, state: String) -> Dictionary:
	var present: bool = FileAccess.file_exists(path)
	var actual: String = FileAccess.get_file_as_string(path) if present else ""
	return {
		"path":path,
		"state":state,
		"expected_content_sha256":expected_sha256,
		"actual_content_sha256":actual.sha256_text() if present else "",
		"actual_bytes":actual.to_utf8_buffer().size(),
	}

func _allowed_generation_root(path: String) -> bool:
	var normalized := path.replace("\\", "/").trim_suffix("/")
	return normalized == "res://gm_runtime/content" or normalized.begins_with("res://gm_runtime/content/")

func _failure(code: String, reason: String, suggestion: String) -> Dictionary:
	var error := {"code":code,"reason_zh":reason,"suggestion_zh":suggestion}
	return {"ok":false,"errors":[error],"errors_zh":[reason],"error_zh":reason}

func _add(errors: Array[Dictionary], code: String, reason: String, suggestion: String) -> void:
	errors.append({"code":code,"reason_zh":reason,"suggestion_zh":suggestion})

func _messages(errors: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for error in errors: result.append(str(error.reason_zh))
	return result

func _snake_case(value: String) -> String:
	var output := ""
	for index in value.length():
		var character := value[index]
		var is_upper := character.to_upper() == character and not character.to_lower() == character
		if is_upper and index > 0:
			var previous := value[index - 1]
			var previous_is_lower := previous.to_lower() == previous and previous.to_upper() != previous
			var next_is_lower := index + 1 < value.length() and value[index + 1].to_lower() == value[index + 1] and value[index + 1].to_upper() != value[index + 1]
			if previous_is_lower or next_is_lower: output += "_"
		output += character.to_lower()
	return output.replace("-", "_")

func _property_name(value: String) -> String:
	var result := value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	var regex := RegEx.new()
	regex.compile("[^a-z0-9_]")
	result = regex.sub(result, "", true)
	if result.is_empty() or result[0].is_valid_int(): return ""
	return result

func _escape(value: String) -> String:
	return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")

func _packed_strings(values: PackedStringArray) -> String:
	var result: Array[String] = []
	for value in values: result.append("\"%s\"" % _escape(str(value)))
	return ", ".join(result)
