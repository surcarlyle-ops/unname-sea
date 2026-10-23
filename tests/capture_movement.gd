extends SceneTree
## Render the real movement practice and stance changes without live mouse input.

var world: Node3D
var player: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	world = (load("res://scenes/combat_mvp.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	player = world.player
	player.set_process_unhandled_input(false)
	world.set_process_unhandled_input(false)
	await create_timer(0.7).timeout
	player.set_controls_active(true)
	player.head.rotation.x = -0.05
	await _frames(3)
	player.set_controls_active(true)
	await _capture("movement_01_route.png")
	Input.action_press("move_up")
	await _frames(36)
	Input.action_press("fps_crouch")
	await _frames(20)
	await _capture("movement_02_slide.png")
	Input.action_release("move_up")
	Input.action_press("fps_walk")
	Input.action_release("fps_crouch")
	player.reset_to_spawn()
	player.position = Vector3(-19, 0.05, -4.8)
	await _frames(8)
	Input.action_press("move_up")
	Input.action_press("fps_jump")
	await _frames(12)
	await _capture("movement_03_mantle.png")
	Input.action_release("move_up")
	Input.action_release("fps_jump")
	player.set_controls_active(false)
	await _capture("movement_04_controls.png")
	world.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("MOVEMENT_CAPTURE_COMPLETE")
	quit()


func _frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _capture(filename: String) -> void:
	# Freeze only for the render so that the captured pose matches the requested state.
	player.set_physics_process(false)
	player.grapple.set_physics_process(false)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/" + filename)
	player.set_physics_process(true)
	player.grapple.set_physics_process(player.controls_active)
