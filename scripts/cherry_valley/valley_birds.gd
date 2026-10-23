extends Node3D
## (Claude Code) Distant birds: a flock of a few dozen wings circling high above
## the valley. One MultiMesh, one draw call, updated on the CPU at a low rate.
## Always far enough away that size and motion read as atmosphere, never clutter.

const BIRD_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, shadows_disabled;
// (Claude Code) Flock body: dark silhouette with a lighter underside so birds
// separate from the pale sky.

uniform vec4 body_color : source_color = vec4(0.20, 0.22, 0.28, 1.0);
uniform vec4 fade_color : source_color = vec4(0.66, 0.72, 0.82, 1.0);

void fragment() {
	float up = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	ALBEDO = mix(fade_color.rgb, body_color.rgb, up);
}
"""

var config: Dictionary
var birds: MultiMeshInstance3D
var sizes: Dictionary = {}

var _points: Array[Dictionary] = []
## CPU mirror of the instance transforms: headless has no GPU buffer to read back,
## so tests and debugging inspect this instead.
var transforms: Array[Transform3D] = []
var _phase: float = 0.0
var _wind: float = 0.0


func build(cfg: Dictionary) -> void:
	config = cfg
	if not cfg.has("birds") or not bool(cfg.birds.enabled):
		return
	var spec: Dictionary = cfg.birds
	var count: int = int(spec.count)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(spec.seed)
	_points.clear()
	for i: int in range(count):
		_points.append({
			# Each bird has its own orbit radius, height and angular offset.
			"radius": float(spec.radius) * rng.randf_range(0.6, 1.0),
			"height": float(spec.center[1]) + rng.randf_range(-1.0, 1.0) * float(spec.height_spread),
			"angle": rng.randf_range(0.0, TAU),
			"angular_speed": float(spec.speed) * rng.randf_range(0.8, 1.25),
			"flap": rng.randf_range(0.0, TAU),
			"flap_rate": rng.randf_range(2.0, 4.0),
			"scale": float(spec.size) * rng.randf_range(0.7, 1.2),
			"offset": Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-14.0, 14.0)),
		})
	var mesh: ArrayMesh = _bird_mesh()
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	# 3 boxes per bird (body + two wings).
	multimesh.mesh = mesh
	multimesh.instance_count = count
	birds = MultiMeshInstance3D.new()
	birds.name = "Birds"
	birds.multimesh = multimesh
	birds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = BIRD_SHADER
	material.shader = shader
	birds.material_override = material
	add_child(birds)
	sizes["birds"] = count
	_update_flock(0.0)


## Tiny two-wing silhouette. Wings are hinged at the body so they can flap.
func _bird_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0, 0, 0), Vector3(0.20, 0.12, 0.62))
	_box(st, Vector3(-0.42, 0.04, 0.02), Vector3(0.72, 0.05, 0.34))
	_box(st, Vector3(0.42, 0.04, 0.02), Vector3(0.72, 0.05, 0.34))
	st.generate_normals()
	return st.commit()


func _box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var half: Vector3 = size * 0.5
	var corners: Array[Vector3] = []
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				corners.append(center + Vector3(sx * half.x, sy * half.y, sz * half.z))
	var faces: Array = [
		[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1],
		[2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3],
	]
	for face: Array in faces:
		var a: Vector3 = corners[face[0]]
		var b: Vector3 = corners[face[1]]
		var c: Vector3 = corners[face[2]]
		var d: Vector3 = corners[face[3]]
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


func _process(delta: float) -> void:
	if birds == null or _points.is_empty():
		return
	_update_flock(delta)


func _update_flock(delta: float) -> void:
	_phase += delta
	var phase: float = _phase
	var spec: Dictionary = config.birds
	var center: Vector3 = Vector3(float(spec.center[0]), 0.0, float(spec.center[2]))
	var multimesh: MultiMesh = birds.multimesh
	transforms.resize(_points.size())
	for i: int in range(_points.size()):
		var point: Dictionary = _points[i]
		var angle: float = float(point.angle) + phase * float(point.angular_speed)
		var radius: float = float(point.radius)
		var position: Vector3 = center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		position.y = float(point.height)
		position.x += float(point.offset.x)
		position.z += float(point.offset.y)
		# Tangent of the orbit: the bird faces where it is going.
		var heading: Vector3 = Vector3(-sin(angle), 0.0, cos(angle)).normalized()
		var bank: float = sin(angle * 1.0) * 0.18
		var flap: float = sin(phase * float(point.flap_rate) + float(point.flap))
		# Occasional glide: flap dips to nothing in the middle of the cycle.
		var flap_amount: float = clampf(flap * 1.4, -1.0, 1.0)
		# Model forward is +Z: build the basis directly from heading.
		var right: Vector3 = Vector3.UP.cross(heading).normalized()
		var up: Vector3 = heading.cross(right).normalized()
		var basis: Basis = Basis(right, up * cos(bank) + right * sin(bank), heading)
		basis = basis * Basis(Vector3.RIGHT, flap_amount * 0.5)
		var scale: float = float(point.scale)
		var transform: Transform3D = Transform3D(basis.scaled(Vector3.ONE * scale), position)
		transforms[i] = transform
		multimesh.set_instance_transform(i, transform)


func set_mood(mood: Dictionary) -> void:
	if birds == null:
		return
	# Birds shelter during rain: thin the flock out rather than hide it outright.
	birds.visible = true
	birds.transparency = 0.35 if bool(mood.rain) else 0.0


func apply_quality(settings: Dictionary) -> void:
	if birds == null:
		return
	birds.visibility_range_end = 380.0 if bool(settings.get("reflection", true)) else 220.0
