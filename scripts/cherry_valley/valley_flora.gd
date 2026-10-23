extends Node3D
## (Claude Code) Cherry trees, blossom MultiMesh, grass/flower/rock scatter,
## falling petals and fireflies. Everything repeated is instanced in one draw call.
## `buffer` is used when the renderer has allocated it (real game); headless falls
## back to per-instance transforms so tests still build the same counts.

const MESH_KIT: Script = preload("res://scripts/cherry_valley/valley_mesh_kit.gd")

var config: Dictionary
var terrain: Node3D
var materials: Dictionary
var sizes: Dictionary = {}

var _blossoms: MultiMeshInstance3D
var _grass: MultiMeshInstance3D
var _flowers: MultiMeshInstance3D
var _rocks: MultiMeshInstance3D
var _petals: CPUParticles3D
var _fireflies: CPUParticles3D
var _petal_material: StandardMaterial3D
var _petal_mesh: ArrayMesh
var _blossom_mesh: ArrayMesh
var _rng: RandomNumberGenerator


func build(cfg: Dictionary, terrain_node: Node3D, kit_materials: Dictionary) -> void:
	config = cfg
	terrain = terrain_node
	materials = kit_materials
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(cfg.flora.cherry_trees.seed)
	# Shared blossom clump: instance colours tint it per cluster.
	var blossom_acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	blossom_acc.blob(Vector3.ZERO, Vector3(0.62, 0.46, 0.62), Color.WHITE, 3, 7, 0.12, 11)
	_blossom_mesh = blossom_acc.to_mesh()
	_build_cherry_trees()
	_build_deep_trees()
	_build_ground_cover()
	_build_rocks()
	_build_petals()
	_build_fireflies()


func set_mood(mood: Dictionary) -> void:
	if _petals != null:
		_petals.color = Color(mood.petal_color)
		_petals.amount = int(config.quality.high.petal_amount) if not bool(mood.rain) else int(config.quality.high.petal_amount) * 2
		_petals.emitting = true
	if _fireflies != null:
		_fireflies.emitting = not bool(mood.rain)


func apply_quality(settings: Dictionary) -> void:
	if _grass != null:
		_grass.visibility_range_end = float(settings.grass_distance)
	if _blossoms != null:
		_blossoms.visibility_range_end = float(settings.tree_distance)
	if _petals != null:
		_petals.amount = int(settings.petal_amount)
	if _fireflies != null:
		_fireflies.amount = int(settings.firefly_amount)


# ---------------------------------------------------------------- cherry trees

func _build_cherry_trees() -> void:
	var blossom_transforms: Array[Transform3D] = []
	var blossom_colors: Array[Color] = []
	var hero: Dictionary = config.flora.hero_tree
	var hero_center: Vector2 = Vector2(float(hero.center[0]), float(hero.center[1]))
	_add_cherry_tree(hero_center, float(hero.scale), int(hero.seed), 4, 3, blossom_transforms, blossom_colors)
	var specs: Dictionary = config.flora.cherry_trees
	var placed: Array[Vector2] = [hero_center]
	var target: int = int(specs.count)
	var attempts: int = 0
	while placed.size() < target and attempts < target * 24:
		attempts += 1
		var x: float = _rng.randf_range(float(specs.x_range[0]), float(specs.x_range[1]))
		var z: float = _rng.randf_range(float(specs.z_range[0]), float(specs.z_range[1]))
		var point: Vector2 = Vector2(x, z)
		if not _valid_tree_site(point, float(specs.min_distance), placed):
			continue
		placed.append(point)
		var scale: float = _rng.randf_range(0.72, 1.15)
		_add_cherry_tree(point, scale, _rng.randi(), 3, 2, blossom_transforms, blossom_colors)
	_build_multimesh(_blossom_mesh, blossom_transforms, blossom_colors,
		"Blossoms", materials.blossom, float(config.quality.high.tree_distance), false)
	sizes["cherry_trees"] = placed.size()
	sizes["blossom_instances"] = blossom_transforms.size()


func _valid_tree_site(point: Vector2, min_distance: float, placed: Array[Vector2]) -> bool:
	if terrain.is_water(point.x, point.y):
		return false
	var river_distance: float = terrain.river_center_distance(point)
	if river_distance < terrain.river_width_at(terrain.nearest_river_t(point)) * 0.5 + 4.0:
		return false
	var height: float = terrain.height_at(point.x, point.y)
	if height < 0.6:
		return false
	# Keep the paths and village clear.
	if _distance_to_paths(point) < 2.6:
		return false
	if point.distance_to(Vector2(31.0, 32.0)) < 14.0:
		return false
	if point.distance_to(Vector2(-45.0, -18.0)) < 11.0:
		return false
	for other: Vector2 in placed:
		if point.distance_to(other) < min_distance:
			return false
	return true


func _distance_to_paths(point: Vector2) -> float:
	var best: float = 1e9
	for path: Dictionary in config.terrain.paths:
		var points: PackedVector2Array = PackedVector2Array()
		for p: Array in path.points:
			points.append(Vector2(float(p[0]), float(p[1])))
		var nearest: Dictionary = terrain.nearest_on_polyline(points, point)
		best = minf(best, float(nearest.distance))
	return best


func _add_cherry_tree(center: Vector2, scale: float, seed_value: int, depth: int, children: int, blossom_transforms: Array[Transform3D], blossom_colors: Array[Color]) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var ground: Vector3 = terrain.ground(center.x, center.y)
	var root: Node3D = Node3D.new()
	root.name = "CherryTree_%d_%d" % [int(center.x), int(center.y)]
	root.position = ground
	add_child(root)
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	var bark: Color = Color("#5b4238")
	var tips: Array[Vector3] = []
	# Root flare, then a leaning trunk that splits into branches.
	acc.blob(Vector3(0, 0.12, 0), Vector3(0.45, 0.22, 0.45) * scale, bark.darkened(0.08), 3, 7, 0.06, seed_value)
	var trunk_dir: Vector3 = Vector3(rng.randf_range(-0.16, 0.16), 1.0, rng.randf_range(-0.16, 0.16)).normalized()
	var trunk_start: Vector3 = Vector3(0, 0.15, 0)
	var trunk_length: float = 2.6 * scale
	# 根须：几条向外倾斜的短圆柱，让树"抓住"地面而不是插在土里。
	var root_count: int = 5
	for root_index: int in range(root_count):
		var root_angle: float = TAU * float(root_index) / float(root_count) + rng.randf_range(-0.3, 0.3)
		var root_dir: Vector3 = Vector3(cos(root_angle), -0.26, sin(root_angle)).normalized()
		var root_len: float = rng.randf_range(0.55, 0.95) * scale
		var root_base: Vector3 = Vector3(0, 0.16, 0)
		acc.cylinder(root_base, root_base + root_dir * root_len, 0.13 * scale, 0.035 * scale, 5, bark.darkened(0.06))
	# 树干：分四段逐段偏转，形成自然弯曲而不是一根直筒。
	var seg_count: int = 4
	var seg_len: float = trunk_length / float(seg_count)
	var cursor: Vector3 = trunk_start
	var seg_dir: Vector3 = trunk_dir
	var seg_radius: float = 0.30 * scale
	for seg: int in range(seg_count):
		var bend: Vector3 = Vector3(rng.randf_range(-0.13, 0.13), 0.05, rng.randf_range(-0.13, 0.13))
		var next_dir: Vector3 = (seg_dir + bend).normalized()
		var next_point: Vector3 = cursor + next_dir * seg_len
		var next_radius: float = seg_radius * 0.82
		acc.cylinder(cursor, next_point, seg_radius, next_radius, 7, bark.lightened(0.02 * float(seg)))
		cursor = next_point
		seg_dir = next_dir
		seg_radius = next_radius
	var trunk_tip: Vector3 = cursor
	var branches: int = children + 1
	for branch: int in range(branches):
		var angle: float = TAU * float(branch) / float(branches) + rng.randf_range(-0.35, 0.35)
		var tilt: float = rng.randf_range(0.45, 0.85)
		var direction: Vector3 = Vector3(cos(angle) * tilt, 1.0, sin(angle) * tilt).normalized()
		_grow_branch(acc, trunk_tip, direction, trunk_length * 0.72, 0.16 * scale, depth, rng, tips, bark)
	root.add_child(MESH_KIT.instance(acc, materials.branch, "TreeBranches"))
	# Blossom clusters at branch tips, plus a sparse halo around the crown.
	for tip: Vector3 in tips:
		var clusters: int = rng.randi_range(2, 3)
		for cluster: int in range(clusters):
			var offset: Vector3 = Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.45, 0.75), rng.randf_range(-0.9, 0.9)) * scale
			var position: Vector3 = ground + tip + offset
			var size: float = rng.randf_range(0.55, 1.15) * scale
			var pink: Color = Color("#ffb7cf").lerp(Color("#ffd9e6"), rng.randf())
			# 每个花簇由主球和两颗卫星球组成：单个球看起来像塑料球，
			# 拆成大小不一的三颗后轮廓才有厚薄、间隙和枝条透出的感觉。
			for lobe: int in range(3):
				var lobe_scale: float = 1.0 if lobe == 0 else rng.randf_range(0.40, 0.62)
				var lobe_offset: Vector3 = Vector3.ZERO
				if lobe > 0:
					lobe_offset = Vector3(rng.randf_range(-0.44, 0.44), rng.randf_range(-0.24, 0.32), rng.randf_range(-0.44, 0.44)) * scale
				var lobe_size: float = size * lobe_scale
				var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(lobe_size, lobe_size * rng.randf_range(0.66, 1.0), lobe_size))
				blossom_transforms.append(Transform3D(basis, position + lobe_offset))
				var lobe_color: Color = pink if lobe == 0 else pink.lerp(Color("#ffe8f0"), rng.randf_range(0.05, 0.40))
				blossom_colors.append(lobe_color)


func _grow_branch(acc: MESH_KIT.Accumulator, base: Vector3, direction: Vector3, length: float, radius: float, depth: int, rng: RandomNumberGenerator, tips: Array[Vector3], bark: Color) -> void:
	var tip: Vector3 = base + direction * length
	acc.cylinder(base, tip, radius, radius * 0.62, 5, bark.lightened(0.04 * float(depth)))
	if depth <= 0:
		tips.append(tip)
		return
	var count: int = 2 if depth < 2 else 3
	for child: int in range(count):
		var angle: float = TAU * float(child) / float(count) + rng.randf_range(-0.5, 0.5)
		var axis: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var side: Vector3 = direction.cross(axis).normalized()
		var tilt: float = rng.randf_range(0.35, 0.75)
		var child_dir: Vector3 = (direction + side * cos(angle) * tilt + axis.cross(side) * sin(angle) * tilt).normalized()
		_grow_branch(acc, tip, child_dir, length * rng.randf_range(0.58, 0.74), radius * 0.64, depth - 1, rng, tips, bark)


# ---------------------------------------------------------------- deep forest

func _build_deep_trees() -> void:
	var specs: Dictionary = config.flora.deep_trees
	var clump: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	# 原来树冠和树干都是球，远看像两颗绿球。改成树干加三层锥形冠，才有针叶树轮廓。
	clump.cylinder(Vector3(0, 0.0, 0), Vector3(0, 3.4, 0), 0.44, 0.26, 6, Color("#5a4a3b"))
	for tier: int in range(3):
		var base_y: float = 2.1 + float(tier) * 1.30
		var radius: float = 2.15 - float(tier) * 0.52
		clump.cylinder(
			Vector3(0, base_y, 0),
			Vector3(0, base_y + 2.05, 0),
			radius,
			0.16,
			7,
			Color("#4e6b57").lightened(0.06 * float(tier)))
	var mesh: ArrayMesh = clump.to_mesh()
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var placed: Array[Vector2] = []
	var target: int = int(specs.count)
	var attempts: int = 0
	while placed.size() < target and attempts < target * 20:
		attempts += 1
		var point: Vector2 = Vector2(
			_rng.randf_range(float(specs.x_range[0]), float(specs.x_range[1])),
			_rng.randf_range(float(specs.z_range[0]), float(specs.z_range[1]))
		)
		if terrain.is_water(point.x, point.y):
			continue
		var slope: float = absf(terrain.height_at(point.x + 1.0, point.y) - terrain.height_at(point.x - 1.0, point.y))
		slope += absf(terrain.height_at(point.x, point.y + 1.0) - terrain.height_at(point.x, point.y - 1.0))
		if slope < float(specs.slope_min):
			continue
		var too_close: bool = false
		for other: Vector2 in placed:
			if point.distance_to(other) < float(specs.min_distance):
				too_close = true
				break
		if too_close:
			continue
		placed.append(point)
		var scale: float = _rng.randf_range(0.75, 1.35)
		var basis: Basis = Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(scale, scale * _rng.randf_range(0.8, 1.25), scale))
		transforms.append(Transform3D(basis, terrain.ground(point.x, point.y)))
		colors.append(Color("#4e6b57").lerp(Color("#33513f"), _rng.randf()))
	_build_multimesh(mesh, transforms, colors, "DeepForest", materials.pine,
		float(config.quality.high.tree_distance) * 1.2, true)
	sizes["deep_trees"] = transforms.size()


# ---------------------------------------------------------------- grass / flowers / rocks

func _build_ground_cover() -> void:
	# A grass tuft: three crossed pairs of short, wide blades. The old blades were
	# 0.75 m tall and 7 cm wide, which is what read as thin spikes from eye level.
	var grass_acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	var root_color: Color = Color("#46613a")
	var tip_color: Color = Color("#8fae63")
	for plane: int in range(3):
		var angle: float = PI * float(plane) / 3.0
		var dir: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * 0.13
		var side: Vector3 = Vector3(-sin(angle), 0.0, cos(angle)) * 0.048
		for blade: int in range(2):
			var offset: Vector3 = Vector3(cos(angle + PI * 0.5), 0, sin(angle + PI * 0.5)) * (float(blade) - 0.5) * 0.15
			var base: Vector3 = offset
			var tip: Vector3 = offset + dir + Vector3(0, 0.34, 0)
			grass_acc.tri(base - side, base + side, tip, root_color, Vector3.UP)
			grass_acc.tri(tip, base + side, base - side, tip_color, Vector3.UP)
	var grass_mesh: ArrayMesh = grass_acc.to_mesh()
	var grass_transforms: Array[Transform3D] = []
	var grass_colors: Array[Color] = []
	var specs: Dictionary = config.flora.grass
	var radius: float = float(specs.radius)
	# Clumps instead of a uniform sprinkle: a low-frequency mask decides where the
	# meadow is dense, and each accepted spot gets a small group of tufts.
	var clump_count: int = maxi(int(float(specs.count) / 2.6), 1)
	for index: int in range(clump_count):
		var center: Vector2 = _scatter_point(radius, specs.seed, index)
		if terrain.is_water(center.x, center.y):
			continue
		if _distance_to_paths(center) < 1.3:
			continue
		if _clump_mask(center) < 0.44:
			continue
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = int(specs.seed) * 977 + index
		var members: int = rng.randi_range(2, 4)
		for member: int in range(members):
			var point: Vector2 = center + Vector2(rng.randf_range(-0.75, 0.75), rng.randf_range(-0.75, 0.75))
			if terrain.is_water(point.x, point.y) or _distance_to_paths(point) < 1.0:
				continue
			var scale: float = rng.randf_range(0.75, 1.2)
			var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale, scale * rng.randf_range(0.8, 1.25), scale))
			grass_transforms.append(Transform3D(basis, terrain.ground(point.x, point.y)))
			grass_colors.append(Color("#7c9c60").lerp(Color("#a3bf7c"), rng.randf()))
	_build_multimesh(grass_mesh, grass_transforms, grass_colors, "Grass", materials.grass,
		float(config.quality.high.grass_distance), false)
	sizes["grass_instances"] = grass_transforms.size()

	# Small clustered blossoms: a single 10 cm ball per instance read as repeated
	# pink dots, so the flower head is now tiny and always comes in groups.
	var flower_acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	flower_acc.blob(Vector3(0, 0.12, 0), Vector3(0.055, 0.05, 0.055), Color("#f4d3dd"), 3, 5, 0.05, 2)
	flower_acc.cylinder(Vector3(0, 0, 0), Vector3(0, 0.11, 0), 0.012, 0.010, 4, Color("#5f7d52"))
	var flower_mesh: ArrayMesh = flower_acc.to_mesh()
	var flower_transforms: Array[Transform3D] = []
	var flower_colors: Array[Color] = []
	var flower_specs: Dictionary = config.flora.flowers
	var flower_clumps: int = maxi(int(float(flower_specs.count) / 4.0), 1)
	for index: int in range(flower_clumps):
		var center: Vector2 = _scatter_point(float(flower_specs.radius), int(flower_specs.seed), index)
		if terrain.is_water(center.x, center.y) or _distance_to_paths(center) < 1.1:
			continue
		if _clump_mask(center + Vector2(37.0, 11.0)) < 0.52:
			continue
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = int(flower_specs.seed) * 613 + index
		var members: int = rng.randi_range(2, 4)
		for member: int in range(members):
			var point: Vector2 = center + Vector2(rng.randf_range(-0.55, 0.55), rng.randf_range(-0.55, 0.55))
			if terrain.is_water(point.x, point.y) or _distance_to_paths(point) < 0.9:
				continue
			var scale: float = rng.randf_range(0.85, 1.4)
			var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale, scale, scale))
			flower_transforms.append(Transform3D(basis, terrain.ground(point.x, point.y)))
			flower_colors.append(Color("#f4d3dd").lerp(Color("#ffe9c9"), rng.randf()))
	_build_multimesh(flower_mesh, flower_transforms, flower_colors, "Flowers", materials.blossom,
		float(config.quality.high.grass_distance), false)
	sizes["flower_instances"] = flower_transforms.size()


## Low-frequency mask that decides where ground cover grows. Keeps large open
## patches so the meadow reads as regions instead of an even carpet.
func _clump_mask(point: Vector2) -> float:
	return terrain._noise.get_noise_2d(point.x * 0.19, point.y * 0.19) * 0.5 + 0.5


func _build_rocks() -> void:
	var rock_acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	rock_acc.blob(Vector3.ZERO, Vector3(0.7, 0.55, 0.6), Color("#8d918a"), 4, 6, 0.18, 5)
	var mesh: ArrayMesh = rock_acc.to_mesh()
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var specs: Dictionary = config.flora.rocks
	for index: int in range(int(specs.count)):
		var point: Vector2 = _scatter_point(float(specs.radius), int(specs.seed), index)
		if terrain.is_water(point.x, point.y):
			continue
		var scale: float = _rng.randf_range(0.35, 1.5)
		var basis: Basis = Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
			Vector3(scale * _rng.randf_range(0.7, 1.4), scale * _rng.randf_range(0.45, 0.9), scale)
		)
		var position: Vector3 = terrain.ground(point.x, point.y)
		position.y -= 0.12 * scale
		transforms.append(Transform3D(basis, position))
		colors.append(Color("#8d918a").lerp(Color("#a9aca2"), _rng.randf()))
	_build_multimesh(mesh, transforms, colors, "Rocks", materials.rock,
		float(config.quality.high.tree_distance), true)
	sizes["rock_instances"] = transforms.size()


func _scatter_point(radius: float, seed_value: int, index: int) -> Vector2:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + index
	var angle: float = rng.randf_range(0.0, TAU)
	var distance: float = sqrt(rng.randf()) * radius
	return Vector2(cos(angle) * distance, sin(angle) * distance) + Vector2(0.0, 20.0)


# ---------------------------------------------------------------- petals & fireflies

func _build_petals() -> void:
	_petal_mesh = _petal_shape()
	_petal_material = StandardMaterial3D.new()
	_petal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_petal_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_petal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_petal_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_petal_material.vertex_color_use_as_albedo = true
	_petal_material.albedo_color = Color.WHITE
	_petals = CPUParticles3D.new()
	_petals.name = "FallingPetals"
	var specs: Dictionary = config.flora.petals
	_petals.amount = int(specs.amount)
	_petals.lifetime = 11.0
	_petals.preprocess = 4.0
	_petals.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_petals.emission_sphere_radius = float(specs.radius)
	_petals.direction = Vector3(0.25, -1.0, 0.15)
	_petals.spread = 38.0
	_petals.gravity = Vector3(0.42, -0.55, 0.25)
	_petals.initial_velocity_min = 0.35
	_petals.initial_velocity_max = 1.1
	_petals.angular_velocity_min = -90.0
	_petals.angular_velocity_max = 90.0
	_petals.angle_min = 0.0
	_petals.angle_max = 360.0
	_petals.scale_amount_min = 0.75
	_petals.scale_amount_max = 1.4
	_petals.color = Color(config.moods.blue_hour.petal_color)
	_petals.mesh = _petal_mesh
	_petals.material_override = _petal_material
	_petals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_petals.position = Vector3(2.0, 8.0, 52.0)
	_petals.local_coords = false
	add_child(_petals)


func _petal_shape() -> ArrayMesh:
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	var pink: Color = Color("#ffd6e2")
	# Two crossed petals so the quad reads as a blossom fragment from any angle.
	acc.tri(Vector3(-0.09, 0.0, 0.0), Vector3(0.0, 0.07, 0.0), Vector3(0.09, 0.0, 0.0), pink, Vector3.UP)
	acc.tri(Vector3(-0.09, 0.0, 0.0), Vector3(0.0, -0.05, 0.0), Vector3(0.09, 0.0, 0.0), pink.darkened(0.08), Vector3.DOWN)
	acc.tri(Vector3(0.0, 0.0, -0.09), Vector3(0.0, 0.07, 0.0), Vector3(0.0, 0.0, 0.09), pink, Vector3.UP)
	return acc.to_mesh()


func _build_fireflies() -> void:
	var specs: Dictionary = config.flora.fireflies
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color("#ffe6a8")
	material.albedo_texture = _halo_texture()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	_fireflies = CPUParticles3D.new()
	_fireflies.name = "Fireflies"
	_fireflies.amount = int(specs.amount)
	_fireflies.lifetime = 7.0
	_fireflies.preprocess = 3.0
	_fireflies.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_fireflies.emission_sphere_radius = float(specs.radius)
	_fireflies.direction = Vector3(0, 0.35, 0)
	_fireflies.spread = 70.0
	_fireflies.gravity = Vector3(0.12, 0.03, 0.08)
	_fireflies.initial_velocity_min = 0.10
	_fireflies.initial_velocity_max = 0.45
	_fireflies.scale_amount_min = 0.5
	_fireflies.scale_amount_max = 1.3
	_fireflies.color = Color("#ffe6a8")
	_fireflies.mesh = quad
	_fireflies.material_override = material
	_fireflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fireflies.position = Vector3(0.0, 3.0, 30.0)
	_fireflies.local_coords = false
	add_child(_fireflies)


static var _halo_cache: GradientTexture2D

func _halo_texture() -> GradientTexture2D:
	if _halo_cache != null:
		return _halo_cache
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	_halo_cache = texture
	return texture


# ---------------------------------------------------------------- multimesh helper

func _build_multimesh(mesh: ArrayMesh, transforms: Array[Transform3D], colors: Array[Color], node_name: String, material: Material, distance: float, shadows: bool) -> void:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	var expected: int = transforms.size() * 16
	if mm.buffer.size() == expected and expected > 0:
		# Fast path (real renderer): one upload for all instances.
		var buffer: PackedFloat32Array = PackedFloat32Array()
		buffer.resize(expected)
		var cursor: int = 0
		for index: int in range(transforms.size()):
			var transform: Transform3D = transforms[index]
			var basis: Basis = transform.basis
			var origin: Vector3 = transform.origin
			buffer[cursor] = basis.x.x
			buffer[cursor + 1] = basis.x.y
			buffer[cursor + 2] = basis.x.z
			buffer[cursor + 3] = origin.x
			buffer[cursor + 4] = basis.y.x
			buffer[cursor + 5] = basis.y.y
			buffer[cursor + 6] = basis.y.z
			buffer[cursor + 7] = origin.y
			buffer[cursor + 8] = basis.z.x
			buffer[cursor + 9] = basis.z.y
			buffer[cursor + 10] = basis.z.z
			buffer[cursor + 11] = origin.z
			var color: Color = colors[index]
			buffer[cursor + 12] = color.r
			buffer[cursor + 13] = color.g
			buffer[cursor + 14] = color.b
			buffer[cursor + 15] = color.a
			cursor += 16
		mm.buffer = buffer
	else:
		# Headless / dummy renderer: no buffer is allocated, so write per instance.
		for index: int in range(transforms.size()):
			mm.set_instance_transform(index, transforms[index])
			mm.set_instance_color(index, colors[index])
	if transforms.size() > 0:
		var bounds: AABB = AABB(transforms[0].origin, Vector3.ZERO)
		for transform: Transform3D in transforms:
			bounds = bounds.expand(transform.origin)
		bounds = bounds.grow(6.0)
		mm.custom_aabb = bounds
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = mm
	instance.material_override = material
	instance.visibility_range_end = distance
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	match node_name:
		"Blossoms": _blossoms = instance
		"Grass": _grass = instance
		"Flowers": _flowers = instance
		"Rocks": _rocks = instance
