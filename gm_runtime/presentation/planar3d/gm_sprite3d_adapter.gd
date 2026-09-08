class_name GMSprite3DAdapter
extends GMLightAsset3D

func configure_sprite(asset_id: String, target_ref: String = "", content_ref: String = "") -> Dictionary:
	return configure("Sprite3D", asset_id, target_ref, content_ref)
