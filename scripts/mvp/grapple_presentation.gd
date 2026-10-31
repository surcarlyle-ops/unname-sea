extends Node3D
## Visual-only waist tether; the existing grapple remains the physics authority.

const ROPE_SHADER: Shader = preload("res://shaders/braided_rope.gdshader")
var hook: Node3D
var attached: bool = false
var flight: float = 0.0
var _segments: Array[MeshInstance3D] = []
var _last_tip: Vector3 = Vector3.ZERO
var _retract: float = 0.0
var shot_duration: float = 0.05
var _launch_origin: Vector3 = Vector3.ZERO
var _settings: Dictionary = {}
var rope_points: PackedVector3Array = PackedVector3Array()

func _ready() -> void:
	_settings = (JSON.parse_string(FileAccess.get_file_as_string("res://data/first_person_presentation.json")) as Dictionary).rope
	for i: int in range(16):
		var part: MeshInstance3D = MeshInstance3D.new()
		var cylinder: CylinderMesh = CylinderMesh.new()
		cylinder.top_radius = 0.009
		cylinder.bottom_radius = 0.009
		cylinder.height = 1.0
		cylinder.radial_segments = 8
		part.mesh = cylinder
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = ROPE_SHADER
		part.material_override = material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.top_level = true
		part.visible = false
		add_child(part)
		_segments.append(part)

func set_attached(value: bool) -> void:
	if value and not attached:
		flight = 0.0
		_launch_origin = hook._camera.global_transform * Vector3(-0.29, -0.68, 0.04)
		shot_duration = clampf(_launch_origin.distance_to(hook.anchor) / float(_settings.shot_speed), float(_settings.shot_min_duration), float(_settings.shot_max_duration))
	if not value and attached:
		_retract = float(_settings.retract_duration)
	attached = value

func reset() -> void:
	attached = false
	_retract = 0.0
	flight = 0.0
	_hide()

func _process(delta: float) -> void:
	if not is_instance_valid(hook) or hook._camera == null:
		return
	if not attached and _retract <= 0.0:
		_hide()
		return
	var camera: Camera3D = hook._camera
	var waist: Vector3 = camera.global_transform * Vector3(-0.29, -0.68, 0.04)
	var hands: Node3D = camera.get_node_or_null("Hands")
	var contact: Vector3 = waist
	var hold: float = 0.0
	if hands != null and hands.has_method("grapple_grip_point"):
		hold = hands.grapple_hold_weight()
		contact = waist.lerp(hands.grapple_grip_point(), hold)
	var tip: Vector3
	if attached:
		flight = minf(flight + delta, 1.0)
		tip = _launch_origin.lerp(hook.anchor, clampf(flight / shot_duration, 0.0, 1.0))
		_last_tip = tip
	else:
		_retract = maxf(0.0, _retract - delta)
		tip = waist.lerp(_last_tip, _retract / float(_settings.retract_duration))
	var points: PackedVector3Array = PackedVector3Array()
	var direction: Vector3 = (tip - contact).normalized()
	var hand_tangent: Vector3 = direction
	if hands != null and hands.has_method("grapple_rope_tangent"):
		hand_tangent = hands.grapple_rope_tangent()
	if hand_tangent.dot(direction) < 0.0:
		hand_tangent = -hand_tangent
	# Route a short straight section THROUGH the closed handle channel.
	# A single palm point let both external spans cut underneath the fist.
	var half_width: float = 0.060 * hold
	var entry: Vector3 = contact - hand_tangent * half_width
	var exit: Vector3 = contact + hand_tangent * half_width
	for i: int in range(5):
		var t: float = float(i) / 4.0
		points.append(waist.lerp(entry, t) + Vector3.DOWN * sin(t * PI) * float(_settings.waist_sag) * hold)
	points.append(contact)
	points.append(exit)
	var impact_age: float = maxf(0.0, flight - shot_duration)
	var settle: float = maxf(0.0, 1.0 - impact_age / float(_settings.impact_settle_duration)) if attached and flight >= shot_duration else 0.0
	for i: int in range(1, 11):
		var t: float = float(i) / 10.0
		var curve: Vector3 = exit.lerp(tip, t)
		var vibration: float = sin(impact_age * 150.0 - t * TAU) * float(_settings.impact_vibration) * settle * sin(t * PI)
		points.append(curve + camera.global_basis.x * vibration)
	rope_points = points
	for i: int in range(_segments.size()):
		_set_segment(_segments[i], points[i], points[i + 1])
	hook._hook_head.visible = true
	hook._hook_head.global_position = tip
	var normal: Vector3 = hook.anchor_normal if attached else (waist - tip).normalized()
	if normal.length_squared() < 0.1:
		normal = Vector3.UP
	hook._hook_head.quaternion = Quaternion(Vector3.UP, normal)

func _set_segment(part: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var direction: Vector3 = end - start
	var length: float = direction.length()
	part.visible = length > 0.002
	if not part.visible:
		return
	var basis: Basis = Basis(Quaternion(Vector3.UP, direction / length))
	part.global_transform = Transform3D(basis.scaled_local(Vector3(1, length, 1)), (start + end) * 0.5)
	(part.material_override as ShaderMaterial).set_shader_parameter("strand_repeats", length * 40.0)

func _hide() -> void:
	for part: MeshInstance3D in _segments:
		part.visible = false
	if is_instance_valid(hook._hook_head):
		hook._hook_head.visible = false
