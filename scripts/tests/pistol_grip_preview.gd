extends Node3D
## Isolated author's reference / own glove comparison, without the main controller.

const REFERENCE: PackedScene = preload("res://assets/characters/fps_arms/pistol_reference/fps_demo_arms.glb")
const M1911: PackedScene = preload("res://assets/weapons/m1911/m1911.fbx")
const STEAM: PackedScene = preload("res://assets/weapons/steampunk_pistol.glb")

var camera: Camera3D
var arm: Node3D
var glove: Node3D
var glove_skeleton: Skeleton3D
var reference: Node3D
var reference_animator: AnimationPlayer
var gun: Node3D
var label: Label
var pose: Dictionary
var selected: String = "m1911"
var angle: int = 0
var _kick: float = 0.0
var _rest_position: Vector3
var _glove_document: GLTFDocument
var _glove_state: GLTFState
var _steam_document: GLTFDocument
var _steam_state: GLTFState

func _ready() -> void:
	pose = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/fps_gloves/pistol_grip_pose.json"))
	camera = Camera3D.new()
	camera.near = 0.01
	camera.fov = 78
	add_child(camera)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("37484c")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.5
	add_child(world)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-25,0)
	light.light_energy = 0.9
	add_child(light)
	reference = REFERENCE.instantiate()
	reference.position = Vector3(0.15,-0.02,-0.1)
	add_child(reference)
	reference_animator = _find_kind(reference,"AnimationPlayer")
	reference_animator.play("pistol_fire")
	reference_animator.seek(0,true)
	reference_animator.pause()
	_reference_materials(reference)
	reference.visible = false
	arm = Node3D.new()
	_rest_position = _vec(pose.hand_position)
	arm.position = _rest_position
	var axes: Array = pose.hand_world_basis
	arm.basis = Basis(_vec(axes[0]),_vec(axes[1]),_vec(axes[2]))
	add_child(arm)
	# Load the unchanged source GLB directly. The project's older generated
	# texture cache currently fails WebP decode; this preview must stay isolated.
	_glove_document = GLTFDocument.new()
	_glove_state = GLTFState.new()
	var status: Error = _glove_document.append_from_file("res://assets/characters/fps_gloves/glove_right.glb",_glove_state)
	if status != OK:
		push_error("Could not read glove source GLB")
		return
	glove = _glove_document.generate_scene(_glove_state)
	arm.add_child(glove)
	glove_skeleton = _find_kind(glove,"Skeleton3D")
	for name: String in pose.right:
		var q: Array = pose.right[name]
		glove_skeleton.set_bone_pose_rotation(glove_skeleton.find_bone(name),Quaternion(q[0],q[1],q[2],q[3]))
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(24,24)
	label.add_theme_font_size_override("font_size",18)
	canvas.add_child(label)
	set_weapon("m1911")
	update_camera()

func _process(delta: float) -> void:
	_kick = maxf(0.0,_kick-delta)
	arm.position = _rest_position + Vector3(0,0.008,0.035)*sin((1.0-_kick/0.18)*PI) if _kick > 0 else _rest_position

func set_weapon(id: String) -> void:
	selected = id
	if is_instance_valid(gun):
		gun.free()
	reference.visible = id == "reference"
	arm.visible = id != "reference"
	if id != "reference":
		if id == "m1911":
			gun = M1911.instantiate()
		else:
			_steam_document = GLTFDocument.new()
			_steam_state = GLTFState.new()
			_steam_document.append_from_file("res://assets/weapons/steampunk_pistol.glb",_steam_state)
			gun = _steam_document.generate_scene(_steam_state)
		var cfg: Dictionary = pose.weapons[id]
		var basis: Basis = Basis(Vector3.BACK,Vector3.LEFT,Vector3.DOWN)
		gun.transform = Transform3D(basis.scaled_local(Vector3.ONE*float(cfg.scale)),_vec(cfg.palm_grip)-basis*_vec(cfg.source_grip)*float(cfg.scale))
		arm.add_child(gun)
		if id == "m1911": _gun_materials(gun)
	label.text = "独立持枪适配预览 · %s\n1 M1911 / 2 原手炮 / 3 原作者参考\nC 第一视角/掌心/手背 · 左键短后坐 · Esc退出" % id
	update_camera()

func update_camera() -> void:
	if angle == 0 or selected == "reference":
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
	else:
		var target: Vector3 = arm.to_global(Vector3(0.005,-0.048,-0.11))
		camera.position = target + Vector3(-0.32 if angle == 1 else 0.32,0.02,0.06)
		camera.look_at(target,Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: set_weapon("m1911")
			KEY_2: set_weapon("steam_pistol")
			KEY_3: set_weapon("reference")
			KEY_C:
				angle = (angle+1)%3
				update_camera()
			KEY_ESCAPE: get_tree().quit()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if selected == "reference":
			reference_animator.play("pistol_fire")
			reference_animator.seek(0,true)
		else:
			_kick = 0.18

func _vec(a: Array) -> Vector3:
	return Vector3(a[0],a[1],a[2])

func _find_kind(node: Node, kind: String) -> Node:
	if node.is_class(kind): return node
	for child: Node in node.get_children():
		var found: Node = _find_kind(child,kind)
		if found != null: return found
	return null

func _reference_materials(node: Node) -> void:
	if node is MeshInstance3D:
		node.visible = node.name in ["fps_arms_extended","pistol"]
		if node.name == "pistol":
			node.set_surface_override_material(0,load("res://assets/characters/fps_arms/pistol_reference/black_mat.material"))
	for child: Node in node.get_children(): _reference_materials(child)

func _gun_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i: int in range(node.mesh.get_surface_count()):
			var original: Material = node.get_active_material(i)
			var material: StandardMaterial3D = StandardMaterial3D.new()
			material.albedo_color = Color("50392a") if original != null and "Grip" in original.resource_name else Color("59616a")
			material.roughness = 0.6
			node.set_surface_override_material(i,material)
	for child: Node in node.get_children(): _gun_materials(child)
