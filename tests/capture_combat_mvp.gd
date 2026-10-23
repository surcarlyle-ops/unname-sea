extends SceneTree
## Deterministic screenshots from the real scene, with live OS input disabled.

var world: Node3D
var player: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.mvp_qa"))
	world = (load("res://scenes/combat_mvp.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	world.start_round(0)
	player = world.player
	player.set_process_unhandled_input(false)
	world.set_process_unhandled_input(false)
	await create_timer(0.3).timeout
	player.set_controls_active(true)
	player.set_physics_process(false)
	for enemy: Node in world.enemies.get_children():
		enemy.set_physics_process(false)
	player.head.rotation.x = -0.08
	await _capture("01_first_person.png")
	player.hands.update_pose(0.016, 0.0, false, 0.43, 0, true, 1.2)
	await _capture("02_melee_swing.png")
	player.hands.update_pose(0.016, 0.0, false, -1.0, 0, true, 1.2)
	var enemy: CharacterBody3D = world.enemies.get_child(0) as CharacterBody3D
	enemy.position = Vector3(0.3, 0.01, 6.3)
	enemy.state = enemy.State.WINDUP
	enemy._update_visual()
	player.head.rotation.x = -0.25
	await _capture("03_enemy_windup.png")
	player.head.look_at(Vector3(0, 6.0, -9))
	player.grapple.try_attach()
	player.grapple.set_physics_process(false)
	player.grapple._update_rope_visual(true)
	await _capture("04_grapple.png")
	player.grapple.reset()
	world._toggle_loadout()
	await _capture("05_loadout.png")
	print("COMBAT_CAPTURE_COMPLETE")
	world.queue_free()
	await process_frame
	quit()


func _capture(filename: String) -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/" + filename)
