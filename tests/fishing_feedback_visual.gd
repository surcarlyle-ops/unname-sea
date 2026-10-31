extends SceneTree
## Small isolated fixture: real fishing, rod/gloves and drop modules, no player/map under parallel edits.
class Actor extends CharacterBody3D:
	var camera: Camera3D
	var menu_open: bool = false
	var controls_active: bool = true

class Bag extends Node:
	var count: int = 0
	var full: bool = false
	func try_add(_id: String, n: int) -> int:
		if full:
			return n
		count += n
		return 0

var failures: int = 0
var actor: Actor
var hands: Node3D
var control: Node
var fx: Node3D
var world: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _process(delta: float) -> bool:
	if is_instance_valid(hands):
		hands.update_pose(delta, 0.0, false, -1.0, 0, true, 2.0)
	return false

func check(ok: bool, title: String) -> void:
	print("PASS " if ok else "FAIL ", title)
	if not ok:
		failures += 1

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/fishing_mvp/feedback_" + name + ".png")

func _run() -> void:
	create_timer(25.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1280, 720)
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("89abb6")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -20, 0)
	world.add_child(sun)
	for i: int in range(2):
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(12, 0.1, 12)
		mesh.mesh = box
		mesh.position = Vector3(0, -0.05 if i == 0 else 0.01, 5 if i == 0 else -7)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color("9d8b6a") if i == 0 else Color("367c91")
		mesh.material_override = mat
		world.add_child(mesh)
	actor = Actor.new()
	world.add_child(actor)
	actor.camera = Camera3D.new()
	actor.camera.position.y = 1.6
	actor.camera.rotation.x = -0.40
	actor.camera.fov = 78.0
	actor.camera.near = 0.04
	actor.camera.current = true
	actor.add_child(actor.camera)
	hands = Node3D.new()
	hands.set_script(load("res://scripts/mvp/first_person_hands.gd"))
	actor.camera.add_child(hands)
	hands.set_weapon("fishing_rod")
	control = load("res://scripts/mvp/fishing_mvp.gd").new()
	control.config = JSON.parse_string(FileAccess.get_file_as_string("res://data/fishing_mvp.json"))
	world.add_child(control)
	hands.bind_fishing_controller(control)
	fx = load("res://scripts/mvp/fishing_presentation.gd").new()
	fx.player = actor
	fx.fishing = control
	fx.water_level = 0.06
	world.add_child(fx)
	fx.set_rod_tip_anchor(hands.fishing_tip_anchor())
	await create_timer(0.3).timeout
	control.force_fish()
	control.begin_cast(hands.fishing_tip_world(), Vector3(0, 0.06, -5))
	await create_timer(0.5).timeout
	control._begin_bite()
	control.set_process(false)
	control._window_left = control._window_initial * (1.0 - 0.20 / 3.0)
	await process_frame
	fx._process(0.0)
	var down: Vector3 = fx._bobber.global_position
	check(down.y < -0.10, "Visible 22cm downward bite tug")
	await snap("bite")
	control.set_paused(true)
	fx._process(0.2)
	check(fx._bobber.global_position == down, "Pause freezes bite presentation")
	control.set_paused(false)
	control.reel_bite()
	control._state_time = 0.17
	await process_frame
	fx._process(0.0)
	check(fx._bobber.global_position.distance_to(fx.rod_tip()) < down.distance_to(fx.rod_tip()), "Reel visibly shrinks line")
	await snap("return")
	var records: Array = []
	control.result_revealed.connect(func(_o: String, _i: String, _m: String) -> void: records.append(true))
	control._state_time = 0.34
	control._process(0.02)
	await process_frame
	check(control.state == 0 and records.size() == 1, "Return resolves once without three-second lock")
	fx._process(0.0)
	check(not fx._line.visible and not fx._bobber.visible, "Line and bobber stowed")
	var drop: Node3D = load("res://scripts/mvp/loot_drop.gd").new()
	var bag: Bag = Bag.new()
	world.add_child(bag)
	drop.manual_collect = true
	drop.auto_collect = false
	drop.bag = bag
	drop.player = actor
	drop.setup("fish_pale_minnow", 1)
	world.add_child(drop)
	drop.global_position = Vector3(0.4, 0.05, -0.9)
	drop.launch_from(fx.rod_tip(), 0.25, 0.2)
	check(drop.try_collect() == 0, "Cannot collect airborne catch")
	await create_timer(0.9).timeout
	drop.set_focused(true)
	actor.camera.rotation.x = -0.95
	await snap("drop")
	check(bag.count == 0, "Ground catch waits for explicit pickup")
	bag.full = true
	check(drop.try_collect() == 0 and drop.amount == 1, "Full bag keeps catch intact")
	bag.full = false
	check(drop.try_collect() == 1 and bag.count == 1, "Explicit pickup credits one fish")
	check(drop.try_collect() == 0 and bag.count == 1, "Duplicate pickup rejected")
	control.begin_cast(hands.fishing_tip_world(), Vector3(0, 0.06, -5))
	control._process(0.5)
	await process_frame
	control.cancel_waiting()
	await create_timer(0.3).timeout
	check(not fx._line.visible and records.size() == 1, "Early cancel returns empty hook")
	print("FISHING_FEEDBACK_VISUAL failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
