extends SceneTree
## (Claude Code) Deterministic screenshots from the real cherry valley scene.
## Run without --headless: Godot writer needs a rendering context.

var world: Node3D
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.cv_qa"))
	world = (load("res://scenes/cherry_valley.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	world.set_process_unhandled_input(false)
	var waited: int = 0
	while not bool(world.build_complete) and waited < 2400:
		await process_frame
		waited += 1
	if not bool(world.build_complete):
		push_error("Cherry valley did not build for capture")
		quit(2)
		return
	world.player.set_process_unhandled_input(false)
	world.player.set_physics_process(false)
	await create_timer(0.6).timeout
	await _capture("01_spawn.png")

	var cinematic: Node3D = world.cinematic
	cinematic.enter(0)
	await create_timer(2.8).timeout
	await _capture("02_valley_panorama.png")
	cinematic.cycle(1)
	await create_timer(2.8).timeout
	await _capture("03_riverside.png")
	cinematic.cycle(1)
	await create_timer(2.8).timeout
	await _capture("04_shrine_path.png")
	cinematic.cycle(1)
	await create_timer(2.8).timeout
	await _capture("05_hillside.png")
	cinematic.exit()
	# Dedicated waterfall framing: the fall sits off the four tour anchors so it
	# needs its own camera to check the sheets, pool and mist.
	var fall_camera: Camera3D = Camera3D.new()
	fall_camera.name = "FallCheck"
	fall_camera.fov = 55.0
	fall_camera.far = 800.0
	world.add_child(fall_camera)
	# Stand in the river corridor, clear of the banks, and look up-valley.
	fall_camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(-14.0, 11.0, -58.0)).looking_at(Vector3(-24.0, 6.0, -88.0), Vector3.UP)
	fall_camera.current = true
	await create_timer(0.8).timeout
	await _capture("08_waterfall.png")
	fall_camera.current = false
	world._apply_mood("rain")
	world._apply_quality("high")
	cinematic.enter(0)
	await create_timer(2.8).timeout
	await _capture("06_rain.png")
	cinematic.exit()
	world._apply_mood("morning")
	cinematic.enter(0)
	await create_timer(2.8).timeout
	await _capture("07_morning.png")
	print("CHERRY_CAPTURE_DONE waited_frames=%d" % waited)
	quit(0)


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_root().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://.cv_qa").path_join(file_name)
	image.save_png(path)
	print("SAVED: ", path)
