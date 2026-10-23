extends SceneTree
## Exercise the authored glove pose through the actual demo equip path.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arena: Node3D = load("res://scenes/combat_mvp.tscn").instantiate() as Node3D
	root.add_child(arena)
	current_scene = arena
	var player: CharacterBody3D = arena.player
	player.selected_slot = 0
	player._refresh_weapon()
	player.hands.update_pose(2.0, 0.0, false, -1.0, 0, true, 1.2)
	player.hands.update_pose(0.5, 0.0, false, -1.0, 0, true, 1.2)
	var glove: Node3D = player.hands.right_glove
	_check(glove.authored_grip, "Demo sword selects the authored pose on the user's glove")
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/fps_gloves/sword_grip_pose.json")) as Dictionary
	for name: String in library.right:
		var values: Array = library.right[name]
		var expected: Quaternion = Quaternion(float(values[0]), float(values[1]), float(values[2]), float(values[3])).normalized()
		var actual: Quaternion = glove.skeleton.get_bone_pose_rotation(glove.skeleton.find_bone(name))
		_check(actual.angle_to(expected) < 0.002, name + " uses the retargeted bone pose")
	_check(glove.skeleton.get_bone_pose_rotation(glove.skeleton.find_bone("Hand")).is_equal_approx(Quaternion.IDENTITY), "Grip leaves wrist and sleeve rest transforms intact")
	_check(player.hands.weapon_root.visible, "The actual imported demo sword is visible")
	player.selected_slot = 1
	player._refresh_weapon()
	player.hands.update_pose(2.0, 0.0, false, -1.0, 0, false, 1.2)
	_check(not player.hands.weapon_root.visible and glove.grip < 0.35, "Empty slot releases the sword pose")
	player.selected_slot = 2
	player._refresh_weapon()
	_check(not glove.authored_grip, "Pistol retains its separate grip path")
	_check(player.hands._pistol_base_pos.is_equal_approx(Vector3(0, -0.034, -0.132) + player.hands.PISTOL_OFFSET), "Sword correction does not shift the independently tuned pistol anchor")
	arena.queue_free()
	await process_frame
	print("AUTHORED_GLOVE_GRIP_TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("FAIL: " + message)
