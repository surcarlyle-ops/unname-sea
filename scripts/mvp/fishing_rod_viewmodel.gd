extends Node3D
## A replaceable rod attached to the verified palm grip, with presentation-only poses.

const CONFIG_PATH: String = "res://data/fishing_rod_presentation.json"
const STATES: Array[String] = ["idle", "casting", "waiting", "biting", "reeling"]

var config: Dictionary = {}
var phase: String = "idle"
var progress: float = 0.0
var _segments: Array[MeshInstance3D] = []
var _guides: Array[MeshInstance3D] = []
var _tip: Marker3D
var _time: float = 0.0
var _flex: float = 0.0
var _bite_feedback: Dictionary = {}


func _ready() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) as Dictionary
	_bite_feedback = JSON.parse_string(FileAccess.get_file_as_string("res://data/fishing_feedback.json")) as Dictionary
	_build()
	_update_shaft()


func set_phase(value: String, normalized_progress: float = 0.0) -> void:
	phase = value.to_lower() if STATES.has(value.to_lower()) else "idle"
	progress = clampf(normalized_progress, 0.0, 1.0)


func reset_presentation() -> void:
	phase = "idle"
	progress = 0.0
	_time = 0.0
	_flex = 0.0
	if is_instance_valid(_tip):
		_update_shaft()


func tip_world_position() -> Vector3:
	return _tip.global_position


func apply_hand_pose(arm: Node3D, delta: float, speed: float, stride_phase: float) -> void:
	_time += delta
	var frame: Dictionary = {"offset": [0, 0, 0], "pitch": 0.0}
	if phase == "casting" or phase == "reeling":
		frame = sample_motion(phase, progress)
	var breath: float = sin(_time * 1.7) * 0.0015
	var moving: float = clampf(speed / 8.2, 0.0, 1.0)
	var bob: float = sin(stride_phase * 2.0) * 0.005 * moving
	arm.position = _vec(config.hand_position) + _vec(frame.offset) + Vector3(0.0, breath + bob, 0.0)
	var base: Quaternion = Quaternion.from_euler(_vec(config.hand_degrees) * PI / 180.0)
	var pitch: float = float(config.forward_tilt_degrees) + float(frame.pitch)
	arm.quaternion = Quaternion(Vector3.RIGHT, deg_to_rad(pitch)) * base
	var target_flex: float = 0.0
	if phase == "casting":
		target_flex = -sin(progress * TAU) * 0.035
	elif phase == "reeling":
		target_flex = sin(progress * PI) * 0.025
	elif phase == "biting":
		var phase_t: float = fposmod(progress * float(_bite_feedback.get("bite_pulses", 3.0)), 1.0)
		var tug: float = smoothstep(0.0, 0.2, phase_t) if phase_t < 0.2 else 1.0 - smoothstep(0.2, 1.0, phase_t)
		target_flex = 0.075 * tug
	elif phase == "waiting":
		target_flex = 0.003 + sin(_time * 2.0) * 0.001
	_flex = lerpf(_flex, target_flex, 1.0 - exp(-delta * 25.0))
	_update_shaft()


func sample_motion(state: String, at: float) -> Dictionary:
	var keys: Array = config.get(state, []) as Array
	if keys.is_empty():
		return {"offset": [0, 0, 0], "pitch": 0.0}
	for i: int in range(1, keys.size()):
		var b: Dictionary = keys[i]
		if at <= float(b.t):
			var a: Dictionary = keys[i - 1]
			var blend: float = smoothstep(0.0, 1.0, clampf((at - float(a.t)) / maxf(float(b.t) - float(a.t), 0.001), 0.0, 1.0))
			var offset: Vector3 = _vec(a.offset).lerp(_vec(b.offset), blend)
			return {"offset": [offset.x, offset.y, offset.z], "pitch": lerpf(float(a.pitch), float(b.pitch), blend)}
	return keys.back() as Dictionary


func _build() -> void:
	var wood: StandardMaterial3D = _material(Color(str(config.colors.wood)), 0.0)
	var wrap: StandardMaterial3D = _material(Color(str(config.colors.wrap)), 0.0)
	var metal: StandardMaterial3D = _material(Color(str(config.colors.metal)), 0.45)
	var light_tip: StandardMaterial3D = _material(Color(str(config.colors.tip)), 0.05)
	var radius: float = float(config.handle_radius)
	var handle: MeshInstance3D = _cylinder(radius, radius * 0.92, 0.28, wrap)
	handle.name = "WrappedHandle"
	handle.position.y = 0.005
	for at: float in [-0.125, 0.125]:
		var cap: MeshInstance3D = _cylinder(radius + 0.002, radius + 0.002, 0.015, metal)
		cap.position.y = at
	for i: int in range(7):
		var band: MeshInstance3D = _cylinder(radius + 0.0007, radius + 0.0007, 0.003, wood)
		band.position.y = -0.095 + float(i) * 0.030
	for i: int in range(12):
		var fraction: float = float(i) / 12.0
		var r: float = lerpf(0.013, 0.003, fraction)
		var segment: MeshInstance3D = _cylinder(r, maxf(0.002, r - 0.001), 0.1, light_tip if i >= 9 else wood)
		_segments.append(segment)
	for i: int in range(4):
		var ring: TorusMesh = TorusMesh.new()
		ring.inner_radius = 0.007 if i == 3 else 0.009
		ring.outer_radius = ring.inner_radius + 0.003
		ring.rings = 12
		ring.ring_segments = 6
		var guide: MeshInstance3D = _mesh(ring, metal)
		_guides.append(guide)
	_tip = Marker3D.new()
	_tip.name = "LineExit"
	add_child(_tip)


func _shaft_point(fraction: float) -> Vector3:
	return Vector3(0.0, lerpf(0.145, float(config.tip_height), fraction), -_flex * fraction * fraction)


func _update_shaft() -> void:
	for i: int in range(_segments.size()):
		var start: Vector3 = _shaft_point(float(i) / float(_segments.size()))
		var finish: Vector3 = _shaft_point(float(i + 1) / float(_segments.size()))
		var segment: MeshInstance3D = _segments[i]
		(segment.mesh as CylinderMesh).height = start.distance_to(finish)
		segment.position = (start + finish) * 0.5
		segment.quaternion = Quaternion(Vector3.UP, (finish - start).normalized())
	for i: int in range(_guides.size()):
		_guides[i].position = _shaft_point([0.12, 0.40, 0.72, 1.0][i]) + Vector3(0.0, 0.0, -0.012)
	_tip.position = _shaft_point(1.0) + Vector3(0.0, 0.0, -0.012)


func _material(color: Color, metal: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = 0.6
	return material


func _cylinder(bottom: float, top: float, height: float, material: Material) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 12
	return _mesh(mesh, material)


func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _vec(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
