extends Node3D
## (Claude Code) Cherry Blossom Valley — scene orchestrator.
## Reads data/cherry_valley.json, builds the landscape in stages with a loading
## veil, then owns mood/quality/shot switching and respawn.

signal build_finished()

const TERRAIN_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_terrain.gd")
const WATER_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_water.gd")
const LIGHTING_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_lighting.gd")
const ARCHITECTURE_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_architecture.gd")
const FLORA_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_flora.gd")
const REFLECTION_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_reflection.gd")
const NAV_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_nav.gd")
const CINEMATIC_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_cinematic.gd")
const HUD_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_hud.gd")
const RAIN_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_rain.gd")
const WALKER_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_walker.gd")
const WATERFALL_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_waterfall.gd")
const BIRDS_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_birds.gd")
const BACKDROP_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_backdrop.gd")
const AMBIENT_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_ambient.gd")
const TOUR_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_tour.gd")
const TOUCH_SCRIPT: Script = preload("res://scripts/cherry_valley/valley_touch.gd")
const MESH_KIT: Script = preload("res://scripts/cherry_valley/valley_mesh_kit.gd")

var config: Dictionary = {}
var terrain: Node3D
var water: Node3D
var lighting: Node3D
var architecture: Node3D
var flora: Node3D
var reflection: Node3D
var navigation: Node3D
var cinematic: Node3D
var hud: Control
var rain: Node3D
var waterfall: Node3D
var birds: Node3D
var backdrop: Node3D
var landmark: Node3D
var ambient: Node3D
var tour: Node3D
var touch: Control
var walker: CharacterBody3D
var player: CharacterBody3D
var materials: Dictionary = {}

var build_complete: bool = false
var mood_keys: Array[String] = []
var quality_level: String = "high"
var _hud_layer: CanvasLayer
var _toon_shader: Shader
var _water_shader: Shader
var _quality_settings: Dictionary = {}
var _bridge_deck_height: float = 1.25
var _bridge_center: Vector2 = Vector2(1.0, 8.0)


func _ready() -> void:
	var source: String = FileAccess.get_file_as_string("res://data/cherry_valley.json")
	if source == "":
		_fail("数据文件缺失：data/cherry_valley.json")
		return
	config = JSON.parse_string(source) as Dictionary
	if not config is Dictionary or config.is_empty():
		_fail("数据文件格式错误：data/cherry_valley.json")
		return
	if not config.has("shaders") or not config.has("scene"):
		_fail("数据文件缺少 scene / shaders 配置")
		return
	_toon_shader = load(str(config.shaders.toon)) as Shader
	_water_shader = load(str(config.shaders.water)) as Shader
	if _toon_shader == null or _water_shader == null:
		_fail("着色器缺失：shaders/valley_toon.gdshader 或 valley_water.gdshader")
		return
	_build_materials()
	_create_hud()
	await _build_async()
	build_complete = true
	build_finished.emit()


func _build_async() -> void:
	var steps: Array[String] = [
		"正在塑造山谷地形", "正在引来河流", "正在布置光线",
		"正在搭建村落与神社", "正在种下樱花林", "正在铺开水面倒影",
		"正在打通村中小径", "正在准备镜头", "正在唤醒山涧瀑布",
	]
	var total: float = float(steps.size())
	for index: int in range(steps.size()):
		_set_loading(steps[index], float(index) / total)
		await get_tree().process_frame
		await get_tree().process_frame
		match index:
			0: _build_terrain()
			1: _build_water()
			2: _build_lighting()
			3: _build_architecture()
			4: _build_flora()
			5: _build_reflection()
			6: _build_navigation()
			7: _build_cinematic_player()
			8: _build_details()
	# Remaining systems after the visual pass.
	_set_loading("正在完成最后细节", 0.96)
	await get_tree().process_frame
	_build_rain()
	_build_touch()
	_build_ambient()
	_build_tour()
	# Touch devices drop to the light grade; the player can still raise it with Y.
	var start_quality: String = "light" if _is_touch_device() else "high"
	_apply_quality(start_quality)
	_apply_mood(lighting.current_key)
	hud.set_loading(false)
	_hud_layer.visible = true


func _build_materials() -> void:
	# 按材质类别分别给噪声尺度、粗糙度与边缘暗化，避免整场景共用一套参数变成塑料感。
	# 地面用专门的预设：噪声尺度放到米级，靠顶点色的分区表达草地/泥土/岩石，
	# 避免整片山坡出现均匀的高频颗粒。
	materials["terrain"] = MESH_KIT.toon_material_for(_toon_shader, "ground", Color(1, 1, 1), 0.10)
	materials["architecture"] = MESH_KIT.toon_material_for(_toon_shader, "plaster", Color(1, 1, 1), 0.28)
	materials["branch"] = MESH_KIT.toon_material_for(_toon_shader, "bark", Color("#b08d7a"), 0.30)
	materials["blossom"] = MESH_KIT.toon_material_for(_toon_shader, "petal", Color(1, 1, 1), 0.16)
	# 松树顶点色本身已是深绿，tint 再乘一层灰绿会被压成黑色，这里改成白色让顶点色决定。
	materials["pine"] = MESH_KIT.toon_material_for(_toon_shader, "grass", Color(1, 1, 1), 0.30)
	materials["grass"] = MESH_KIT.toon_material_for(_toon_shader, "grass", Color(1, 1, 1), 0.12)
	materials["rock"] = MESH_KIT.toon_material_for(_toon_shader, "stone", Color(1, 1, 1), 0.35)


# ---------------------------------------------------------------- stage builders

func _build_terrain() -> void:
	terrain = Node3D.new()
	terrain.name = "Terrain"
	terrain.set_script(TERRAIN_SCRIPT)
	add_child(terrain)
	terrain.build(config, materials)


func _build_water() -> void:
	water = Node3D.new()
	water.name = "Water"
	water.set_script(WATER_SCRIPT)
	add_child(water)
	water.build(config, terrain, _water_shader)


func _build_lighting() -> void:
	lighting = Node3D.new()
	lighting.name = "Lighting"
	lighting.set_script(LIGHTING_SCRIPT)
	add_child(lighting)
	lighting.build(config)
	mood_keys = lighting.get_mood_keys()


func _build_architecture() -> void:
	architecture = Node3D.new()
	architecture.name = "Architecture"
	architecture.set_script(ARCHITECTURE_SCRIPT)
	add_child(architecture)
	architecture.build(config, terrain, materials)
	var bridge: Dictionary = config.village.bridge
	_bridge_center = Vector2(float(bridge.center[0]), float(bridge.center[1]))
	# The deck is generated from the ground, so the guide route has to ask for the
	# height that was actually built instead of assuming the config value.
	_bridge_deck_height = float(architecture.sizes.get("bridge_deck_y", _bridge_deck_height))


func _build_flora() -> void:
	flora = Node3D.new()
	flora.name = "Flora"
	flora.set_script(FLORA_SCRIPT)
	add_child(flora)
	flora.build(config, terrain, materials)


func _build_reflection() -> void:
	reflection = Node3D.new()
	reflection.name = "Reflection"
	reflection.set_script(REFLECTION_SCRIPT)
	add_child(reflection)
	reflection.build(config)
	var sources: Array[Node3D] = [terrain, architecture]
	# Only the near half of the flora is mirrored; distant trees cost more than
	# they add to the reflection.
	for child: Node in flora.get_children():
		if child is MeshInstance3D and str(child.name).contains("CherryTree"):
			var distance: float = (child as Node3D).global_position.distance_to(Vector3(_bridge_center.x, 0.0, _bridge_center.y))
			if distance < 70.0:
				sources.append(child as Node3D)
	reflection.copy_from(sources)


func _build_navigation() -> void:
	navigation = Node3D.new()
	navigation.name = "Navigation"
	navigation.set_script(NAV_SCRIPT)
	add_child(navigation)
	navigation.build(config, terrain)
	walker = CharacterBody3D.new()
	walker.name = "LanternSpirit"
	walker.set_script(WALKER_SCRIPT)
	add_child(walker)
	var route: Array[Vector3] = [
		Vector3(31.0, terrain.height_at(31.0, 32.0) + 0.2, 32.0),
		Vector3(20.0, terrain.height_at(20.0, 20.0) + 0.2, 20.0),
		Vector3(_bridge_center.x, _bridge_deck_height + 0.2, _bridge_center.y),
		Vector3(-30.0, terrain.height_at(-30.0, 2.0) + 0.2, 2.0),
		Vector3(-45.0, terrain.height_at(-45.0, -17.0) + 0.2, -17.0),
	]
	walker.build(route, route[0])


func _build_cinematic_player() -> void:
	player = (load(str(config.scene.player_scene)) as PackedScene).instantiate() as CharacterBody3D
	player.name = "ValleyPlayer"
	var spawn: Array = config.scene.spawn
	var spawn_x: float = float(spawn[0])
	var spawn_z: float = float(spawn[1])
	player.position = Vector3(spawn_x, terrain.height_at(spawn_x, spawn_z) + 0.15, spawn_z)
	player.rotation.y = deg_to_rad(float(config.scene.spawn_yaw_degrees))
	add_child(player)
	# Explore mode: empty hands, no combat HUD, no loadout panel noise.
	player.selected_slot = 1
	if player.quick_slots.size() > 1:
		player.quick_slots[1] = ""
	player._refresh_weapon()
	var camera: Camera3D = player.get_node("Head/Camera3D") as Camera3D
	camera.far = float(config.scene.camera_far)
	camera.fov = 78.0
	player.retry_requested.connect(_respawn)
	if not player.notice_requested.is_connected(_on_player_notice):
		player.notice_requested.connect(_on_player_notice)
	cinematic = Node3D.new()
	cinematic.name = "Cinematic"
	cinematic.set_script(CINEMATIC_SCRIPT)
	add_child(cinematic)
	cinematic.build(config, player)
	cinematic.shot_changed.connect(_on_shot_changed)


## Scenery that frames the vista: waterfall at the head of the river, birds
## overhead, plus the plunge pool at the head of the river. Each piece owns its
## own config block.
func _build_details() -> void:
	if config.has("waterfall") and bool(config.waterfall.enabled):
		waterfall = Node3D.new()
		waterfall.name = "Waterfall"
		waterfall.set_script(WATERFALL_SCRIPT)
		add_child(waterfall)
		waterfall.build(config, terrain, materials)
	backdrop = Node3D.new()
	backdrop.name = "Backdrop"
	backdrop.set_script(BACKDROP_SCRIPT)
	add_child(backdrop)
	backdrop.build(config, terrain, materials)
	_build_landmark()
	if config.has("birds") and bool(config.birds.enabled):
		birds = Node3D.new()
		birds.name = "Birds"
		birds.set_script(BIRDS_SCRIPT)
		add_child(birds)
		birds.build(config)


## 导入的烘焙庭院（Pagoda Cherry，Fab）。整包是一个带自家庭院地面与夜空球的
## 独立场景：夜空球必须按配置关掉，否则会把整个山谷罩进一颗黑球里；落位用
## terrain.height_at 取地面高度，配合 valley_terrain 里同一坐标的压平台地。
func _build_landmark() -> void:
	if not config.has("landmark") or not bool(config.landmark.get("enabled", false)):
		return
	var spec: Dictionary = config.landmark
	var packed: PackedScene = load(str(spec.get("scene", ""))) as PackedScene
	if packed == null:
		push_warning("landmark scene missing: " + str(spec.get("scene", "")))
		return
	landmark = packed.instantiate() as Node3D
	landmark.name = "Landmark"
	add_child(landmark)
	for hidden: Variant in spec.get("hide_nodes", []):
		var found: Node = landmark.find_child(str(hidden), true, false)
		if found is Node3D:
			(found as Node3D).visible = false
	var center: Array = spec.get("center", [0.0, 0.0]) as Array
	var at: Vector2 = Vector2(float(center[0]), float(center[1]))
	landmark.position = Vector3(at.x, terrain.height_at(at.x, at.y), at.y)
	landmark.rotation.y = deg_to_rad(float(spec.get("yaw", 0.0)))
	landmark.scale = Vector3.ONE * float(spec.get("scale", 1.0))


func _build_ambient() -> void:
	if not config.has("ambient"):
		return
	ambient = Node3D.new()
	ambient.name = "Ambient"
	ambient.set_script(AMBIENT_SCRIPT)
	add_child(ambient)
	ambient.build(config)


func _build_tour() -> void:
	if not config.has("tour") or cinematic == null:
		return
	tour = Node3D.new()
	tour.name = "Tour"
	tour.set_script(TOUR_SCRIPT)
	add_child(tour)
	tour.build(config, cinematic)


func _build_touch() -> void:
	if not config.has("touch"):
		return
	touch = Control.new()
	touch.name = "ValleyTouch"
	touch.set_script(TOUCH_SCRIPT)
	_hud_layer.add_child(touch)
	touch.build(config, player)
	if bool(touch.sizes.get("touch_enabled", false)):
		# Mobile runs the reduced-motion profile and the simplified HUD copy.
		hud.mobile = true


func _is_touch_device() -> bool:
	return DisplayServer.is_touchscreen_available()


func _build_rain() -> void:
	rain = Node3D.new()
	rain.name = "Rain"
	rain.set_script(RAIN_SCRIPT)
	add_child(rain)
	rain.build(config, player.get_node("Head/Camera3D") as Camera3D)


func _create_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "ValleyHud"
	_hud_layer.layer = 5
	add_child(_hud_layer)
	hud = Control.new()
	hud.name = "ValleyHudRoot"
	hud.set_script(HUD_SCRIPT)
	hud.config = config
	_hud_layer.add_child(hud)
	hud.set_loading(true, str(config.scene.title), 0.0)
	hud.mood_label = lighting_label_or_default()
	hud.quality_label = "高画质"


func _set_loading(message: String, progress: float) -> void:
	if hud != null:
		hud.set_loading(true, message, progress)


# ---------------------------------------------------------------- mood & quality

func _apply_mood(key: String) -> void:
	if lighting == null:
		return
	lighting.apply_mood(key)
	var mood: Dictionary = config.moods[key]
	# Custom toon lighting reads the sun strength from the palette: a custom
	# light() gets no LIGHT_ENERGY in Compatibility, so every toon material in
	# the valley tree must be told how strong the sun is.
	set_toon_sun_scale(float(mood.get("sun_scale", 0.1)))
	if water != null:
		water.set_mood(mood)
	if flora != null:
		flora.set_mood(mood)
	if rain != null:
		rain.set_mood(mood)
	if waterfall != null:
		waterfall.set_mood(mood)
	if birds != null:
		birds.set_mood(mood)
	if architecture != null:
		architecture.set_lantern_energy(1.9 if key == "blue_hour" else (0.9 if key == "morning" else 1.2))
	if backdrop != null:
		backdrop.set_mood(mood)
	if hud != null:
		hud.mood_label = lighting.mood_label(key)


func _apply_quality(level: String) -> void:
	quality_level = level
	_quality_settings = config.quality[level]
	if reflection != null:
		reflection.set_enabled(bool(_quality_settings.reflection))
	if flora != null:
		flora.apply_quality(_quality_settings)
	if lighting != null and lighting.sun != null:
		lighting.sun.directional_shadow_max_distance = float(_quality_settings.shadow_distance)
	if waterfall != null:
		waterfall.apply_quality(_quality_settings)
	if birds != null:
		birds.apply_quality(_quality_settings)
	if backdrop != null:
		backdrop.apply_quality(_quality_settings)
	if hud != null:
		hud.quality_label = "高画质" if level == "high" else "轻量"


func _respawn() -> void:
	if player == null:
		return
	player.reset_to_spawn(true)
	if cinematic != null and cinematic.active:
		cinematic.exit()


func _on_player_notice(_message: String) -> void:
	pass


func _on_shot_changed(index: int, label: String) -> void:
	if hud != null:
		hud.shot_label = label
		hud.show_help = false
	if touch != null:
		touch.set_active(index < 0)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event as InputEventKey
		match key.physical_keycode:
			KEY_C:
				if build_complete and cinematic != null:
					if tour != null:
						tour.stop(false)
					if cinematic.active:
						cinematic.exit()
					else:
						cinematic.enter(0)
			KEY_Q:
				if tour != null:
					tour.stop(false)
				if cinematic != null and cinematic.active:
					cinematic.cycle(-1)
			KEY_E:
				if tour != null:
					tour.stop(false)
				if cinematic != null and cinematic.active:
					cinematic.cycle(1)
			KEY_T:
				if build_complete and tour != null:
					tour.toggle()
			KEY_J:
				if ambient != null:
					ambient.toggle()
			KEY_M:
				if lighting != null:
					var next_key: String = lighting.next_mood()
					_apply_mood(next_key)
			KEY_Y:
				_apply_quality("light" if quality_level == "high" else "high")
			KEY_H:
				if hud != null:
					hud.ui_hidden = not hud.ui_hidden
					if hud.ui_hidden:
						hud.show_help = false


func _process(_delta: float) -> void:
	if rain != null and rain.rain != null and build_complete:
		# Follow whichever camera is active.
		var camera: Camera3D = cinematic.camera if cinematic != null and cinematic.active else player.get_node("Head/Camera3D") as Camera3D
		rain.set_camera(camera)


## Fail visibly: a readable error node instead of an endless progress bar.
func _fail(message: String) -> void:
	push_error("樱花 valley: " + message)
	var fallback: Dictionary = {"scene": {"title": "樱花山谷", "subtitle": ""}}
	config = fallback
	_create_hud()
	hud.set_error(message)


## Push the mood's sun strength into every toon-shaded material below this node.
## Materials are shared per system, so each one is visited once.
func set_toon_sun_scale(value: float) -> void:
	var seen: Dictionary = {}
	_push_sun_scale(self, value, seen)


func _push_sun_scale(node: Node, value: float, seen: Dictionary) -> void:
	var candidate: Array[Material] = []
	# MultiMeshInstance3D is a GeometryInstance3D but not a MeshInstance3D, so the
	# override is read at the common base.
	if node is GeometryInstance3D:
		var geometry_node: GeometryInstance3D = node as GeometryInstance3D
		if geometry_node.material_override != null:
			candidate.append(geometry_node.material_override)
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node.mesh != null:
			for surface: int in range(mesh_node.mesh.get_surface_count()):
				candidate.append(mesh_node.mesh.surface_get_material(surface))
	for material: Material in candidate:
		if material is ShaderMaterial and (material as ShaderMaterial).shader == _toon_shader:
			var shader_material: ShaderMaterial = material as ShaderMaterial
			if seen.has(shader_material):
				continue
			seen[shader_material] = true
			shader_material.set_shader_parameter("sun_scale", value)
	for child: Node in node.get_children():
		_push_sun_scale(child, value, seen)


func lighting_label_or_default() -> String:
	return "蓝调时刻"
