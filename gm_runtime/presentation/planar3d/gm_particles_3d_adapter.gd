class_name GMParticles3DAdapter
extends GMLightAsset3D

func configure_particles(asset_id: String, target_ref: String = "", content_ref: String = "") -> Dictionary:
	return configure("Particles", asset_id, target_ref, content_ref)
