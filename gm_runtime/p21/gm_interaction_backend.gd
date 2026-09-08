class_name GMInteractionBackend
extends RefCounted

## Replaceable backend boundary. Implementations return a Dictionary or
## GMInteractionResult; the router normalizes both to one stable envelope.

var backend_id := "gm.interaction.backend.base"

func _init(p_backend_id: String = "gm.interaction.backend.base") -> void:
	backend_id = p_backend_id if GMP21Contract.stable_id(p_backend_id) else "gm.interaction.backend.base"

func submit(_request: GMInteractionRequest) -> Variant:
	return {"status": "rejected", "code": "interaction.backend_not_implemented", "reason_zh": "当前交互Backend未实现提交。", "payload": {}}

func can_handle(_kind: String) -> bool:
	return true

