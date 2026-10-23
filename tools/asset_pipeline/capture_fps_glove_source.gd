extends SceneTree
## Render the supplied static glove from several sides before skinning it.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	current_scene = world
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.22, 0.26, 0.29)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.85
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	world.add_child(environment_node)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -20, 0)
	sun.light_energy = 1.0
	world.add_child(sun)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(25, 145, 0)
	fill.light_energy = 0.45
	world.add_child(fill)
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var error: Error = document.append_from_file(ProjectSettings.globalize_path("res://assets/characters/fps_gloves/source/hand_glove_04_raw.glb"), state)
	if error != OK:
		push_error("Cannot read supplied glove: %s" % error_string(error))
		quit(1)
		return
	world.add_child(document.generate_scene(state))
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.8
	world.add_child(camera)
	camera.current = true
	var target: Vector3 = Vector3(0, 0.18, 0)
	var views: Dictionary = {
		"front": Vector3(0, 0.25, 1.8),
		"back": Vector3(0, 0.25, -1.8),
		"top": Vector3(0, 1.8, 0.08),
		"angled": Vector3(0.6, 0.8, 1.5)
	}
	for view_name: String in views:
		camera.position = views[view_name]
		camera.look_at(target)
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		var output: String = "res://.mvp_qa/glove_source_%s.png" % view_name
		root.get_texture().get_image().save_png(output)
	print("GLOVE_SOURCE_CAPTURE_COMPLETE")
	world.queue_free()
	await process_frame
	quit()
