extends SceneTree
## (CodeBuddy) Throwaway diagnostic: what stops the player at the east bridge head.

var world: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	world = (load("res://scenes/cherry_valley.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	var waited: int = 0
	while not bool(world.build_complete) and waited < 3000:
		await process_frame
		waited += 1
	var terrain: Node3D = world.terrain
	var player: CharacterBody3D = world.player
	player.global_position = Vector3(-5.06, 0.9, 9.36)
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	await physics_frame
	await physics_frame
	await physics_frame
	print("PLAYER_AT ", player.global_position, " floor=", player.is_on_floor())
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var bridge: Dictionary = world.config.village.bridge
	var center: Vector2 = Vector2(float(bridge.center[0]), float(bridge.center[1]))
	var dir: Vector2 = (center - Vector2(player.global_position.x, player.global_position.z)).normalized()
	for height: float in [0.05, 0.2, 0.35, 0.5, 0.9, 1.3]:
		var from: Vector3 = player.global_position + Vector3(0, height, 0)
		var to: Vector3 = from + Vector3(dir.x, 0, dir.y) * 3.0
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			print("RAY h=%.2f no hit" % height)
		else:
			print("RAY h=%.2f hit %s at %s normal=%s" % [height, (hit.collider as Node).get_path(), hit.position, hit.normal])
	# Walk straight at the bridge using the player's own basis.
	var local_dir: Vector2 = Vector2(dir.x * player.global_basis.x.x + dir.y * player.global_basis.x.z, dir.x * player.global_basis.z.x + dir.y * player.global_basis.z.z)
	print("LOCAL_DIR ", local_dir)
	for step: int in range(90):
		player.set_touch_move(local_dir)
		await physics_frame
		if step % 15 == 0 or step == 89:
			var normals: Array[String] = []
			for index: int in range(player.get_slide_collision_count()):
				var collision: KinematicCollision3D = player.get_slide_collision(index)
				normals.append("%s n=%s" % [(collision.get_collider() as Node).get_path(), collision.get_normal()])
			print("STEP %d pos=%s vel=%s hits=%d %s" % [step, player.global_position, player.velocity, player.get_slide_collision_count(), ", ".join(normals)])
	quit(0)
