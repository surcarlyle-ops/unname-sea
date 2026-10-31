extends SceneTree
## 临时：从真实入口 scenes/shore_fishing_mvp.tscn 取景，验证玩家确实站在谷里。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: Node = (load("res://scenes/shore_fishing_mvp.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	await _frames(30)
	# 关掉开场的「点击画面开始」遮罩，取正常游玩时的光。
	world.player.set_controls_active(true)
	await _frames(10)
	var player: CharacterBody3D = world.player
	var shore: Node3D = world.shore_area
	print("player=", player.global_position, " shore=", shore.global_position, " spawn=", shore.player_spawn_point())
	var dir: String = "user://shore_entry"
	DirAccess.make_dir_recursive_absolute(dir)
	await _shot("01_spawn")
	player.rotation.y = 0.45
	await _frames(6)
	await _shot("01b_left")
	player.rotation.y = -0.45
	await _frames(6)
	await _shot("01c_right")
	player.rotation.y = 0.0
	# 走到木台末端，朝水面。
	player.global_position = shore.fishing_spot() + Vector3(0.0, 0.05, 2.4)
	player.rotation.y = 0.0
	player.head.rotation.x = -0.18
	await _frames(12)
	await _shot("02_dock")
	# 从战斗空地朝水面看，确认整条岸线的取景。
	player.global_position = Vector3(300.0, 0.08, 1.0)
	player.rotation.y = 0.0
	player.head.rotation.x = -0.10
	await _frames(12)
	await _shot("03_bank")
	world.queue_free()
	await _frames(2)
	quit(0)


func _shot(shot_name: String) -> void:
	await process_frame
	var image: Image = root.get_texture().get_image()
	var path: String = "user://shore_entry/%s.png" % shot_name
	image.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame
		await process_frame
