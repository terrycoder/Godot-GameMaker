class_name GMBillboard3DAdapter
extends GMLightAsset3D

func configure_billboard(asset_id: String, target_ref: String = "", content_ref: String = "") -> Dictionary:
	return configure("Billboard", asset_id, target_ref, content_ref)
