class_name GMCuePresentation3D
extends "res://gm_runtime/feedback/gm_feedback_backend.gd"

## P18-compatible presentation backend for 3D VFX/text/audio channels.  Cue
## routing remains on the one GMCueRouter; this backend never owns facts.

const SEQUENCE_SCRIPT := preload("res://gm_runtime/feedback/gm_feedback_sequence_definition.gd")
const STEP_SCRIPT := preload("res://gm_runtime/feedback/gm_feedback_step.gd")
const CONTRACT := preload("res://gm_runtime/combat/gm_combat_contract.gd")

const STEP_KINDS := ["vfx", "text", "audio", "cue"]
const CHANNELS := ["world_vfx", "bone_vfx", "facility_vfx", "ground_vfx", "floating_text", "audio_3d", "camera"]
const CUE_IDS := {
	"world_vfx": "gm.cue.combat.3d.world_vfx",
	"bone_vfx": "gm.cue.combat.3d.bone_vfx",
	"facility_vfx": "gm.cue.combat.3d.facility_vfx",
	"ground_vfx": "gm.cue.combat.3d.ground_vfx",
	"floating_text": "gm.cue.combat.3d.floating_text",
	"audio_3d": "gm.cue.combat.3d.audio_3d",
	"camera": "gm.cue.combat.3d.camera",
}

var step_kind := "vfx"
var channels: Array[String] = []
var presentation_events: Array[Dictionary] = []
var _bound_router: Object

func _init(p_step_kind: String = "vfx", p_channels: Array = []) -> void:
	step_kind = p_step_kind
	super._init("gm.feedback.backend.%s" % step_kind)
	if p_channels.is_empty():
		if step_kind == "vfx":
			channels = ["world_vfx", "bone_vfx", "facility_vfx", "ground_vfx"]
		elif step_kind == "text":
			channels = ["floating_text"]
		elif step_kind == "audio":
			channels = ["audio_3d"]
		elif step_kind == "cue":
			channels = ["camera"]
	else:
		for value in p_channels:
			channels.append(str(value))

func accept_step(step, request, logical_tick: int) -> Dictionary:
	if step == null or request == null:
		return {"ok": false, "code": "feedback.backend_input_invalid", "reason_zh": "CuePresentation3D收到空步骤或空请求。"}
	if step.step_kind != step_kind:
		return {"ok": false, "code": "feedback.3d.step_kind_mismatch", "reason_zh": "CuePresentation3D后端不能接收其他步骤类型。"}
	var channel := str(step.metadata.get("channel", "")) if step.metadata is Dictionary else ""
	if not channels.has(channel):
		return {"ok": false, "code": "feedback.3d.channel_invalid", "reason_zh": "CuePresentation3D缺少受支持的表现频道。", "channel": channel}
	if not CONTRACT.stable_id(request.feedback_id) or not CONTRACT.stable_id(step.step_id):
		return {"ok": false, "code": "feedback.3d.identity_invalid", "reason_zh": "CuePresentation3D步骤身份无效。"}
	var event := {
		"backend_id": backend_id,
		"step_kind": step_kind,
		"step_id": step.step_id,
		"channel": channel,
		"feedback_id": request.feedback_id,
		"target_ref": request.target_ref,
		"logical_tick": logical_tick,
		"content_id": step.content_id,
		"text_zh": step.text_zh,
		"metadata": step.metadata.duplicate(true),
		"presentation_only": true,
		"domain_facts_written": false,
	}
	var stable := GMStableData.validate_persistence(event, "$.cue_presentation_3d.event")
	if not stable.ok:
		return {"ok": false, "code": "feedback.3d.event_not_pure", "reason_zh": "CuePresentation3D事件必须是稳定纯值。", "errors": stable.errors}
	accepted_steps.append(event.duplicate(true))
	presentation_events.append(event.duplicate(true))
	return {"ok": true, "code": "feedback.3d.step_accepted", "backend_id": backend_id, "channel": channel, "event": event}

func bind_router(router: Object) -> Dictionary:
	if router == null or not router.has_method("add_listener"):
		return {"ok": false, "code": "feedback.3d.cue_router_missing", "reason_zh": "CuePresentation3D缺少现有GMCueRouter。"}
	if _bound_router == router:
		return {"ok": true, "code": "feedback.3d.cue_router_idempotent"}
	var result: Dictionary = router.add_listener(Callable(self, "_on_cue_routed"))
	if not result.ok:
		return result
	_bound_router = router
	return {"ok": true, "code": "feedback.3d.cue_router_bound"}

func install_cue_definitions(router: Object, required: bool = true) -> Dictionary:
	if router == null or not router.has_method("register_definition"):
		return {"ok": false, "code": "feedback.3d.cue_router_missing", "reason_zh": "CuePresentation3D缺少现有GMCueRouter。"}
	var registered: Array[String] = []
	for channel in ["world_vfx", "bone_vfx", "facility_vfx", "ground_vfx", "floating_text", "audio_3d", "camera"]:
		var definition := GMCueDefinition.new()
		definition.cue_id = str(CUE_IDS[channel])
		definition.display_name_zh = "战斗3D表现·%s" % channel
		definition.semantic_tag = "combat.presentation_3d.%s" % channel
		definition.allowed_stages = PackedStringArray(["execute"])
		definition.required = required
		var result: Dictionary = router.register_definition(definition)
		if not result.ok:
			return {"ok": false, "code": "feedback.3d.cue_definition_invalid", "reason_zh": "CuePresentation3D Cue定义注册失败。", "details": result, "registered": registered}
		registered.append(definition.cue_id)
	return {"ok": true, "code": "feedback.3d.cues_registered", "cue_ids": registered}

func clear_feedback(feedback_id: String) -> Dictionary:
	var base := super.clear_feedback(feedback_id)
	var kept: Array[Dictionary] = []
	for event in presentation_events:
		if str(event.get("feedback_id", "")) != feedback_id:
			kept.append(event)
	presentation_events = kept
	return base

func snapshot() -> Dictionary:
	var base := super.snapshot()
	base["step_kind"] = step_kind
	base["channels"] = channels.duplicate()
	base["events"] = presentation_events.duplicate(true)
	base["presentation_only"] = true
	base["domain_facts_written"] = false
	return base

## Convenience installation keeps P18 as the only playback coordinator.
static func install_into(playback_service: Object, router: Object, required_cues: bool = true) -> Dictionary:
	if playback_service == null or not playback_service.has_method("register_backend"):
		return {"ok": false, "code": "feedback.3d.playback_missing", "reason_zh": "CuePresentation3D未连接现有P18 PlaybackService。"}
	var installed: Array[Object] = []
	for kind in ["vfx", "text", "audio"]:
		var backend := GMCuePresentation3D.new(kind)
		var result: Dictionary = playback_service.register_backend(backend)
		if not result.ok:
			return {"ok": false, "code": "feedback.3d.backend_register_failed", "reason_zh": "CuePresentation3D表现后端注册失败。", "details": result}
		installed.append(backend)
	var cue_backend := GMCuePresentation3D.new("cue")
	var cue_backend_register: Dictionary = playback_service.register_backend(cue_backend)
	if not cue_backend_register.ok:
		return {"ok": false, "code": "feedback.3d.backend_register_failed", "reason_zh": "CuePresentation3D Cue表现后端注册失败。", "details": cue_backend_register}
	var cue_register := cue_backend.install_cue_definitions(router, required_cues)
	if not cue_register.ok:
		return cue_register
	var bound := cue_backend.bind_router(router)
	if not bound.ok:
		return bound
	installed.append(cue_backend)
	return {"ok": true, "code": "feedback.3d.installed", "step_kinds": ["vfx", "text", "audio", "cue"], "backend_ids": installed.map(func(value): return value.backend_id), "cue_ids": cue_register.cue_ids, "router_bound": true, "presentation_only": true, "domain_facts_written": false}

static func build_sequence_definition(sequence_id: String, target_ref: String) -> GMFeedbackSequenceDefinition:
	var definition: GMFeedbackSequenceDefinition = SEQUENCE_SCRIPT.new(sequence_id, "Planar Combat 3D Cue反馈")
	definition.max_steps = 8
	definition.max_duration_ticks = 8
	for row in [
		["gm.feedback.3d.step.world_vfx", "world_vfx", "gm.content.combat.3d.world_vfx"],
		["gm.feedback.3d.step.bone_vfx", "bone_vfx", "gm.content.combat.3d.bone_vfx"],
		["gm.feedback.3d.step.facility_vfx", "facility_vfx", "gm.content.combat.3d.facility_vfx"],
		["gm.feedback.3d.step.ground_vfx", "ground_vfx", "gm.content.combat.3d.ground_vfx"],
	]:
		var step: GMFeedbackStep = STEP_SCRIPT.new(row[0], "vfx")
		step.target_ref = target_ref
		step.content_id = row[2]
		step.logical_order = 0
		step.parallel_group = "gm.feedback.3d.parallel.vfx"
		step.metadata = {"channel": row[1], "representation": "3d_vfx"}
		definition.steps.append(step)
	var text_step: GMFeedbackStep = STEP_SCRIPT.new("gm.feedback.3d.step.floating_text", "text")
	text_step.target_ref = target_ref
	text_step.content_id = "gm.content.combat.3d.floating_text"
	text_step.text_zh = "Planar命中"
	text_step.logical_order = 1
	text_step.after_step_ids = ["gm.feedback.3d.step.world_vfx", "gm.feedback.3d.step.bone_vfx", "gm.feedback.3d.step.facility_vfx", "gm.feedback.3d.step.ground_vfx"]
	text_step.metadata = {"channel": "floating_text", "representation": "3d_floating_text"}
	definition.steps.append(text_step)
	var audio_step: GMFeedbackStep = STEP_SCRIPT.new("gm.feedback.3d.step.audio", "audio")
	audio_step.target_ref = target_ref
	audio_step.content_id = "gm.content.combat.3d.audio_3d"
	audio_step.logical_order = 0
	audio_step.metadata = {"channel": "audio_3d", "representation": "Audio3D"}
	definition.steps.append(audio_step)
	var camera_step: GMFeedbackStep = STEP_SCRIPT.new("gm.feedback.3d.step.camera", "cue")
	camera_step.target_ref = target_ref
	camera_step.cue_id = str(CUE_IDS["camera"])
	camera_step.logical_order = 0
	camera_step.metadata = {"channel": "camera", "representation": "Camera Cue"}
	definition.steps.append(camera_step)
	return definition

func _on_cue_routed(cue: Dictionary) -> void:
	var cue_id := str(cue.get("cue_id", ""))
	if not CUE_IDS.values().has(cue_id):
		return
	var channel := ""
	for candidate in CUE_IDS.keys():
		if str(CUE_IDS[candidate]) == cue_id:
			channel = str(candidate)
			break
	if channel.is_empty():
		return
	var event := {
		"backend_id": backend_id,
		"step_kind": "cue",
		"channel": channel,
		"cue_id": cue_id,
		"target_id": str(cue.get("target_id", "")),
		"feedback_id": str(cue.get("parameters", {}).get("feedback_id", "")) if cue.get("parameters", {}) is Dictionary else "",
		"parameters": cue.get("parameters", {}).duplicate(true) if cue.get("parameters", {}) is Dictionary else {},
		"presentation_only": true,
		"domain_facts_written": false,
	}
	presentation_events.append(event)
