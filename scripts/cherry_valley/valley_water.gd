extends Node3D
## (Claude Code) River surface: a ribbon mesh that follows the terrain spline,
## custom ripple shader, foam edge strips and a handful of koi.

const MESH_KIT: Script = preload("res://scripts/cherry_valley/valley_mesh_kit.gd")

var config: Dictionary
var water_material: ShaderMaterial
var surface: MeshInstance3D
var sizes: Dictionary = {}

var _terrain: Node3D
var _segments: int = 96
var _across: int = 14
var _surface_y: float = 0.02
var _koi: Array[Dictionary] = []
var _koi_root: Node3D
var _koi_mesh: ArrayMesh
var _koi_material: StandardMaterial3D
var _time: float = 0.0


func build(cfg: Dictionary, terrain: Node3D, shader: Shader) -> void:
	config = cfg
	_terrain = terrain
	var water: Dictionary = cfg.water
	_segments = int(water.segments)
	_across = int(water.across)
	_surface_y = float(water.surface_offset)
	water_material = ShaderMaterial.new()
	water_material.shader = shader
	water_material.set_shader_parameter("deep_color", Color(water.deep_color))
	water_material.set_shader_parameter("shallow_color", Color(water.shallow_color))
	water_material.set_shader_parameter("sky_color", Color(water.get("sky_color", "#8593ab")))
	water_material.set_shader_parameter("foam_color", Color(water.foam_color))
	water_material.set_shader_parameter("alpha_base", float(water.alpha))
	water_material.set_shader_parameter("wave_strength", float(water.wave_strength))
	water_material.set_shader_parameter("flow_speed", float(water.flow_speed))
	water_material.set_shader_parameter("rain_amount", 0.0)
	_build_surface()
	_build_koi()
	_build_river_blocker()


func set_mood(mood: Dictionary) -> void:
	if water_material == null:
		return
	water_material.set_shader_parameter("deep_color", Color(mood.water_deep))
	water_material.set_shader_parameter("shallow_color", Color(mood.water_shallow))
	water_material.set_shader_parameter("sky_color", Color(mood.get("water_sky", "#8593ab")))
	water_material.set_shader_parameter("alpha_base", float(mood.water_alpha))
	water_material.set_shader_parameter("rain_amount", 0.65 if bool(mood.rain) else 0.0)


## Water surface. The ribbon stops just past the carved shoreline and its outer
## columns drop into the bank, so the plane is always tucked under the terrain
## instead of floating over it with a visible straight edge.
func _build_surface() -> void:
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	for segment: int in range(_segments):
		var t0: float = float(segment) / float(_segments)
		var t1: float = float(segment + 1) / float(_segments)
		var center0: Vector2 = _terrain.sample_river(t0)
		var center1: Vector2 = _terrain.sample_river(t1)
		var width0: float = _terrain.river_width_at(t0) * 0.5 * 1.10
		var width1: float = _terrain.river_width_at(t1) * 0.5 * 1.10
		var normal0: Vector2 = _river_normal(t0)
		var normal1: Vector2 = _river_normal(t1)
		for across: int in range(_across):
			var a0: float = float(across) / float(_across)
			var a1: float = float(across + 1) / float(_across)
			var l0: float = lerpf(-width0, width0, a0)
			var l1: float = lerpf(-width0, width0, a1)
			var m0: float = lerpf(-width1, width1, a0)
			var m1: float = lerpf(-width1, width1, a1)
			var y0: float = _surface_y - _edge_drop(a0)
			var y1: float = _surface_y - _edge_drop(a1)
			var p00: Vector3 = Vector3(center0.x + normal0.x * l0, y0, center0.y + normal0.y * l0)
			var p01: Vector3 = Vector3(center0.x + normal0.x * l1, y1, center0.y + normal0.y * l1)
			var p10: Vector3 = Vector3(center1.x + normal1.x * m0, y0, center1.y + normal1.y * m0)
			var p11: Vector3 = Vector3(center1.x + normal1.x * m1, y1, center1.y + normal1.y * m1)
			# COLOR.r is the channel depth factor the shader reads: 0 at the
			# shoreline, 1 in the middle of the river.
			var c0: Color = Color(_channel_factor(a0), 0.0, 0.0, 1.0)
			var c1: Color = Color(_channel_factor(a1), 0.0, 0.0, 1.0)
			acc.tri(p00, p01, p10, c0, Vector3.UP)
			acc.tri(p01, p11, p10, c1, Vector3.UP)
	surface = MESH_KIT.instance(acc, water_material, "RiverSurface")
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	sizes["water_triangles"] = int(acc.vertices.size() / 3)


## How far the outer water columns are pushed below the surface. Only the two edge
## columns move, so the middle stays flat and the edges hide inside the bank.
func _edge_drop(across: float) -> float:
	return (smoothstep(0.16, 0.0, across) + smoothstep(0.84, 1.0, across)) * 0.55


## 0 at the shoreline, 1 mid-channel. Mirrors the parabolic bed the terrain carves,
## so the water's colour gradient follows the actual river cross-section.
func _channel_factor(across: float) -> float:
	var u: float = clampf(absf(across * 2.0 - 1.0) / 0.94, 0.0, 1.0)
	return clampf(1.0 - u * u, 0.0, 1.0)


func _river_normal(t: float) -> Vector2:
	var delta: float = 0.002
	var a: Vector2 = _terrain.sample_river(maxf(t - delta, 0.0))
	var b: Vector2 = _terrain.sample_river(minf(t + delta, 1.0))
	var tangent: Vector2 = (b - a)
	if tangent.length_squared() < 0.0001:
		return Vector2(1, 0)
	tangent = tangent.normalized()
	return Vector2(-tangent.y, tangent.x)


func _build_koi() -> void:
	_koi_root = Node3D.new()
	_koi_root.name = "Koi"
	add_child(_koi_root)
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	acc.blob(Vector3.ZERO, Vector3(0.12, 0.075, 0.32), Color("e8b25c"), 4, 7, 0.05, 3)
	acc.blob(Vector3(0.0, 0.01, 0.30), Vector3(0.09, 0.02, 0.14), Color("f2d7a4"), 3, 6, 0.04, 5)
	acc.blob(Vector3(0.0, 0.0, -0.30), Vector3(0.10, 0.04, 0.12), Color("d98a4f"), 3, 6, 0.06, 7)
	_koi_mesh = acc.to_mesh()
	_koi_material = StandardMaterial3D.new()
	_koi_material.vertex_color_use_as_albedo = true
	_koi_material.roughness = 0.5
	_koi_material.metallic = 0.1
	var count: int = int(config.flora.koi.count)
	for index: int in range(count):
		var koi: MeshInstance3D = MeshInstance3D.new()
		koi.mesh = _koi_mesh
		koi.material_override = _koi_material
		koi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_koi_root.add_child(koi)
		_koi.append({
			"node": koi,
			"t": float(index) / float(maxi(count, 1)),
			"lateral": (float(index % 3) - 1.0) * 1.8,
			"speed": 0.012 + 0.004 * float(index % 4),
			"tail_phase": randf() * TAU,
		})


## Invisible collision along the waterline so the player crosses on the bridge
## instead of walking on the river bed. It only covers the water (the old boxes
## were 26 m wide and reached 4.5 m up the banks) and it is cut open where the
## bridge crosses, otherwise the deck itself sat inside the wall.
func _build_river_blocker() -> void:
	var blocker: StaticBody3D = StaticBody3D.new()
	blocker.name = "RiverBankBlocker"
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	add_child(blocker)
	var bridge: Dictionary = config.village.bridge
	var bridge_center: Vector2 = Vector2(float(bridge.center[0]), float(bridge.center[1]))
	var axis: Vector2 = _terrain.crossing_axis(bridge_center)
	# Clear the whole deck plus one box length. A plain radius test left a box
	# sitting right on the east head, which is what stopped the player there.
	var clear: float = _terrain.bridge_span(bridge_center, bridge) * 0.5 + 2.6
	var segments: int = 56
	for segment: int in range(segments):
		var t0: float = float(segment) / float(segments)
		var t1: float = float(segment + 1) / float(segments)
		var a: Vector2 = _terrain.sample_river(t0)
		var b: Vector2 = _terrain.sample_river(t1)
		var half_width: float = _terrain.river_width_at((t0 + t1) * 0.5) * 0.5 * 0.96
		var mid: Vector2 = (a + b) * 0.5
		var offset: Vector2 = mid - bridge_center
		var along: float = offset.x * axis.x + offset.y * axis.y
		if absf(along) < clear:
			continue
		var tangent: Vector2 = b - a
		var yaw: float = atan2(-tangent.y, tangent.x)
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		# Rotated so the long axis runs along the flow, the short axis spans the water.
		box.size = Vector3(maxf(tangent.length() * 1.15, 1.0), 1.9, half_width * 2.0)
		shape.shape = box
		shape.position = Vector3(mid.x, 0.05, mid.y)
		shape.rotation.y = yaw
		blocker.add_child(shape)
	sizes["blocker_segments"] = blocker.get_child_count()


func _process(delta: float) -> void:
	_time += delta
	for entry: Dictionary in _koi:
		var t: float = fposmod(float(entry.t) + delta * float(entry.speed), 1.0)
		entry.t = t
		var center: Vector2 = _terrain.sample_river(t)
		var normal: Vector2 = _river_normal(t)
		var lateral: float = float(entry.lateral)
		var position: Vector3 = Vector3(center.x + normal.x * lateral, -0.42, center.y + normal.y * lateral)
		var node: MeshInstance3D = entry.node
		node.position = position
		var ahead: Vector2 = _terrain.sample_river(minf(t + 0.012, 1.0))
		var direction: Vector3 = Vector3(ahead.x - center.x, 0.0, ahead.y - center.y)
		if direction.length_squared() > 0.0001:
			node.rotation.y = atan2(-direction.z, direction.x) + PI * 0.5
		node.position.y += sin(_time * 2.2 + float(entry.tail_phase)) * 0.035
