@tool
class_name GMModuleManifestIndex
extends Resource

@export var index_version: String = "1.0.0"
@export var manifest_paths: PackedStringArray = []

func schema_errors(validate_manifest_paths: bool = true) -> Array[String]:
	var errors: Array[String] = []
	var version_pattern := RegEx.new()
	if index_version.strip_edges().is_empty() or version_pattern.compile("^[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?$") != OK or version_pattern.search(index_version) == null:
		errors.append("Manifest索引版本无效：%s" % index_version)
	if not validate_manifest_paths:
		return errors
	var seen: Dictionary = {}
	for path in manifest_paths:
		var normalized := str(path).strip_edges().replace("\\", "/")
		if normalized.is_empty():
			errors.append("Manifest索引路径不能为空")
		elif normalized != str(path).replace("\\", "/"):
			errors.append("Manifest索引路径不得包含首尾空白：%s" % path)
		elif not normalized.begins_with("res://") or normalized == "res://":
			# Path node type and file-boundary semantics are validated per entry
			# by GMModuleRegistry.  Keeping a res:// entry here lets a malformed
			# Manifest item retain its own raw/normalized/source/entry_kind
			# identity instead of being collapsed into an Index schema error.
			errors.append("Manifest索引路径格式无效：%s" % path)
		elif seen.has(normalized):
			errors.append("Manifest索引路径重复：%s" % normalized)
		else:
			seen[normalized] = true
	return errors
