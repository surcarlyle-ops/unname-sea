extends Node3D
## The supplied glove, with a custom finger rig and independently replaceable poses.

const RIGHT_MODEL: PackedScene = preload("res://assets/characters/fps_gloves/glove_right.glb")
const LEFT_MODEL: PackedScene = preload("res://assets/characters/fps_gloves/glove_left.glb")

var left_hand: bool = false
var skeleton: Skeleton3D
var grip: float = 0.0
var _fingers: Array[Dictionary] = []
## 逐指四元数覆盖：非空时与基础握姿按权重混合，避免出招收招瞬间跳变。
var _pose_override: Dictionary = {}
var _override_weight: float = 0.0
var authored_grip: bool = true
var _sword_pose: Dictionary = {}


func _ready() -> void:
	var model: Node3D = (LEFT_MODEL if left_hand else RIGHT_MODEL).instantiate() as Node3D
	add_child(model)
	_disable_shadows(model)
	skeleton = _find_skeleton(model)
	if skeleton == null:
		push_error("Glove model is missing its hand skeleton")
		return
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/fps_gloves/rig_layout.json")) as Dictionary
	var poses: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/fps_gloves/sword_grip_pose.json")) as Dictionary
	_sword_pose = poses.get("right", {})
	for finger_name: String in layout.fingers:
		var locations: Array = layout.fingers[finger_name]
		var start: Vector3 = _point(locations[0])
		var finish: Vector3 = _point(locations[3])
		var axis: Vector3 = (finish - start).normalized().cross(Vector3.DOWN).normalized()
		for segment: int in range(3):
			var index: int = skeleton.find_bone(finger_name + str(segment + 1))
			var angle: float = [20.0, 30.0, 15.0][segment] if finger_name == "Thumb" else [70.0, 95.0, 55.0][segment]
			_fingers.append({"bone": index, "name": finger_name + str(segment + 1), "axis": axis, "angle": deg_to_rad(angle), "opposition": finger_name == "Thumb" and segment == 0})
	set_pose_immediate(0.15)


func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_disable_shadows(child)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _point(values: Array) -> Vector3:
	return Vector3(float(values[0]) * (-1.0 if left_hand else 1.0), float(values[1]), float(values[2]))


func set_grip(value: float, delta: float) -> void:
	set_pose_immediate(lerpf(grip, clampf(value, 0.0, 1.0), 1.0 - exp(-delta * 16.0)))


## 挥砍期间把迁移好的逐指姿势按权重混合到当前握姿上。
func apply_pose_override(poses: Dictionary, weight: float) -> void:
	_pose_override = poses
	_override_weight = clampf(weight, 0.0, 1.0)


func clear_pose_override() -> void:
	_pose_override = {}
	_override_weight = 0.0


func set_pose_immediate(value: float) -> void:
	grip = clampf(value, 0.0, 1.0)
	if skeleton == null:
		return
	for finger: Dictionary in _fingers:
		var rotation: Quaternion = Quaternion(finger.axis as Vector3, float(finger.angle) * grip)
		if bool(finger.opposition):
			rotation = Quaternion(Vector3.UP, grip * (1.0 if left_hand else -1.0)) * rotation
		if authored_grip and not left_hand and _sword_pose.has(finger.name):
			var values: Array = _sword_pose[finger.name] as Array
			var target: Quaternion = Quaternion(float(values[0]), float(values[1]), float(values[2]), float(values[3])).normalized()
			rotation = rotation.slerp(target, smoothstep(0.40, 0.86, grip))
		if _override_weight > 0.001 and _pose_override.has(finger.name):
			var raw: Array = _pose_override[finger.name] as Array
			var migrated: Quaternion = Quaternion(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3])).normalized()
			rotation = rotation.slerp(migrated, _override_weight)
		skeleton.set_bone_pose_rotation(int(finger.bone), rotation)
