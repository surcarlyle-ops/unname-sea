extends RefCounted
## Lightweight poses on the existing rigid rig; no new model or external DCC.

var boss: CharacterBody3D
var rig: Skeleton3D
var _pose: Array[Transform3D] = []
var _global: Dictionary = {}
var walk_phase: float = 0.0

func setup(owner_boss: CharacterBody3D) -> void:
	boss = owner_boss
	rig = boss.skeleton
	for i: int in range(rig.get_bone_count()):
		_pose.append(rig.get_bone_pose(i))
		_global[rig.get_bone_name(i)] = rig.get_bone_global_pose(i)

func reset_pose() -> void:
	for i: int in range(_pose.size()):
		rig.set_bone_pose(i, _pose[i])
	boss.model.position = Vector3.ZERO

func walk(delta: float, speed: float) -> void:
	reset_pose()
	var weight: float = clampf(speed / maxf(float(boss.tuning.walk_speed), 0.01), 0.0, 1.0)
	walk_phase = fmod(walk_phase + delta * speed * 3.8, TAU)
	for side: String in ["heavy", "light"]:
		var sign_value: float = 1.0 if side == "heavy" else -1.0
		var stride: float = sin(walk_phase) * sign_value
		var foot: Vector3 = (_global["foot_" + side] as Transform3D).origin
		foot.z += stride * 0.055 * weight
		foot.y += maxf(0, cos(walk_phase) * sign_value) * 0.028 * weight
		_two_link("thigh_" + side, "shin_" + side, (_global["foot_" + side] as Transform3D).origin, foot, Vector3.FORWARD)
		_set_global_basis("foot_" + side, (_global["foot_" + side] as Transform3D).basis)
	_rotate_global("chest", Vector3.UP, sin(walk_phase) * 0.035 * weight)
	_rotate_global("upper_arm_heavy", Vector3.RIGHT, sin(walk_phase) * 0.075 * weight)
	_rotate_global("upper_arm_light", Vector3.RIGHT, -sin(walk_phase) * 0.16 * weight)

func attack(kind: String, time: float, windup: float, active: float, recovery: float) -> void:
	reset_pose()
	var prep: float = smoothstep(0, windup, time)
	var strike: float = smoothstep(windup, windup + active, time)
	var recover: float = smoothstep(windup + active, windup + active + recovery, time)
	var heavy: Vector3
	var light: Vector3
	if kind == "slam":
		# Lower the pelvis while keeping both feet planted; the short stone arms
		# cannot reach the ground from a fully upright pose.
		var pelvis: int = rig.find_bone("pelvis")
		rig.set_bone_pose_position(pelvis, _pose[pelvis].origin + Vector3.DOWN * 0.10 * prep * strike * (1.0 - recover))
		for side: String in ["heavy", "light"]:
			var foot: Vector3 = (_global["foot_" + side] as Transform3D).origin
			_two_link("thigh_" + side, "shin_" + side, foot, foot, Vector3.FORWARD)
			_set_global_basis("foot_" + side, (_global["foot_" + side] as Transform3D).basis)
		heavy = Vector3(-0.34, 0.70, 0.03).lerp(Vector3(-0.18, 0.22, 0.20), strike)
		light = Vector3(0.27, 0.67, 0.05).lerp(Vector3(0.20, 0.22, 0.20), strike)
		_rotate_global("chest", Vector3.RIGHT, lerpf(-0.12, 0.16, strike) * prep * (1.0 - recover))
	else:
		heavy = Vector3(-0.43, 0.42, 0.02).lerp(Vector3(0.23, 0.29, 0.35), strike)
		light = Vector3(0.27, 0.40, 0.12)
		_rotate_global("chest", Vector3.UP, lerpf(-0.20, 0.23, strike) * prep * (1.0 - recover))
	var weight: float = prep * (1.0 - recover)
	var hammer: Vector3 = _hammer_center()
	_two_link("upper_arm_heavy", "stone_hammer", hammer, hammer.lerp(heavy, weight), Vector3.LEFT)
	var light_tip: Vector3 = (_global.forearm_light as Transform3D) * Vector3(0, 0.16, 0)
	_two_link("upper_arm_light", "forearm_light", light_tip, light_tip.lerp(light, weight), Vector3.RIGHT)

func _hammer_center() -> Vector3:
	var initial: Transform3D = _global.stone_hammer
	if is_instance_valid(boss.solid_fist):
		return initial * (boss.solid_fist._center / (boss.MODEL_SCALE * boss.size_multiplier))
	return initial * Vector3(0, 0.18, 0)

func _two_link(upper_name: String, lower_name: String, initial_tip: Vector3, target: Vector3, pole: Vector3) -> void:
	var upper: int = rig.find_bone(upper_name)
	var lower: int = rig.find_bone(lower_name)
	var start: Vector3 = rig.get_bone_global_pose(upper).origin
	var initial_upper: Transform3D = _global[upper_name]
	var initial_lower: Transform3D = _global[lower_name]
	var length_a: float = initial_upper.origin.distance_to(initial_lower.origin)
	var length_b: float = initial_lower.origin.distance_to(initial_tip)
	var offset: Vector3 = target - start
	var distance: float = clampf(offset.length(), absf(length_a - length_b) + 0.001, length_a + length_b - 0.001)
	var direction: Vector3 = offset.normalized()
	var bend: Vector3 = (pole - direction * pole.dot(direction)).normalized()
	if bend.length_squared() < 0.1:
		bend = direction.cross(Vector3.UP).normalized()
	var along: float = (length_a * length_a - length_b * length_b + distance * distance) / (2 * distance)
	var elbow: Vector3 = start + direction * along + bend * sqrt(maxf(0, length_a * length_a - along * along))
	var upper_axis: Vector3 = (initial_lower.origin - initial_upper.origin).normalized()
	var upper_basis: Basis = Basis(Quaternion(upper_axis, (elbow - start).normalized())) * initial_upper.basis
	_set_global_basis(upper_name, upper_basis)
	var lower_axis: Vector3 = (initial_tip - initial_lower.origin).normalized()
	var lower_basis: Basis = Basis(Quaternion(lower_axis, (direction * distance + start - elbow).normalized())) * initial_lower.basis
	_set_global_basis(lower_name, lower_basis)

func _rotate_global(name: String, axis: Vector3, angle: float) -> void:
	_set_global_basis(name, Basis(axis, angle) * (_global[name] as Transform3D).basis)

func _set_global_basis(name: String, basis: Basis) -> void:
	var index: int = rig.find_bone(name)
	var parent: int = rig.get_bone_parent(index)
	var local_basis: Basis = basis
	if parent >= 0:
		local_basis = rig.get_bone_global_pose(parent).basis.inverse() * basis
	rig.set_bone_pose_rotation(index, local_basis.orthonormalized().get_rotation_quaternion())
