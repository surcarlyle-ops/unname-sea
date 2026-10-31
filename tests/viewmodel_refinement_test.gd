extends SceneTree
## Real viewmodel frames: sparse running hands, isolated gun recoil, bounded rope follow.

var player: CharacterBody3D
var hands: Node3D
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.mvp_qa/viewmodel_refinement")
	var arena: Node3D = load("res://scenes/combat_mvp.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	player = arena.player
	hands = player.hands
	player.set_controls_active(true)
	player.set_physics_process(false)
	arena.guardian.set_physics_process(false)
	player.position = Vector3(8, 0.02, 20)
	player.rotation = Vector3.ZERO
	player.assign_quick_slot(0, "")
	player.selected_slot = 0
	player._refresh_weapon()
	_pose(0, 0, false)
	_check(hands.left_arm.position.y < -0.7 and hands.right_arm.position.y < -0.7, "Empty idle arms naturally leave the view")
	await _capture("empty_idle")
	for phase: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		_pose(8.2, phase, false)
		_check(hands.left_arm.position.y < -0.55 and hands.right_arm.position.y < -0.55, "Running does not lift both arms into the centre")
		await _capture("run_%d" % roundi(phase * 100))
	player.assign_quick_slot(0, "tide_blade")
	player._refresh_weapon()
	hands._cancel_spawn_animation()
	_pose(0, 0, true)
	var sword_neutral: Quaternion = hands.right_arm.quaternion
	for i: int in range(45):
		hands.update_pose(1.0 / 60, 0, false, -1, 0, true, 2, {"grounded":true, "crouching":true})
	_check(absf(rad_to_deg(hands._state_angles.z) - 45.0) < 1.0, "Crouch smoothly reaches a 45-degree left tilt")
	await _capture("sword_crouch")
	for i: int in range(45):
		hands.update_pose(1.0 / 60, 8, true, -1, 0, true, 2, {"grounded":true, "sliding":true})
	_check(hands._state_offset.x > 0.09 and hands._state_offset.y < -0.09, "Slide tucks the sword down and right")
	await _capture("sword_slide")
	_pose(0, 0, true)
	_check(hands.right_arm.quaternion.angle_to(sword_neutral) < 0.01, "Standing restores the original holding pose")
	hands.notify_landing(14)
	hands.update_pose(0.1, 0, false, -1, 0, true, 2)
	_check(hands._landing_strength > 0.7 and hands._landing_time < 0.2, "Landing starts a short proportional hand dip")
	_pose(0, 0, true)
	player.assign_quick_slot(0, "steam_pistol")
	player._refresh_weapon()
	hands._cancel_pistol_spawn()
	_pose(0, 0, true)
	var neutral_position: Vector3 = hands.right_arm.position
	var neutral: Quaternion = hands.right_arm.quaternion
	await _capture("gun_neutral")
	player.request_attack()
	arena.hud._swing_streak = 0.0
	arena.hud._process(1.0 / 60)
	_check(arena.hud._swing_streak == 0.0, "Gun fire does not trigger melee screen streaks")
	# Before the projectile is emitted, no slash or fake windup motion is allowed.
	hands.update_pose(1.0 / 60, 0, false, 0.20, 1, true, 2)
	_check(neutral.angle_to(hands.right_arm.quaternion) < 0.001 and neutral_position.distance_to(hands.right_arm.position) < 0.001, "Gun attack progress does not enter the melee swing fallback")
	player._update_attack(float(player._weapon.windup) + 0.001)
	hands.update_pose(1.0 / 60, 0, false, 0.3, 1, true, 2)
	_check(hands._pistol_recoil_left > 0 and hands.right_arm.position.z > neutral_position.z + 0.02, "The actual projectile emission triggers short rearward recoil")
	_check(absf(hands.right_arm.position.x - neutral_position.x) < 0.001 and neutral.angle_to(hands.right_arm.quaternion) < deg_to_rad(5), "Gun recoil stays small without a lateral sword slash")
	await _capture("gun_recoil")
	_pose(0, 0, true)
	_check(hands.right_arm.position.distance_to(neutral_position) < 0.001, "Gun returns to its holding pose")
	player.grapple.set_physics_process(false)
	player.grapple._raycast_anchor()
	player.grapple.state = player.grapple.State.ATTACHED
	player.grapple.anchor = Vector3(2, 6, 9)
	player.grapple.anchor_normal = Vector3.BACK
	player.grapple._update_rope_visual(true)
	_follow(player.grapple.anchor, -7)
	var left_pose: Quaternion = hands.left_arm.quaternion
	var forearm: int = hands.left_glove.skeleton.find_bone("Forearm")
	var sleeve_direction: Vector3 = hands.left_arm.quaternion * hands.left_glove.skeleton.get_bone_pose_rotation(forearm) * Vector3.BACK
	await _capture("rope_left")
	player.grapple.anchor = Vector3(16, 3, 11)
	_follow(player.grapple.anchor, 7)
	var new_sleeve: Vector3 = hands.left_arm.quaternion * hands.left_glove.skeleton.get_bone_pose_rotation(forearm) * Vector3.BACK
	_check(sleeve_direction.angle_to(new_sleeve) > deg_to_rad(0.5) and new_sleeve.angle_to(hands.left_arm.quaternion * left_pose.inverse() * sleeve_direction) < 0.01, "Hand and sleeve share the same small follow rotation")
	_check(left_pose.angle_to(hands.left_arm.quaternion) > deg_to_rad(5), "Rope bearing and lateral momentum rotate the holding forearm")
	_check(absf(hands._grapple_follow.x) <= deg_to_rad(10.01) and absf(hands._grapple_follow.y) <= deg_to_rad(12.01) and absf(hands._grapple_follow.z) <= deg_to_rad(5.01), "Rope-follow rotation remains bounded")
	_check(hands.left_glove._override_weight > 0.99, "Following does not open the fingers")
	_check(hands.left_glove.skeleton.get_bone_pose_scale(forearm).is_equal_approx(Vector3.ONE) and hands.left_glove.skeleton.get_bone_pose_scale(hands.left_glove.skeleton.find_bone("Hand")).is_equal_approx(Vector3.ONE), "Restored grip does not stretch the sleeve or rescale the hand")
	await _capture("rope_right")
	player.grapple.reset()
	var boss: CharacterBody3D = arena.guardian
	var old_health: int = boss.health
	arena.hud.clear_damage_numbers()
	boss.apply_part_damage(21, Vector3.ZERO, "body")
	_check(arena.hud._damage_numbers.size() == 1 and int(arena.hud._damage_numbers[0].amount) == old_health - boss.health, "Damage popups report health actually removed")
	old_health = boss.health
	boss.apply_part_damage(21, Vector3.ZERO, "stone_hammer")
	_check(arena.hud._damage_numbers.size() == 2 and bool(arena.hud._damage_numbers[1].armored) and int(arena.hud._damage_numbers[1].amount) == old_health - boss.health, "Armored hits report reduced damage once")
	arena.hud._damage_numbers[0].point = player.position + Vector3(0, 2.0, -6)
	arena.hud._damage_numbers[1].point = player.position + Vector3(1, 2.0, -6)
	await _capture("damage_numbers")
	arena.hud._process(0.9)
	_check(arena.hud._damage_numbers.is_empty(), "Damage numbers expire without accumulating")
	arena.hud.add_damage_number(1, boss.position, false)
	arena.restart_round()
	arena.guardian.set_physics_process(false)
	_check(arena.hud._damage_numbers.is_empty(), "Restart clears old damage numbers")
	_pose(0, 0, true)
	_check(hands._grapple_follow.length() < 0.001, "Release clears the follow state")
	player.velocity = Vector3(8.2, 0, 0)
	player.motion._slide_impact_age = 0.0
	player.motion._update_view(0.04)
	_check(absf(player.camera.position.y - player.motion._camera_base_position.y) > 0.0001, "Slide entry has a short visible impulse")
	player.motion._update_view(0.3)
	_check(absf(player.camera.position.y - player.motion._camera_base_position.y) < 0.00001 and absf(player.camera.rotation.x - player.motion._camera_base_rotation.x) < 0.00001, "Slide entry vibration fully stops after 180 milliseconds")
	print("VIEWMODEL_REFINEMENT_RESULT checks=%d failures=%d" % [checks, failures])
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _pose(speed: float, phase: float, equipped: bool) -> void:
	for i: int in range(45):
		hands.update_pose(1.0 / 60, speed, speed > 5, -1, 0, equipped, 2, {"grounded":true, "stride_phase":phase})

func _follow(anchor: Vector3, sideways_speed: float) -> void:
	for i: int in range(45):
		hands.update_pose(1.0 / 60, 8, true, -1, 0, true, 2, {"grounded":false, "grappling":true, "grapple_anchor":anchor, "local_velocity":Vector3(sideways_speed, 0, 0)})

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/viewmodel_refinement/" + label + ".png")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
