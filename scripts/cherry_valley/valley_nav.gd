extends Node3D
## (Claude Code) Walkable navigation. Builds a dedicated low-poly walkable mesh
## (paths, village yard, bridge deck, shrine apron) and bakes it synchronously —
## no parse_source_geometry_data, which is experimental in 4.7.

var config: Dictionary
var terrain: Node3D
var region: NavigationRegion3D
var navigation_mesh: NavigationMesh
var sizes: Dictionary = {}
var baked: bool = false


func build(cfg: Dictionary, terrain_node: Node3D) -> void:
	config = cfg
	terrain = terrain_node
	var nav_settings: Dictionary = cfg.navigation
	navigation_mesh = NavigationMesh.new()
	navigation_mesh.cell_size = float(nav_settings.cell_size)
	navigation_mesh.cell_height = float(nav_settings.cell_size) * 0.5
	navigation_mesh.agent_radius = float(nav_settings.agent_radius)
	navigation_mesh.agent_height = float(nav_settings.agent_height)
	navigation_mesh.agent_max_slope = deg_to_rad(float(nav_settings.max_slope_degrees))
	navigation_mesh.agent_max_climb = float(nav_settings.max_climb)
	navigation_mesh.region_min_size = 4.0
	navigation_mesh.region_merge_size = 12.0
	navigation_mesh.filter_low_hanging_obstacles = false
	navigation_mesh.filter_ledge_spans = false
	var walkable: ArrayMesh = _walkable_mesh()
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	source.add_mesh_array(_mesh_arrays(walkable), Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source)
	region = NavigationRegion3D.new()
	region.name = "ValleyNavigation"
	region.navigation_mesh = navigation_mesh
	add_child(region)
	baked = navigation_mesh.get_polygon_count() > 0
	sizes["nav_polygons"] = navigation_mesh.get_polygon_count()


## Simple textured-free walkable surface: paths + yards + bridge, sampled at a
## coarse spacing to keep the bake fast.
func _walkable_mesh() -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var steps: int = 3
	for path: Dictionary in config.terrain.paths:
		var points: PackedVector2Array = PackedVector2Array()
		for p: Array in path.points:
			points.append(Vector2(float(p[0]), float(p[1])))
		var width: float = float(path.width) + 1.0
		var samples: int = maxi(points.size() * 8, 16)
		var start_index: int = vertices.size()
		for sample: int in range(samples):
			var t: float = float(sample) / float(samples - 1)
			var center: Vector2 = terrain.sample_polyline(points, t)
			# Slight forward sample gives the local tangent for the strip width.
			var ahead: Vector2 = terrain.sample_polyline(points, minf(t + 0.01, 1.0))
			var tangent: Vector2 = ahead - center
			if tangent.length_squared() < 0.0001:
				tangent = Vector2(0, 1)
			tangent = tangent.normalized()
			var side: Vector2 = Vector2(-tangent.y, tangent.x) * width * 0.5
			for column: int in range(steps):
				var offset: float = float(column) / float(steps - 1) * 2.0 - 1.0
				var point: Vector2 = center + side * offset
				var y: float = terrain.height_at(point.x, point.y) + 0.06
				y = maxf(y, _bridge_deck_height(point))
				vertices.append(Vector3(point.x, y, point.y))
			if sample > 0:
				for column: int in range(steps - 1):
					var a: int = start_index + (sample - 1) * steps + column
					var b: int = a + 1
					var c: int = a + steps
					var d: int = c + 1
					# Clockwise winding for the navmesh parser.
					indices.append(a)
					indices.append(c)
					indices.append(b)
					indices.append(b)
					indices.append(c)
					indices.append(d)
	var areas: Array = config.navigation.areas
	for area: Dictionary in areas:
		_append_patch(
			vertices, indices,
			Vector2(float(area.center[0]), float(area.center[1])),
			Vector2(float(area.size[0]), float(area.size[1])),
			area.height
		)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Square patch (yards, bridge deck). `fixed_height` -1 means "follow terrain".
func _append_patch(vertices: PackedVector3Array, indices: PackedInt32Array, center: Vector2, size: Vector2, fixed_height: Variant) -> void:
	var cells: int = 8
	var start_index: int = vertices.size()
	for row: int in range(cells + 1):
		for column: int in range(cells + 1):
			var local: Vector2 = Vector2(
				(float(column) / float(cells) - 0.5) * size.x,
				(float(row) / float(cells) - 0.5) * size.y
			)
			var point: Vector2 = center + local
			var y: float = terrain.height_at(point.x, point.y) + 0.06
			if fixed_height != null:
				y = maxf(float(fixed_height), y - 0.2)
			vertices.append(Vector3(point.x, y, point.y))
	for row: int in range(cells):
		for column: int in range(cells):
			var a: int = start_index + row * (cells + 1) + column
			var b: int = a + 1
			var c: int = a + (cells + 1)
			var d: int = c + 1
			indices.append(a)
			indices.append(c)
			indices.append(b)
			indices.append(b)
			indices.append(c)
			indices.append(d)


## Bridge deck height at a world point, matching the arched deck collision.
func _bridge_deck_height(point: Vector2) -> float:
	var bridge: Dictionary = config.village.bridge
	var center: Vector2 = Vector2(float(bridge.center[0]), float(bridge.center[1]))
	var span: float = float(bridge.span)
	var width: float = float(bridge.width)
	var deck_y: float = float(bridge.height)
	var local: Vector2 = point - center
	if absf(local.x) > span * 0.5 + 0.5 or absf(local.y) > width * 0.6:
		return -1000.0
	var t: float = clampf((local.x + span * 0.5) / span, 0.0, 1.0)
	return deck_y + sin(t * PI) * 0.55 + 0.10


func _mesh_arrays(mesh: ArrayMesh) -> Array:
	return mesh.surface_get_arrays(0)


func polygon_exists() -> bool:
	return baked and navigation_mesh != null and navigation_mesh.get_polygon_count() > 0
