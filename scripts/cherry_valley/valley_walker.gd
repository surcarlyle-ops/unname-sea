extends CharacterBody3D
## (Claude Code) A small lantern spirit that walks its route on the baked navmesh.
## No combat, no collision with the player: it demonstrates that village paths and
## the bridge are actually navigable.

const MESH_KIT: Script = preload("res://scripts/cherry_valley/valley_mesh_kit.gd")

var agent: NavigationAgent3D
var route: Array[Vector3] = []
var speed: float = 1.35
var current_index: int = 0
var waiting: float = 0.0

var _visual: Node3D
var _bob_time: float = 0.0


func build(points: Array[Vector3], start_position: Vector3) -> void:
	global_position = start_position
	route = points
	collision_layer = 0
	collision_mask = 0
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.8
	agent.avoidance_enabled = false
	add_child(agent)
	_visual = Node3D.new()
	_visual.name = "LanternSpirit"
	add_child(_visual)
	var acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	acc.blob(Vector3(0, 0.55, 0), Vector3(0.30, 0.36, 0.30), Color("#f5e6c4"), 4, 8, 0.04, 7)
	acc.blob(Vector3(0, 0.20, 0), Vector3(0.16, 0.16, 0.16), Color("#d9a86a"), 3, 6, 0.03, 9)
	var toon: ShaderMaterial = MESH_KIT.toon_material(
		load("res://shaders/valley_toon.gdshader"), Color.WHITE, 0.5
	)
	_visual.add_child(MESH_KIT.instance(acc, toon, "SpiritBody"))
	var glow_material: StandardMaterial3D = MESH_KIT.emissive_material(Color("#ffd9a0"), 2.0)
	var glow_acc: MESH_KIT.Accumulator = MESH_KIT.Accumulator.new()
	glow_acc.blob(Vector3(0, 0.6, 0), Vector3(0.13, 0.15, 0.13), Color.WHITE, 3, 6, 0.0, 1)
	var glow: MeshInstance3D = MESH_KIT.instance(glow_acc, glow_material, "SpiritCore")
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(glow)


func _ready() -> void:
	# Wait for the navigation map to sync before asking for a path.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_set_next_target()


func _set_next_target() -> void:
	if route.is_empty() or agent == null:
		return
	agent.target_position = route[current_index]


func _physics_process(delta: float) -> void:
	if agent == null or route.is_empty():
		return
	_bob_time += delta
	_visual.position.y = sin(_bob_time * 2.4) * 0.06
	if waiting > 0.0:
		waiting = maxf(0.0, waiting - delta)
		velocity = Vector3.ZERO
		move_and_slide()
		return
	if agent.is_navigation_finished():
		waiting = 1.6
		current_index = (current_index + 1) % route.size()
		_set_next_target()
		return
	var next_point: Vector3 = agent.get_next_path_position()
	var direction: Vector3 = next_point - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= 14.0 * delta
	else:
		velocity.y = -0.1
	move_and_slide()
	if direction.length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.z, direction.x), minf(delta * 5.0, 1.0))
