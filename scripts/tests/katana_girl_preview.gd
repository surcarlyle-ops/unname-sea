extends Node3D
## (CodeBuddy) Standalone preview for the CombatGirls katana character.
## Not part of the main game: it exists to check the import, the clip merge, the
## material bindings and the attack chain before any of it touches combat_mvp.
##
## Controls: WASD move · Shift walk · mouse drag orbit · wheel zoom
##           LMB attack combo · 1/2/3 single attack · 4 skill · Tab outfit
##           F face · R reset · Esc release mouse

const GIRL_SCRIPT: Script = preload("res://scripts/characters/katana_girl.gd")

const WALK_SPEED: float = 1.35
const RUN_SPEED: float = 4.2
const TURN_SPEED: float = 12.0
## The pack is authored facing -Z; flip here if the model turns out backwards.
const MODEL_YAW_OFFSET: float = 0.0

var girl: Node3D
var camera: Camera3D
var hud: Label

var _yaw: float = 0.35
var _pitch: float = -0.18
var _distance: float = 3.6
## Height of the camera's look-at point above the character's feet.
var _focus_height: float = 1.05
var _attack_elapsed: float = -1.0
var _attack_length: float = 0.0
var _combo_step: int = 0
var _combo_queued: bool = false
var _attack_locked: bool = false
var _velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	_build_environment()
	_build_ground()
	girl = Node3D.new()
	girl.name = "KatanaGirl"
	girl.set_script(GIRL_SCRIPT)
	add_child(girl)
	_build_camera()
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh_hud()


func _build_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#5b6b86")
	sky_material.sky_horizon_color = Color("#c9b9bd")
	sky_material.ground_bottom_color = Color("#3a3f47")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.6
	environment.ambient_light_energy = 0.55
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.95
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	sun.light_color = Color("#fff0dd")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 140.0, 0.0)
	fill.light_color = Color("#9fb4d8")
	fill.light_energy = 0.45
	add_child(fill)


func _build_ground() -> void:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("#6d7268")
	material.roughness = 0.95
	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.material_override = material
	add_child(ground)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 200.0
	add_child(camera)
	_update_camera()


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(24.0, 20.0)
	hud.add_theme_color_override("font_color", Color(0.95, 0.94, 0.97))
	hud.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.07, 0.8))
	hud.add_theme_constant_override("outline_size", 5)
	hud.add_theme_font_size_override("font_size", 15)
	layer.add_child(hud)


func _refresh_hud() -> void:
	if hud == null or girl == null:
		return
	hud.text = "剑姬预览\nclips: %d   outfit: %s   face: %d/%d\nWASD 移动 · Shift 走 · 左键连招 · 1/2/3 单段 · 4 技能 · Tab 换装 · F 换脸 · R 重置" % [
		girl.clip_names.size(), girl.outfit, girl.face_index, girl.face_count()]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch - event.relative.y * 0.004, -0.9, 0.55)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_request_attack()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance - 0.3, 1.6, 9.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance + 0.3, 1.6, 9.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_1:
				_play_attack(1)
			KEY_2:
				_play_attack(2)
			KEY_3:
				_play_attack(3)
			KEY_4:
				_play_attack(0)
			KEY_TAB:
				girl.set_outfit("sportswear" if girl.outfit == "uniform" else "uniform")
				_refresh_hud()
			KEY_F:
				girl.set_face(girl.face_index % maxi(girl.face_count(), 1) + 1)
				_refresh_hud()
			KEY_R:
				girl.position = Vector3.ZERO
				girl.rotation.y = 0.0
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _request_attack() -> void:
	if _attack_locked:
		_combo_queued = true
		return
	_combo_step = 1
	_play_attack(1)


func _play_attack(step: int) -> void:
	# step 0 is the special skill clip.
	var clip: String = "skill1" if step == 0 else "attack%d" % step
	if not girl.animation_player.has_animation(clip):
		return
	_attack_length = girl.play_once(clip)
	_attack_elapsed = 0.0
	_attack_locked = true
	_combo_queued = false
	_combo_step = step


func _process(delta: float) -> void:
	if girl == null:
		return
	_update_attack(delta)
	_update_movement(delta)
	_update_camera()


func _update_attack(delta: float) -> void:
	if not _attack_locked:
		return
	_attack_elapsed += delta
	# Chain into the next hit near the end of the current swing if the player
	# clicked again while it was running.
	if _combo_queued and _combo_step > 0 and _combo_step < 3 and _attack_elapsed > _attack_length * 0.55:
		_play_attack(_combo_step + 1)
		return
	if _attack_elapsed >= _attack_length:
		_attack_locked = false
		_attack_elapsed = -1.0
		_combo_queued = false
		_combo_step = 0
		girl.play("idle", 0.18)


func _update_movement(delta: float) -> void:
	var input: Vector2 = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up"))
	# The preview should still work when the project input map is not loaded.
	if input == Vector2.ZERO:
		input = Vector2(
			float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	var walking: bool = Input.is_key_pressed(KEY_SHIFT)
	if _attack_locked:
		input = Vector2.ZERO
	var camera_basis: Basis = Basis(Vector3.UP, _yaw)
	var direction: Vector3 = camera_basis * Vector3(input.x, 0.0, input.y)
	if direction.length() > 1.0:
		direction = direction.normalized()
	var speed: float = WALK_SPEED if walking else RUN_SPEED
	_velocity = direction * speed
	girl.position += _velocity * delta
	girl.position.x = clampf(girl.position.x, -18.0, 18.0)
	girl.position.z = clampf(girl.position.z, -18.0, 18.0)
	if direction.length_squared() > 0.001:
		var target_yaw: float = atan2(direction.x, direction.z) + MODEL_YAW_OFFSET
		girl.rotation.y = lerp_angle(girl.rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))
		if not _attack_locked:
			var clip: String = "walk" if walking else "run"
			girl.play(clip, 0.15)
			# Match playback rate to speed so the feet do not skate.
			var target_speed: float = WALK_SPEED if walking else RUN_SPEED
			var natural: float = target_speed
			girl.animation_player.speed_scale = clampf(_velocity.length() / maxf(natural, 0.1), 0.6, 1.4)
	elif not _attack_locked:
		girl.play("idle", 0.2)
		girl.animation_player.speed_scale = 1.0


func _update_camera() -> void:
	if camera == null or girl == null:
		return
	var focus: Vector3 = girl.global_position + Vector3(0.0, _focus_height, 0.0)
	var offset: Vector3 = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * Vector3(0.0, 0.0, _distance)
	camera.global_position = focus + offset
	camera.look_at(focus, Vector3.UP)
