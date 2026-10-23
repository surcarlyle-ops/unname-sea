extends CharacterBody3D
## Ground enemy with a visible windup, stagger and one damage event per attack.

signal defeated(enemy: Node3D)

enum State { CHASE, WINDUP, RECOVERY, STAGGER, DEAD }

var target: CharacterBody3D
var tuning: Dictionary
var stats: Dictionary
var dead: bool = false
var health: int = 20
var state: State = State.CHASE
var state_time: float = 0.0
var attack_count: int = 0
var _shell: MeshInstance3D
var _body: Node3D
var _warning: MeshInstance3D
var _label: Label3D
var _shell_material: StandardMaterial3D
var _flash_time: float = 0.0
var _white_flash_time: float = 0.0  ## (Claude Code) pure white hit-flash — stronger than the regular tint
var _walk_time: float = 0.0


func _ready() -> void:
	add_to_group("mvp_enemies")
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = 0.25
	health = int(stats.get("hp", 20))
	var collision: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.43
	capsule.height = 1.05
	collision.shape = capsule
	collision.position.y = 0.525
	add_child(collision)
	_build_visual()


func _physics_process(delta: float) -> void:
	if dead or target == null or not target.controls_active:
		return
	state_time = maxf(0.0, state_time - delta)
	_flash_time = maxf(0.0, _flash_time - delta)
	_white_flash_time = maxf(0.0, _white_flash_time - delta)  ## (Claude Code) count down the white flash
	_walk_time += delta
	var toward: Vector3 = target.global_position - global_position
	toward.y = 0.0
	var distance: float = toward.length()
	var desired: Vector3 = Vector3.ZERO
	if state == State.CHASE:
		if distance <= float(tuning.attack_range) and _can_hit_player():
			state = State.WINDUP
			state_time = float(tuning.windup)
		else:
			desired = _steer(toward.normalized()) * float(tuning.walk_speed)
	elif state == State.WINDUP and state_time <= 0.0:
		if distance <= float(tuning.damage_range) and _can_hit_player():
			target.receive_damage(int(stats.get("attack", 8)), global_position)
			attack_count += 1
		state = State.RECOVERY
		state_time = float(tuning.recovery)
	elif state in [State.RECOVERY, State.STAGGER] and state_time <= 0.0:
		state = State.CHASE
	var rate: float = 7.0 if state == State.STAGGER else 12.0
	velocity.x = move_toward(velocity.x, desired.x, rate * delta)
	velocity.z = move_toward(velocity.z, desired.z, rate * delta)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()
	if toward.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(toward.x, toward.z), minf(delta * 8.0, 1.0))
	_update_visual()
	if global_position.y < -5.0:
		_die()


func _steer(direction: Vector3) -> Vector3:
	var from: Vector3 = global_position + Vector3.UP * 0.45
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + direction * 1.3, 1)
	if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return direction
	for angle: float in [-0.9, 0.9, -1.6, 1.6]:
		var candidate: Vector3 = direction.rotated(Vector3.UP, angle)
		query.to = from + candidate * 1.3
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return candidate
	return Vector3.ZERO


func _can_hit_player() -> bool:
	if absf(target.global_position.y - global_position.y) > 1.2:
		return false
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.6, target.global_position + Vector3.UP * 0.7, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func apply_damage(amount: int, push: Vector3) -> void:
	if dead:
		return
	health = maxi(0, health - maxi(amount - int(stats.get("defense", 0)), 1))
	_flash_time = 0.12
	_white_flash_time = 0.07  ## (Claude Code) bright white flash — sells the impact
	velocity += Vector3(push.x, 1.3, push.z)
	state = State.STAGGER
	state_time = float(tuning.stagger)
	if health <= 0:
		_die()
	else:
		_update_visual()


func _die() -> void:
	if dead:
		return
	dead = true
	state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	_warning.visible = false
	_label.visible = false
	_shell_material.albedo_color = Color("d4c7ac")
	var animation: Tween = create_tween()
	animation.tween_property(_body, "scale", Vector3(1.3, 0.15, 1.3), 0.16)
	animation.tween_property(_body, "position:y", -0.2, 0.20)
	animation.tween_callback(queue_free)
	defeated.emit(self)


func _build_visual() -> void:
	_body = Node3D.new()
	_body.name = "PlaceholderShell"
	add_child(_body)
	_shell_material = StandardMaterial3D.new()
	_shell_material.albedo_color = Color("6c9290")
	_shell_material.roughness = 0.9
	var shell: SphereMesh = SphereMesh.new()
	shell.radius = 0.52
	shell.height = 0.65
	shell.radial_segments = 10
	shell.rings = 5
	_shell = _mesh(_body, shell, Vector3(0, 0.53, 0), _shell_material)
	var leg_material: StandardMaterial3D = StandardMaterial3D.new()
	leg_material.albedo_color = Color("364e51")
	for side: float in [-1.0, 1.0]:
		for leg: int in range(3):
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(0.48, 0.09, 0.09)
			var limb: MeshInstance3D = _mesh(_body, box, Vector3(side * 0.48, 0.22, -0.28 + leg * 0.27), leg_material)
			limb.rotation_degrees.z = side * 16.0
		var eye: SphereMesh = SphereMesh.new()
		eye.radius = 0.065
		eye.height = 0.13
		_mesh(_body, eye, Vector3(side * 0.18, 0.70, 0.40), leg_material)
	var ring: CylinderMesh = CylinderMesh.new()
	ring.top_radius = float(tuning.damage_range)
	ring.bottom_radius = ring.top_radius
	ring.height = 0.015
	ring.radial_segments = 32
	var warning_material: StandardMaterial3D = StandardMaterial3D.new()
	warning_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warning_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warning_material.albedo_color = Color(1.0, 0.40, 0.15, 0.27)
	_warning = _mesh(self, ring, Vector3(0, 0.018, 0), warning_material)
	_warning.visible = false
	_label = Label3D.new()
	_label.position.y = 1.25
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 25
	_label.pixel_size = 0.006
	_label.outline_size = 5
	_label.modulate = Color("f5ead1")
	add_child(_label)
	_update_visual()


func _update_visual() -> void:
	_warning.visible = state == State.WINDUP
	# (Claude Code) White-hit flash overrides everything for a frame or two.
	# This reads as "impact" way better than a warm tint.
	if _white_flash_time > 0.0:
		var flash_strength: float = clampf(_white_flash_time / 0.07, 0.0, 1.0)
		_shell_material.albedo_color = Color(1.0, 1.0, 0.96, 1.0).lerp(Color("fff1c6"), 1.0 - flash_strength)
	elif _flash_time > 0.0:
		_shell_material.albedo_color = Color("fff1c6")
	else:
		_shell_material.albedo_color = Color("d77748") if state == State.WINDUP else Color("6c9290")
	_body.position.y = sin(_walk_time * 10.0) * 0.035 if state == State.CHASE else -0.07
	_label.text = "蓄力！" if state == State.WINDUP else str(health)
	_label.visible = target != null and target.global_position.distance_to(global_position) < 8.0


func _mesh(parent: Node3D, mesh: Mesh, point: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = point
	instance.material_override = material
	parent.add_child(instance)
	return instance
