extends Node3D
## Imported firearm only. Temporary solid materials until the texture pack arrives.

const MODEL: PackedScene = preload("res://assets/weapons/m1911/m1911.fbx")

func _ready() -> void:
	var model: Node3D = MODEL.instantiate()
	model.scale = Vector3.ONE * 1.2
	model.position = -Vector3(0.025, -0.037, 0.0) * 1.2
	add_child(model)
	_style(model)

func _style(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface: int in range(node.mesh.get_surface_count()):
			var original: Material = node.get_active_material(surface)
			var grip: bool = original != null and "Grip" in original.resource_name
			var material: StandardMaterial3D = StandardMaterial3D.new()
			material.albedo_color = Color("50392a") if grip else Color("555d65")
			material.metallic = 0.0 if grip else 0.8
			material.roughness = 0.85 if grip else 0.42
			node.set_surface_override_material(surface, material)
	for child: Node in node.get_children():
		_style(child)
