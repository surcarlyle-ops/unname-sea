extends SceneTree
## Capture the actual first-person scene at readable attack phases.

var arena: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.mvp_qa/guardian_combat")
	arena = (load("res://scenes/combat_mvp.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	await _frames(8)
	await _capture("startup")
	var player: CharacterBody3D = arena.player
	var boss: CharacterBody3D = arena.guardian
	player.set_controls_active(true)
	player.set_physics_process(false)
	player.position = Vector3(0, 0.01, 4.2)
	player.rotation = Vector3.ZERO
	boss.set_physics_process(false)
	boss.rotation = Vector3.ZERO
	boss.position = Vector3(0, 0.01, 0)
	boss.play_attack()
	for i: int in range(ceili(205.0 / boss.attack_speed)):
		await physics_frame
		boss._physics_process(1.0 / 60.0)
		await process_frame
		if i == roundi(30.0 / boss.attack_speed):
			await _capture("windup")
		elif i == roundi(106.0 / boss.attack_speed):
			await _capture("impact")
		elif i == roundi(160.0 / boss.attack_speed):
			await _capture("recovery")
	boss.apply_damage(60, Vector3.ZERO)
	await _frames(2)
	await _capture("damaged")
	print("GUARDIAN_CAPTURE_DONE health=%d player_health=%d drift=%.4f" % [boss.health, player.health, boss.mesh_drift()])
	arena.queue_free()
	await process_frame
	quit()


func _frames(count: int) -> void:
	for i: int in range(count):
		await physics_frame
		await process_frame


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.mvp_qa/guardian_combat/" + label + ".png")
