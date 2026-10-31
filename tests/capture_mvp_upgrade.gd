extends SceneTree
## Capture real demo hands before and after the MVP presentation upgrade.

var arena: Node3D
var output_dir: String = "res://.mvp_qa/mvp_upgrade"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	arena = load("res://scenes/combat_mvp.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await _frames(6)
	var player: CharacterBody3D = arena.player
	player.set_controls_active(true)
	player.set_physics_process(false)
	if is_instance_valid(arena.guardian):
		arena.guardian.set_physics_process(false)
	player.position = Vector3(0, 0.1, 16)
	player.rotation = Vector3.ZERO
	for item: String in ["", "steam_pistol", "tide_blade"]:
		player.hands.set_weapon(item)
		player.hands._pistol_spawn = 0
		player.hands._spawn_time = 0
		for i: int in range(30):
			player.hands.update_pose(1.0 / 60.0, 0, false, -1, 0, item != "", 2.0)
		await _capture("before_" + ("empty" if item == "" else item))
		if item == "":
			player.hands.right_arm.position = Vector3(0.22, -0.23, -0.52)
			player.hands.left_arm.position = Vector3(-0.22, -0.23, -0.52)
			player.hands.right_arm.rotation = Vector3(0.85, -0.15, -0.15)
			player.hands.left_arm.rotation = Vector3(0.85, 0.15, 0.15)
			await _capture("before_fingers_curled")
			player.hands.right_glove.set_pose_immediate(0)
			player.hands.left_glove.set_pose_immediate(0)
			await _capture("before_rest")
	arena.queue_free()
	await process_frame
	quit()

func _frames(count: int) -> void:
	for i: int in range(count):
		await process_frame

func _capture(label: String) -> void:
	await _frames(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir + "/" + label + ".png")
