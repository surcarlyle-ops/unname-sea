extends CharacterBody3D
## (CodeBuddy) Ruin Guardian — first mini-boss.
##
## The GLB ships one 4.93 s clip whose forward travel is baked into the `root` bone
## (1.0266 model units). Two ways to use it, and only one is correct in gameplay:
##
##   DriveMode.ANIMATION   the clip plays untouched, so the *mesh* slides forward
##                          while the collider stays put. Reference only.
##   DriveMode.ROOT_MOTION the same curve drives the CharacterBody3D while the model
##                          is counter-translated, so mesh and collider travel
##                          together and a wall actually stops the lunge.
##
## Never run both at once: that doubles the distance.
##
## Facing: this asset faces +Z (the lunge moves +Z), so "forward" here is
## `global_basis.z`, not Godot's usual `-global_basis.z`.

signal windup_started()
signal damage_window_opened()
signal damage_window_closed()
signal recovery_started()
signal attack_finished()

enum DriveMode { ANIMATION, ROOT_MOTION }

const MODEL_PATH: String = "res://assets/enemies/ruin_guardian/guardian_06_video_lunge_study.glb"
const CLIP_NAME: String = "guardian_video_lunge_study_NOT_GAMEPLAY"

## The source model is 0.80 units tall; 3.0 puts the guardian at ~2.4 m, which also
## turns the baked 1.0266 unit lunge into ~3.08 m of world travel.
const MODEL_SCALE: float = 3.0
const BODY_HEIGHT: float = 2.4
const BODY_RADIUS: float = 0.62

## Timing read off the baked root curve, not guessed:
##   0.00-0.53 step back · 0.53-2.77 crouch hold (telegraph) · 2.77-3.73 dash
##   3.73-4.93 recovery. The fist lands at the end of the fast phase, so only that
##   slice is a damage window — the whole clip is never a hitbox.
const DASH_WINDOW: Vector2 = Vector2(2.77, 3.73)
const DAMAGE_WINDOW: Vector2 = Vector2(3.22, 3.56)
## The hold is 2.24 s long, which is unreadable in play; it can be skipped from the
## front without touching the dash.
const SHORT_WINDUP_SKIP: float = 1.60

var drive_mode: int = DriveMode.ROOT_MOTION
var windup_skip: float = 0.0
var attacking: bool = false
var clip_length: float = 4.933
var travel_units: float = 0.0

var model: Node3D
var skeleton: Skeleton3D
var animation_player: AnimationPlayer

var _elapsed: float = 0.0
var _root_curve: PackedFloat32Array = PackedFloat32Array()
var _curve_start: float = 0.0
var _curve_step: float = 0.0
var _last_curve_value: float = 0.0
var _window_open: bool = false
var _recovery_sent: bool = false
var _spawn: Vector3 = Vector3.ZERO
var gravity: float = 22.0
var attack_speed: float = 1.0
var size_multiplier: float = 1.0
var root_motion_multiplier: float = 1.0
var _motion_animation: Animation
var _motion_track: int = -1


func _ready() -> void:
	_build_body()
	_load_model()
	_fix_materials()
	_extract_root_curve()
	mark_spawn()


## The GLB has two materials. Only the body has a texture; the joint covers added
## during the rebind (`RecessedJointBronze`) ship with none, so without this they
## render as flat white patches between the stone plates.
func _fix_materials() -> void:
	if model == null:
		return
	var joint: StandardMaterial3D = StandardMaterial3D.new()
	joint.albedo_color = Color("#6f5a3c")
	joint.roughness = 0.55
	joint.metallic = 0.35
	for child: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = child as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface: int in range(mesh_node.mesh.get_surface_count()):
			var material: Material = mesh_node.mesh.surface_get_material(surface)
			if material == null:
				continue
			var has_texture: bool = material is StandardMaterial3D and (material as StandardMaterial3D).albedo_texture != null
			if not has_texture:
				mesh_node.set_surface_override_material(surface, joint)


func _build_body() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.height = BODY_HEIGHT * size_multiplier
	capsule.radius = BODY_RADIUS * size_multiplier
	shape.shape = capsule
	shape.position = Vector3(0.0, BODY_HEIGHT * size_multiplier * 0.5, 0.0)
	add_child(shape)


func _load_model() -> void:
	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("RuinGuardian: model missing at " + MODEL_PATH)
		return
	model = packed.instantiate() as Node3D
	model.name = "Model"
	model.scale = Vector3.ONE * MODEL_SCALE * size_multiplier
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player != null and animation_player.has_animation(CLIP_NAME):
		animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var animation: Animation = animation_player.get_animation(CLIP_NAME)
		animation.loop_mode = Animation.LOOP_NONE
		clip_length = animation.length


## Sample the baked root translation once so it can be replayed on the body.
func _extract_root_curve() -> void:
	_root_curve.clear()
	if animation_player == null or not animation_player.has_animation(CLIP_NAME):
		return
	var animation: Animation = animation_player.get_animation(CLIP_NAME)
	var track: int = -1
	for t: int in range(animation.get_track_count()):
		if animation.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if str(animation.track_get_path(t)).contains("root"):
			track = t
			break
	if track < 0:
		return
	_motion_animation = animation
	_motion_track = track
	var keys: int = animation.track_get_key_count(track)
	_curve_start = animation.track_get_key_time(track, 0)
	_curve_step = (animation.track_get_key_time(track, keys - 1) - _curve_start) / float(maxi(keys - 1, 1))
	_root_curve.resize(keys)
	for k: int in range(keys):
		_root_curve[k] = animation.track_get_key_value(track, k).z
	travel_units = _root_curve[keys - 1] - _root_curve[0]


## Baked forward travel at a given clip time, in model units.
func curve_at(time: float) -> float:
	# Import optimization removes redundant keys; their times are not uniform.
	if _motion_animation != null and _motion_track >= 0:
		return _motion_animation.position_track_interpolate(_motion_track, time).z
	if _root_curve.is_empty():
		return 0.0
	var index: float = (time - _curve_start) / maxf(_curve_step, 0.0001)
	var low: int = clampi(int(floor(index)), 0, _root_curve.size() - 1)
	var high: int = clampi(low + 1, 0, _root_curve.size() - 1)
	return lerpf(_root_curve[low], _root_curve[high], clampf(index - float(low), 0.0, 1.0))


func set_drive_mode(mode: int) -> void:
	drive_mode = mode
	if model != null:
		model.position = Vector3.ZERO
	_last_curve_value = curve_at(_elapsed)


func play_attack() -> void:
	if animation_player == null or not animation_player.has_animation(CLIP_NAME):
		return
	attacking = true
	_elapsed = windup_skip
	_window_open = false
	_recovery_sent = false
	_last_curve_value = curve_at(_elapsed)
	animation_player.play(CLIP_NAME, 0.0)
	animation_player.seek(_elapsed, true)
	if drive_mode == DriveMode.ROOT_MOTION:
		model.position.z = -(curve_at(_elapsed) - curve_at(0.0)) * MODEL_SCALE * size_multiplier
	windup_started.emit()


func cancel_attack() -> void:
	attacking = false
	_window_open = false
	if animation_player != null:
		animation_player.stop()
	if model != null:
		model.position = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if not attacking:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return
	var previous: float = _elapsed
	_elapsed = minf(_elapsed + delta * attack_speed, clip_length)
	animation_player.seek(_elapsed, true)

	if drive_mode == DriveMode.ROOT_MOTION and not _root_curve.is_empty():
		var now: float = curve_at(_elapsed)
		var travel: float = (now - _last_curve_value) * MODEL_SCALE * size_multiplier * root_motion_multiplier
		_last_curve_value = now
		# Cancel the baked translation so the mesh stays on the collider, then push
		# the collider by the same amount. Doing one without the other is what makes
		# the model drift off its hitbox.
		model.position.z = -(now - curve_at(0.0)) * MODEL_SCALE * size_multiplier
		var horizontal: Vector3 = global_basis.z * (travel / maxf(delta, 0.0001))
		velocity.x = horizontal.x
		velocity.z = horizontal.z
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	_apply_gravity(delta)
	move_and_slide()

	_check_windows(previous, _elapsed)
	if _elapsed >= clip_length:
		attacking = false
		velocity.x = 0.0
		velocity.z = 0.0
		attack_finished.emit()


func _check_windows(previous: float, current: float) -> void:
	if not _window_open and current >= DAMAGE_WINDOW.x and previous < DAMAGE_WINDOW.x:
		_window_open = true
		damage_window_opened.emit()
	if _window_open and current >= DAMAGE_WINDOW.y:
		_window_open = false
		damage_window_closed.emit()
	if not _recovery_sent and current >= DASH_WINDOW.y:
		_recovery_sent = true
		recovery_started.emit()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * delta, -35.0)
	elif velocity.y < 0.0:
		velocity.y = 0.0


func damage_window_active() -> bool:
	return _window_open


func clip_time() -> float:
	return _elapsed


func mark_spawn() -> void:
	_spawn = global_position


## The baked lunge converted to metres at the current model scale.
func world_lunge() -> float:
	return absf(travel_units) * MODEL_SCALE * size_multiplier * root_motion_multiplier


func dash_window() -> Vector2:
	return DASH_WINDOW


func short_windup() -> float:
	return SHORT_WINDUP_SKIP


## Distance the collider has travelled from its spawn point, in metres.
func body_travel() -> float:
	return Vector2(global_position.x - _spawn.x, global_position.z - _spawn.z).length()


## How far the mesh has slid away from the collider. ~0 in root-motion mode, and it
## grows to the full lunge length in animation mode.
func mesh_drift() -> float:
	if skeleton == null or model == null:
		return 0.0
	var bone: int = skeleton.find_bone("root")
	if bone < 0:
		return 0.0
	var pose: Vector3 = skeleton.get_bone_pose_position(bone)
	var rest: Vector3 = skeleton.get_bone_rest(bone).origin
	var bone_drift: float = Vector2(pose.z - rest.z, pose.x - rest.x).length() * MODEL_SCALE * size_multiplier
	var counter: float = absf(model.position.z)
	return maxf(bone_drift - counter, 0.0)
