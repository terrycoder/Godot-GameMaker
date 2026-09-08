class_name GMExt3D03CourtyardSample
extends RefCounted

## Tier1 content fixture: courtyard -> indoor floor -> upper bridge, with
## stairs/bridge/portal connections, three stable anchors, a patrol route and
## one neutral interactive object.  This file is development content only.

const MAP_ID := "gm.map.ext3d03.courtyard"
const COURTYARD_ID := "gm.surface.ext3d03.courtyard"
const INDOOR_ID := "gm.surface.ext3d03.indoor"
const BRIDGE_ID := "gm.surface.ext3d03.bridge_upper"
const GRAPH_ID := "gm.surface_graph.ext3d03.courtyard"

static func build_registry() -> GMMapSemanticRegistry:
	var registry := GMMapSemanticRegistry.new()
	var semantic := GMMapSemanticResource.new()
	semantic.map_id = MAP_ID
	semantic.surface_ids = PackedStringArray([COURTYARD_ID, INDOOR_ID, BRIDGE_ID])
	for row in [["gm.anchor.ext3d03.courtyard_start", Vector2(2.0, 2.0), COURTYARD_ID, "庭院起点"], ["gm.anchor.ext3d03.indoor_goal", Vector2(18.0, 18.0), INDOOR_ID, "室内目标"], ["gm.anchor.ext3d03.bridge_upper", Vector2(5.0, 5.0), BRIDGE_ID, "桥面目标"]]:
		var anchor := GMSemanticAnchor.new()
		anchor.anchor_id = row[0]
		anchor.position = row[1]
		anchor.surface_id = row[2]
		anchor.editor_label = row[3]
		semantic.anchors.append(anchor)
	var route := GMSemanticRoute.new()
	route.route_id = "gm.route.ext3d03.courtyard_patrol"
	route.map_id = MAP_ID
	route.closed = true
	route.points = [{"position": Vector2(2.0, 2.0), "surface_id": COURTYARD_ID, "wait": 0.1}, {"position": Vector2(18.0, 18.0), "surface_id": COURTYARD_ID, "wait": 0.1}]
	semantic.routes = [route]
	var registered := registry.register_map(semantic)
	return registry if registered.ok else null

static func build_graph() -> GMSurfaceGraph:
	var graph := GMSurfaceGraph.new()
	graph.graph_id = GRAPH_ID
	graph.map_id = MAP_ID
	graph.display_name_zh = "EXT03中性小院Tier1"
	var courtyard := GMSurfaceDefinition3D.rectangle(COURTYARD_ID, MAP_ID, "courtyard", Vector3(0.0, 0.0, 0.0), Vector2(20.0, 20.0))
	courtyard.display_name_zh = "庭院"
	var indoor := GMSurfaceDefinition3D.rectangle(INDOOR_ID, MAP_ID, "floor", Vector3(22.0, 4.0, 0.0), Vector2(20.0, 20.0))
	indoor.display_name_zh = "室内二层"
	var bridge := GMSurfaceDefinition3D.rectangle(BRIDGE_ID, MAP_ID, "bridge", Vector3(45.0, 8.0, 14.0), Vector2(10.0, 10.0))
	bridge.display_name_zh = "上层桥面"
	graph.register_surface(courtyard)
	graph.register_surface(indoor)
	graph.register_surface(bridge)
	graph.register_connection(_connection("gm.connection.ext3d03.stairs", COURTYARD_ID, INDOOR_ID, "stairs", Vector2(18.0, 10.0), Vector2(0.0, 10.0), true))
	graph.register_connection(_connection("gm.connection.ext3d03.bridge", INDOOR_ID, BRIDGE_ID, "bridge", Vector2(20.0, 18.0), Vector2(0.0, 5.0), true))
	graph.register_connection(_connection("gm.connection.ext3d03.portal", BRIDGE_ID, COURTYARD_ID, "portal", Vector2(5.0, 5.0), Vector2(2.0, 2.0), false))
	return graph

static func build_fixture() -> Dictionary:
	var registry := build_registry()
	var graph := build_graph()
	var backend := GMMapBackend3D.new()
	var configured := backend.configure_graph(graph)
	if not configured.ok: return {"ok": false, "code": "sample.graph_invalid", "details": configured}
	var adapter := GMPlanar3DSpatialAdapter.new(registry, true, backend)
	return {"ok": true, "registry": registry, "graph": graph, "backend": backend, "adapter": adapter, "map_id": MAP_ID, "surface_ids": [COURTYARD_ID, INDOOR_ID, BRIDGE_ID], "anchors": ["gm.anchor.ext3d03.courtyard_start", "gm.anchor.ext3d03.indoor_goal", "gm.anchor.ext3d03.bridge_upper"], "controls_zh": ["点击地面选择移动目标", "鼠标/控制器选择交互对象", "固定正交相机跟随角色", "保存后可关闭并重开当前Surface"]}

static func _connection(connection_id: String, source_surface: String, target_surface: String, kind: String, source_exit: Vector2, target_entry: Vector2, bidirectional: bool) -> GMSurfaceConnection:
	var connection := GMSurfaceConnection.new()
	connection.connection_id = connection_id
	connection.source_map_id = MAP_ID
	connection.source_surface_id = source_surface
	connection.target_map_id = MAP_ID
	connection.target_surface_id = target_surface
	connection.connection_kind = kind
	connection.source_exit = source_exit
	connection.target_entry = target_entry
	connection.bidirectional = bidirectional
	connection.direction = "source_to_target"
	connection.agent_profiles = PackedStringArray(["default"])
	connection.traversal_cost = 2.0
	return connection
