extends SceneTree
## Focused fishing return/drop checks and three rendered checkpoints.
var failures: int = 0
var world: Node
var fishing: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, title: String) -> void:
	print("PASS " if ok else "FAIL ", title)
	if not ok:
		failures += 1

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/fishing_mvp/feedback_" + name + ".png")

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1280, 720)
	world = load("res://scenes/shore_fishing_mvp.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await create_timer(0.5).timeout
	var player: CharacterBody3D = world.player
	fishing = world.fishing
	player.set_controls_active(true)
	player.global_position = world.shore_area.fishing_spot() + Vector3.UP * 0.08
	player.head.rotation.x = -0.48
	await create_timer(0.25).timeout
	fishing.force_fish()
	world._on_fishing_action()
	await create_timer(0.5).timeout
	fishing._begin_bite()
	fishing.set_paused(true)
	world.set_process(false)
	# Controlled bite fraction isolates pulse shape from random countdown sampling.
	fishing._window_left = fishing._window_initial * (1.0 - 0.2 / 3.0)
	world.fishing_fx._process(0.0)
	fishing.set_paused(false)
	world.fishing_fx._process(0.0)
	var down: Vector3 = world.fishing_fx._bobber.global_position
	check(down.y < world.shore_area.water_level() - 0.15, "Bite visibly sinks below surface")
	await snap("bite")
	fishing.set_paused(true)
	world.fishing_fx._process(0.2)
	check(world.fishing_fx._bobber.global_position == down, "Paused visual remains still")
	fishing.set_paused(false)
	world.set_process(true)
	world._on_fishing_action()
	await create_timer(0.14).timeout
	check(world.fishing_fx._bobber.global_position.distance_to(world.fishing_fx.rod_tip()) < down.distance_to(world.fishing_fx.rod_tip()), "Bobber travels toward real rod tip")
	await snap("return")
	await create_timer(0.6).timeout
	check(not world.fishing_fx._line.visible and not world.fishing_fx._bobber.visible, "Line and bobber fully stowed after return")
	check(fishing.state == 0, "No extra three-second result lock")
	check(world.loot.total_items() == 0 and world.pickups.size() == 1, "One physical catch and no premature credit")
	var drop: Node3D = world.pickups[0]
	check(drop.global_position.y > 0.5, "Catch stays on wooden deck rather than below it")
	player.head.rotation.x = -1.05
	await create_timer(0.3).timeout
	await snap("drop")
	var full_amount: int = drop.amount
	# A full bag stub uses the same public overflow contract as the real inventory.
	var blocked: Node = Node.new()
	var stub: GDScript = GDScript.new()
	stub.source_code = "extends Node\nfunc try_add(_id: String, n: int) -> int:\n\treturn n\n"
	stub.reload()
	blocked.set_script(stub)
	root.add_child(blocked)
	drop.bag = blocked
	check(drop.try_collect() == 0 and drop.amount == full_amount, "Full bag leaves catch on ground")
	drop.bag = world.loot
	blocked.queue_free()
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_F
	event.pressed = true
	world._unhandled_input(event)
	check(world.loot.total_items() == 1, "F picks up exactly one catch")
	world._unhandled_input(event)
	check(world.loot.total_items() == 1, "Repeated F cannot duplicate catch")
	await process_frame
	# Early cancel also returns the line, with no loot.
	player.head.rotation.x = -0.48
	world._on_fishing_action()
	await create_timer(0.5).timeout
	world._on_fishing_action()
	await create_timer(0.3).timeout
	check(not world.fishing_fx._line.visible and world.loot.total_items() == 1, "Early reel stows line without reward")
	world.restart_round()
	check(world.loot.total_items() == 1, "Retry keeps collected inventory")
	print("FISHING_FEEDBACK failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
