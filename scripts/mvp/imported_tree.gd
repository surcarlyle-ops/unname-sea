extends Node3D
## Runtime material repair for the user's FBX tree; the source stays unchanged.

const MODEL: PackedScene = preload("res://assets/environments/highpoly_tree/tree.fbx")
const LEAF: Texture2D = preload("res://assets/environments/highpoly_tree/T_HP_Tree_Leaf.PNG")
const BARK: Texture2D = preload("res://assets/environments/highpoly_tree/T_HP_Tree_Trunk.PNG")
const NORMAL: Texture2D = preload("res://assets/environments/highpoly_tree/T_HP_Tree_Trunk_normal.PNG")

func _ready() -> void:
	var model: Node3D = MODEL.instantiate()
	add_child(model)
	_repair(model)

func _repair(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface: int in range(node.mesh.get_surface_count()):
			var source: Material = node.get_active_material(surface)
			var leaf: bool = source != null and "Leaf" in source.resource_name
			var material: StandardMaterial3D = StandardMaterial3D.new()
			material.albedo_texture = LEAF if leaf else BARK
			material.roughness = 0.9
			if leaf:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				material.alpha_scissor_threshold = 0.45
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
			else:
				material.normal_enabled = true
				material.normal_texture = NORMAL
			node.set_surface_override_material(surface, material)
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	for child: Node in node.get_children():
		_repair(child)
