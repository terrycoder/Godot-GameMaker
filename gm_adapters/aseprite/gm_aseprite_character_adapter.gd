@tool
class_name GMAsepriteCharacterAdapter
extends RefCounted

## Optional adapter only. The task11 runtime/editor core never imports an Aseprite plugin.
func is_available() -> bool:
	return ClassDB.class_exists("AsepriteImporter") or Engine.has_singleton("AsepriteWizard")

func import_if_available(source_path: String) -> Dictionary:
	if not is_available():
		return {"ok": false, "code": "character.aseprite_adapter_unavailable", "error_zh": "Aseprite 适配器未安装；核心 SpriteFrames/AnimationPlayer 流程仍可使用。", "source_path": source_path}
	return {"ok": false, "code": "character.aseprite_adapter_manual_handoff", "error_zh": "已检测到可选 Aseprite 扩展，请使用其公开导入入口生成 SpriteFrames。", "source_path": source_path}
