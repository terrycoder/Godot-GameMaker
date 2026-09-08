class_name GMPoseSamplingAdapter
extends RefCounted

## Adapter 只把 Profile 采样结果交给 Skeleton 呈现层。

func sample(pose: Variant, logical_time: float, profile: GMAnimationSamplingProfile, duration: float = 1.0) -> Dictionary:
	if profile == null: return {"ok": false, "code": "pose_sampling.profile_missing", "error_zh": "Pose Sampling Profile缺失。", "failure_closed": true}
	var checked := profile.validate_sampling()
	if not bool(checked.get("ok", false)): return {"ok": false, "code": "pose_sampling.profile_invalid", "error_zh": str(checked.get("error_zh", "Pose Sampling Profile无效。")), "details": checked, "failure_closed": true}
	return profile.sample_pose(pose, logical_time, duration)

func sample_skeleton_pose(pose: Variant, logical_time: float, profile: GMAnimationSamplingProfile, duration: float = 1.0) -> Dictionary:
	return sample(pose, logical_time, profile, duration)
