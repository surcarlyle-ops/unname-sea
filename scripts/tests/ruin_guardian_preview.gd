extends Node3D
## (CodeBuddy) Standalone test for the Ruin Guardian. Not wired into the main game.
##
## What it verifies:
##   1. the clip plays once at its original speed, loop off;
##   2. whether the collider and the mesh stay together (root-motion vs raw clip);
##   3. the lunge on open ground and against a wall;
##   4. windup / damage window / recovery, and a dodge that can beat it.
##
## Controls: 1 attack · 2 toggle motion mode · 3 toggle short windup · 4 toggle 0.35x
##           speed · WASD move · Space dodge · R reset · mouse drag orbit · Esc release

const GUARDIAN_SCRIPT: Script = preload("res://scripts/enemies/ruin_guardian.gd")

const PLAYER_SPEED: float = 3.6
const DODGE_SPEED: float = 11.0
const DODGE_TIME: float = 0.28
const DODGE_IFRAMES: float = 0.34
const HIT_RADIUS: float = 1.9
const HIT_FORWARD: float = 1.5

var guardian: CharacterBody3D
var player: CharacterBody3D
var camera: Camera3D
var hud: Label

var _yaw: float = 0.6
var _pitch: float = -0.22
var _distance: float = 8.5
## Height of the camera's look-at point; lowered for the feet check.
var _focus_height: float = 1.3
var _slow: bool = false
var _dodge_time: float = -1.0
var _hit_count: int = 0
var _dodge_count: int = 0
var _last_event: String = "-"
var _hit_this_swing: bool = false
var _wall_body: StaticBody3D
var _wall_mesh: MeshInstance3D
var _wall_on: bool = false


func _ready() -> void:
	_build_environment()
	_build_ground_and_wall()
	_build_guardian()
	_build_player()
	_build_camera()
	_build_hud()
	guardian.damage_window_opened.connect(_on_damage_window_opened)
	guardian.attack_finished.connect(func() -> void: _hit_this_swing = false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#4d5c78")
	sky_material.sky_horizon_color = Color("#b8b0b4")
	sky_material.ground_bottom_color = Color("#31353c")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.55
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, -35.0, 0.0)
	sun.light_color = Color("#ffe8cf")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)


func _build_ground_and_wall() -> void:
	var ground_body: StaticBody3D = StaticBody3D.new()
	ground_body.name = "Ground"
	ground_body.collision_layer = 1
	var ground_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	ground_shape.shape = box
	ground_shape.position = Vector3(0.0, -0.5, 0.0)
	ground_body.add_child(ground_shape)
	add_child(ground_body)
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("#6a6f66")
	material.roughness = 0.95
	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = material
	add_child(ground)

	# The wall sits just past the full lunge, and is toggled off by default so the
	# open-ground travel can be measured first. With it on, travel must come up short.
	_wall_body = StaticBody3D.new()
	_wall_body.name = "Wall"
	_wall_body.collision_layer = 1
	var wall_shape: CollisionShape3D = CollisionShape3D.new()
	var wall_box: BoxShape3D = BoxShape3D.new()
	wall_box.size = Vector3(8.0, 3.0, 0.6)
	wall_shape.shape = wall_box
	_wall_body.position = Vector3(0.0, 1.5, 3.4)
	_wall_body.add_child(wall_shape)
	add_child(_wall_body)
	var wall_mesh: BoxMesh = BoxMesh.new()
	wall_mesh.size = Vector3(8.0, 3.0, 0.6)
	var wall_material: StandardMaterial3D = StandardMaterial3D.new()
	wall_material.albedo_color = Color("#8a8578")
	_wall_mesh = MeshInstance3D.new()
	_wall_mesh.mesh = wall_mesh
	_wall_mesh.material_override = wall_material
	_wall_mesh.position = Vector3(0.0, 1.5, 3.4)
	add_child(_wall_mesh)
	_set_wall(false)


func _set_wall(value: bool) -> void:
	_wall_on = value
	if _wall_body != null:
		_wall_body.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
		_wall_body.collision_layer = 1 if value else 0
	if _wall_mesh != null:
		_wall_mesh.visible = value


func _build_guardian() -> void:
	guardian = CharacterBody3D.new()
	guardian.name = "Guardian"
	guardian.set_script(GUARDIAN_SCRIPT)
	add_child(guardian)
	guardian.global_position = Vector3(0.0, 0.0, 0.0)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "PlayerStandIn"
	player.collision_layer = 4
	player.collision_mask = 1
	var shape: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.height = 1.75
	capsule.radius = 0.35
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.875, 0.0)
	player.add_child(shape)
	var body_mesh: CapsuleMesh = CapsuleMesh.new()
	body_mesh.height = 1.75
	body_mesh.radius = 0.35
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("#d9a35e")
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = body_mesh
	mesh.material_override = material
	mesh.position = Vector3(0.0, 0.875, 0.0)
	player.add_child(mesh)
	add_child(player)
	player.global_position = Vector3(0.0, 0.0, 2.2)


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
	hud.position = Vector2(24.0, 18.0)
	hud.add_theme_color_override("font_color", Color(0.96, 0.95, 0.98))
	hud.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.85))
	hud.add_theme_constant_override("outline_size", 5)
	hud.add_theme_font_size_override("font_size", 14)
	layer.add_child(hud)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.004, -1.1, 0.4)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance - 0.8, 3.0, 18.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance + 0.8, 3.0, 18.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_1:
				_hit_this_swing = false
				guardian.play_attack()
			KEY_2:
				guardian.set_drive_mode(
					0 if guardian.drive_mode == 1 else 1)
				_last_event = "motion: " + ("animation drives mesh" if guardian.drive_mode == 0 else "root motion drives body")
			KEY_3:
				guardian.windup_skip = 0.0 if guardian.windup_skip > 0.0 else guardian.short_windup()
				_last_event = "windup skip: %.1fs" % guardian.windup_skip
			KEY_4:
				_slow = not _slow
				Engine.time_scale = 0.35 if _slow else 1.0
				_last_event = "speed: 0.35x" if _slow else "speed: 1.0x"
			KEY_5:
				_set_wall(not _wall_on)
				_last_event = "wall on" if _wall_on else "wall off"
			KEY_SPACE:
				_start_dodge()
			KEY_R:
				Engine.time_scale = 1.0
				_slow = false
				guardian.cancel_attack()
				guardian.global_position = Vector3.ZERO
				guardian.rotation.y = 0.0
				guardian.mark_spawn()
				player.global_position = Vector3(0.0, 0.0, 3.4)
				_hit_count = 0
				_dodge_count = 0
				_last_event = "reset"
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _start_dodge() -> void:
	if _dodge_time >= 0.0:
		return
	_dodge_time = 0.0
	_dodge_count += 1
	_last_event = "dodge"


func _process(delta: float) -> void:
	_update_player(delta)
	_update_camera()
	_update_hud()


func _update_player(delta: float) -> void:
	var move: Vector2 = Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	var basis: Basis = Basis(Vector3.UP, _yaw)
	var direction: Vector3 = basis * Vector3(move.x, 0.0, move.y)
	if direction.length() > 1.0:
		direction = direction.normalized()
	var velocity: Vector3 = direction * PLAYER_SPEED
	if _dodge_time >= 0.0:
		_dodge_time += delta
		var away: Vector3 = (player.global_position - guardian.global_position)
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.BACK
		velocity = away * DODGE_SPEED
		if _dodge_time >= DODGE_TIME:
			_dodge_time = -1.0
	player.velocity = velocity
	player.move_and_slide()


func _update_camera() -> void:
	if camera == null or guardian == null:
		return
	var focus: Vector3 = guardian.global_position + Vector3(0.0, _focus_height, 0.6)
	var offset: Vector3 = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * Vector3(0.0, 0.0, _distance)
	camera.global_position = focus + offset
	camera.look_at(focus, Vector3.UP)


func _on_damage_window_opened() -> void:
	if _hit_this_swing:
		return
	var reach: Vector3 = guardian.global_position + guardian.global_basis.z * HIT_FORWARD + Vector3(0.0, 1.0, 0.0)
	var distance: float = reach.distance_to(player.global_position + Vector3(0.0, 1.0, 0.0))
	if distance > HIT_RADIUS:
		return
	if _dodge_time >= 0.0 and _dodge_time <= DODGE_IFRAMES:
		_last_event = "DODGED (i-frames)"
		return
	_hit_this_swing = true
	_hit_count += 1
	_last_event = "HIT"


func _update_hud() -> void:
	if hud == null or guardian == null:
		return
	var state: String = "idle"
	var dash: Vector2 = guardian.dash_window()
	if guardian.attacking:
		var t: float = guardian.clip_time()
		if t < dash.x:
			state = "windup"
		elif t < dash.y:
			state = "dash"
		else:
			state = "recovery"
		if guardian.damage_window_active():
			state += "  [DAMAGE WINDOW]"
	var mode: String = "animation -> mesh only" if guardian.drive_mode == 0 else "root motion -> body"
	hud.text = "遗迹守卫 · 独立测试\nmode: %s   wall: %s   windup skip: %.1fs   time_scale: %.2f\nstate: %s   clip t=%.2f / %.2fs\nbody travel: %.2f m   mesh drift: %.2f m   lunge: %.2f m\nhits: %d   dodges: %d   last: %s\n\n1 攻击 · 2 位移归属 · 3 短前摇 · 4 0.35x · 5 墙 · WASD 移动 · 空格 闪避 · R 重置" % [
		mode, "on" if _wall_on else "off", guardian.windup_skip, Engine.time_scale,
		state, guardian.clip_time(), guardian.clip_length,
		guardian.body_travel(), guardian.mesh_drift(), guardian.world_lunge(),
		_hit_count, _dodge_count, _last_event]
