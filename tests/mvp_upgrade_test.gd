extends SceneTree
## Exercise the real hands, guardian and grapple without requiring new assets.

var arena: Node3D
var player: CharacterBody3D
var boss: CharacterBody3D
var checks: int = 0
var failures: int = 0
var capture: bool = false

func _initialize() -> void:
	capture = DisplayServer.get_name() != "headless"
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.mvp_qa/mvp_upgrade")
	arena = load("res://scenes/combat_mvp.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await _frames(4)
	player = arena.player
	boss = arena.guardian
	player.set_controls_active(true)
	player.set_physics_process(false)
	boss.set_physics_process(false)
	_reset(Vector3(8, 0.02, 20))
	print("RIG_TRACE hammer=%s shoulder=%s elbow=%s root=%s" % [boss.motion._hammer_center(), boss.motion._global.upper_arm_heavy.origin, boss.motion._global.stone_hammer.origin, boss.motion._global.root.origin])
	var hands: Node3D = player.hands
	hands.set_weapon("")
	_pose(0, 0)
	_check(hands.right_arm.position.y < -0.60 and hands.left_arm.position.y < -0.60, "Empty idle hands rest below the frame")
	await _capture("empty_idle")
	_pose(3, PI / 2)
	var slow: float = hands.right_arm.position.distance_to(hands.left_arm.position * Vector3(-1, 1, 1))
	_pose(8.2, PI / 2)
	var fast: float = hands.right_arm.position.distance_to(hands.left_arm.position * Vector3(-1, 1, 1))
	_check(fast > slow * 1.3, "Running increases alternating arm swing relative to walking")
	var forward: Vector3 = hands.right_arm.position
	await _capture("empty_run_a")
	_pose(8.2, PI * 1.5)
	_check(hands.right_arm.position.y < forward.y - 0.10, "Opposite stride reverses the arm swing")
	await _capture("empty_run_b")
	for state: String in ["air", "sliding", "mantling", "grappling"]:
		for i: int in range(65):
			var motion: Dictionary = {"grounded": state != "air", "stride_phase": float(i) / 5.0}
			motion[state] = true
			hands.update_pose(1.0 / 60, 8.2, true, -1, 0, false, 2, motion)
		_check(hands._empty_move_blend < 0.01, state + " suppresses running arm swing")
	for item: String in ["tide_blade", "steam_pistol"]:
		hands.set_weapon(item)
		hands._spawn_time = 0
		hands._pistol_spawn = 0
		_pose(0, 0, true)
		_check(hands.weapon_root.visible, item + " keeps its equip presentation")
		await _capture(item)
	_reset(Vector3(8, 0.02, 18))
	boss._cooldown = 100
	var hip: int = boss.skeleton.find_bone("thigh_heavy")
	var rest: Quaternion = boss.skeleton.get_bone_pose_rotation(hip)
	await _boss_frames(12)
	_check(rest.angle_to(boss.skeleton.get_bone_pose_rotation(hip)) > 0.01, "Walking animates the existing leg bones")
	await _capture("guardian_walk")
	_reset(Vector3(8, 0.02, 21))
	boss._cooldown = 0
	await _boss_frames(1)
	_check(boss.attacking and boss.attack_kind == "charge", "Distant target selects charge")
	var near_charge: float = boss.world_lunge()
	boss.cancel_attack()
	player.position.z = 35
	boss.play_attack()
	_check(boss.world_lunge() > near_charge and boss.world_lunge() <= float(boss.tuning.charge_max_distance) + 0.01, "Charge distance adapts to initial target distance with a cap")
	var heading: float = boss.rotation.y
	player.position.x += 5
	await _boss_frames(28)
	_check(absf(boss.rotation.y - heading) < 0.001, "Committed charge does not home toward a moving player")
	await _capture("guardian_charge_windup")
	_reset(Vector3(8, 0.02, 15.2))
	boss._cooldown = 0
	await _boss_frames(1)
	_check(boss.attack_kind == "swing" and boss.attacking, "Nearby target selects a fist swing")
	await _boss_frames(28)
	await _capture("guardian_swing_windup")
	await _boss_frames(17)
	print("SWING_ACTIVE fist=%s target=%s time=%.3f" % [boss.fist_position(), player.position, boss._close_elapsed])
	await _capture("guardian_swing_hit")
	await _boss_frames(55)
	_check(not boss.attacking and not boss.damage_window_active(), "Swing closes its damage window and recovers")
	print("SWING_TRACE player_health=%d hits=%d" % [player.health, boss.attack_count])
	_check(player.health == 78 and boss.attack_count == 1, "Swing reaches the selected melee range and damages once")
	_reset(Vector3(8, 0.02, 15.0))
	boss._close_count = 2
	boss._cooldown = 0
	await _boss_frames(1)
	_check(boss.attack_kind == "slam" and boss.attacking, "Close-range AI mixes in the third heavy slam")
	_reset(Vector3(8, 0.02, 21))
	var wall: Node3D = arena._box("AdaptiveChargeWall", Vector3(8, 2, 15), Vector3(5, 4, 0.4), Color.WHITE)
	await _frames(3)
	boss.play_attack()
	await _boss_frames(175)
	_check(boss.position.z < 13.7 and player.health == 100, "Adaptive charge stops at a wall without damaging through it")
	wall.queue_free()
	await _frames(2)
	_reset(Vector3(8, 0.02, 17.5))
	boss.start_close_attack("slam")
	await _boss_frames(40)
	_check(player.health == 100 and boss._warning.visible, "Slam gives advance warning before damage")
	await _capture("guardian_slam_windup")
	await _boss_frames(23)
	await _capture("guardian_slam_impact")
	await _boss_frames(60)
	_check(player.health == 78 and boss.attack_count == 1, "Grounded target is hit once by the expanding ground wave")
	_reset(Vector3(8, 1.1, 17.5))
	boss.start_close_attack("slam")
	await _boss_frames(123)
	_check(player.health == 100, "A player above the ground wave avoids slam damage")
	_reset(Vector3(8, 0.02, 20))
	boss.start_close_attack("slam")
	player.set_controls_active(false)
	var frozen: float = boss._close_elapsed
	await _boss_frames(10)
	_check(is_equal_approx(frozen, boss._close_elapsed), "Pausing freezes new attack timelines")
	player.set_controls_active(true)
	boss.cancel_attack()
	player.hands.set_weapon("steam_pistol")
	player.hands._pistol_spawn = 0
	player.grapple.set_physics_process(false)
	player.grapple.anchor = Vector3(4, 5, 9)
	player.grapple.anchor_normal = Vector3.BACK
	player.grapple.state = player.grapple.State.ATTACHED
	player.grapple._update_rope_visual(true)
	for i: int in range(30):
		player.hands.update_pose(1.0 / 60, 8, true, -1, 0, true, 2, {"grounded":false, "grappling":true, "grapple_anchor":player.grapple.anchor})
		await process_frame
	_check(hands.grapple_hold_weight() > 0.95 and hands.left_arm.position.y > -0.35, "Grapple raises the left hand into a rope grip")
	_check(player.grapple._hook_head.visible and player.grapple.rope_visual._segments[8].visible, "Hook head and physical rope presentation are visible")
	await _capture("grapple_hold")
	player.grapple.release()
	for i: int in range(30):
		hands.update_pose(1.0 / 60, 0, false, -1, 0, true, 2)
		await process_frame
	_check(hands.grapple_hold_weight() < 0.01, "Releasing restores the left hand")
	player.grapple.reset()
	_check(not player.grapple._hook_head.visible, "Retry/reset hides the hook and rope")
	boss.apply_damage(10000, Vector3.ZERO)
	_check(arena.round_complete and boss.dead and not boss._warning.visible and not boss._shockwave.visible, "Death clears new attack visuals and completes the trial")
	print("MVP_UPGRADE_RESULT checks=%d failures=%d" % [checks, failures])
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _reset(point: Vector3) -> void:
	boss.cancel_attack()
	boss._set_idle_pose()
	boss.position = Vector3(8, 0.02, 12)
	boss.rotation = Vector3.ZERO
	boss.velocity = Vector3.ZERO
	boss._cooldown = 100
	boss._close_count = 0
	boss._idle_pending = false
	boss._hit_this_attack = false
	boss.attack_count = 0
	player.position = point
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.health = 100
	player.hurt_time_left = 0
	player.set_controls_active(true)

func _pose(speed: float, phase: float, equipped: bool = false) -> void:
	for i: int in range(40):
		player.hands.update_pose(1.0 / 60, speed, speed > 5, -1, 0, equipped, 2, {"grounded":true, "stride_phase":phase})

func _boss_frames(count: int) -> void:
	for i: int in range(count):
		await physics_frame
		boss._physics_process(1.0 / 60)
		await process_frame

func _frames(count: int) -> void:
	for i: int in range(count):
		await process_frame

func _capture(label: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/mvp_upgrade/" + label + ".png")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
