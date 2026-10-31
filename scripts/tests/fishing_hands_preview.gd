extends Node3D
## A visual fixture only: no fishing RNG, inventory, encounter or map integration.

const HANDS_SCRIPT: Script = preload("res://scripts/mvp/first_person_hands.gd")

var camera: Camera3D
var view_anchor: Node3D
var hands: Node3D
var bobber: Node3D
var phase: String = "idle"
var elapsed: float = 0.0
var angle: int = 0
var paused: bool = false
var equipped: bool = true
var _line: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _title: Label
var _status: Label
var _flight_start: Vector3
var _water_target: Vector3 = Vector3(0.0, 0.065, -3.5)
var _time: float = 0.0


func _ready() -> void:
	_build_fixture()
	view_anchor = Node3D.new()
	view_anchor.name = "PlayerEyeAnchor"
	view_anchor.position = Vector3(0.0, 1.6, 3.0)
	view_anchor.rotation.x = deg_to_rad(-8.0)
	add_child(view_anchor)
	camera = Camera3D.new()
	camera.fov = 78.0
	camera.near = 0.04
	camera.current = true
	add_child(camera)
	hands = Node3D.new()
	hands.name = "Hands"
	hands.set_script(HANDS_SCRIPT)
	view_anchor.add_child(hands)
	hands.set_weapon("fishing_rod")
	for i: int in range(90):
		hands.update_pose(1.0 / 60.0, 0.0, false, -1.0, 0, true, 2.0)
	_build_bobber()
	_build_labels()
	update_camera()
	sample_pose("idle", 0.0)


func _process(delta: float) -> void:
	if paused:
		return
	_time += delta
	elapsed += delta
	var duration: float = 1.0
	if phase == "casting":
		duration = float(hands._fishing_rod.config.cast_duration)
	elif phase == "reeling":
		duration = float(hands._fishing_rod.config.reel_duration)
	if phase in ["casting", "reeling"] and elapsed >= duration:
		_set_phase("waiting" if phase == "casting" else "idle")
	elif phase == "biting" and elapsed >= 1.5:
		# This fixed preview cue is not the gameplay bite-window algorithm.
		_set_phase("waiting")
	sample_pose(phase, clampf(elapsed / duration, 0.0, 1.0), delta)


func sample_pose(state: String, progress: float, delta: float = 1.0 / 60.0) -> void:
	hands.set_fishing_presentation(state, progress)
	hands.update_pose(delta, 0.0, false, -1.0, 0, equipped, 2.0)
	var tip: Vector3 = hands.fishing_tip_world()
	var point: Vector3 = _water_target
	if state == "casting":
		var flight: float = smoothstep(0.40, 1.0, progress)
		var start: Vector3 = _flight_start if _flight_start != Vector3.ZERO else tip
		point = start.lerp(_water_target, flight) + Vector3.UP * sin(flight * PI) * 0.5
	elif state == "reeling":
		point = _water_target.lerp(tip, smoothstep(0.0, 1.0, progress))
	elif state == "biting":
		point.y += -0.045 + sin(_time * 16.0) * 0.024
	else:
		point.y += sin(_time * 2.2) * 0.008
	bobber.global_position = point
	bobber.visible = equipped and state != "idle"
	var show_line: bool = bobber.visible
	for i: int in range(_line.size()):
		_line[i].visible = show_line
		var a: float = float(i) / float(_line.size())
		var b: float = float(i + 1) / float(_line.size())
		var start: Vector3 = tip.lerp(point, a) + Vector3.DOWN * sin(a * PI) * 0.025
		var finish: Vector3 = tip.lerp(point, b) + Vector3.DOWN * sin(b * PI) * 0.025
		_between(_line[i], start, finish)
	for i: int in range(_rings.size()):
		var ring: MeshInstance3D = _rings[i]
		ring.visible = equipped and state in ["waiting", "biting"]
		ring.position = Vector3(_water_target.x, 0.022 + float(i) * 0.001, _water_target.z)
		var pulse: float = fposmod(_time * (1.5 if state == "biting" else 0.5) + float(i) * 0.5, 1.0)
		ring.scale = Vector3.ONE * lerpf(0.5, 2.2 if state == "biting" else 1.3, pulse)
		var material: StandardMaterial3D = ring.material_override as StandardMaterial3D
		material.albedo_color = Color(0.78, 0.91, 0.84, (1.0 - pulse) * 0.65)
	_update_status(state)
	if angle > 0:
		update_camera()


func _set_phase(value: String) -> void:
	phase = value
	elapsed = 0.0
	if phase == "casting":
		_flight_start = hands.fishing_tip_world()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_1:
				equipped = true
				hands.set_weapon("fishing_rod")
				_set_phase("idle")
			KEY_2:
				equipped = false
				hands.set_weapon("")
				_set_phase("idle")
			KEY_B:
				if phase == "waiting":
					_set_phase("biting")
			KEY_C:
				angle = (angle + 1) % 3
				update_camera()
			KEY_P:
				paused = not paused
				_update_status(phase)
			KEY_R:
				angle = 0
				paused = false
				equipped = true
				hands.set_weapon("fishing_rod")
				hands.reset_motion()
				_set_phase("idle")
				update_camera()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not paused and equipped:
		if phase == "idle":
			_set_phase("casting")
		elif phase in ["waiting", "biting"]:
			_set_phase("reeling")


func update_camera() -> void:
	if angle == 0:
		camera.transform = view_anchor.transform
	else:
		var contact: Vector3 = hands.right_arm.to_global(hands.GRIP_CENTER)
		camera.global_position = contact + view_anchor.basis * Vector3(-0.35 if angle == 1 else 0.35, 0.07, 0.12)
		camera.look_at(contact, Vector3.UP)


func _update_status(state: String) -> void:
	var names: Dictionary = {"idle": "持竿", "casting": "抛竿", "waiting": "等待", "biting": "鱼漂咬钩 · 左键提竿", "reeling": "提竿收回"}
	_status.text = ("已暂停 · P继续" if paused else str(names.get(state, state))) if equipped else "空手 · 1取出鱼竿"


func _build_labels() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)
	var panel: ColorRect = ColorRect.new()
	panel.color = Color(0.07, 0.06, 0.13, 0.85)
	panel.position = Vector2(24, 22)
	panel.size = Vector2(590, 118)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(panel)
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	_title = Label.new()
	_title.position = Vector2(40, 30)
	_title.add_theme_font_override("font", font)
	_title.add_theme_font_size_override("font_size", 17)
	_title.text = "鱼竿与手部 · 独立动作预览\n左键 抛竿/收竿 · B 模拟咬钩 · 1 鱼竿 / 2 空手\nC 第一视角/掌心/手背 · P 暂停 · R 复位 · Esc 退出"
	canvas.add_child(_title)
	_status = Label.new()
	_status.position = Vector2(40, 111)
	_status.add_theme_font_override("font", font)
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color("efd08d"))
	canvas.add_child(_status)


func _build_fixture() -> void:
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("b2c9cb")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("e3e3cf")
	world.environment.ambient_light_energy = 0.65
	add_child(world)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_energy = 0.9
	add_child(light)
	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size = Vector2(35, 35)
	var floor_instance: MeshInstance3D = _fixture_mesh(floor_mesh, Color("b8b9a1"))
	floor_instance.position.y = -0.06
	var water_mesh: PlaneMesh = PlaneMesh.new()
	water_mesh.size = Vector2(14, 14)
	var water: MeshInstance3D = _fixture_mesh(water_mesh, Color("477d81"))
	water.position = Vector3(0, 0.0, -5.5)
	var edge_mesh: BoxMesh = BoxMesh.new()
	edge_mesh.size = Vector3(14, 0.12, 0.20)
	var edge: MeshInstance3D = _fixture_mesh(edge_mesh, Color("827356"))
	edge.position = Vector3(0, 0.0, 1.5)
	for x: float in [-6.5, 6.5]:
		var rock_mesh: SphereMesh = SphereMesh.new()
		rock_mesh.radius = 1.2
		rock_mesh.height = 1.5
		var rock: MeshInstance3D = _fixture_mesh(rock_mesh, Color("7f8b7d"))
		rock.position = Vector3(x, 0.0, -8.0)
		rock.scale = Vector3(1.0, 1.0, 1.8)


func _build_bobber() -> void:
	bobber = Node3D.new()
	bobber.name = "PreviewBobber"
	add_child(bobber)
	for i: int in range(2):
		var half: SphereMesh = SphereMesh.new()
		half.radius = 0.055
		half.height = 0.11
		var instance: MeshInstance3D = _fixture_mesh(half, Color("b74c39") if i == 0 else Color("f4e7bd"))
		remove_child(instance)
		bobber.add_child(instance)
		instance.position.y = 0.035 if i == 0 else -0.025
	var stem: CylinderMesh = CylinderMesh.new()
	stem.top_radius = 0.007
	stem.bottom_radius = 0.007
	stem.height = 0.14
	var stem_instance: MeshInstance3D = _fixture_mesh(stem, Color("efcf89"))
	remove_child(stem_instance)
	bobber.add_child(stem_instance)
	stem_instance.position.y = 0.11
	for i: int in range(8):
		var wire: CylinderMesh = CylinderMesh.new()
		wire.top_radius = 0.002
		wire.bottom_radius = 0.002
		wire.radial_segments = 6
		var segment: MeshInstance3D = _fixture_mesh(wire, Color("374735"))
		_line.append(segment)
	for i: int in range(2):
		var ripple: TorusMesh = TorusMesh.new()
		ripple.inner_radius = 0.12
		ripple.outer_radius = 0.127
		ripple.rings = 32
		ripple.ring_segments = 6
		var ring: MeshInstance3D = _fixture_mesh(ripple, Color("c9e3d0"))
		(ring.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_rings.append(ring)


func _fixture_mesh(mesh: Mesh, color: Color) -> MeshInstance3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _between(instance: MeshInstance3D, start: Vector3, finish: Vector3) -> void:
	var difference: Vector3 = finish - start
	(instance.mesh as CylinderMesh).height = maxf(difference.length(), 0.0001)
	instance.global_position = (start + finish) * 0.5
	if difference.length_squared() > 0.000001:
		instance.quaternion = Quaternion(Vector3.UP, difference.normalized())
