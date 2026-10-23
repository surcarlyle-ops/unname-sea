extends Node3D
## A repeatable combat slice, separate from the legacy shore and fishing prototype.

const PLAYER_SCENE: PackedScene = preload("res://scenes/mvp/first_person_player.tscn")
const ENEMY_SCRIPT: Script = preload("res://scripts/mvp/melee_enemy.gd")
const HUD_SCRIPT: Script = preload("res://scripts/mvp/combat_hud.gd")
const COURSE_SCRIPT: Script = preload("res://scripts/mvp/movement_course.gd")
const RUINS_SCENE: PackedScene = preload("res://assets/environments/portal_ruins/portal_ruins_sample.glb")
## 遗迹偏移：已按地形扫描反算，让最平坦的草地正好落在训练场原点。
## 原偏移 (20,110,-640) 下平坦区在世界 (4,36.5,-162)，故新偏移 = 旧偏移 - 该点 + (0,1,0)。
const RUINS_OFFSET: Vector3 = Vector3(16.0, 72.5, -478.0)

var player: CharacterBody3D
var hud: Control
var enemies: Node3D
var tuning: Dictionary
var course: Node3D
var mode: int = 0
var defeated_count: int = 0
var round_total: int = 0
var round_complete: bool = false
var notice: String = ""
var notice_time: float = 0.0
var _sounds: Dictionary = {}
var _audio: Array[AudioStreamPlayer] = []
var _audio_index: int = 0


func _ready() -> void:
	tuning = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat_mvp.json")) as Dictionary
	_build_world()
	player = PLAYER_SCENE.instantiate() as CharacterBody3D
	player.position = _vector(tuning.arena.spawn)
	add_child(player)
	player.retry_requested.connect(restart_round)
	player.loadout_requested.connect(_toggle_loadout)
	player.notice_requested.connect(show_notice)
	player.attack_started.connect(func() -> void: _sound("swing"))
	player.melee_hit.connect(func(_target: Node3D) -> void: _sound("hit"))
	player.movement_sound.connect(func(sound_name: String, strength: float) -> void: _sound(sound_name, strength))
	player.wave_released.connect(func() -> void: _sound("wave"))
	player.health_changed.connect(func(_value: int) -> void:
		if player.hurt_time_left > 0.0:
			_sound("hurt")
	)
	enemies = Node3D.new()
	enemies.name = "Enemies"
	add_child(enemies)
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_script(HUD_SCRIPT)
	hud.arena = self
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(hud)
	_build_audio()
	start_round(2)
	# Give the player time to read the controls before enemies advance.
	player.set_controls_active(false)


func _process(delta: float) -> void:
	notice_time = maxf(0.0, notice_time - delta)


func _exit_tree() -> void:
	for voice: AudioStreamPlayer in _audio:
		voice.stop()
		voice.stream = null
	_sounds.clear()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F:
			start_round(0)
		elif event.physical_keycode == KEY_G:
			start_round(1)
		elif event.physical_keycode == KEY_H:
			start_round(2)


func start_round(next_mode: int) -> void:
	mode = clampi(next_mode, 0, 2)
	for old_enemy: Node in enemies.get_children():
		enemies.remove_child(old_enemy)
		old_enemy.queue_free()
	defeated_count = 0
	round_complete = false
	player.spawn_position = _vector(tuning.arena.movement_spawn if mode == 2 else tuning.arena.spawn)
	player.reset_to_spawn()
	course.reset()
	hud.close_loadout()
	var positions: Array = [] if mode == 2 else (tuning.arena.swarm_spawns if mode == 0 else tuning.arena.mobility_spawns)
	round_total = positions.size()
	for point: Array in positions:
		var enemy: CharacterBody3D = CharacterBody3D.new()
		enemy.set_script(ENEMY_SCRIPT)
		enemy.target = player
		enemy.tuning = tuning.enemy
		enemy.stats = GameData.get_monster(str(tuning.enemy.source_id))
		enemy.position = _vector(point)
		enemy.defeated.connect(_on_enemy_defeated)
		enemies.add_child(enemy)
	show_notice("清怪试炼：用横扫同时命中多个敌人" if mode == 0 else ("机动试炼：钩住横梁，松钩后保留速度，再返回地面近战" if mode == 1 else "移动练习：沿左侧金色标记前进，Ctrl 滑铲、空格翻越"))


func restart_round() -> void:
	start_round(mode)


func _on_enemy_defeated(_enemy: Node3D) -> void:
	defeated_count += 1
	if defeated_count >= round_total:
		round_complete = true
		show_notice("试炼完成！R 再来一轮 · F 清怪 / G 机动 · 也可以继续练习钩爪")


func show_notice(message: String) -> void:
	notice = message
	notice_time = 5.0


func _toggle_loadout() -> void:
	if player.menu_open:
		hud.close_loadout()
		player.set_controls_active(true)
	else:
		player.menu_open = true
		player.set_controls_active(false)
		hud.open_loadout()


func _build_world() -> void:
	var environment: WorldEnvironment = WorldEnvironment.new()
	var settings: Environment = Environment.new()
	# 用程序化天空代替纯色背景：环境光从天空取，遗迹贴图才有立体感。
	settings.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.44, 0.58, 0.66)
	sky_material.sky_horizon_color = Color(0.80, 0.86, 0.84)
	sky_material.ground_horizon_color = Color(0.66, 0.72, 0.66)
	sky_material.ground_bottom_color = Color(0.30, 0.36, 0.32)
	sky_material.sun_angle_max = 24.0
	sky.sky_material = sky_material
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_energy = 0.40
	# ACES 的高光滚降比 FILMIC 更硬，压曝光后细节保得住。
	settings.tonemap_mode = Environment.TONE_MAPPER_ACES
	settings.tonemap_exposure = 0.90
	# 屏幕空间环境光遮蔽：让石头缝隙、墙根有接触阴影，立体感更强。
	settings.ssao_enabled = true
	settings.ssao_radius = 1.4
	settings.ssao_intensity = 1.8
	settings.ssao_power = 1.6
	# 远景雾：把几百米外的遗迹压淡，近处训练场保持清晰，形成空间层次。
	settings.fog_enabled = true
	settings.fog_light_color = Color(0.58, 0.66, 0.66)
	settings.fog_light_energy = 0.5
	settings.fog_density = 0.0055
	settings.fog_aerial_perspective = 0.45
	settings.fog_sky_affect = 0.35
	environment.environment = settings
	add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 0.90
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	# 遗迹地形先铺底，训练场元素再叠在上面。
	_build_ruins()
	var floor_size: Vector3 = _vector(tuning.arena.size)
	# 地面加厚到 3 米，把遗迹草地的起伏埋在下面。
	_box("ArenaFloor", Vector3(0, -1.5, 0), Vector3(floor_size.x, 3.0, floor_size.z), Color("9c8f78"))
	for side: float in [-1.0, 1.0]:
		# 加高的外墙：既是场地边界，也是蹬墙跑的墙面（7.2 米，够跑完整段）。
		_box("SideWall", Vector3(side * 23.6, 3.6, 0), Vector3(0.8, 7.2, 44), Color("bfae90"))
		_box("EndWall", Vector3(0, 3.6, side * 21.5), Vector3(47, 7.2, 0.8), Color("bfae90"))
		# 场内独立矮墙，提供不靠边界的蹬墙跑练习段。
		_box("WallrunWall", Vector3(side * 17.5, 3.6, side * 6.0), Vector3(0.6, 7.2, 10), Color("cdbb9c"))
		for z: float in [-9.0, 4.0]:
			_box("HookPillar", Vector3(side * 7.5, 3.0, z), Vector3(1.1, 6, 1.1), Color("b6a891"))
			_box("HookCap", Vector3(side * 7.5, 6.15, z), Vector3(1.8, 0.3, 1.8), Color("d7c595"))
		_box("RaisedPlatform", Vector3(side * 12, 1.0, -5), Vector3(4, 2, 6), Color("b0a28c"))
		# A walkable ramp provides an ordinary route even without a grapple.
		var ramp: Node3D = _box("PlatformRamp", Vector3(side * 12, 1.01, 1.55), Vector3(4, 0.2, 8.0), Color("c4b396"))
		ramp.rotation_degrees.x = 16.0
		_box("LowCover", Vector3(side * 4.0, 0.55, -13.5), Vector3(3.2, 1.1, 1.3), Color("8a8072"))
	_box("FrontHookBeam", Vector3(0, 6.0, -9), Vector3(16.1, 0.5, 1.1), Color("b6a891"))
	_box("RearHookBeam", Vector3(0, 6.0, 4), Vector3(16.1, 0.5, 1.1), Color("b6a891"))
	# Bright strips identify good grapple surfaces without changing collision rules.
	_box("FrontHookStripe", Vector3(0, 5.96, -8.43), Vector3(15, 0.16, 0.035), Color("d2ac68"), false)
	_box("RearHookStripe", Vector3(0, 5.96, 4.57), Vector3(15, 0.16, 0.035), Color("d2ac68"), false)
	_box("SafePoint", Vector3(0, 0.015, 8), Vector3(3.2, 0.025, 2.6), Color("c9bda4"), false)
	_sign("练习场  /  TRAINING", Vector3(0, 3.7, -20.9), 55)
	_sign("右键钩爪 · 起钩后立刻空格助推", Vector3(0, 5.0, -8.35), 32)
	_sign("高台", Vector3(-12, 3, -5), 32)
	_sign("高台", Vector3(12, 3, -5), 32)
	_build_parkour()
	course = Node3D.new()
	course.set_script(COURSE_SCRIPT)
	course.arena = self
	add_child(course)


## 载入 UE 遗迹地形，只给 Landscape 加三角碰撞，建筑保持纯装饰。
func _build_ruins() -> void:
	if RUINS_SCENE == null:
		push_warning("遗迹模型缺失，训练场单独运行")
		return
	var ruins: Node3D = RUINS_SCENE.instantiate() as Node3D
	if ruins == null:
		return
	ruins.name = "ImportedRuins"
	ruins.position = RUINS_OFFSET
	add_child(ruins)
	_add_ruins_collisions(ruins)


func _add_ruins_collisions(node: Node) -> void:
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh != null and String(instance.get_path()).contains("Landscape"):
			instance.create_trimesh_collision()
	for child: Node in node.get_children():
		_add_ruins_collisions(child)


func _build_parkour() -> void:
	# Elevated routes and floating islands for grapple practice.
	# Kept clear of the enemy spawns (z -1..-8) and the player spawn (0, 0.08, 8).
	# Rear course: a stair of platforms climbing toward the back wall.
	_box("ParkourStepA", Vector3(0, 2.5, -15), Vector3(4, 1, 4), Color("c2b294"))
	_box("ParkourStepB", Vector3(6, 5.0, -17), Vector3(4, 1, 4), Color("c2b294"))
	_box("ParkourStepC", Vector3(-6, 8.0, -19), Vector3(4, 1, 4), Color("c2b294"))
	_box("ParkourStepD", Vector3(0, 12.0, -20), Vector3(4, 1, 4), Color("d7c595"))
	# Front course: a gentler climb near the spawn side.
	_box("ParkourStepE", Vector3(0, 2.5, 13), Vector3(4, 1, 4), Color("c2b294"))
	_box("ParkourStepF", Vector3(8, 6.0, 16), Vector3(4, 1, 4), Color("c2b294"))
	_box("ParkourStepG", Vector3(-8, 10.0, 18), Vector3(4, 1, 4), Color("d7c595"))
	# Floating islands in the middle: only reachable with the hook.
	_box("FloatingIslandLow", Vector3(0, 9.0, 0), Vector3(6, 0.8, 6), Color("b6a891"))
	_box("FloatingIslandHigh", Vector3(0, 15.0, -10), Vector3(5, 0.8, 5), Color("d7c595"))
	# Tall anchor pillars at the four corners, 18 m high.
	for side: float in [-1.0, 1.0]:
		for depth: float in [-14.0, 14.0]:
			_box("TallAnchor", Vector3(side * 16.0, 9.0, depth), Vector3(1.5, 18, 1.5), Color("b6a891"))
			_box("TallAnchorCap", Vector3(side * 16.0, 18.2, depth), Vector3(2.4, 0.4, 2.4), Color("d2ac68"))
	# High beams give long, readable swing lines.
	_box("HighBeamFront", Vector3(0, 12.0, 14), Vector3(20, 0.4, 0.8), Color("b6a891"))
	_box("HighBeamRear", Vector3(0, 16.0, -14), Vector3(20, 0.4, 0.8), Color("b6a891"))
	# Bright strips mark the beams as grapple surfaces, matching the existing style.
	_box("HighBeamFrontStripe", Vector3(0, 11.78, 14), Vector3(19, 0.06, 0.5), Color("d2ac68"), false)
	_box("HighBeamRearStripe", Vector3(0, 15.78, -14), Vector3(19, 0.06, 0.5), Color("d2ac68"), false)


func _box(node_name: String, point: Vector3, dimensions: Vector3, color: Color, solid: bool = true) -> Node3D:
	var body: Node3D = StaticBody3D.new() if solid else Node3D.new()
	body.name = node_name
	body.position = point
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _material(color)
	body.add_child(visual)
	if solid:
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = dimensions
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
	add_child(body)
	return body


func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	# 占位灰盒的反照率偏高，在室外强光下会发白；整体压暗以贴近遗迹石材质感。
	material.albedo_color = color.darkened(0.24)
	material.roughness = 0.95
	material.metallic = 0.0
	return material


func _sign(text: String, point: Vector3, font_size: int) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.position = point
	label.font_size = font_size
	label.pixel_size = 0.009
	label.modulate = Color("eff0da")
	label.outline_modulate = Color("435a55")
	label.outline_size = 10
	add_child(label)


func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _build_audio() -> void:
	for index: int in range(4):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.volume_db = -18.0
		add_child(voice)
		_audio.append(voice)
	_sounds.swing = _tone(200.0, 0.10, 0.6)
	_sounds.hit = _tone(540.0, 0.075, 0.25)
	_sounds.hurt = _tone(110.0, 0.14, 0.7)
	_sounds.step = _movement_noise(0.10, 100.0, 0.30)
	_sounds.land = _movement_noise(0.18, 65.0, 0.45)
	_sounds.jump = _movement_noise(0.10, 140.0, 0.55)
	_sounds.slide = _movement_noise(0.25, 80.0, 0.85)
	_sounds.wave = _tone(320.0, 0.32, 0.75)


func _tone(frequency: float, duration: float, slide: float) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var count: int = int(duration * 22050.0)
	var samples: PackedByteArray = PackedByteArray()
	samples.resize(count * 2)
	var phase: float = 0.0
	for index: int in range(count):
		var progress: float = float(index) / float(count)
		phase += TAU * frequency * (1.0 - progress * slide) / 22050.0
		var envelope: float = minf(progress * 40.0, 1.0) * pow(1.0 - progress, 2.0)
		samples.encode_s16(index * 2, int(sin(phase) * envelope * 18000.0))
	stream.data = samples
	return stream


func _movement_noise(duration: float, frequency: float, roughness: float) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var count: int = int(duration * stream.mix_rate)
	var samples: PackedByteArray = PackedByteArray()
	samples.resize(count * 2)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 4821
	var filtered: float = 0.0
	for index: int in range(count):
		var progress: float = float(index) / float(count)
		filtered = lerpf(filtered, random.randf_range(-1.0, 1.0), 0.28)
		var thump: float = sin(TAU * frequency * float(index) / float(stream.mix_rate))
		var envelope: float = minf(progress * 60.0, 1.0) * pow(1.0 - progress, 2.0)
		samples.encode_s16(index * 2, int(lerpf(thump * 0.5, filtered, roughness) * envelope * 23000.0))
	stream.data = samples
	return stream


func _sound(sound_name: String, strength: float = 1.0) -> void:
	if _audio.is_empty() or not _sounds.has(sound_name):
		return
	var voice: AudioStreamPlayer = _audio[_audio_index % _audio.size()]
	_audio_index += 1
	var movement: bool = sound_name in ["step", "land", "jump", "slide"]
	voice.volume_db = float(tuning.player.movement_audio_db) + linear_to_db(maxf(strength, 0.01)) if movement else -18.0
	voice.stream = _sounds[sound_name]
	voice.play()
