extends Node3D
## Isolated source-asset preview. Never changes the production player or hands.

var animation_player: AnimationPlayer
var camera: Camera3D
var source_model: Node3D
var skeleton: Skeleton3D
var socket: BoneAttachment3D
var status: Label
var animation_names: Array[String] = []
var selected: int = 0
var capture_mode: bool = false
var source_sword: Node3D
var fantasy_sword: Node3D
var use_fantasy_sword: bool = false
var camera_view: int = 0

func _ready() -> void:
	capture_mode = "--capture-melee" in OS.get_cmdline_user_args()
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("28333f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.7
	environment_node.environment = environment
	add_child(environment_node)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	add_child(light)
	camera = Camera3D.new()
	camera.near = 0.01
	camera.fov = 75.0
	add_child(camera)
	camera.current = true
	source_model = load("res://assets/characters/fps_arms/Arms.fbx").instantiate() as Node3D
	source_model.rotation_degrees = Vector3(5, 180, 0)
	# Keep the authored poses, move the complete viewmodel back for a wider view.
	source_model.position = Vector3(0.0, 0.035, -0.04)
	add_child(source_model)
	skeleton = _find_skeleton(source_model)
	animation_player = source_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip: String in animation_player.get_animation_list():
		animation_names.append(clip)
	selected = animation_names.find("CharacterArmature|Sword_Idle")
	socket = BoneAttachment3D.new()
	socket.bone_name = "Wrist.R"
	skeleton.add_child(socket)
	var weapon: Node3D = load("res://assets/characters/fps_arms/Steel Shortsword.fbx").instantiate() as Node3D
	socket.add_child(weapon)
	# FBX import reflects the source X axis; convert the Unity-local socket too.
	weapon.position = Vector3(0.0066, 0.1093, -0.0544)
	weapon.quaternion = Quaternion(-0.25174302, 0.24411201, 0.63064706, 0.6923288).normalized()
	source_sword = weapon
	var palette_image: Image = Image.load_from_file("res://assets/characters/fps_arms/reference/Colour_Palette.png")
	var palette: StandardMaterial3D = StandardMaterial3D.new()
	palette.albedo_texture = ImageTexture.create_from_image(palette_image)
	palette.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	palette.roughness = 0.85
	for mesh: Node in weapon.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = palette
	fantasy_sword = Node3D.new()
	weapon.add_child(fantasy_sword)
	var own_sword: Node3D = load("res://assets/weapons/fantasy sword 3d model.glb").instantiate() as Node3D
	# Match the grip center, keeping the existing game sword's source intact.
	own_sword.scale = Vector3.ONE * 0.65
	own_sword.position.y = -0.137
	own_sword.rotation_degrees.y = 90
	fantasy_sword.add_child(own_sword)
	fantasy_sword.visible = false
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(24, 20)
	status.add_theme_font_size_override("font_size", 20)
	canvas.add_child(status)
	_play()
	if capture_mode:
		_capture_all.call_deferred()

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null

func _play() -> void:
	var clip: String = animation_names[selected]
	animation_player.play(clip, 0.12)
	socket.visible = "Sword" in clip
	status.text = "近战资源独立预览 | " + clip.get_slice("|", 1) + (" | 项目剑" if use_fantasy_sword else " | 原版短剑") + "\n左右方向键：切动作　空格：重播　C：近景　T：换剑　鼠标左右键：挥砍　Esc：退出"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		selected = animation_names.find("CharacterArmature|Sword_Slash1" if event.button_index == MOUSE_BUTTON_LEFT else "CharacterArmature|Sword_Slash2")
		_play()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_LEFT:
			selected = posmod(selected + (1 if event.keycode == KEY_RIGHT else -1), animation_names.size())
			_play()
		elif event.keycode == KEY_SPACE:
			_play()
		elif event.keycode == KEY_T:
			use_fantasy_sword = not use_fantasy_sword
			for mesh: Node in source_sword.find_children("*", "MeshInstance3D", false, false):
				(mesh as MeshInstance3D).visible = not use_fantasy_sword
			fantasy_sword.visible = use_fantasy_sword
			_play()
		elif event.keycode == KEY_C:
			camera_view = (camera_view + 1) % 3
			if camera_view != 0:
				camera.position = socket.global_position + Vector3(0.20 if camera_view == 1 else -0.15, 0.08, 0.16)
				camera.look_at(socket.global_position + Vector3(0, 0.055, 0))
			else:
				camera.transform = Transform3D.IDENTITY

func _capture_all() -> void:
	var output: String = "res://.mvp_qa/melee_candidate/"
	for clip_name: String in ["Sword_Idle", "Sword_Slash1", "Sword_Slash2", "Sword_Walk", "Sword_Block", "Fists_Idle", "Fists_Block", "Lefthand_Spell1", "Consumable_Drink_001"]:
		var clip: String = "CharacterArmature|" + clip_name
		selected = animation_names.find(clip)
		_play()
		animation_player.play(clip)
		socket.visible = "Sword" in clip_name
		animation_player.advance(0)
		animation_player.pause()
		for fraction: float in ([0.0, 0.5] if "Slash" in clip_name else [0.0]):
			animation_player.seek(animation_player.get_animation(clip).length * fraction, true)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output + clip_name + "_%s.png" % int(fraction * 100))
	animation_player.play("CharacterArmature|Sword_Idle")
	status.text = "原版手臂＋原版短剑：握柄近景"
	socket.visible = true
	animation_player.advance(0)
	animation_player.pause()
	await get_tree().process_frame
	var grip: Vector3 = socket.global_position
	camera.position = grip + Vector3(0.20, 0.05, 0.16)
	camera.look_at(grip + Vector3(0, 0.06, 0))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + "grip_close.png")
	camera.position = socket.global_position + Vector3(-0.15, 0.08, 0.15)
	camera.look_at(socket.global_position + Vector3(0, 0.055, 0))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + "grip_palm.png")
	camera.transform = Transform3D.IDENTITY
	for mesh: Node in source_sword.find_children("*", "MeshInstance3D", false, false):
		(mesh as MeshInstance3D).visible = false
	fantasy_sword.visible = true
	status.text = "原版手臂＋项目剑：测试装配（尚未替换主游戏）"
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + "project_sword.png")
	# A short sequence makes both authored swings reviewable outside the editor.
	for clip_index: int in range(2):
		var clip: String = "CharacterArmature|Sword_Slash" + str(clip_index + 1)
		animation_player.play(clip)
		animation_player.advance(0)
		animation_player.pause()
		for frame: int in range(18):
			animation_player.seek(animation_player.get_animation(clip).length * float(frame) / 17.0, true)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output + "swing_%02d_%02d.png" % [clip_index, frame])
	print("MELEE_PREVIEW_CAPTURE_COMPLETE")
	get_tree().quit()
