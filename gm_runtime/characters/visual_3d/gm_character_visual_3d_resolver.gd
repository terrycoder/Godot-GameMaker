@tool
class_name GMCharacterVisual3DResolver
extends RefCounted

## Runtime resolver adapter. The injected GMContentLibrary remains the only
## registry; this object never serializes its own index or creates domain facts.

var content_library: GMContentLibrary

func _init(p_library: GMContentLibrary = null) -> void:
	content_library = p_library

func resolve(content_id: String) -> Resource:
	if content_library == null: return null
	var entry := content_library.entry_for_id(content_id)
	return entry.get("resource", null) if not entry.is_empty() else null

func validate(recipe: GMCharacterVisualRecipe) -> Dictionary:
	if content_library == null: return {"ok": false, "code": "character.runtime_library_missing", "error_zh": "3D 角色运行时缺少既有 GMContentLibrary。", "failure_closed": true}
	return GMCharacterAssetValidator.validate_recipe(recipe, content_library)

func resource_fingerprint(content_id: String) -> String:
	var resource := resolve(content_id)
	if resource == null: return ""
	return GMCharacter3DContract.digest({"content_id": content_id, "resource_path": resource.resource_path, "resource_class": resource.get_class()})
