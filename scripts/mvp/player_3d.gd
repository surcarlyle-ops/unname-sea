extends CharacterBody3D
## Camera-relative movement and collision-safe dodge for the shore prototype.

signal returned_to_shore()
signal dodge_started()

@export var move_speed: float = 2.8
@export var acceleration: float = 22.0
@export var stopping_speed: float = 30.0
@export var dodge_speed: float = 11.5
@export var dodge_duration: float = 0.24
@export var dodge_cooldown: float = 0.85
@export var mouse_sensitivity: float = 0.0026

## Idle is a long Tripo clip (~15s); slice a short loop so the stance stays calm.
const IDLE_LOOP_SECONDS: float = 3.0

@onready var visual: Node3D = $Visual
@onready var animation_player: AnimationPlayer = $Visual/Model.find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var camera_yaw: Node3D = $CameraYaw
@onready var camera_pitch: Node3D = $CameraYaw/CameraPitch
@onready var spring_arm: SpringArm3D = $CameraYaw/CameraPitch/SpringArm3D
@onready var camera: Camera3D = $CameraYaw/CameraPitch/SpringArm3D/Camera3D

var controls_active: bool = true
var spawn_position: Vector3 = Vector3.ZERO
var dodge_time_left: float = 0.0
var cooldown_left: float = 0.0
var distance_walked: float = 0.0
var dodge_count: int = 0
var _dodge_direction: Vector3 = Vector3.FORWARD
var _current_animation: StringName = &""
var _gravity: float = 9.8


func _ready() -> void:
	spawn_position = global_position
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	spring_arm.add_excluded_object(get_rid())
	if animation_player != null:
		_prepare_animations()
	set_controls_active(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		set_controls_active(not controls_active)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed and not controls_active:
			set_controls_active(true)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and controls_active:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		rotate_camera(motion.relative)
	if event.is_action_pressed("mvp_reset"):
		reset_to_spawn()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		set_controls_active(false)


func _prepare_animations() -> void:
	var idle: Animation = animation_player.get_animation(&"idle")
	if idle != null and idle.length > IDLE_LOOP_SECONDS:
		_trim_animation(idle, IDLE_LOOP_SECONDS)
	var walk: Animation = animation_player.get_animation(&"walk")
	if walk != null:
		walk.loop_mode = Animation.LOOP_LINEAR
	for anim_name: StringName in [&"idle", &"walk"]:
		var anim: Animation = animation_player.get_animation(anim_name)
		if anim != null:
			_fix_torso_rotation(anim)


func _fix_torso_rotation(anim: Animation) -> void:
	# Tripo/Mixamo export leaves extra Y/Z twist on the spine chain and neck.
	# Flatten those axes so the torso stands upright.
	# Hips is intentionally untouched: its -90 deg Y is the Mixamo basis, not an error.
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var track_path: String = str(anim.track_get_path(t)).to_lower()
		var is_torso: bool = false
		for part: String in ["spine", "neck"]:
			if track_path.contains(part):
				is_torso = true
				break
		if not is_torso:
			continue
		var key_count: int = anim.track_get_key_count(t)
		for k in range(key_count):
			var q: Quaternion = anim.track_get_key_value(t, k)
			var e: Vector3 = q.get_euler()
			e.y = 0.0
			e.z = 0.0
			anim.track_set_key_value(t, k, Quaternion.from_euler(e))


func _trim_animation(anim: Animation, new_length: float) -> void:
	# Drop keys past new_length, then shorten the clip so it loops in place.
	for i in range(anim.get_track_count()):
		var key_count: int = anim.track_get_key_count(i)
		var keep: int = 0
		for k in range(key_count):
			if anim.track_get_key_time(i, k) <= new_length:
				keep = k
			else:
				break
		while anim.track_get_key_count(i) > keep + 1:
			anim.track_remove_key(i, anim.track_get_key_count(i) - 1)
	anim.length = new_length
	anim.loop_mode = Animation.LOOP_LINEAR


func set_controls_active(active: bool) -> void:
	controls_active = active
	if not active:
		dodge_time_left = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE


func rotate_camera(relative: Vector2) -> void:
	camera_yaw.rotation.y -= relative.x * mouse_sensitivity
	camera_pitch.rotation.x = clampf(
		camera_pitch.rotation.x - relative.y * mouse_sensitivity, -0.95, 0.3
	)


func _physics_process(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	dodge_time_left = maxf(dodge_time_left - delta, 0.0)
	var direction: Vector3 = Vector3.ZERO
	if controls_active:
		var axes: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		direction = camera_yaw.basis * Vector3(axes.x, 0.0, axes.y)
		if Input.is_action_just_pressed("mvp_dodge"):
			try_dodge(direction)
	var desired: Vector3 = direction * move_speed
	if dodge_time_left > 0.0:
		desired = _dodge_direction * dodge_speed
		velocity.x = desired.x
		velocity.z = desired.z
	else:
		var rate: float = acceleration if direction.length_squared() > 0.01 else stopping_speed
		velocity.x = move_toward(velocity.x, desired.x, rate * delta)
		velocity.z = move_toward(velocity.z, desired.z, rate * delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	var previous: Vector3 = global_position
	move_and_slide()
	distance_walked += Vector2(global_position.x - previous.x, global_position.z - previous.z).length()
	_update_visual(delta)
	if global_position.y < -1.2:
		reset_to_spawn()
		returned_to_shore.emit()


func try_dodge(direction: Vector3) -> bool:
	if not controls_active or not is_on_floor() or cooldown_left > 0.0:
		return false
	_dodge_direction = direction.normalized() if direction.length_squared() > 0.01 else -visual.basis.z
	_dodge_direction.y = 0.0
	dodge_time_left = dodge_duration
	cooldown_left = dodge_cooldown
	dodge_count += 1
	dodge_started.emit()
	return true


func reset_to_spawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	dodge_time_left = 0.0
	cooldown_left = 0.0
	camera_yaw.rotation.y = 0.0
	camera_pitch.rotation.x = -0.15
	visual.rotation = Vector3.ZERO
	spring_arm.force_update_transform()


func _update_visual(delta: float) -> void:
	# Keep the view clear when an obstacle forces the camera into the avatar.
	visual.visible = spring_arm.get_hit_length() > 1.75
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() > 0.1:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-horizontal.x, -horizontal.z), 14.0 * delta)
	if animation_player != null:
		var next_animation: StringName = &"idle"
		if dodge_time_left > 0.0:
			next_animation = &"dodge"
		elif horizontal.length() > 3.0:
			next_animation = &"run"
		elif horizontal.length() > 0.1:
			next_animation = &"walk"
		# Use the supplied walking clip until dedicated run/dodge clips are added.
		if not animation_player.has_animation(next_animation):
			next_animation = &"walk" if horizontal.length() > 0.1 and animation_player.has_animation(&"walk") else &"idle"
		if next_animation != _current_animation:
			animation_player.play(next_animation, 0.12)
			_current_animation = next_animation
		if next_animation in [&"run", &"walk"]:
			animation_player.speed_scale = clampf(horizontal.length() / move_speed, 0.6, 1.6)
		else:
			animation_player.speed_scale = 1.0
	visual.rotation.x = move_toward(visual.rotation.x, 0.15 if dodge_time_left > 0.0 else 0.0, delta * 5.0)
