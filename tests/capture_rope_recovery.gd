extends SceneTree
## Real viewmodel close-up and lifecycle checks for the approved closed rope grip.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.mvp_qa/rope_recovery")
	var arena: Node3D = load("res://scenes/combat_mvp.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	var player: CharacterBody3D = arena.player
	player.set_controls_active(true)
	player.set_physics_process(false)
	arena.guardian.set_physics_process(false)
	player.position = Vector3(8, 0.02, 20)
	player.rotation = Vector3.ZERO
	var hands: Node3D = player.hands
	hands.set_weapon("steam_pistol")
	hands._pistol_spawn = 0
	player.grapple.set_physics_process(false)
	player.grapple.anchor = Vector3(10, 5, 9)
	player.grapple.anchor_normal = Vector3.BACK
	player.grapple._raycast_anchor()
	player.grapple.state = player.grapple.State.ATTACHED
	player.grapple._update_rope_visual(true)
	for i: int in range(45):
		hands.update_pose(1.0 / 60, 8, true, -1, 0, true, 2, {"grounded":false, "grappling":true, "grapple_anchor":player.grapple.anchor})
		await process_frame
		if DisplayServer.get_name() != "headless" and i in [0, 1, 3, 8]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.mvp_qa/rope_recovery/rope_launch_%02d.png" % i)
	var errors: int = 0
	var visual: Node3D = player.grapple.rope_visual
	var max_deviation: float = 0.0
	var a: Vector3 = visual.rope_points[6]
	var b: Vector3 = visual.rope_points[16]
	for i: int in range(7, 16):
		max_deviation = maxf(max_deviation, visual.rope_points[i].distance_to(Geometry3D.get_closest_point_to_segment(visual.rope_points[i], a, b)))
	if max_deviation > 0.020 or visual.shot_duration > 0.061 or player.grapple._hook_head.global_position.distance_to(player.grapple.anchor) > 0.01:
		errors += 1
	print("ROPE_TENSION deviation=%.4fm shot_duration=%.4fs reached_anchor=%s" % [max_deviation, visual.shot_duration, player.grapple._hook_head.global_position.distance_to(player.grapple.anchor) < 0.01])
	# The palm section must follow the actual grasp axis, not the anchor line.
	var palm_axis: Vector3 = hands.grapple_rope_tangent()
	var palm_line: Vector3 = (visual.rope_points[6] - visual.rope_points[4]).normalized()
	if absf(palm_axis.dot(palm_line)) < 0.999 or visual.rope_points[5].distance_to(hands.grapple_grip_point()) > 0.001:
		errors += 1
	var reference: Dictionary = hands.left_glove._rope_pose
	for name: String in reference:
		var values: Array = reference[name]
		var expected: Quaternion = Quaternion(values[0], values[1], values[2], values[3]).normalized()
		var actual: Quaternion = hands.left_glove.skeleton.get_bone_pose_rotation(hands.left_glove.skeleton.find_bone(name))
		if expected.angle_to(actual) > 0.01:
			errors += 1
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.mvp_qa/rope_recovery/rope_restored.png")
	# Check the steep upward camera angles from the user's screenshot as well.
	for pitch: float in [0.7, 1.1]:
		player.camera.rotation.x = pitch
		player.grapple.anchor = player.camera.global_transform * Vector3(2, 1, -12)
		for i: int in range(30):
			hands.update_pose(1.0 / 60, 8, true, -1, 0, true, 2, {"grounded":false, "grappling":true, "grapple_anchor":player.grapple.anchor})
			await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.mvp_qa/rope_recovery/rope_up_%d.png" % roundi(pitch * 100))
	player.grapple.reset()
	for i: int in range(50):
		hands.update_pose(1.0 / 60, 0, false, -1, 0, true, 2)
		await process_frame
	if hands._rope_wrist_bent or hands.left_glove._override_weight > 0.001:
		errors += 1
	print("ROPE_GRIP_RESULT fingers=15 release_checked=true failures=%d" % errors)
	arena.queue_free()
	await process_frame
	quit(0 if errors == 0 else 1)
