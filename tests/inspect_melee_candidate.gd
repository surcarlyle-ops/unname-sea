extends SceneTree
## Inspect imported FBX animation and attachment data independently of the game.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node3D = load("res://assets/characters/fps_arms/Arms.fbx").instantiate() as Node3D
	root.add_child(scene)
	_dump(scene)
	var animations: AnimationPlayer = scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("ANIMATIONS ", animations.get_animation_list())
	for animation_name: String in animations.get_animation_list():
		if "Sword_Idle" in animation_name:
			animations.play(animation_name)
			animations.seek(0.0, true)
	var skeleton: Skeleton3D = _skeleton(scene)
	for bone_name: String in ["Wrist.R", "Index1.R", "Index2.R", "Index3.R", "Middle1.R", "Thumb1.R"]:
		var index: int = skeleton.find_bone(bone_name)
		print("BONE ", bone_name, " rest=", skeleton.get_bone_rest(index), " pose=", skeleton.get_bone_global_pose(index))
	var sword: Node3D = load("res://assets/characters/fps_arms/Steel Shortsword.fbx").instantiate() as Node3D
	root.add_child(sword)
	_dump(sword)
	for node: Node in sword.find_children("*", "MeshInstance3D", true, false):
		print("SWORD_AABB ", (node as MeshInstance3D).get_aabb())
	quit()

func _dump(node: Node) -> void:
	print(node.get_path(), " ", node.get_class(), " ", (node as Node3D).transform if node is Node3D else "")
	for child: Node in node.get_children():
		_dump(child)

func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = _skeleton(child)
		if found != null:
			return found
	return null
