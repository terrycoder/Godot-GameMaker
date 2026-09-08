@tool
class_name GMSurfaceGizmoNode
extends Node3D

## Editor-only projection anchor for a saved Surface Graph.
## The node carries no runtime facts, entities, navigation state or save data.

@export var graph: Resource
@export var surface_id: StringName = &""

func surface_definition() -> Resource:
	if graph == null or not graph.has_method("resolve_surface"):
		return null
	return graph.call("resolve_surface", str(surface_id)) as Resource
