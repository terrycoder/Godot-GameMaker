@tool
class_name GMAnimationSamplingProfile
extends GMContent

## Pose Sampling 只改变 Skeleton 的取样时间，不改变逻辑时间、根位移、碰撞或 Cue。

const CONTENT_TYPE_ID := "gm.presentation.animation_sampling_profile"
const SCHEMA_VERSION := "gm.presentation.animation_sampling_profile.v1"
const MODES := ["8", "10", "12", "15", "Smooth"]

@export_group("Animation Sampling")
@export var sampling_mode: String = "Smooth"
@export_range(0, 60, 1) var samples_per_cycle: int = 0
@export var interpolation: String = "linear"

func _init() -> void:
	content_type_id = CONTENT_TYPE_ID

func validate_sampling() -> Dictionary:
	var errors: Array[String] = []
	if sampling_mode not in MODES: errors.append("pose_sampling.mode_invalid：Sampling Mode必须是8、10、12、15或Smooth。")
	var expected := 0 if sampling_mode == "Smooth" else int(sampling_mode)
	if samples_per_cycle != expected: errors.append("pose_sampling.rate_invalid：Samples per Cycle必须与Sampling Mode一致。")
	if interpolation not in ["linear", "nearest"]: errors.append("pose_sampling.interpolation_invalid：插值模式不受支持。")
	var identity_errors := GMContentValidator.validate_content(self, resource_path, {}, true)
	if not bool(identity_errors.get("ok", false)):
		for issue in identity_errors.get("errors_zh", []): errors.append(str(issue))
	return {"ok": errors.is_empty(), "code": "pose_sampling.valid" if errors.is_empty() else "pose_sampling.invalid", "errors_zh": errors, "error_zh": "Pose Sampling Profile校验通过。" if errors.is_empty() else str(errors[0]), "failure_closed": true}

func validate() -> Dictionary:
	return validate_sampling()

func sample_time(logical_time: float, duration: float = 1.0) -> Dictionary:
	if not is_finite(logical_time) or not is_finite(duration) or duration <= 0.0: return {"ok": false, "code": "pose_sampling.time_invalid", "error_zh": "逻辑时间或动画时长无效。", "failure_closed": true}
	var normalized := fmod(logical_time, duration)
	if normalized < 0.0: normalized += duration
	var sampled := normalized
	if sampling_mode != "Smooth":
		var step := duration / float(samples_per_cycle)
		sampled = floor(normalized / step + 0.5) * step
		if sampled >= duration: sampled = 0.0
	return {"ok": true, "code": "pose_sampling.sampled", "mode": sampling_mode, "logical_time": logical_time, "sampled_time": sampled, "duration": duration, "logic_time_unchanged": true, "root_motion_unchanged": true}

func sample_pose(pose: Variant, logical_time: float, duration: float = 1.0) -> Dictionary:
	var timing := sample_time(logical_time, duration)
	if not bool(timing.get("ok", false)): return timing
	if pose is Object: return {"ok": false, "code": "pose_sampling.pose_unstable", "error_zh": "Pose不能包含运行时对象引用。", "failure_closed": true}
	var copied: Variant = pose.duplicate(true) if pose is Dictionary or pose is Array else pose
	return {"ok": true, "code": "pose_sampling.pose_sampled", "pose": copied, "timing": timing, "root_state": pose.get("root_state", {}) if pose is Dictionary else {}, "logic_state_changed": false, "root_motion_changed": false, "collision_changed": false, "cue_changed": false, "presentation_only": true}

func to_native() -> Dictionary:
	return {"schema": SCHEMA_VERSION, "display_name_zh": display_name_zh, "content_id": content_id, "content_type_id": content_type_id, "tags": Array(tags), "content_version": content_version, "source": source, "deprecated": deprecated, "aliases": Array(aliases), "sampling_mode": sampling_mode, "samples_per_cycle": samples_per_cycle, "interpolation": interpolation, "logic_time_unchanged": true, "root_motion_unchanged": true, "presentation_only": true}

static func from_native(value: Variant) -> GMAnimationSamplingProfile:
	if not value is Dictionary: return null
	var profile := GMAnimationSamplingProfile.new()
	profile.display_name_zh = str(value.get("display_name_zh", profile.display_name_zh))
	profile.content_id = str(value.get("content_id", profile.content_id))
	profile.content_type_id = CONTENT_TYPE_ID
	profile.tags = PackedStringArray(value.get("tags", Array(profile.tags)))
	profile.content_version = str(value.get("content_version", profile.content_version))
	profile.source = str(value.get("source", profile.source))
	profile.deprecated = bool(value.get("deprecated", profile.deprecated))
	profile.aliases = PackedStringArray(value.get("aliases", Array(profile.aliases)))
	profile.sampling_mode = str(value.get("sampling_mode", profile.sampling_mode))
	profile.samples_per_cycle = int(value.get("samples_per_cycle", profile.samples_per_cycle))
	profile.interpolation = str(value.get("interpolation", profile.interpolation))
	return profile
