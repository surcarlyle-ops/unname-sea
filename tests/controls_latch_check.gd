extends SceneTree
var failures: int = 0
var world: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, title: String) -> void:
	print("PASS " if ok else "FAIL ", title)
	if not ok:
		failures += 1

func key(code: int) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event

func click_button(title: String) -> void:
	await process_frame
	var found: Button
	for child: Node in world.play_menu._column.get_children():
		if child is Button and child.text == title:
			found = child
	if found == null:
		check(false, "Button exists: " + title)
		return
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = found.get_global_rect().get_center()
	down.pressed = true
	root.push_input(down, true)
	var up: InputEventMouseButton = down.duplicate()
	up.pressed = false
	root.push_input(up, true)
	await process_frame

func _run() -> void:
	create_timer(20.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1280, 720)
	world = load("res://scenes/shore_fishing_mvp.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await create_timer(0.4).timeout
	var player: CharacterBody3D = world.player
	player.set_controls_active(true)
	world._input(key(KEY_ESCAPE))
	check(world.play_menu.opened and player.menu_open and not player.controls_active, "Esc opens action menu and pauses player")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/fishing_mvp/action_menu.png")
	await click_button("选择试炼")
	await click_button("清怪")
	check(world.mode == 0 and not world.play_menu.opened and player.controls_active, "Real menu click switches trial and resumes")
	world._input(key(KEY_ESCAPE))
	await click_button("选择试炼")
	await click_button("钓鱼")
	check(world.mode == 4, "Fishing trial remains available through menu")
	world._input(key(KEY_ESCAPE))
	await click_button("开发工具")
	await click_button("下一次钓到鱼")
	check(world.fishing.force == 1 and not world.play_menu.opened, "Dev override lives in menu")
	world._unhandled_input(key(KEY_G))
	check(world.mode == 4, "Old trial keys no longer switch scenes")
	world._spawn_pickup("fish_pale_minnow", 1, player.global_position)
	await create_timer(0.3).timeout
	var before: int = world.loot.count("fish_pale_minnow")
	world._unhandled_input(key(KEY_T))
	check(world.loot.count("fish_pale_minnow") == before, "T no longer picks up")
	world._unhandled_input(key(KEY_F))
	check(world.mode == 4 and world.loot.count("fish_pale_minnow") == before + 1, "F collects instead of switching trial")
	player._unhandled_input(key(KEY_TAB))
	check(player.menu_open, "Tab opens inventory")
	world._input(key(KEY_ESCAPE))
	check(not player.menu_open and not world.play_menu.opened, "Esc closes inventory without opening another panel")
	# Test force timing directly on the actual grapple, independent of render frame rate.
	player.set_physics_process(false)
	player.grapple.set_physics_process(false)
	player.global_position = world.shore_area.fishing_spot() + Vector3.UP * 0.08
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	world._box("LatchTestAnchor", player.camera.global_position + Vector3(0, 0, -6), Vector3(1, 2, 1), Color.GRAY)
	await physics_frame
	await physics_frame
	var hook: Node3D = player.grapple
	hook.reset()
	check(hook.try_attach(), "Grapple accepts launch")
	hook._physics_process(hook.windup_duration + 0.001)
	check(hook.is_attached(), "Hook hits test wall")
	check(is_equal_approx(hook._pull_start_delay - hook.rope_visual.shot_duration, 1.0 / 15.0), "Impact hold is one third of the original 0.2 seconds")
	player.velocity = Vector3(1.1, 0.25, 0.0)
	var velocity: Vector3 = player.velocity
	hook._physics_process(hook.rope_visual.shot_duration + hook.impact_pull_delay - 0.001)
	check(player.velocity == velocity and not hook.is_pulling(), "No pull, damping or impulse during impact hold")
	check(not hook.apply_super_grapple(), "Jump boost cannot bypass impact hold")
	hook._physics_process(0.002)
	check(hook.is_pulling() and player.velocity != velocity, "Pull starts after hold")
	hook.release()
	check(not hook.is_attached(), "Release works after pull")
	hook.try_attach()
	hook._physics_process(hook.windup_duration + 0.001)
	hook.release()
	check(not hook.is_attached(), "Release cancels during hold")
	print("CONTROLS_LATCH failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
