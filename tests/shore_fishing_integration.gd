extends SceneTree
## One short integration round through the menu's actual shore destination.
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _run() -> void:
	create_timer(35.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1280, 720)
	var world: Node = load("res://scenes/shore_fishing_mvp.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await create_timer(0.5).timeout
	check(world.mode == 4 and world.guardian == null, "Shore entry starts fishing without guardian")
	check(world.shore_area != null, "Delivered shore prefab is in main gameplay")
	var player: CharacterBody3D = world.player
	var fishing: Node = world.fishing
	player.set_controls_active(true)
	player.global_position = world.shore_area.fishing_spot() + Vector3.UP * 0.08
	player.rotation.y = 0.0
	player.head.rotation.x = -0.48
	await create_timer(0.2).timeout
	check(world.fishing_fx.rod_tip_anchor == player.hands.fishing_tip_anchor(), "Real rod tip owns line")
	var before: int = world.loot.total_items()
	fishing.force_fish()
	world._on_fishing_action()
	check(fishing.state == 1, "Cast hits prefab water from dock")
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/fishing_mvp/integrated_shore.png")
	fishing._begin_bite()
	world._on_fishing_action()
	await create_timer(0.5).timeout
	check(world.loot.total_items() == before and world.pickups.size() == 1, "Fish lands before inventory credit")
	await create_timer(0.4).timeout
	check(world.loot.total_items() == before, "Standing near fish does not auto-collect")
	world._collect_nearest_pickup()
	await process_frame
	check(world.loot.total_items() == before + 1, "Explicit pickup credits fish once")
	fishing.cancel_silent("test")
	fishing.force_encounter()
	world._on_fishing_action()
	await create_timer(0.5).timeout
	fishing._begin_bite()
	world._on_fishing_action()
	await create_timer(0.5).timeout
	var enemy: CharacterBody3D = world.encounter_enemy
	check(is_instance_valid(enemy), "Encounter uses shore spawn markers")
	if is_instance_valid(enemy):
		check(enemy.global_position.distance_to(player.global_position) >= 5.0, "Encounter reaction distance")
		enemy.apply_damage(1000, Vector3.ZERO)
		await process_frame
		check(world.pickups.size() == 1, "Enemy drops material")
		if world.pickups.size() > 0:
			player.global_position = world.pickups[0].global_position + Vector3.UP * 0.08
			await create_timer(0.4).timeout
			world._collect_nearest_pickup()
			await process_frame
			check(world.loot.count("item_scale") == 1, "Material picked up into same bag")
	check(not fishing.encounter_active, "Fishing unlocked after encounter")
	var kept: int = world.loot.total_items()
	world.restart_round()
	check(world.loot.total_items() == kept, "Retry retains acquired items")
	world.start_round(2)
	world.start_round(4)
	check(world.fishing_fx.rod_tip_anchor == player.hands.fishing_tip_anchor(), "Re-enter rebinds line and map")
	print("SHORE_INTEGRATION failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
