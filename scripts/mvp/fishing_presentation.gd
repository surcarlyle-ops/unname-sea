extends Node3D
class_name FishingPresentation
## MVP fishing visuals: bobber, line and water ripples (CodeBuddy 2026-10-28).
##
## Placeholder art only. first_person_hands.gd (Codex) can call
## set_rod_tip_anchor() with the real hand/rod tip node; until then the line
## starts from a fixed offset in front of the camera.

const ORB_VISUAL: Script = preload("res://scripts/mvp/loot_orb_visual.gd")
const FEEDBACK_PATH: String = "res://data/fishing_feedback.json"

const LINE_RADIUS: float = 0.0045
## Mirrors FishingMVP.State; kept local so this script never depends on the
## global class cache being rebuilt after adding a file.
const STATE_IDLE: int = 0
const STATE_CASTING: int = 1
const STATE_WAITING: int = 2
const STATE_BITING: int = 3
const STATE_REVEAL: int = 4

var fishing: Node
var player: CharacterBody3D
var rod_tip_anchor: Node3D
var water_level: float = 0.0

var _bobber: Node3D
var _bobber_cap: MeshInstance3D
var _line: MeshInstance3D
var _ripples: Array[Dictionary] = []
var _ripple_material: StandardMaterial3D
var _cap_red: StandardMaterial3D
var _cap_gold: StandardMaterial3D
var _bite_phase: float = 0.0
var feedback: Dictionary = {}
var _return_from: Vector3
var _return_clock: float = -1.0
var _fish_on_line: bool = false
var _catch_orb: Node3D
var _last_pulse: int = -1
signal bite_tug



func _ready() -> void:
	_build_bobber()
	_build_line()
	feedback = JSON.parse_string(FileAccess.get_file_as_string(FEEDBACK_PATH)) as Dictionary
	_catch_orb = ORB_VISUAL.build(float(feedback.orb_radius), Color(str(feedback.orb_color)))
	add_child(_catch_orb)
	_catch_orb.visible = false
	fishing.reel_started.connect(_begin_return)
	fishing.cancelled.connect(_on_cancel)
	fishing.cast_started.connect(func(_point: Vector3) -> void:
		_return_clock = -1.0
		_fish_on_line = false
		_last_pulse = -1
	)
	fishing.bite_started.connect(func() -> void: _last_pulse = -1)


## Optional hook for the hand layer: once the rod tip is a real node, the line
## follows it instead of the camera offset.
func set_rod_tip_anchor(node: Node3D) -> void:
	rod_tip_anchor = node


func rod_tip() -> Vector3:
	if rod_tip_anchor != null and is_instance_valid(rod_tip_anchor):
		return rod_tip_anchor.global_position
	if player == null or player.camera == null:
		return Vector3.ZERO
	var camera: Camera3D = player.camera
	return camera.global_position + camera.global_basis * Vector3(0.24, -0.18, -0.62)


func _process(delta: float) -> void:
	if fishing == null or player == null or fishing.is_paused():
		return
	_update_ripples(delta)
	var state: int = int(fishing.state)
	var returning: bool = state == STATE_REVEAL or _return_clock >= 0.0
	if state == STATE_IDLE and not returning:
		_bobber.visible = false
		_line.visible = false
		_catch_orb.visible = false
		return
	_bobber.visible = true
	_line.visible = true
	_catch_orb.visible = false
	var target: Vector3 = fishing.bobber_position + Vector3.UP * 0.04
	var tip: Vector3 = rod_tip()
	if returning:
		var progress: float = fishing.reveal_progress()
		if state != STATE_REVEAL:
			_return_clock += delta
			progress = clampf(_return_clock / float(feedback.early_return_seconds), 0.0, 1.0)
		var travel: float = 1.0 - pow(1.0 - maxf(progress, 0.0), 1.5)
		target = _return_from.lerp(tip, travel) + Vector3.UP * sin(travel * PI) * float(feedback.return_arc)
		_catch_orb.visible = _fish_on_line and progress < 1.0
		_catch_orb.global_position = target - Vector3.UP * 0.10
		if progress >= 1.0:
			_return_clock = -1.0
			_bobber.visible = false
			_line.visible = false
			_catch_orb.visible = false
	elif state == STATE_CASTING:
		var progress: float = fishing.cast_progress()
		target = fishing.cast_tip_origin.lerp(target, progress) + Vector3.UP * sin(progress * PI) * 0.85
	elif state == STATE_BITING:
		var cycle: float = fishing.bite_progress() * float(feedback.bite_pulses)
		var phase: float = fposmod(cycle, 1.0)
		var down: float = float(feedback.bite_down_fraction)
		var tug: float = smoothstep(0.0, down, phase) if phase < down else 1.0 - smoothstep(down, 1.0, phase)
		target.y -= float(feedback.bite_sink) * tug
		target.x += float(feedback.bite_side_pull) * sin(cycle * PI) * tug
		_bobber.rotation.z = tug * 0.22
		if int(cycle) != _last_pulse:
			_last_pulse = int(cycle)
			spawn_ripple(0.38, 0.25)
			bite_tug.emit()
		_bobber_cap.material_override = _cap_gold
	elif state == STATE_WAITING:
		target.y += sin(Time.get_ticks_msec() * 0.0016) * 0.012
		_bobber.rotation.z = 0.0
		_bobber_cap.material_override = _cap_red
	_bobber.global_position = target
	_update_line(tip, target)


func _begin_return(is_fish: bool) -> void:
	_return_from = _bobber.global_position
	_return_clock = -1.0
	_fish_on_line = is_fish
	spawn_ripple(0.65, 0.5)


func _on_cancel(reason: String) -> void:
	_fish_on_line = false
	if reason == "early" or reason == "distance":
		_return_from = _bobber.global_position
		_return_clock = 0.0
	else:
		_return_clock = -1.0
		_bobber.visible = false
		_line.visible = false
		_catch_orb.visible = false


func _update_line(from: Vector3, to: Vector3) -> void:
	var offset: Vector3 = to - from
	var length: float = offset.length()
	if length < 0.05:
		_line.visible = false
		return
	var direction: Vector3 = offset / length
	var helper: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var side: Vector3 = direction.cross(helper).normalized()
	var depth: Vector3 = side.cross(direction).normalized()
	_line.global_transform = Transform3D(Basis(side * LINE_RADIUS, direction * length, depth * LINE_RADIUS), (from + to) * 0.5)


## Bigger ring for the encounter warning; smaller rings mark ordinary catches.
func spawn_ripple(radius: float, strength: float = 1.0) -> void:
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = _ripple_material.duplicate() as StandardMaterial3D
	ring.position = Vector3(fishing.bobber_position.x, water_level + 0.015, fishing.bobber_position.z)
	add_child(ring)
	_ripples.append({"node": ring, "age": 0.0, "radius": radius, "strength": strength})


func _update_ripples(delta: float) -> void:
	for index: int in range(_ripples.size() - 1, -1, -1):
		var entry: Dictionary = _ripples[index]
		var node: MeshInstance3D = entry.node as MeshInstance3D
		entry.age = float(entry.age) + delta
		var age: float = entry.age
		var life: float = 1.15 if float(entry.strength) > 0.9 else 0.85
		if age >= life or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_ripples.remove_at(index)
			continue
		var t: float = age / life
		var scale_value: float = lerpf(0.25, float(entry.radius), 1.0 - pow(1.0 - t, 2.0))
		node.scale = Vector3(scale_value, 1.0, scale_value)
		# Each ring owns its material so the fade stays independent.
		if node.material_override is StandardMaterial3D:
			var fade: Color = (node.material_override as StandardMaterial3D).albedo_color
			fade.a = (1.0 - t) * 0.55
			(node.material_override as StandardMaterial3D).albedo_color = fade


func _build_bobber() -> void:
	_bobber = Node3D.new()
	_bobber.name = "Bobber"
	add_child(_bobber)
	var float_mesh: SphereMesh = SphereMesh.new()
	float_mesh.radius = 0.075
	float_mesh.height = 0.15
	float_mesh.radial_segments = 12
	float_mesh.rings = 6
	var floater: MeshInstance3D = MeshInstance3D.new()
	floater.mesh = float_mesh
	floater.material_override = _bobber_material(Color("efe6d2"))
	_bobber.add_child(floater)
	var cap_mesh: SphereMesh = SphereMesh.new()
	cap_mesh.radius = 0.078
	cap_mesh.height = 0.075
	cap_mesh.radial_segments = 12
	cap_mesh.rings = 5
	_bobber_cap = MeshInstance3D.new()
	_bobber_cap.mesh = cap_mesh
	_cap_red = _bobber_material(Color("d96b5a"))
	_cap_gold = _bobber_material(Color("f2c56a"))
	_bobber_cap.material_override = _cap_red
	_bobber_cap.position.y = 0.058
	_bobber.add_child(_bobber_cap)
	var stem: CylinderMesh = CylinderMesh.new()
	stem.top_radius = 0.008
	stem.bottom_radius = 0.008
	stem.height = 0.16
	var stem_instance: MeshInstance3D = MeshInstance3D.new()
	stem_instance.mesh = stem
	stem_instance.material_override = _bobber_material(Color("2f2a38"))
	stem_instance.position.y = 0.16
	_bobber.add_child(stem_instance)
	_bobber.visible = false
	_ripple_material = StandardMaterial3D.new()
	_ripple_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ripple_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ripple_material.albedo_color = Color(0.85, 0.94, 0.98, 0.55)
	_ripple_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _build_line() -> void:
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.radial_segments = 5
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.86, 0.88, 0.9, 0.75)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line = MeshInstance3D.new()
	_line.name = "FishingLine"
	_line.mesh = cylinder
	_line.material_override = material
	_line.visible = false
	add_child(_line)


func _bobber_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	return material
