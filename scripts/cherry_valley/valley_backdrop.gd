extends Node3D
## (Claude Code) Distant ridge silhouettes and low river mist.
##
## The valley itself only reaches z = -140 with hills 42 m tall, so past the
## waterfall the panorama looked into empty sky. The reference shot sells the
## depth with hazy ridge tiers on the horizon; this module builds those
## silhouettes and the ground mist that ties them to the village, so the haze
## sheets have something to wrap instead of floating in front of the sky.
##
## Layers are anchored to the river mouth and pushed down-valley along the
## configured azimuths, so re-aiming the valley never leaves a ridge in frame
## where the terrain does not meet it.

const RIDGE_SEGMENTS: int = 128
const RIDGE_ROWS: int = 6
const MIST_SEGMENTS: int = 44
const RIDGE_SHADER: String = "res://shaders/valley_ridge.gdshader"

var config: Dictionary
var terrain: Node3D
var materials: Dictionary
var sizes: Dictionary = {}

var _ridges: Array[MeshInstance3D] = []
var _ridge_materials: Array[ShaderMaterial] = []
var _ridge_shader: Shader
var _mist_bands: Array[MeshInstance3D] = []


func build(cfg: Dictionary, terrain_node: Node3D, kit_materials: Dictionary) -> void:
	config = cfg
	terrain = terrain_node
	materials = kit_materials
	_build_ridges()
	_build_mist()


func set_mood(mood: Dictionary) -> void:
	# Ridges are unshaded cards coloured by baked vertex shades, so a mood change
	# only moves their tint toward the mood's haze and re-derives the alpha.
	var tint: Color = Color(mood.get("ridge_tint", "#ffffff"))
	var haze_alpha: float = float(mood.get("haze_alpha", 0.055))
	for index: int in range(_ridge_materials.size()):
		var material: ShaderMaterial = _ridge_materials[index]
		material.set_shader_parameter("tint", Color(_base_ridge_color(index) * tint, _ridge_alpha(index, haze_alpha)))
	for index: int in range(_mist_bands.size()):
		var mist_material: StandardMaterial3D = _mist_bands[index].material_override as StandardMaterial3D
		if mist_material != null:
			var weight: float = lerpf(0.45, 1.0, float(index) / maxf(1.0, float(_mist_bands.size() - 1)))
			mist_material.albedo_color = Color(Color(mood.fog_color), 0.10 * weight * haze_alpha / 0.055)


func apply_quality(settings: Dictionary) -> void:
	var distance: float = float(settings.get("tree_distance", 240.0))
	for ridge: MeshInstance3D in _ridges:
		ridge.visibility_range_end = maxf(distance * 3.0, 700.0)
	for band: MeshInstance3D in _mist_bands:
		band.visibility_range_end = maxf(distance, 200.0)


# ---------------------------------------------------------------- ridges

func _build_ridges() -> void:
	if not config.has("valley"):
		return
	_ridge_shader = load(RIDGE_SHADER) as Shader
	var mouth: Vector2 = terrain.sample_river(1.0)
	var count: int = 0
	for entry: Dictionary in config.valley.ridges:
		count += 1
		_build_ridge(entry, mouth, count)
	sizes["ridges"] = _ridges.size()


## One ridge = two slices of the same skyline at different depths: the far slice
## keeps the haze colour, the near one sits a little darker and taller, which is
## the tier contrast the reference uses before the sky.
func _build_ridge(entry: Dictionary, mouth: Vector2, index: int) -> void:
	var azimuth: float = deg_to_rad(float(entry.azimuth))
	# Azimuth 180 points down-valley (-Z); 150 and 210 fan out east and west.
	var direction: Vector2 = Vector2(sin(azimuth), cos(azimuth))
	var distance: float = float(entry.distance)
	var span: float = float(entry.span)
	var height: float = float(entry.height)
	var steepness: float = float(entry.steepness)
	var noise_amount: float = float(entry.noise)
	var base_y: float = float(terrain.water_level) + 0.5
	for slice: int in range(2):
		var slice_distance: float = distance + float(slice) * distance * 0.20
		var center: Vector2 = mouth + direction * slice_distance
		var slice_height: float = height * (1.0 - float(slice) * 0.26)
		var slice_span: float = span * (1.0 - float(slice) * 0.12)
		var mesh: ArrayMesh = _ridge_mesh(center, slice_height, slice_span, steepness,
			noise_amount, int(entry.seed) + slice * 17, base_y, index * 2 + slice)
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = _ridge_shader
		# Fog stays off on purpose: at 430 m depth fog would erase the silhouette
		# into the sky. Aerial perspective is baked into the vertex colours.
		material.set_shader_parameter("tint", Color(_base_ridge_color(index * 2 + slice), _ridge_alpha(index * 2 + slice, 0.055)))
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "Ridge%d_%d" % [index, slice]
		node.mesh = mesh
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_ridges.append(node)
		_ridge_materials.append(material)


## Ridge card: a vertical curtain of RIDGE_ROWS rows following one skyline.
## Vertex shades darken toward the base so the silhouette reads as a solid mass
## instead of a flat paper cut-out.
func _ridge_mesh(center: Vector2, height: float, span: float, steepness: float,
		noise_amount: float, seed_value: int, base_y: float, colour_seed: int) -> ArrayMesh:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.004
	noise.fractal_octaves = 3
	var detail: FastNoiseLite = FastNoiseLite.new()
	detail.seed = seed_value + 101
	detail.frequency = 0.02
	detail.fractal_octaves = 2

	var columns: int = RIDGE_SEGMENTS + 1
	var profiles: PackedFloat32Array = PackedFloat32Array()
	profiles.resize(columns)
	for column: int in range(columns):
		var offset: float = float(column) / float(RIDGE_SEGMENTS) * 2.0 - 1.0
		# A bell pulls the mass up in the middle of the span; steepness keeps the
		# flanks high enough that the ridge reads as a range, not a single dome.
		var bell: float = exp(-pow(absf(offset) * 1.9, 2.0))
		var wave: float = (noise.get_noise_2d(float(column) * 3.0, 0.0) * 0.5 + 0.5) * noise_amount
		var jitter: float = detail.get_noise_2d(float(column) * 5.0, 0.0) * 0.05
		profiles[column] = clampf(bell * steepness * (0.72 + wave) + jitter, 0.04, 1.20)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = colour_seed + 911
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size: float = span
	for row: int in range(RIDGE_ROWS):
		var f0: float = float(row) / float(RIDGE_ROWS)
		var f1: float = float(row + 1) / float(RIDGE_ROWS)
		for column: int in range(RIDGE_SEGMENTS):
			var u0: float = float(column) / float(RIDGE_SEGMENTS) - 0.5
			var u1: float = float(column + 1) / float(RIDGE_SEGMENTS) - 0.5
			var x0: float = center.x + u0 * size
			var x1: float = center.x + u1 * size
			var z0: float = center.y
			var peak0: float = profiles[column] * height
			var peak1: float = profiles[column + 1] * height
			var p00: Vector3 = Vector3(x0, base_y, z0)
			var p10: Vector3 = Vector3(x1, base_y, z0)
			var p01: Vector3 = Vector3(x0, base_y + peak0, z0)
			var p11: Vector3 = Vector3(x1, base_y + peak1, z0)
			var a00: Vector3 = p00.lerp(p01, f0)
			var a10: Vector3 = p10.lerp(p11, f0)
			var a01: Vector3 = p00.lerp(p01, f1)
			var a11: Vector3 = p10.lerp(p11, f1)
			_quad(surface, a00, a10, a01, a11, f0, f1, rng)
	surface.generate_normals()
	return surface.commit()


func _quad(surface: SurfaceTool, a00: Vector3, a10: Vector3, a01: Vector3, a11: Vector3,
		depth0: float, depth1: float, rng: RandomNumberGenerator) -> void:
	var normal: Vector3 = Vector3(0, 0, 1)
	var points: Array[Vector3] = [a00, a10, a01, a10, a11, a01]
	var depths: Array[float] = [depth0, depth0, depth1, depth0, depth1, depth1]
	for i: int in range(points.size()):
		surface.set_normal(normal)
		# Base a touch darker than the crest, so a flat card still catches the eye.
		var shade: float = 0.70 + 0.30 * depths[i] + rng.randf_range(-0.015, 0.015)
		surface.set_color(Color(shade, shade, shade, 1.0))
		surface.add_vertex(points[i])


func _base_ridge_color(index: int) -> Color:
	# Slice 0 sits nearer the camera and stays darker; slice 1 is the far tier.
	# Both stay well below the sky brightness so they read as land, not cloud.
	if index % 2 == 1:
		return Color("55627a")
	return Color("3d4759")


func _ridge_alpha(index: int, haze_alpha: float) -> float:
	var base: float = 0.90 if index % 2 == 1 else 0.97
	return clampf(base + haze_alpha * 0.8, 0.0, 1.0)


# ---------------------------------------------------------------- river mist

## Low mist cards laid along the downstream half of the river. They hug the water
## so the valley floor fades into haze instead of ending on a hard bank.
func _build_mist() -> void:
	var texture: GradientTexture2D = GradientTexture2D.new()
	var gradient: Gradient = Gradient.new()
	# Radial falloff from a dense centre to transparent edges.
	gradient.set_color(0, Color(1, 1, 1, 1.0))
	gradient.set_color(1, Color(1, 1, 1, 0.0))
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.width = 128
	texture.height = 128
	_mist_bands.clear()
	for i: int in range(MIST_SEGMENTS):
		var t: float = float(i) / float(MIST_SEGMENTS - 1)
		# Down-valley reach of the river only: the village stays crisp.
		var river_t: float = lerpf(0.0, 0.42, t)
		var point: Vector2 = terrain.sample_river(river_t)
		var width: float = terrain.river_width_at(river_t)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.disable_receive_shadows = true
		material.albedo_texture = texture
		material.albedo_color = Color(Color("7089aa"), 0.10 * lerpf(0.45, 1.0, t))
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(width * 3.2, 3.6 + width * 0.35)
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "RiverMist%d" % i
		node.mesh = quad
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = Vector3(point.x, float(terrain.water_level) + 2.2, point.y)
		add_child(node)
		_mist_bands.append(node)
	sizes["river_mist"] = _mist_bands.size()
