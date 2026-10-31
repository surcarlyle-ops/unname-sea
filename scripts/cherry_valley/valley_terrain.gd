extends Node3D
## (Claude Code) Cherry valley terrain: noise heightfield, river carve, path flatten,
## vertex-coloured smooth mesh, HeightMapShape3D collision and the spline helpers
## that the water, vegetation, navigation and prop placement all query.

const MESH_KIT: Script = preload("res://scripts/cherry_valley/valley_mesh_kit.gd")

var config: Dictionary
var materials: Dictionary
var sizes: Dictionary = {}

var _width: float = 280.0
var _depth: float = 280.0
var _resolution: int = 176
var _step: float = 1.6
var _noise: FastNoiseLite
var _noise_amplitude: float = 2.2
var _base_height: float = 1.35
var _hills: Array[Dictionary] = []
var _river_points: PackedVector2Array = PackedVector2Array()
var _river_widths: PackedFloat32Array = PackedFloat32Array()
var _river_width: float = 13.0
var _river_depth: float = 3.6
var _river_bank: float = 6.5
var _paths: Array[Dictionary] = []
var _palette: Dictionary = {}
## Parametric terrain features carved after the base landform is evaluated.
## Currently used by the waterfall plunge pool; both the mesh and the collision
## map are built from `height_at`, so they stay in agreement.
var _carves: Array[Dictionary] = []
var _heights: PackedFloat32Array = PackedFloat32Array()
var _river_distance_grid: PackedFloat32Array = PackedFloat32Array()
var _river_t_grid: PackedFloat32Array = PackedFloat32Array()
var _river_samples: PackedVector2Array = PackedVector2Array()
## Water plane height. Every river, bank and pad height is expressed against this
## instead of a literal 0, so moving the water level moves the whole channel.
var _water_level: float = 0.02
## Read-only water plane height for the bridge, waterfall and water modules.
var water_level: float:
	get:
		return _water_level
## Flat ground discs under buildings and at both bridge heads.
var _pads: Array[Dictionary] = []

const RIVER_SAMPLES: int = 72


## Build everything. `materials` supplies the toon ShaderMaterial factory results.
func build(cfg: Dictionary, kit_materials: Dictionary) -> void:
	config = cfg
	materials = kit_materials
	var terrain: Dictionary = cfg.terrain
	_width = float(terrain.size[0])
	_depth = float(terrain.size[1])
	_resolution = int(terrain.resolution)
	_step = _width / float(_resolution - 1)
	_base_height = float(terrain.base_height)
	_noise = FastNoiseLite.new()
	_noise.seed = int(terrain.noise.seed)
	_noise.frequency = float(terrain.noise.frequency)
	_noise.fractal_octaves = int(terrain.noise.octaves)
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_amplitude = float(terrain.noise.amplitude)
	for hill: Dictionary in terrain.hills:
		_hills.append({
			"center": Vector2(float(hill.center[0]), float(hill.center[1])),
			"radius": float(hill.radius),
			"height": float(hill.height),
		})
	var river: Dictionary = terrain.river
	for point: Array in river.points:
		_river_points.append(Vector2(float(point[0]), float(point[1])))
	_river_width = float(river.width)
	_river_depth = float(river.depth)
	_river_bank = float(river.bank)
	var samples: int = maxi(_river_points.size() * 14, 64)
	for i: int in range(samples):
		var t: float = float(i) / float(samples - 1)
		# Width breathes gently along the river so the banks are not parallel lines.
		_river_widths.append(_river_width * (0.86 + 0.28 * sin(t * 5.3 + 1.1) + 0.08 * sin(t * 13.0)))
	_river_samples = PackedVector2Array()
	for i: int in range(RIVER_SAMPLES):
		_river_samples.append(sample_river(float(i) / float(RIVER_SAMPLES - 1)))
	_water_level = float(cfg.get("water", {}).get("surface_offset", 0.02))
	_paths = []
	for path: Dictionary in terrain.paths:
		var points: PackedVector2Array = PackedVector2Array()
		for p: Array in path.points:
			points.append(Vector2(float(p[0]), float(p[1])))
		var lengths: Array[float] = []
		var total: float = 0.0
		for i: int in range(points.size() - 1):
			var length: float = points[i].distance_to(points[i + 1])
			lengths.append(length)
			total += length
		_paths.append({
			"name": str(path.name), "width": float(path.width), "points": points,
			"lengths": lengths, "total": total,
		})
	_palette = terrain.palette
	_build_carves(cfg)
	_build_pads(cfg)
	_build_heights()
	_build_mesh()
	_build_collision()


## Turn the configured scenic pieces (the waterfall lip and plunge pool) into
## heightfield operations so the landform matches the props placed on it.
func _build_carves(cfg: Dictionary) -> void:
	_carves.clear()
	if not cfg.has("waterfall") or not bool(cfg.waterfall.enabled):
		return
	var fall: Dictionary = cfg.waterfall.fall
	var fall_z: float = float(fall.z)
	# The lip always sits on the channel centre: the fall used to be authored 6 m
	# off the river, so its water landed on the bank instead of in the stream.
	var fall_x: float = river_point_at_z(fall_z).x
	# Shallow plunge pool just downstream of the lip. The old bowl was carved 16 m
	# deep into a hillside, which is why the fall read as a hole in the terrain.
	_carves.append({
		"type": "pool",
		"center": Vector2(fall_x, fall_z + 5.0),
		"radius": float(cfg.waterfall.get("pool_radius", 9.0)),
		"bed": _water_level - 1.35,
	})
	# Upstream of the lip the corridor becomes a rock shelf at crest height, so the
	# river visibly arrives from above instead of being cut straight through a hill.
	_carves.append({
		"type": "shelf",
		"z": fall_z - 2.0,
		"height": float(fall.top_y) - 1.0,
		"blend": float(fall.get("shelf_blend", 5.5)),
	})


## Smooth bowl under the fall plus the rock shelf that feeds it.
func _apply_carves(x: float, z: float, h: float, distance: float = 0.0) -> float:
	for carve: Dictionary in _carves:
		match str(carve.type):
			"pool":
				var center: Vector2 = carve.center
				var radius: float = float(carve.radius)
				var to_center: float = Vector2(x, z).distance_to(center)
				if to_center > radius:
					continue
				var weight: float = 1.0 - smoothstep(radius * 0.35, radius, to_center)
				h = lerpf(h, float(carve.bed), weight * 0.96)
			"shelf":
				var line: float = float(carve.z)
				var blend: float = float(carve.blend)
				var reach: float = _river_width * 0.5 + _river_bank + 16.0
				var lateral: float = 1.0 - smoothstep(reach * 0.55, reach, distance)
				var weight: float = smoothstep(line + blend * 0.5, line - blend * 0.5, z) * lateral
				if weight <= 0.0:
					continue
				h = lerpf(h, maxf(h, float(carve.height)), weight)
	return h


## Flat ground under every building and at both bridge heads. Buildings used to be
## dropped straight onto the noisy slope, so one corner floated and another sank.
func _build_pads(cfg: Dictionary) -> void:
	_pads.clear()
	var village: Dictionary = cfg.village
	var specs: Array = []
	if village.has("tea_house"):
		specs.append(village.tea_house)
	for house: Variant in village.houses:
		specs.append(house)
	if village.has("shrine"):
		specs.append(village.shrine)
	if village.has("pagoda"):
		specs.append(village.pagoda)
	# 导入的地标庭院也要一块压平的台地，否则四角会一角悬空一角陷进坡里。
	if cfg.has("landmark") and bool(cfg.landmark.get("enabled", false)):
		var landmark_footprint: float = float(cfg.landmark.get("footprint", 20.0))
		specs.append({"center": cfg.landmark.center, "size": [landmark_footprint, landmark_footprint]})
	for spec: Dictionary in specs:
		var center: Vector2 = Vector2(float(spec.center[0]), float(spec.center[1]))
		var footprint: float = 0.0
		if spec.has("size"):
			footprint = maxf(float(spec.size[0]), float(spec.size[1]))
		elif spec.has("base_width"):
			footprint = float(spec.base_width) + 4.0
		_add_pad(center, footprint * 0.62 + 1.4, 3.4)
	var bridge: Dictionary = village.bridge
	var bridge_center: Vector2 = Vector2(float(bridge.center[0]), float(bridge.center[1]))
	var half: float = bridge_span(bridge_center, bridge) * 0.5
	var axis: Vector2 = crossing_axis(bridge_center)
	for side: float in [-1.0, 1.0]:
		_add_pad(bridge_center + axis * half * side, 3.2, 3.4)


func _add_pad(center: Vector2, radius: float, feather: float) -> void:
	# Average a few samples so the terrace cuts into the uphill side instead of
	# hovering over the downhill one.
	var total: float = 0.0
	var weight: float = 0.0
	for step: int in range(5):
		var offset: Vector2 = Vector2.ZERO
		if step > 0:
			var angle: float = TAU * float(step - 1) / 4.0
			offset = Vector2(cos(angle), sin(angle)) * radius * 0.7
		var point: Vector2 = center + offset
		var query: Dictionary = river_query(point)
		total += _shaped_height(point.x, point.y, float(query.distance), float(query.t))
		weight += 1.0
	_pads.append({
		"center": center,
		"radius": radius,
		"feather": feather,
		"y": total / maxf(weight, 1.0) + 0.04,
	})


func _apply_pads(x: float, z: float, h: float) -> float:
	for pad: Dictionary in _pads:
		var center: Vector2 = pad.center
		var radius: float = float(pad.radius)
		var feather: float = float(pad.feather)
		var d: float = Vector2(x, z).distance_to(center)
		if d > radius + feather:
			continue
		var w: float = 1.0 - smoothstep(radius, radius + feather, d)
		h = lerpf(h, float(pad.y), w)
	return h


## Deck length needed so both ends land on the bank instead of in the water.
func bridge_span(center: Vector2, bridge: Dictionary) -> float:
	var query: Dictionary = river_query(center)
	var half_width: float = river_width_at(float(query.t)) * 0.5
	return maxf(float(bridge.span), 2.0 * (half_width + 3.4))


## World-space direction perpendicular to the river at a point.
func crossing_axis(center: Vector2) -> Vector2:
	var query: Dictionary = river_query(center)
	var t: float = float(query.t)
	var tangent: Vector2 = sample_river(minf(t + 0.01, 1.0)) - sample_river(maxf(t - 0.01, 0.0))
	if tangent.length_squared() < 0.0001:
		return Vector2.RIGHT
	tangent = tangent.normalized()
	return Vector2(-tangent.y, tangent.x)


# ---------------------------------------------------------------- sampling API

## Height of the raw valley before river/path shaping is applied. `noise_scale`
## lets the trail sampler reuse the same hills with the high-frequency detail
## removed, instead of inventing a second landform.
func _landform(x: float, z: float, river_distance: float, noise_scale: float = 1.0) -> float:
	var h: float = _base_height + _noise.get_noise_2d(x, z) * _noise_amplitude * noise_scale
	for hill: Dictionary in _hills:
		var center: Vector2 = hill.center
		var radius: float = hill.radius
		var d: float = Vector2(x, z).distance_to(center) / radius
		if d < 1.0:
			var falloff: float = 1.0 - d
			h += hill.height * falloff * falloff * (1.6 - 0.6 * falloff)
	# Valley bowl: the further from the river corridor the higher the ground rises.
	h += smoothstep(40.0, 130.0, river_distance) * 14.0
	return h


## Cross-section of the river. The bed is a bowl that reaches the water line at a
## known distance from the centre, then the bank climbs back to the natural ground.
## The old code subtracted a fixed depth from a noisy surface, so the bed poked
## through the water and the bank height changed every few metres.
func _river_profile(distance: float, t: float, natural: float) -> float:
	var half_width: float = river_width_at(t) * 0.5
	var shore: float = half_width * 0.94
	var outer: float = half_width + _river_bank
	if distance >= outer:
		return natural
	var edge_y: float = _water_level - 0.05
	if distance <= shore:
		var u: float = clampf(distance / maxf(shore, 0.1), 0.0, 1.0)
		return lerpf(_water_level - _river_depth, edge_y, pow(u, 2.0))
	var bank_top: float = maxf(natural, _water_level + 0.85)
	var v: float = clampf((distance - shore) / maxf(outer - shore, 0.1), 0.0, 1.0)
	# Convex bank: steep at the waterline, flattening out towards the field.
	return lerpf(edge_y, bank_top, pow(smoothstep(0.0, 1.0, v), 0.62))


## River + trail shaping, before pads and carves. Shared by the mesh builder and by
## every placement query so props and terrain can never disagree.
func _shaped_height(x: float, z: float, distance: float, t: float) -> float:
	var half_width: float = river_width_at(t) * 0.5
	# Damp the noise inside the corridor: a 3.2 m noise amplitude against a 3.6 m
	# deep channel is what made the shoreline ragged.
	var proximity: float = 1.0 - smoothstep(_river_bank * 0.7, _river_bank * 3.4, distance - half_width)
	var noise_scale: float = 1.0 - proximity * 0.88
	var natural: float = _landform(x, z, distance, noise_scale)
	var smooth_natural: float = _landform(x, z, distance, 0.0)
	var h: float = _river_profile(distance, t, natural)
	var h_smooth: float = _river_profile(distance, t, smooth_natural)
	# Trails keep their slope but lose the noise, so they read as walkable ground
	# instead of the flat shelf the old constant -0.06 target carved into the bank.
	for path: Dictionary in _paths:
		var width: float = float(path.width)
		var nearest: Dictionary = _nearest_on_path(path, Vector2(x, z))
		var d: float = float(nearest.distance)
		if d < width * 1.8:
			var w: float = smoothstep(width * 1.8, width * 0.55, d)
			h = lerpf(h, h_smooth, w * 0.9)
	return h


## Analytic height used by placement and by the mesh builder.
func height_at(x: float, z: float) -> float:
	var query: Dictionary = river_query(Vector2(x, z))
	var h: float = _shaped_height(x, z, float(query.distance), float(query.t))
	h = _apply_pads(x, z, h)
	return _apply_carves(x, z, h, float(query.distance))


## River centre sampled along its length, parameter t in [0,1].
func sample_river(t: float) -> Vector2:
	return catmull_rom_chain(_river_points, clampf(t, 0.0, 1.0))


func river_width_at(t: float) -> float:
	if _river_widths.is_empty():
		return _river_width
	var index: int = clampi(int(round(t * float(_river_widths.size() - 1))), 0, _river_widths.size() - 1)
	return _river_widths[index]


## Perpendicular distance to the river centre line plus the spline parameter of the
## closest point. Point sampling alone leaves a scalloped bank (the sample spacing
## is several metres), so the nearest sample is refined against its neighbours.
func river_query(point: Vector2) -> Dictionary:
	var count: int = _river_samples.size()
	if count < 2:
		return {"distance": 1e9, "t": 0.0}
	var best_index: int = 0
	var best_d2: float = 1e18
	for i: int in range(count):
		var d2: float = point.distance_squared_to(_river_samples[i])
		if d2 < best_d2:
			best_d2 = d2
			best_index = i
	var best_t: float = float(best_index) / float(count - 1)
	for i: int in range(maxi(best_index - 2, 0), mini(best_index + 2, count - 2) + 1):
		var a: Vector2 = _river_samples[i]
		var ab: Vector2 = _river_samples[i + 1] - a
		var local: float = clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d2: float = point.distance_squared_to(a + ab * local)
		if d2 < best_d2:
			best_d2 = d2
			best_t = (float(i) + local) / float(count - 1)
	return {"distance": sqrt(best_d2), "t": best_t}


func river_center_distance(point: Vector2) -> float:
	return float(river_query(point).distance)


## Is this point inside the water surface?
func is_water(x: float, z: float) -> bool:
	var query: Dictionary = river_query(Vector2(x, z))
	return float(query.distance) < river_width_at(float(query.t)) * 0.5 * 0.98


func nearest_river_t(point: Vector2) -> float:
	return float(river_query(point).t)


## Sample height used for prop placement: avoids placing things in the water.
func ground(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


## Distance from a point to the waterline: positive on land, negative in the water.
func shore_offset(x: float, z: float) -> float:
	var query: Dictionary = river_query(Vector2(x, z))
	return float(query.distance) - river_width_at(float(query.t)) * 0.5 * 0.94


## True when the point sits on the riverbank strip that should stay wet and bare.
func is_shore(x: float, z: float, band: float) -> bool:
	var offset: float = shore_offset(x, z)
	return offset > -0.6 and offset < band


## Centroid of the river at a given z slice, used for bridge and water placement.
func river_point_at_z(z: float) -> Vector2:
	var best: Vector2 = sample_river(0.0)
	var best_d: float = 1e9
	for i: int in range(80):
		var t: float = float(i) / 79.0
		var c: Vector2 = sample_river(t)
		var d: float = absf(c.y - z)
		if d < best_d:
			best_d = d
			best = c
	return best


# ---------------------------------------------------------------- mesh building

func _build_heights() -> void:
	_heights.resize(_resolution * _resolution)
	_river_distance_grid.resize(_resolution * _resolution)
	_river_t_grid.resize(_resolution * _resolution)
	for j: int in range(_resolution):
		for i: int in range(_resolution):
			var x: float = -_width * 0.5 + float(i) * _step
			var z: float = -_depth * 0.5 + float(j) * _step
			var query: Dictionary = river_query(Vector2(x, z))
			_river_distance_grid[j * _resolution + i] = float(query.distance)
			_river_t_grid[j * _resolution + i] = float(query.t)
			var h: float = _shaped_height(x, z, float(query.distance), float(query.t))
			h = _apply_pads(x, z, h)
			h = _apply_carves(x, z, h, float(query.distance))
			_heights[j * _resolution + i] = h


func _build_mesh() -> void:
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	var grass: Color = Color(_palette.grass)
	var grass_dark: Color = Color(_palette.grass_dark)
	var path_color: Color = Color(_palette.path)
	var rock: Color = Color(_palette.rock)
	var snow: Color = Color(_palette.snow)
	var river_bed: Color = Color(config.terrain.river.bed_color)
	var wet: Color = Color(config.terrain.river.wet_color)
	# Vertex colours double as cheap ambient occlusion: recessed areas darken.
	for j: int in range(_resolution - 1):
		for i: int in range(_resolution - 1):
			var x0: float = -_width * 0.5 + float(i) * _step
			var z0: float = -_depth * 0.5 + float(j) * _step
			var p00: Vector3 = Vector3(x0, _height(i, j), z0)
			var p10: Vector3 = Vector3(x0 + _step, _height(i + 1, j), z0)
			var p01: Vector3 = Vector3(x0, _height(i, j + 1), z0 + _step)
			var p11: Vector3 = Vector3(x0 + _step, _height(i + 1, j + 1), z0 + _step)
			var center: Vector3 = (p00 + p11) * 0.5
			# The river bed is a real surface now. Leaving it open (the previous
			# hack that let the mirrored copy show through) is what made the river
			# read as a flat band hovering over a void.
			var color: Color = _terrain_color(center, grass, grass_dark, path_color, rock, snow, river_bed, wet, i, j)
			var normal: Vector3 = (p10 - p00).cross(p01 - p00).normalized()
			if normal.y < 0.0:
				normal = -normal
			acc.tri(p00, p01, p10, color, normal)
			acc.tri(p10, p01, p11, color, normal)
	var mesh: MeshInstance3D = MESH_KIT.instance(acc, materials.terrain, "TerrainMesh")
	# Recompute smooth normals so the whole valley shades as one continuous surface.
	var arrays: Array = mesh.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = PackedVector3Array()
	norms.resize(verts.size())
	var key_scale: float = 20.0
	# Neighbouring triangles share exact corners; average their face normals.
	var accumulated: Dictionary = {}
	var tri_count: int = verts.size() / 3
	for t: int in range(tri_count):
		var a: Vector3 = verts[t * 3]
		var b: Vector3 = verts[t * 3 + 1]
		var c: Vector3 = verts[t * 3 + 2]
		var face: Vector3 = (b - a).cross(c - a).normalized()
		if face.y < 0.0:
			face = -face
		for v: Vector3 in [a, b, c]:
			var key: String = "%d_%d_%d" % [
				int(round(v.x * key_scale)), int(round(v.y * key_scale)), int(round(v.z * key_scale))
			]
			if not accumulated.has(key):
				accumulated[key] = Vector3.ZERO
			accumulated[key] = (accumulated[key] as Vector3) + face
	for i: int in range(verts.size()):
		var v: Vector3 = verts[i]
		var key: String = "%d_%d_%d" % [
			int(round(v.x * key_scale)), int(round(v.y * key_scale)), int(round(v.z * key_scale))
		]
		var sum: Vector3 = accumulated.get(key, Vector3.UP) as Vector3
		norms[i] = sum.normalized() if sum.length_squared() > 0.0001 else Vector3.UP
	arrays[Mesh.ARRAY_NORMAL] = norms
	mesh.mesh.clear_surfaces()
	mesh.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	add_child(mesh)
	sizes["terrain_triangles"] = tri_count
	sizes["terrain_vertices"] = verts.size()


func _height(i: int, j: int) -> float:
	return _heights[j * _resolution + i]


## Ground colour, built in bands from large to small: a broad meadow / dry-grass
## zone mask, then earth around the trails, then rock on the steep faces and a wet
## strip along the waterline. Detail noise is deliberately left to the shader.
func _terrain_color(point: Vector3, grass: Color, grass_dark: Color, path: Color, rock: Color, snow: Color, bed: Color, wet: Color, i: int, j: int) -> Color:
	var index: int = j * _resolution + i
	var distance: float = _river_distance_grid[index]
	var half_width: float = river_width_at(_river_t_grid[index]) * 0.5
	var dirt: Color = Color(_palette.get("dirt", "#8a7a5e"))
	var dry_grass: Color = Color(_palette.get("dry_grass", "#a5a375"))
	# 1. Large zones: a very low frequency mask splits meadow from sun-dried grass.
	var zone: float = _noise.get_noise_2d(point.x * 0.42 + 311.0, point.z * 0.42 - 173.0) * 0.5 + 0.5
	var result: Color = grass.lerp(dry_grass, smoothstep(0.45, 0.92, zone) * 0.62)
	# 2. Height banding: the valley floor stays green, the shoulders lean cooler.
	result = result.lerp(grass_dark, clampf((point.y - 3.0) / 16.0, 0.0, 1.0) * 0.5)
	# 3. Shoreline: a narrow wet gravel strip instead of a 13 m grey apron.
	var offset: float = distance - half_width
	if offset < 4.0:
		var shore_mix: float = 1.0 - smoothstep(-0.4, 4.0, offset)
		result = result.lerp(wet, shore_mix * 0.85)
	if point.y < _water_level - 0.02 and offset < 2.5:
		result = bed.lerp(wet, clampf((point.y - (_water_level - _river_depth)) / _river_depth, 0.0, 1.0) * 0.35)
	# 4. Carved pools read as wet stone, never as grass under water.
	for carve: Dictionary in _carves:
		if str(carve.type) != "pool":
			continue
		var to_center: float = Vector2(point.x, point.z).distance_to(carve.center)
		if to_center < float(carve.radius) * 1.2 and point.y < 0.6:
			var pool_mix: float = 1.0 - smoothstep(float(carve.radius) * 0.55, float(carve.radius) * 1.2, to_center)
			result = result.lerp(bed.lerp(wet, 0.35), pool_mix)
	# 5. Trails: a soft dirt shoulder under the flat part, the trodden path on top.
	for path_color_entry: Dictionary in _paths:
		var width: float = float(path_color_entry.width)
		var nearest: Dictionary = _nearest_on_path(path_color_entry, Vector2(point.x, point.z))
		var d: float = float(nearest.distance)
		if d < width * 1.7:
			var shoulder: float = 1.0 - smoothstep(width * 0.9, width * 1.7, d)
			result = result.lerp(dirt, shoulder * 0.55)
			var core: float = 1.0 - smoothstep(width * 0.35, width * 0.92, d)
			result = result.lerp(path, core * 0.9)
			break
	# 6. Steep ground reads as rock. Read neighbours from the cached height grid.
	var dx: float = (_height(mini(i + 1, _resolution - 1), j) - _height(maxi(i - 1, 0), j)) / (2.0 * _step)
	var dz: float = (_height(i, mini(j + 1, _resolution - 1)) - _height(i, maxi(j - 1, 0))) / (2.0 * _step)
	var gradient: float = sqrt(dx * dx + dz * dz)
	if gradient > 0.42:
		result = result.lerp(rock, clampf((gradient - 0.42) * 0.9, 0.0, 0.72))
	if point.y > 30.0:
		result = result.lerp(snow, clampf((point.y - 30.0) / 12.0, 0.0, 0.9))
	# 7. Tiny per-vertex jitter only breaks up banding; the visible texture is in
	# the shader, and a big per-vertex jitter is what made the slopes look grainy.
	var variation: float = _noise.get_noise_2d(point.x * 1.7, point.z * 1.7) * 0.012
	return Color(
		clampf(result.r + variation, 0.0, 1.0),
		clampf(result.g + variation * 0.9, 0.0, 1.0),
		clampf(result.b + variation * 0.7, 0.0, 1.0),
		1.0
	)


func _build_collision() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: HeightMapShape3D = HeightMapShape3D.new()
	# HeightMapShape3D samples are exactly 1 unit apart; fold the spacing into
	# the node scale and pre-divide the heights so the product matches.
	shape.map_width = _resolution
	shape.map_depth = _resolution
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(_resolution * _resolution)
	for index: int in range(_heights.size()):
		data[index] = _heights[index] / _step
	shape.map_data = data
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "TerrainShape"
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	body.scale = Vector3(_step, _step, _step)
	# HeightMapShape3D maps sample (0,0) to (-(w-1)/2, -(d-1)/2) *before* the node
	# scale, so the body needs a half-cell offset to put that sample at the mesh's
	# lower-left corner. Without it the whole collision map shifts half a valley.
	body.position = Vector3(-_step * 0.5, 0.0, -_step * 0.5)
	sizes["map_width"] = shape.map_width
	sizes["map_depth"] = shape.map_depth


# ---------------------------------------------------------------- spline helpers

## Uniform Catmull-Rom through the control points, t in [0,1].
func catmull_rom_chain(points: PackedVector2Array, t: float) -> Vector2:
	var count: int = points.size()
	if count == 0:
		return Vector2.ZERO
	if count == 1:
		return points[0]
	var scaled: float = clampf(t, 0.0, 1.0) * float(count - 1)
	var index: int = mini(int(floor(scaled)), count - 2)
	var local: float = scaled - float(index)
	var p0: Vector2 = points[maxi(index - 1, 0)]
	var p1: Vector2 = points[index]
	var p2: Vector2 = points[index + 1]
	var p3: Vector2 = points[mini(index + 2, count - 1)]
	return catmull_rom(p0, p1, p2, p3, local)


func catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


func sample_polyline(points: PackedVector2Array, t: float) -> Vector2:
	if points.size() < 2:
		return points[0] if points.size() == 1 else Vector2.ZERO
	var lengths: Array[float] = []
	var total: float = 0.0
	for i: int in range(points.size() - 1):
		var length: float = points[i].distance_to(points[i + 1])
		lengths.append(length)
		total += length
	var target: float = clampf(t, 0.0, 1.0) * total
	var walked: float = 0.0
	for i: int in range(lengths.size()):
		if walked + lengths[i] >= target:
			var local: float = (target - walked) / maxf(lengths[i], 0.0001)
			return points[i].lerp(points[i + 1], local)
		walked += lengths[i]
	return points[points.size() - 1]


## Fast nearest lookup for a path dict that already cached its segment lengths.
func _nearest_on_path(path: Dictionary, point: Vector2) -> Dictionary:
	var points: PackedVector2Array = path.points
	var lengths: Array[float] = path.lengths
	var total: float = float(path.total)
	var best_distance: float = 1e9
	var best_t: float = 0.0
	var walked: float = 0.0
	for i: int in range(lengths.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var ab: Vector2 = b - a
		var local: float = clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var closest: Vector2 = a + ab * local
		var distance: float = point.distance_to(closest)
		if distance < best_distance:
			best_distance = distance
			best_t = (walked + lengths[i] * local) / maxf(total, 0.0001)
		walked += lengths[i]
	return {"distance": best_distance, "t": best_t}


## Nearest point on a polyline: distance plus normalised position along it.
func nearest_on_polyline(points: PackedVector2Array, point: Vector2) -> Dictionary:
	var best_distance: float = 1e9
	var best_t: float = 0.0
	var total: float = 0.0
	var lengths: Array[float] = []
	for i: int in range(points.size() - 1):
		var length: float = points[i].distance_to(points[i + 1])
		lengths.append(length)
		total += length
	if total <= 0.0001:
		return {"distance": point.distance_to(points[0]) if not points.is_empty() else 1e9, "t": 0.0}
	var walked: float = 0.0
	for i: int in range(lengths.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var ab: Vector2 = b - a
		var local: float = clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var closest: Vector2 = a + ab * local
		var distance: float = point.distance_to(closest)
		if distance < best_distance:
			best_distance = distance
			best_t = (walked + lengths[i] * local) / total
		walked += lengths[i]
	return {"distance": best_distance, "t": best_t}
