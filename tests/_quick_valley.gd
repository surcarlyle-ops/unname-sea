extends SceneTree
## (CodeBuddy) Throwaway fast iteration: three fixed shots, no walk, no mood sweep.

var world: Node3D
var tag: String = "q"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		tag = str(args[0])
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.cv_qa/codebuddy_polish_round2"))
	world = (load("res://scenes/cherry_valley.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	var waited: int = 0
	while not bool(world.build_complete) and waited < 3000:
		await process_frame
		waited += 1
	world.player.set_process_unhandled_input(false)
	world.player.set_physics_process(false)
	await create_timer(0.6).timeout
	await _shot("02_bridge", Vector3(-3.0, 2.4, 18.0), Vector3(-15.0, 1.4, 5.0), 70.0, 0.0)
	await _shot("03_riverside", Vector3(3.0, 0.0, 26.0), Vector3(-15.0, 1.6, 6.0), 68.0, 1.15)
	await _shot("04_waterfall", Vector3(-16.0, 2.4, -58.0), Vector3(-22.0, 10.0, -88.0), 66.0, 0.0)
	await _shot("05_waterfall_player", Vector3(-30.0, 0.0, -72.0), Vector3(-18.0, 4.0, -84.0), 62.0, 1.6)
	await _shot("01_spawn", Vector3(22.0, 0.0, 70.0), Vector3(6.0, 3.4, 18.0), 78.0, 1.66)
	quit(0)


func _shot(file_name: String, position: Vector3, target: Vector3, fov: float, ground_offset: float) -> void:
	var resolved: Vector3 = position
	if ground_offset > 0.0:
		resolved.y = float(world.terrain.height_at(position.x, position.z)) + ground_offset
	var camera: Camera3D = Camera3D.new()
	camera.name = "Shot"
	camera.fov = fov
	camera.far = 1200.0
	world.add_child(camera)
	camera.global_transform = Transform3D(Basis.IDENTITY, resolved).looking_at(target, Vector3.UP)
	camera.current = true
	await create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_root().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://.cv_qa/codebuddy_polish_round2").path_join("%s_%s.png" % [file_name, tag])
	image.save_png(path)
	print("SAVED: ", path)
	camera.queue_free()
