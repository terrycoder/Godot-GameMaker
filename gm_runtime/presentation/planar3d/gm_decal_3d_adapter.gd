class_name GMDecal3DAdapter
extends GMLightAsset3D

func configure_decal(asset_id: String, target_ref: String = "", content_ref: String = "") -> Dictionary:
	return configure("Decal", asset_id, target_ref, content_ref)
