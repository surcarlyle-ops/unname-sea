extends SceneTree
## Real input and physics checks for the movement chain, stance safety and traversal.
##
## Test lane: this suite used to run at x=18, but the arena's wall-run wall now
## occupies x 17.2–17.8 for z 1–11. With a 0.35 m capsule radius the player clipped
## it, which killed speed mid-check, aborted slides and made _clear_at() fail, so
## crouch-stand and mantle refused to start. LANE_X is a corridor a shape scan shows
## clear from z=16 down to z=-8 (see .mvp_qa/motion_fix/lanes.log).
const LANE_X: float = 2.5

var checks: int = 0
var failures: int = 0
var world: Node3D
var player: CharacterBody3D
var movement_sounds: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(55.0).timeout.connect(func() -> void: push_error("Motion test timeout"); quit(2))
	world = (load("res://scenes/combat_mvp.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	player = world.player
	player.movement_sound.connect(func(sound_name: String, _strength: float) -> void: movement_sounds.append(sound_name))
	# The arena now boots into the guardian trial (mode 3) and the player's collision
	# mask includes enemies, so a guardian can physically block the lane mid-check.
	# This suite measures the enemy-free movement practice, so establish that round
	# first instead of assuming it is the default.
	world.start_round(2)
	await _frames(8)
	_check(world.mode == 2 and world.enemies.get_child_count() == 0, "Default movement practice contains no attacking enemies")
	await _reset(Vector3(LANE_X, 0.05, 16))
	_check(player.velocity.length() < 0.01, "Auto-run does not move the player without directional input")
	var walk_binding: InputEventKey = InputMap.action_get_events("fps_walk")[0] as InputEventKey
	_check(walk_binding.physical_keycode == KEY_SHIFT, "Shift is bound to hold-to-walk")
	Input.action_press("move_up")
	await _frames(30)
	_check(absf(player.velocity.z + 8.2) < 0.02, "Moving forward runs by default without holding Shift")
	Input.action_press("fps_walk")
	await _frames(20)
	_check(absf(player.velocity.z + 5.2) < 0.02, "Holding Shift slows movement to walking speed")
	Input.action_release("fps_walk")
	await _frames(20)
	_check(absf(player.velocity.z + 8.2) < 0.02, "Releasing Shift resumes running without a toggle")
	var held_stop: Dictionary = await _measure_stop(true)
	var released_stop: Dictionary = await _measure_stop(false)
	_check(absf(float(held_stop.seconds) - float(released_stop.seconds)) < 0.018, "Stopping time is independent of holding walk while releasing forward: " + str(held_stop) + " / " + str(released_stop))
	_check(absf(float(held_stop.distance) - float(released_stop.distance)) < 0.03, "Stopping distance is independent of the walk modifier")
	_check(float(released_stop.seconds) <= 0.37, "Ordinary sprint braking no longer uses grapple overspeed deceleration")
	await _reset(Vector3(LANE_X, 0.05, 10))
	Input.action_press("move_right")
	await _frames(25)
	_check(absf(player.velocity.x - 5.5) < 0.02, "Agile profile uses a lower sideways sprint speed")
	await _reset(Vector3(LANE_X, 0.05, 10))
	Input.action_press("move_down")
	await _frames(25)
	_check(absf(player.velocity.z - 4.6) < 0.02, "Backward sprint remains available with its own speed limit")
	await _reset(Vector3(LANE_X, 0.05, 16))
	var profile_key: InputEventKey = InputEventKey.new()
	profile_key.physical_keycode = KEY_V
	profile_key.pressed = true
	player._unhandled_input(profile_key)
	Input.action_press("move_up")
	await _frames(30)
	_check(player.motion.profile_id == "light_reference" and absf(player.velocity.z + 6.6) < 0.02, "F4 selects a playable Light reference speed of 6.6 m/s")
	player.reset_to_spawn()
	_check(player.motion.profile_id == "light_reference", "Retry preserves the selected comparison profile")
	player._unhandled_input(profile_key)
	await _reset(Vector3(LANE_X, 0.05, 16))
	player.velocity.z = -4.2
	Input.action_press("move_up")
	Input.action_press("fps_crouch")
	await _frames(5)
	_check(player.motion.sliding and player.motion.slide_count == 1, "An early crouch press buffers into a slide while sprint accelerates")
	await _reset(Vector3(LANE_X, 0.05, 16))
	movement_sounds.clear()
	await _frames(20)
	_check(not movement_sounds.has("step"), "Standing still does not produce footsteps")
	Input.action_press("move_up")
	await _frames(40)
	_check(movement_sounds.has("step"), "Actual grounded travel produces footstep feedback")
	await _reset(Vector3(LANE_X, 2.5, 16))
	movement_sounds.clear()
	await _frames(45)
	_check(movement_sounds.has("land") and not movement_sounds.has("step"), "A vertical landing plays an impact without phantom footsteps")
	await _reset(Vector3(LANE_X, 0.05, 14))
	Input.action_press("fps_crouch")
	await _frames(12)
	_check(player.motion.crouching and absf(player.get_node("CollisionShape3D").shape.height - 1.05) < 0.01, "Crouch reduces the real collider height")
	_check(player.head.position.y < 1.03, "Eye height smoothly follows crouching")
	var roof: Node3D = world._box("TestLowCeiling", Vector3(LANE_X, 1.4, 10), Vector3(3.0, 0.35, 3.0), Color.WHITE)
	Input.action_press("move_up")
	await _frames(80)
	Input.action_release("move_up")
	Input.action_release("fps_crouch")
	await _frames(8)
	_check(player.global_position.z < 11.0 and player.motion.crouching, "A player can pass under a low ceiling while crouched")
	_check(player.head.position.y < 1.03, "Releasing crouch under a ceiling cannot stand through it")
	Input.action_press("move_up")
	await _frames(80)
	Input.action_release("move_up")
	await _frames(12)
	_check(not player.motion.crouching and player.head.position.y > 1.55, "Standing resumes automatically when overhead clearance returns")
	world.remove_child(roof)
	roof.queue_free()
	await _reset(Vector3(LANE_X, 0.05, 16))
	Input.action_press("move_up")
	await _frames(40)
	Input.action_press("fps_crouch")
	await _frames(3)
	_check(player.motion.sliding and player.motion.slide_count == 1, "Sprint plus crouch starts a slide without repeated activation")
	var slide_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	_check(slide_speed > 6.5 and player.motion.crouching, "Slide carries sprint momentum with a low collider")
	var lowest_shake: float = INF
	var highest_shake: float = -INF
	var peak_roll: float = 0.0
	for index: int in range(12):
		await _frames(1)
		lowest_shake = minf(lowest_shake, player.camera.position.y)
		highest_shake = maxf(highest_shake, player.camera.position.y)
		peak_roll = maxf(peak_roll, absf(rad_to_deg(player.camera.rotation.z)))
	_check(player.head.position.y < 0.94 and player.head.position.y > 0.78, "Sliding smoothly lowers eye height beyond ordinary crouching")
	# The entry impulse oscillates the camera by at most twice the configured shake.
	# The old 6 mm ceiling predates the retune to 9 mm (slide_camera_shake), so the
	# bound is derived from the tuning value instead of a fixed number.
	var shake_range: float = highest_shake - lowest_shake
	var shake_bound: float = 2.0 * float(player.motion._tuning.slide_camera_shake) + 0.001
	_check(shake_range > 0.001 and shake_range <= shake_bound, "Slide vibration is visible and bounded by the configured shake: %.4f" % shake_range)
	_check(peak_roll > 0.1 and peak_roll < 0.8 and player.camera.position.z > 0.015, "Slide has a small bounded lean and backward camera offset")
	_check((-player.camera.global_basis.z).dot(-player.head.global_basis.z) > 0.99999, "Slide feedback preserves mouse pitch and the forward aiming direction")
	_check(player.camera.fov <= 81.81, "Slide field-of-view feedback stays within its configured limit")
	slide_speed = Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_press("fps_jump")
	await _frames(3)
	Input.action_release("fps_jump")
	_check(not player.motion.sliding and player.velocity.y > 4.0, "Jump can interrupt the slide immediately")
	_check(Vector2(player.velocity.x, player.velocity.z).length() >= slide_speed - 0.3, "Slide-jump preserves horizontal momentum")
	Input.action_release("fps_crouch")
	# 先停下再验证"回到普通姿态"：跑动时镜头本来就有起伏（camera_bob），
	# 这条检查写在起伏功能之前，旧版一直按着 move_up 会误判。
	Input.action_release("move_up")
	# 45 帧只够减到 ~3.6 m/s，仍在跑动起伏区间；等它彻底停下再判断。
	await _frames(100)
	_check(player.camera.position.length() < 0.001 and absf(player.camera.rotation.z) < 0.001 and player.head.position.y > 1.55,
		"Leaving the slide returns the view smoothly to its ordinary pose (pos=%.5f roll=%.5f head=%.3f)" % [
			player.camera.position.length(), absf(player.camera.rotation.z), player.head.position.y])
	await _reset(Vector3(LANE_X, 0.05, 16))
	player._settings.slide_camera_motion_scale = 0.0
	player.velocity.z = -8.2
	Input.action_press("fps_crouch")
	await _frames(15)
	_check(player.motion.sliding and player.camera.position.length() < 0.00001 and player.camera.rotation.length() < 0.00001, "Slide feedback can be disabled without disabling sliding or crouch collision")
	player._settings.slide_camera_motion_scale = 1.0
	await _frames(6)
	player.set_controls_active(false)
	_check(player.camera.position.length() < 0.00001 and player.camera.rotation.length() < 0.00001, "Pausing during a slide clears visual offsets immediately")
	player.reset_to_spawn()
	_check(player.camera.position.length() < 0.00001 and absf(player.head.position.y - 1.6) < 0.001, "Retry clears the slide camera pose and restores standing eye height")
	await _reset(Vector3(LANE_X, 0.05, 16))
	player.velocity.z = -8.2
	Input.action_press("fps_crouch")
	await _frames(85)
	_check(not player.motion.sliding and player.motion.slide_count == 1, "Holding crouch does not loop slides forever on flat ground")
	await _reset(Vector3(LANE_X, 2.5, 16))
	player.velocity.z = -8.2
	Input.action_press("fps_crouch")
	await _frames(38)
	_check(player.motion.slide_count == 1 and player.motion.sliding, "Holding crouch in the air chains directly into a slide on landing")
	await _reset(Vector3(LANE_X, 0.05, 7.2))
	var step: Node3D = world._box("TestSmallStep", Vector3(LANE_X, 0.12, 5), Vector3(3, 0.24, 1.2), Color.WHITE)
	Input.action_press("move_up")
	var step_peak: float = 0.0
	for index: int in range(45):
		await _frames(1)
		step_peak = maxf(step_peak, player.global_position.y)
	Input.action_release("move_up")
	_check(player.global_position.z < 4.8 and step_peak > 0.2, "Small steps can be crossed without pressing jump: " + str(player.global_position))
	_check(player.motion.step_count > 0, "Step handling resolves a real obstacle rather than teleporting through it")
	world.remove_child(step)
	step.queue_free()
	await _reset(Vector3(LANE_X, 0.05, 2))
	var wall: Node3D = world._box("TestVaultWall", Vector3(LANE_X, 0.425, 0), Vector3(3, 0.85, 0.85), Color.WHITE)
	Input.action_press("move_up")
	await _frames(12)
	Input.action_press("fps_jump")
	var peak: float = 0.0
	var greatest_step: float = 0.0
	var vault_diagonal: bool = false
	for index: int in range(32):
		var before: Vector3 = player.global_position
		await _frames(1)
		if player.motion.vaulting and player.global_position.y > before.y + 0.002 and player.global_position.z < before.z - 0.002:
			vault_diagonal = true
		greatest_step = maxf(greatest_step, before.distance_to(player.global_position))
		peak = maxf(peak, player.global_position.y)
	Input.action_release("fps_jump")
	Input.action_release("move_up")
	_check(player.motion.mantle_count == 1 and peak > 0.84, "Forward plus jump initiates a low obstacle mantle")
	_check(not player.motion.mantling and player.global_position.z < 0.2, "Mantle completes and returns control to ordinary movement")
	_check(greatest_step < 0.3, "Traversal advances through physics instead of a single teleport")
	_check(vault_diagonal, "Low vault moves forward while rising instead of using an elevator-shaped path")
	await _reset(Vector3(LANE_X, 0.05, 1.3))
	_check(player.motion.try_mantle(Vector3.FORWARD), "A low vault starts before a new overhead obstacle appears")
	var moving_roof: Node3D = world._box("TestNewOverheadObstacle", Vector3(LANE_X, 1.9, 1.3), Vector3(3, 0.2, 1.0), Color.WHITE)
	await _frames(8)
	_check(not player.motion.mantling and player.global_position.y < 0.15, "A newly blocked overhead path aborts traversal without clipping through the roof")
	world.remove_child(moving_roof)
	moving_roof.queue_free()
	world.remove_child(wall)
	wall.queue_free()
	await _reset(Vector3(LANE_X, 0.05, 3.3))
	var ledge: Node3D = world._box("TestHighLedge", Vector3(LANE_X, 0.725, 0), Vector3(3, 1.45, 2.8), Color.WHITE)
	Input.action_press("move_up")
	await _frames(12)
	Input.action_press("fps_jump")
	await _frames(35)
	Input.action_release("fps_jump")
	Input.action_release("move_up")
	_check(player.motion.mantle_count == 1 and player.global_position.y > 1.4, "A reachable high ledge can be climbed: " + str(player.global_position) + " grabs=" + str(player.motion.mantle_count))
	# The mantle parks the capsule ~4.5 cm above the ledge so it cannot clip into it,
	# so give the short drop a few frames to land before asserting floor contact.
	await _frames(10)
	_check(not player.motion.mantling and player.is_on_floor(), "The capsule stands on the ledge after climbing")
	var ceiling: Node3D = world._box("TestBlockedLanding", Vector3(LANE_X, 2.5, 0), Vector3(3, 0.2, 2.8), Color.WHITE)
	await _reset(Vector3(LANE_X, 0.05, 2.3))
	_check(not player.motion.try_mantle(Vector3.FORWARD), "Mantle refuses a destination with insufficient headroom")
	world.remove_child(ceiling)
	ceiling.queue_free()
	world.remove_child(ledge)
	ledge.queue_free()
	var tall_wall: Node3D = world._box("TestTooHigh", Vector3(LANE_X, 1.2, 0), Vector3(3, 2.4, 2.8), Color.WHITE)
	await _reset(Vector3(LANE_X, 0.05, 2.2))
	_check(not player.motion.try_mantle(Vector3.FORWARD), "A wall above mantle reach is not climbed")
	world.remove_child(tall_wall)
	tall_wall.queue_free()
	await _reset(Vector3(LANE_X, 0.05, 16))
	player.velocity.z = -10.0
	Input.action_press("fps_crouch")
	await _frames(20)
	var flat_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	await _reset(Vector3(12, 2.1, -1))
	player.rotation.y = PI
	await _frames(5)
	player.velocity.z = 10.0
	Input.action_press("fps_crouch")
	await _frames(20)
	_check(Vector2(player.velocity.x, player.velocity.z).length() > flat_speed + 0.3, "Downhill sliding retains more speed than sliding on flat ground")
	var long_slope: Node3D = world._box("TestLongDownhill", Vector3(LANE_X, 4.1, 0), Vector3(3, 0.2, 22), Color.WHITE)
	long_slope.rotation_degrees.x = 20.0
	await _reset(long_slope.to_global(Vector3(0, 0.1, -8)) + Vector3.UP * 0.05)
	player.rotation.y = PI
	player.velocity.z = 6.0
	Input.action_press("fps_crouch")
	await _frames(75)
	_check(player.motion.sliding and player.motion.slide_count == 1, "A downhill slide continues beyond the flat-ground time limit without restarting")
	_check(Vector2(player.velocity.x, player.velocity.z).length() < 16.1, "Downhill speed remains bounded")
	world.remove_child(long_slope)
	long_slope.queue_free()
	await _reset(Vector3(0, 0.05, 8))
	player.head.look_at(Vector3(0, 6, -9))
	_check(player.grapple.try_attach(), "The unchanged grapple attaches with the new locomotion controller")
	# try_attach() now enters a short windup with no rope and no pull (0.12 s). The
	# old fixed 6-frame wait sampled the release before any momentum existed, so wait
	# out the configured windup plus a couple of frames for the first pull.
	var windup_frames: int = int(ceil(float(player.grapple.windup_duration) * float(Engine.physics_ticks_per_second))) + 3
	await _frames(windup_frames)
	var release_horizontal: float = Vector2(player.velocity.x, player.velocity.z).length()
	player.grapple.release()
	await _frames(1)
	_check(release_horizontal > 0.25 and absf(Vector2(player.velocity.x, player.velocity.z).length() - release_horizontal) < 0.05, "Grapple release retains actual horizontal momentum through the movement transition")
	player.set_controls_active(false)
	_check(not player.motion.mantling and not player.motion.sliding and not player.grapple.is_attached(), "Pause clears traversal, slide and grapple state")
	world.start_round(2)
	_check(player.global_position.distance_to(Vector3(-19, 0.08, 17)) < 0.02 and player.motion.slide_count == 0, "Movement retry resets the course and motion counters")
	player.set_controls_active(true)
	player.velocity = Vector3(0, 0, -25)
	await _frames(2)
	_check(player.camera.fov <= 81.1 and player.head.rotation.z == 0.0, "Speed feedback has a small FOV limit and no forced camera roll")
	# Complete the actual course using the same inputs available to the player.
	_release_inputs()
	world.start_round(2)
	await _frames(8)
	Input.action_press("move_up")
	await _until_z(12.5, 90)
	Input.action_press("fps_crouch")
	await _until_z(6.5, 90)
	_check(world.course.progress >= 1 and player.global_position.z < 6.5, "Course: sprint-slide passes through the actual low tunnel")
	Input.action_release("fps_crouch")
	Input.action_press("fps_walk")
	await _until_z(0.3, 120)
	_check(world.course.progress >= 2, "Course: the ordinary step is crossed on the way to the wall")
	Input.action_press("fps_jump")
	await _until_z(-2.0, 90)
	Input.action_release("fps_jump")
	_check(world.course.progress >= 3, "Course: low wall traversal advances the route")
	await _until_z(-4.8, 90)
	Input.action_press("fps_jump")
	await _until_z(-6.2, 90)
	Input.action_release("fps_jump")
	Input.action_release("move_up")
	_check(world.course.progress >= 4 and player.global_position.y > 1.3, "Course: the high ledge can be reached in sequence")
	player.head.look_at(Vector3(-16, 15, -14))
	player.grapple.try_attach()
	# Same windup: the route only counts the grapple step once it is actually attached.
	await _frames(windup_frames)
	_check(world.course.progress == 5, "Course: grapple finishes the complete movement chain")
	_release_inputs()
	player.motion.toggle_profile()
	world.start_round(2)
	await _frames(8)
	Input.action_press("move_up")
	await _until_z(12.5, 90)
	Input.action_press("fps_crouch")
	await _until_z(6.5, 120)
	Input.action_release("fps_crouch")
	Input.action_press("fps_walk")
	await _until_z(0.3, 120)
	Input.action_press("fps_jump")
	await _until_z(-2.0, 90)
	Input.action_release("fps_jump")
	await _until_z(-4.8, 90)
	Input.action_press("fps_jump")
	await _until_z(-6.2, 90)
	Input.action_release("fps_jump")
	Input.action_release("move_up")
	_check(world.course.progress >= 4 and player.global_position.y > 1.3, "Light reference profile can complete the tunnel, step, vault and ledge sequence")
	print("FIRST_PERSON_MOTION_RESULT checks=%d failures=%d" % [checks, failures])
	_release_inputs()
	world.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(0 if failures == 0 else 1)


func _reset(point: Vector3) -> void:
	_release_inputs()
	player.reset_to_spawn()
	player.global_position = point
	await _frames(10)


func _measure_stop(keep_sprint: bool) -> Dictionary:
	await _reset(Vector3(LANE_X, 0.05, 16))
	Input.action_press("move_up")
	await _frames(35)
	Input.action_release("move_up")
	if not keep_sprint:
		Input.action_press("fps_walk")
	var start: Vector3 = player.global_position
	var frames: int = 0
	while Vector2(player.velocity.x, player.velocity.z).length() > 0.01 and frames < 60:
		await _frames(1)
		frames += 1
	return {"seconds": float(frames) / float(Engine.physics_ticks_per_second), "distance": start.distance_to(player.global_position)}


func _release_inputs() -> void:
	for action: String in ["move_up", "move_down", "move_left", "move_right", "fps_walk", "fps_crouch", "fps_jump", "fps_attack"]:
		Input.action_release(action)


func _frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _until_z(destination: float, limit: int) -> void:
	for index: int in range(limit):
		if player.global_position.z < destination:
			return
		await _frames(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)
