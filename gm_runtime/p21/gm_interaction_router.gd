class_name GMInteractionRouter
extends RefCounted

## One routing surface for Ability/Task/Transaction/Process requests.

var backends: Dictionary = {}

func register_backend(kind: String, backend: GMInteractionBackend) -> Dictionary:
	if kind not in GMP21Contract.INTERACTION_KINDS:
		return GMP21Contract.failure("interaction.kind_invalid", "交互类型不受支持。", {"kind": kind})
	if backend == null or not is_instance_valid(backend):
		return GMP21Contract.failure("interaction.backend_missing", "不能注册空Backend。")
	if not backend.can_handle(kind):
		return GMP21Contract.failure("interaction.backend_kind_unsupported", "Backend不支持声明的交互类型。", {"kind": kind, "backend_id": backend.backend_id})
	backends[kind] = backend
	return {"ok": true, "code": "interaction.backend_registered", "kind": kind}

func unregister_backend(kind: String) -> Dictionary:
	if not backends.has(kind):
		return {"ok": true, "already_missing": true, "kind": kind}
	backends.erase(kind)
	return {"ok": true, "kind": kind}

func submit(request_value: Variant) -> GMInteractionResult:
	var decoded := _decode_request(request_value)
	if not decoded.ok:
		var public_request: Variant = request_value.to_dict() if request_value is GMInteractionRequest else request_value
		return GMInteractionResult.rejected_public(public_request, str(decoded.get("code", "interaction.request_invalid")), str(decoded.get("reason_zh", "交互请求无效。")), {"validation": decoded})
	var request: GMInteractionRequest = decoded.request
	var backend: GMInteractionBackend = backends.get(request.kind, null)
	if backend == null:
		return GMInteractionResult.rejected(request, "interaction.backend_missing", "当前交互类型没有可用Backend。", {"kind": request.kind})
	var raw: Variant = backend.submit(request)
	var normalized: GMInteractionResult = GMInteractionResult.from_backend(request, raw, backend.backend_id)
	if normalized.request_id != request.request_id or normalized.interaction_id != request.interaction_id or normalized.kind != request.kind:
		return GMInteractionResult.rejected(request, "interaction.backend_identity_mismatch", "Backend结果身份与请求不一致。")
	var checked: Dictionary = normalized.validate()
	if not checked.ok:
		return GMInteractionResult.rejected(request, "interaction.backend_result_invalid", "Backend结果未通过稳定合同校验。", {"validation": checked})
	return normalized

func submit_dict(value: Dictionary) -> Dictionary:
	var result := submit(value)
	return result.to_dict()

func _decode_request(value: Variant) -> Dictionary:
	if value is GMInteractionRequest:
		var request: GMInteractionRequest = value
		var checked := request.validate()
		return {"ok": true, "request": request} if checked.ok else checked
	if value is Dictionary:
		return GMInteractionRequest.from_dict(value)
	return GMP21Contract.failure("interaction.request_type_invalid", "交互提交需要GMInteractionRequest或其纯值Dictionary。")
