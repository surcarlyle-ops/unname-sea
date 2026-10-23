extends SceneTree
## Geometric checks on the actual equipped Demo, not duplicated animation math.
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var arena: Node3D = load("res://scenes/combat_mvp.tscn").instantiate() as Node3D
	root.add_child(arena)
	current_scene = arena
	var player: Node3D = arena.player
	player.selected_slot = 0
	player._refresh_weapon()
	player.set_controls_active(true)
	player.set_physics_process(false)
	player.grapple.set_physics_process(false)
	var hands: Node3D = player.hands
	hands.update_pose(2.0, 0.0, false, -1.0, 0, true, 1.2)
	hands.update_pose(1.0, 0.0, false, -1.0, 0, true, 1.2)
	var idle: Transform3D = hands.right_arm.transform
	var source_fingers: Dictionary = {}
	var skeleton: Skeleton3D = hands.right_glove.skeleton
	for name: String in hands.right_glove._sword_pose:
		source_fingers[name] = skeleton.get_bone_pose_rotation(skeleton.find_bone(name))
	var result: Array = []
	for swing: int in [0, 1]:
		var min_forward: float = INF
		var min_sleeve: float = INF
		var min_depth: float = INF
		var previous: Quaternion = idle.basis.get_rotation_quaternion()
		var max_step: float = 0.0
		for i: int in range(101):
			var p: float = float(i) / 100.0
			hands.update_pose(0.0, 0.0, false, p, swing, true, 1.2)
			var blade: Vector3 = (hands.right_arm.basis * hands.weapon_root.basis.y).normalized()
			var rotation: Quaternion = hands.right_arm.quaternion
			var wrist: Transform3D = skeleton.get_bone_pose(skeleton.find_bone("Forearm")) * skeleton.get_bone_pose(skeleton.find_bone("Hand"))
			_check(wrist.origin.length() < 0.0001 and wrist.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) < 0.002, "Forearm bend must preserve the hand and sword attachment frame")
			max_step = maxf(max_step, rad_to_deg(previous.angle_to(rotation)))
			previous = rotation
			if p >= 0.22 and p <= 0.56:
				min_forward = minf(min_forward, -blade.z)
				min_sleeve = minf(min_sleeve, hands.right_arm.basis.z.z)
				min_depth = minf(min_depth, -hands.right_arm.position.z)
				_check(blade.z < -0.15, "Active blade must point into the forward hemisphere")
				_check(hands.right_arm.basis.z.z > 0.0, "Cuff must extend back toward the shoulder")
				_check(hands.right_arm.position.z < idle.origin.z - 0.04, "Active wrist must be extended ahead of idle")
			if i == 0 or i == 100:
				_check(hands.right_arm.transform.is_equal_approx(idle), "Swing endpoint must match idle without a snap")
			for name: String in source_fingers:
				_check(skeleton.get_bone_pose_rotation(skeleton.find_bone(name)).angle_to(source_fingers[name]) < 0.002, "Sword fingers must retain handle contact")
		_check(max_step < 20.0, "No discontinuous orientation between sampled frames")
		result.append({"swing": swing, "minimum_forward_component": min_forward, "minimum_sleeve_back_component": min_sleeve, "minimum_wrist_depth_m": min_depth, "max_rotation_per_percent_degrees": max_step})
	print("OUTWARD_SWORD_METRICS ", JSON.stringify(result))
	hands.set_weapon("steam_pistol")
	var forearm: int = skeleton.find_bone("Forearm")
	_check(skeleton.get_bone_pose(forearm).is_equal_approx(skeleton.get_bone_rest(forearm)), "Switching weapon clears the sword-only forearm bend")
	print("OUTWARD_SWORD_TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
