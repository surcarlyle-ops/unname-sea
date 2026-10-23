extends SceneTree
## Integration checks exercise the real arena, input, hit logic and grapple component.

var checks: int = 0
var failures: int = 0
var world: Node3D
var player: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(55.0).timeout.connect(func() -> void: push_error("Combat test timeout"); quit(2))
	world = (load("res://scenes/combat_mvp.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	player = world.player
	_check(not player.controls_active, "Startup waits for a click, enemies do not attack the instructions")
	_check(not player.equipped_blade(), "Startup defaults to empty hands before selecting a weapon")
	# Configure this fixture explicitly; the actual game starts unarmed with the tide blade in slot one.
	player.assign_quick_slot(0, "practice_blade")
	player.selected_slot = 0
	player._refresh_weapon()
	world.start_round(0)
	_freeze_enemies()
	player.set_controls_active(true)
	await _frames(12)
	_check(player.is_on_floor(), "First-person capsule settles on the arena floor")
	_check(absf(player.camera.global_position.y - player.global_position.y - 1.6) < 0.01, "Camera stays at first-person eye height")
	var origin: Vector3 = player.global_position
	Input.action_press("fps_walk")
	Input.action_press("move_up")
	await _frames(60)
	Input.action_release("move_up")
	var distance: float = origin.distance_to(player.global_position)
	_check(distance > 4.8 and distance < 5.6, "Walking uses configured speed and actual physics movement")
	player.reset_to_spawn()
	await _frames(5)
	origin = player.global_position
	Input.action_press("move_up")
	Input.action_press("move_right")
	await _frames(60)
	Input.action_release("move_up")
	Input.action_release("move_right")
	_check(origin.distance_to(player.global_position) <= distance + 0.05 and origin.distance_to(player.global_position) > distance * 0.8, "Diagonal movement respects directional limits without increasing walking speed")
	player.reset_to_spawn()
	player.global_position.z = 14.0
	await _frames(5)
	origin = player.global_position
	Input.action_press("move_up")
	Input.action_release("fps_walk")
	await _frames(60)
	Input.action_release("move_up")
	Input.action_press("fps_walk")
	_check(origin.distance_to(player.global_position) > distance * 1.4 and absf(player.velocity.z + 8.2) < 0.02, "Sprint accelerates to configured speed and covers more distance than walking")
	player.reset_to_spawn()
	await _frames(5)
	Input.action_press("fps_jump")
	await _frames(2)
	Input.action_release("fps_jump")
	await _frames(10)
	_check(player.global_position.y > 0.6, "Jump lifts the capsule off the ground")
	player.rotate_camera(Vector2(0, -10000))
	_check(absf(player.head.rotation.x - 1.45) < 0.001, "Vertical look is clamped")
	player.reset_to_spawn()
	player.global_position = Vector3(22.5, 0.05, 12)
	await _frames(5)
	Input.action_press("move_right")
	await _frames(30)
	Input.action_release("move_right")
	_check(player.global_position.x < 23.0, "Arena wall blocks the capsule")
	player.reset_to_spawn()
	player.global_position = Vector3(12, 0.05, 6)
	await _frames(5)
	Input.action_press("move_up")
	await _frames(115)
	Input.action_release("move_up")
	_check(player.global_position.y > 1.8 and player.global_position.z < -2.0, "The high platform has a walkable ramp without requiring the grapple: " + str(player.global_position))
	player.reset_to_spawn()
	player.assign_quick_slot(4, "practice_blade")
	_check(player.quick_slots[4] == "practice_blade" and player.quick_slots[0].is_empty(), "Moving the blade to slot five does not duplicate it")
	_check(not player.request_attack(), "An empty selected slot cannot attack")
	player.selected_slot = 4
	player._refresh_weapon()
	_check(player.request_attack(), "The blade attacks from its reassigned slot")
	player.attack_elapsed = -1.0
	player.assign_quick_slot(0, "practice_blade")
	player.selected_slot = 0
	player._refresh_weapon()
	world._toggle_loadout()
	_check(player.menu_open and not player.controls_active, "Opening loadout releases input and pauses combat")
	world._toggle_loadout()
	_check(not player.menu_open and player.controls_active, "Closing loadout resumes the same round")
	player.set_controls_active(false)
	Input.action_press("fps_attack")
	player.set_controls_active(true)
	await _frames(2)
	_check(player.attack_elapsed < 0.0, "The click used to resume cannot also trigger an accidental swing")
	Input.action_release("fps_attack")
	# Test a real swing against several actual enemy colliders in one cone.
	world.start_round(0)
	_freeze_enemies()
	var enemies: Array[Node] = world.enemies.get_children()
	var positions: Array[Vector3] = [Vector3(-0.6, 0.02, 6.3), Vector3(0.6, 0.02, 6.3), Vector3(0, 0.02, 10), Vector3(0, 0.02, 2), Vector3(2, 0.02, 7)]
	for index: int in range(enemies.size()):
		enemies[index].position = positions[index]
	var barrier: Node3D = world._box("TestOccluder", Vector3(1.0, 1.0, 7.5), Vector3(0.18, 2.0, 1.0), Color.WHITE)
	await _frames(5)
	player.request_attack()
	await _frames(22)
	_check(enemies[0].health == 8 and enemies[1].health == 8, "One wide swing damages two frontal enemies")
	_check(player.hit_count == 2, "An active swing damages each enemy only once")
	_check(enemies[2].health == 20, "A target behind the player is not hit")
	_check(enemies[3].health == 20, "A target beyond blade range is not hit")
	_check(enemies[4].health == 20, "A wall blocks melee damage")
	await _frames(15)
	player.request_attack()
	await _frames(20)
	_check(enemies[0].dead and enemies[1].dead and world.defeated_count == 2, "A second swing defeats targets and updates round progress")
	barrier.queue_free()
	world.start_round(1)
	_freeze_enemies()
	_check(world.round_total == 3 and world.enemies.get_child_count() == 3, "Mobility mode starts three enemies and resets the round")
	world.start_round(0)
	_freeze_enemies()
	_check(world.round_total == 5 and world.defeated_count == 0, "Crowd mode starts five enemies with fresh progress")
	# Exercise actual enemy windup, damage and invulnerability.
	for enemy: Node in world.enemies.get_children():
		enemy.position = Vector3(-18, 0.02, -15)
	var attacker: CharacterBody3D = world.enemies.get_child(0) as CharacterBody3D
	attacker.position = Vector3(0, 0.02, 6.7)
	attacker.set_physics_process(true)
	await _frames(8)
	_check(attacker.state == attacker.State.WINDUP and player.health == player.max_health, "Enemy shows a windup before dealing damage")
	await _frames(40)
	_check(player.health == player.max_health - 8 and attacker.attack_count == 1, "Enemy deals one configured hit after the windup")
	_check(not player.receive_damage(8, attacker.global_position), "Invulnerability prevents repeated same-frame damage")
	attacker.set_physics_process(false)
	attacker.position = Vector3(-18, 0.02, -15)
	# Actual grapple ray query and controller integration, not a mocked velocity.
	player.reset_to_spawn()
	await _frames(5)
	player.head.look_at(Vector3(0, 6.0, -9))
	var hook: Node3D = player.grapple
	_check(hook.can_attach() and hook.try_attach(), "The real grapple ray attaches to the forward beam within 21 m")
	var pull_origin: Vector3 = player.global_position
	await _frames(4)
	_check(player.velocity.dot((hook.anchor - player.global_position).normalized()) > 0.25 and player.global_position.distance_to(pull_origin) > 0.01, "Grapple pull accelerates toward its anchor without being overwritten by locomotion")
	_check(hook.apply_super_grapple(), "Jump assist is accepted inside the super-grapple window")
	_check(not hook.apply_super_grapple(), "Super-grapple impulse can only be used once per attach")
	var velocity_before: Vector3 = player.velocity
	hook.release()
	await _frames(1)
	_check(player.velocity.length() > 6.0 and player.velocity.length() > velocity_before.length() * 0.75, "Releasing preserves launch momentum")
	_check(hook.is_ready() and hook.cooldown_left == 0.0, "CodeBuddy developer mode permits immediate reuse")
	player.reset_to_spawn()
	player.head.look_at(Vector3(0, 6, -9))
	hook.try_attach()
	Input.action_press("fps_jump")
	await _frames(2)
	Input.action_release("fps_jump")
	_check(hook._super_window_left == 0.0, "The controller routes the actual jump input to super-grapple")
	hook.release()
	player.reset_to_spawn()
	player.head.look_at(Vector3(0, 6.0, -9))
	_check(hook.try_attach(), "Grapple can reattach after reset")
	player.set_controls_active(false)
	var paused_point: Vector3 = player.global_position
	await _frames(10)
	_check(not hook.is_attached() and player.global_position.is_equal_approx(paused_point), "Pause releases the hook and freezes player motion")
	player.set_controls_active(true)
	player.reset_to_spawn()
	player.head.look_at(Vector3(0, 100, 0))
	_check(not hook.can_attach() and not hook.try_attach(), "Aiming into empty sky fails cleanly")
	player.head.look_at(Vector3(0, 6, -9))
	hook.try_attach()
	player.receive_damage(1000, Vector3.ZERO)
	_check(player.dead and not hook.is_attached() and not player.controls_active, "Death clears the grapple and stops controls")
	world.restart_round()
	_freeze_enemies()
	_check(not player.dead and player.health == player.max_health and not hook.is_attached(), "Retry restores health and clears old grapple state")
	_check(player.quick_slots.size() == 5, "HUD contract retains five freely assignable quick slots")
	print("FIRST_PERSON_COMBAT_RESULT checks=%d failures=%d" % [checks, failures])
	world.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(0 if failures == 0 else 1)


func _freeze_enemies() -> void:
	for enemy: Node in world.enemies.get_children():
		enemy.set_physics_process(false)


func _frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)
