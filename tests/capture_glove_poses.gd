extends SceneTree
## Render real skinned poses, then the integrated first-person view.

const GLOVE: Script = preload("res://scripts/mvp/fps_glove.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	current_scene = world
	var sky: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.20, 0.23, 0.25)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.85
	sky.environment = environment
	world.add_child(sky)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	world.add_child(sun)
	var right: Node3D = GLOVE.new() as Node3D
	right.position.x = 0.14
	world.add_child(right)
	var left: Node3D = GLOVE.new() as Node3D
	left.left_hand = true
	left.position.x = -0.14
	world.add_child(left)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.58
	world.add_child(camera)
	camera.position = Vector3(0.0, 0.8, -0.5)
	camera.look_at(Vector3(0, 0, -0.01))
	camera.current = true
	var poses: Dictionary = {"open": 0.0, "relaxed": 0.18, "grip": 0.86}
	for pose: String in poses:
		right.set_pose_immediate(float(poses[pose]))
		left.set_pose_immediate(float(poses[pose]))
		await _capture("glove_rig_%s.png" % pose)
	world.queue_free()
	await process_frame
	var arena: Node3D = (load("res://scenes/combat_mvp.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	var player: CharacterBody3D = arena.player
	player.set_process_unhandled_input(false)
	arena.set_process_unhandled_input(false)
	player.set_controls_active(true)
	await create_timer(0.2).timeout
	player.set_physics_process(false)
	player.grapple.set_physics_process(false)
	player.selected_slot = 0
	player.hands.set_weapon("tide_blade")
	player.hands.update_pose(2.0, 0.0, false, -1.0, 0, true, 1.2)
	player.hands.right_glove.set_pose_immediate(0.86)
	player.hands.left_glove.set_pose_immediate(0.18)
	await _capture("glove_game_blade.png")
	player.selected_slot = 1
	player.hands.update_pose(0.5, 0.0, false, -1.0, 0, false, 1.2)
	await _capture("glove_game_empty.png")
	player.hands.update_pose(1.0, 8.2, true, -1.0, 0, false, 1.2, {"stride_phase": 1.0})
	await _capture("glove_game_run.png")
	player.hands.update_pose(1.0, 0.0, false, -1.0, 0, true, 1.2, {"mantling": true})
	await _capture("glove_game_mantle.png")
	player.selected_slot = 0
	player.hands.update_pose(1.0, 8.2, true, -1.0, 0, true, 1.2, {"sliding": true})
	await _capture("glove_game_slide.png")
	player.hands.update_pose(1.0, 0.0, false, 0.42, 0, true, 1.2)
	await _capture("glove_game_swing.png")
	player.hands.update_pose(1.0, 0.0, false, -1.0, 0, true, 1.2)
	var close_camera: Camera3D = Camera3D.new()
	close_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	close_camera.size = 0.23
	close_camera.near = 0.01
	arena.add_child(close_camera)
	var wrist: Node3D = player.hands.right_arm
	var grip_point: Vector3 = wrist.to_global(player.hands.GRIP_CENTER)
	close_camera.global_position = wrist.to_global(Vector3(0.0, -0.32, -0.132))
	close_camera.look_at(grip_point, wrist.global_basis.x.normalized())
	close_camera.current = true
	await _capture("glove_grip_palm.png")
	close_camera.global_position = wrist.to_global(Vector3(0.0, 0.30, -0.132))
	close_camera.look_at(grip_point, wrist.global_basis.x.normalized())
	await _capture("glove_grip_back.png")
	arena.queue_free()
	await process_frame
	print("GLOVE_POSE_CAPTURE_COMPLETE")
	quit()


func _capture(filename: String) -> void:
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/" + filename)
