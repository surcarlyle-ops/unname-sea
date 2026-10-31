extends AnimatableBody3D
## A fitted solid/hurt region follows an existing rigid guardian bone.

var guardian: CharacterBody3D
var bone_name: StringName = &"stone_hammer"
var _bone: int = -1
var _center: Vector3 = Vector3.ZERO
var solid_shape: ConvexPolygonShape3D


func _ready() -> void:
	top_level = true
	sync_to_physics = false
	process_physics_priority = -9
	collision_layer = 2
	collision_mask = 4
	_bone = guardian.skeleton.find_bone(bone_name)
	var points: PackedVector3Array = PackedVector3Array()
	var model_scale: float = guardian.MODEL_SCALE * guardian.size_multiplier
	# Use the imported skin's inverse bind matrices, not assumed Blender/Godot axes.
	for mesh_node: MeshInstance3D in guardian._meshes:
		if mesh_node.skin == null or mesh_node.mesh == null:
			continue
		var bind: int = -1
		for i: int in range(mesh_node.skin.get_bind_count()):
			if mesh_node.skin.get_bind_name(i) == bone_name or mesh_node.skin.get_bind_bone(i) == _bone:
				bind = i
				break
		if bind < 0:
			continue
		for surface: int in range(mesh_node.mesh.get_surface_count()):
			var arrays: Array = mesh_node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or bones.is_empty():
				continue
			var stride: int = bones.size() / vertices.size()
			for vertex: int in range(vertices.size()):
				for slot: int in range(stride):
					var offset: int = vertex * stride + slot
					if bones[offset] == bind and weights[offset] > 0.5:
						points.append((mesh_node.skin.get_bind_pose(bind) * vertices[vertex]) * model_scale)
						break
	if points.size() < 4:
		push_error("Guardian region has no valid skinned collision points: " + str(bone_name))
		return
	for point: Vector3 in points:
		_center += point
	_center /= float(points.size())
	solid_shape = ConvexPolygonShape3D.new()
	solid_shape.points = points
	solid_shape.margin = 0.035
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = solid_shape
	add_child(collision)
	add_collision_exception_with(guardian)
	guardian.add_collision_exception_with(self)
	sync_pose()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(guardian) or guardian.dead:
		collision_layer = 0
		return
	sync_pose()


func sync_pose() -> void:
	if _bone < 0:
		return
	var pose: Transform3D = guardian.skeleton.global_transform * guardian.skeleton.get_bone_global_pose(_bone)
	# Shape points are already scaled; physics bodies keep an orthonormal basis.
	global_transform = Transform3D(pose.basis.orthonormalized(), pose.origin)


func world_center() -> Vector3:
	return global_transform * _center


func apply_damage(amount: int, push: Vector3) -> void:
	if is_instance_valid(guardian):
		guardian.apply_part_damage(amount, push, str(bone_name))
