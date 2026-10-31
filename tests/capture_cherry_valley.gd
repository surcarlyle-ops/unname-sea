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
		if waited % 200 == 0:
			print("BUILD_WAIT frames=", waited)
	if not bool(world.build_complete):
		push_error("Cherry valley did not build for capture")
		quit(2)
		return
	world.player.set_process_unhandled_input(false)
	world.player.set_physics_process(false)
	await _wait(0.6)
	await _capture("01_spawn.png")

	var cinematic: Node3D = world.cinematic
	cinematic.enter(0)
	await _wait(2.8)
	await _capture("02_valley_panorama.png")
	cinematic.cycle(1)
	await _wait(2.8)
	await _capture("03_riverside.png")
	cinematic.cycle(1)
	await _wait(2.8)
	await _capture("04_shrine_path.png")
	cinematic.cycle(1)
	await _wait(2.8)
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
	await _wait(0.8)
	await _capture("08_waterfall.png")
	fall_camera.current = false
	# Mood swaps reuse the same public path as the in-game key: writing the mood
	# straight into the world was what hung the run after 08_waterfall, before
	# either of the last two shots was written.
	await _switch_mood("rain")
	cinematic.enter(0)
	await _wait(2.8)
	await _capture("06_rain.png")
	cinematic.exit()
	await _switch_mood("morning")
	cinematic.enter(0)
	await _wait(2.8)
	await _capture("07_morning.png")
	cinematic.exit()
	print("CHERRY_CAPTURE_DONE waited_frames=%d" % waited)
	quit(0)


## Wall-clock wait that does not depend on the tree's main loop advancing the
## SceneTreeTimer: in this harness a --headless-free run stalled inside
## create_timer once the scene had been alive a while, which is what left the
## two mood shots unwritten.
func _wait(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _capture(file_name: String) -> void:
	print("CAPTURE_BEGIN: ", file_name)
	var started: int = Time.get_ticks_msec()
	await RenderingServer.frame_post_draw
	print("CAPTURE_DRAW ", file_name, " ms=", Time.get_ticks_msec() - started)
	var image: Image = get_root().get_texture().get_image()
	print("CAPTURE_READ ", file_name, " ms=", Time.get_ticks_msec() - started)
	var path: String = ProjectSettings.globalize_path("res://.cv_qa").path_join(file_name)
	image.save_png(path)
	print("SAVED: ", path)


## Walk the public mood cycle until the requested key is current, so the capture
## never calls world internals that the player path does not use.
func _switch_mood(key: String) -> void:
	var guard: int = 0
	while str(world.lighting.current_key) != key and guard < 4:
		var started: int = Time.get_ticks_msec()
		world.lighting.next_mood()
		print("MOOD_STEP lighting_ms=", Time.get_ticks_msec() - started)
		started = Time.get_ticks_msec()
		world._apply_mood(str(world.lighting.current_key))
		print("MOOD_STEP world_ms=", Time.get_ticks_msec() - started)
		guard += 1
	await _wait(0.9)
	print("MOOD_SWITCH_DONE ", key)
