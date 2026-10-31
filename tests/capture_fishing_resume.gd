extends SceneTree
## Focused screenshots for the resumed fishing task (Claude 2026-10-28).
## Only the parts whose code changed after the earlier capture set: the line now
## starts at the real rod tip in the hand, and the loot panel reads FishingLoot
## (Inventory-backed quantities). The previous 01-08 set is not regenerated.
## Run windowed: godot --path . --script res://tests/capture_fishing_resume.gd

var world: Node3D
var player: CharacterBody3D
var fishing: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.mvp_qa/fishing_mvp/resume"))
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
	await create_timer(0.4).timeout
	print("ROD_ANCHOR=", world.fishing_fx.rod_tip_anchor != null, " TIP=", world.fishing_fx.rod_tip())
	world._on_fishing_action()
	await create_timer(0.7).timeout
	await _capture("r1_waiting_line_from_tip.png")
	fishing.force = 1
	fishing._begin_bite()
	await create_timer(0.15).timeout
	world._on_fishing_action()
	await create_timer(0.6).timeout
	await _capture("r2_catch_message.png")
	await create_timer(3.2).timeout
	world._toggle_loadout()
	await create_timer(0.3).timeout
	await _capture("r3_backpack_loot.png")
	print("FISHING_RESUME_CAPTURE_COMPLETE loot_total=", world.loot.total_items())
	world.queue_free()
	await process_frame
	quit()


func _capture(filename: String) -> void:
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/fishing_mvp/resume/" + filename)
