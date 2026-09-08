class_name GMInstanceGroupPresentation3D
extends GMLightAsset3D

func configure_group(asset_id: String, target_ref: String = "", content_ref: String = "") -> Dictionary:
	return configure("Instance Group", asset_id, target_ref, content_ref)
