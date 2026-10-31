extends SceneTree

var rig: Skeleton3D
var wrist: int
var canonical: Basis

func _initialize() -> void:
	_run.call_deferred()

func _find(node: Node, kind: String) -> Node:
	if node.is_class(kind):
		return node
	for child: Node in node.get_children():
		var found: Node = _find(child, kind)
		if found != null:
			return found
	return null

func _run() -> void:
	var source: Node3D = load("res://assets/characters/fps_arms/pistol_reference/fps_demo_arms.glb").instantiate()
	root.add_child(source)
	rig = _find(source, "Skeleton3D")
	wrist = rig.find_bone("hand.R")
	var rest_wrist: Transform3D = rig.get_bone_global_rest(wrist)
	var middle: Vector3 = _rest_point("middle2.R") - _rest_point("middle1.R")
	var back: Vector3 = -middle.normalized()
	var lateral: Vector3 = _rest_point("pink1.R") - _rest_point("index1.R")
	lateral = (lateral - back * lateral.dot(back)).normalized()
	var dorsal: Vector3 = back.cross(lateral).normalized()
	canonical = Basis(lateral, dorsal, back).transposed()
	var animator: AnimationPlayer = _find(source, "AnimationPlayer")
	print("SOURCE_PISTOL_ANIMS ",animator.get_animation_list())
	animator.play("pistol_fire")
	animator.seek(0.0, true)
	animator.pause()
	rig.force_update_all_bone_transforms()
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/fps_gloves/rig_layout.json"))
	var names: Dictionary = {"Thumb":"thumb", "Index":"index", "Middle":"middle", "Ring":"ring", "Pinky":"pink"}
	var poses: Dictionary = {}
	var joint_points: Dictionary = {}
	for digit: String in names:
		var first: Quaternion = _delta(str(names[digit]) + "1.R")
		var second: Quaternion = _delta(str(names[digit]) + "2.R")
		var distal: Quaternion = first.inverse() * second
		var local_rotations: Array[Quaternion] = [first, Quaternion.IDENTITY.slerp(distal, 0.62), Quaternion.IDENTITY.slerp(distal, 0.38)]
		var rest_points: Array = layout.fingers[digit]
		var point: Vector3 = _vector(rest_points[0])
		var endpoints: Array = [_array(point)]
		var rotation: Quaternion = Quaternion.IDENTITY
		for segment: int in range(3):
			var q: Quaternion = local_rotations[segment]
			poses[digit + str(segment + 1)] = [q.x, q.y, q.z, q.w]
			rotation = rotation * q
			point += rotation * (_vector(rest_points[segment + 1]) - _vector(rest_points[segment]))
			endpoints.append(_array(point))
		joint_points[digit] = endpoints
	# Preserve the donor's extended thumb, correcting its contact for this wider
	# target palm and the M1911 grip rather than letting it float beside the gun.
	var thumb: Array[Vector3] = []
	for a: Array in joint_points.Thumb:
		thumb.append(_vector(a))
	var thumb_rest: Array = layout.fingers.Thumb
	var lengths: Array[float] = []
	for i: int in range(3):
		lengths.append((_vector(thumb_rest[i+1])-_vector(thumb_rest[i])).length())
	var thumb_base: Vector3 = thumb[0]
	for iteration: int in range(20):
		thumb[3] = Vector3(-0.037,-0.026,-0.145)
		for i: int in range(2,-1,-1):
			thumb[i] = thumb[i+1] + (thumb[i]-thumb[i+1]).normalized()*lengths[i]
		thumb[0] = thumb_base
		for i: int in range(3):
			thumb[i+1] = thumb[i] + (thumb[i+1]-thumb[i]).normalized()*lengths[i]
	var parent_rotation: Quaternion = Quaternion.IDENTITY
	joint_points.Thumb = []
	for point: Vector3 in thumb:
		joint_points.Thumb.append(_array(point))
	for i: int in range(3):
		var rest_direction: Vector3 = (_vector(thumb_rest[i+1])-_vector(thumb_rest[i])).normalized()
		var rotation: Quaternion = Quaternion(rest_direction,(thumb[i+1]-thumb[i]).normalized())
		var q: Quaternion = parent_rotation.inverse()*rotation
		poses["Thumb"+str(i+1)] = [q.x,q.y,q.z,q.w]
		parent_rotation = rotation
	var world_wrist: Transform3D = rig.global_transform * rig.get_bone_global_pose(wrist)
	var hand_basis: Basis = world_wrist.basis.orthonormalized() * canonical.inverse()
	print("CANONICAL ",canonical," HAND_WORLD ",hand_basis)
	var result: Dictionary = {"source":"bukkbeek/GodotFPS-Template / fps_demo_arms.glb / pistol_fire t=0", "method":"Palm-frame bone delta transfer; distribute donor's two phalanges over target three without copying Euler angles", "right":poses, "posed_joint_points":joint_points, "hand_world_basis":[_array(hand_basis.x),_array(hand_basis.y),_array(hand_basis.z)]}
	var target_path: String = "res://assets/characters/fps_gloves/pistol_grip_pose.json"
	if FileAccess.file_exists(target_path):
		var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(target_path))
		for key: String in ["hand_position", "weapons"]:
			if previous.has(key): result[key] = previous[key]
	var file: FileAccess = FileAccess.open(target_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	print("POSE_EXPORTED ",joint_points)
	source.queue_free()
	quit()

func _rest_point(name: String) -> Vector3:
	return rig.get_bone_global_rest(wrist).affine_inverse() * rig.get_bone_global_rest(rig.find_bone(name)).origin

func _delta(name: String) -> Quaternion:
	var bone: int = rig.find_bone(name)
	var rest: Basis = (rig.get_bone_global_rest(wrist).affine_inverse() * rig.get_bone_global_rest(bone)).basis.orthonormalized()
	var posed: Basis = (rig.get_bone_global_pose(wrist).affine_inverse() * rig.get_bone_global_pose(bone)).basis.orthonormalized()
	return (canonical * posed * rest.inverse() * canonical.inverse()).get_rotation_quaternion().normalized()

func _vector(a: Array) -> Vector3:
	return Vector3(a[0],a[1],a[2])

func _array(v: Vector3) -> Array:
	return [v.x,v.y,v.z]
