extends SceneTree
## Narrow regression: the real player's capsule/camera must stay outside the stone fist.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arena: Node3D = (load("res://scenes/combat_mvp.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	var boss: CharacterBody3D = arena.guardian
	var player: CharacterBody3D = arena.player
	boss.set_physics_process(false)
	player.set_physics_process(false)
	await physics_frame
	var fist: AnimatableBody3D = boss.solid_fist
	fist.sync_pose()
	var center: Vector3 = fist.world_center()
	var aim: Vector3 = center
	aim.y = maxf(center.y, 1.65)
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(aim + Vector3.LEFT * 5.0, aim + Vector3.RIGHT * 3.0, 2, [boss.get_rid()])
	var hit: Dictionary = arena.get_world_3d().direct_space_state.intersect_ray(ray)
	var fails: int = 0
	if hit.get("collider") != fist:
		push_error("FAIL: the fitted stone fist must be a ray-detectable solid")
		quit(1)
		return
	var surface: Vector3 = hit.position
	player.position = Vector3(surface.x - 0.9, aim.y - 1.6, aim.z)
	for i: int in range(30):
		await physics_frame
		player.velocity = Vector3.RIGHT * 8.0
		player.move_and_slide()
	var outside: bool = player.camera.global_position.x < surface.x - 0.20
	print("FIST_BLOCK outside=%s camera=%s surface=%s points=%d" % [outside, player.camera.global_position, surface, fist.solid_shape.points.size()])
	if not outside:
		fails += 1
	player.set_controls_active(true)
	boss._cooldown = 100.0
	boss.play_attack()
	var inside_frames: int = 0
	var query: PhysicsPointQueryParameters3D = PhysicsPointQueryParameters3D.new()
	query.collision_mask = 2
	query.exclude = [boss.get_rid()]
	for i: int in range(150):
		await physics_frame
		boss._physics_process(1.0 / 60.0)
		fist.sync_pose()
		player.velocity = Vector3.ZERO
		player.move_and_slide()
		query.position = player.camera.global_position
		if not arena.get_world_3d().direct_space_state.intersect_point(query, 4).is_empty():
			inside_frames += 1
	print("FIST_MOTION camera_inside_frames=%d drift=%.4f" % [inside_frames, boss.mesh_drift()])
	if inside_frames > 0:
		fails += 1
	var hp: int = boss.health
	fist.apply_damage(10, Vector3.ZERO)
	if boss.health != hp - 5:
		fails += 1
	print("FIST_COLLISION_RESULT checks=4 failures=%d" % fails)
	arena.queue_free()
	await process_frame
	quit(0 if fails == 0 else 1)
