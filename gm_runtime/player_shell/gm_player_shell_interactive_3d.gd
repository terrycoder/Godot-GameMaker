class_name GMPlayerShellInteractive3D
extends StaticBody3D

## 3D query projection.  The stable identity is authored on the object and is
## the only identity accepted by GMInteractionQuery3D.

@export var stable_instance_id := ""
@export var map_id := ""
@export var spatial_position: Dictionary = {}

func _ready() -> void:
	if not stable_instance_id.is_empty():
		set_meta("gm_stable_instance_id", stable_instance_id)
