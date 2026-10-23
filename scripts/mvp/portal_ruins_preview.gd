extends Node3D
## Standalone preview of a bounded export from the user's UE ruin level.

const CONFIG_PATH: String = "res://data/portal_ruins_preview.json"
const PLAYER_SCENE: PackedScene = preload("res://scenes/mvp/player_3d.tscn")
const PlayerController = preload("res://scripts/mvp/player_3d.gd")

var _config: Dictionary = {}
var _player: PlayerController
var _overview: Camera3D
var _status: Label
var _overview_active: bool = false


func _ready() -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) as Dictionary
	_setup_environment()
	_setup_hud()
	var model_scene: PackedScene = load(String(_config["model"])) as PackedScene
	var model: Node3D = model_scene.instantiate() as Node3D
	model.name = "ImportedUERuins"
	model.position = _vector(_config["world_offset"])
	add_child(model)
	var mesh_count: int = _add_collisions(model)
	_player = PLAYER_SCENE.instantiate() as PlayerController
	_player.name = "Player"
	_player.position = Vector3(float(_config["spawn_xz"][0]), 250.0, float(_config["spawn_xz"][1]))
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_controls_active(false)
	_overview = Camera3D.new()
	_overview.name = "OverviewCamera"
	_overview.far = 1800.0
	_overview.position = _vector(_config["overview_position"])
	add_child(_overview)
	_overview.look_at(_vector(_config["overview_target"]))
	_player.camera.far = 1200.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var start: Vector3 = _player.position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		start, Vector3(start.x, -100.0, start.z), 1
	)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_player.global_position = (hit["position"] as Vector3) + Vector3.UP * 0.12
		_player.spawn_position = _player.global_position
		_player.camera_yaw.rotation.y = float(_config["camera_yaw"])
		_player.visual.rotation.y = _player.camera_yaw.rotation.y
		_player.camera_pitch.rotation.x = -0.18
		_player.set_physics_process(true)
		_player.set_controls_active(true)
		_status.text = "已载入 %d 个模型部件 · %s" % [mesh_count, _config["scope"]]
		print("PORTAL_PREVIEW_READY meshes=%d spawn=%s" % [mesh_count, _player.global_position])
	else:
		_overview_active = true
		_overview.make_current()
		_status.text = "场景已载入；出生点地面未命中，当前为全景预览。"
		push_warning("Portal preview spawn has no ground; retained overview instead of dropping player.")
	if "--portal-overview" in OS.get_cmdline_user_args() and not _overview_active:
		_toggle_overview()
	if "--portal-capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(3.0).timeout
		print("PORTAL_PREVIEW_GROUND floor=%s position=%s" % [_player.is_on_floor(), _player.global_position])
		var filename: String = "godot_overview.png" if _overview_active else "godot_preview.png"
		get_viewport().get_texture().get_image().save_png(
			"res://docs/art/ue_portal_import/" + filename
		)
		get_tree().quit()


func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _add_collisions(node: Node) -> int:
	var count: int = 0
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh != null and instance.mesh.get_surface_count() > 0:
			if String(instance.get_path()).contains("Landscape"):
				var ground: StandardMaterial3D = StandardMaterial3D.new()
				ground.albedo_color = Color(0.35, 0.43, 0.24)
				ground.roughness = 1.0
				ground.metallic_specular = 0.0
				instance.material_override = ground
			instance.create_trimesh_collision()
			count += 1
	for child: Node in node.get_children():
		count += _add_collisions(child)
	return count


func _setup_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.15, 0.29, 0.42)
	sky_material.sky_horizon_color = Color(0.67, 0.75, 0.75)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.78, 0.86)
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.9, 0.73)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)


func _setup_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	margin.add_child(column)
	for text: String in [String(_config["title"]), String(_config["role"]), String(_config["controls"])]:
		var label: Label = Label.new()
		label.text = text
		column.add_child(label)
	_status = Label.new()
	_status.text = "正在准备模型碰撞…"
	column.add_child(_status)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_TAB:
			_toggle_overview()
			get_viewport().set_input_as_handled()


func _toggle_overview() -> void:
	_overview_active = not _overview_active
	if _overview_active:
		_overview.make_current()
		_player.set_controls_active(false)
	else:
		_player.camera.make_current()
		_player.set_controls_active(true)
