extends SceneTree
## 从 Arms.fbx 提取 Sword_Slash1/2 的手腕轨迹与手指姿势。
## 在 headless 下运行：godot --headless --script res://tools/asset_pipeline/extract_slash_tracks.gd
## 注意：headless 下 Skeleton3D.force_update_all_bone_transforms() 不刷新 global pose，
## 因此这里手动按 rest * pose 逐级相乘计算骨骼全局变换。

const ARMS_PATH: String = "res://assets/characters/fps_arms/Arms.fbx"
const LAYOUT_PATH: String = "res://assets/characters/fps_gloves/rig_layout.json"
const OUT_PATH: String = "res://assets/characters/fps_gloves/sword_slash_tracks.json"
const FPS: float = 60.0
const SLASHES: Array[String] = [
	"CharacterArmature|Sword_Slash1",
	"CharacterArmature|Sword_Slash2",
]
const FINGERS: Array[String] = ["Index", "Middle", "Ring", "Pinky", "Thumb"]

var _cache: Dictionary = {}


func _initialize() -> void:
	var packed: PackedScene = load(ARMS_PATH) as PackedScene
	if packed == null:
		print("LOAD FAIL")
		quit()
		return
	var model: Node3D = packed.instantiate() as Node3D
	root.add_child(model)
	var skeleton: Skeleton3D = _find_skeleton(model)
	var player: AnimationPlayer = _find_anim(model)
	if skeleton == null or player == null:
		print("MISSING SKELETON OR ANIM")
		quit()
		return

	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH)) as Dictionary
	var result: Dictionary = {"fps": FPS, "source": "BigAndCrispy/Unity-First-Person-Melee / Arms.fbx"}

	# 基准帧：Sword_Idle 第 1 帧对应项目里的持械静态姿态，其余动作按它取增量。
	var idle_name: String = "CharacterArmature|Sword_Idle"
	if player.has_animation(idle_name):
		_apply_anim_at(skeleton, player.get_animation(idle_name), 0.0)
		result["base"] = _sample(skeleton, layout)
		print("BASE sampled")

	for anim_name: String in SLASHES:
		if not player.has_animation(anim_name):
			print("SKIP ", anim_name)
			continue
		var anim: Animation = player.get_animation(anim_name)
		var duration: float = anim.length
		var frame_count: int = int(ceil(duration * FPS))
		var frames: Array = []
		for i: int in range(frame_count + 1):
			var t: float = minf(float(i) / FPS, duration)
			_apply_anim_at(skeleton, anim, t)
			var sample: Dictionary = _sample(skeleton, layout)
			sample["t"] = snappedf(t, 0.0001)
			frames.append(sample)
		var key: String = anim_name.get_slice("|", 1)
		result[key] = {"duration": duration, "frames": frames}
		print("SAMPLED ", key, " frames=", frames.size())

	var file: FileAccess = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		print("WRITE FAIL")
	else:
		file.store_string(JSON.stringify(result, "  "))
		file.close()
		print("WROTE ", OUT_PATH)
	quit()


## AnimationPlayer 在 headless 下 seek 不会立刻生效，改为直接按轨道插值写入骨骼。
func _apply_anim_at(skeleton: Skeleton3D, anim: Animation, time: float) -> void:
	for i: int in range(skeleton.get_bone_count()):
		var rest: Transform3D = skeleton.get_bone_rest(i)
		skeleton.set_bone_pose_position(i, rest.origin)
		skeleton.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(i, rest.basis.get_scale())
	for track: int in range(anim.get_track_count()):
		var path: NodePath = anim.track_get_path(track)
		var bone_name: String = str(path.get_concatenated_subnames())
		var bone_index: int = skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		match anim.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(bone_index, anim.position_track_interpolate(track, time))
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bone_index, anim.rotation_track_interpolate(track, time))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(bone_index, anim.scale_track_interpolate(track, time))
	_cache.clear()


## 手动计算骨骼全局变换：逐级 rest * pose 相乘。
func _bone_global(skeleton: Skeleton3D, bone_index: int) -> Transform3D:
	if _cache.has(bone_index):
		return _cache[bone_index]
	var chain: Array[int] = []
	var cursor: int = bone_index
	while cursor >= 0:
		chain.push_front(cursor)
		cursor = skeleton.get_bone_parent(cursor)
	var result: Transform3D = Transform3D.IDENTITY
	for index: int in chain:
		# bone_pose 已是完整局部变换（含 rest），再乘 rest 会重复叠加。
		var local: Transform3D = Transform3D(
			Basis(skeleton.get_bone_pose_rotation(index)),
			skeleton.get_bone_pose_position(index)
		)
		local.basis = local.basis.scaled(skeleton.get_bone_pose_scale(index))
		result = result * local
	_cache[bone_index] = result
	return result


func _sample(skeleton: Skeleton3D, layout: Dictionary) -> Dictionary:
	var wrist_global: Transform3D = _bone_global(skeleton, skeleton.find_bone("Wrist.R"))
	var chest_global: Transform3D = _bone_global(skeleton, skeleton.find_bone("Chest"))
	var wrist_local: Transform3D = chest_global.affine_inverse() * wrist_global
	var quaternion: Quaternion = wrist_local.basis.get_rotation_quaternion()
	return {
		"wrist_pos": [wrist_local.origin.x, wrist_local.origin.y, wrist_local.origin.z],
		"wrist_quat": [quaternion.x, quaternion.y, quaternion.z, quaternion.w],
		"fingers": _finger_poses(skeleton, layout),
	}


## 用解剖掌面坐标把源指节方向迁移到手套骨架，返回 15 根指骨的局部四元数。
func _finger_poses(skeleton: Skeleton3D, layout: Dictionary) -> Dictionary:
	var wrist_global: Transform3D = _bone_global(skeleton, skeleton.find_bone("Wrist.R"))

	var forward: Vector3 = (_point(skeleton, wrist_global, "Middle3.R") - _point(skeleton, wrist_global, "Middle2.R")).normalized()
	var lateral: Vector3 = _point(skeleton, wrist_global, "Pinky2.R") - _point(skeleton, wrist_global, "Index2.R")
	lateral = (lateral - forward * lateral.dot(forward)).normalized()
	var back: Vector3 = -forward
	var dorsal: Vector3 = back.cross(lateral).normalized()
	var canonical: Basis = Basis(lateral, dorsal, back)

	var poses: Dictionary = {}
	for digit: String in FINGERS:
		var rest: Array = layout.fingers[digit]
		var parent_rotation: Quaternion = Quaternion.IDENTITY
		for segment: int in range(3):
			var source_segment: int = segment + (1 if digit == "Thumb" else 2)
			var start_name: String = "%s%d.R" % [digit, source_segment]
			var end_name: String = ""
			if source_segment < (3 if digit == "Thumb" else 4):
				end_name = "%s%d.R" % [digit, source_segment + 1]
			else:
				end_name = "%s%d.R_end" % [digit, source_segment]
			var authored: Vector3 = (canonical * (_point(skeleton, wrist_global, end_name) - _point(skeleton, wrist_global, start_name))).normalized()
			var from_point: Array = rest[segment]
			var to_point: Array = rest[segment + 1]
			var rest_direction: Vector3 = Vector3(
				float(to_point[0]) - float(from_point[0]),
				float(to_point[1]) - float(from_point[1]),
				float(to_point[2]) - float(from_point[2])
			).normalized()
			var global_rotation: Quaternion = Quaternion(rest_direction, authored)
			var local_rotation: Quaternion = parent_rotation.inverse() * global_rotation
			poses["%s%d" % [digit, segment + 1]] = [local_rotation.x, local_rotation.y, local_rotation.z, local_rotation.w]
			parent_rotation = global_rotation
	return poses


func _point(skeleton: Skeleton3D, wrist_global: Transform3D, bone_name: String) -> Vector3:
	var index: int = skeleton.find_bone(bone_name)
	if index < 0:
		return Vector3.ZERO
	return wrist_global.affine_inverse() * _bone_global(skeleton, index).origin


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_anim(child)
		if found != null:
			return found
	return null
