extends CharacterBody3D
## Minimal first-person controller for the grapple test scene only.
## Not part of the main project controller; safe to delete after validation.

@export var move_speed: float = 6.0
@export var ground_acceleration: float = 45.0
@export var air_acceleration: float = 12.0
@export var jump_velocity: float = 5.5
@export var mouse_sensitivity: float = 0.0022

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var grapple: GrappleHook = $GrappleHook

var _gravity: float = 9.8
var _base_fov: float = 75.0
var _spawn: Vector3 = Vector3.ZERO
## Tracks whether the player wants the mouse captured, so focus changes can restore it.
var _wants_mouse_capture: bool = true


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_base_fov = camera.fov
	_spawn = global_position
	_set_mouse_captured(true)


func _notification(what: int) -> void:
	# Restore mouse capture when the window regains focus (minimize / alt-tab).
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		if _wants_mouse_capture:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_mouse_captured(captured: bool) -> void:
	_wants_mouse_capture = captured
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	# Clicking while the cursor is free re-captures it (also covers returning from minimize).
	if event is InputEventMouseButton and not _wants_mouse_capture:
		var click := event as InputEventMouseButton
		if click.pressed:
			_set_mouse_captured(true)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		head.rotate_x(-motion.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, -1.4, 1.4)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			if button.pressed:
				grapple.try_attach()
			else:
				grapple.release()
		elif button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			_swing()
	elif event.is_action_pressed("ui_cancel"):
		_set_mouse_captured(false)
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction: Vector3 = (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()

	if grapple.is_attached():
		# The grapple owns horizontal velocity; only allow light air steering.
		velocity += direction * air_acceleration * delta
	else:
		var target: Vector3 = direction * move_speed
		var accel: float = ground_acceleration if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, target.x, accel * delta)
		velocity.z = move_toward(velocity.z, target.z, accel * delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	if Input.is_action_just_pressed("ui_accept"):
		if is_on_floor():
			velocity.y = jump_velocity
		elif grapple.is_attached():
			# APEX super grapple: jumping right after attaching adds forward momentum.
			grapple.apply_super_grapple()

	move_and_slide()

	if global_position.y < -20.0:
		respawn()

	var horizontal: float = Vector2(velocity.x, velocity.z).length()
	var ratio: float = clampf(horizontal / move_speed, 0.0, 2.0)
	var target_fov: float = _base_fov + maxf(ratio - 1.0, 0.0) * 14.0
	camera.fov = lerpf(camera.fov, target_fov, 8.0 * delta)


func _swing() -> void:
	# Placeholder melee: ray forward and push a RigidBody away.
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = camera.global_position
	var to: Vector3 = from - camera.global_transform.basis.z * 3.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return
	var body := hit.collider as RigidBody3D
	if body != null:
		body.apply_central_impulse(-camera.global_transform.basis.z * 8.0)


func respawn() -> void:
	global_position = _spawn
	velocity = Vector3.ZERO
	grapple.reset()
