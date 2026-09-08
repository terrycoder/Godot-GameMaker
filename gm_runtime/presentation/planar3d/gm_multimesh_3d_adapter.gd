class_name GMMultiMesh3DAdapter
extends GMLightAsset3D

func configure_multimesh(asset_id: String, target_ref: String = "", content_ref: String = "") -> Dictionary:
	return configure("MultiMesh", asset_id, target_ref, content_ref)
