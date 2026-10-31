extends SceneTree
## Check only the requested tree placement and independent fourth-slot firearm.

var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.mvp_qa/ue5_placement")
	var arena: Node3D = load("res://scenes/combat_mvp.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	var player: CharacterBody3D = arena.player
	player.set_physics_process(false)
	player.set_controls_active(true)
	arena.guardian.set_physics_process(false)
	player.position = Vector3(0, 0.08, 12)
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	_check(player.quick_slots[3] == "m1911" and player.quick_slots[2] == "steam_pistol", "Slot four is M1911; slot three remains the hand cannon")
	var trees: Node3D = arena.get_node("ExteriorTrees")
	_check(trees.get_child_count() == 3, "Exactly three trees")
	for tree: Node3D in trees.get_children():
		_check(tree.position.z < -22, "Tree planted beyond the rear wall")
	player.selected_slot = 3
	player._refresh_weapon()
	player.hands._cancel_pistol_spawn()
	for i: int in range(45):
		player.hands.update_pose(1.0 / 60, 0, false, -1, 0, true, 2)
		await process_frame
	_check(player.hands._m1911_pivot.visible and not player.hands._pistol.visible, "Fourth slot displays only M1911")
	await _capture("trees_and_m1911")
	player.position = Vector3(3, 0.08, -3)
	player.camera.rotation.x = 0.35
	await _capture("trees_over_wall")
	player.set_controls_active(true)
	_check(player.request_attack(), "M1911 accepts fire input")
	player._update_attack(0.04)
	_check(player.hands._pistol_recoil_left > 0, "M1911 emits a projectile and starts firearm recoil")
	player.selected_slot = 2
	player._refresh_weapon()
	player.hands.update_pose(1.0 / 60, 0, false, -1, 0, true, 2)
	_check(not player.hands._m1911_pivot.visible and player.hands._pistol.visible, "Switching back restores the original hand cannon")
	print("UE5_PLACEMENT_RESULT failures=%d" % failures)
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/ue5_placement/" + label + ".png")

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
