extends SceneTree
## Exercise the actual arena/player/guardian contracts and physics, not isolated mocks.

var arena: Node3D
var player: CharacterBody3D
var boss: CharacterBody3D
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	arena = (load("res://scenes/combat_mvp.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	player = arena.player
	boss = arena.guardian
	_check(arena.mode == 3 and is_instance_valid(boss), "Main scene starts the guardian trial")
	_check(not player.controls_active and boss.is_in_group("mvp_enemies"), "Startup pauses AI and registers the damage contract")
	await _frames(20)
	_check(boss.is_on_floor() and boss.health == 300 and player.health == 100, "Gravity settles the 300 HP boss without attacking startup instructions")
	player.set_controls_active(true)
	player.set_physics_process(false)
	var before: Vector3 = boss.global_position
	await _frames(50)
	_check(boss.global_position.distance_to(before) > 0.8, "AI approaches a player outside attack range")
	boss.set_physics_process(false)
	_reset_combat(Vector3(0, 0.01, 4.2))
	boss.play_attack()
	for i: int in range(ceili(70.0 / boss.attack_speed)):
		await physics_frame
		boss._physics_process(1.0 / 60.0)
	_check(player.health == 100 and boss.state in [boss.State.WINDUP, boss.State.DASH], "Windup gives a visible warning before damage")
	_check(boss._warning.visible and boss.mesh_drift() < 0.03, "Telegraph is visible and mesh stays with its collider")
	var frozen_time: float = boss.clip_time()
	player.set_controls_active(false)
	for i: int in range(20):
		await physics_frame
		boss._physics_process(1.0 / 60.0)
	_check(is_equal_approx(boss.clip_time(), frozen_time), "Pausing freezes the attack timeline")
	player.set_controls_active(true)
	await _attack_frames(132)
	print("HIT_TRACE health=%d hits=%d body=%s fist=%s time=%.3f" % [player.health, boss.attack_count, boss.global_position, boss.fist_position(), boss.clip_time()])
	_check(player.health == 78 and boss.attack_count == 1, "A frontal charge hits the real player once for configured damage")
	_check(not boss.attacking and not boss.damage_window_active(), "Recovery ends the damage window")
	_reset_combat(Vector3(0, 0.01, 4.2))
	boss.play_attack()
	await _attack_frames(60)
	player.global_position.x = 5.0
	await _attack_frames(140)
	_check(player.health == 100 and absf(boss.rotation.y) < 0.001, "Side movement avoids the locked charge; it does not home toward the player")
	_reset_combat(Vector3(0, 0.01, -3))
	boss.play_attack()
	await _attack_frames(200)
	_check(player.health == 100, "Targets behind the charge are not damaged")
	_reset_combat(Vector3(0, 0.01, 4.2))
	var barrier: Node3D = arena._box("GuardianTestWall", Vector3(0, 2, 2.2), Vector3(8, 4, 0.4), Color.WHITE)
	await _frames(3)
	boss.play_attack()
	await _attack_frames(200)
	_check(boss.global_position.z < 1.4 and player.health == 100, "Wall stops the collision body and prevents damage through the wall")
	barrier.queue_free()
	await _frames(3)
	_reset_combat(Vector3(5, 0.01, 4.2))
	boss.position.y = 3.0
	player.set_controls_active(false)
	await _attack_frames(90, false)
	_check(boss.is_on_floor() and absf(boss.position.y) < 0.06, "Gravity also works while AI is paused")
	_reset_combat(Vector3(0, 0.01, 0))
	boss.position = Vector3(0, 0.01, -2)
	player.rotation = Vector3.ZERO
	player.assign_quick_slot(0, "practice_blade")
	player.selected_slot = 0
	player._refresh_weapon()
	await _frames(3)
	var hp: int = boss.health
	player._hit_targets.clear()
	player._resolve_melee()
	_check(boss.health == hp - 12, "The existing sword damages the guardian with its configured defense")
	Engine.time_scale = 1.0
	player._hitstop_time = 0.0
	player.assign_quick_slot(0, "steam_pistol")
	player._refresh_weapon()
	hp = boss.health
	player._fire_bolt()
	await _frames(12)
	_check(boss.health == hp - 13, "The existing hand cannon hits the guardian collider")
	player.assign_quick_slot(0, "tide_blade")
	player._refresh_weapon()
	player.energy = player.energy_max()
	hp = boss.health
	_check(player.release_wave(), "The equipped clock sword can release its charged wave")
	await _frames(12)
	_check(boss.health == hp - 17, "The existing charged wave damages the guardian once")
	boss.apply_damage(10000, Vector3.ZERO)
	_check(boss.dead and arena.round_complete and arena.defeated_count == 1, "Death completes the actual arena trial")
	boss.apply_damage(10000, Vector3.ZERO)
	_check(arena.defeated_count == 1 and not boss.damage_window_active(), "Death cannot score twice or keep an active hitbox")
	arena.restart_round()
	boss = arena.guardian
	boss.set_physics_process(false)
	_check(boss.health == 300 and not player.dead and player.health == 100 and arena.enemies.get_child_count() == 1, "Retry creates one healthy boss and restores the player")
	arena.start_round(0)
	_check(arena.enemies.get_child_count() == 5 and arena.guardian == null, "Existing swarm mode remains available")
	arena.start_round(2)
	_check(arena.enemies.get_child_count() == 0, "Movement practice remains enemy-free")
	print("GUARDIAN_COMBAT_RESULT checks=%d failures=%d" % [checks, failures])
	arena.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	quit(0 if failures == 0 else 1)


func _reset_combat(player_point: Vector3) -> void:
	boss.cancel_attack()
	boss._set_idle_pose()
	boss.attacking = false
	boss.state = boss.State.CHASE
	boss._idle_pending = false
	boss._cooldown = 100.0
	boss.position = Vector3(0, 0.01, 0)
	boss.rotation = Vector3.ZERO
	boss.velocity = Vector3.ZERO
	boss.attack_count = 0
	player.position = player_point
	player.velocity = Vector3.ZERO
	player.health = 100
	player.dead = false
	player.hurt_time_left = 0
	player.set_controls_active(true)


func _attack_frames(count: int, scale_attack: bool = true) -> void:
	var actual_count: int = ceili(float(count) / boss.attack_speed) if scale_attack else count
	for i: int in range(actual_count):
		await physics_frame
		boss._physics_process(1.0 / 60.0)
		await process_frame


func _frames(count: int) -> void:
	for i: int in range(count):
		await physics_frame
		await process_frame


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)
