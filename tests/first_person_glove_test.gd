extends SceneTree
## Validate the imported skin and real first-person equip/locomotion integration.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var hands: Node3D = (load("res://scripts/mvp/first_person_hands.gd") as Script).new() as Node3D
	root.add_child(hands)
	for glove: Node3D in [hands.right_glove, hands.left_glove]:
		var skeleton: Skeleton3D = glove.skeleton
		var side: String = "Left" if glove.left_hand else "Right"
		_check(skeleton != null and skeleton.get_bone_count() == 22, side + " has wrist and five articulated fingers")
		var meshes: Array[MeshInstance3D] = []
		_find_meshes(glove, meshes)
		_check(meshes.size() == 1 and meshes[0].skin != null, side + " imports as a skinned mesh")
		var mesh: MeshInstance3D = meshes[0]
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var valid_weights: bool = true
		for vertex: int in range(weights.size() / 4):
			var sum: float = 0.0
			for influence: int in range(4):
				var weight: float = weights[vertex * 4 + influence]
				valid_weights = valid_weights and is_finite(weight) and weight >= 0.0
				sum += weight
			valid_weights = valid_weights and absf(sum - 1.0) < 0.0001
		_check(valid_weights and not weights.is_empty(), side + " weights are finite and normalized")
		var material: StandardMaterial3D = mesh.mesh.surface_get_material(0) as StandardMaterial3D
		_check(material != null and material.albedo_texture != null, side + " retains its source texture")
		_check(mesh.global_basis.determinant() > 0.0, side + " mirror is baked without negative scale")
		_check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, side + " does not cast detached viewmodel shadows")
		var finger: int = skeleton.find_bone("Index2")
		glove.set_pose_immediate(0.0)
		var rest: Quaternion = skeleton.get_bone_pose_rotation(finger)
		glove.set_pose_immediate(0.86)
		_check(rest.angle_to(skeleton.get_bone_pose_rotation(finger)) > 1.0, side + " grip rotates a real finger joint")
		_check(skeleton.get_bone_pose_rotation(skeleton.find_bone("Forearm")).is_equal_approx(Quaternion.IDENTITY), side + " grip keeps the sleeve stable")
	hands.update_pose(1.0, 0.0, false, -1.0, 0, true, 1.2)
	_check(hands.weapon_root.visible and hands.right_glove.grip > 0.8, "Equipping closes the weapon hand around its socket")
	hands.update_pose(1.0, 0.0, false, -1.0, 0, false, 1.2)
	_check(not hands.weapon_root.visible and hands.right_arm.visible and hands.left_arm.visible and hands.right_glove.grip < 0.35 and hands.right_arm.position.y < -0.5, "Empty slot rests both relaxed arms below the view")
	hands.update_pose(1.0, 8.2, true, -1.0, 0, false, 1.2, {"sliding": true})
	_check(hands.right_arm.position.y < -0.3, "Slide lowers the integrated hand rig")
	hands.update_pose(1.0, 0.0, false, -1.0, 0, false, 1.2, {"mantling": true})
	_check(hands.left_glove.grip < 0.05 and hands.left_arm.position.y > -0.25, "Mantle opens and reaches the left hand")
	hands.reset_motion()
	_check(is_equal_approx(hands.right_glove.grip, 0.28) and is_equal_approx(hands.left_glove.grip, 0.30), "Retry clears the previous finger pose")
	var skeleton: Skeleton3D = hands.right_glove.skeleton
	var toward_index: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone("Index1")).origin - skeleton.get_bone_global_rest(skeleton.find_bone("Pinky1")).origin
	_check(hands.weapon_root.basis.y.normalized().dot(toward_index.normalized()) > 0.95, "Blade exits on the thumb/index side, not the little-finger side")
	hands.set_weapon("tide_blade")
	hands.update_pose(2.0, 0.0, false, -1.0, 0, true, 1.2)
	_check(hands.weapon_root.global_basis.y.normalized().dot(Vector3.UP) > 0.9, "Side grip leaves the real sword upright")
	var before: Quaternion
	for boundary: float in [0.23, 0.60]:
		hands.update_pose(1.0, 0.0, false, boundary - 0.0001, 0, true, 1.2)
		before = hands.right_arm.quaternion
		hands.update_pose(1.0, 0.0, false, boundary + 0.0001, 0, true, 1.2)
		_check(before.angle_to(hands.right_arm.quaternion) < 0.01, "Swing rotation is continuous across phase " + str(boundary))
	hands.set_weapon("")
	_check(hands._spawn_time == 0.0 and hands._tide_pivot.rotation.is_zero_approx(), "Holstering cancels the toss without leaving a floating sword")
	hands.queue_free()
	await process_frame
	var arena: Node3D = (load("res://scenes/combat_mvp.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	var player: CharacterBody3D = arena.player
	_check(not player.equipped_blade() and player.energy_max() == 0, "Actual arena starts empty-handed")
	player.set_controls_active(true)
	var key: InputEventKey = InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_1
	player._unhandled_input(key)
	_check(player.equipped_blade() and player.hands._weapon_id == "tide_blade", "Number one equips the imported weapon through real input")
	key.physical_keycode = KEY_2
	player._unhandled_input(key)
	_check(not player.equipped_blade() and player.hands._spawn_time == 0.0, "Number two returns to empty hands and cancels the equip animation")
	arena.queue_free()
	await process_frame
	print("GLOVE_TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _find_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_find_meshes(child, meshes)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
