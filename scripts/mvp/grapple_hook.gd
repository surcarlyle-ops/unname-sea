extends Node3D
class_name GrappleHook
## Standalone APEX-style grapple hook.
## Attach as a child of a CharacterBody3D; while attached it drives the body's velocity.
## It never touches other player logic, so it can be merged without conflicts.
##
## v0.1 "初版钩爪" — 2026-10-20
## 21 m reach, pendulum swing (radial pull + tangential momentum preserved),
## super grapple, crosshair-ready can_attach(), developer mode disables cooldown.

signal attached(point: Vector3)
signal released()
signal attach_failed()

enum State { IDLE, ATTACHED, COOLDOWN }

@export_group("Range")
## Maximum reach, matching APEX Pathfinder's 21 m.
@export var max_range: float = 21.0
## Distance at which the hook auto-releases.
@export var auto_release_distance: float = 2.0

@export_group("Pull")
## Radial speed right after the bite on a point-blank grapple.
@export var pull_speed_start_near: float = 8.1
## Radial speed right after the bite on a max-range grapple (slow start).
@export var pull_speed_start_far: float = 5.2
## Hard cap for the radial pull speed.
@export var pull_speed_max: float = 18.0
## Seconds to ramp from start to max (longer = more gradual acceleration).
@export var pull_accel_duration: float = 0.86
## Tension delay before the pull starts, same for every distance (APEX-style hang).
@export var pull_delay_near: float = 0.08
## Tension delay before the pull starts, same for every distance.
@export var pull_delay_far: float = 0.08
## How quickly the radial speed approaches its current target.
@export var pull_sharpness: float = 8.0
## Slow down when close to the anchor so the player does not slam into it.
@export var arrival_soften_distance: float = 4.0

@export_group("Swing")
## Rope stiffness when taut.
@export var swing_stiffness: float = 14.0
## Velocity damping while attached, stops endless oscillation.
@export var swing_damping: float = 1.2
## Lateral force from A/D while attached (APEX-style sideways swing).
@export var swing_side_force: float = 9.0

@export_group("Super Grapple")
## Forward impulse granted by jumping right after attaching.
@export var super_grapple_impulse: float = 7.0
## Time window after attach in which the jump counts as a super grapple.
@export var super_grapple_window: float = 0.35

@export_group("Cooldown")
## Cooldown for the shortest possible grapple.
@export var min_cooldown: float = 10.0
## Cooldown for a full 21 m grapple.
@export var max_cooldown: float = 30.0
## Developer mode: skip cooldown so the hook can be fired again immediately.
## Set to false before shipping.
@export var disable_cooldown: bool = true

var state: State = State.IDLE
var anchor: Vector3 = Vector3.ZERO
var rope_length: float = 0.0
var cooldown_left: float = 0.0
var last_cooldown: float = 0.0

## Optional override for the desired swing direction (world space), set by a controller.
## When disabled, the hook reads WASD relative to the camera.
var use_wish_override: bool = false
var wish_direction_override: Vector3 = Vector3.ZERO

var _body: CharacterBody3D
var _camera: Camera3D
var _super_window_left: float = 0.0
var _attach_time: float = 0.0
var _rope_mesh: MeshInstance3D
var _hook_head: Node3D


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_error("GrappleHook must be a child of a CharacterBody3D")
		return
	_build_rope_visual()
	_build_hook_head()


func _physics_process(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = maxf(cooldown_left - delta, 0.0)
		if state == State.COOLDOWN and cooldown_left <= 0.0:
			state = State.IDLE

	_super_window_left = maxf(_super_window_left - delta, 0.0)

	if state != State.ATTACHED or _body == null:
		_update_rope_visual(false)
		return

	var to_anchor: Vector3 = anchor - _body.global_position
	var distance: float = to_anchor.length()

	if distance <= auto_release_distance:
		release()
		return

	var direction: Vector3 = to_anchor / maxf(distance, 0.001)

	# Split velocity into radial (along the rope) and tangential (the swing).
	# Pulling only the radial part preserves tangential momentum, which is what
	# turns the hook into a pendulum instead of a straight zip to the anchor.
	var radial_speed: float = _body.velocity.dot(direction)
	var tangential: Vector3 = _body.velocity - direction * radial_speed

	# Pull: close grapples skip the slow start; long ones ease in.
	# rope_length is fixed at attach time, so the curve matches the shot distance.
	var distance_ratio: float = clampf(rope_length / maxf(max_range, 0.001), 0.0, 1.0)
	var active_delay: float = lerpf(pull_delay_near, pull_delay_far, distance_ratio)
	var active_start: float = lerpf(pull_speed_start_near, pull_speed_start_far, distance_ratio)
	_attach_time += delta
	var ramp: float = clampf((_attach_time - active_delay) / maxf(pull_accel_duration, 0.01), 0.0, 1.0)
	var target_radial: float = lerpf(active_start, pull_speed_max, ramp * ramp)
	if distance < arrival_soften_distance:
		target_radial *= clampf(distance / maxf(arrival_soften_distance, 0.01), 0.3, 1.0)
	var blend: float = clampf(pull_sharpness * delta, 0.0, 1.0)
	radial_speed = lerpf(radial_speed, target_radial, blend)

	# Swing: WASD adds force on the tangent plane only, so input steers the arc
	# without pulling the player off it.
	var wish: Vector3 = _read_wish_direction()
	if wish.length_squared() > 0.0001:
		var tangential_wish: Vector3 = wish - direction * wish.dot(direction)
		if tangential_wish.length_squared() > 0.0001:
			tangential += tangential_wish.normalized() * swing_side_force * delta

	# Damp only the swing so the pendulum settles without killing the pull.
	tangential *= 1.0 - clampf(swing_damping * delta, 0.0, 0.5)

	# Reassemble the velocity.
	_body.velocity = direction * radial_speed + tangential

	# Rope constraint: never stretch past rope_length, and a rope cannot push.
	if distance > rope_length:
		var overshoot: float = distance - rope_length
		_body.velocity -= direction * overshoot * swing_stiffness * delta
		var outward: float = _body.velocity.dot(direction)
		if outward < 0.0:
			_body.velocity -= direction * outward

	_update_rope_visual(true)


## True when the hook could attach right now. Used by the crosshair every frame.
func can_attach() -> bool:
	if state != State.IDLE or _body == null:
		return false
	return not _raycast_anchor().is_empty()


## Fire the hook toward the camera's forward direction. Returns true on hit.
func try_attach() -> bool:
	if state != State.IDLE:
		return false
	var hit: Dictionary = _raycast_anchor()
	if hit.is_empty():
		attach_failed.emit()
		return false

	anchor = hit.position as Vector3
	rope_length = maxf(_camera.global_position.distance_to(anchor), auto_release_distance + 0.5)
	state = State.ATTACHED
	_super_window_left = super_grapple_window
	_attach_time = 0.0
	attached.emit(anchor)
	return true


## APEX "super grapple": jumping right after attaching adds forward momentum.
func apply_super_grapple() -> bool:
	if state != State.ATTACHED or _super_window_left <= 0.0:
		return false
	if _body == null or _camera == null:
		return false
	var forward: Vector3 = -_camera.global_transform.basis.z
	_body.velocity += forward * super_grapple_impulse
	_super_window_left = 0.0
	return true


## Let go and keep the current momentum. Cooldown scales with travel distance.
func release() -> void:
	if state != State.ATTACHED:
		return
	_update_rope_visual(false)
	if disable_cooldown:
		# Developer mode: no cooldown, ready to fire again immediately.
		last_cooldown = 0.0
		cooldown_left = 0.0
		state = State.IDLE
	else:
		var ratio: float = clampf(rope_length / maxf(max_range, 0.001), 0.0, 1.0)
		last_cooldown = lerpf(min_cooldown, max_cooldown, ratio)
		cooldown_left = last_cooldown
		state = State.COOLDOWN
	released.emit()


## Reset to a clean idle state (call on death / respawn).
func reset() -> void:
	state = State.IDLE
	cooldown_left = 0.0
	anchor = Vector3.ZERO
	rope_length = 0.0
	_super_window_left = 0.0
	_attach_time = 0.0
	_update_rope_visual(false)


func is_attached() -> bool:
	return state == State.ATTACHED


func is_ready() -> bool:
	return state == State.IDLE


## 0..1 cooldown progress, handy for HUD.
func cooldown_ratio() -> float:
	if last_cooldown <= 0.0:
		return 0.0
	return clampf(cooldown_left / last_cooldown, 0.0, 1.0)


func _read_wish_direction() -> Vector3:
	if use_wish_override:
		return wish_direction_override
	if _camera == null:
		return Vector3.ZERO
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var cam_basis: Basis = _camera.global_transform.basis
	return cam_basis.x * input.x + cam_basis.z * input.y


func _raycast_anchor() -> Dictionary:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
	if _camera == null or _body == null:
		return {}
	var from: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_transform.basis.z
	var to: Vector3 = from + forward * max_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_body.get_rid()]
	query.collide_with_areas = false
	return _body.get_world_3d().direct_space_state.intersect_ray(query)


func _build_rope_visual() -> void:
	_rope_mesh = MeshInstance3D.new()
	var rope := CylinderMesh.new()
	rope.top_radius = 0.025
	rope.bottom_radius = 0.025
	rope.height = 1.0
	rope.radial_segments = 6
	rope.rings = 1
	_rope_mesh.mesh = rope
	_rope_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.35, 0.8, 1.0)
	_rope_mesh.material_override = material
	_rope_mesh.top_level = true
	_rope_mesh.visible = false
	add_child(_rope_mesh)


func _build_hook_head() -> void:
	_hook_head = Node3D.new()
	_hook_head.top_level = true
	_hook_head.visible = false
	add_child(_hook_head)
	for i in range(3):
		var claw := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.05
		cone.height = 0.3
		cone.radial_segments = 6
		claw.mesh = cone
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.95, 0.98, 1.0)
		claw.material_override = material
		var angle: float = TAU * float(i) / 3.0
		claw.position = Vector3(cos(angle) * 0.1, 0.0, sin(angle) * 0.1)
		claw.rotation = Vector3(0.5, -angle, 0.0)
		_hook_head.add_child(claw)


func _update_rope_visual(visible_now: bool) -> void:
	if _rope_mesh == null or _hook_head == null:
		return
	if not visible_now or _body == null or _camera == null:
		_rope_mesh.visible = false
		_hook_head.visible = false
		return

	var cam_basis: Basis = _camera.global_transform.basis
	var start: Vector3 = _camera.global_position + cam_basis.x * 0.28 - cam_basis.y * 0.22 - cam_basis.z * 0.3
	var delta: Vector3 = anchor - start
	var length: float = delta.length()
	if length < 0.05:
		_rope_mesh.visible = false
		_hook_head.visible = false
		return

	var up: Vector3 = delta / length
	var right: Vector3 = up.cross(Vector3.FORWARD)
	if right.length_squared() < 0.0001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward: Vector3 = right.cross(up).normalized()
	var rope_basis := Basis(right, up, forward)
	var mid: Vector3 = (start + anchor) * 0.5

	_rope_mesh.visible = true
	_rope_mesh.global_transform = Transform3D(rope_basis, mid).scaled_local(Vector3(1.0, length, 1.0))

	_hook_head.visible = true
	_hook_head.global_position = anchor
