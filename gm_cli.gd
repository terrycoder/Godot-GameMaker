extends SceneTree

const PLATFORM_SCRIPT := preload("res://gm_runtime/gm_platform.gd")
const MODULE_REGISTRY_SCRIPT := preload("res://gm_runtime/gm_module_registry.gd")
const PROFILE := preload("res://gm_runtime/gm_module_profile.tres")

const SUPPORTED_COMMANDS := [
	"help",
	"environment",
	"compatibility",
	"validate",
	"modules",
]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var command := str(args[0]) if not args.is_empty() else "help"
	var result := _run(command)
	print("GM CLI | %s | %s" % [command, "PASS" if bool(result.get("ok", false)) else "FAIL"])
	print(JSON.stringify(result))
	quit(0 if bool(result.get("ok", false)) else 2)

func _run(command: String) -> Dictionary:
	match command:
		"help":
			return {
				"ok": true,
				"command": command,
				"supported_commands": SUPPORTED_COMMANDS,
				"note_zh": "发布包只保留只读的平台检查命令；内部测试、GUT、fixture、审查证据和历史导出命令不随包提供。",
			}
		"environment":
			return _as_result(command, PLATFORM_SCRIPT.environment())
		"compatibility":
			return _as_result(command, PLATFORM_SCRIPT.compatibility())
		"validate":
			return _as_result(command, PLATFORM_SCRIPT.validate())
		"modules":
			var registry = MODULE_REGISTRY_SCRIPT.new()
			var resolved: Dictionary = registry.resolve(PROFILE.enabled_modules)
			return {
				"ok": bool(resolved.get("ok", false)),
				"command": command,
				"template_id": PROFILE.template_id,
				"enabled_modules": PROFILE.enabled_modules,
				"resolution": resolved,
			}
		_:
			return {
				"ok": false,
				"command": command,
				"code": "cli.command_unsupported_in_release",
				"supported_commands": SUPPORTED_COMMANDS,
				"error_zh": "此命令属于内部测试或历史交付流程，发布包不提供。",
			}

func _as_result(command: String, value: Variant) -> Dictionary:
	var payload: Dictionary = value if value is Dictionary else {"value": value}
	var result := payload.duplicate(true)
	result["command"] = command
	if not result.has("ok"):
		result["ok"] = true
	return result
