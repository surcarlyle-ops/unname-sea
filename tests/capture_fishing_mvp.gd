extends SceneTree
## Fishing MVP screenshots from the real scene (CodeBuddy 2026-10-28).
## Run windowed: godot --path . --script res://tests/capture_fishing_mvp.gd

var world: Node3D
var player: CharacterBody3D
var fishing: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.mvp_qa/fishing_mvp"))
	world = (load("res://scenes/combat_mvp.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	await create_timer(0.4).timeout
	player = world.player
	fishing = world.fishing
	player.set_process_unhandled_input(false)
	world.set_process_unhandled_input(false)
	world.start_round(4)
	await create_timer(0.5).timeout
	player.set_controls_active(true)
	player.set_physics_process(false)
	player.global_position = Vector3(-8.0, 0.08, 10.0)
	player.rotation.y = PI
	player.head.rotation.x = -0.42
	player.hands.set_weapon("fishing_rod")
	await _capture("01_bank_pond.png")
	world._on_fishing_action()
	await create_timer(0.18).timeout
	await _capture("02_cast_flight.png")
	await create_timer(0.5).timeout
	await _capture("03_waiting_bobber.png")
	fishing.force = 1
	fishing._begin_bite()
	await create_timer(0.12).timeout
	await _capture("04_bite.png")
	world._on_fishing_action()
	await create_timer(0.55).timeout
	await _capture("05_catch_message.png")
	await create_timer(3.2).timeout
	fishing.force = 2
	world._on_fishing_action()
	await create_timer(0.5).timeout
	fishing._begin_bite()
	await create_timer(0.1).timeout
	world._on_fishing_action()
	await create_timer(0.9).timeout
	await _capture("06_encounter_spawn.png")
	if is_instance_valid(world.encounter_enemy):
		world.encounter_enemy.apply_damage(50, Vector3.ZERO)
		await create_timer(1.2).timeout
		await _capture("07_loot_pickup.png")
	player.global_position = world.pickups[0].global_position + Vector3(0, 0.08, 0) if world.pickups.size() > 0 else player.global_position
	await create_timer(0.4).timeout
	world._toggle_loadout()
	await create_timer(0.3).timeout
	await _capture("08_backpack_loot.png")
	print("FISHING_CAPTURE_COMPLETE")
	world.queue_free()
	await process_frame
	quit()


func _capture(filename: String) -> void:
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/fishing_mvp/" + filename)
