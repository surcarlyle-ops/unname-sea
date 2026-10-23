extends RefCounted
## (Claude Code) Shared procedural mesh/material kit for the cherry valley scene.
## Every builder in scripts/cherry_valley/ appends vertices through one Accumulator
## so a whole building or tree ends up as a single ArrayMesh surface.

## Colour ramp helper: jitter a base colour without leaving the palette.
static func tint(base: Color, amount: float, seed_value: int) -> Color:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var delta: float = rng.randf_range(-amount, amount)
	return Color(
		clampf(base.r + delta, 0.0, 1.0),
		clampf(base.g + delta * 0.85, 0.0, 1.0),
		clampf(base.b + delta * 0.7, 0.0, 1.0),
		base.a
	)


## Smooth stylized material used by most of the valley. Vertex colour supplies the
## per-vertex tint; the shader adds soft light bands and a rim light.
## 新增细节参数都有默认值，老调用点不用改；需要区分质感的地方再单独传。
static func toon_material(shader: Shader, tint_color: Color, rim: float = 0.35, grain_scale: float = 3.0, grain_strength: float = 0.18, base_roughness: float = 0.86, edge_darken: float = 0.14, wetness: float = 0.0, grain_stretch: Vector3 = Vector3.ONE) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint", tint_color)
	material.set_shader_parameter("rim_strength", rim)
	material.set_shader_parameter("grain_scale", grain_scale)
	material.set_shader_parameter("grain_strength", grain_strength)
	material.set_shader_parameter("base_roughness", base_roughness)
	material.set_shader_parameter("edge_darken", edge_darken)
	material.set_shader_parameter("wetness", wetness)
	material.set_shader_parameter("grain_stretch", grain_stretch)
	return material


## 按材质类别给出预设，避免每个调用点都手写一堆参数。
## kind: stone / wood / tile / petal / grass / water_edge / plaster / bark
static func toon_material_for(shader: Shader, kind: String, tint_color: Color, rim: float = 0.35) -> ShaderMaterial:
	match kind:
		"stone":
			# 石头：细密噪声、偏粗糙、边缘压得重一点。
			return toon_material(shader, tint_color, rim, 13.0, 0.55, 0.92, 0.24, 0.0, Vector3.ONE)
		"wood":
			# 木头：沿 Y 轴拉伸的纹理，粗糙度中等。
			return toon_material(shader, tint_color, rim, 16.0, 0.42, 0.78, 0.18, 0.0, Vector3(1.0, 0.22, 1.0))
		"bark":
			# 树皮：更粗糙、更强对比。
			return toon_material(shader, tint_color, rim, 20.0, 0.58, 0.94, 0.26, 0.0, Vector3(1.0, 0.35, 1.0))
		"tile":
			# 瓦片：细颗粒、略光滑，有高光层次。
			return toon_material(shader, tint_color, rim, 22.0, 0.38, 0.62, 0.20, 0.0, Vector3.ONE)
		"plaster":
			# 墙面：几乎无纹理，只留轻微不均。
			return toon_material(shader, tint_color, rim, 5.0, 0.16, 0.90, 0.10, 0.0, Vector3.ONE)
		"petal":
			# 花瓣：平滑、微透，边缘光强一点。
			return toon_material(shader, tint_color, rim, 6.0, 0.22, 0.52, 0.12, 0.0, Vector3.ONE)
		"grass":
			# 草地：中频斑驳，太弱会退回纯色。
			return toon_material(shader, tint_color, rim, 5.5, 0.78, 0.95, 0.16, 0.0, Vector3.ONE)
		"ground":
			# 大面积地面：噪声尺度放到米级，只留缓慢的明暗，不再做砂纸颗粒。
			# 细节由顶点色的草地/泥土/岩石分区承担。
			return toon_material(shader, tint_color, rim, 0.42, 0.16, 0.96, 0.05, 0.0, Vector3.ONE)
		"water_edge":
			# 岸边湿石：低粗糙 + 湿润高光。
			return toon_material(shader, tint_color, rim, 14.0, 0.50, 0.55, 0.20, 0.65, Vector3.ONE)
		_:
			return toon_material(shader, tint_color, rim)


## Plain lit material for cases where the toon shader is overkill (collision only
## props, tiny details seen from far away).
static func simple_material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material


## Self-lit material for lantern paper, windows, glow accents.
static func emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.35)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.roughness = 0.6
	return material


## Accumulator: build one mesh surface from many primitives in any colour.
class Accumulator:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()

	## Add a quad (two triangles) facing the given normal.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, normal: Vector3) -> void:
		_triangle(a, b, c, color, normal)
		_triangle(a, c, d, color, normal)

	## Add a triangle with a shared per-face normal.
	func tri(a: Vector3, b: Vector3, c: Vector3, color: Color, normal: Vector3) -> void:
		_triangle(a, b, c, color, normal)

	func _triangle(a: Vector3, b: Vector3, c: Vector3, color: Color, normal: Vector3) -> void:
		vertices.append(a)
		vertices.append(b)
		vertices.append(c)
		for i: int in range(3):
			normals.append(normal)
			colors.append(color)

	## Axis-aligned-ish box from a centre and size, with optional yaw rotation
	## around the centre. Each face gets the same tint, slightly shaded per side.
	func box(center: Vector3, size: Vector3, color: Color, yaw: float = 0.0) -> void:
		var half: Vector3 = size * 0.5
		var basis: Basis = Basis(Vector3.UP, yaw)
		var corners: Array[Vector3] = []
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					corners.append(center + basis * Vector3(sx * half.x, sy * half.y, sz * half.z))
		# Index layout: sx*4 + sy*2 + sz mapped from the loops above.
		var p000: Vector3 = corners[0]
		var p001: Vector3 = corners[1]
		var p010: Vector3 = corners[2]
		var p011: Vector3 = corners[3]
		var p100: Vector3 = corners[4]
		var p101: Vector3 = corners[5]
		var p110: Vector3 = corners[6]
		var p111: Vector3 = corners[7]
		_face(p000, p001, p011, p010, color, -basis.x)
		_face(p100, p110, p111, p101, color, basis.x)
		_face(p000, p100, p101, p001, color, -basis.y)
		_face(p010, p011, p111, p110, color, basis.y)
		_face(p000, p010, p110, p100, color, -basis.z)
		_face(p001, p101, p111, p011, color, basis.z)

	## Box whose four vertical corners are given independently: lets roofs flare,
	## walls lean, and beams taper.
	func frustum(bottom: Array[Vector3], top: Array[Vector3], color: Color) -> void:
		if bottom.size() < 4 or top.size() < 4:
			return
		var bottom_normal: Vector3 = _normal(bottom[0], bottom[1], bottom[2]).normalized()
		_face(bottom[0], bottom[1], bottom[2], bottom[3], color.darkened(0.15), bottom_normal)
		var top_normal: Vector3 = _normal(top[0], top[1], top[2]).normalized()
		_face(top[0], top[3], top[2], top[1], color, top_normal)
		for i: int in range(4):
			var j: int = (i + 1) % 4
			var normal: Vector3 = ((bottom[i] + bottom[j]) * 0.5 - (top[i] + top[j]) * 0.5)
			var side_normal: Vector3 = _normal(bottom[i], bottom[j], top[j]).normalized()
			if side_normal.dot(normal) < 0.0:
				side_normal = -side_normal
			_face(bottom[i], bottom[j], top[j], top[i], color.darkened(0.06), side_normal)

	## Cylinder/cone along +Y from base to top.
	func cylinder(base: Vector3, top: Vector3, radius_bottom: float, radius_top: float, segments: int, color: Color, capped: bool = true) -> void:
		var axis: Vector3 = (top - base).normalized()
		var helper: Vector3 = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var side: Vector3 = axis.cross(helper).normalized()
		var forward: Vector3 = side.cross(axis).normalized()
		for i: int in range(segments):
			var angle_a: float = TAU * float(i) / float(segments)
			var angle_b: float = TAU * float(i + 1) / float(segments)
			var dir_a: Vector3 = side * cos(angle_a) + forward * sin(angle_a)
			var dir_b: Vector3 = side * cos(angle_b) + forward * sin(angle_b)
			var b_a: Vector3 = base + dir_a * radius_bottom
			var b_b: Vector3 = base + dir_b * radius_bottom
			var t_a: Vector3 = top + dir_a * radius_top
			var t_b: Vector3 = top + dir_b * radius_top
			var face_normal: Vector3 = (dir_a + dir_b).normalized()
			_face(b_a, b_b, t_b, t_a, color, face_normal)
			if capped and radius_bottom > 0.001:
				_triangle(base, b_b, b_a, color.darkened(0.2), -axis)
			if capped and radius_top > 0.001:
				_triangle(top, t_a, t_b, color, axis)

	## Ellipsoid blob, used for canopy clumps, shrubs and rocks. Vertices carry
	## smooth normals so the surface reads soft rather than faceted.
	func blob(center: Vector3, radii: Vector3, color: Color, rings: int = 5, segments: int = 8, jitter: float = 0.06, seed_value: int = 0) -> void:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_value
		# Build a lat/long grid first, then stitch it into triangles.
		var grid: Array[Vector3] = []
		var grid_colors: Array[Color] = []
		for ring: int in range(rings + 1):
			var v: float = float(ring) / float(rings)
			var phi: float = v * PI
			var y: float = cos(phi)
			var ring_radius: float = sin(phi)
			for seg: int in range(segments):
				var theta: float = TAU * float(seg) / float(segments)
				var wobble: float = 1.0 + rng.randf_range(-jitter, jitter)
				var point: Vector3 = center + Vector3(
					cos(theta) * ring_radius * radii.x * wobble,
					y * radii.y * wobble,
					sin(theta) * ring_radius * radii.z * wobble
				)
				grid.append(point)
				# Slight vertical shading gives blobs volume without SSAO.
				var shade: float = 0.92 + 0.08 * (1.0 - v)
				grid_colors.append(Color(color.r * shade, color.g * shade, color.b * shade, color.a))
		for ring: int in range(rings):
			for seg: int in range(segments):
				var next_seg: int = (seg + 1) % segments
				var a_index: int = ring * segments + seg
				var b_index: int = ring * segments + next_seg
				var c_index: int = (ring + 1) * segments + seg
				var d_index: int = (ring + 1) * segments + next_seg
				var a: Vector3 = grid[a_index]
				var b: Vector3 = grid[b_index]
				var c: Vector3 = grid[c_index]
				var d: Vector3 = grid[d_index]
				# The first and last rings collapse to a pole; skip the degenerate pair.
				if ring > 0:
					_vertex(a, (a - center).normalized(), grid_colors[a_index])
					_vertex(b, (b - center).normalized(), grid_colors[b_index])
					_vertex(c, (c - center).normalized(), grid_colors[c_index])
				if ring < rings - 1:
					_vertex(b, (b - center).normalized(), grid_colors[b_index])
					_vertex(d, (d - center).normalized(), grid_colors[d_index])
					_vertex(c, (c - center).normalized(), grid_colors[c_index])

	func _vertex(point: Vector3, normal: Vector3, color: Color) -> void:
		vertices.append(point)
		normals.append(normal)
		colors.append(color)

	func _face(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, normal_hint: Vector3) -> void:
		var computed: Vector3 = _normal(a, b, c).normalized()
		if computed.dot(normal_hint) < 0.0:
			_triangle(a, c, b, color, -computed)
			_triangle(a, d, c, color, -computed)
		else:
			_triangle(a, b, c, color, computed)
			_triangle(a, c, d, color, computed)

	static func _normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
		return (b - a).cross(c - a)

	func is_empty() -> bool:
		return vertices.is_empty()

	## Commit into a mesh. Triangles get per-face normals; call smooth_normals()
	## afterwards for blobs and terrain-like surfaces.
	func to_mesh() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh

	## Average normals of coincident vertices for a smooth look (blobs, terrain).
	func smooth_normals(mesh: ArrayMesh) -> void:
		var arrays: Array = mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var accrued: Dictionary = {}
		var key_scale: float = 100.0
		for i: int in range(verts.size()):
			var key: String = "%d_%d_%d" % [
				int(round(verts[i].x * key_scale)),
				int(round(verts[i].y * key_scale)),
				int(round(verts[i].z * key_scale)),
			]
			if not accrued.has(key):
				accrued[key] = Vector3.ZERO
			accrued[key] = (accrued[key] as Vector3) + normals[i]
		var smoothed: PackedVector3Array = PackedVector3Array()
		smoothed.resize(verts.size())
		for i: int in range(verts.size()):
			var key: String = "%d_%d_%d" % [
				int(round(verts[i].x * key_scale)),
				int(round(verts[i].y * key_scale)),
				int(round(verts[i].z * key_scale)),
			]
			var sum: Vector3 = accrued[key] as Vector3
			smoothed[i] = sum.normalized() if sum.length_squared() > 0.0001 else normals[i]
		arrays[Mesh.ARRAY_NORMAL] = smoothed
		mesh.clear_surfaces()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## Create a MeshInstance3D whose mesh comes from an accumulator.
static func instance(acc: Accumulator, material: Material, node_name: String, smooth: bool = false) -> MeshInstance3D:
	var mesh: ArrayMesh = acc.to_mesh()
	if smooth:
		acc.smooth_normals(mesh)
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	return node


## Simple static body with box collision, for buildings and props.
static func solid_box(parent: Node3D, node_name: String, center: Vector3, size: Vector3, yaw: float = 0.0) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.position = center
	body.rotation.y = yaw
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body
