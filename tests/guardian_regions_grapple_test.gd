extends SceneTree
## Actual melee/projectile contact regions and cancellable grapple preparation.

var arena: Node3D
var player: CharacterBody3D
var boss: CharacterBody3D
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.mvp_qa/guardian_regions")
	arena = load("res://scenes/combat_mvp.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	player = arena.player
	boss = arena.guardian
	player.set_controls_active(true)
	player.set_physics_process(false)
	boss.set_physics_process(false)
	boss.position = Vector3(8, 0.02, 12)
	for part: AnimatableBody3D in boss.solid_parts:
		part.sync_pose()
	await physics_frame
	await process_frame
	_check(boss.solid_parts.size() == 12, "Rigid visible body pieces have fitted solid hurt regions")
	player.assign_quick_slot(0, "practice_blade")
	player.selected_slot = 0
	player._refresh_weapon()
	var normal: int = maxi(int(player._weapon.damage) - int(boss.stats.defense), 1)
	var armored: int = maxi(roundi(normal * 0.5), 1)
	for name: String in ["stone_hammer", "forearm_light", "foot_heavy", "foot_light"]:
		var part: AnimatableBody3D = _part(name)
		var direction: Vector3 = part.world_center() - boss.position
		direction.y = 0
		direction = direction.normalized()
		var excluded: Array[RID] = [boss.get_rid()]
		for other: AnimatableBody3D in boss.solid_parts:
			if other != part:
				excluded.append(other.get_rid())
		var center: Vector3 = part.world_center()
		var ray: Dictionary = arena.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(center + direction * 4, center, 2, excluded))
		_check(ray.get("collider") == part, name + " blocks rays on its actual mesh")
		print("PART_RAY %s center=%s hit=%s" % [name, center, ray.get("collider")])
		if ray.is_empty():
			continue
		player.position = ray.position + direction * 0.85 - Vector3.UP * 1.6
		player.camera.look_at(center, Vector3.UP)
		var before: int = boss.health
		player._hit_targets.clear()
		player._resolve_melee()
		player.clear_hitstop()
		_check(boss.health == before - armored, name + " takes half damage from the real sword")
		player._resolve_melee()
		player.clear_hitstop()
		_check(boss.health == before - armored, name + " cannot cause duplicate damage during one swing")
		await process_frame
	# Above the fists, the torso keeps ordinary damage.
	player.position = boss.position + Vector3(0, 2.4, 3)
	player.camera.look_at(boss.position + Vector3(0, 4.0, 0), Vector3.UP)
	var before: int = boss.health
	player._hit_targets.clear()
	player._resolve_melee()
	player.clear_hitstop()
	_check(boss.health == before - normal, "Torso receives normal sword damage")
	# Physical player/camera approach to the smaller fist.
	var small: AnimatableBody3D = _part("forearm_light")
	var center: Vector3 = small.world_center()
	player.position = center + Vector3.RIGHT * 3 - Vector3.UP * 1.6
	for i: int in range(28):
		await physics_frame
		player.velocity = Vector3.LEFT * 8
		player.move_and_slide()
	var query: PhysicsPointQueryParameters3D = PhysicsPointQueryParameters3D.new()
	query.position = player.camera.global_position
	query.collision_mask = 2
	var inside_small: bool = false
	for hit: Dictionary in arena.get_world_3d().direct_space_state.intersect_point(query):
		inside_small = inside_small or hit.collider == small
	_check(not inside_small and player.platform_floor_layers == 1, "Small fist blocks the camera and cannot launch the player as a moving platform")
	# Projectile contact forwards its region multiplier to the same guardian HP.
	before = boss.health
	small.apply_damage(21, Vector3.ZERO)
	_check(boss.health == before - 10, "Small-fist projectile region applies half of post-defense damage")
	player.position = Vector3(0, 0.02, 20)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	arena._box("WindupAnchor", Vector3(0, 2, 14), Vector3(3, 4, 0.4), Color.WHITE)
	await physics_frame
	await process_frame
	var hook: Node3D = player.grapple
	hook.set_physics_process(false)
	hook.reset()
	_check(hook.try_attach() and hook.is_preparing() and not hook.is_attached(), "Press starts preparation without instant attachment")
	hook._physics_process(0.06)
	_check(hook.is_preparing() and player.velocity == Vector3.ZERO and not hook._hook_head.visible, "First half of windup has no hook flight or pull")
	for i: int in range(5):
		player.hands.update_pose(1.0 / 60, 0, false, -1, 0, true, 2, {"grapple_preparing":true})
		await process_frame
	_check(player.hands._grapple_blend > 0.4, "Left hand raises during preparation")
	await _capture("hook_prepare")
	hook.release()
	_check(not hook.is_preparing() and hook.is_ready() and not hook.is_attached(), "Releasing before launch cancels windup")
	hook.try_attach()
	hook._physics_process(0.13)
	_check(hook.is_attached() and hook.rope_visual.shot_duration <= 0.06, "After windup the existing fast hook launches")
	await process_frame
	hook.reset()
	hook.try_attach()
	player.set_controls_active(false)
	_check(hook.is_ready() and not hook.is_preparing(), "Pause cancels preparation")
	print("GUARDIAN_REGIONS_GRAPPLE_RESULT checks=%d failures=%d normal=%d armor=%d" % [checks, failures, normal, armored])
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _part(name: String) -> AnimatableBody3D:
	for part: AnimatableBody3D in boss.solid_parts:
		if str(part.bone_name) == name:
			return part
	return null

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/guardian_regions/" + label + ".png")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
